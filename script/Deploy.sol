// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';
import {UNISWAP_V4_POOL_MANAGER, UNISWAP_V4_ROUTER} from 'src/utils/OptimismConstants.sol';

import {Script} from 'forge-std/Script.sol';

contract Deploy is Script {
  RefTokenBridge internal _refTokenBridge;
  UniSwapExecutor internal _uniSwapExecutor;
  bytes32 internal _salt = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');

  /// @notice Deployment parameters for each chain
  function setUp() public virtual {}

  function run() public {
    vm.startBroadcast();

    _refTokenBridge = new RefTokenBridge{salt: _salt}();

    _uniSwapExecutor = new UniSwapExecutor(UNISWAP_V4_ROUTER, UNISWAP_V4_POOL_MANAGER, _refTokenBridge);

    vm.stopBroadcast();
  }
}
