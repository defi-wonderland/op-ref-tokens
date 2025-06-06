// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IRefTokenBridge {
  /**
   * @notice Data structure for the RefTokenBridge
   * @param token The token to be bridged
   * @param amount The amount of token to be bridged
   * @param recipient The recipient of the bridged token
   * @param destinationExecutor The destination executor
   */
  struct RefTokenBridgeData {
    address token;
    uint256 amount;
    address recipient;
    address destinationExecutor;
  }

  /**
   * @notice Data structure for the RefToken metadata
   * @param nativeAssetChainId The chain ID of the native asset
   * @param nativeAssetName The name of the native asset
   * @param nativeAssetSymbol The symbol of the native asset
   * @param nativeAssetDecimals The decimals of the native asset
   */
  struct RefTokenMetadata {
    uint256 nativeAssetChainId;
    string nativeAssetName;
    string nativeAssetSymbol;
    uint8 nativeAssetDecimals;
  }

  /**
   * @notice Event emitted when tokens are locked
   * @param _token The token to be locked
   * @param _amount The amount of tokens to be locked
   */
  event TokensLocked(address indexed _token, uint256 _amount);

  /**
   * @notice Event emitted when tokens are burned
   * @param _token The token to be burned
   * @param _amount The amount of tokens to be burned
   */
  event TokensBurned(address indexed _token, uint256 _amount);

  /**
   * @notice Event emitted when tokens are unlocked
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of tokens to be unlocked
   */
  event TokensUnlocked(address indexed _token, address indexed _to, uint256 _amount);

  /**
   * @notice Event emitted when a message is sent
   * @dev If data is empty, just send token to the destination chain
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationExecutor The destination executor
   * @param _destinationChainId The destination chain ID
   */
  event MessageSent(
    address indexed _token,
    uint256 _amount,
    address indexed _recipient,
    address indexed _destinationExecutor,
    uint256 _destinationChainId
  );

  /**
   * @notice Event emitted when a message is relayed
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationExecutor The destination executor
   * @param _destinationChainId The destination chain ID
   */
  event MessageRelayed(
    address indexed _token,
    uint256 _amount,
    address indexed _recipient,
    address indexed _destinationExecutor,
    uint256 _destinationChainId
  );

  /**
   * @notice Error emitted when the RefTokenBridgeData is invalid
   */
  error RefTokenBridge_InvalidData();

  /**
   * @notice Error emitted when the amount is invalid
   */
  error RefTokenBridge_InvalidAmount();

  /**
   * @notice Error emitted when the message is invalid
   */
  error RefTokenBridge_InvalidMessage();

  /**
   * @notice Error emitted when the sender is invalid
   */
  error RefTokenBridge_InvalidSender();

  /**
   * @notice Get the L2 to L2 cross domain messenger address
   * @return _l2ToL2CrossDomainMessenger The L2 to L2 cross domain messenger address
   */
  function L2_TO_L2_CROSS_DOMAIN_MESSENGER()
    external
    view
    returns (IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger);

  /**
   * @notice Get the RefToken metadata
   * @param _token The token to get the metadata from
   * @return _nativeAssetChainId The chain ID of the native asset
   * @return _nativeAssetName The name of the native asset
   * @return _nativeAssetSymbol The symbol of the native asset
   */
  function refTokenMetadata(address _token)
    external
    view
    returns (uint256 _nativeAssetChainId, string memory _nativeAssetName, string memory _nativeAssetSymbol);

  /**
   * @notice Send token to the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _destinationChainId The destination chain ID
   */
  function send(RefTokenBridgeData calldata _refTokenBridgeData, uint256 _destinationChainId) external;

  /**
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _destinationChainId The destination chain ID
   * @param _data The data to be executed on the destination chain
   */
  function sendAndExecute(
    RefTokenBridgeData calldata _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external;

  /**
   * @notice Relay token from the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   */
  function relay(RefTokenBridgeData calldata _refTokenBridgeData) external;
  // TODO: Check naming, change relay for something better
  /**
   * @notice Relay message from the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _data The data to be executed
   */
  function relayAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external;

  /**
   * @notice Unlocks the token on the origin chain
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _token, address _to, uint256 _amount) external;
}
