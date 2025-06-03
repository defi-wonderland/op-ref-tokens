// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SuperchainERC20} from '@interop-lib/src/SuperchainERC20.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';

import {Unauthorized} from '@interop-lib/src/libraries/errors/CommonErrors.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';

contract RefToken is SuperchainERC20 {
  IRefTokenBridge public immutable REF_TOKEN_BRIDGE;
  uint256 public immutable NATIVE_ASSET_CHAIN_ID;

  string public NATIVE_ASSET_NAME;
  string public NATIVE_ASSET_SYMBOL;

  // TODO: Native asset address and decimals as metadata? No needed in the logic.

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

  function mint(address _to, uint256 _amount) external {
    if (msg.sender != address(REF_TOKEN_BRIDGE)) revert Unauthorized();
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    if (msg.sender != address(REF_TOKEN_BRIDGE)) revert Unauthorized();
    _burn(_from, _amount);
  }

  function name() public view override returns (string memory) {
    return string.concat('RefToken (', NATIVE_ASSET_NAME, ')');
  }

  function symbol() public view override returns (string memory) {
    return string.concat('REF-', NATIVE_ASSET_SYMBOL);
  }

  function _mint(address _to, uint256 _amount) internal override {
    if (msg.sender == PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE && block.chainid == NATIVE_ASSET_CHAIN_ID) {
      REF_TOKEN_BRIDGE.unlock(_to, _amount);
    } else {
      super._mint(_to, _amount);
    }
  }
}
