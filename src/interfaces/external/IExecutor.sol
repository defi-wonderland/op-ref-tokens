// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IExecutor
 * @notice Interface for the Executor
 */
interface IExecutor {
  /**
   * @notice Executes the given data
   * @param _refToken The RefToken address
   * @param _recipient The recipient of the RefToken after execution
   * @param _amount The approved amount of RefToken
   * @param _destinationChainId The chain Id of the next step after execution
   * @param _data The data to execute
   */
  function execute(
    address _refToken,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external;
}
