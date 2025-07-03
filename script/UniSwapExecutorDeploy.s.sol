// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';

import {Script} from 'forge-std/Script.sol';
import {UNISWAP_V4_POOL_MANAGER, UNISWAP_V4_ROUTER} from 'src/utils/OptimismConstants.sol';

contract DeployUniSwapExecutor is Script {
  UniSwapExecutor internal _uniSwapExecutor;

  function run() public {
    vm.startBroadcast();

    address _refTokenBridge = vm.envAddress('REF_TOKEN_BRIDGE');
    _uniSwapExecutor = deploy(_refTokenBridge);

    vm.stopBroadcast();
  }

  function deploy(address _refTokenBridge) public returns (UniSwapExecutor _executor) {
    _executor = new UniSwapExecutor(UNISWAP_V4_ROUTER, UNISWAP_V4_POOL_MANAGER, _refTokenBridge);
  }
}
