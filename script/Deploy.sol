// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {Script} from 'forge-std/Script.sol';

contract Deploy is Script {
  RefTokenBridge internal _refTokenBridge;

  bytes32 internal _salt = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');

  /// @notice Deployment parameters for each chain
  function setUp() public virtual {}

  function run() public {
    vm.startBroadcast();

    _refTokenBridge = new RefTokenBridge{salt: _salt}();

    vm.stopBroadcast();
  }
}
