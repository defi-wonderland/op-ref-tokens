// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Commands} from '@uniswap/universal-router/contracts/libraries/Commands.sol';
import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';

import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IV4Router} from '@uniswap/v4-periphery/src/interfaces/IV4Router.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {
  IL2ToL2CrossDomainMessenger,
  IPermit2,
  IPoolManager,
  IRefTokenBridge,
  IUniSwapExecutor,
  IUniversalRouter
} from 'interfaces/external/IUniSwapExecutor.sol';

/**
 * @title UniSwapExecutor
 * @notice Executes a V4 swap from the RefTokenBridge
 */
contract UniSwapExecutor is IUniSwapExecutor {
  using StateLibrary for IPoolManager;

  /**
   * @notice The L2 to L2 cross domain messenger address
   */
  IL2ToL2CrossDomainMessenger public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER =
    IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  /**
   * @notice The Permit2 address
   */
  IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

  /**
   * @notice The commands to execute in the Universal Router
   */
  bytes public constant COMMANDS = abi.encodePacked(uint8(Commands.V4_SWAP));

  /**
   * @notice The actions to execute in the Universal Router
   */
  bytes public constant ACTIONS =
    abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

  /**
   * @notice The Universal Router address
   */
  IUniversalRouter public immutable ROUTER;

  /**
   * @notice The RefTokenBridge address
   */
  IRefTokenBridge public immutable REF_TOKEN_BRIDGE;

  /**
   * @notice The PoolManager address
   */
  IPoolManager public immutable POOL_MANAGER;

  /**
   * @notice Constructor
   * @param _router The Universal Router address
   * @param _poolManager The PoolManager address
   * @param _refTokenBridge The RefTokenBridge address
   */
  constructor(IUniversalRouter _router, IPoolManager _poolManager, IRefTokenBridge _refTokenBridge) {
    ROUTER = _router;
    POOL_MANAGER = _poolManager;
    REF_TOKEN_BRIDGE = _refTokenBridge;
  }

  /**
   * @notice Executes a Uniswap V4 swap and then either transfers the token to the recipient or sends it to the
   *         destination chain through the RefTokenBridge
   * @param _token The token to swap
   * @param _recipient The recipient of the token
   * @param _amount The amount of token to swap
   * @param _destinationChainId The destination chain ID
   * @param _data The data to execute
   */
  function execute(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external {
    if (msg.sender != address(REF_TOKEN_BRIDGE)) revert UniSwapExecutor_InvalidCaller();

    if (_amount > type(uint128).max) revert UniSwapExecutor_AmountTooLarge();

    // Execute the swap
    (address _tokenOut, uint256 _amountOut) = _executeSwap(_token, uint128(_amount), _data);

    // If the destination chain is the same as the current chain, transfer the token to the recipient
    if (block.chainid == _destinationChainId) {
      IERC20(_tokenOut).transfer(_recipient, _amountOut);
    } else {
      // If the destination chain is not the same as the current chain, send the token to the destination chain
      // If the token is a RefToken, use the native asset chain ID, otherwise use the current chain ID
      uint256 _nativeAssetChainId =
        REF_TOKEN_BRIDGE.isRefTokenDeployed(_tokenOut) ? IRefToken(_tokenOut).NATIVE_ASSET_CHAIN_ID() : block.chainid;
      REF_TOKEN_BRIDGE.send(_nativeAssetChainId, _destinationChainId, _tokenOut, _amountOut, _recipient);
    }
  }

  /**
   * @notice Swaps and bridges the token to the relay chain through the RefTokenBridge
   * @param _tokenIn The input token to be swapped
   * @param _amountIn The amount of token to be swapped
   * @param _originSwapData The data to be executed on the origin chain swap before bridging the assets
   * @param _relayChainId The destination chain ID
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _executionData The data for execution on the destination chain
   */
  function swapAndSend(
    address _tokenIn,
    uint128 _amountIn,
    bytes calldata _originSwapData,
    uint256 _relayChainId,
    address _recipient,
    IRefTokenBridge.ExecutionData calldata _executionData
  ) external {
    // Execute the swap
    (address _tokenOut, uint256 _amountOut) = _executeSwap(_tokenIn, _amountIn, _originSwapData);

    // If the token is a RefToken, use the native asset chain ID, otherwise use the current chain ID
    uint256 _nativeAssetChainId =
      REF_TOKEN_BRIDGE.isRefTokenDeployed(_tokenOut) ? IRefToken(_tokenOut).NATIVE_ASSET_CHAIN_ID() : block.chainid;

    // If there is execution data, send the token and execute the data on the destination chain
    if (_executionData.destinationExecutor != address(0)) {
      REF_TOKEN_BRIDGE.sendAndExecute(
        _nativeAssetChainId, _relayChainId, _tokenOut, _amountOut, _recipient, _executionData
      );
    } else {
      // Otherwise, just send the token to the destination chain
      REF_TOKEN_BRIDGE.send(_nativeAssetChainId, _relayChainId, _tokenOut, _amountOut, _recipient);
    }
  }

  /**
   * @notice Executes a swap
   * @param _token The token to swap
   * @param _amount The amount of token to swap
   * @param _data The data to execute
   * @return _tokenOut The token out
   * @return _amountOut The amount out
   */
  function _executeSwap(
    address _token,
    uint128 _amount,
    bytes calldata _data
  ) internal returns (address _tokenOut, uint256 _amountOut) {
    bytes[] memory _inputs = new bytes[](1);

    (
      V4SwapExactInParams memory _v4Params,
      PoolKey memory _poolKey,
      bool _zeroForOne,
      Currency _inputCurrency,
      Currency _outputCurrency
    ) = _decodeV4SwapExactInParamsAndGetPoolKey(_data, _token);

    // Set the params for the router
    bytes[] memory _params = new bytes[](3);

    _params[0] = abi.encode(
      IV4Router.ExactInputSingleParams({
        poolKey: _poolKey,
        zeroForOne: _zeroForOne,
        amountIn: _amount,
        amountOutMinimum: _v4Params.amountOutMin,
        hookData: abi.encode('')
      })
    );

    _params[1] = abi.encode(_inputCurrency, _amount);
    _params[2] = abi.encode(_outputCurrency, _v4Params.amountOutMin);

    // Set the actions for the router
    _inputs[0] = abi.encode(ACTIONS, _params);

    // Transfer the token from the RefTokenBridge to the executor and approve the router
    IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    PERMIT2.approve(_token, address(ROUTER), uint160(_amount), _v4Params.deadline);

    _tokenOut = _v4Params.tokenOut;
    uint256 _balanceBefore = IERC20(_tokenOut).balanceOf(address(this));

    // Execute the swap
    ROUTER.execute(COMMANDS, _inputs, _v4Params.deadline);

    _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _balanceBefore;
    if (_amountOut < _v4Params.amountOutMin) revert UniSwapExecutor_InsufficientOutputAmount();

    emit SwapExecuted(_token, _amount, _tokenOut, _amountOut);
  }

  /**
   * @notice Decodes the V4SwapExactInParams and returns the pool key, the zero for one flag, the input currency and the output currency
   * @param _data The data to decode
   * @param _tokenIn The token in
   * @return _params The V4SwapExactInParams
   * @return _poolKey The pool key
   * @return _zeroForOne Whether the token in is less than the token out
   * @return _inputCurrency The input currency
   * @return _outputCurrency The output currency
   */
  function _decodeV4SwapExactInParamsAndGetPoolKey(
    bytes calldata _data,
    address _tokenIn
  )
    internal
    pure
    returns (
      V4SwapExactInParams memory _params,
      PoolKey memory _poolKey,
      bool _zeroForOne,
      Currency _inputCurrency,
      Currency _outputCurrency
    )
  {
    _params = abi.decode(_data, (V4SwapExactInParams));
    _zeroForOne = _tokenIn < _params.tokenOut;
    _inputCurrency = Currency.wrap(_tokenIn);
    _outputCurrency = Currency.wrap(_params.tokenOut);

    _poolKey = PoolKey({
      currency0: _zeroForOne ? _inputCurrency : _outputCurrency,
      currency1: _zeroForOne ? _outputCurrency : _inputCurrency,
      fee: _params.fee,
      tickSpacing: _params.tickSpacing,
      hooks: IHooks(address(0))
    });
  }
}
