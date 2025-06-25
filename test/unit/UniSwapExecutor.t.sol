// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {
  IERC20,
  IPermit2,
  IPoolManager,
  IRefTokenBridge,
  IUniSwapExecutor,
  IUniversalRouter,
  PredeployAddresses,
  UniSwapExecutor
} from 'contracts/external/UniSwapExecutor.sol';

import {IAllowanceTransfer} from 'lib/permit2/src/interfaces/IAllowanceTransfer.sol';

contract UniSwapExecutorUnit is Helpers {
  // Contract
  IRefTokenBridge public refTokenBridge;
  IUniversalRouter public universalRouter;
  IPoolManager public poolManager;
  IPermit2 public permit2;
  IUniSwapExecutor public uniSwapExecutor;

  function setUp() external {
    refTokenBridge = IRefTokenBridge(makeAddr('RefTokenBridge'));
    universalRouter = IUniversalRouter(makeAddr('UniversalRouter'));
    poolManager = IPoolManager(makeAddr('PoolManager'));
    permit2 = IPermit2(makeAddr('Permit2'));

    uniSwapExecutor = new UniSwapExecutor(universalRouter, poolManager, refTokenBridge, permit2);
  }

  function test_ConstructorWhenConstructorIsSet(
    IUniversalRouter _router,
    IPoolManager _poolManager,
    IRefTokenBridge _refTokenBridge,
    IPermit2 _permit2
  ) external {
    uniSwapExecutor = new UniSwapExecutor(_router, _poolManager, _refTokenBridge, _permit2);

    assertEq(address(uniSwapExecutor.ROUTER()), address(_router));
    assertEq(address(uniSwapExecutor.POOL_MANAGER()), address(_poolManager));
    assertEq(
      address(uniSwapExecutor.L2_TO_L2_CROSS_DOMAIN_MESSENGER()), PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER
    );
    assertEq(address(uniSwapExecutor.REF_TOKEN_BRIDGE()), address(_refTokenBridge));
    assertEq(address(uniSwapExecutor.PERMIT2()), address(_permit2));
  }

  function test_ExecuteRevertWhen_CallerIsNotTheRefTokenBridge(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external {
    vm.expectRevert(abi.encodeWithSelector(IUniSwapExecutor.UniSwapExecutor_InvalidCaller.selector));
    uniSwapExecutor.execute(_token, _recipient, _amount, _destinationChainId, _data);
  }

  function test_ExecuteRevertWhen_AmountOutAfterTheSwapIsLessThanTheMinimumAmountOut(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    _assumeFuzzable(_token);
    _assumeFuzzable(_params.tokenOut);
    vm.assume(_params.tokenOut > _token);

    _amount = bound(_amount, 1, type(uint128).max);
    _params.amountOutMin = bound(_params.amountOutMin, _amount + 1, type(uint160).max);
    _params.deadline = bound(_params.deadline, 0, type(uint48).max);

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(permit2),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    _mockAndExpect(
      _params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector, uniSwapExecutor), abi.encode(_amount)
    );

    vm.expectRevert(abi.encodeWithSelector(IUniSwapExecutor.UniSwapExecutor_InsufficientOutputAmount.selector));
    vm.prank(address(refTokenBridge));
    uniSwapExecutor.execute(_token, _recipient, _amount, _destinationChainId, _data);
  }

  function test_ExecuteWhenDestinationChainIsTheSameAsTheCurrentChain(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    _assumeFuzzable(_token);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);
    vm.assume(_params.tokenOut > _token);

    _params.amountOutMin = 0;
    _amount = bound(_amount, 1, type(uint160).max);
    _params.deadline = bound(_params.deadline, 0, type(uint48).max);

    _destinationChainId = block.chainid;

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(permit2),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    vm.mockCall(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(true));

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    _mockAndExpect(
      _params.tokenOut,
      abi.encodeWithSelector(IERC20.transfer.selector, _recipient, _params.amountOutMin),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SwapExecuted(_token, _amount, _params.tokenOut, _params.amountOutMin);

    vm.prank(address(refTokenBridge));
    uniSwapExecutor.execute(_token, _recipient, _amount, _destinationChainId, _data);
  }

  function test_ExecuteWhenDestinationChainIsNotTheSameAsTheCurrentChain(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    _assumeFuzzable(_token);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);
    vm.assume(_params.tokenOut > _token);

    _params.amountOutMin = 0;
    _amount = bound(_amount, 1, type(uint160).max);
    _params.deadline = bound(_params.deadline, 0, type(uint48).max);
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(permit2),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    _mockAndExpect(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector, uniSwapExecutor), abi.encode(0));

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(
        IRefTokenBridge.send.selector,
        block.chainid,
        _destinationChainId,
        _params.tokenOut,
        _params.amountOutMin,
        _recipient
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SwapExecuted(_token, _amount, _params.tokenOut, _params.amountOutMin);

    vm.prank(address(refTokenBridge));
    uniSwapExecutor.execute(_token, _recipient, _amount, _destinationChainId, _data);
  }
}
