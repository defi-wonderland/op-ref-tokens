// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Relayer} from '@interop-lib/src/test/Relayer.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';
import {Test} from 'forge-std/Test.sol';

import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';
import {UniswapV4Pool} from 'test/utils/UniswapV4Pool.t.sol';

import {
  OP_TOKEN_OPTIMISM,
  UNISWAP_V4_POOL_MANAGER_OPTIMISM,
  UNISWAP_V4_POOL_MANAGER_UNICHAIN,
  UNISWAP_V4_ROUTER_OPTIMISM,
  UNISWAP_V4_ROUTER_UNICHAIN,
  USDC_TOKEN_OPTIMISM,
  USDC_TOKEN_UNICHAIN
} from 'src/utils/Constants.sol';

contract E2EBase is Test, Relayer, PrecomputeRefToken, UniswapV4Pool {
  bytes32 internal _salt = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');

  // RefTokenBridge and UniSwapExecutor contracts
  RefTokenBridge internal _opRefTokenBridge;
  RefTokenBridge internal _unichainRefTokenBridge;
  RefTokenBridge internal _baseRefTokenBridge;
  UniSwapExecutor internal _opUniSwapExecutor;
  UniSwapExecutor internal _unichainUniSwapExecutor;

  // Tokens and PositionManager
  IPositionManager internal _unichainPositionManager = IPositionManager(0x4529A01c7A0410167c5740C487A8DE60232617bf);
  IERC20 internal _opOptimism = IERC20(OP_TOKEN_OPTIMISM);
  IERC20 internal _usdcOptimism = IERC20(USDC_TOKEN_OPTIMISM);
  IERC20 internal _usdcUnichain = IERC20(USDC_TOKEN_UNICHAIN);

  // Addresses
  address internal _relayer = vm.addr(uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a));
  address internal _opWhaleInOpChain = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
  address internal _usdcWhaleInUnichainChain = 0xB5A2a236581dbd6BCECD8A25EeBFF140595f138C;
  address internal _poolDeployer = makeAddr('poolDeployer');
  address internal _user = makeAddr('user');
  address internal _recipient = makeAddr('recipient');
  address internal _refund = makeAddr('refund');

  // Chain IDs
  uint256 internal _chainA;
  uint256 internal _chainB;
  uint256 internal _chainC;

  // Amounts
  uint256 internal _amountToSwap = 1 ether;
  uint256 internal _opAmountToRelay = 100_000 ether;
  uint256 internal _usdcAmountToRelay = 50_000 * 10 ** 6;

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
