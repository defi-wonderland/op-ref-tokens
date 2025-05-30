// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IL2ToL2CrossDomainMessenger, IRefTokenBridge} from '../interfaces/IRefTokenBridge.sol';

contract RefTokenBridge is IRefTokenBridge {
  /// @inheritdoc IRefTokenBridge
  IL2ToL2CrossDomainMessenger public immutable L2_To_L2_CDM;

  constructor(IL2ToL2CrossDomainMessenger _l2ToL2CDM) {
    L2_To_L2_CDM = _l2ToL2CDM;
  }

  /// @inheritdoc IRefTokenBridge
  function sendAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external payable {}

  /// @inheritdoc IRefTokenBridge
  function send(RefTokenBridgeData calldata _refTokenBridgeData) external payable {}

  /// @inheritdoc IRefTokenBridge
  function relayAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external {}

  /// @inheritdoc IRefTokenBridge
  function relay(RefTokenBridgeData calldata _refTokenBridgeData) external {}

  /**
   * @notice Internal function to lock the token
   * @dev This function is used to lock the token on the source chain
   * @param _token The token to be locked
   * @param _amount The amount of token to be locked
   */
  function _lock(address _token, uint256 _amount) internal {
    //
  }

  /**
   * @notice Internal function to release the token
   * @dev This function is used to release the token on the source chain
   * @param _token The token to be released
   * @param _amount The amount of token to be released
   */
  function _release(address _token, uint256 _amount) internal {
    //
  }

  /**
   * @notice Internal function to mint the RefToken
   * @dev This function is used to mint the RefToken on the destination chain
   * @param _token The token to be minted
   * @param _amount The amount of token to be minted
   */
  function _mint(address _token, uint256 _amount) internal {}

  /**
   * @notice Internal function to burn the RefToken
   * @dev This function is used to burn the RefToken on the destination chain
   * @param _token The token to be burned
   * @param _amount The amount of token to be burned
   */
  function _burn(address _token, uint256 _amount) internal {}

  /**
   * @notice Internal function to deploy the RefToken
   * @param _token The token to be deployed
   */
  function _deployRefToken(address _token) internal {}
}
