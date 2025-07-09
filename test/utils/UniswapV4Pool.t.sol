// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IAllowanceTransfer} from '@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol';

import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {IPoolInitializer_v4} from '@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {IUniSwapExecutor} from 'interfaces/external/IUniSwapExecutor.sol';

/**
 * @title UniswapV4Pool
 * @notice Contains helper functions to create a pool and mint a position on Uniswap V4
 */
contract UniswapV4Pool {
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
   * @notice Helper function to create the pool and mint a position
   * @param _positionManager The address of the position manager
   * @param _uniSwapExecutor The address of the uni swap executor
   * @param _recipient The address of the recipient
   * @param _token0 The address of the first token
   * @param _token1 The address of the second token
   * @param _amount0 The amount of the first token
   * @param _amount1 The amount of the second token
   * @param _sqrtPriceX96 The sqrt price x96
   * @param _tickLower The lower tick
   * @param _tickUpper The upper tick
   */
  function _createPoolAndMintPosition(
    IPositionManager _positionManager,
    IUniSwapExecutor _uniSwapExecutor,
    address _recipient,
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1,
    uint160 _sqrtPriceX96,
    int24 _tickLower,
    int24 _tickUpper,
    uint128 _liquidity
  ) internal {
    // approve permit2 as a spender
    IERC20(_token0).approve(address(_uniSwapExecutor.PERMIT2()), type(uint256).max);
    IERC20(_token1).approve(address(_uniSwapExecutor.PERMIT2()), type(uint256).max);

    // approve `PositionManager` as a spender
    IAllowanceTransfer(address(_uniSwapExecutor.PERMIT2())).approve(
      _token0, address(_positionManager), type(uint160).max, type(uint48).max
    );
    IAllowanceTransfer(address(_uniSwapExecutor.PERMIT2())).approve(
      _token1, address(_positionManager), type(uint160).max, type(uint48).max
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

    IPositionManager _avoidStackTooDeepPositionManager = _positionManager;

    // Fixed value for the sqrt price usdc 1 OP ~= 0.5 USDC
    _params[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, _poolKey, _sqrtPriceX96);

    // Create the actions
    bytes memory _actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

    address _avoidStackTooDeepRecipient = _recipient;

    // Create the mint params
    bytes[] memory _mintParams = new bytes[](2);

    uint256 _amount0Liquidity = _zeroForOne ? _amount0 : _amount1;
    uint256 _amount1Liquidity = _zeroForOne ? _amount1 : _amount0;

    // Create the mint params
    _mintParams[0] = abi.encode(
      _poolKey,
      _tickLower,
      _tickUpper,
      _liquidity,
      _amount0Liquidity,
      _amount1Liquidity,
      _avoidStackTooDeepRecipient,
      ''
    );

    // Create the mint params
    _mintParams[1] = abi.encode(_poolKey.currency0, _poolKey.currency1);

    // Create the deadline
    uint256 _deadline = block.timestamp + 60;
    _params[1] = abi.encodeWithSelector(
      _avoidStackTooDeepPositionManager.modifyLiquidities.selector, abi.encode(_actions, _mintParams), _deadline
    );

    _avoidStackTooDeepPositionManager.multicall(_params);
  }
}
