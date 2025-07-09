// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';
import {Hashing} from '@interop-lib/src/libraries/Hashing.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IAllowanceTransfer} from '@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol';
import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IPoolInitializer_v4} from '@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {IRefTokenBridge, RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';

import {
  Identifier,
  MockL2ToL2CrossDomainMessenger as L2ToL2CrossDomainMessenger
} from './external/MockL2ToL2CrossDomainMessenger.sol';

import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';

contract IntegrationRefTokenBridgeTest is IntegrationBase {
  /**
   * @notice Test that the bridge can send OP to Unichain and deploy a ref token when the ref token is not deployed
   */
  function test_sendFromOpChainToUnichainWithRefTokenNotDeployed() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

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
    _op.approve(address(_refTokenBridge), _standardBridgeAmount);

    // Revert when sending OP to Unichain passing a bad native chain id
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidNativeAssetChainId.selector);
    _refTokenBridge.send(_unichainChainId, _unichainChainId, address(_op), _standardBridgeAmount, _recipient);

    // Send OP to Unichain
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _standardBridgeAmount, _recipient);

    vm.stopPrank();

    // Check that the OP is on the recipient
    assertEq(_op.balanceOf(_user), _userBalanceBefore - _standardBridgeAmount);
    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _bridgeBalanceBefore + _standardBridgeAmount);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    // Check that the ref token is deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
    // Check that the total supply of the ref token is 0 in the native chain
    assertEq(IERC20(_refOp).totalSupply(), 0);

    // Check ref token params
    IRefToken.RefTokenMetadata memory _refTokenMetadata = IRefToken(_refOp).metadata();
    assertEq(_refTokenMetadata.nativeAsset, address(_op));
    assertEq(_refTokenMetadata.nativeAssetChainId, _opChainId);
    assertEq(_refTokenMetadata.nativeAssetName, _op.name());
    assertEq(_refTokenMetadata.nativeAssetSymbol, _op.symbol());
    assertEq(_refTokenMetadata.nativeAssetDecimals, _op.decimals());

    // Compute the message that should have been relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _standardBridgeAmount, _recipient, _refTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and deploy a ref token and send OP again when the ref token is already deployed
   */
  function test_sendFromOpChainToUnichainWithRefTokenDeployed() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _userBalance);

    // Send OP to Unichain first time and deploy ref token
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _standardBridgeAmount, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _standardBridgeAmount);

    // Precompute the ref token metadata
    // Compute the message that should have been relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _standardBridgeAmount, _recipient, _refoOpMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Check that ref op was deployed and is the same as the precomputed ref token address
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refoOpMetadata));

    // Send OP to Unichain second time
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _doubleBridgeAmount, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _standardBridgeAmount + _doubleBridgeAmount);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refoOpMetadata));

    // Check that the total supply of the ref token is 0 in the native chain
    assertEq(IERC20(_refOp).totalSupply(), 0);

    // Compute the message that should have been relayed
    _message = abi.encodeWithSelector(_refTokenBridge.relay.selector, _doubleBridgeAmount, _recipient, _refoOpMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and send execute data to swap
   */
  function test_sendAndExecuteFromOpChainToUnichain() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _userBalance);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Create the execution data
    _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _unichainChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Send OP to Unichain first time and deploy ref token
    _refTokenBridge.sendAndExecute(
      _opChainId, _unichainChainId, address(_op), _standardBridgeAmount, _recipient, _executionData
    );

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _standardBridgeAmount);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refoOpMetadata));

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(address(_refTokenBridge)), 0);

    // Compute the message that should have been relayed
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _standardBridgeAmount, _recipient, _refoOpMetadata, _executionData
    );

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _unichainChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Send OP to Unichain second time
    _refTokenBridge.sendAndExecute(
      _opChainId, _unichainChainId, address(_op), _doubleBridgeAmount, _recipient, _executionData
    );

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _standardBridgeAmount + _doubleBridgeAmount);

    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _doubleBridgeAmount, _recipient, _refoOpMetadata, _executionData
    );

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and relay and execute back to the op chain simulating a user sending the ref token to the op chain from Unichain
   */
  function test_sendOpToUnichainAndRelayAndExecuteBackToOpChain() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _standardBridgeAmount);
    // Send OP to Unichain
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _standardBridgeAmount, _recipient);
    vm.stopPrank();

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);

    // Check that the total supply of the ref token is 0 in the native chain
    assertEq(IERC20(_refOp).totalSupply(), 0);

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _standardBridgeAmount, _recipient, _refoOpMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Now, we assume that the user sends the ref token to the op chain from Unichain

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_usdc));

    // Create the execution data
    _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _unichainChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    _message = abi.encodeWithSelector(
      RefTokenBridge.relayAndExecute.selector, _standardBridgeAmount, _recipient, _refoOpMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 0, _opChainId);

    // Check that ref token is deployed on the op chain before the relay
    assertEq(_refTokenBridge.isRefTokenDeployed(address(_refOp)), true);

    // Relay OP from Unichain
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the op on the recipient is used for the swap
    assertEq(_op.balanceOf(_recipient), 0);

    uint256 _fixUsdcSwapped = 562_141;

    // Create the message to be relayed to final destination
    _message = abi.encodeWithSelector(RefTokenBridge.relay.selector, _fixUsdcSwapped, _recipient, _refUsdcMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and relay back to the op chain simulating a user sending the ref token to the op chain from Unichain
   */
  function test_sendOpToUnichainAndRelayBackToOpChain() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _standardBridgeAmount);
    // Send OP to Unichain
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _standardBridgeAmount, _recipient);
    vm.stopPrank();

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);

    // Check that the total supply of the ref token is 0 in the native chain
    assertEq(IERC20(_refOp).totalSupply(), 0);

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _standardBridgeAmount, _recipient, _refoOpMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Now, we assume that the user sends the ref token to the op chain from Unichain

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 0, _opChainId);

    // Check that ref token is deployed on the op chain before the relay
    assertEq(_refTokenBridge.isRefTokenDeployed(address(_refOp)), true);

    // Relay OP from Unichain
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the OP is on the recipient and unlocked in the bridge
    assertEq(_op.balanceOf(_recipient), _standardBridgeAmount);
    assertEq(_op.balanceOf(address(_refTokenBridge)), 0);
  }

  /**
   * @notice Test that the bridge can relay OP from OpChain to Unichain and deploy a RefToken for OP when the ref token is not deployed
   * @param _amountToBridge The amount of OP to relay
   */
  function test_relayFromOpChainToUnichainWithRefTokenNotDeployed(uint256 _amountToBridge) public {
    vm.chainId(_unichainChainId);
    _amountToBridge = bound(_amountToBridge, 1, type(uint256).max);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Relay OP from OpChain
    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refoOpMetadata);

    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 0, _unichainChainId);

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
  function test_relayFromOpChainToUnichainWithRefTokenDeployed(
    uint256 _amountToBridge,
    uint256 _firstAmountToBridge
  ) public {
    vm.chainId(_unichainChainId);
    _firstAmountToBridge = bound(_firstAmountToBridge, 1, type(uint128).max);
    _amountToBridge = bound(_amountToBridge, _firstAmountToBridge, type(uint256).max);
    uint256 _secondAmountToBridge = _amountToBridge - _firstAmountToBridge;

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _firstAmountToBridge, _recipient, _refoOpMetadata);

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 0, _unichainChainId);

    // Relay OP from OpChain first time and deploy ref token
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(IERC20(_refOp).balanceOf(_recipient), _firstAmountToBridge);

    // Check that ref op was deployed and is the same as the precomputed ref token address
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refoOpMetadata));

    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _secondAmountToBridge, _recipient, _refoOpMetadata);
    (_sentMessage, _identifier) = _messageAndIdentifier(_message, 1, _unichainChainId);

    // Relay OP from OpChain second time
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _firstAmountToBridge + _secondAmountToBridge);

    // Check that ref op was deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
  }

  /**
   * @notice Test that the bridge can relay OP and USDC from Unichain to OpChain, swap and send to Unichain
   */
  function test_relayFromUnichainToOpChainAndSwapAndSend() public {
    // Create the ref token metadata, setting the native assets chain to be unichain instead of OP
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);
    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op and usdc to Unichain and get the ref tokens
    _relayToGetRefToken(_opAmountToRelay, 0, _recipient, _opChainId, _opRefTokenMetadata);
    _relayToGetRefToken(_opAmountToRelay, 1, _recipient, _opChainId, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _opAmountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _opAmountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(
      _positionManager,
      _uniSwapExecutor,
      _recipient,
      address(_refOp),
      address(_refUsdc),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();

    // Create the message to be relayed to execute a swap, now the recipient is the user
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _standardSwapAmount, _user, _opRefTokenMetadata);

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref usdc is got to the user
    assertEq(IERC20(_refOp).balanceOf(_user), _standardSwapAmount);

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_refUsdc));

    // Only send the usdc to the op chain
    _executionData.destinationExecutor = address(0);

    // Swap and send the op to the op chain
    vm.startPrank(_user);
    IERC20(_refOp).approve(address(_uniSwapExecutor), _standardSwapAmount);
    _uniSwapExecutor.swapAndSend(
      address(_refOp), _standardSwapAmount, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );
    vm.stopPrank();

    // Check that the ref op on the user is used for the swap
    // Check that the ref usdc is burned and send it to the unichain
    assertEq(IERC20(_refOp).balanceOf(_user), 0);
    assertEq(IERC20(_refUsdc).balanceOf(_user), 0);

    uint256 _fixUsdcSwapped = 455_407;

    // Create the message to be relayed
    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _fixUsdcSwapped, _recipient, _usdcRefTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can relay a message from unichain to op chain and execute a swap with ref tokens
   */
  function test_relayAndExecuteFromUnichainToOpChainAndSwapWithRefTokenAndGetRefToken() public {
    // Create the ref token metadata
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);

    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_opAmountToRelay, 0, _recipient, _opChainId, _opRefTokenMetadata);

    // Relay the usdc ref token
    _relayToGetRefToken(_opAmountToRelay, 1, _recipient, _opChainId, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _opAmountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _opAmountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(
      _positionManager,
      _uniSwapExecutor,
      _recipient,
      address(_refOp),
      address(_refUsdc),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_refUsdc));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _opChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Create the message to be relayed to execute a swap, now the recipient is the user
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _standardSwapAmount, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint256 _fixUsdcSwapped = 455_407;

    // Check that the ref usdc is got to the user
    assertEq(IERC20(_refUsdc).balanceOf(_user), _fixUsdcSwapped);

    // Check that the ref op token is swapped
    assertEq(IERC20(_refOp).balanceOf(_user), 0);
  }

  /**
   * @notice Test that the bridge can relay a message from unichain to op chain and execute a swap with native tokens, also will send it to destination chain
   */
  function test_relayAndExecuteFromUnichainToOpChainAndSwapWithNativeTokenAndGetRefToken() public {
    // Set up user funds
    vm.startPrank(_opWhale);
    _op.transfer(address(_recipient), _opAmountToRelay);
    _op.transfer(address(_user), _standardSwapAmount);
    vm.stopPrank();

    // Create the ref token metadata, setting the native assets chain to be unichain instead of OP
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _opChainId);
    // Create the ref token metadata, setting the native assets chain to be OP chain
    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_usdcAmountToRelay, 0, _recipient, _opChainId, _usdcRefTokenMetadata);

    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _usdcAmountToRelay);
    assertEq(_op.balanceOf(_recipient), _opAmountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(
      _positionManager,
      _uniSwapExecutor,
      _recipient,
      address(_op),
      address(_refUsdc),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_refUsdc));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _baseChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Send the usdc to the unichain
    vm.startPrank(_user);
    _op.approve(address(_refTokenBridge), _standardSwapAmount);
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _standardSwapAmount, _user);
    vm.stopPrank();

    // Check that the recipient has no usdc because it was sent to the unichain
    assertEq(_op.balanceOf(_user), 0);

    // Create the message to be relayed to final destination
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _standardSwapAmount, _user, _opRefTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Now, we will relay the usdc to the op chain and execute a swap with the native token

    // Create the message to be relayed to execute a swap, now the recipient is the user
    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _standardSwapAmount, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 1, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint256 _usdcFixSwapped = 455_407;

    // Create the message to be relayed to final destination
    _message = abi.encodeWithSelector(RefTokenBridge.relay.selector, _usdcFixSwapped, _user, _usdcRefTokenMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _baseChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can relay a message from unichain to op chain and execute a swap with native tokens, also will send it to destination chain
   */
  function test_relayAndExecuteFromUnichainToOpChainAndSwapWithNativeTokenAndNativeToken() public {
    uint256 _usdcStandardSwapAmount = 1 * 10 ** 6;
    // Set up user funds
    vm.startPrank(_usdcWhale);
    _usdc.transfer(address(_recipient), _usdcAmountToRelay);
    _usdc.transfer(address(_user), _usdcStandardSwapAmount);
    vm.stopPrank();

    vm.startPrank(_opWhale);
    _op.transfer(address(_recipient), _opAmountToRelay);
    vm.stopPrank();

    // Check that the ref token is on the recipient
    assertEq(IERC20(_op).balanceOf(_recipient), _opAmountToRelay);
    assertEq(_usdc.balanceOf(_recipient), _usdcAmountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(
      _positionManager,
      _uniSwapExecutor,
      _recipient,
      address(_op),
      address(_usdc),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_op));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _baseChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Send the usdc to the unichain
    vm.startPrank(_user);
    _usdc.approve(address(_refTokenBridge), _usdcStandardSwapAmount);
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_usdc), _usdcStandardSwapAmount, _user);
    vm.stopPrank();

    // Check that the recipient has no usdc because it was sent to the unichain
    assertEq(_usdc.balanceOf(_user), 0);

    // Create the message to be relayed to final destination
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _usdcStandardSwapAmount, _user, _refUsdcMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Now, we will relay the usdc to the op chain and execute a swap with the native token

    // Create the message to be relayed to execute a swap, now the recipient is the user
    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _usdcStandardSwapAmount, _user, _refUsdcMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 1, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint256 _fixOpSwapped = 1_768_240_869_652_251_541;

    // Create the message to be relayed to final destination
    _message = abi.encodeWithSelector(RefTokenBridge.relay.selector, _fixOpSwapped, _user, _refoOpMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _baseChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that if the swap and send to origin chain revert, the bridge will revert the relay and execute
   */
  function test_relayAndExecuteRevertInSwapAndSendToOriginChain() public {
    uint256 _usdcStandardSwapAmount = 1 * 10 ** 6;

    // Set up user funds
    vm.startPrank(_usdcWhale);
    _usdc.transfer(address(_recipient), _usdcAmountToRelay);
    _usdc.transfer(address(_user), _usdcStandardSwapAmount);
    vm.stopPrank();

    vm.startPrank(_opWhale);
    _op.transfer(address(_recipient), _opAmountToRelay);
    vm.stopPrank();

    // Check that the ref token is on the recipient
    assertEq(IERC20(_op).balanceOf(_recipient), _opAmountToRelay);
    assertEq(_usdc.balanceOf(_recipient), _usdcAmountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(
      _positionManager,
      _uniSwapExecutor,
      _recipient,
      address(_op),
      address(_usdc),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _baseChainId,
      data: bytes(''),
      refundAddress: _refund
    });

    // Send the usdc to the unichain
    vm.startPrank(_user);
    _usdc.approve(address(_refTokenBridge), _usdcStandardSwapAmount);
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_usdc), _usdcStandardSwapAmount, _user);
    vm.stopPrank();

    // Check that the recipient has no usdc because it was sent to the unichain
    assertEq(_usdc.balanceOf(_user), 0);

    // Create the message to be relayed to final destination
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _usdcStandardSwapAmount, _user, _refUsdcMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Now, we will relay the usdc to the op chain and execute a swap, it will revert because the swap will revert
    // The amount will be sent to the origin chain

    // Create the message to be relayed to execute a swap, now the recipient is the user
    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _usdcStandardSwapAmount, _user, _refUsdcMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    // The chain id identifier is the unichain chain id because the message will be relayed to the unichain chain
    bytes memory _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _opChainId, address(_refTokenBridge), 0),
      abi.encode(address(_refTokenBridge), _message)
    );

    Identifier memory _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 0,
      timestamp: block.timestamp,
      chainId: _unichainChainId
    });

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Create the message to be relayed to final destination
    _message = abi.encodeWithSelector(RefTokenBridge.relay.selector, _usdcStandardSwapAmount, _refund, _refUsdcMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can relay OP and USDC from Unichain to OpChain, execute a swap, and swap and send to Unichain
   */
  function test_relayAndExecuteFromUnichainToOpChainAndSwapAndSend() public {
    // Create the ref token metadata
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);

    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_opAmountToRelay, 0, _recipient, _opChainId, _opRefTokenMetadata);

    // Relay the usdc ref token
    _relayToGetRefToken(_usdcAmountToRelay, 1, _recipient, _opChainId, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _opAmountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _usdcAmountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(
      _positionManager,
      _uniSwapExecutor,
      _recipient,
      address(_refOp),
      address(_refUsdc),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_refUsdc));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _opChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Create the message to be relayed to execute a swap, now the recipient is the user
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _standardSwapAmount, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint128 _fixUsdcSwapped = 455_407;
    // Check that the ref usdc is got to the user
    assertEq(IERC20(_refUsdc).balanceOf(_user), _fixUsdcSwapped);

    // Create the swap params
    _v4SwapParams = _createV4SwapParams(address(_refOp));

    // Create destination v4 swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParamsDestination = _createV4SwapParams(address(_op));

    // Create the execution data
    _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _unichainChainId,
      data: abi.encode(_v4SwapParamsDestination),
      refundAddress: _refund
    });

    // Swap and send the usdc to the op chain
    vm.startPrank(_user);
    IERC20(_refUsdc).approve(address(_uniSwapExecutor), _fixUsdcSwapped);
    _uniSwapExecutor.swapAndSend(
      address(_refUsdc), _fixUsdcSwapped, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );
    vm.stopPrank();

    // Check that the usdc is sent to the op chain
    assertEq(IERC20(_refUsdc).balanceOf(_user), 0);

    uint256 _fixOpSwapped = 994_006_906_200_230_120;

    // Compute the message that should have been relayed
    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _fixOpSwapped, _recipient, _opRefTokenMetadata, _executionData
    );

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that swap and send to Unichain, relay and execute back to the op chain
   */
  function test_swapAndSendAndRelayFromOpChainToUnichain() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    // Set up user funds
    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_uniSwapExecutor), _userBalance);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Swap and send the USDC to Unichain
    _uniSwapExecutor.swapAndSend(
      address(_op), _standardSwapAmount, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the user's OP token balance has decreased
    assertEq(_op.balanceOf(_user), _userBalance - _standardSwapAmount);

    // Check that the USDC is on the bridge
    uint256 _usdcBalance = _usdc.balanceOf(address(_refTokenBridge));

    // Check that the USDC is on the bridge
    assertEq(_usdcBalance, _fixAmountOut);

    // Check that the ref op was deployed
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _opChainId);
    assertEq(_refUsdc, _precalculateRefTokenAddress(address(_refTokenBridge), _refUsdcMetadata));

    // Compute the message that should have been relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _usdcBalance, _recipient, _refUsdcMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Swap and send the USDC to Unichain second time
    _uniSwapExecutor.swapAndSend(
      address(_op), _standardSwapAmount, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the ref op was deployed
    _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _opChainId);
    assertEq(_refUsdc, _precalculateRefTokenAddress(address(_refTokenBridge), _refUsdcMetadata));

    uint256 _usdcBalanceSecondSwap = _usdc.balanceOf(address(_refTokenBridge)) - _usdcBalance;

    // Compute the message that should have been relayed
    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _usdcBalanceSecondSwap, _recipient, _refUsdcMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that swap and send to Unichain, relay and execute back to the op chain
   */
  function test_swapAndSendAndRelayAndExecuteFromOpChainToUnichain() public {
    uint256 _userBalance = _op.balanceOf(_opWhale);

    // Set up user funds
    vm.startPrank(_opWhale);
    _op.transfer(address(_user), _userBalance);
    vm.stopPrank();

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_uniSwapExecutor), _userBalance);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Create destination v4 swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParamsDestination = _createV4SwapParams(address(_op));

    // Create the execution data
    _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _unichainChainId,
      data: abi.encode(_v4SwapParamsDestination),
      refundAddress: _refund
    });

    // Swap and send the USDC to Unichain
    _uniSwapExecutor.swapAndSend(
      address(_op), _standardSwapAmount, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the user's OP token balance has decreased
    assertEq(_op.balanceOf(_user), _userBalance - _standardSwapAmount);

    // Check that the USDC is on the bridge
    uint256 _usdcBalance = _usdc.balanceOf(address(_refTokenBridge));

    // Check that the USDC is on the bridge
    assertEq(_usdcBalance, _fixAmountOut);

    // Check that the ref op was deployed
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _opChainId);
    assertEq(_refUsdc, _precalculateRefTokenAddress(address(_refTokenBridge), _refUsdcMetadata));

    // Compute the message that should have been relayed
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _usdcBalance, _recipient, _refUsdcMetadata, _executionData
    );

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Swap and send the USDC to Unichain second time
    _uniSwapExecutor.swapAndSend(
      address(_op), _standardSwapAmount, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the ref op was deployed
    _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _opChainId);
    assertEq(_refUsdc, _precalculateRefTokenAddress(address(_refTokenBridge), _refUsdcMetadata));

    uint256 _usdcBalanceSecondSwap = _usdc.balanceOf(address(_refTokenBridge)) - _usdcBalance;

    // Compute the message that should have been relayed
    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _usdcBalanceSecondSwap, _recipient, _refUsdcMetadata, _executionData
    );

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Helper function to create the ref token metadata
   * @param _token The token to create the metadata for
   * @param _chainId The chain id of the token
   * @return _refTokenMetadata The ref token metadata
   */
  function _createRefTokenMetadata(
    address _token,
    uint256 _chainId
  ) internal view returns (IRefToken.RefTokenMetadata memory _refTokenMetadata) {
    _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: _token,
      nativeAssetChainId: _chainId,
      nativeAssetName: IERC20(_token).name(),
      nativeAssetSymbol: IERC20(_token).symbol(),
      nativeAssetDecimals: IERC20(_token).decimals()
    });
  }

  /**
   * @notice Helper function to compute the message hash
   * @param _message The message to be relayed
   * @param _nonce The nonce of the relay message
   * @param _sourceChainId The chain id of the origin of the sent message
   * @param _destinationChainId The chain id of the destination of the sent message
   * @return _messageHash The message hash
   */
  function _computeMessageHash(
    bytes memory _message,
    uint256 _nonce,
    uint256 _sourceChainId,
    uint256 _destinationChainId
  ) internal view returns (bytes32 _messageHash) {
    _messageHash = Hashing.hashL2toL2CrossDomainMessage({
      _destination: _destinationChainId,
      _source: _sourceChainId,
      _nonce: _nonce,
      _sender: address(_refTokenBridge),
      _target: address(_refTokenBridge),
      _message: _message
    });
  }

  /**
   * @notice Helper function to create the message and identifier for the relay message
   * @param _message The message to be relayed
   * @param _nonce The nonce of the relay message
   * @param _chainId The chain id of the relay message
   * @return _sentMessage The sent message
   * @return _identifier The identifier for the relay message
   */
  function _messageAndIdentifier(
    bytes memory _message,
    uint256 _nonce,
    uint256 _chainId
  ) internal view returns (bytes memory _sentMessage, Identifier memory _identifier) {
    _sentMessage = abi.encodePacked(
      abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, _chainId, address(_refTokenBridge), _nonce),
      abi.encode(address(_refTokenBridge), _message)
    );

    _identifier = Identifier({
      origin: PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      blockNumber: block.number,
      logIndex: 0,
      timestamp: block.timestamp,
      chainId: _chainId
    });
  }

  /**
   * @notice Helper function to relay to get the ref token
   * @param _amountToBridge The amount of token to relay
   * @param _nonce The nonce of the relay message
   */
  function _relayToGetRefToken(
    uint256 _amountToBridge,
    uint256 _nonce,
    address _recipient,
    uint256 _chainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) internal {
    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, _nonce, _chainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);
  }
}
