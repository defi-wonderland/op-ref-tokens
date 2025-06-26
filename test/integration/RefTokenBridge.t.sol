// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';

import {IRefTokenBridge, RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';

import {Identifier, L2ToL2CrossDomainMessenger} from './external/L2ToL2CrossDomainMessenger.sol';

import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';

contract IntegrationRefTokenBridgeTest is IntegrationBase {
  function setUp() public virtual override {
    super.setUp();
  }

  function test_sendOpToUnichainWithRefTokenNotDeployed(uint256 _userBalance, uint256 _amountToBridge) public {
    _userBalance = bound(_userBalance, 1, type(uint128).max);
    _amountToBridge = bound(_amountToBridge, 1, _userBalance);

    // Set up user funds
    deal(address(_op), _user, _userBalance);

    // Check that the bridge has no OP
    uint256 _bridgeBalanceBefore = _op.balanceOf(address(_refTokenBridge));
    assertEq(_bridgeBalanceBefore, 0);

    // Check that the user has OP
    uint256 _userBalanceBefore = _op.balanceOf(_user);
    assertEq(_userBalanceBefore, _userBalance);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _amountToBridge);

    // Revert when sending OP to Unichain passing a bad native chain id
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidNativeAssetChainId.selector);
    _refTokenBridge.send(_unichainChainId, _unichainChainId, address(_op), _amountToBridge, _recipient);

    // Send OP to Unichain
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _amountToBridge, _recipient);

    vm.stopPrank();

    // Check that the OP is on the recipient
    assertEq(_op.balanceOf(_user), _userBalanceBefore - _amountToBridge);
    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _bridgeBalanceBefore + _amountToBridge);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    // Check that the ref token is deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);

    // Check ref token params
    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken(_refOp).metadata();
    assertEq(_refTokenMetadata.nativeAsset, address(_op));
    assertEq(_refTokenMetadata.nativeAssetChainId, _opChainId);
    assertEq(_refTokenMetadata.nativeAssetName, _op.name());
    assertEq(_refTokenMetadata.nativeAssetSymbol, _op.symbol());
    assertEq(_refTokenMetadata.nativeAssetDecimals, _op.decimals());
  }

  function test_sendOpToUnichainWithRefTokenDeployed(uint256 _userBalance, uint256 _amountToBridge) public {
    _userBalance = bound(_userBalance, 200, type(uint128).max);
    _amountToBridge = bound(_amountToBridge, 200, _userBalance);

    // Set up user funds
    deal(address(_op), _user, _userBalance);

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _amountToBridge);

    // Send OP to Unichain first time and deploy ref token
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), 100, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), 100);

    IRefToken.RefTokenMetadata memory _precomputedRefTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Check that ref op was deployed and is the same as the precomputed ref token address
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _precomputedRefTokenMetadata));

    // Send OP to Unichain second time and check that the ref token is already deployed
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _amountToBridge - 100, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _amountToBridge);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _precomputedRefTokenMetadata));
  }

  function test_relayOpFromOpChainWithRefTokenNotDeployed(uint256 _amountToBridge) public {
    vm.chainId(_unichainChainId);
    _amountToBridge = bound(_amountToBridge, 1, type(uint128).max);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Relay OP from OpChain
    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Create the sent message
    bytes memory _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_refTokenBridge), 1),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Create the identifier for the relay message
    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 1,
      timestamp: block.timestamp,
      chainId: _opChainId
    });

    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    // Check that the ref token is deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);

    // Check ref token params
    IRefToken.RefTokenMetadata memory _onchainRefTokenMetadata = IRefToken(_refOp).metadata();
    assertEq(_onchainRefTokenMetadata.nativeAsset, address(_op));
    assertEq(_onchainRefTokenMetadata.nativeAssetChainId, _opChainId);
    assertEq(_onchainRefTokenMetadata.nativeAssetName, _op.name());
    assertEq(_onchainRefTokenMetadata.nativeAssetSymbol, _op.symbol());
    assertEq(_onchainRefTokenMetadata.nativeAssetDecimals, _op.decimals());

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _amountToBridge);
  }

  function test_relayOpFromOpChainWithRefTokenDeployed(uint256 _amountToBridge) public {
    vm.chainId(_unichainChainId);
    _amountToBridge = bound(_amountToBridge, 200, type(uint128).max);

    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Create the message to be relayed
    bytes memory _message = abi.encodeWithSelector(_refTokenBridge.relay.selector, 100, _recipient, _refTokenMetadata);

    // Create the sent message
    bytes memory _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_refTokenBridge), 1),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Create the identifier for the relay message
    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 1,
      timestamp: block.timestamp,
      chainId: _opChainId
    });

    // Relay OP from OpChain first time and deploy ref token
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(IERC20(_refOp).balanceOf(_recipient), 100);

    // Check that ref op was deployed and is the same as the precomputed ref token address
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refTokenMetadata));

    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge - 100, _recipient, _refTokenMetadata);
    _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_refTokenBridge), 2),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Relay OP from OpChain second time
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _amountToBridge);

    // Check that ref op was deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
  }

  function test_sendOpToUnichainRelayFromUnichainAndBackToOpChain(uint256 _amountToBridge) public {
    _amountToBridge = bound(_amountToBridge, 1, type(uint128).max);

    // Set up user funds
    deal(address(_op), _user, _amountToBridge);

    // Create a new ref token bridge for the unichain chain
    RefTokenBridge _unichainRefTokenBridge = new RefTokenBridge();

    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _amountToBridge);
    // Send OP to Unichain
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _amountToBridge, _recipient);
    vm.stopPrank();

    vm.chainId(_unichainChainId);

    // Check that ref token is not deployed
    address _refOp = _unichainRefTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Get the ref token address from the op chain
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);

    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Create the sent message
    bytes memory _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_unichainRefTokenBridge), 1),
      abi.encode(address(_unichainRefTokenBridge), _message)
    );

    // Create the identifier for the relay message
    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 1,
      timestamp: block.timestamp,
      chainId: _opChainId
    });

    // Relay OP from Unichain
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that ref token is deployed
    address _uniRefOp = _unichainRefTokenBridge.nativeToRefToken(address(_op), _opChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_uniRefOp).balanceOf(_recipient), _amountToBridge);

    // TODO: THIS IS NOT WORKING
    vm.chainId(_unichainChainId);

    // The recipient sends the ref token to the op chain
    vm.prank(_recipient);
    // Send the ref token to the op chain
    _unichainRefTokenBridge.send(_unichainChainId, _opChainId, address(_uniRefOp), _amountToBridge, _user);

    // Check that the ref token in the recipient has been burned
    assertEq(IERC20(_uniRefOp).balanceOf(_recipient), 0);

    // Change to the op chain
    vm.chainId(_opChainId);

    _message = abi.encodeWithSelector(RefTokenBridge.relay.selector, _amountToBridge, _user, _refTokenMetadata);

    _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _opChainId, address(_refTokenBridge), 2),
      abi.encode(address(_refTokenBridge), _message)
    );

    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the OP is on the user
    assertEq(_op.balanceOf(_user), _amountToBridge);

    // Check that the bridge unlocked the OP and burn the ref token
    assertEq(_op.balanceOf(address(_refTokenBridge)), 0);
    assertEq(IERC20(_refOp).balanceOf(address(_refTokenBridge)), 0);
  }
}
