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
  event TokensLocked(address indexed _token, address _user, uint256 _amount);

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
   */
  event RefTokenDeployed(address indexed _refToken, address indexed _nativeAsset);

  /**
   * @notice Thrown when the amount is invalid
   */
  error RefTokenBridge_InvalidAmount();

  /**
   * @notice Thrown when the recipient is invalid
   */
  error RefTokenBridge_InvalidRecipient();

  /**
   * @notice Thrown when the destination chain id is invalid
   */
  error RefTokenBridge_InvalidDestinationChainId();

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
   * @notice Thrown when the native asset chain id does not match the block chain id when deploying a RefToken on _send
   */
  error RefTokenBridge_InvalidNativeAssetChainId();

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
   * @param _refToken The RefToken address
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   */
  function relay(
    address _refToken,
    uint256 _amount,
    address _recipient,
    address _nativeAsset,
    uint256 _nativeAssetChainId
  ) external;

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _refToken The token to be relayed
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   * @param _executionData The data to be executed on the destination chain
   */
  function relayAndExecute(
    address _refToken,
    uint256 _amount,
    address _recipient,
    address _nativeAsset,
    uint256 _nativeAssetChainId,
    ExecutionData calldata _executionData
  ) external;

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
}
