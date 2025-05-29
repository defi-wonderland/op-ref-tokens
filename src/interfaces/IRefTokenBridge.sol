// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IRefTokenBridge {
  /**
   * @notice Event emitted when a message is sent
   * @dev If data is empty, just send token to the destination chain
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationChainId The destination chain ID
   */
  event MessageSent(address indexed _token, uint256 _amount, address indexed _recipient, uint256 _destinationChainId);

  /**
   * @notice Event emitted when a message is relayed
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationChainId The destination chain ID
   */
  event MessageRelayed(
    address indexed _token, uint256 _amount, address indexed _recipient, uint256 _destinationChainId
  );

  /**
   * @notice Data structure for the RefTokenBridge
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationChainId The destination chain ID
   */
  struct RefTokenBridgeData {
    address _token;
    uint256 _amount;
    address _recipient;
    uint256 _destinationChainId;
  }

  /**
   * @notice Send token to the destination chain and execute in the executor destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _data The data to be executed on the destination chain
   */
  function sendAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external;

  /**
   * @notice Send token to the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   */
  function sendToken(RefTokenBridgeData calldata _refTokenBridgeData) external;

  /**
   * @notice Relay message from the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _data The data to be executed
   */
  function relayMessage(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external;
}
