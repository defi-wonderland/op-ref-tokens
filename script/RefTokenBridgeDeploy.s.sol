// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {Script} from 'forge-std/Script.sol';

contract DeployRefTokenBridge is Script {
  RefTokenBridge internal _refTokenBridge;
  bytes32 internal _salt = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');

  function run() public {
    vm.startBroadcast();

    _refTokenBridge = new RefTokenBridge{salt: _salt}();

    vm.stopBroadcast();
  }
}
