// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IExecutor
 * @notice Interface for the Executor
 */
interface IExecutor {
  /**
   * @notice Executes the given data
   * @param _token The token to be executed, either the native asset or the RefToken
   * @param _recipient The recipient of the token after execution
   * @param _amount The amount of token to be executed
   * @param _destinationChainId The chain Id of the next step after execution
   * @param _data The data to execute
   */
  function execute(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external;
}
