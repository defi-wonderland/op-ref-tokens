// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRefToken} from './IRefToken.sol';
import {IL2ToL2CrossDomainMessenger} from '@interop-lib/src/interfaces/IL2ToL2CrossDomainMessenger.sol';

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IRefTokenBridge {
  /**
   * @notice Data structure for the execution data
   * @param destinationExecutor The address of the destination executor
   * @param destinationChainId The chain ID of the destination chain
   * @param refundAddress The address to refund the token to if the execution fails
   * @param data The data to be executed on the destination chain
   */
  struct ExecutionData {
    address destinationExecutor;
    uint256 destinationChainId;
    address refundAddress;
    bytes data;
  }

  /**
   * @notice Event emitted when tokens are locked
   * @param _token The token to be locked
   * @param _user The address that locked the tokens
   * @param _amount The amount of tokens to be locked
   */
  event NativeAssetLocked(address indexed _token, address _user, uint256 _amount);

  /**
   * @notice Event emitted when tokens are unlocked
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of tokens to be unlocked
   */
  event NativeAssetUnlocked(address indexed _token, address indexed _to, uint256 _amount);

  /**
   * @notice Event emitted when tokens are burned
   * @param _token The token to be burned
   * @param _to The address to burn the token to
   * @param _amount The amount of tokens to be burned
   */
  event RefTokenBurned(address indexed _token, address indexed _to, uint256 _amount);
  /**
   * @notice Event emitted when tokens are minted
   * @param _token The token to be minted
   * @param _to The address to mint the token to
   * @param _amount The amount of tokens to be minted
   */
  event RefTokenMinted(address indexed _token, address indexed _to, uint256 _amount);

  /**
   * @notice Event emitted when a message is sent
   * @dev If data is empty, just send token to the destination chain
   * @param _refToken The RefToken address
   * @param _amount The amount of token to be bridged
   * @param _recipient The recipient of the bridged token
   * @param _destinationExecutor The destination executor
   * @param _executionChainId The execution chain ID
   */
  event MessageSent(
    address indexed _refToken,
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
   * @param _nativeAssetChainId The chain ID of the native asset
   */
  event RefTokenDeployed(address indexed _refToken, address indexed _nativeAsset, uint256 _nativeAssetChainId);

  /**
   * @notice Event emitted when funds are stuck on the destination chain
   * @param _recipient The recipient of the stuck funds
   * @param _nativeAsset The native asset address
   * @param _amount The amount of funds that are stuck
   */
  event StuckFunds(address indexed _recipient, address indexed _nativeAsset, uint256 _amount);

  /**
   * @notice Event emitted when stuck funds are withdrawn
   * @param _user The user to withdraw the funds from
   * @param _nativeAsset The native asset to withdraw the funds from
   * @param _amount The amount of funds that are withdrawn
   */
  event StuckFundsWithdrawn(address indexed _user, address indexed _nativeAsset, uint256 _amount);

  /**
   * @notice Thrown when the amount is invalid
   */
  error RefTokenBridge_InvalidAmount();

  /**
   * @notice Thrown when the recipient is invalid
   */
  error RefTokenBridge_InvalidRecipient();

  /**
   * @notice Thrown when the relay chain id is invalid
   */
  error RefTokenBridge_InvalidRelayChainId();

  /**
   * @notice Thrown when the execution chain id is invalid
   */
  error RefTokenBridge_InvalidExecutionChainId();

  /**
   * @notice Thrown when the destination executor is invalid
   */
  error RefTokenBridge_InvalidDestinationExecutor();

  /**
   * @notice Thrown when the caller is not authorized
   */
  error RefTokenBridge_Unauthorized();

  /**
   * @notice Thrown when the token is not the native asset
   */
  error RefTokenBridge_NotNativeAsset();

  /**
   * @notice Thrown when the native asset chain id is zero
   */
  error RefTokenBridge_InvalidNativeAssetChainId();

  /**
   * @notice Thrown when the token is not the RefToken
   */
  error RefTokenBridge_NotRefToken();

  /**
   * @notice Thrown when the refund address is invalid
   */
  error RefTokenBridge_InvalidRefundAddress();

  /**
   * @notice Thrown when there are no stuck funds
   */
  error RefTokenBridge_NoStuckFunds();

  /**
   * @notice Send token to the relay chain
   * @dev The native asset MUST implement the IERC20Metadata interface for this function to work
   * @param _nativeAssetChainId The chain ID of the native asset
   * @param _relayChainId The chain where the tokens will be relayed to
   * @param _token The input token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the relay chain
   */
  function send(
    uint256 _nativeAssetChainId,
    uint256 _relayChainId,
    address _token,
    uint256 _amount,
    address _recipient
  ) external;

  /**
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @dev The native asset MUST implement the IERC20Metadata interface for this function to work
   * @param _nativeAssetChainId The chain ID of the native asset
   * @param _relayChainId The chain where the tokens will be relayed
   * @param _token The input token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _executionData The data to be executed on the destination chain
   */
  function sendAndExecute(
    uint256 _nativeAssetChainId,
    uint256 _relayChainId,
    address _token,
    uint256 _amount,
    address _recipient,
    ExecutionData calldata _executionData
  ) external;

  /**
   * @notice Relay token from the destination chain
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _refTokenMetadata The metadata of the RefToken
   */
  function relay(uint256 _amount, address _recipient, IRefToken.RefTokenMetadata calldata _refTokenMetadata) external;

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _executionData The data to be executed on the destination chain
   */
  function relayAndExecute(
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata calldata _refTokenMetadata,
    ExecutionData calldata _executionData
  ) external;

  /**
   * @notice Withdraw stuck funds
   * @param _recipient The recipient to withdraw the funds to
   * @param _nativeAsset The native asset to withdraw the funds from
   */
  function withdrawStuckFunds(address _recipient, address _nativeAsset) external;

  /**
   * @notice Unlocks the token on the origin chain
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _token, address _to, uint256 _amount) external;

  /**
   * @notice Gets the RefToken
   * @param _token Either the native asset or the RefToken
   * @param _nativeAssetChainId The chain ID of the native asset
   * @return _refToken The address of the RefToken, zero address if the RefToken is not deployed
   */
  function getRefToken(address _token, uint256 _nativeAssetChainId) external view returns (address _refToken);

  /**
   * @notice Get the L2 to L2 cross domain messenger address
   * @return _l2ToL2CrossDomainMessenger The L2 to L2 cross domain messenger address
   */
  function L2_TO_L2_CROSS_DOMAIN_MESSENGER()
    external
    view
    returns (IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger);

  /**
   * @notice Check if the RefToken is deployed
   * @param _refToken The RefToken address
   * @return _isRefTokenDeployed Whether the RefToken is deployed
   */
  function isRefTokenDeployed(address _refToken) external view returns (bool _isRefTokenDeployed);

  /**
   * @notice Get the RefToken address
   * @param _nativeToken The native token to get the RefToken address from
   * @param _nativeAssetChainId The chain ID of the native asset
   * @return _refToken The RefToken address
   */
  function nativeToRefToken(
    address _nativeToken,
    uint256 _nativeAssetChainId
  ) external view returns (address _refToken);
}
