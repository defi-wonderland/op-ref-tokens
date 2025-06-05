// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IRefToken {
  /**
   * @notice The address of the RefTokenBridge contract
   */
  function REF_TOKEN_BRIDGE() external view returns (address);

  /**
   * @notice The chain id where the native asset is locked
   */
  function NATIVE_ASSET_CHAIN_ID() external view returns (uint256);

  /**
   * @notice The name of the native asset
   */
  function NATIVE_ASSET_NAME() external view returns (string memory);

  /**
   * @notice The symbol of the native asset
   */
  function NATIVE_ASSET_SYMBOL() external view returns (string memory);

  /**
   * @notice The decimals of the native asset
   */
  function NATIVE_ASSET_DECIMALS() external view returns (uint8);

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

  /**
   * @notice The name of the RefToken, composed by a predefined string and the native asset name
   */
  function name() external view returns (string memory);

  /**
   * @notice The symbol of the RefToken, composed by a predefined string and the native asset symbol
   */
  function symbol() external view returns (string memory);

  /**
   * @notice The decimals of the RefToken, matching the native asset decimals
   */
  function decimals() external view returns (uint8);
}
