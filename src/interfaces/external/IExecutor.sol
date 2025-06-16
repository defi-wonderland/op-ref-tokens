// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IExecutor
 * @notice Interface for the Executor
 */
interface IExecutor {
  /**
   * @notice Executes the given data
   * @param _token The token to execute
   * @param _recipient The recipient of the token
   * @param _amount The amount of token to execute
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
}
