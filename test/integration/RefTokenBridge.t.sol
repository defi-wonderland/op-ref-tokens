// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';
import {Hashing} from '@interop-lib/src/libraries/Hashing.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IRefTokenBridge, RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';

import {
  Identifier,
  MockL2ToL2CrossDomainMessenger as L2ToL2CrossDomainMessenger
} from './external/MockL2ToL2CrossDomainMessenger.sol';

import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';

contract IntegrationRefTokenBridgeTest is IntegrationBase {
  /**
   * @notice Test that the bridge can send OP to Unichain and deploy a ref token when the ref token is not deployed
   * @param _userBalance The balance of the user
   * @param _amountToBridge The amount of OP to bridge
   */
  function test_sendOpToUnichainWithRefTokenNotDeployed(uint256 _userBalance, uint256 _amountToBridge) public {
    _userBalance = bound(_userBalance, 1, type(uint256).max);
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

    // Compute the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = Hashing.hashL2toL2CrossDomainMessage({
      _destination: _unichainChainId,
      _source: _opChainId,
      _nonce: 0,
      _sender: address(_refTokenBridge),
      _target: address(_refTokenBridge),
      _message: _message
    });

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and deploy a ref token and send OP again when the ref token is already deployed
   * @param _userBalance The balance of the user
   * @param _firstAmountToBridge The amount of OP to bridge first time
   */
  function test_sendOpToUnichainWithRefTokenDeployed(uint256 _userBalance, uint256 _firstAmountToBridge) public {
    _firstAmountToBridge = bound(_firstAmountToBridge, 1, type(uint128).max);
    _userBalance = bound(_userBalance, _firstAmountToBridge + 1, type(uint256).max);
    uint256 _secondAmountToBridge = _userBalance - _firstAmountToBridge;

    // Set up user funds
    deal(address(_op), _user, _userBalance);

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _userBalance);

    // Send OP to Unichain first time and deploy ref token
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _firstAmountToBridge, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _firstAmountToBridge);

    // Precompute the ref token metadata
    IRefToken.RefTokenMetadata memory _precomputedRefTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Compute the message to be relayed
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relay.selector, _firstAmountToBridge, _recipient, _precomputedRefTokenMetadata
    );

    // Check that the message hash is correct
    bytes32 _messageHash = Hashing.hashL2toL2CrossDomainMessage({
      _destination: _unichainChainId,
      _source: _opChainId,
      _nonce: 0,
      _sender: address(_refTokenBridge),
      _target: address(_refTokenBridge),
      _message: _message
    });

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Check that ref op was deployed and is the same as the precomputed ref token address
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _precomputedRefTokenMetadata));

    // Send OP to Unichain second time and check that the ref token is already deployed
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _secondAmountToBridge, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _firstAmountToBridge + _secondAmountToBridge);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _precomputedRefTokenMetadata));

    // Compute the message to be relayed
    _message = abi.encodeWithSelector(
      _refTokenBridge.relay.selector, _secondAmountToBridge, _recipient, _precomputedRefTokenMetadata
    );

    // Check that the message hash is correct
    _messageHash = Hashing.hashL2toL2CrossDomainMessage({
      _destination: _unichainChainId,
      _source: _opChainId,
      _nonce: 1,
      _sender: address(_refTokenBridge),
      _target: address(_refTokenBridge),
      _message: _message
    });

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can relay OP from OpChain to Unichain and deploy a RefToken for OP when the ref token is not deployed
   * @param _amountToBridge The amount of OP to relay
   */
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
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_refTokenBridge), 0),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Create the identifier for the relay message
    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 0,
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

  /**
   * @notice Test that the bridge can relay OP from OpChain to Unichain and deploy a RefToken and relay OP again when the ref token is already deployed
   * @param _amountToBridge The amount of OP to relay
   * @param _firstAmountToBridge The amount of OP to relay first time
   */
  function test_relayOpFromOpChainWithRefTokenDeployed(uint256 _amountToBridge, uint256 _firstAmountToBridge) public {
    vm.chainId(_unichainChainId);
    _firstAmountToBridge = bound(_firstAmountToBridge, 1, type(uint128).max);
    _amountToBridge = bound(_amountToBridge, _firstAmountToBridge, type(uint128).max);
    uint256 _secondAmountToBridge = _amountToBridge - _firstAmountToBridge;

    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _firstAmountToBridge, _recipient, _refTokenMetadata);

    // Create the sent message
    bytes memory _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_refTokenBridge), 0),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Create the identifier for the relay message
    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 0,
      timestamp: block.timestamp,
      chainId: _opChainId
    });

    // Relay OP from OpChain first time and deploy ref token
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(IERC20(_refOp).balanceOf(_recipient), _firstAmountToBridge);

    // Check that ref op was deployed and is the same as the precomputed ref token address
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refTokenMetadata));

    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _secondAmountToBridge, _recipient, _refTokenMetadata);
    _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _unichainChainId, address(_refTokenBridge), 1),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Relay OP from OpChain second time
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _firstAmountToBridge + _secondAmountToBridge);

    // Check that ref op was deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and relay back to the op chain simulating a user sending the ref token to the op chain from Unichain
   * @param _amountToBridge The amount of OP to send to Unichain
   */
  function test_sendOpToUnichainAndRelayBackToOpChain(uint256 _amountToBridge) public {
    _amountToBridge = bound(_amountToBridge, 1, type(uint256).max);

    // Set up user funds
    deal(address(_op), _user, _amountToBridge);

    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _amountToBridge);
    // Send OP to Unichain
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _amountToBridge, _recipient);
    vm.stopPrank();

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken(_refOp).metadata();

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = Hashing.hashL2toL2CrossDomainMessage({
      _destination: _unichainChainId,
      _source: _opChainId,
      _nonce: 0,
      _sender: address(_refTokenBridge),
      _target: address(_refTokenBridge),
      _message: _message
    });

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Now, we assume that the user sends the ref token to the op chain from Unichain

    // Create the message to be relayed from Unichain to the op chain
    _message = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _opChainId, address(_refTokenBridge), 0),
      abi.encode(address(_refTokenBridge), _message)
    );

    // Create the identifier for the relay message
    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 0,
      timestamp: block.timestamp,
      chainId: _unichainChainId
    });

    // Check that ref token is deployed on the op chain before the relay
    assertEq(_refTokenBridge.isRefTokenDeployed(address(_refOp)), true);

    // Relay OP from Unichain
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _message);

    // Check that the OP is on the recipient and unlocked in the bridge
    assertEq(_op.balanceOf(_recipient), _amountToBridge);
    assertEq(_op.balanceOf(address(_refTokenBridge)), 0);
  }
}
