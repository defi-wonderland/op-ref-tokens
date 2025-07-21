// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {RefToken} from 'contracts/RefToken.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';

/**
 * @title PrecomputeRefToken
 * @notice Contains helper functions to precalculate the address of the RefToken
 */
contract PrecomputeRefToken {
  /**
   * @notice Helper function to precalculate the address of the RefToken
   * @param _refTokenBridge The address of the RefTokenBridge contract
   * @param _refTokenMetadata The metadata of the RefToken
   * @return _refTokenAddress The address of the RefToken
   */
  function _precalculateRefTokenAddress(
    address _refTokenBridge,
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) internal pure returns (address _refTokenAddress) {
    bytes32 _salt = keccak256(abi.encode(_refTokenMetadata.nativeAssetChainId, _refTokenMetadata.nativeAsset));

    bytes memory _initCode = bytes.concat(type(RefToken).creationCode, abi.encode(_refTokenBridge, _refTokenMetadata));

    bytes32 _initCodeHash = keccak256(_initCode);
    _refTokenAddress = _precalculateCreate2Address(_salt, _initCodeHash, _refTokenBridge);
  }

  /**
   * @notice Helper function to precalculate and address to be deployed using the `CREATE2` opcode
   * @param _salt The 32-byte random value used to create the contract address.
   * @param _initCodeHash The 32-byte bytecode digest of the contract creation bytecode.
   * @param _deployer The 20-byte _deployer address.
   * @return _precalculatedAddress The 20-byte address where a contract will be stored.
   */
  function _precalculateCreate2Address(
    bytes32 _salt,
    bytes32 _initCodeHash,
    address _deployer
  ) internal pure returns (address _precalculatedAddress) {
    assembly ("memory-safe") {
      let _ptr := mload(0x40)
      mstore(add(_ptr, 0x40), _initCodeHash)
      mstore(add(_ptr, 0x20), _salt)
      mstore(_ptr, _deployer)
      let _start := add(_ptr, 0x0b)
      mstore8(_start, 0xff)
      _precalculatedAddress := and(keccak256(_start, 85), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
  }

  /**
   * @notice Helper function to precalculate the ref token metadata
   * @param _token The token to create the metadata for
   * @param _chainId The chain id of the token
   * @return _refTokenMetadata The ref token metadata
   */
  function _precalculateRefTokenMetadata(
    address _token,
    uint256 _chainId
  ) internal view returns (IRefToken.RefTokenMetadata memory _refTokenMetadata) {
    _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: _token,
      nativeAssetChainId: _chainId,
      nativeAssetName: IERC20(_token).name(),
      nativeAssetSymbol: IERC20(_token).symbol(),
      nativeAssetDecimals: IERC20(_token).decimals()
    });
  }
}
