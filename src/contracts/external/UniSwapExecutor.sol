// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Commands} from '@uniswap/universal-router/contracts/libraries/Commands.sol';
import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';

import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IV4Router} from '@uniswap/v4-periphery/src/interfaces/IV4Router.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';

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
   * @notice The Universal Router address
   */
  IUniversalRouter public immutable ROUTER;

  /**
   * @notice The L2 to L2 cross domain messenger address
   */
  IL2ToL2CrossDomainMessenger public immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER;

  /**
   * @notice The RefTokenBridge address
   */
  IRefTokenBridge public immutable REF_TOKEN_BRIDGE;

  /**
   * @notice The PoolManager address
   */
  IPoolManager public immutable POOL_MANAGER;

  /**
   * @notice The Permit2 address
   */
  IPermit2 public immutable PERMIT2;

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
   * @notice Constructor
   * @param _router The Universal Router address
   * @param _poolManager The PoolManager address
   * @param _l2ToL2CrossDomainMessenger The L2 to L2 cross domain messenger address
   * @param _refTokenBridge The RefTokenBridge address
   * @param _permit2 The Permit2 address
   */
  constructor(
    IUniversalRouter _router,
    IPoolManager _poolManager,
    IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger,
    IRefTokenBridge _refTokenBridge,
    IPermit2 _permit2
  ) {
    ROUTER = _router;
    POOL_MANAGER = _poolManager;
    L2_TO_L2_CROSS_DOMAIN_MESSENGER = _l2ToL2CrossDomainMessenger;
    REF_TOKEN_BRIDGE = _refTokenBridge;
    PERMIT2 = _permit2;
  }

  /**
   * @notice Executes a V4 swap
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
    (address _nativeAsset,,,,) = REF_TOKEN_BRIDGE.refTokenMetadata(_token);
    if (_nativeAsset == address(0)) revert UniSwapExecutor_InvalidToken();

    // Execute the swap
    (address _tokenOut, uint256 _amountOut) = _executeSwap(_token, _amount, _data);

    // If the destination chain is the same as the current chain, transfer the token to the recipient
    if (block.chainid == _destinationChainId) {
      IERC20(_tokenOut).transfer(_recipient, _amountOut);
    } else {
      // If the destination chain is not the same as the current chain, send the token to the destination chain
      REF_TOKEN_BRIDGE.send(
        IRefTokenBridge.RefTokenBridgeData({
          token: _tokenOut,
          recipient: _recipient,
          amount: _amountOut,
          destinationExecutor: address(0)
        }),
        _destinationChainId
      );

      emit SentToDestinationChain(_tokenOut, _amountOut, _recipient, _destinationChainId);
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
    uint256 _amount,
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
        amountIn: uint128(_amount),
        amountOutMinimum: uint128(_v4Params.amountOutMin),
        hookData: abi.encode('')
      })
    );

    _params[1] = abi.encode(_inputCurrency, _amount);
    _params[2] = abi.encode(_outputCurrency, _v4Params.amountOutMin);

    // Set the actions for the router
    _inputs[0] = abi.encode(ACTIONS, _params);

    // Transfer the token from the RefTokenBridge to the executor and approve the router
    IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    PERMIT2.approve(_token, address(ROUTER), uint160(_amount), uint48(_v4Params.deadline));

    // Execute the swap
    ROUTER.execute(COMMANDS, _inputs, _v4Params.deadline);

    _tokenOut = _v4Params.tokenOut;

    _amountOut = IERC20(_tokenOut).balanceOf(address(this));
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
    _inputCurrency = Currency.wrap(_zeroForOne ? _tokenIn : _params.tokenOut);
    _outputCurrency = Currency.wrap(_zeroForOne ? _params.tokenOut : _tokenIn);

    _poolKey = PoolKey({
      currency0: _inputCurrency,
      currency1: _outputCurrency,
      fee: _params.fee,
      tickSpacing: _params.tickSpacing,
      hooks: IHooks(address(0))
    });
  }
}
