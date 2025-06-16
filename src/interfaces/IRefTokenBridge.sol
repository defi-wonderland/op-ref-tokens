// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IRefTokenBridge {
  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/
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
   * @param nativeAssetAddress The address of the native asset
   * @param nativeAssetChainId The chain ID of the native asset
   * @param nativeAssetName The name of the native asset
   * @param nativeAssetSymbol The symbol of the native asset
   */
  struct RefTokenMetadata {
    address nativeAssetAddress;
    uint256 nativeAssetChainId;
    string nativeAssetName;
    string nativeAssetSymbol;
    uint8 nativeAssetDecimals;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Event emitted when tokens are locked
   * @param _token The token to be locked
   * @param _amount The amount of tokens to be locked
   */
  event TokensLocked(address indexed _token, uint256 _amount);

  /**
   * @notice Event emitted when tokens are unlocked
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of tokens to be unlocked
   */
  event TokensUnlocked(address indexed _token, address indexed _to, uint256 _amount);

  /**
   * @notice Event emitted when tokens are burned
   * @param _token The token to be burned
   * @param _to The address to burn the token to
   * @param _amount The amount of tokens to be burned
   */
  event RefTokensBurned(address indexed _token, address indexed _to, uint256 _amount);
  /**
   * @notice Event emitted when tokens are minted
   * @param _token The token to be minted
   * @param _to The address to mint the token to
   * @param _amount The amount of tokens to be minted
   */
  event RefTokensMinted(address indexed _token, address indexed _to, uint256 _amount);

  /**
   * @notice Event emitted when a message is sent
   * @dev If data is empty, just send token to the destination chain
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationExecutor The destination executor
   * @param _executionChainId The execution chain ID
   */
  event MessageSent(
    address indexed _token,
    uint256 _amount,
    address indexed _recipient,
    address indexed _destinationExecutor,
    uint256 _executionChainId
  );

  /**
   * @notice Event emitted when a message is relayed
   * @param _token The token to be bridged
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationExecutor The destination executor
   */
  event MessageRelayed(
    address indexed _token, uint256 _amount, address indexed _recipient, address indexed _destinationExecutor
  );

  /**
   * @notice Event emitted when a RefToken is deployed
   * @param _refToken The RefToken address
   * @param _nativeAsset The native asset address
   */
  event RefTokenDeployed(address indexed _refToken, address indexed _nativeAsset);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Error emitted when the amount is invalid
   */
  error RefTokenBridge_InvalidAmount();

  /**
   * @notice Error emitted when the recipient is invalid
   */
  error RefTokenBridge_InvalidRecipient();

  /**
   * @notice Error emitted when the destination chain id is invalid
   */
  error RefTokenBridge_InvalidDestinationChainId();

  /**
   * @notice Error emitted when the execution chain id is invalid
   */
  error RefTokenBridge_InvalidExecutionChainId();

  /**
   * @notice Error emitted when the destination executor is invalid
   */
  error RefTokenBridge_InvalidDestinationExecutor();

  /**
   * @notice Error emitted when the messenger is invalid
   */
  error RefTokenBridge_InvalidMessenger();

  /**
   * @notice Error emitted when the sender is invalid
   */
  error RefTokenBridge_InvalidSender();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Send token to the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _destinationChainId The destination chain ID
   */
  function send(RefTokenBridgeData calldata _refTokenBridgeData, uint256 _destinationChainId) external;

  /**
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _executionChainId The execution chain ID
   * @param _destinationChainId The destination chain ID
   * @param _refundAddress The address to refund the token to if the execution fails
   * @param _data The data to be executed on the destination chain
   */
  function sendAndExecute(
    RefTokenBridgeData calldata _refTokenBridgeData,
    uint256 _executionChainId,
    uint256 _destinationChainId,
    address _refundAddress,
    bytes memory _data
  ) external;

  /**
   * @notice Relay token from the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _refTokenMetadata The metadata of the RefToken
   */
  function relay(RefTokenBridgeData calldata _refTokenBridgeData, RefTokenMetadata calldata _refTokenMetadata) external;

  /**
   * @notice Relay message from the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _destinationChainId The destination chain ID
   * @param _refundAddress The address to refund the token to if the execution fails
   * @param _data The data to be executed
   */
  function relayAndExecute(
    RefTokenBridgeData calldata _refTokenBridgeData,
    RefTokenMetadata calldata _refTokenMetadata,
    uint256 _destinationChainId,
    address _refundAddress,
    bytes memory _data
  ) external;

  /**
   * @notice Unlocks the token on the origin chain
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _token, address _to, uint256 _amount) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

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
   * @return _nativeAssetAddress The address of the native asset
   * @return _nativeAssetChainId The chain ID of the native asset
   * @return _nativeAssetName The name of the native asset
   * @return _nativeAssetSymbol The symbol of the native asset
   * @return _nativeAssetDecimals The decimals of the native asset
   */
  function refTokenMetadata(address _token)
    external
    view
    returns (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    );

  /**
   * @notice Get the RefToken address
   * @param _nativeToken The native token to get the RefToken address from
   * @return _refToken The RefToken address
   */
  function nativeToRefToken(address _nativeToken) external view returns (address _refToken);
}
