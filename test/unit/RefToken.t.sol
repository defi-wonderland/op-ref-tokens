// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {Unauthorized} from '@interop-lib/src/libraries/errors/CommonErrors.sol';

import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';
import {RefToken} from 'src/contracts/RefToken.sol';

contract UnitRefTokenTest is Test {
  RefToken refToken;
  address user = makeAddr('user');
  address refTokenBridge = makeAddr('RefTokenBridge');
  uint256 nativeAssetChainId = 2;
  string nativeAssetName = 'Native Asset';
  string nativeAssetSymbol = 'NA';
  uint8 nativeAssetDecimals = 18;

  function setUp() external {
    refToken = new RefToken(refTokenBridge, nativeAssetChainId, nativeAssetName, nativeAssetSymbol, nativeAssetDecimals);
  }

  function _mockAndExpect(address _contract, bytes memory _data, bytes memory _returnData) internal {
    vm.mockCall(_contract, _data, abi.encode(_returnData));
    vm.expectCall(_contract, _data);
  }

  function test_ConstructorWhenDeployed(
    address _refTokenBridge,
    uint256 _nativeAssetChainId,
    string memory _nativeAssetName,
    string memory _nativeAssetSymbol,
    uint8 _nativeAssetDecimals
  ) external {
    // It constructs the RefToken contract
    RefToken newRefToken =
      new RefToken(_refTokenBridge, _nativeAssetChainId, _nativeAssetName, _nativeAssetSymbol, _nativeAssetDecimals);
    assertEq(address(newRefToken.REF_TOKEN_BRIDGE()), _refTokenBridge);
    assertEq(newRefToken.NATIVE_ASSET_CHAIN_ID(), _nativeAssetChainId);
    assertEq(newRefToken.NATIVE_ASSET_NAME(), _nativeAssetName);
    assertEq(newRefToken.NATIVE_ASSET_SYMBOL(), _nativeAssetSymbol);
    assertEq(newRefToken.decimals(), _nativeAssetDecimals);
  }

  function test_MintWhenCallerIsNotAuthorized(address _caller) external {
    vm.assume(_caller != refTokenBridge);
    // It reverts
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    refToken.mint(user, 100);
  }

  function test_MintWhenCallerIsAuthorized(address _user, uint256 _amount) external {
    uint256 _initialBalance = refToken.balanceOf(_user);
    vm.prank(refTokenBridge);

    vm.expectEmit(true, true, true, true, address(refToken));
    emit IERC20.Transfer(address(0), _user, _amount);

    // It mints the specified amount of RefToken to the recipient
    refToken.mint(_user, _amount);

    assertEq(refToken.balanceOf(_user), _initialBalance + _amount);
  }

  function test_BurnWhenCallerIsNotAuthorized(address _caller) external {
    vm.assume(_caller != refTokenBridge);
    // It reverts
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    refToken.burn(user, 100);
  }

  function test_BurnWhenCallerIsAuthorized(address _user, uint256 _initialBalance, uint256 _burnAmount) external {
    _initialBalance = bound(_initialBalance, 1, type(uint256).max);
    _burnAmount = bound(_burnAmount, 1, _initialBalance);

    vm.prank(refTokenBridge);
    refToken.mint(_user, _initialBalance);

    vm.expectEmit(true, true, true, true, address(refToken));
    emit IERC20.Transfer(_user, address(0), _burnAmount);

    // It burns the specified amount of RefToken from the caller
    vm.prank(refTokenBridge);
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
    vm.prank(refTokenBridge);
    refToken.mint(_to, _amount);

    assertEq(refToken.balanceOf(_to), _initialBalance + _amount);
  }

  function test__mintWhenChainIdDiffersFromTheNativeAssetChainId(address _to, uint256 _amount) external {
    uint256 _initialBalance = refToken.balanceOf(_to);

    // It calls super._mint
    vm.prank(refTokenBridge);
    refToken.mint(_to, _amount);

    assertEq(refToken.balanceOf(_to), _initialBalance + _amount);
  }

  function test_CrosschainMintWhenCallerIsAuthorizedAndChainIdIsTheNativeAssetOne(
    address _to,
    uint256 _amount
  ) external {
    vm.chainId(nativeAssetChainId);

    // It calls RefTokenBridge.unlock
    _mockAndExpect(address(refTokenBridge), abi.encodeWithSelector(IRefTokenBridge.unlock.selector, _to, _amount), '');
    vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
    refToken.crosschainMint(_to, _amount);
  }
}
