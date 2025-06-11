// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {UniversalRouter} from '@uniswap/universal-router/contracts/UniversalRouter.sol';
import {Commands} from '@uniswap/universal-router/contracts/libraries/Commands.sol';

import {IHooks} from '@uniswap/v4-core/src/interfaces/IHooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {IV4Router} from '@uniswap/v4-periphery/src/interfaces/IV4Router.sol';
import {Actions} from '@uniswap/v4-periphery/src/libraries/Actions.sol';
import {IExecutor} from 'interfaces/external/IExecutor.sol';
import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

contract UniSwapExecutor is IExecutor {
  using StateLibrary for IPoolManager;

  struct V4SwapExactInParams {
    address tokenOut;
    uint24 fee;
    int24 tickSpacing;
    uint256 amountOutMin;
    uint256 deadline;
  }

  /**
   * @notice The Universal Router address
   */
  UniversalRouter public immutable ROUTER;

  /**
   * @notice The L2 to L2 cross domain messenger address
   */
  IL2ToL2CrossDomainMessenger public immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER;

  IPoolManager public immutable POOL_MANAGER;

  error InsufficientOutputAmount();

  constructor(
    UniversalRouter _router,
    IPoolManager _poolManager,
    IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger
  ) {
    ROUTER = _router;
    POOL_MANAGER = _poolManager;
    L2_TO_L2_CROSS_DOMAIN_MESSENGER = _l2ToL2CrossDomainMessenger;
  }

  function execute(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external {
    // Encode the Universal Router command
    bytes memory _commands = abi.encodePacked(uint8(Commands.V4_SWAP));
    bytes[] memory _inputs = new bytes[](1);

    // Encode V4Router actions
    bytes memory _actions =
      abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

    // Prepare parameters for each action
    bytes[] memory _params = new bytes[](3);

    (V4SwapExactInParams memory _v4Params, PoolKey memory _key, bool _zeroForOne) =
      _decodeV4SwapExactInParamsAndGetPoolKey(_data, _token);

    _params[0] = abi.encode(
      IV4Router.ExactInputSingleParams({
        poolKey: _key,
        zeroForOne: _zeroForOne,
        amountIn: _amount,
        amountOutMinimum: _v4Params.amountOutMin,
        deadline: _v4Params.deadline
      })
    );
    _params[1] = _zeroForOne ? abi.encode(_key.currency0, _amount) : abi.encode(_key.currency1, _amount);
    _params[2] = _zeroForOne
      ? abi.encode(_key.currency1, _v4Params.amountOutMin)
      : abi.encode(_key.currency0, _v4Params.amountOutMin);

    // Combine actions and params into inputs
    _inputs[0] = abi.encode(_actions, _params);

    // Execute the swap
    IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    IERC20(_token).approve(address(ROUTER), _amount);
    ROUTER.execute(_commands, _inputs, _v4Params.deadline);

    // Verify and return the output amount
    uint256 _amountOut =
      _zeroForOne ? IERC20(_key.currency1).balanceOf(address(this)) : IERC20(_key.currency0).balanceOf(address(this));

    if (_amountOut < _v4Params.amountOutMin) {
      revert InsufficientOutputAmount();
    }

    if (block.chainid == _destinationChainId) {
      if (_zeroForOne) {
        IERC20(_key.currency1).transfer(_recipient, _amountOut);
      } else {
        IERC20(_key.currency0).transfer(_recipient, _amountOut);
      }
    } else {
      L2_TO_L2_CROSS_DOMAIN_MESSENGER.sendMessage(_destinationChainId, abi.encode(_recipient, _amountOut));
    }
  }

  function _decodeV4SwapExactInParamsAndGetPoolKey(
    bytes calldata _data,
    address _tokenIn
  ) internal pure returns (V4SwapExactInParams memory _params, PoolKey memory _key, bool _zeroForOne) {
    _params = abi.decode(_data, (V4SwapExactInParams));

    _zeroForOne = _tokenIn < _params.tokenOut;
    _key = PoolKey({
      currency0: Currency.wrap(_zeroForOne ? _tokenIn : _params.tokenOut),
      currency1: Currency.wrap(_zeroForOne ? _params.tokenOut : _tokenIn),
      fee: _params.fee,
      tickSpacing: _params.tickSpacing,
      hooks: IHooks(address(0))
    });
  }
}
