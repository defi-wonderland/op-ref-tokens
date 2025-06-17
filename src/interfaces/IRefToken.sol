// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';

/**
 * @title IRefToken
 * @notice Interface for the RefToken
 */
interface IRefToken {
  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Data structure for the RefToken metadata
   * @param nativeAsset The address of the native asset
   * @param nativeAssetChainId The chain ID of the native asset
   * @param nativeAssetName The name of the native asset
   * @param nativeAssetSymbol The symbol of the native asset
   */
  struct RefTokenMetadata {
    address nativeAsset;
    uint256 nativeAssetChainId;
    string nativeAssetName;
    string nativeAssetSymbol;
    uint8 nativeAssetDecimals;
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Mints RefToken's to the specified address
   * @param _to The address to mint the RefToken to
   * @param _amount The amount of RefToken to mint
   */
  function mint(address _to, uint256 _amount) external;

  /**
   * @notice Burns RefToken's from the specified address
   * @param _from The address to burn the RefToken from
   * @param _amount The amount of RefToken to burn
   */
  function burn(address _from, uint256 _amount) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The address of the RefTokenBridge contract
   * @return _refTokenBridge The RefTokenBridge contract address
   */
  function REF_TOKEN_BRIDGE() external view returns (IRefTokenBridge _refTokenBridge);

  /**
   * @notice The chain id where the native asset is locked
   * @return _nativeAssetChainId The native asset chain id
   */
  function NATIVE_ASSET_CHAIN_ID() external view returns (uint256 _nativeAssetChainId);

  /**
   * @notice The name of the native asset
   * @return _nativeAssetName The native asset name
   */
  function nativeAssetName() external view returns (string memory _nativeAssetName);

  /**
   * @notice The symbol of the native asset
   * @return _nativeAssetSymbol The native asset symbol
   */
  function nativeAssetSymbol() external view returns (string memory _nativeAssetSymbol);

  /**
   * @notice The RefToken metadata
   * @return _refTokenMetadata The RefToken metadata
   */
  function metadata() external view returns (RefTokenMetadata memory _refTokenMetadata);
}
