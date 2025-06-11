// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
   * @notice The decimals of the native asset
   */
  uint8 internal immutable _NATIVE_ASSET_DECIMALS;

  /**
   * @notice The name of the native asset
   */
  string public nativeAssetName;

  /**
   * @notice The symbol of the native asset
   */
  string public nativeAssetSymbol;

  /**
   * @notice Constructs the RefToken contract
   * @param _refTokenBridge The address of the RefTokenBridge contract
   * @param _nativeAssetChainId The chain id where the native asset is locked
   * @param _nativeAssetName The name of the native asset
   * @param _nativeAssetSymbol The symbol of the native asset
   * @param _nativeAssetDecimals The decimals of the native asset
   */
  constructor(
    address _refTokenBridge,
    uint256 _nativeAssetChainId,
    string memory _nativeAssetName,
    string memory _nativeAssetSymbol,
    uint8 _nativeAssetDecimals
  ) {
    REF_TOKEN_BRIDGE = IRefTokenBridge(_refTokenBridge);
    NATIVE_ASSET_CHAIN_ID = _nativeAssetChainId;
    nativeAssetName = _nativeAssetName;
    nativeAssetSymbol = _nativeAssetSymbol;
    _NATIVE_ASSET_DECIMALS = _nativeAssetDecimals;
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
   * @return _name The RefToken name
   */
  function name() public view override returns (string memory _name) {
    _name = string.concat('RefToken (', nativeAssetName, ')');
  }

  /**
   * @notice The symbol of the RefToken, composed by a predefined string and the native asset symbol
   * @return _symbol The RefToken symbol
   */
  function symbol() public view override returns (string memory _symbol) {
    _symbol = string.concat('REF-', nativeAssetSymbol);
  }

  /**
   * @notice The decimals of the RefToken, matching the native asset decimals
   * @return _decimals The RefToken decimals
   */
  function decimals() public view override returns (uint8 _decimals) {
    _decimals = _NATIVE_ASSET_DECIMALS;
  }

  /**
   * @notice Mints RefToken's to the specified address or unlocks the native asset if the caller is the
   *         SuperchainTokenBridge and the chain id is the native asset one
   * @param _to The address to mint the RefToken to
   * @param _amount The amount of RefToken to mint
   */
  function _mint(address _to, uint256 _amount) internal override {
    if (msg.sender == PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE && block.chainid == NATIVE_ASSET_CHAIN_ID) {
      REF_TOKEN_BRIDGE.unlock(address(this), _to, _amount);
    } else {
      super._mint(_to, _amount);
    }
  }

  /**
   * @notice Sets Permit2 contract's allowance at infinity.
   * @return _supportsPermit2 True since this token supports Permit2
   */
  function _givePermit2InfiniteAllowance() internal view virtual override returns (bool _supportsPermit2) {
    _supportsPermit2 = true;
  }
}
