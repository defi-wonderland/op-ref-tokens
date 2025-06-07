// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IExecutor
 * @notice Interface for the Executor
 */
interface IExecutor {
  /**
   * @notice Executes the given data
   * @param _data The data to execute
   */
  function execute(bytes calldata _data) external;
}
