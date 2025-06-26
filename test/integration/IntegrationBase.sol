// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IL2ToL2CrossDomainMessenger, L2ToL2CrossDomainMessenger} from './external/L2ToL2CrossDomainMessenger.sol';

import {EIP1967Helper} from './external/EIP1967Helper.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {Deploy} from 'script/Deploy.sol';
import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';

contract IntegrationBase is Deploy, Test, PrecomputeRefToken {
  uint256 internal constant _OPTIMISM_FORK_BLOCK = 137_639_140;

  L2ToL2CrossDomainMessenger internal _l2ToL2CrossDomainMessenger;

  IERC20 internal _op;
  address internal _user;
  address internal _recipient;

  uint256 internal _unichainChainId;
  uint256 internal _opChainId;

  function setUp() public virtual override {
    run();

    _l2ToL2CrossDomainMessenger = new L2ToL2CrossDomainMessenger();

    EIP1967Helper.setImplementation(
      PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(_l2ToL2CrossDomainMessenger)
    );

    IL2ToL2CrossDomainMessenger(_l2ToL2CrossDomainMessenger).setCrossDomainMessageSender(address(_refTokenBridge));

    _user = makeAddr('user');
    _recipient = makeAddr('recipient');

    _op = IERC20(0x4200000000000000000000000000000000000042);
    _unichainChainId = 130;
    _opChainId = 10;

    vm.createSelectFork(vm.rpcUrl('optimism'), _OPTIMISM_FORK_BLOCK);
  }
}
