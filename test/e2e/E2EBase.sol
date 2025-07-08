// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Relayer} from '@interop-lib/src/test/Relayer.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IRefTokenBridge, RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';
import {Test} from 'forge-std/Test.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';
import {UniswapV4Pool} from 'test/utils/UniswapV4Pool.t.sol';

import {IAllowanceTransfer} from '@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IPoolInitializer_v4} from '@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';

import {
  BASE_CHAIN_ID,
  OP_CHAIN_ID,
  OP_TOKEN_OPTIMISM,
  UNISWAP_V4_POOL_MANAGER_OPTIMISM,
  UNISWAP_V4_POOL_MANAGER_UNICHAIN,
  UNISWAP_V4_ROUTER_OPTIMISM,
  UNISWAP_V4_ROUTER_UNICHAIN,
  UNI_CHAIN_ID,
  USDC_TOKEN_OPTIMISM,
  USDC_TOKEN_UNICHAIN
} from 'src/utils/Constants.sol';

contract E2EBase is Test, Relayer, PrecomputeRefToken, UniswapV4Pool {
  bytes32 internal _salt = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');
  RefTokenBridge internal _opRefTokenBridge;
  RefTokenBridge internal _unichainRefTokenBridge;
  RefTokenBridge internal _baseRefTokenBridge;

  UniSwapExecutor internal _opUniSwapExecutor;
  UniSwapExecutor internal _unichainUniSwapExecutor;

  IPositionManager internal _unichainPositionManager = IPositionManager(0x4529A01c7A0410167c5740C487A8DE60232617bf);
  IERC20 internal _opOptimism = IERC20(OP_TOKEN_OPTIMISM);
  IERC20 internal _usdcOptimism = IERC20(USDC_TOKEN_OPTIMISM);
  IERC20 internal _usdcUnichain = IERC20(USDC_TOKEN_UNICHAIN);

  address internal _poolDeployer = makeAddr('poolDeployer');
  address internal _user = makeAddr('user');
  address internal _recipient = makeAddr('recipient');
  address internal _refund = makeAddr('refund');
  address internal _relayer = vm.addr(uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a));

  uint256 internal _chainA;
  uint256 internal _chainB;
  uint256 internal _chainC;

  // Run against supersim locally so forking is fast
  string[] internal _rpcUrls = ['http://127.0.0.1:9545', 'http://127.0.0.1:9546', 'http://127.0.0.1:9547'];

  constructor() Relayer(_rpcUrls) {
    _chainA = forkIds[0];
    _chainB = forkIds[1];
    _chainC = forkIds[2];
  }

  function setUp() public virtual {
    // Deploy RefTokenBridge and UniSwapExecutor contracts on the op chain
    vm.selectFork(_chainA);
    _opRefTokenBridge = new RefTokenBridge{salt: _salt}();
    _opUniSwapExecutor =
      new UniSwapExecutor(UNISWAP_V4_ROUTER_OPTIMISM, UNISWAP_V4_POOL_MANAGER_OPTIMISM, address(_opRefTokenBridge));

    // Deploy RefTokenBridge contract on the unichain chain
    vm.selectFork(_chainB);
    _unichainRefTokenBridge = new RefTokenBridge{salt: _salt}();
    _unichainUniSwapExecutor = new UniSwapExecutor(
      UNISWAP_V4_ROUTER_UNICHAIN, UNISWAP_V4_POOL_MANAGER_UNICHAIN, address(_unichainRefTokenBridge)
    );

    // Deploy RefTokenBridge contract on the base chain
    vm.selectFork(_chainC);
    _baseRefTokenBridge = new RefTokenBridge{salt: _salt}();
  }
}
