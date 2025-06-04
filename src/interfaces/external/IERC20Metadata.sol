// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from 'openzeppelin/token/ERC20/IERC20.sol';

/**
 * @title IRefTokenBridge
 * @notice Interface for the RefTokenBridge
 */
interface IERC20Metadata is IERC20 {
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
}
