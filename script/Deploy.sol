// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from 'forge-std/Script.sol';

contract Deploy is Script {
  /// @notice Deployment parameters for each chain
  function setUp() public {}

  function run() public {
    vm.startBroadcast();
    vm.stopBroadcast();
  }
}
