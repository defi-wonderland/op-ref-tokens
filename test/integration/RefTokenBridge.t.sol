// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';

contract IntegrationRefTokenBridgeTest is IntegrationBase {
  function test_skip() public {
    // Delete when adding integration tests, this is just to avoid the CI failing
    vm.skip(true);
  }
}
