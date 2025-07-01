// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {
  Currency,
  IERC20,
  IHooks,
  IPoolManager,
  IRefToken,
  IRefTokenBridge,
  IUniSwapExecutor,
  IUniversalRouter,
  IV4Router,
  PoolKey,
  PredeployAddresses,
  UniSwapExecutor
} from 'contracts/external/UniSwapExecutor.sol';

import {IAllowanceTransfer} from 'lib/permit2/src/interfaces/IAllowanceTransfer.sol';

contract UniSwapExecutorUnit is Helpers {
  // Contract
  IRefTokenBridge public refTokenBridge;
  IUniversalRouter public universalRouter;
  IPoolManager public poolManager;
  IUniSwapExecutor public uniSwapExecutor;

  function setUp() external {
    refTokenBridge = IRefTokenBridge(makeAddr('RefTokenBridge'));
    universalRouter = IUniversalRouter(makeAddr('UniversalRouter'));
    poolManager = IPoolManager(makeAddr('PoolManager'));

    uniSwapExecutor = new UniSwapExecutor(universalRouter, poolManager, refTokenBridge);
  }

  function test_ConstructorWhenConstructorIsSet(
    IUniversalRouter _router,
    IPoolManager _poolManager,
    IRefTokenBridge _refTokenBridge
  ) external {
    uniSwapExecutor = new UniSwapExecutor(_router, _poolManager, _refTokenBridge);

    assertEq(address(uniSwapExecutor.ROUTER()), address(_router));
    assertEq(address(uniSwapExecutor.POOL_MANAGER()), address(_poolManager));
    assertEq(
      address(uniSwapExecutor.L2_TO_L2_CROSS_DOMAIN_MESSENGER()), PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER
    );
    assertEq(address(uniSwapExecutor.REF_TOKEN_BRIDGE()), address(_refTokenBridge));
    assertEq(address(uniSwapExecutor.PERMIT2()), address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
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

  function test_ExecuteRevertWhen_AmountIsTooLarge(uint256 _amount) external {
    uint256 _initialBalance = type(uint128).max;
    ++_initialBalance;
    _amount = bound(_amount, _initialBalance, type(uint256).max);

    vm.expectRevert(abi.encodeWithSelector(IUniSwapExecutor.UniSwapExecutor_AmountTooLarge.selector));
    vm.prank(address(refTokenBridge));
    uniSwapExecutor.execute(address(0), address(0), _amount, 0, bytes(''));
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

    _amount = uint128(bound(_amount, 1, type(uint64).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, _amount + 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    bytes[] memory _routerInput = _getRouterInputForTest(_data, _token, uint128(_amount));

    _mockAndExpect(
      address(universalRouter),
      abi.encodeWithSelector(
        IUniversalRouter.execute.selector, uniSwapExecutor.COMMANDS(), _routerInput, _params.deadline
      ),
      abi.encode(true)
    );

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
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    _assumeFuzzable(_token);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _amount = uint128(bound(_amount, 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));

    _destinationChainId = block.chainid;

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    bytes[] memory _routerInput = _getRouterInputForTest(_data, _token, uint128(_amount));

    _mockAndExpect(
      address(universalRouter),
      abi.encodeWithSelector(
        IUniversalRouter.execute.selector, uniSwapExecutor.COMMANDS(), _routerInput, _params.deadline
      ),
      abi.encode(true)
    );

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

  function test_ExecuteWhenDestinationChainIsNotTheSameAsTheCurrentChainAndTheTokenOutIsNotARefToken(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    _assumeFuzzable(_token);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _amount = uint128(bound(_amount, 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    bytes[] memory _routerInput = _getRouterInputForTest(_data, _token, uint128(_amount));

    _mockAndExpect(
      address(universalRouter),
      abi.encodeWithSelector(
        IUniversalRouter.execute.selector, uniSwapExecutor.COMMANDS(), _routerInput, _params.deadline
      ),
      abi.encode(true)
    );

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.isRefTokenDeployed.selector, _params.tokenOut),
      abi.encode(false)
    );

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

  function test_ExecuteWhenDestinationChainIsNotTheSameAsTheCurrentChainAndTheTokenOutIsARefToken(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    _assumeFuzzable(_token);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _amount = uint128(bound(_amount, 1, type(uint160).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);

    bytes memory _data = abi.encode(_params);

    _mockAndExpect(
      _token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(refTokenBridge), uniSwapExecutor, _amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector,
        _token,
        address(universalRouter),
        uint160(_amount),
        uint48(_params.deadline)
      ),
      abi.encode(true)
    );

    bytes[] memory _routerInput = _getRouterInputForTest(_data, _token, uint128(_amount));

    _mockAndExpect(
      address(universalRouter),
      abi.encodeWithSelector(
        IUniversalRouter.execute.selector, uniSwapExecutor.COMMANDS(), _routerInput, _params.deadline
      ),
      abi.encode(true)
    );

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.isRefTokenDeployed.selector, _params.tokenOut),
      abi.encode(true)
    );

    _mockAndExpect(
      _params.tokenOut,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_destinationChainId)
    );

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(
        IRefTokenBridge.send.selector,
        _destinationChainId,
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

  /**
   * @notice Helper function to get the router input for the test
   * @param _data The data to decode
   * @param _tokenIn The token in
   * @param _amount The amount
   * @return _routerInput The router input
   */
  function _getRouterInputForTest(
    bytes memory _data,
    address _tokenIn,
    uint128 _amount
  ) internal view returns (bytes[] memory _routerInput) {
    _routerInput = new bytes[](1);

    IUniSwapExecutor.V4SwapExactInParams memory _v4Params = abi.decode(_data, (IUniSwapExecutor.V4SwapExactInParams));
    bool _zeroForOne = _tokenIn < _v4Params.tokenOut;
    Currency _inputCurrency = Currency.wrap(_tokenIn);
    Currency _outputCurrency = Currency.wrap(_v4Params.tokenOut);

    PoolKey memory _poolKey = PoolKey({
      currency0: _zeroForOne ? _inputCurrency : _outputCurrency,
      currency1: _zeroForOne ? _outputCurrency : _inputCurrency,
      fee: _v4Params.fee,
      tickSpacing: _v4Params.tickSpacing,
      hooks: IHooks(address(0))
    });

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

    _routerInput[0] = abi.encode(uniSwapExecutor.ACTIONS(), _params);
  }
}
