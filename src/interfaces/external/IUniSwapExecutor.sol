// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IUniversalRouter} from '@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol';

import {IPermit2} from '@uniswap/permit2/src/interfaces/IPermit2.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';
import {IExecutor} from 'interfaces/external/IExecutor.sol';
import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

/**
 * @title IUniSwapExecutor
 * @notice Interface for the UniSwapExecutor
 */
interface IUniSwapExecutor is IExecutor {
  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters for the V4 swap exact in
   * @param tokenOut The token to swap to
   * @param fee The fee to use for the swap
   * @param tickSpacing The tick spacing to use for the swap
   * @param amountOutMin The minimum amount of tokens to receive
   * @param deadline The deadline for the swap
   */
  struct V4SwapExactInParams {
    address tokenOut;
    uint24 fee;
    int24 tickSpacing;
    uint128 amountOutMin;
    uint48 deadline;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Event emitted when a swap is executed
   * @param _tokenIn The token in
   * @param _amountIn The amount in
   * @param _tokenOut The token out
   * @param _amountOut The amount out
   */
  event SwapExecuted(address indexed _tokenIn, uint256 _amountIn, address indexed _tokenOut, uint256 _amountOut);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Error emitted when the output amount is insufficient
   */
  error UniSwapExecutor_InsufficientOutputAmount();

  /**
   * @notice Error emitted when the caller is invalid
   */
  error UniSwapExecutor_InvalidCaller();

  /**
   * @notice Error emitted when the amount is too large
   */
  error UniSwapExecutor_AmountTooLarge();

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Get the Universal Router address
   * @return _router The Universal Router address
   */
  function ROUTER() external view returns (IUniversalRouter _router);

  /**
   * @notice Get the PoolManager address
   * @return _poolManager The PoolManager address
   */
  function POOL_MANAGER() external view returns (IPoolManager _poolManager);

  /**
   * @notice Get the L2 to L2 cross domain messenger address
   * @return _l2ToL2CrossDomainMessenger The L2 to L2 cross domain messenger address
   */
  function L2_TO_L2_CROSS_DOMAIN_MESSENGER()
    external
    view
    returns (IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger);

  /**
   * @notice Get the RefTokenBridge address
   * @return _refTokenBridge The RefTokenBridge address
   */
  function REF_TOKEN_BRIDGE() external view returns (IRefTokenBridge _refTokenBridge);

  /**
   * @notice Get the Permit2 address
   * @return _permit2 The Permit2 address
   */
  function PERMIT2() external view returns (IPermit2 _permit2);

  /**
   * @notice Get the commands to execute in the Universal Router
   * @return _commands The commands to execute in the Universal Router
   */
  function COMMANDS() external view returns (bytes memory _commands);

  /**
   * @notice Get the actions to execute in the Universal Router
   * @return _actions The actions to execute in the Universal Router
   */
  function ACTIONS() external view returns (bytes memory _actions);

  /*///////////////////////////////////////////////////////////////
                            FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Executes a Uniswap V4 swap and then either transfers the token to the recipient or sends it to the
   *         destination chain through the RefTokenBridge
   * @param _token The token to swap
   * @param _recipient The recipient of the token
   * @param _amount The amount of token to swap
   * @param _destinationChainId The destination chain ID
   * @param _data The data to execute
   */
  function execute(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external;

  /**
   * @notice Swaps and bridges the token to the relay chain through the RefTokenBridge
   * @param _tokenIn The input token to be swapped
   * @param _amountIn The amount of token to be swapped
   * @param _originSwapData The data to be executed on the origin chain swap before bridging the assets
   * @param _relayChainId The destination chain ID
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _executionData The data for execution on the destination chain
   */
  function bridgeAndSend(
    address _tokenIn,
    uint128 _amountIn,
    bytes calldata _originSwapData,
    uint256 _relayChainId,
    address _recipient,
    IRefTokenBridge.ExecutionData calldata _executionData
  ) external;
}
