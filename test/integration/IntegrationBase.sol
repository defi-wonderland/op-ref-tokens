// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {EIP1967Helper} from './external/EIP1967Helper.sol';
import {MockL2ToL2CrossDomainMessenger as L2ToL2CrossDomainMessenger} from
  './external/MockL2ToL2CrossDomainMessenger.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {Deploy} from 'script/Deploy.sol';
import {OP_CHAIN_ID, OP_TOKEN, UNI_CHAIN_ID, USDC_TOKEN} from 'src/utils/OptimismConstants.sol';
import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';

contract IntegrationBase is Deploy, Test, PrecomputeRefToken {
  uint256 internal constant _OPTIMISM_FORK_BLOCK = 137_639_140;

  L2ToL2CrossDomainMessenger internal _l2ToL2CrossDomainMessenger =
    L2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  IERC20 internal _op;
  IERC20 internal _usdc;
  address internal _user;
  address internal _recipient;
  address internal _refund;

  uint256 internal _unichainChainId;
  uint256 internal _opChainId;
  bytes internal _swapData;

  IUniSwapExecutor.V4SwapExactInParams internal _v4SwapParams;
  IRefToken.RefTokenMetadata internal _refTokenMetadata;
  IRefTokenBridge.ExecutionData internal _executionData;

  function setUp() public virtual override {
    run();

    EIP1967Helper.setImplementation(
      PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger())
    );

    _user = makeAddr('user');
    _recipient = makeAddr('recipient');
    _refund = makeAddr('refund');

    _op = OP_TOKEN;
    _usdc = USDC_TOKEN;
    _unichainChainId = UNI_CHAIN_ID;
    _opChainId = OP_CHAIN_ID;

    vm.createSelectFork(vm.rpcUrl('optimism'), _OPTIMISM_FORK_BLOCK);

    // Create the ref token metadata
    _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_op),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _op.name(),
      nativeAssetSymbol: _op.symbol(),
      nativeAssetDecimals: _op.decimals()
    });

    // Create the origin swap data
    _v4SwapParams = IUniSwapExecutor.V4SwapExactInParams({
      tokenOut: address(_usdc),
      fee: 3000, // 0.3%
      tickSpacing: 60, // Stable pairs
      amountOutMin: 0,
      deadline: type(uint48).max
    });
  }
}
