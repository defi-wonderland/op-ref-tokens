// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Metadata} from './IERC20Metadata.sol';

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IRefToken is IERC20Metadata {
  /**
   * @notice The native asset chain ID
   */
  function NATIVE_ASSET_CHAIN_ID() external view returns (uint256 _nativeAssetChainId);

  /**
   * @notice The native asset name
   */
  function NATIVE_ASSET_NAME() external view returns (string memory _nativeAssetName);

  /**
   * @notice The native asset symbol
   */
  function NATIVE_ASSET_SYMBOL() external view returns (string memory _nativeAssetSymbol);

  /**
   * @notice Burn the token
   * @param _amount The amount of token to burn
   */
  function burn(uint256 _amount) external;
}
