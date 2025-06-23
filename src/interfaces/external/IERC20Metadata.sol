// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IERC20Metadata
 * @notice Interface for the ERC20 metadata
 */
interface IERC20Metadata {
  /**
   * @notice The name of the token
   * @return _name The name of the token
   */
  function name() external view returns (string memory _name);

  /**
   * @notice The symbol of the token
   * @return _symbol The symbol of the token
   */
  function symbol() external view returns (string memory _symbol);

  /**
   * @notice The decimals of the token
   * @return _decimals The decimals of the token
   */
  function decimals() external view returns (uint8 _decimals);
}
