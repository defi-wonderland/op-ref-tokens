// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {Script} from 'forge-std/Script.sol';

contract Deploy is Script {
  RefTokenBridge internal _refTokenBridge;

  /// @notice Deployment parameters for each chain
  function setUp() public virtual {}

  function run() public {
    vm.startBroadcast();

    _refTokenBridge = new RefTokenBridge();

    vm.stopBroadcast();
  }
}
