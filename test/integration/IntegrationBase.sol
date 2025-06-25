// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {Deploy} from 'script/Deploy.sol';

contract IntegrationBase is Deploy, Test {
  uint256 internal constant _OPTIMISM_FORK_BLOCK = 137_000_000;

  IERC20 internal _op;
  address internal _user;
  address internal _recipient;

  uint256 internal _unichainChainId;
  uint256 internal _opChainId;

  function setUp() public virtual override {
    // Run deployment script
    super.setUp();
    run();

    _user = makeAddr('user');
    _recipient = makeAddr('recipient');

    _op = IERC20(0x4200000000000000000000000000000000000042);
    _unichainChainId = 130;
    _opChainId = 10;

    vm.createSelectFork(vm.rpcUrl('optimism'), _OPTIMISM_FORK_BLOCK);
  }
}
