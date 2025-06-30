// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {IL2ToL2CrossDomainMessenger} from '@interop-lib/src/interfaces/IL2ToL2CrossDomainMessenger.sol';
import {IRefToken, IRefTokenBridge, RefTokenBridge} from 'src/contracts/RefTokenBridge.sol';
import {IExecutor} from 'src/interfaces/external/IExecutor.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IERC20Metadata} from 'src/interfaces/external/IERC20Metadata.sol';

contract RefTokenBridgeForTest is RefTokenBridge {
  function setRefTokenDeployed(address _nativeToken, bool _deployed) external {
    isRefTokenDeployed[_nativeToken] = _deployed;
  }

  function setNativeToRefToken(address _nativeToken, uint256 _nativeAssetChainId, address _refToken) external {
    nativeToRefToken[_nativeToken][_nativeAssetChainId] = _refToken;
  }
}

contract RefTokenBridgeUnit is Helpers {
  address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

  /// Contracts
  IL2ToL2CrossDomainMessenger public l2ToL2CrossDomainMessenger;
  RefTokenBridgeForTest public refTokenBridge;

  /// Variables
  address public refToken;
  IRefToken.RefTokenMetadata public refTokenMetadata;

  function setUp() public {
    refTokenBridge = new RefTokenBridgeForTest();

    refTokenMetadata = IRefToken.RefTokenMetadata({
      nativeAsset: nativeAsset,
      nativeAssetChainId: nativeAssetChainId,
      nativeAssetName: nativeAssetName,
      nativeAssetSymbol: nativeAssetSymbol,
      nativeAssetDecimals: nativeAssetDecimals
    });

    refToken = _precalculateRefTokenAddress(address(refTokenBridge), refTokenMetadata);
    vm.label(refToken, 'Setup RefToken');
  }

  function test_SendRevertWhen_AmountIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _relayChainId
  ) external {
    uint256 _amount = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidAmount.selector);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_RecipientIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    uint256 _amount,
    uint256 _relayChainId
  ) external {
    _amount = bound(_amount, 1, type(uint256).max);
    address _recipient = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRecipient.selector);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_RelayChainIdIsTheBlockChainId(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount
  ) external {
    vm.assume(_recipient != address(0));
    _amount = bound(_amount, 1, type(uint256).max);
    uint256 _relayChainId = block.chainid;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRelayChainId.selector);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_RelayChainIdIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount
  ) external {
    vm.assume(_recipient != address(0));
    _amount = bound(_amount, 1, type(uint256).max);
    uint256 _relayChainId = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRelayChainId.selector);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_NativeAssetChainIdIsZero(
    uint256 _relayChainId,
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount
  ) external {
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    _nativeAssetChainId = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidNativeAssetChainId.selector);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_NativeAssetChainIdDoesNotMatchTheBlockChainIdWhenDeployingARefToken(
    address _caller,
    uint256 _relayChainId,
    uint256 _nativeAssetChainId,
    address _nativeAsset,
    address _recipient,
    uint256 _amount
  ) external {
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    if (_nativeAssetChainId == block.chainid) ++_nativeAssetChainId;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidNativeAssetChainId.selector);
    vm.prank(_caller);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _nativeAsset, _amount, _recipient);
  }

  function test_SendRevertWhen_NativeChainIdMatchesTheBlockChainIdAndTheTokenIsNotTheNativeToken(
    address _caller,
    uint256 _relayChainId,
    address _nativeAsset,
    address _refToken,
    address _recipient,
    uint256 _amount
  ) external {
    // Setup
    _assumeFuzzable(_nativeAsset);
    _assumeFuzzable(_refToken);
    vm.assume(_nativeAsset != _refToken);

    _amount = bound(_amount, 1, type(uint256).max);
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;

    vm.assume(_recipient != address(0));

    refTokenBridge.setRefTokenDeployed(_refToken, true);

    refTokenMetadata.nativeAsset = _nativeAsset;
    refTokenMetadata.nativeAssetChainId = block.chainid;
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(refTokenMetadata));

    // Action and assertion
    vm.prank(_caller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_NotNativeAsset.selector);
    refTokenBridge.send(block.chainid, _relayChainId, _refToken, _amount, _recipient);
  }

  function test_SendRevertWhen_NativeChainIdIsNotDoesNotMatchTheBlockChainIdAndTheTokenIsNotTheRefToken(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _refToken,
    address _recipient,
    uint256 _amount
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_refToken);

    _amount = bound(_amount, 1, type(uint256).max);
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    _refTokenMetadata.nativeAssetChainId = bound(_refTokenMetadata.nativeAssetChainId, 1, type(uint256).max);

    vm.assume(_recipient != address(0));
    vm.assume(_refTokenMetadata.nativeAsset != _refToken);

    if (_relayChainId == block.chainid) ++_relayChainId;
    if (_refTokenMetadata.nativeAssetChainId == block.chainid) ++_refTokenMetadata.nativeAssetChainId;

    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    vm.prank(_caller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_NotRefToken.selector);
    refTokenBridge.send(
      _refTokenMetadata.nativeAssetChainId, _relayChainId, _refTokenMetadata.nativeAsset, _amount, _recipient
    );
  }

  function test_SendWhenCalledWithANativeTokenFirstTime(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    uint256 _amount
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;

    // It should create the RefToken
    _refTokenMetadata.nativeAssetChainId = block.chainid;
    address _refToken = _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(_refToken, _refTokenMetadata.nativeAsset, block.chainid);

    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeWithSelector(IERC20Metadata.name.selector),
      abi.encode(_refTokenMetadata.nativeAssetName)
    );
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeWithSelector(IERC20Metadata.symbol.selector),
      abi.encode(_refTokenMetadata.nativeAssetSymbol)
    );
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeWithSelector(IERC20Metadata.decimals.selector),
      abi.encode(_refTokenMetadata.nativeAssetDecimals)
    );

    // On this branch, `metadata()` should not be called
    vm.expectCall(_refToken, abi.encodeCall(IRefToken.metadata, ()), 0);

    // It should lock the tokens
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeCall(IERC20.transferFrom, (_caller, address(refTokenBridge), _amount)),
      abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetLocked(_refTokenMetadata.nativeAsset, _caller, _amount);

    // It should send the message to call relay
    bytes memory _message = abi.encodeCall(IRefTokenBridge.relay, (_amount, _recipient, _refTokenMetadata));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_relayChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    // It should emit MessageSent
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(_refTokenMetadata.nativeAsset, _amount, _recipient, address(0), _relayChainId);

    vm.prank(_caller);
    refTokenBridge.send(
      _refTokenMetadata.nativeAssetChainId, _relayChainId, _refTokenMetadata.nativeAsset, _amount, _recipient
    );

    assertTrue(refTokenBridge.isRefTokenDeployed(_refToken));
    assertEq(
      refTokenBridge.nativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId), _refToken
    );
  }

  function test_SendWhenCallingWithTheNativeTokenAfterTheCreationOfTheRefToken(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _refToken,
    address _recipient,
    uint256 _amount
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_refToken);
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    _refTokenMetadata.nativeAssetChainId = block.chainid;

    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    // It should lock the tokens
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeCall(IERC20.transferFrom, (_caller, address(refTokenBridge), _amount)),
      abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetLocked(_refTokenMetadata.nativeAsset, _caller, _amount);

    // It should send the message to call relay
    bytes memory _message = abi.encodeCall(IRefTokenBridge.relay, (_amount, _recipient, _refTokenMetadata));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_relayChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    // It should emit MessageSent
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(_refTokenMetadata.nativeAsset, _amount, _recipient, address(0), _relayChainId);

    vm.prank(_caller);
    refTokenBridge.send(
      _refTokenMetadata.nativeAssetChainId, _relayChainId, _refTokenMetadata.nativeAsset, _amount, _recipient
    );
  }

  function test_SendWhenCalledWithARefToken(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _refToken,
    address _recipient,
    uint256 _amount
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_refToken);
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    _refTokenMetadata.nativeAssetChainId = bound(_refTokenMetadata.nativeAssetChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;

    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    // It should burn the tokens
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.burn, (_caller, _amount)), abi.encode(true));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenBurned(_refToken, _caller, _amount);

    // It should send the message to call relay
    bytes memory _message = abi.encodeCall(IRefTokenBridge.relay, (_amount, _recipient, _refTokenMetadata));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_relayChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    // It should emit MessageSent
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(_refToken, _amount, _recipient, address(0), _relayChainId);

    vm.prank(_caller);
    refTokenBridge.send(_refTokenMetadata.nativeAssetChainId, _relayChainId, _refToken, _amount, _recipient);
  }

  function test_SendAndExecuteRevertWhen_ExecutionDataDestinationExecutorIsTheZeroAddress(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _executionData.destinationExecutor = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationExecutor.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_ExecutionDataDestinationChainIdIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    _executionData.destinationChainId = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidExecutionChainId.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_ExecutionDataDestinationChainIdIsTheBlockChainId(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    _executionData.destinationChainId = block.chainid;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidExecutionChainId.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_AmountIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));

    uint256 _amount = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidAmount.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_RecipientIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));
    _amount = bound(_amount, 1, type(uint256).max);

    address _recipient = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRecipient.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_RefundAddressIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _executionData.destinationChainId = bound(_executionData.destinationChainId, 1, type(uint256).max);
    if (_executionData.destinationChainId == block.chainid) ++_executionData.destinationChainId;
    vm.assume(_recipient != address(0));
    vm.assume(_executionData.destinationExecutor != address(0));

    _executionData.refundAddress = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRefundAddress.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_RelayChainIdIsZero(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);

    vm.assume(_recipient != address(0));
    _amount = bound(_amount, 1, type(uint256).max);
    uint256 _relayChainId = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRelayChainId.selector);
    refTokenBridge.send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient);
  }

  function test_SendAndExecuteRevertWhen_RelayChainIdIsTheBlockChainId(
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));

    vm.assume(_recipient != address(0));
    _amount = bound(_amount, 1, type(uint256).max);
    uint256 _relayChainId = block.chainid;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRelayChainId.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_NativeAssetChainIdDoesNotMatchTheBlockChainIdWhenDeployingARefToken(
    address _caller,
    uint256 _relayChainId,
    uint256 _nativeAssetChainId,
    address _nativeAsset,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    if (_nativeAssetChainId == block.chainid) ++_nativeAssetChainId;
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidNativeAssetChainId.selector);
    vm.prank(_caller);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _nativeAsset, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_NativeAssetChainIdIsZero(
    uint256 _relayChainId,
    uint256 _nativeAssetChainId,
    address _token,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    _executionData.destinationChainId = bound(_executionData.destinationChainId, 1, type(uint256).max);
    if (_executionData.destinationChainId == block.chainid) ++_executionData.destinationChainId;
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.refundAddress != address(0));

    // It should revert
    _nativeAssetChainId = 0;
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidNativeAssetChainId.selector);
    refTokenBridge.sendAndExecute(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_NativeChainIdMatchesTheBlockChainIdAndTheTokenIsNotTheNativeToken(
    address _caller,
    uint256 _relayChainId,
    address _nativeAsset,
    address _refToken,
    address _recipient,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    // Setup
    _assumeFuzzable(_nativeAsset);
    _assumeFuzzable(_refToken);
    vm.assume(_nativeAsset != _refToken);

    _amount = bound(_amount, 1, type(uint256).max);
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;

    _refTokenMetadata.nativeAsset = _nativeAsset;
    _refTokenMetadata.nativeAssetChainId = block.chainid;

    vm.assume(_recipient != address(0));
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));

    refTokenBridge.setRefTokenDeployed(_refToken, true);

    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    // Action and assertion
    vm.prank(_caller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_NotNativeAsset.selector);
    refTokenBridge.sendAndExecute(block.chainid, _relayChainId, _refToken, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_NativeChainIdIsNotDoesNotMatchTheBlockChainIdAndTheTokenIsNotTheRefToken(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _refToken,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_refToken);

    _refTokenMetadata.nativeAssetChainId = bound(_refTokenMetadata.nativeAssetChainId, 1, type(uint256).max);
    _executionData.destinationChainId = bound(_executionData.destinationChainId, 1, type(uint256).max);
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    _amount = bound(_amount, 1, type(uint256).max);

    if (_executionData.destinationChainId == block.chainid) ++_executionData.destinationChainId;
    if (_relayChainId == block.chainid) ++_relayChainId;
    if (_refTokenMetadata.nativeAssetChainId == block.chainid) ++_refTokenMetadata.nativeAssetChainId;

    vm.assume(_recipient != address(0));
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.refundAddress != address(0));
    vm.assume(_refTokenMetadata.nativeAsset != _refToken);
    vm.assume(_executionData.refundAddress != address(0));

    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    vm.prank(_caller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_NotRefToken.selector);
    refTokenBridge.sendAndExecute(
      _refTokenMetadata.nativeAssetChainId,
      _relayChainId,
      _refTokenMetadata.nativeAsset,
      _amount,
      _recipient,
      _executionData
    );
  }

  function test_SendAndExecuteWhenCalledWithANativeTokenFirstTime(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));

    // It should create the RefToken
    _refTokenMetadata.nativeAssetChainId = block.chainid;
    address _refToken = _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(_refToken, _refTokenMetadata.nativeAsset, block.chainid);

    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeWithSelector(IERC20Metadata.name.selector),
      abi.encode(_refTokenMetadata.nativeAssetName)
    );
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeWithSelector(IERC20Metadata.symbol.selector),
      abi.encode(_refTokenMetadata.nativeAssetSymbol)
    );
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeWithSelector(IERC20Metadata.decimals.selector),
      abi.encode(_refTokenMetadata.nativeAssetDecimals)
    );
    // On this branch, `metadata()` should not be called
    vm.expectCall(_refToken, abi.encodeCall(IRefToken.metadata, ()), 0);

    // It should lock the tokens
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeCall(IERC20.transferFrom, (_caller, address(refTokenBridge), _amount)),
      abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetLocked(_refTokenMetadata.nativeAsset, _caller, _amount);

    // It should send the message to call relay
    bytes memory _message =
      abi.encodeCall(IRefTokenBridge.relayAndExecute, (_amount, _recipient, _refTokenMetadata, _executionData));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_relayChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    // It should emit MessageSent
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenMetadata.nativeAsset, _amount, _recipient, _executionData.destinationExecutor, _relayChainId
    );

    vm.prank(_caller);
    refTokenBridge.sendAndExecute(
      _refTokenMetadata.nativeAssetChainId,
      _relayChainId,
      _refTokenMetadata.nativeAsset,
      _amount,
      _recipient,
      _executionData
    );

    assertTrue(refTokenBridge.isRefTokenDeployed(_refToken));
    assertEq(
      refTokenBridge.nativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId), _refToken
    );
  }

  function test_SendAndExecuteWhenCallingWithTheNativeTokenAfterTheCreationOfTheRefToken(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _refToken,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_refToken);
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;
    _refTokenMetadata.nativeAssetChainId = block.chainid;
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));

    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    // It should lock the tokens
    _mockAndExpect(
      _refTokenMetadata.nativeAsset,
      abi.encodeCall(IERC20.transferFrom, (_caller, address(refTokenBridge), _amount)),
      abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetLocked(_refTokenMetadata.nativeAsset, _caller, _amount);

    // It should send the message to call relay
    bytes memory _message =
      abi.encodeCall(IRefTokenBridge.relayAndExecute, (_amount, _recipient, _refTokenMetadata, _executionData));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_relayChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    // It should emit MessageSent
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenMetadata.nativeAsset, _amount, _recipient, _executionData.destinationExecutor, _relayChainId
    );

    vm.prank(_caller);
    refTokenBridge.sendAndExecute(
      _refTokenMetadata.nativeAssetChainId,
      _relayChainId,
      _refTokenMetadata.nativeAsset,
      _amount,
      _recipient,
      _executionData
    );
  }

  function test_SendAndExecuteWhenCalledWithARefToken(
    address _caller,
    uint256 _relayChainId,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _refToken,
    address _recipient,
    uint256 _amount,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_refToken);
    _amount = bound(_amount, 1, type(uint256).max);
    vm.assume(_recipient != address(0));
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    vm.assume(_executionData.refundAddress != address(0));
    _refTokenMetadata.nativeAssetChainId = bound(_refTokenMetadata.nativeAssetChainId, 1, type(uint256).max);
    _relayChainId = bound(_relayChainId, 1, type(uint256).max);
    if (_relayChainId == block.chainid) ++_relayChainId;

    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.metadata, ()), abi.encode(_refTokenMetadata));

    // It should burn the tokens
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.burn, (_caller, _amount)), abi.encode(true));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenBurned(_refToken, _caller, _amount);

    // It should send the message to call relay
    bytes memory _message =
      abi.encodeCall(IRefTokenBridge.relayAndExecute, (_amount, _recipient, _refTokenMetadata, _executionData));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_relayChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    // It should emit MessageSent
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(_refToken, _amount, _recipient, _executionData.destinationExecutor, _relayChainId);

    vm.prank(_caller);
    refTokenBridge.sendAndExecute(
      _refTokenMetadata.nativeAssetChainId, _relayChainId, _refToken, _amount, _recipient, _executionData
    );
  }

  function test_RelayRevertWhen_SenderIsNotTheL2ToL2CrossDomainMessenger(
    address _caller,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    uint256 _amount,
    address _recipient
  ) external {
    vm.assume(_caller != L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(_caller);
    refTokenBridge.relay(_amount, _recipient, _refTokenMetadata);
  }

  function test_RelayRevertWhen_CrossDomainSenderIsNotTheRefTokenBridge(
    address _randomCaller,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    uint256 _amount,
    address _recipient
  ) external {
    vm.assume(_randomCaller != address(refTokenBridge));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(_randomCaller)
    );

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relay(_amount, _recipient, _refTokenMetadata);
  }

  function test_RelayWhenOnTheNativeAssetChain(
    address _refToken,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);

    _refTokenMetadata.nativeAssetChainId = block.chainid;
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );

    // It should unlock the native assets to the recipient
    _mockAndExpect(
      _refTokenMetadata.nativeAsset, abi.encodeCall(IERC20.transfer, (_recipient, _amount)), abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetUnlocked(_refTokenMetadata.nativeAsset, _recipient, _amount);

    // It should emit MessageRelayed
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(_refTokenMetadata.nativeAsset, _amount, _recipient, address(0));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relay(_amount, _recipient, _refTokenMetadata);
  }

  function test_RelayWhenCalledNotOnTheNativeAssetChainAndTheRefTokenIsDeployed(
    address _refToken,
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) external {
    vm.assume(_refTokenMetadata.nativeAssetChainId != block.chainid);
    _assumeFuzzable(_refToken);

    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );

    // It should mint the tokens to the recipient
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.mint, (_recipient, _amount)), abi.encode(true));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenMinted(_refToken, _recipient, _amount);

    // It should emit MessageRelayed
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(_refToken, _amount, _recipient, address(0));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relay(_amount, _recipient, _refTokenMetadata);
  }

  function test_RelayWhenCalledNotOnTheNativeAssetChainAndTheRefTokenIsNotDeployed(
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) external {
    vm.assume(_refTokenMetadata.nativeAssetChainId != block.chainid);

    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );

    // It should deploy the RefToken
    address _refToken = _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata);
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(
      _refToken, _refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId
    );

    // It should mint the tokens to the recipient
    vm.expectCall(_refToken, abi.encodeCall(IRefToken.mint, (_recipient, _amount)));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenMinted(_refToken, _recipient, _amount);

    // It should emit MessageRelayed
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(_refToken, _amount, _recipient, address(0));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relay(_amount, _recipient, _refTokenMetadata);

    assertTrue(refTokenBridge.isRefTokenDeployed(_refToken));
    assertEq(
      refTokenBridge.nativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId), _refToken
    );
  }

  function test_RelayAndExecuteRevertWhen_SenderIsNotTheL2ToL2CrossDomainMessenger(
    address _caller,
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_caller != L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(_caller);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteRevertWhen_CrossDomainSenderIsNotTheRefTokenBridge(
    address _randomCaller,
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_randomCaller != address(refTokenBridge));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(_randomCaller)
    );

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteWhenOnTheNativeAssetChainAndExecutionSucceeds(
    address _refToken,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_executionData.destinationExecutor);

    _refTokenMetadata.nativeAssetChainId = block.chainid;
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );

    // It should approve the executor
    vm.mockCall(_refTokenMetadata.nativeAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.expectCall(
      _refTokenMetadata.nativeAsset, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, _amount))
    );

    // It should execute the data
    _mockAndExpect(
      _executionData.destinationExecutor,
      abi.encodeCall(
        IExecutor.execute,
        (_refTokenMetadata.nativeAsset, _recipient, _amount, _executionData.destinationChainId, _executionData.data)
      ),
      abi.encode(true)
    );

    // It should emit MessageRelayed
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenMetadata.nativeAsset, _amount, _recipient, _executionData.destinationExecutor
    );

    // It should revoke the executor approval
    vm.expectCall(
      _refTokenMetadata.nativeAsset, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, 0))
    );

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteWhenOnTheNativeAssetChainAndExecutionFails(
    address _refToken,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    IRefTokenBridge.ExecutionData memory _executionData,
    uint256 _sourceChainId
  ) external {
    _assumeFuzzable(_refTokenMetadata.nativeAsset);
    _assumeFuzzable(_executionData.destinationExecutor);

    _refTokenMetadata.nativeAssetChainId = block.chainid;
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSource, ()),
      abi.encode(_sourceChainId)
    );

    // It should approve the executor
    vm.mockCall(_refTokenMetadata.nativeAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.expectCall(
      _refTokenMetadata.nativeAsset, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, _amount))
    );

    // It should execute the data
    _mockRevertAndExpect(
      _executionData.destinationExecutor,
      abi.encodeCall(
        IExecutor.execute,
        (_refTokenMetadata.nativeAsset, _recipient, _amount, _executionData.destinationChainId, _executionData.data)
      ),
      abi.encode(true)
    );

    // It should send RefTokens to the refund address on the origin chain
    bytes memory _message =
      abi.encodeCall(IRefTokenBridge.relay, (_amount, _executionData.refundAddress, _refTokenMetadata));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_sourceChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenMetadata.nativeAsset, _amount, _executionData.refundAddress, address(0), _sourceChainId
    );

    // It should revoke the executor approval
    vm.expectCall(
      _refTokenMetadata.nativeAsset, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, 0))
    );

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndTheRefTokenIsDeployedAndExecutionSucceeds(
    address _refToken,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_refToken);
    _assumeFuzzable(_executionData.destinationExecutor);

    if (_refTokenMetadata.nativeAssetChainId == block.chainid) ++_refTokenMetadata.nativeAssetChainId;
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );

    // It should mint the tokens to itself
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.mint, (address(refTokenBridge), _amount)), abi.encode(true));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenMinted(_refToken, address(refTokenBridge), _amount);

    // It should approve the executor
    vm.mockCall(_refToken, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, _amount)));

    // It should execute the data
    _mockAndExpect(
      _executionData.destinationExecutor,
      abi.encodeCall(
        IExecutor.execute, (_refToken, _recipient, _amount, _executionData.destinationChainId, _executionData.data)
      ),
      abi.encode(true)
    );

    // It should emit MessageRelayed
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(_refToken, _amount, _recipient, _executionData.destinationExecutor);

    // It should revoke the executor approval
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, 0)));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndTheRefTokenIsNotDeployedAndExecutionSucceeds(
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _assumeFuzzable(_executionData.destinationExecutor);
    vm.assume(_executionData.destinationExecutor != PERMIT2);
    if (_refTokenMetadata.nativeAssetChainId == block.chainid) ++_refTokenMetadata.nativeAssetChainId;

    // It should deploy the RefToken
    address _refToken = _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata);
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(
      _refToken, _refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId
    );

    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );

    // It should mint the tokens to itself
    vm.expectCall(_refToken, abi.encodeCall(IRefToken.mint, (address(refTokenBridge), _amount)));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenMinted(_refToken, address(refTokenBridge), _amount);

    // It should approve the executor
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, _amount)));

    // It should execute the data
    _mockAndExpect(
      _executionData.destinationExecutor,
      abi.encodeCall(
        IExecutor.execute, (_refToken, _recipient, _amount, _executionData.destinationChainId, _executionData.data)
      ),
      abi.encode(true)
    );

    // It should emit MessageRelayed
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(_refToken, _amount, _recipient, _executionData.destinationExecutor);

    // It should revoke the executor approval
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, 0)));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);

    assertTrue(refTokenBridge.isRefTokenDeployed(_refToken));
    assertEq(
      refTokenBridge.nativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId), _refToken
    );
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndRefTokenIsDeployedAndExecutionFails(
    address _refToken,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    IRefTokenBridge.ExecutionData memory _executionData,
    uint256 _sourceChainId
  ) external {
    _assumeFuzzable(_executionData.destinationExecutor);
    _assumeFuzzable(_refToken);
    if (_refTokenMetadata.nativeAssetChainId == block.chainid) ++_refTokenMetadata.nativeAssetChainId;
    refTokenBridge.setNativeToRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId, _refToken);

    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSource, ()),
      abi.encode(_sourceChainId)
    );

    // It should mint the tokens to itself
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.mint, (address(refTokenBridge), _amount)), abi.encode(true));
    // vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenMinted(_refToken, address(refTokenBridge), _amount);

    // It should approve the executor
    vm.mockCall(_refToken, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, _amount)));

    // It should execute the data
    _mockRevertAndExpect(
      _executionData.destinationExecutor,
      abi.encodeCall(
        IExecutor.execute, (_refToken, _recipient, _amount, _executionData.destinationChainId, _executionData.data)
      ),
      abi.encode(true)
    );

    // It should burn the RefTokens
    _mockAndExpect(_refToken, abi.encodeCall(IRefToken.burn, (address(refTokenBridge), _amount)), abi.encode(true));
    // vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenBurned(_refToken, address(refTokenBridge), _amount);

    // It should send RefTokens to the refund address on the origin chain
    bytes memory _message =
      abi.encodeCall(IRefTokenBridge.relay, (_amount, _executionData.refundAddress, _refTokenMetadata));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_sourceChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );
    // vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(_refToken, _amount, _executionData.refundAddress, address(0), _sourceChainId);

    // It should revoke the executor approval
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, 0)));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndTheRefTokenIsNotDeployedAndExecutionFails(
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    address _recipient,
    IRefTokenBridge.ExecutionData memory _executionData,
    uint256 _sourceChainId
  ) external {
    _assumeFuzzable(_executionData.destinationExecutor);
    vm.assume(_executionData.destinationExecutor != PERMIT2);
    if (_refTokenMetadata.nativeAssetChainId == block.chainid) ++_refTokenMetadata.nativeAssetChainId;

    // It should deploy the RefToken
    address _refToken = _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata);
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(
      _refToken, _refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId
    );

    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSender, ()),
      abi.encode(address(refTokenBridge))
    );
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.crossDomainMessageSource, ()),
      abi.encode(_sourceChainId)
    );

    // It should mint the tokens to itself
    vm.expectCall(_refToken, abi.encodeCall(IRefToken.mint, (address(refTokenBridge), _amount)));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenMinted(_refToken, address(refTokenBridge), _amount);

    // It should approve the executor
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, _amount)));

    // It should execute the data
    _mockRevertAndExpect(
      _executionData.destinationExecutor,
      abi.encodeCall(
        IExecutor.execute, (_refToken, _recipient, _amount, _executionData.destinationChainId, _executionData.data)
      ),
      abi.encode(true)
    );

    // It should burn the RefTokens
    vm.expectCall(_refToken, abi.encodeCall(IRefToken.burn, (address(refTokenBridge), _amount)));
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenBurned(_refToken, address(refTokenBridge), _amount);

    // It should send RefTokens to the refund address on the origin chain
    bytes memory _message =
      abi.encodeCall(IRefTokenBridge.relay, (_amount, _executionData.refundAddress, _refTokenMetadata));
    _mockAndExpect(
      L2_TO_L2_CROSS_DOMAIN_MESSENGER,
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_sourceChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(_refToken, _amount, _executionData.refundAddress, address(0), _sourceChainId);

    // It should revoke the executor approval
    vm.expectCall(_refToken, abi.encodeCall(IERC20.approve, (_executionData.destinationExecutor, 0)));

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.relayAndExecute(_amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_UnlockRevertWhen_CallerIsNotTheL2ToL2CrossDomainMessenger(
    address _caller,
    address _nativeAsset,
    address _recipient,
    uint256 _amount
  ) external {
    vm.assume(_caller != address(0));
    vm.assume(_caller != L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(_caller);
    refTokenBridge.unlock(_nativeAsset, _recipient, _amount);
  }

  function test_UnlockRevertWhen_CallerIsNotTheRefTokenForTheNativeAsset(
    address _caller,
    address _refToken,
    address _nativeAsset,
    address _recipient,
    uint256 _amount
  ) external {
    vm.assume(_caller != L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    vm.assume(_caller != _refToken);

    refTokenBridge.setNativeToRefToken(_nativeAsset, block.chainid, _refToken);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(_caller);
    refTokenBridge.unlock(_nativeAsset, _recipient, _amount);
  }

  function test_UnlockWhenCalledByTheL2ToL2CrossDomainMessenger(
    address _nativeAsset,
    address _recipient,
    uint256 _amount
  ) external {
    _assumeFuzzable(_nativeAsset);

    // It should transfer the tokens to user
    _mockAndExpect(_nativeAsset, abi.encodeCall(IERC20.transfer, (_recipient, _amount)), abi.encode(true));

    // It should emit TokenUnlocked
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetUnlocked(_nativeAsset, _recipient, _amount);

    vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    refTokenBridge.unlock(_nativeAsset, _recipient, _amount);
  }

  function test_UnlockWhenCalledByTheAssociatedRefToken(
    address _refToken,
    address _nativeAsset,
    address _recipient,
    uint256 _amount
  ) external {
    _assumeFuzzable(_nativeAsset);
    refTokenBridge.setNativeToRefToken(_nativeAsset, block.chainid, _refToken);

    // It should transfer the tokens to user
    _mockAndExpect(_nativeAsset, abi.encodeCall(IERC20.transfer, (_recipient, _amount)), abi.encode(true));

    // It should emit NativeAssetUnlocked
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.NativeAssetUnlocked(_nativeAsset, _recipient, _amount);

    vm.prank(_refToken);
    refTokenBridge.unlock(_nativeAsset, _recipient, _amount);
  }

  function test_GetRefTokenWhenCalledWithANativeTokenAndTheRefTokenExists(
    address _nativeAsset,
    uint256 _nativeAssetChainId,
    address _refToken
  ) external {
    vm.assume(_nativeAsset != address(0));
    refTokenBridge.setRefTokenDeployed(_refToken, true);
    refTokenBridge.setNativeToRefToken(_nativeAsset, _nativeAssetChainId, _refToken);

    // It should return the RefToken
    address _refTokenResult = refTokenBridge.getRefToken(_nativeAsset, _nativeAssetChainId);
    assertEq(_refTokenResult, _refToken);
  }

  function test_GetRefTokenWhenCalledWithANativeTokenAndTheRefTokenDoesntExist(
    address _nativeAsset,
    uint256 _nativeAssetChainId
  ) external view {
    // It should return the RefToken
    address _refTokenResult = refTokenBridge.getRefToken(_nativeAsset, _nativeAssetChainId);

    assertEq(_refTokenResult, address(0));
  }

  function test_GetRefTokenWhenCalledWithARefTokenAndTheRefTokenExists(
    address _refToken,
    uint256 _randomChainId
  ) external {
    refTokenBridge.setRefTokenDeployed(_refToken, true);

    // It should return the RefToken
    address _refTokenResult = refTokenBridge.getRefToken(_refToken, _randomChainId);
    assertEq(_refTokenResult, _refToken);
  }

  function test_GetRefTokenWhenCalledWithARefTokenAndTheRefTokenDoesntExist(
    address _refToken,
    uint256 _randomChainId
  ) external view {
    // It should return the RefToken
    address _refTokenResult = refTokenBridge.getRefToken(_refToken, _randomChainId);
    assertEq(_refTokenResult, address(0));
  }
}
