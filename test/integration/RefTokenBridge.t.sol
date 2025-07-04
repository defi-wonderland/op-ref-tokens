// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';
import {Hashing} from '@interop-lib/src/libraries/Hashing.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';

import {IAllowanceTransfer} from '@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol';

import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IPoolInitializer_v4} from '@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
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
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

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
    // Compute the message that should have been relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _firstAmountToBridge, _recipient, _refTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));

    // Check that ref op was deployed and is the same as the precomputed ref token address
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refTokenMetadata));

    // Send OP to Unichain second time
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _secondAmountToBridge, _recipient);

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _firstAmountToBridge + _secondAmountToBridge);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refTokenMetadata));

    // Check that the total supply of the ref token is 0 in the native chain
    assertEq(IERC20(_refOp).totalSupply(), 0);

    // Compute the message that should have been relayed
    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _secondAmountToBridge, _recipient, _refTokenMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain through the executor
   * @param _userBalance The balance of the user
   */
  function test_sendFromOpChainToUnichainThroughExecutor(uint256 _userBalance) public {
    // Cant be fuzzed because the pool doesn't have enough liquidity
    uint128 _firstAmountToSwap = 1 ether;
    uint128 _secondAmountToSwap = 2 ether;
    _userBalance = bound(_userBalance, _firstAmountToSwap + _secondAmountToSwap + 1, type(uint256).max);

    // Set up user funds
    deal(address(_op), _user, _userBalance);

    // Approve the bridge to spend the OP
    vm.startPrank(_user);
    _op.approve(address(_uniSwapExecutor), _userBalance);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Swap and send the USDC to Unichain
    _uniSwapExecutor.swapAndSend(
      address(_op), _firstAmountToSwap, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the user's OP token balance has decreased
    assertEq(_op.balanceOf(_user), _userBalance - _firstAmountToSwap);

    // Check that the USDC is on the bridge
    uint256 _usdcBalance = IERC20(_usdc).balanceOf(address(_refTokenBridge));

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
      address(_op), _secondAmountToSwap, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the ref op was deployed
    _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _opChainId);
    assertEq(_refUsdc, _precalculateRefTokenAddress(address(_refTokenBridge), _refUsdcMetadata));

    uint256 _usdcBalanceSecondSwap = IERC20(_usdc).balanceOf(address(_refTokenBridge)) - _usdcBalance;

    // Compute the message that should have been relayed
    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _usdcBalanceSecondSwap, _recipient, _refUsdcMetadata);

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and send execute data to swap
   * @param _userBalance The balance of the user
   * @param _firstAmountToBridge The amount of OP to bridge first time
   */
  function test_sendAndExecuteFromOpChainToUnichain(uint256 _userBalance, uint256 _firstAmountToBridge) public {
    _firstAmountToBridge = bound(_firstAmountToBridge, 1, type(uint128).max);
    _userBalance = bound(_userBalance, _firstAmountToBridge + 1, type(uint256).max);
    uint256 _secondAmountToBridge = _userBalance - _firstAmountToBridge;

    // Set up user funds
    deal(address(_op), _user, _userBalance);

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
      _opChainId, _unichainChainId, address(_op), _firstAmountToBridge, _recipient, _executionData
    );

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _firstAmountToBridge);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refTokenMetadata));

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(address(_refTokenBridge)), 0);

    // Compute the message that should have been relayed
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _firstAmountToBridge, _recipient, _refTokenMetadata, _executionData
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
      _opChainId, _unichainChainId, address(_op), _secondAmountToBridge, _recipient, _executionData
    );

    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _firstAmountToBridge + _secondAmountToBridge);

    _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _secondAmountToBridge, _recipient, _refTokenMetadata, _executionData
    );

    // Check that the message hash is correct
    _messageHash = _computeMessageHash(_message, 1, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send OP to Unichain and send execute data to swap through the executor
   * @param _userBalance The balance of the user
   */
  function test_sendAndExecuteFromOpChainToUnichainThroughExecutor(uint256 _userBalance) public {
    // Cant be fuzzed because the pool doesn't have enough liquidity
    uint128 _firstAmountToSwap = 1 ether;
    uint128 _secondAmountToSwap = 2 ether;
    _userBalance = bound(_userBalance, _firstAmountToSwap + _secondAmountToSwap + 1, type(uint256).max);

    // Set up user funds
    deal(address(_op), _user, _userBalance);

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
      address(_op), _firstAmountToSwap, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the user's OP token balance has decreased
    assertEq(_op.balanceOf(_user), _userBalance - _firstAmountToSwap);

    // Check that the USDC is on the bridge
    uint256 _usdcBalance = IERC20(_usdc).balanceOf(address(_refTokenBridge));

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
      address(_op), _secondAmountToSwap, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );

    // Check that the ref op was deployed
    _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _opChainId);
    assertEq(_refUsdc, _precalculateRefTokenAddress(address(_refTokenBridge), _refUsdcMetadata));

    uint256 _usdcBalanceSecondSwap = IERC20(_usdc).balanceOf(address(_refTokenBridge)) - _usdcBalance;

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
   * @notice Test that the bridge can send OP to Unichain and send execute data to swap through the executor
   */
  function test_sendFromOpChainToUnichainThroughExecutorWithRefToken() public {
    uint256 _amountToRelay = 100_000 ether;
    uint256 _amountToSwap = 1 ether;

    // Create the ref token metadata
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);

    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_amountToRelay, 0, _opRefTokenMetadata);

    // Relay the usdc ref token
    _relayToGetRefToken(_amountToRelay, 1, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _amountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _amountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(address(_refOp), address(_refUsdc), _amountToRelay, _amountToRelay);
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
      _refTokenBridge.relayAndExecute.selector, _amountToSwap, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint128 _fixUsdcSwapped = 614_726;
    // Check that the ref usdc is got to the user
    assertEq(IERC20(_refUsdc).balanceOf(_user), _fixUsdcSwapped);

    // Create the swap params
    _v4SwapParams = _createV4SwapParams(address(_refOp));

    // Only send the usdc to the op chain
    _executionData.destinationExecutor = address(0);

    // Swap and send the usdc to the op chain
    vm.startPrank(_user);
    IERC20(_refUsdc).approve(address(_uniSwapExecutor), _fixUsdcSwapped);
    _uniSwapExecutor.swapAndSend(
      address(_refUsdc), _fixUsdcSwapped, abi.encode(_v4SwapParams), _unichainChainId, _recipient, _executionData
    );
    vm.stopPrank();

    // Check that the usdc is sent to the op chain
    assertEq(IERC20(_refUsdc).balanceOf(_user), 0);

    uint256 _fixOpSwapped = 994_006_798_483_961_118;

    // Create the message to be relayed
    _message = abi.encodeWithSelector(_refTokenBridge.relay.selector, _fixOpSwapped, _recipient, _opRefTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
  }

  /**
   * @notice Test that the bridge can send and execute a swap from OpChain to Unichain through the executor
   */
  function test_sendAndExecuteFromOpChainToUnichainThroughExecutorWithRefToken() public {
    uint256 _amountToRelay = 100_000 ether;
    uint256 _amountToSwap = 1 ether;

    // Create the ref token metadata
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);

    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_amountToRelay, 0, _opRefTokenMetadata);

    // Relay the usdc ref token
    _relayToGetRefToken(_amountToRelay, 1, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _amountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _amountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(address(_refOp), address(_refUsdc), _amountToRelay, _amountToRelay);
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
      _refTokenBridge.relayAndExecute.selector, _amountToSwap, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint128 _fixUsdcSwapped = 614_726;
    // Check that the ref usdc is got to the user
    assertEq(IERC20(_refUsdc).balanceOf(_user), _fixUsdcSwapped);

    // Create the swap params
    _v4SwapParams = IUniSwapExecutor.V4SwapExactInParams({
      tokenOut: address(_refOp),
      fee: 3000, // 0.3%
      tickSpacing: 60, // Stable pairs
      amountOutMin: 0,
      deadline: type(uint48).max
    });

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

    uint256 _fixOpSwapped = 994_006_798_483_961_118;

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
   * @notice Test that the bridge can relay OP from OpChain to Unichain and deploy a RefToken for OP when the ref token is not deployed
   * @param _amountToBridge The amount of OP to relay
   */
  function test_relayOpFromOpChainToUnichainWithRefTokenNotDeployed(uint256 _amountToBridge) public {
    vm.chainId(_unichainChainId);
    _amountToBridge = bound(_amountToBridge, 1, type(uint256).max);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Relay OP from OpChain
    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

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
  function test_relayOpFromOpChainToUnichainWithRefTokenDeployed(
    uint256 _amountToBridge,
    uint256 _firstAmountToBridge
  ) public {
    vm.chainId(_unichainChainId);
    _firstAmountToBridge = bound(_firstAmountToBridge, 1, type(uint128).max);
    _amountToBridge = bound(_amountToBridge, _firstAmountToBridge, type(uint256).max);
    uint256 _secondAmountToBridge = _amountToBridge - _firstAmountToBridge;

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _firstAmountToBridge, _recipient, _refTokenMetadata);

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 0, _unichainChainId);

    // Relay OP from OpChain first time and deploy ref token
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(IERC20(_refOp).balanceOf(_recipient), _firstAmountToBridge);

    // Check that ref op was deployed and is the same as the precomputed ref token address
    assertEq(_refOp, _precalculateRefTokenAddress(address(_refTokenBridge), _refTokenMetadata));

    _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _secondAmountToBridge, _recipient, _refTokenMetadata);
    (_sentMessage, _identifier) = _messageAndIdentifier(_message, 1, _unichainChainId);

    // Relay OP from OpChain second time
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _firstAmountToBridge + _secondAmountToBridge);

    // Check that ref op was deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
  }

  /**
   * @notice Test that the bridge can relay a message from unichain to op chain and execute a swap
   */
  function test_relayAndExecuteToOpChainAndSwap() public {
    uint256 _amountToRelay = 100_000 ether;
    uint256 _amountToSwap = 1 ether;

    // Create the ref token metadata
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);

    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_amountToRelay, 0, _opRefTokenMetadata);

    // Relay the usdc ref token
    _relayToGetRefToken(_amountToRelay, 1, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _amountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _amountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(address(_refOp), address(_refUsdc), _amountToRelay, _amountToRelay);
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
      _refTokenBridge.relayAndExecute.selector, _amountToSwap, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint256 _fixUsdcSwapped = 614_726;
    // Check that the ref usdc is got to the user
    assertEq(IERC20(_refUsdc).balanceOf(_user), _fixUsdcSwapped);

    // Check that the ref op token is swapped
    assertEq(IERC20(_refOp).balanceOf(_user), 0);
  }

  /**
   * @notice Test that the bridge can relay a message from op chain to unichain and execute a swap and send the usdc to the destination chain in unichain
   */
  function test_relayAndExecuteToOpChainAndSwapAndSendToDestination() public {
    uint256 _amountToRelay = 100_000 ether;
    uint256 _amountToSwap = 1 ether;

    // Create the ref token metadata
    IRefToken.RefTokenMetadata memory _opRefTokenMetadata = _createRefTokenMetadata(address(_op), _unichainChainId);

    IRefToken.RefTokenMetadata memory _usdcRefTokenMetadata = _createRefTokenMetadata(address(_usdc), _unichainChainId);

    // Relay the op ref token
    _relayToGetRefToken(_amountToRelay, 0, _opRefTokenMetadata);

    // Relay the usdc ref token
    _relayToGetRefToken(_amountToRelay, 1, _usdcRefTokenMetadata);

    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _unichainChainId);
    address _refUsdc = _refTokenBridge.nativeToRefToken(address(_usdc), _unichainChainId);

    // Check that the ref token is on the recipient
    assertEq(IERC20(_refOp).balanceOf(_recipient), _amountToRelay);
    assertEq(IERC20(_refUsdc).balanceOf(_recipient), _amountToRelay);

    // Create the pool and mint the position
    vm.startPrank(_recipient);
    _createPoolAndMintPosition(address(_refOp), address(_refUsdc), _amountToRelay, _amountToRelay);
    vm.stopPrank();

    // Create the swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_refUsdc));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_uniSwapExecutor),
      destinationChainId: _unichainChainId,
      data: abi.encode(_v4SwapParams),
      refundAddress: _refund
    });

    // Create the message to be relayed to execute a swap, now the recipient is the user
    bytes memory _message = abi.encodeWithSelector(
      _refTokenBridge.relayAndExecute.selector, _amountToSwap, _user, _opRefTokenMetadata, _executionData
    );

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, 2, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);

    uint256 _fixUsdcSwapped = 614_726;

    // Create the message to be relayed to final destination
    _message = abi.encodeWithSelector(RefTokenBridge.relay.selector, _fixUsdcSwapped, _user, _usdcRefTokenMetadata);

    // Check that the message hash is correct
    bytes32 _messageHash = _computeMessageHash(_message, 0, _opChainId, _unichainChainId);

    // Check that the message hash is correct
    assertEq(true, _l2ToL2CrossDomainMessenger.sentMessages(_messageHash));
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

    // Check that the total supply of the ref token is 0 in the native chain
    assertEq(IERC20(_refOp).totalSupply(), 0);

    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(RefTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

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
    assertEq(_op.balanceOf(_recipient), _amountToBridge);
    assertEq(_op.balanceOf(address(_refTokenBridge)), 0);
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
   * @notice Helper function to create the v4 swap params
   * @param _tokenOut The token to swap to
   * @return _v4SwapParams The v4 swap params
   */
  function _createV4SwapParams(address _tokenOut) internal pure returns (IUniSwapExecutor.V4SwapExactInParams memory) {
    return IUniSwapExecutor.V4SwapExactInParams({
      tokenOut: _tokenOut,
      fee: 3000, // 0.3%
      tickSpacing: 60, // Stable pairs
      amountOutMin: 0,
      deadline: type(uint48).max
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
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) internal {
    // Create the message to be relayed
    bytes memory _message =
      abi.encodeWithSelector(_refTokenBridge.relay.selector, _amountToBridge, _recipient, _refTokenMetadata);

    // Create the message and identifier for the relay message and the identifier for the sent message
    (bytes memory _sentMessage, Identifier memory _identifier) = _messageAndIdentifier(_message, _nonce, _opChainId);

    // Relay the message
    _l2ToL2CrossDomainMessenger.relayMessage(_identifier, _sentMessage);
  }

  /**
   * @notice Helper function to create the pool and mint a position
   */
  function _createPoolAndMintPosition(address _token0, address _token1, uint256 _amount0, uint256 _amount1) internal {
    IPositionManager _positionManager = IPositionManager(0x3C3Ea4B57a46241e54610e5f022E5c45859A1017);

    // approve permit2 as a spender
    IERC20(_token0).approve(address(_uniSwapExecutor.PERMIT2()), type(uint256).max);
    IERC20(_token1).approve(address(_uniSwapExecutor.PERMIT2()), type(uint256).max);

    // approve `PositionManager` as a spender
    IAllowanceTransfer(address(_uniSwapExecutor.PERMIT2())).approve(
      _token0, address(_positionManager), type(uint160).max, type(uint48).max
    );
    IAllowanceTransfer(address(_uniSwapExecutor.PERMIT2())).approve(
      _token1, address(_positionManager), type(uint160).max, type(uint48).max
    );

    // Create the params for the multicall
    bytes[] memory _params = new bytes[](2);

    bool _zeroForOne = _token0 < _token1;

    // Create the pool key
    PoolKey memory _poolKey = PoolKey({
      currency0: _zeroForOne ? Currency.wrap(_token0) : Currency.wrap(_token1),
      currency1: _zeroForOne ? Currency.wrap(_token1) : Currency.wrap(_token0),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    // Fixed value for the sqrt price usdc 1 op 0.5
    uint160 _sqrtPriceX96 = 560_227_709_747_861_399_344_248;
    _params[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, _poolKey, _sqrtPriceX96);

    // Create the actions
    bytes memory _actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

    // Create the mint params
    bytes[] memory _mintParams = new bytes[](2);

    // Fixed values for the pool
    int24 _tickLower = -285_540;
    int24 _tickUpper = -281_160;
    uint128 _liquidity = 10 ether;

    _amount0 = _zeroForOne ? _amount0 : _amount1;
    _amount1 = _zeroForOne ? _amount1 : _amount0;

    // Create the mint params
    _mintParams[0] = abi.encode(_poolKey, _tickLower, _tickUpper, _liquidity, _amount0, _amount1, _recipient, '');

    // Create the mint params
    _mintParams[1] = abi.encode(_poolKey.currency0, _poolKey.currency1);

    // Create the deadline
    uint256 _deadline = block.timestamp + 60;
    _params[1] =
      abi.encodeWithSelector(_positionManager.modifyLiquidities.selector, abi.encode(_actions, _mintParams), _deadline);

    _positionManager.multicall(_params);
  }
}
