// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';
import {UNISWAP_V4_POOL_MANAGER, UNISWAP_V4_ROUTER} from 'src/utils/OptimismConstants.sol';

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
