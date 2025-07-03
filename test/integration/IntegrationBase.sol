// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {EIP1967Helper} from './external/EIP1967Helper.sol';
import {MockL2ToL2CrossDomainMessenger as L2ToL2CrossDomainMessenger} from
  './external/MockL2ToL2CrossDomainMessenger.sol';
import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';

import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';
import {Test} from 'forge-std/Test.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {DeployRefTokenBridge} from 'script/RefTokenBridgeDeploy.s.sol';
import {DeployUniSwapExecutor} from 'script/UniSwapExecutorDeploy.s.sol';
import {OP_CHAIN_ID, OP_TOKEN, UNI_CHAIN_ID, USDC_TOKEN} from 'src/utils/OptimismConstants.sol';
import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';

contract IntegrationBase is DeployRefTokenBridge, Test, PrecomputeRefToken {
  uint256 internal constant _OPTIMISM_FORK_BLOCK = 137_639_140;

  L2ToL2CrossDomainMessenger internal _l2ToL2CrossDomainMessenger =
    L2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  IERC20 internal _op = IERC20(OP_TOKEN);
  IERC20 internal _usdc = IERC20(USDC_TOKEN);
  address internal _user = makeAddr('user');
  address internal _recipient = makeAddr('recipient');
  address internal _refund = makeAddr('refund');
  uint256 internal _unichainChainId = UNI_CHAIN_ID;
  uint256 internal _opChainId = OP_CHAIN_ID;

  // The min amount out for the swap
  uint128 internal _amountOutMin = 542_700;
  // The total amount out of USDC that will be swapped on this specific fixed block
  uint256 internal _fixAmountOut = 542_800;

  UniSwapExecutor internal _uniSwapExecutor;
  IRefToken.RefTokenMetadata internal _refTokenMetadata;
  IRefToken.RefTokenMetadata internal _refUsdcMetadata;
  IRefTokenBridge.ExecutionData internal _executionData;
  IUniSwapExecutor.V4SwapExactInParams internal _v4SwapParams;
  bytes internal _swapData;

  function setUp() public virtual {
    // Deploy the RefTokenBridge
    run();

    // Deploy the UniSwapExecutor
    DeployUniSwapExecutor deployUniSwapExecutor = new DeployUniSwapExecutor();
    _uniSwapExecutor = deployUniSwapExecutor.deploy(address(_refTokenBridge));

    EIP1967Helper.setImplementation(
      PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger())
    );

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
      amountOutMin: _amountOutMin, // Min amount out
      deadline: type(uint48).max
    });

    // Create ref token metadata for the usdc
    _refUsdcMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: address(_usdc),
      nativeAssetChainId: _opChainId,
      nativeAssetName: _usdc.name(),
      nativeAssetSymbol: _usdc.symbol(),
      nativeAssetDecimals: _usdc.decimals()
    });
  }
}
