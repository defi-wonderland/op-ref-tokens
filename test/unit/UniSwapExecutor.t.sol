// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {
  IERC20,
  IL2ToL2CrossDomainMessenger,
  IPermit2,
  IPoolManager,
  IRefTokenBridge,
  IUniSwapExecutor,
  IUniversalRouter,
  IV4Router,
  UniSwapExecutor
} from 'contracts/external/UniSwapExecutor.sol';

import {IAllowanceTransfer} from 'lib/permit2/src/interfaces/IAllowanceTransfer.sol';

contract UniSwapExecutorUnit is Helpers {
  // Contract
  IRefTokenBridge public refTokenBridge;
  IL2ToL2CrossDomainMessenger public l2ToL2CrossDomainMessenger;
  IUniversalRouter public universalRouter;
  IPoolManager public poolManager;
  IPermit2 public permit2;
  IUniSwapExecutor public uniSwapExecutor;

  function setUp() external {
    refTokenBridge = IRefTokenBridge(makeAddr('RefTokenBridge'));
    l2ToL2CrossDomainMessenger = IL2ToL2CrossDomainMessenger(makeAddr('L2ToL2CrossDomainMessenger'));
    universalRouter = IUniversalRouter(makeAddr('UniversalRouter'));
    poolManager = IPoolManager(makeAddr('PoolManager'));
    permit2 = IPermit2(makeAddr('Permit2'));

    uniSwapExecutor =
      new UniSwapExecutor(universalRouter, poolManager, l2ToL2CrossDomainMessenger, refTokenBridge, permit2);
  }

  function test_ConstructorWhenConstructorIsSet(
    IUniversalRouter _router,
    IPoolManager _poolManager,
    IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger,
    IRefTokenBridge _refTokenBridge,
    IPermit2 _permit2
  ) external {
    uniSwapExecutor = new UniSwapExecutor(_router, _poolManager, _l2ToL2CrossDomainMessenger, _refTokenBridge, _permit2);

    assertEq(address(uniSwapExecutor.ROUTER()), address(_router));
    assertEq(address(uniSwapExecutor.POOL_MANAGER()), address(_poolManager));
    assertEq(address(uniSwapExecutor.L2_TO_L2_CROSS_DOMAIN_MESSENGER()), address(_l2ToL2CrossDomainMessenger));
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

  function test_ExecuteRevertWhen_TokenIsNotAValidToken(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external {
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.refTokenMetadata.selector, _token),
      abi.encode(address(0), 0, '', '', 0)
    );
    vm.expectRevert(abi.encodeWithSelector(IUniSwapExecutor.UniSwapExecutor_InvalidToken.selector));
    vm.prank(address(refTokenBridge));
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

    // Mocks and
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.refTokenMetadata.selector, _token),
      abi.encode(_token, 0, '', '', 0)
    );

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
      _params.tokenOut,
      abi.encodeWithSelector(IERC20.balanceOf.selector, uniSwapExecutor),
      abi.encode(_params.amountOutMin - 1)
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

    _params.amountOutMin = bound(_params.amountOutMin, 1, type(uint160).max);
    _amount = bound(_amount, 1, type(uint160).max);
    _params.deadline = bound(_params.deadline, 0, type(uint48).max);

    _destinationChainId = block.chainid;

    bytes memory _data = abi.encode(_params);

    // Mocks and
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.refTokenMetadata.selector, _token),
      abi.encode(_token, 0, '', '', 0)
    );

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
      _params.tokenOut,
      abi.encodeWithSelector(IERC20.balanceOf.selector, uniSwapExecutor),
      abi.encode(_params.amountOutMin)
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

    _params.amountOutMin = bound(_params.amountOutMin, 1, type(uint160).max);
    _amount = bound(_amount, 1, type(uint160).max);
    _params.deadline = bound(_params.deadline, 0, type(uint48).max);
    _destinationChainId = bound(_destinationChainId, block.chainid + 1, type(uint256).max);

    bytes memory _data = abi.encode(_params);

    // Mocks and
    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(IRefTokenBridge.refTokenMetadata.selector, _token),
      abi.encode(_token, 0, '', '', 0)
    );

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
      _params.tokenOut,
      abi.encodeWithSelector(IERC20.balanceOf.selector, uniSwapExecutor),
      abi.encode(_params.amountOutMin)
    );

    _mockAndExpect(
      address(refTokenBridge),
      abi.encodeWithSelector(
        IRefTokenBridge.send.selector,
        IRefTokenBridge.RefTokenBridgeData({
          token: _params.tokenOut,
          recipient: _recipient,
          amount: _params.amountOutMin,
          destinationExecutor: address(0)
        }),
        _destinationChainId
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SwapExecuted(_token, _amount, _params.tokenOut, _params.amountOutMin);

    vm.expectEmit(address(uniSwapExecutor));
    emit IUniSwapExecutor.SentToDestinationChain(
      _params.tokenOut, _params.amountOutMin, _recipient, _destinationChainId
    );

    vm.prank(address(refTokenBridge));
    uniSwapExecutor.execute(_token, _recipient, _amount, _destinationChainId, _data);
  }
}
