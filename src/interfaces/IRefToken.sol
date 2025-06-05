// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ISuperchainERC20} from '@interop-lib/src/interfaces/ISuperchainERC20.sol';

interface IRefToken is ISuperchainERC20 {
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
  function REF_TOKEN_BRIDGE() external view returns (address _refTokenBridge);

  /**
   * @notice The chain id where the native asset is locked
   * @return _nativeAssetChainId The native asset chain id
   */
  function NATIVE_ASSET_CHAIN_ID() external view returns (uint256 _nativeAssetChainId);

  /**
   * @notice The decimals of the native asset
   * @return _nativeAssetDecimals The native asset decimals
   */
  function NATIVE_ASSET_DECIMALS() external view returns (uint8 _nativeAssetDecimals);

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
   * @notice The name of the RefToken, composed by a predefined string and the native asset name
   * @return _name The RefToken name
   */
  function name() external view returns (string memory _name);

  /**
   * @notice The symbol of the RefToken, composed by a predefined string and the native asset symbol
   * @return _symbol The RefToken symbol
   */
  function symbol() external view returns (string memory _symbol);

  /**
   * @notice The decimals of the RefToken, matching the native asset decimals
   * @return _decimals The RefToken decimals
   */
  function decimals() external view returns (uint8 _decimals);
}
