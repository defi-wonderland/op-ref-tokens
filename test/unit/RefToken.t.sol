// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {Unauthorized} from '@interop-lib/src/libraries/errors/CommonErrors.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';
import {RefToken} from 'src/contracts/RefToken.sol';
import {Helpers} from 'test/utils/Helpers.t.sol';

contract RefTokenUnit is Helpers {
  error Permit2AllowanceIsFixedAtInfinity();

  RefToken public refToken;
  IRefTokenBridge public refTokenBridge;
  IRefToken.RefTokenMetadata public refTokenMetadata;

  function setUp() public {
    refTokenBridge = IRefTokenBridge(makeAddr('RefTokenBridge'));
    refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: nativeAsset,
      nativeAssetChainId: nativeAssetChainId,
      nativeAssetName: nativeAssetName,
      nativeAssetSymbol: nativeAssetSymbol,
      nativeAssetDecimals: nativeAssetDecimals
    });
    refToken = new RefToken(address(refTokenBridge), refTokenMetadata);
  }

  function test_ConstructorWhenDeployed(
    IRefTokenBridge _refTokenBridge,
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) external {
    // It constructs the RefToken contract
    RefToken newRefToken = new RefToken(address(_refTokenBridge), _refTokenMetadata);

    assertEq(address(newRefToken.REF_TOKEN_BRIDGE()), address(_refTokenBridge));
    assertEq(newRefToken.NATIVE_ASSET_CHAIN_ID(), _refTokenMetadata.nativeAssetChainId);
    assertEq(newRefToken.nativeAssetName(), _refTokenMetadata.nativeAssetName);
    assertEq(newRefToken.nativeAssetSymbol(), _refTokenMetadata.nativeAssetSymbol);
    assertEq(newRefToken.decimals(), _refTokenMetadata.nativeAssetDecimals);
  }

  function test_MintWhenCallerIsNotAuthorized(address _caller, address _user, uint256 _amount) external {
    vm.assume(_caller != address(refTokenBridge));
    _amount = bound(_amount, 1, type(uint256).max);

    // It reverts
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    refToken.mint(_user, _amount);
  }

  function test_MintWhenCallerIsAuthorized(address _user, uint256 _amount) external {
    uint256 _initialBalance = refToken.balanceOf(_user);
    vm.prank(address(refTokenBridge));

    vm.expectEmit();
    emit IERC20.Transfer(address(0), _user, _amount);

    // It mints the specified amount of RefToken to the recipient
    refToken.mint(_user, _amount);

    assertEq(refToken.balanceOf(_user), _initialBalance + _amount);
  }

  function test_BurnWhenCallerIsNotAuthorized(address _caller, address _user, uint256 _amount) external {
    vm.assume(_caller != address(refTokenBridge));
    _amount = bound(_amount, 1, type(uint256).max);

    // It reverts
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    refToken.burn(_user, _amount);
  }

  function test_BurnWhenCallerIsAuthorized(address _user, uint256 _initialBalance, uint256 _burnAmount) external {
    _initialBalance = bound(_initialBalance, 1, type(uint256).max);
    _burnAmount = bound(_burnAmount, 1, _initialBalance);

    vm.prank(address(refTokenBridge));
    refToken.mint(_user, _initialBalance);

    vm.expectEmit();
    emit IERC20.Transfer(_user, address(0), _burnAmount);

    // It burns the specified amount of RefToken from the caller
    vm.prank(address(refTokenBridge));
    refToken.burn(_user, _burnAmount);
    assertEq(refToken.balanceOf(_user), _initialBalance - _burnAmount);
  }

  function test_NameWhenCalled() external view {
    // It returns the name of the RefToken
    assertEq(refToken.name(), string.concat('RefToken (', nativeAssetName, ')'));
  }

  function test_SymbolWhenCalled() external view {
    // It returns the symbol of the RefToken
    assertEq(refToken.symbol(), string.concat('REF-', nativeAssetSymbol));
  }

  function test_DecimalsWhenCalled() external view {
    // It returns the decimals of the RefToken
    assertEq(refToken.decimals(), nativeAssetDecimals);
  }

  function test__mintWhenCallerIsNotTheSuperchainTokenBridge(address _to, uint256 _amount) external {
    uint256 _initialBalance = refToken.balanceOf(_to);

    // It calls super._mint
    vm.prank(address(refTokenBridge));
    refToken.mint(_to, _amount);

    assertEq(refToken.balanceOf(_to), _initialBalance + _amount);
  }

  function test__mintWhenChainIdDiffersFromTheNativeAssetChainId(address _to, uint256 _amount) external {
    uint256 _initialBalance = refToken.balanceOf(_to);

    // It calls super._mint
    vm.prank(address(refTokenBridge));
    refToken.mint(_to, _amount);

    assertEq(refToken.balanceOf(_to), _initialBalance + _amount);
  }

  function test_CrosschainMintWhenCallerIsAuthorizedAndChainIdIsTheNativeAssetOne(
    address _to,
    uint256 _amount
  ) external {
    vm.chainId(nativeAssetChainId);

    // It calls RefTokenBridge.unlock
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.unlock.selector, address(refToken), _to, _amount),
      ''
    );
    vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
    refToken.crosschainMint(_to, _amount);
  }

  function test_AllowanceWhenTheSpenderIsThePermit2Contract(address _owner) external view {
    // It returns the max uint256 value
    assertEq(refToken.allowance(_owner, PERMIT2), type(uint256).max);
  }

  function test_ApproveWhenTheSpenderIsThePermit2ContractAndValueIsNotTheMaxValue(
    address _caller,
    uint256 _amount
  ) external {
    _amount = bound(_amount, 1, type(uint256).max - 1);

    // It reverts
    vm.startPrank(_caller);
    vm.expectRevert(Permit2AllowanceIsFixedAtInfinity.selector);
    refToken.approve(PERMIT2, _amount);
  }

  function test_PermitWhenTheSpenderIsThePermit2ContractAndValueIsNotTheMaxValue(
    address _caller,
    address _owner,
    uint256 _amount,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    _amount = bound(_amount, 1, type(uint256).max - 1);

    // It reverts
    vm.startPrank(_caller);
    vm.expectRevert(Permit2AllowanceIsFixedAtInfinity.selector);
    refToken.permit(_owner, PERMIT2, _amount, _deadline, _v, _r, _s);
  }

  function test_TransferFromWhenTheCallerIsThePermit2ContractAndFromHasEnoughBalance(
    address _from,
    address _to,
    uint256 _amount
  ) external {
    vm.prank(address(refTokenBridge));
    refToken.mint(_from, _amount);

    uint256 _fromBalanceBefore = refToken.balanceOf(_from);
    uint256 _toBalanceBefore = refToken.balanceOf(_to);

    // It transfers the amount
    vm.prank(PERMIT2);
    refToken.transferFrom(_from, _to, _amount);

    if (_from == _to) {
      assertEq(refToken.balanceOf(_from), _fromBalanceBefore);
    } else {
      assertEq(refToken.balanceOf(_from), _fromBalanceBefore - _amount);
      assertEq(refToken.balanceOf(_to), _toBalanceBefore + _amount);
    }
  }

  function test_RefTokenMetadataWhenCalled() external view {
    assertEq(abi.encode(refToken.metadata()), abi.encode(refTokenMetadata));
  }
}
