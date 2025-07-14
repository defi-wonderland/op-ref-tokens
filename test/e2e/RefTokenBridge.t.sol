// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E2EBase} from './E2EBase.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IRefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {BASE_CHAIN_ID, OP_CHAIN_ID, UNI_CHAIN_ID} from 'src/utils/Constants.sol';

contract E2ERefTokenBridgeTest is E2EBase {
  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, send the op to the op chain, relay and execute in the unichain chain
   * and check that the ref token is deployed and the pool is created
   */
  function test_sendAndExecuteOpChainAndRelayAndExecuteUnichain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_chainA);

    // Set up user funds
    vm.prank(_opWhaleInOpChain);
    _opOptimism.transfer(address(_user), _amountToSwap);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_usdcUnichain));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _amountToSwap);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _amountToSwap, _recipient, _executionData
    );
    vm.stopPrank();

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_chainB);

    // Relay the op to the unichain chain
    vm.startPrank(_relayer);
    relayAllMessages();

    vm.stopPrank();

    // Check that the recipient received the usdc in unichain
    assertGt(IERC20(_usdcUnichain).balanceOf(_recipient), _v4SwapParams.amountOutMin);
  }

  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain and send to base chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, send the op to the op chain, relay and execute in the unichain chain
   * and check that the ref token is deployed and the pool is created
   */
  function test_sendAndExecuteOpChainAndRelayAndExecuteUnichainAndSendBaseChain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_chainA);

    // Set up user funds
    vm.prank(_opWhaleInOpChain);
    _opOptimism.transfer(address(_user), _amountToSwap);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_usdcUnichain));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: BASE_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _amountToSwap);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _amountToSwap, _recipient, _executionData
    );
    vm.stopPrank();

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_chainB);

    // Precalculate the ref USDC address on the base chain
    IRefToken.RefTokenMetadata memory _refUSDCMetadata =
      _precalculateRefTokenMetadata(address(_usdcUnichain), UNI_CHAIN_ID);
    address _refUSDCBase = _precalculateRefTokenAddress(address(_baseRefTokenBridge), _refUSDCMetadata);

    // Relay the op to the unichain chain
    vm.startPrank(_relayer);
    relayAllMessages();
    vm.stopPrank();

    // Relay the usdc to the base chain, the ref USDC will be deployed on the base chain
    vm.selectFork(_chainC);
    vm.startPrank(_relayer);

    relayAllMessages();

    vm.stopPrank();

    // Check that the ref USDC is deployed on the base chain
    assertEq(IERC20(_refUSDCBase).balanceOf(_refund), _v4SwapParams.amountOutMin);
  }

  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain and revert and relay back to the op chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, send the op to the op chain, relay and execute in the unichain chain
   * and check that the ref token is deployed and the pool is created, then revert the execution and relay back to the op chain
   */
  function test_sendAndExecuteOpChainAndRelayAndExecuteRevertAndRelayBackToOpChain() public {
    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_chainA);

    // Set up user funds
    vm.prank(_opWhaleInOpChain);
    _opOptimism.transfer(address(_user), _amountToSwap);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_usdcUnichain));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _amountToSwap);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _amountToSwap, _recipient, _executionData
    );
    vm.stopPrank();

    // Relay the op to the unichain chain to execute the swap
    vm.startPrank(_relayer);
    relayAllMessages();
    vm.stopPrank();

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_chainB);

    // As swap revert, the op will be returned to the op chain
    vm.startPrank(_relayer);
    relayMessages(vm.getRecordedLogs(), OP_CHAIN_ID);
    vm.stopPrank();

    vm.selectFork(_chainA);

    // Check that the refund is sent to the refund address
    assertEq(IERC20(_opOptimism).balanceOf(_refund), _amountToSwap);
  }

  /**
   * @notice Test swap op to usdc in the op chain and send to the unichain chain
   */
  function test_swapOpToUsdcInOpChainAndSendToUnichain() public {
    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_chainA);

    // Set up user funds
    vm.prank(_opWhaleInOpChain);
    _opOptimism.transfer(address(_user), _amountToSwap);

    // Create the v4 swap params
    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_usdcOptimism));

    // Empty execution data
    IRefTokenBridge.ExecutionData memory _executionData;

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opUniSwapExecutor), _amountToSwap);
    _opUniSwapExecutor.swapAndSend(
      address(_opOptimism), uint128(_amountToSwap), abi.encode(_v4SwapParams), UNI_CHAIN_ID, _recipient, _executionData
    );
    vm.stopPrank();

    // Precalculate the ref USDC address on the unichain chain
    IRefToken.RefTokenMetadata memory _refUsdcOptimismMetadata =
      _precalculateRefTokenMetadata(address(_usdcOptimism), OP_CHAIN_ID);

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_chainB);

    // As swap revert, the op will be returned to the op chain
    vm.startPrank(_relayer);
    relayMessages(vm.getRecordedLogs(), OP_CHAIN_ID);
    vm.stopPrank();

    address _refUsdcOptimismUnichain =
      _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refUsdcOptimismMetadata);

    // Check that the usdc is received in the unichain chain
    assertGt(IERC20(_refUsdcOptimismUnichain).balanceOf(_recipient), _v4SwapParams.amountOutMin);
  }

  /**
   * @notice Helper function to create the pool with the ref op token and usdc in the unichain chain
   */
  function _createPoolOpRefTokenAndUSDCInUnichain() internal {
    // Send and execute in the op chain
    vm.selectFork(_chainA);

    // Set up user funds
    vm.prank(_opWhaleInOpChain);
    _opOptimism.transfer(address(_user), _opAmountToRelay);

    IRefToken.RefTokenMetadata memory _refOpTokenMetadata =
      _precalculateRefTokenMetadata(address(_opOptimism), OP_CHAIN_ID);

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _opAmountToRelay);
    _opRefTokenBridge.send(OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _opAmountToRelay, _poolDeployer);
    vm.stopPrank();

    vm.selectFork(_chainB);

    // Set up user funds
    vm.prank(_usdcWhaleInUnichainChain);
    _usdcUnichain.transfer(address(_poolDeployer), _usdcAmountToRelay);

    // Relay the op to the unichain chain
    vm.startPrank(_relayer);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref token is deployed
    address _refOpUnichain = _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadata);

    // Check balances of the pool deployer
    assertEq(IERC20(_refOpUnichain).balanceOf(_poolDeployer), _opAmountToRelay);
    assertEq(_usdcUnichain.balanceOf(_poolDeployer), _usdcAmountToRelay);

    vm.startPrank(_poolDeployer);
    // Fixed value for the sqrt price usdc 1 OP ~= 0.5 USDC
    uint160 _sqrtPriceX96 = 1_120_455_419_495_722_798_688_496;
    // Fixed value for the tick lower and upper
    int24 _tickLower = 283_260; // 60 * 4721, below current price
    int24 _tickUpper = 283_320; // 60 * 4722, above current price
    uint128 _liquidity = 10 ether;

    _createPoolAndMintPosition(
      _unichainPositionManager,
      _unichainUniSwapExecutor,
      _recipient,
      address(_refOpUnichain),
      address(_usdcUnichain),
      _opAmountToRelay,
      _usdcAmountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();
  }
}
