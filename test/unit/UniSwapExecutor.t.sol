// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {
  IERC20,
  IPoolManager,
  IRefToken,
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
    _amount = bound(_amount, type(uint160).max, type(uint256).max);

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

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

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

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

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

  function test_BridgeAndSendWhenBridgingANativeTokenWithoutExecutionData(
    address _user,
    address _tokenIn,
    address _recipient,
    uint128 _amountIn,
    uint256 _destinationChainId,
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    // It should lock the native asset and send it to the destination chain
    // It should emit SwapExecuted
    // It should emit SentToDestinationChain
    _assumeFuzzable(_user);
    _assumeFuzzable(_tokenIn);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _amountIn = uint128(bound(_amountIn, 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);

    bytes memory _originSwapData = abi.encode(_params);
    IRefTokenBridge.ExecutionData memory _executionData;

    // Mocks for _executeSwap
    _mockAndExpect(
      _tokenIn,
      abi.encodeWithSelector(IERC20.transferFrom.selector, _user, address(uniSwapExecutor), _amountIn),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector, _tokenIn, address(universalRouter), uint160(_amountIn), _params.deadline
      ),
      abi.encode(true)
    );

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    // Mocks for bridgeAndSend after swap
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
    emit IUniSwapExecutor.SwapExecuted(_tokenIn, _amountIn, _params.tokenOut, _params.amountOutMin);

    // Call
    vm.prank(_user);
    uniSwapExecutor.bridgeAndSend(_tokenIn, _amountIn, _originSwapData, _destinationChainId, _recipient, _executionData);
  }

  function test_BridgeAndSendWhenBridgingANativeTokenWithExecutionData(
    address _user,
    address _tokenIn,
    address _recipient,
    uint128 _amountIn,
    uint256 _destinationChainId,
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    // It should lock the native asset and send it to the destination chain
    // It should emit SwapExecuted
    // It should emit SentToDestinationChain
    _assumeFuzzable(_user);
    _assumeFuzzable(_tokenIn);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _amountIn = uint128(bound(_amountIn, 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);

    // Make sure execution data is valid
    _executionData.destinationExecutor = makeAddr('destinationExecutor');
    _executionData.destinationChainId = bound(_executionData.destinationChainId, 1, type(uint256).max);
    if (_executionData.destinationChainId == block.chainid) ++_executionData.destinationChainId;
    _executionData.refundAddress = makeAddr('refundAddress');

    bytes memory _originSwapData = abi.encode(_params);

    // Mocks for _executeSwap
    _mockAndExpect(
      _tokenIn,
      abi.encodeWithSelector(IERC20.transferFrom.selector, _user, address(uniSwapExecutor), _amountIn),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector, _tokenIn, address(universalRouter), uint160(_amountIn), _params.deadline
      ),
      abi.encode(true)
    );

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    // Mocks for bridgeAndSend after swap
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.isRefTokenDeployed.selector, _params.tokenOut),
      abi.encode(false)
    );

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(
        IRefTokenBridge.sendAndExecute.selector,
        block.chainid,
        _destinationChainId,
        _params.tokenOut,
        _params.amountOutMin,
        _recipient,
        _executionData
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SwapExecuted(_tokenIn, _amountIn, _params.tokenOut, _params.amountOutMin);

    // Call
    vm.prank(_user);
    uniSwapExecutor.bridgeAndSend(_tokenIn, _amountIn, _originSwapData, _destinationChainId, _recipient, _executionData);
  }

  function test_BridgeAndSendWhenBridgingARefTokenWithoutExecutionData(
    address _user,
    address _tokenIn,
    address _recipient,
    uint128 _amountIn,
    uint256 _destinationChainId,
    uint256 _nativeAssetChainId,
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params
  ) external {
    // It should burn the RefToken and send it to the destination chain
    // It should emit SwapExecuted
    // It should emit SentToDestinationChain
    _assumeFuzzable(_user);
    _assumeFuzzable(_tokenIn);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _amountIn = uint128(bound(_amountIn, 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);
    _nativeAssetChainId = bound(_nativeAssetChainId, 1, type(uint256).max);
    if (_nativeAssetChainId == block.chainid) ++_nativeAssetChainId;

    bytes memory _originSwapData = abi.encode(_params);
    IRefTokenBridge.ExecutionData memory _executionData;

    // Mocks for _executeSwap
    _mockAndExpect(
      _tokenIn,
      abi.encodeWithSelector(IERC20.transferFrom.selector, _user, address(uniSwapExecutor), _amountIn),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector, _tokenIn, address(universalRouter), uint160(_amountIn), _params.deadline
      ),
      abi.encode(true)
    );

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    // Mocks for bridgeAndSend after swap
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.isRefTokenDeployed.selector, _params.tokenOut),
      abi.encode(true)
    );
    _mockAndExpect(
      _params.tokenOut,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_nativeAssetChainId)
    );

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(
        IRefTokenBridge.send.selector,
        _nativeAssetChainId,
        _destinationChainId,
        _params.tokenOut,
        _params.amountOutMin,
        _recipient
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SwapExecuted(_tokenIn, _amountIn, _params.tokenOut, _params.amountOutMin);

    // Call
    vm.prank(_user);
    uniSwapExecutor.bridgeAndSend(_tokenIn, _amountIn, _originSwapData, _destinationChainId, _recipient, _executionData);
  }

  function test_BridgeAndSendWhenBridgingARefTokenWithExecutionData(
    address _user,
    address _tokenIn,
    address _recipient,
    uint128 _amountIn,
    uint256 _destinationChainId,
    uint256 _nativeAssetChainId,
    uint256 _initialBalance,
    IUniSwapExecutor.V4SwapExactInParams memory _params,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    // It should burn the RefToken and send it to the destination chain
    // It should emit SwapExecuted
    // It should emit SentToDestinationChain
    _assumeFuzzable(_user);
    _assumeFuzzable(_tokenIn);
    _assumeFuzzable(_params.tokenOut);
    _assumeFuzzable(_recipient);

    _initialBalance = uint128(bound(_initialBalance, 1, type(uint128).max));
    _params.amountOutMin = uint128(bound(_params.amountOutMin, 1, type(uint128).max));
    _amountIn = uint128(bound(_amountIn, 1, type(uint128).max));
    _params.deadline = uint48(bound(_params.deadline, 0, type(uint48).max));
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);
    _nativeAssetChainId = bound(_nativeAssetChainId, 1, type(uint256).max);
    if (_nativeAssetChainId == block.chainid) ++_nativeAssetChainId;

    // Make sure execution data is valid
    _executionData.destinationExecutor = makeAddr('destinationExecutor');
    _executionData.destinationChainId = bound(_executionData.destinationChainId, 1, type(uint256).max);
    if (_executionData.destinationChainId == block.chainid) ++_executionData.destinationChainId;
    _executionData.refundAddress = makeAddr('refundAddress');

    bytes memory _originSwapData = abi.encode(_params);

    // Mocks for _executeSwap
    _mockAndExpect(
      _tokenIn,
      abi.encodeWithSelector(IERC20.transferFrom.selector, _user, address(uniSwapExecutor), _amountIn),
      abi.encode(true)
    );

    _mockAndExpect(
      address(uniSwapExecutor.PERMIT2()),
      abi.encodeWithSelector(
        IAllowanceTransfer.approve.selector, _tokenIn, address(universalRouter), uint160(_amountIn), _params.deadline
      ),
      abi.encode(true)
    );

    vm.mockCall(address(universalRouter), abi.encodeWithSelector(IUniversalRouter.execute.selector), abi.encode(true));

    bytes[] memory _mocks = new bytes[](2);
    _mocks[0] = abi.encode(_initialBalance);
    _mocks[1] = abi.encode(_params.amountOutMin + _initialBalance);

    vm.mockCalls(_params.tokenOut, abi.encodeWithSelector(IERC20.balanceOf.selector), _mocks);

    // Mocks for bridgeAndSend after swap
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.isRefTokenDeployed.selector, _params.tokenOut),
      abi.encode(true)
    );
    _mockAndExpect(
      _params.tokenOut,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_nativeAssetChainId)
    );

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(
        IRefTokenBridge.sendAndExecute.selector,
        _nativeAssetChainId,
        _destinationChainId,
        _params.tokenOut,
        _params.amountOutMin,
        _recipient,
        _executionData
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SwapExecuted(_tokenIn, _amountIn, _params.tokenOut, _params.amountOutMin);

    // Call
    vm.prank(_user);
    uniSwapExecutor.bridgeAndSend(_tokenIn, _amountIn, _originSwapData, _destinationChainId, _recipient, _executionData);
  }
}
