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

import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {DeployRefTokenBridge} from 'script/RefTokenBridgeDeploy.s.sol';
import {DeployUniSwapExecutor} from 'script/UniSwapExecutorDeploy.s.sol';
import {
  BASE_CHAIN_ID, OP_CHAIN_ID, OP_TOKEN_OPTIMISM, UNI_CHAIN_ID, USDC_TOKEN_OPTIMISM
} from 'src/utils/Constants.sol';
import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';
import {UniswapV4Pool} from 'test/utils/UniswapV4Pool.t.sol';

contract IntegrationBase is DeployRefTokenBridge, Test, PrecomputeRefToken, UniswapV4Pool {
  uint256 internal constant _OPTIMISM_FORK_BLOCK = 137_639_140;

  L2ToL2CrossDomainMessenger internal _l2ToL2CrossDomainMessenger =
    L2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  IERC20 internal _op = IERC20(OP_TOKEN_OPTIMISM);
  IERC20 internal _usdc = IERC20(USDC_TOKEN_OPTIMISM);
  address internal _user = makeAddr('user');
  address internal _recipient = makeAddr('recipient');
  address internal _refund = makeAddr('refund');
  uint256 internal _unichainChainId = UNI_CHAIN_ID;
  uint256 internal _opChainId = OP_CHAIN_ID;
  uint256 internal _baseChainId = BASE_CHAIN_ID;

  // The min amount out for the swap
  uint128 internal _amountOutMin = 542_700;
  // The total amount out of USDC that will be swapped on this specific fixed block
  uint256 internal _fixAmountOut = 542_800;

  // Fixed value for the sqrt price usdc 1 OP ~= 0.5 USDC
  uint160 internal _sqrtPriceX96 = 560_227_709_747_861_399_344_248;
  // Fixed value for the tick lower and upper
  int24 internal _tickLower = -285_540; // 60 * -4759, below current price
  int24 internal _tickUpper = -281_160; // 60 * -4686, above current price
  uint128 internal _liquidity = 10 ether;

  UniSwapExecutor internal _uniSwapExecutor;
  IRefToken.RefTokenMetadata internal _refoOpMetadata;
  IRefToken.RefTokenMetadata internal _refUsdcMetadata;
  IRefTokenBridge.ExecutionData internal _executionData;
  IUniSwapExecutor.V4SwapExactInParams internal _v4SwapParams;
  IPositionManager internal _positionManager;
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

    _positionManager = IPositionManager(0x3C3Ea4B57a46241e54610e5f022E5c45859A1017);

    vm.createSelectFork(vm.rpcUrl('optimism'), _OPTIMISM_FORK_BLOCK);

    // Create the ref token metadata
    _refoOpMetadata = IRefToken.RefTokenMetadata({
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
