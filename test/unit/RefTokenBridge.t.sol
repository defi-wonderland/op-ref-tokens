// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {IL2ToL2CrossDomainMessenger} from '@interop-lib/src/interfaces/IL2ToL2CrossDomainMessenger.sol';

import {IExecutor, IRefToken, IRefTokenBridge, RefTokenBridge} from 'src/contracts/RefTokenBridge.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {IERC20Metadata} from 'src/interfaces/external/IERC20Metadata.sol';

contract RefTokenBridgeForTest is RefTokenBridge {
  function setRefTokenAddress(address _nativeToken, address _refToken) external {
    nativeToRefToken[_nativeToken] = _refToken;
  }

  function setRefTokenMetadata(address _refToken, IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata) external {
    refTokenMetadata[_refToken] = _refTokenMetadata;
  }
}

contract RefTokenBridgeUnit is Helpers {
  address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER;
  address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

  /// Contracts
  IL2ToL2CrossDomainMessenger public l2ToL2CrossDomainMessenger;
  RefTokenBridgeForTest public refTokenBridge;

  /// Variables
  address public refToken;
  IRefTokenBridge.RefTokenMetadata public refTokenMetadata;

  mapping(address _refToken => bool _deployed) public refTokenDeployed;

  function setUp() public {
    refTokenBridge = new RefTokenBridgeForTest();

    refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAsset: nativeAsset,
      nativeAssetChainId: nativeAssetChainId,
      nativeAssetName: nativeAssetName,
      nativeAssetSymbol: nativeAssetSymbol,
      nativeAssetDecimals: nativeAssetDecimals
    });

    refToken = _precalculateRefTokenAddress(address(refTokenBridge), refTokenMetadata);
    vm.label(refToken, 'Setup RefToken');
  }

  function test_SendRevertWhen_AmountIsZero(address _token, address _recipient, uint256 _relayChainId) external {
    uint256 _amount = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidAmount.selector);
    refTokenBridge.send(_relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_RecipientIsZero(address _token, uint256 _amount, uint256 _relayChainId) external {
    _amount = bound(_amount, 1, type(uint256).max);
    address _recipient = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRecipient.selector);
    refTokenBridge.send(_relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_RelayChainIdIsTheBlockChainId(
    address _token,
    address _recipient,
    uint256 _amount
  ) external {
    vm.assume(_recipient != address(0));
    _amount = bound(_amount, 1, type(uint256).max);
    uint256 _relayChainId = block.chainid;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.send(_relayChainId, _token, _amount, _recipient);
  }

  function test_SendRevertWhen_RelayChainIdIsZero(address _token, address _recipient, uint256 _amount) external {
    vm.assume(_recipient != address(0));
    _amount = bound(_amount, 1, type(uint256).max);
    uint256 _relayChainId = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.send(_relayChainId, _token, _amount, _recipient);
  }

  function test_SendWhenCalledWithANativeTokenFirstTime() external {
    // It should create the RefToken
    // It should lock the tokens
    // It should send the message to call relay
    // It should emit MessageSent
  }

  function test_SendWhenCallingWithTheNativeTokenAfterTheCreationOfTheRefToken() external {
    // It should lock the tokens
    // It should send the message to call relay
    // It should emit MessageSent
  }

  function test_SendWhenCalledWithARefToken() external {
    // It should burn the tokens
    // It should send the message to call relay
    // It should emit MessageSent
  }

  function test_SendAndExecuteRevertWhen_ExecutionDataDestinationExecutorIsTheZeroAddress(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    _executionData.destinationExecutor = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationExecutor.selector);
    refTokenBridge.sendAndExecute(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_ExecutionDataDestinationChainIdIsZero(
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
    refTokenBridge.sendAndExecute(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_ExecutionDataDestinationChainIdIsTheBlockChainId(
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
    refTokenBridge.sendAndExecute(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_AmountIsZero(
    address _token,
    address _recipient,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);

    uint256 _amount = 0;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidAmount.selector);
    refTokenBridge.sendAndExecute(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_RecipientIsZero(
    address _token,
    uint256 _amount,
    uint256 _relayChainId,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_executionData.destinationExecutor != address(0));
    vm.assume(_executionData.destinationChainId != block.chainid);
    vm.assume(_executionData.destinationChainId != 0);
    _amount = bound(_amount, 1, type(uint256).max);

    address _recipient = address(0);

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRecipient.selector);
    refTokenBridge.sendAndExecute(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteRevertWhen_RelayChainIdIsZero(
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
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.send(_relayChainId, _token, _amount, _recipient);
  }

  function test_SendAndExecuteRevertWhen_RelayChainIdIsTheBlockChainId(
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
    uint256 _relayChainId = block.chainid;

    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.sendAndExecute(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  function test_SendAndExecuteWhenCalledWithANativeTokenFirstTime() external {
    // It should create the RefToken
    // It should lock the tokens
    // It should send the message to call relayAndExecute
    // It should emit MessageSent
  }

  function test_SendAndExecuteWhenCallingWithTheNativeTokenAfterTheCreationOfTheRefToken() external {
    // It should lock the tokens
    // It should send the message to call relayAndExecute
    // It should emit MessageSent
  }

  function test_SendAndExecuteWhenCalledWithARefToken() external {
    // It should burn the tokens
    // It should send the message to call relayAndExecute
    // It should emit MessageSent
  }

  function test_RelayRevertWhen_SenderIsNotTheL2ToL2CrossDomainMessenger(
    address _caller,
    address _token,
    uint256 _amount,
    address _recipient,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    vm.assume(_caller != L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(_caller);
    refTokenBridge.relay(_token, _amount, _recipient, _refTokenMetadata);
  }

  function test_RelayRevertWhen_CrossDomainSenderIsNotTheRefTokenBridge(
    address _randomCaller,
    address _token,
    uint256 _amount,
    address _recipient,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
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
    refTokenBridge.relay(_token, _amount, _recipient, _refTokenMetadata);
  }

  function test_RelayWhenOnTheNativeAssetChain() external {
    // It should unlock the native assets to the recipient
    // It should emit MessageRelayed
  }

  function test_RelayWhenCalledNotOnTheNativeAssetChainAndTheRefTokenIsDeployed() external {
    // It should mint the tokens to the recipient
    // It should emit MessageRelayed and revert
  }

  function test_RelayWhenCalledNotOnTheNativeAssetChainAndTheRefTokenIsNotDeployed() external {
    // It should deploy the RefToken
    // It should mint the tokens to the recipient
    // It should emit MessageRelayed
  }

  function test_RelayAndExecuteRevertWhen_SenderIsNotTheL2ToL2CrossDomainMessenger(
    address _caller,
    address _token,
    uint256 _amount,
    address _recipient,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    IRefTokenBridge.ExecutionData memory _executionData
  ) external {
    vm.assume(_caller != L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    // It should revert
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_Unauthorized.selector);
    vm.prank(_caller);
    refTokenBridge.relayAndExecute(_token, _amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteRevertWhen_CrossDomainSenderIsNotTheRefTokenBridge(
    address _randomCaller,
    address _token,
    uint256 _amount,
    address _recipient,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
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
    refTokenBridge.relayAndExecute(_token, _amount, _recipient, _refTokenMetadata, _executionData);
  }

  function test_RelayAndExecuteWhenOnTheNativeAssetChainAndExecutionSucceeds() external {
    // It should unlock the native assets to the executor
    // It should approve the executor
    // It should execute the data
    // It should emit MessageRelayed
    // It should revoke the executor approval
  }

  function test_RelayAndExecuteWhenOnTheNativeAssetChainAndExecutionFails() external {
    // It should unlock the native assets to the executor
    // It should approve the executor
    // It should execute the data
    // It shouldsend RefTokens to the refund address on the origin chain
    // It should revoke the executor approval
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndTheRefTokenIsDeployedAndExecutionSucceeds() external {
    // It should mint the tokens to the executor
    // It should approve the executor
    // It should execute the data
    // It should emit MessageRelayed
    // It should revoke the executor approval
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndTheRefTokenIsNotDeployedAndExecutionSucceeds() external {
    // It should deploy the RefToken
    // It should mint the tokens to the executor
    // It should approve the executor
    // It should execute the data
    // It should emit MessageRelayed
    // It should revoke the executor approval
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndRefTokenIsDeployedAndExecutionFails() external {
    // It should mint the tokens to the executor
    // It should approve the executor
    // It should execute the data
    // It should burn the RefTokens
    // It shouldsend RefTokens to the refund address on the origin chain
    // It should revoke the executor approval
  }

  function test_RelayAndExecuteWhenNotOnTheNativeAssetChainAndTheRefTokenIsNotDeployedAndExecutionFails() external {
    // It should deploy the RefToken
    // It should mint the tokens to the executor
    // It should approve the executor
    // It should execute the data
    // It should burn the RefTokens
    // It should send RefTokens to the refund address on the origin chain
    // It should revoke the executor approval
  }

  function test_UnlockRevertWhen_CallerIsNotValid() external {
    // It should revert
  }

  function test_UnlockWhenCalledL2ToL2CrossDomainMessenger() external {
    // It should emit TokenUnlocked
    // It should transfer the tokens to user
  }

  function test_UnlockWhenCalledToken() external {
    // It should emit TokenUnlocked
    // It should transfer the tokens to user
  }

  function test_GetRefTokenWhenCalledWithANativeTokenAndTheRefTokenExists() external {
    // It should return the RefToken and its metadata
  }

  function test_GetRefTokenWhenCalledWithANativeTokenAndTheRefTokenDoesntExist() external {
    // It should empty the RefToken and its metadata
  }

  function test_GetRefTokenWhenCalledWithARefTokenAndTheRefTokenExists() external {
    // It should return the RefToken and its metadata
  }

  function test_GetRefTokenWhenCalledWithARefTokenAndTheRefTokenDoesntExist() external {
    // It should return the RefToken and its metadata
  }
}
