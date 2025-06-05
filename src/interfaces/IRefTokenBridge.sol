// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IRefTokenBridge {
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
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _data The data to be executed on the destination chain
   */
  function sendAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external payable;

  /**
   * @notice Send token to the destination chain to transfer tokens to the recipient
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   */
  function send(RefTokenBridgeData calldata _refTokenBridgeData) external payable;

  /**
   * @notice Relay message from the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _data The data to be executed
   */
  function relayAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external;

  /**
   * @notice Relay message from the destination chain to transfer tokens to the recipient
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   */
  function relay(RefTokenBridgeData calldata _refTokenBridgeData) external;

  // TODO: Define
  /**
   * @notice Unlocks the token on the origin chain
   * @param _recipient The recipient of the unlocked token
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _recipient, uint256 _amount) external;

  /**
   * @notice Get the L2 to L2 cross domain messenger address
   * @return _l2ToL2CrossDomainMessenger The L2 to L2 cross domain messenger address
   */
  function L2_TO_L2_CROSS_DOMAIN_MESSENGER()
    external
    view
    returns (IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger);
}
