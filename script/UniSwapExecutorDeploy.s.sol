// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';

import {Script} from 'forge-std/Script.sol';
import {UNISWAP_V4_POOL_MANAGER_OPTIMISM, UNISWAP_V4_ROUTER_OPTIMISM} from 'src/utils/Constants.sol';

contract DeployUniSwapExecutor is Script {
  error RefTokenBridgeNotSet();

  UniSwapExecutor internal _uniSwapExecutor;

  function run() public {
    vm.startBroadcast();

    address _refTokenBridge = vm.envAddress('REF_TOKEN_BRIDGE');
    if (_refTokenBridge == address(0)) revert RefTokenBridgeNotSet();

    _uniSwapExecutor = deploy(_refTokenBridge);

    vm.stopBroadcast();
  }

  function deploy(address _refTokenBridge) public returns (UniSwapExecutor _executor) {
    _executor = new UniSwapExecutor(UNISWAP_V4_ROUTER_OPTIMISM, UNISWAP_V4_POOL_MANAGER_OPTIMISM, _refTokenBridge);
  }
}
