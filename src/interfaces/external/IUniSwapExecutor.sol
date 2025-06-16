// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
    uint256 amountOutMin;
    uint256 deadline;
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

  /**
   * @notice Event emitted when a swap is sent to the destination chain
   * @param _tokenOut The token out
   * @param _amountOut The amount out
   * @param _recipient The recipient
   * @param _destinationChainId The destination chain id
   */
  event SentToDestinationChain(
    address indexed _tokenOut, uint256 _amountOut, address indexed _recipient, uint256 _destinationChainId
  );

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
   * @notice Error emitted when the token is invalid
   */
  error UniSwapExecutor_InvalidToken();

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
}
