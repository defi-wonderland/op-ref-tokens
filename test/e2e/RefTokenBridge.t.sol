// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console} from 'forge-std/Console.sol';
import {StdUtils} from 'forge-std/StdUtils.sol';
import {Test} from 'forge-std/Test.sol';
import {Vm, VmSafe} from 'forge-std/Vm.sol';

import {Relayer} from '@interop-lib/src/test/Relayer.sol';

import {Hashing} from '@interop-lib/src/libraries/Hashing.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';

import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';

import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IRefTokenBridge, RefTokenBridge} from 'contracts/RefTokenBridge.sol';
import {UniSwapExecutor} from 'contracts/external/UniSwapExecutor.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';
import {PrecomputeRefToken} from 'test/utils/PrecomputeRefToken.t.sol';

import {IAllowanceTransfer} from '@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IPoolInitializer_v4} from '@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';

import {
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

contract E2ERefTokenBridgeTest is StdUtils, Test, Relayer, PrecomputeRefToken {
  bytes32 internal _salt = vm.envBytes32('REF_TOKEN_BRIDGE_SALT');
  RefTokenBridge internal _opRefTokenBridge;
  RefTokenBridge internal _unichainRefTokenBridge;
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

  // Run against supersim locally so forking is fast
  string[] internal _rpcUrls = ['http://127.0.0.1:9545', 'http://127.0.0.1:9546'];

  constructor() Relayer(_rpcUrls) {
    _chainA = forkIds[0];
    _chainB = forkIds[1];
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
  }

  /**
   * @notice Test send and execute in the op chain and relay and execute in the unichain chain
   * @dev This test will create a pool with the ref op token and usdc in the unichain chain, send the op to the op chain, relay and execute in the unichain chain
   * and check that the ref token is deployed and the pool is created
   */
  function test_sendAndExecuteInOpChainAndRelayAndExecuteInUnichain() public {
    // Create the pool with the ref op token and usdc in the unichain chain
    _createPoolOpRefTokenAndUSDCInUnichain();

    // After the pool is created, send the op from the op chain and relay and execute in the unichain chain
    vm.selectFork(_chainA);

    uint256 _amountToSwap = 1 ether;

    // Set up user funds
    deal(address(_opOptimism), _user, _amountToSwap);

    IUniSwapExecutor.V4SwapExactInParams memory _v4SwapParams = _createV4SwapParams(address(_usdcUnichain));

    // Create the execution data
    IRefTokenBridge.ExecutionData memory _executionData = IRefTokenBridge.ExecutionData({
      destinationExecutor: address(_unichainUniSwapExecutor),
      destinationChainId: UNI_CHAIN_ID,
      refundAddress: _refund,
      data: abi.encode(_v4SwapParams)
    });

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _amountToSwap);
    _opRefTokenBridge.sendAndExecute(
      OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _amountToSwap, _recipient, _executionData
    );
    vm.stopPrank();

    // After the op is sent, relay and execute in the unichain chain
    vm.selectFork(_chainB);

    // Relay the op to the unichain chain
    vm.startPrank(_relayer);
    relayAllMessages();
    vm.stopPrank();

    // Check that the recipient received the usdc in unichain
    assertGt(IERC20(_usdcUnichain).balanceOf(_recipient), _v4SwapParams.amountOutMin);
  }

  /**
   * @notice Helper function to create the ref token metadata
   * @param _token The token to create the metadata for
   * @param _chainId The chain id of the token
   * @return _refTokenMetadata The ref token metadata
   */
  function _createRefTokenMetadata(
    address _token,
    uint256 _chainId
  ) internal view returns (IRefToken.RefTokenMetadata memory _refTokenMetadata) {
    _refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: _token,
      nativeAssetChainId: _chainId,
      nativeAssetName: IERC20(_token).name(),
      nativeAssetSymbol: IERC20(_token).symbol(),
      nativeAssetDecimals: IERC20(_token).decimals()
    });
  }

  /**
   * @notice Helper function to create the v4 swap params
   * @param _tokenOut The token to swap to
   * @return _v4SwapParams The v4 swap params
   */
  function _createV4SwapParams(address _tokenOut) internal pure returns (IUniSwapExecutor.V4SwapExactInParams memory) {
    return IUniSwapExecutor.V4SwapExactInParams({
      tokenOut: _tokenOut,
      fee: 3000, // 0.3%
      tickSpacing: 60, // Stable pairs
      amountOutMin: 0,
      deadline: type(uint48).max
    });
  }

  /**
   * @notice Helper function to create the pool with the ref op token and usdc in the unichain chain
   */
  function _createPoolOpRefTokenAndUSDCInUnichain() internal {
    // Send and execute in the op chain
    vm.selectFork(_chainA);

    uint256 _amountToRelay = 10_000 ether;

    // Set up user funds
    deal(address(_opOptimism), _user, _amountToRelay);

    IRefToken.RefTokenMetadata memory _refOpTokenMetadata = _createRefTokenMetadata(address(_opOptimism), OP_CHAIN_ID);

    // Send the op to the op chain
    vm.startPrank(_user);
    _opOptimism.approve(address(_opRefTokenBridge), _amountToRelay);
    _opRefTokenBridge.send(OP_CHAIN_ID, UNI_CHAIN_ID, address(_opOptimism), _amountToRelay, _poolDeployer);
    vm.stopPrank();

    vm.selectFork(_chainB);
    // Set up user funds
    deal(address(_usdcUnichain), _poolDeployer, _amountToRelay);

    // Relay the op to the unichain chain
    vm.startPrank(_relayer);
    relayAllMessages();
    vm.stopPrank();

    // Check that the ref token is deployed
    address _refOpUnichain = _precalculateRefTokenAddress(address(_unichainRefTokenBridge), _refOpTokenMetadata);

    // Check balances of the pool deployer
    assertEq(IERC20(_refOpUnichain).balanceOf(_poolDeployer), _amountToRelay);
    assertEq(_usdcUnichain.balanceOf(_poolDeployer), _amountToRelay);

    vm.startPrank(_poolDeployer);
    _createPoolAndMintPosition(
      _unichainUniSwapExecutor, address(_refOpUnichain), address(_usdcUnichain), _amountToRelay, _amountToRelay
    );
    vm.stopPrank();
  }

  /**
   * @notice Helper function to create the pool and mint a position
   * @param _uniSwapExecutor The uni swap executor
   * @param _token0 The token0
   * @param _token1 The token1
   * @param _amount0 The amount0
   * @param _amount1 The amount1
   */
  function _createPoolAndMintPosition(
    IUniSwapExecutor _uniSwapExecutor,
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1
  ) internal {
    // approve permit2 as a spender
    IERC20(_token0).approve(address(_uniSwapExecutor.PERMIT2()), type(uint256).max);
    IERC20(_token1).approve(address(_uniSwapExecutor.PERMIT2()), type(uint256).max);

    // approve `PositionManager` as a spender
    IAllowanceTransfer(address(_uniSwapExecutor.PERMIT2())).approve(
      _token0, address(_unichainPositionManager), type(uint160).max, type(uint48).max
    );
    IAllowanceTransfer(address(_uniSwapExecutor.PERMIT2())).approve(
      _token1, address(_unichainPositionManager), type(uint160).max, type(uint48).max
    );

    // Create the params for the multicall
    bytes[] memory _params = new bytes[](2);

    bool _zeroForOne = _token0 < _token1;

    // Create the pool key
    PoolKey memory _poolKey = PoolKey({
      currency0: _zeroForOne ? Currency.wrap(_token0) : Currency.wrap(_token1),
      currency1: _zeroForOne ? Currency.wrap(_token1) : Currency.wrap(_token0),
      fee: 3000,
      tickSpacing: 60,
      hooks: IHooks(address(0))
    });

    // Fixed value for the sqrt price: 1 OP ~= 0.5 USDC (currency0=USDC, currency1=OP)
    uint160 _sqrtPriceX96 = 112_045_541_949_572_279_869_449_664;
    _params[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, _poolKey, _sqrtPriceX96);

    // Create the actions
    bytes memory _actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

    // Create the mint params
    bytes[] memory _mintParams = new bytes[](2);

    // Fixed values for the pool - wider range around current tick (-131231), divisible by tickSpacing (60)
    int24 _tickLower = -139_980; // 60 * -2333, below current price
    int24 _tickUpper = -120_000; // 60 * -2000, above current price
    uint128 _liquidity = 10 ether;

    // Use maximum amounts - let the pool calculate the exact amounts needed
    uint256 _amount0Max = _zeroForOne ? _amount0 : _amount1;
    uint256 _amount1Max = _zeroForOne ? _amount1 : _amount0;

    // Create the mint params
    _mintParams[0] = abi.encode(_poolKey, _tickLower, _tickUpper, _liquidity, _amount0Max, _amount1Max, _recipient, '');

    // Create the mint params
    _mintParams[1] = abi.encode(_poolKey.currency0, _poolKey.currency1);

    // Create the deadline
    uint256 _deadline = block.timestamp + 60;
    _params[1] = abi.encodeWithSelector(
      _unichainPositionManager.modifyLiquidities.selector, abi.encode(_actions, _mintParams), _deadline
    );

    _unichainPositionManager.multicall(_params);
  }
}
