// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {E2EBase, IRefToken, IRefTokenBridge, IUniSwapExecutor} from './E2EBase.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {
  BASE_CHAIN_ID, OP_CHAIN_ID, OP_TOKEN_OPTIMISM, UNI_CHAIN_ID, USDC_TOKEN_OPTIMISM
} from 'src/utils/Constants.sol';

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

    uint256 _amountToSwap = 1 ether;

    // Set up user funds
    deal(address(_opOptimism), _user, _amountToSwap);

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

    uint256 _amountToSwap = 1 ether;

    // Set up user funds
    deal(address(_opOptimism), _user, _amountToSwap);

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
   * @notice Helper function to create the pool with the ref op token and usdc in the unichain chain
   */
  function _createPoolOpRefTokenAndUSDCInUnichain() internal {
    // Send and execute in the op chain
    vm.selectFork(_chainA);

    uint256 _amountToRelay = 10_000 ether;

    // Set up user funds
    deal(address(_opOptimism), _user, _amountToRelay);

    IRefToken.RefTokenMetadata memory _refOpTokenMetadata =
      _precalculateRefTokenMetadata(address(_opOptimism), OP_CHAIN_ID);

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _amountToRelay);
    _opRefTokenBridge.send(OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _amountToRelay, _poolDeployer);
    vm.stopPrank();

    vm.selectFork(_chainB);
    // Set up user funds
    deal(address(_usdcUnichain), _poolDeployer, _amountToRelay);

    // Relay the op to the unichain chain
    vm.startPrank(_relayer);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref token is deployed
    address _refOpUnichain = _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadata);

    // Check balances of the pool deployer
    assertEq(IERC20(_refOpUnichain).balanceOf(_poolDeployer), _amountToRelay);
    assertEq(_usdcUnichain.balanceOf(_poolDeployer), _amountToRelay);

    vm.startPrank(_poolDeployer);
    uint160 _sqrtPriceX96 = 112_045_541_949_572_279_869_449_664;
    int24 _tickLower = -139_980; // 60 * -2333, below current price
    int24 _tickUpper = -120_000; // 60 * -2000, above current price
    uint128 _liquidity = 10 ether;

    _createPoolAndMintPosition(
      _unichainPositionManager,
      _unichainUniSwapExecutor,
      _recipient,
      address(_refOpUnichain),
      address(_usdcUnichain),
      _amountToRelay,
      _amountToRelay,
      _sqrtPriceX96,
      _tickLower,
      _tickUpper,
      _liquidity
    );
    vm.stopPrank();
  }
}
