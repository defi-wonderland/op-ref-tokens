// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SuperchainERC20} from '@interop-lib/src/SuperchainERC20.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {Unauthorized} from '@interop-lib/src/libraries/errors/CommonErrors.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';

/**
 * @title RefToken
 * @notice A SuperchainERC20-compatible reference token for bridging locked native assets and ERC-20s across OP-Stack
 *         chains. Issues RefTokens via the RefTokenBridge and enables arbitrary execution on destination chains upon
 *         receipt.
 */
contract RefToken is SuperchainERC20 {
  /**
   * @notice The address of the RefTokenBridge contract
   */
  IRefTokenBridge public immutable REF_TOKEN_BRIDGE;

  /**
   * @notice The chain id where the native asset is locked
   */
  uint256 public immutable NATIVE_ASSET_CHAIN_ID;

  /**
   * @notice The name of the native asset
   */
  string public NATIVE_ASSET_NAME;

  /**
   * @notice The symbol of the native asset
   */
  string public NATIVE_ASSET_SYMBOL;

  // TODO: Native asset address and decimals as metadata? No needed in the logic.

  /**
   * @notice Constructs the RefToken contract
   * @param _refTokenBridge The address of the RefTokenBridge contract
   * @param _nativeAssetChainId The chain id where the native asset is locked
   * @param _nativeAssetName The name of the native asset
   * @param _nativeAssetSymbol The symbol of the native asset
   */
  constructor(
    address _refTokenBridge,
    uint256 _nativeAssetChainId,
    string memory _nativeAssetName,
    string memory _nativeAssetSymbol
  ) {
    REF_TOKEN_BRIDGE = IRefTokenBridge(_refTokenBridge);
    NATIVE_ASSET_CHAIN_ID = _nativeAssetChainId;
    NATIVE_ASSET_NAME = _nativeAssetName;
    NATIVE_ASSET_SYMBOL = _nativeAssetSymbol;
  }

  /**
   * @notice Mints RefToken's to the specified address
   * @param _to The address to mint the RefToken to
   * @param _amount The amount of RefToken to mint
   */
  function mint(address _to, uint256 _amount) external {
    if (msg.sender != address(REF_TOKEN_BRIDGE)) revert Unauthorized();
    _mint(_to, _amount);
  }

  /**
   * @notice Burns RefToken's from the specified address
   * @param _from The address to burn the RefToken from
   * @param _amount The amount of RefToken to burn
   */
  function burn(address _from, uint256 _amount) external {
    if (msg.sender != address(REF_TOKEN_BRIDGE)) revert Unauthorized();
    _burn(_from, _amount);
  }

  /**
   * @notice The name of the RefToken, composed by a predefined string and the native asset name
   */
  function name() public view override returns (string memory) {
    return string.concat('RefToken (', NATIVE_ASSET_NAME, ')');
  }

  /**
   * @notice The symbol of the RefToken, composed by a predefined string and the native asset symbol
   */
  function symbol() public view override returns (string memory) {
    return string.concat('REF-', NATIVE_ASSET_SYMBOL);
  }

  /**
   * @notice Mints RefToken's to the specified address or unlocks the native asset if the caller is the
   *  SuperchainTokenBridge and the chain id is the native asset one
   * @param _to The address to mint the RefToken to
   * @param _amount The amount of RefToken to mint
   */
  function _mint(address _to, uint256 _amount) internal override {
    if (msg.sender == PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE && block.chainid == NATIVE_ASSET_CHAIN_ID) {
      REF_TOKEN_BRIDGE.unlock(_to, _amount);
    } else {
      super._mint(_to, _amount);
    }
  }
}
