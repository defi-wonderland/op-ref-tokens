// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Encoding
/// @notice Encoding handles Optimism's various different encoding schemes.
library Encoding {
  /// @notice Adds a version number into the first two bytes of a message nonce.
  /// @param _nonce   Message nonce to encode into.
  /// @param _version Version number to encode into the message nonce.
  /// @return Message nonce with version encoded into the first two bytes.
  function encodeVersionedNonce(uint240 _nonce, uint16 _version) internal pure returns (uint256) {
    uint256 nonce;
    assembly {
      nonce := or(shl(240, _version), _nonce)
    }
    return nonce;
  }
}
