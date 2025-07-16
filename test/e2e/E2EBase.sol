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
  UNISWAP_V4_POSITION_MANAGER_UNICHAIN,
  UNISWAP_V4_ROUTER_OPTIMISM,
  UNISWAP_V4_ROUTER_UNICHAIN,
  USDC_TOKEN_OPTIMISM,
  USDC_TOKEN_UNICHAIN
} from 'src/utils/Constants.sol';

contract E2EBase is Test, Relayer, PrecomputeRefToken, UniswapV4Pool {
  // Pool liquidity constraints require fixed swap amounts
  uint128 internal constant _STANDARD_BRIDGE_AMOUNT = 1 ether;
  uint128 internal constant _DOUBLE_BRIDGE_AMOUNT = 2 ether;
  uint128 internal constant _STANDARD_SWAP_AMOUNT = 1 ether;
  uint128 internal constant _OP_AMOUNT_TO_RELAY = 100_000 ether;
  uint128 internal constant _USDC_AMOUNT_TO_RELAY = 50_000 * 10 ** 6;

  // Tokens and PositionManager
  IPositionManager internal constant _UNICHAIN_POSITION_MANAGER = IPositionManager(UNISWAP_V4_POSITION_MANAGER_UNICHAIN);
  IERC20 internal constant _OP_OPTIMISM = IERC20(OP_TOKEN_OPTIMISM);
  IERC20 internal constant _USDC_OPTIMISM = IERC20(USDC_TOKEN_OPTIMISM);
  IERC20 internal constant _USDC_UNICHAIN = IERC20(USDC_TOKEN_UNICHAIN);

  // Whales
  address internal constant _WHALE_IN_OPTIMISM_CHAIN = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
  address internal constant _WHALE_IN_UNICHAIN_CHAIN = 0xB5A2a236581dbd6BCECD8A25EeBFF140595f138C;

  // Immutable variables
  address internal immutable _RELAYER =
    vm.addr(uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a));
  bytes32 internal immutable _REF_TOKEN_BRIDGE_SALT = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');

  // RefTokenBridge and UniSwapExecutor contracts
  RefTokenBridge internal _opRefTokenBridge;
  RefTokenBridge internal _unichainRefTokenBridge;
  RefTokenBridge internal _baseRefTokenBridge;
  UniSwapExecutor internal _opUniSwapExecutor;
  UniSwapExecutor internal _unichainUniSwapExecutor;

  // Addresses
  address internal _poolDeployer = makeAddr('poolDeployer');
  address internal _user = makeAddr('user');
  address internal _recipient = makeAddr('recipient');
  address internal _refund = makeAddr('refund');

  // Chain IDs
  uint256 internal _optimismChainId;
  uint256 internal _unichainChainId;
  uint256 internal _baseChainId;

  string[] internal _rpcUrls = ['http://127.0.0.1:9545', 'http://127.0.0.1:9546', 'http://127.0.0.1:9547'];

  constructor() Relayer(_rpcUrls) {
    _optimismChainId = forkIds[0];
    _unichainChainId = forkIds[1];
    _baseChainId = forkIds[2];
  }

  function setUp() public virtual {
    // Deploy RefTokenBridge and UniSwapExecutor contracts on the op chain
    vm.selectFork(_optimismChainId);
    _opRefTokenBridge = new RefTokenBridge{salt: _REF_TOKEN_BRIDGE_SALT}();
    _opUniSwapExecutor =
      new UniSwapExecutor(UNISWAP_V4_ROUTER_OPTIMISM, UNISWAP_V4_POOL_MANAGER_OPTIMISM, address(_opRefTokenBridge));

    // Deploy RefTokenBridge contract on the unichain chain
    vm.selectFork(_unichainChainId);
    _unichainRefTokenBridge = new RefTokenBridge{salt: _REF_TOKEN_BRIDGE_SALT}();
    _unichainUniSwapExecutor = new UniSwapExecutor(
      UNISWAP_V4_ROUTER_UNICHAIN, UNISWAP_V4_POOL_MANAGER_UNICHAIN, address(_unichainRefTokenBridge)
    );

    // Deploy RefTokenBridge contract on the base chain
    vm.selectFork(_baseChainId);
    _baseRefTokenBridge = new RefTokenBridge{salt: _REF_TOKEN_BRIDGE_SALT}();
  }
}
