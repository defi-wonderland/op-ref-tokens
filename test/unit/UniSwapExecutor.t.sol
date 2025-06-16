// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {
  IL2ToL2CrossDomainMessenger,
  IPermit2,
  IPoolManager,
  IRefTokenBridge,
  IUniSwapExecutor,
  IUniversalRouter,
  IV4Router,
  UniSwapExecutor
} from 'contracts/external/UniSwapExecutor.sol';

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

  function test_ExecuteRevertWhen_AmountOutAfterTheSwapIsLessThanTheMinimumAmountOut() external {
    // It should revert
  }

  function test_ExecuteWhenDestinationChainIsTheSameAsTheCurrentChain() external {
    // It should transfer the token to the recipient
    // It should emit SwapExecuted
  }

  function test_ExecuteWhenDestinationChainIsNotTheSameAsTheCurrentChain() external {
    // It should send the token to the destination chain
    // It should emit SwapExecuted
    // It should emit SentToDestinationChain
  }
}
