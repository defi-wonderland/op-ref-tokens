// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

import {IExecutor, IRefToken, IRefTokenBridge, RefTokenBridge} from 'src/contracts/RefTokenBridge.sol';

import {IERC20, IERC20Metadata} from 'openzeppelin/token/ERC20/extensions/IERC20Metadata.sol';

contract RefTokenBridgeUnit is Helpers {
  /// Contracts
  IL2ToL2CrossDomainMessenger public l2ToL2CrossDomainMessenger;
  RefTokenBridgeForTest public refTokenBridge;

  /// Variables
  address public nativeAsset = makeAddr('NativeAsset');
  address public refToken;
  IRefTokenBridge.RefTokenMetadata public refTokenMetadata;
  string public refTokenName = 'RefToken';
  string public refTokenSymbol = 'REF';
  uint8 public refTokenDecimals = 18;

  mapping(bytes32 _salt => mapping(bytes32 _initCodeHash => bool _used)) public refTokenDeployed;

  function setUp() public override {
    super.setUp();
    l2ToL2CrossDomainMessenger = IL2ToL2CrossDomainMessenger(makeAddr('L2ToL2CrossDomainMessenger'));
    refTokenBridge = new RefTokenBridgeForTest(l2ToL2CrossDomainMessenger);

    refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetAddress: nativeAsset,
      nativeAssetChainId: block.chainid,
      nativeAssetName: refTokenName,
      nativeAssetSymbol: refTokenSymbol,
      nativeAssetDecimals: refTokenDecimals
    });

    bytes32 _salt;
    bytes32 _initCodeHash;
    (refToken, _salt, _initCodeHash) =
      _precalculateRefTokenAddress(address(refTokenBridge), nativeAsset, refTokenMetadata);
    refTokenDeployed[_salt][_initCodeHash] = true;
  }

  /// Functions
  function test_ConstructorWhenConstructorIsSet(IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger) external {
    refTokenBridge = new RefTokenBridgeForTest(_l2ToL2CrossDomainMessenger);

    assertEq(address(refTokenBridge.L2_TO_L2_CROSS_DOMAIN_MESSENGER()), address(_l2ToL2CrossDomainMessenger));
  }

  function test_SendRevertWhen_TokenIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _refTokenBridgeData.token = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendRevertWhen_AmountIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _refTokenBridgeData.amount = 0;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendRevertWhen_RecipientIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _refTokenBridgeData.recipient = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendRevertWhen_DestinationChainIdIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _destinationChainId = 0;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendWhenCalledWithANativeTokenFirstTime(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _refTokenBridgeData.destinationExecutor = address(0);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    // Hardcoded to this chain id since it is the first time the ref token is deployed when the native asset is locked
    _refTokenMetadata.nativeAssetChainId = block.chainid;

    (address _precalculatedRefToken, bytes32 _salt, bytes32 _initCodeHash) =
      _precalculateRefTokenAddress(address(refTokenBridge), _refTokenBridgeData.token, _refTokenMetadata);

    if (refTokenDeployed[_salt][_initCodeHash]) vm.skip(true);
    refTokenDeployed[_salt][_initCodeHash] = true;

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.name.selector),
      abi.encode(_refTokenMetadata.nativeAssetName)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.symbol.selector),
      abi.encode(_refTokenMetadata.nativeAssetSymbol)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.decimals.selector),
      abi.encode(_refTokenMetadata.nativeAssetDecimals)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensLocked(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    // TODO: Due to a Foundry issue, this expect fails even though the event matches the emitted one
    // vm.expectEmit(address(refTokenBridge));
    // emit IRefTokenBridge.RefTokenDeployed(_precalculatedRefToken, _refTokenBridgeData.token);

    vm.prank(caller);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_precalculatedRefToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, _refTokenMetadata.nativeAssetChainId);
    assertEq(_nativeAssetName, _refTokenMetadata.nativeAssetName);
    assertEq(_nativeAssetSymbol, _refTokenMetadata.nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, _refTokenMetadata.nativeAssetDecimals);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), _precalculatedRefToken);
  }

  function test_SendWhenCalledWithANativeTokenFollowingSuccessions(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _refTokenBridgeData.destinationExecutor = address(0);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    refTokenBridge.setRefTokenAddress(_refTokenBridgeData.token, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, refTokenMetadata);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      refToken, abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector), abi.encode(block.chainid)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensLocked(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(caller);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, block.chainid);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken);
  }

  function test_SendWhenCalledWithARefToken(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _nativeAssetChainId
  ) external {
    if (_nativeAssetChainId == block.chainid) ++_nativeAssetChainId;

    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _nativeAssetChainId = bound(_nativeAssetChainId, 1, type(uint256).max);

    _refTokenMetadata.nativeAssetChainId = _nativeAssetChainId;
    _refTokenBridgeData.token = refToken;

    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_nativeAssetChainId)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.burn.selector, caller, _refTokenBridgeData.amount),
      abi.encode(true)
    );
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(_refTokenBridgeData.token, caller, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(caller);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendAndExecuteRevertWhen_TokenIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _refTokenBridgeData.token = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);
  }

  function test_SendAndExecuteRevertWhen_AmountIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _refTokenBridgeData.amount = 0;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);
  }

  function test_SendAndExecuteRevertWhen_RecipientIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _refTokenBridgeData.recipient = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);
  }

  function test_SendAndExecuteRevertWhen_DestinationChainIdIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _destinationChainId = 0;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);
  }

  function test_SendAndExecuteRevertWhen_DestinationExecutorIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _refTokenBridgeData.destinationExecutor = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidData.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);
  }

  function test_SendAndExecuteWhenCalledWithANativeTokenFirstTime(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    // Hardcoded to this chain id since it is the first time the ref token is deployed when the native asset is locked
    _refTokenMetadata.nativeAssetChainId = block.chainid;

    (address _precalculatedRefToken, bytes32 _salt, bytes32 _initCodeHash) =
      _precalculateRefTokenAddress(address(refTokenBridge), _refTokenBridgeData.token, _refTokenMetadata);

    if (refTokenDeployed[_salt][_initCodeHash]) vm.skip(true);
    refTokenDeployed[_salt][_initCodeHash] = true;

    bytes memory _message = abi.encodeWithSelector(
      IRefTokenBridge.relayAndExecute.selector, _refTokenBridgeData, _refTokenMetadata, caller, _data
    );

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.name.selector),
      abi.encode(_refTokenMetadata.nativeAssetName)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.symbol.selector),
      abi.encode(_refTokenMetadata.nativeAssetSymbol)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.decimals.selector),
      abi.encode(_refTokenMetadata.nativeAssetDecimals)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensLocked(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    // TODO: Due to a Foundry issue, this expect fails even though the event matches the emitted one
    // vm.expectEmit(address(refTokenBridge));
    // emit IRefTokenBridge.RefTokenDeployed(_precalculatedRefToken, _refTokenBridgeData.token);

    vm.prank(caller);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_precalculatedRefToken);

    assertEq(_nativeAssetChainId, _refTokenMetadata.nativeAssetChainId, '1');
    assertEq(_nativeAssetName, _refTokenMetadata.nativeAssetName, '2');
    assertEq(_nativeAssetSymbol, _refTokenMetadata.nativeAssetSymbol, '3');
    assertEq(_nativeAssetDecimals, _refTokenMetadata.nativeAssetDecimals, '4');
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), _precalculatedRefToken, '5');
  }

  function test_SendAndExecuteWhenCalledWithANativeTokenFollowingSuccessions(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    refTokenBridge.setRefTokenAddress(_refTokenBridgeData.token, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, refTokenMetadata);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relayAndExecute.selector, _refTokenBridgeData, refTokenMetadata, _data);

    // Mocks and Expects
    _mockAndExpect(
      refToken, abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector), abi.encode(block.chainid)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensLocked(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(caller);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, block.chainid);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken);
  }

  function test_SendAndExecuteWhenCalledWithARefToken(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _nativeAssetChainId,
    bytes memory _data
  ) external {
    if (_nativeAssetChainId == block.chainid) ++_nativeAssetChainId;

    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _nativeAssetChainId = bound(_nativeAssetChainId, 1, type(uint256).max);

    _refTokenMetadata.nativeAssetChainId = _nativeAssetChainId;
    _refTokenBridgeData.token = refToken;

    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message = abi.encodeWithSelector(
      IRefTokenBridge.relayAndExecute.selector, _refTokenBridgeData, _refTokenMetadata, caller, _data
    );

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_nativeAssetChainId)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.burn.selector, caller, _refTokenBridgeData.amount),
      abi.encode(true)
    );
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(_refTokenBridgeData.token, caller, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      refToken,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(caller);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _destinationChainId, _data);
  }

  function test_RelayRevertWhen_CrossDomainSenderIsNotTheRefTokenBridgeAndIsNotValidCaller(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    vm.prank(address(caller));
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidMessage.selector);
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);
  }

  function test_RelayWhenCalledToRelayTheTokensToTheNativeChain(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    _refTokenMetadata.nativeAssetChainId = block.chainid;
    _assumeFuzzable(_refTokenBridgeData.token);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20.transfer.selector, _refTokenBridgeData.recipient, _refTokenBridgeData.amount),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensUnlocked(
      _refTokenBridgeData.token, _refTokenBridgeData.recipient, _refTokenBridgeData.amount
    );

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _refTokenMetadata.nativeAssetChainId
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);
  }

  function test_RelayWhenCalledToRelayWithARefTokenAndIsNotDeployedAndNativeTokenIsSent(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);

    _refTokenBridgeData.token = _refTokenMetadata.nativeAssetAddress;
    _refTokenMetadata.nativeAssetAddress = _refTokenBridgeData.token;
    _refTokenMetadata.nativeAssetName = 'RefToken';
    _refTokenMetadata.nativeAssetSymbol = 'REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.mint.selector, _refTokenBridgeData.recipient, _refTokenBridgeData.amount),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(refToken, _refTokenBridgeData.recipient, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      block.chainid
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken);
  }

  function test_RelayWhenCalledToRelayWithARefTokenAndIsNotDeployedAndRefTokenIsSent(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);

    _refTokenMetadata.nativeAssetName = 'RefToken';
    _refTokenMetadata.nativeAssetSymbol = 'REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.mint.selector, _refTokenBridgeData.recipient, _refTokenBridgeData.amount),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(refToken, _refTokenBridgeData.recipient, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      block.chainid
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenMetadata.nativeAssetAddress), refToken);
  }

  function test_RelayWhenCalledToRelayWithARefTokenAndIsDeployed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId,
    address _deployedRefToken
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    vm.assume(_deployedRefToken != refToken);
    _assumeFuzzable(_deployedRefToken);

    _refTokenMetadata.nativeAssetName = 'DeployedRefToken';
    _refTokenMetadata.nativeAssetSymbol = 'DEPLOYED_REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    refTokenBridge.setRefTokenAddress(_refTokenMetadata.nativeAssetAddress, _deployedRefToken);
    refTokenBridge.setRefTokenMetadata(_deployedRefToken, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      _deployedRefToken,
      abi.encodeWithSelector(IRefToken.mint.selector, _refTokenBridgeData.recipient, _refTokenBridgeData.amount),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(_deployedRefToken, _refTokenBridgeData.recipient, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      block.chainid
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_deployedRefToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'DeployedRefToken');
    assertEq(_nativeAssetSymbol, 'DEPLOYED_REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenMetadata.nativeAssetAddress), _deployedRefToken);
  }

  function test_RelayAndExecuteRevertWhen_CrossDomainSenderIsNotTheRefTokenBridgeAndIsNotValidCaller(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    bytes memory _data
  ) external {
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    vm.prank(address(caller));
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidMessage.selector);
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteTheTokensToTheNativeChain(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenMetadata.nativeAssetChainId = block.chainid;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(
        IERC20.approve.selector, _refTokenBridgeData.destinationExecutor, _refTokenBridgeData.amount
      ),
      abi.encode(true)
    );

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _refTokenMetadata.nativeAssetChainId
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsNotDeployedAndNativeTokenIsSent(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId,
    bytes memory _data
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.token = _refTokenMetadata.nativeAssetAddress;
    _refTokenMetadata.nativeAssetAddress = _refTokenBridgeData.token;
    _refTokenMetadata.nativeAssetName = 'RefToken';
    _refTokenMetadata.nativeAssetSymbol = 'REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(
        IERC20.approve.selector, _refTokenBridgeData.destinationExecutor, _refTokenBridgeData.amount
      ),
      abi.encode(true)
    );

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      block.chainid
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsNotDeployedAndRefTokenIsSent(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId,
    bytes memory _data
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenMetadata.nativeAssetName = 'RefToken';
    _refTokenMetadata.nativeAssetSymbol = 'REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(
        IERC20.approve.selector, _refTokenBridgeData.destinationExecutor, _refTokenBridgeData.amount
      ),
      abi.encode(true)
    );

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      block.chainid
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenMetadata.nativeAssetAddress), refToken);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsDeployed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId,
    address _deployedRefToken,
    bytes memory _data
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    vm.assume(_deployedRefToken != refToken);
    _assumeFuzzable(_deployedRefToken);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenMetadata.nativeAssetName = 'DeployedRefToken';
    _refTokenMetadata.nativeAssetSymbol = 'DEPLOYED_REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    refTokenBridge.setRefTokenAddress(_refTokenMetadata.nativeAssetAddress, _deployedRefToken);
    refTokenBridge.setRefTokenMetadata(_deployedRefToken, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      _deployedRefToken,
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      _deployedRefToken,
      abi.encodeWithSelector(
        IERC20.approve.selector, _refTokenBridgeData.destinationExecutor, _refTokenBridgeData.amount
      ),
      abi.encode(true)
    );

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(_deployedRefToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      block.chainid
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_deployedRefToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'DeployedRefToken');
    assertEq(_nativeAssetSymbol, 'DEPLOYED_REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenMetadata.nativeAssetAddress), _deployedRefToken);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteTheTokensToTheNativeChainAndExecutionFailed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    bytes memory _data,
    uint256 _destinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenMetadata.nativeAssetChainId = block.chainid;

    // Create a new RefTokenBridgeData with the same values but with the recipient as the caller
    IRefTokenBridge.RefTokenBridgeData memory _newRefTokenBridgeData = _refTokenBridgeData;
    _newRefTokenBridgeData.recipient = caller;

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _newRefTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(_refTokenBridgeData.token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCallRevert(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(false)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
      abi.encode(_destinationChainId)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _newRefTokenBridgeData.token,
      _newRefTokenBridgeData.amount,
      _newRefTokenBridgeData.recipient,
      _newRefTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsNotDeployedAndNativeTokenIsSentAndExecutionFailed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _anotherDestinationChainId,
    bytes memory _data
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.token = _refTokenMetadata.nativeAssetAddress;
    _refTokenMetadata.nativeAssetAddress = _refTokenBridgeData.token;
    _refTokenMetadata.nativeAssetName = 'RefToken';
    _refTokenMetadata.nativeAssetSymbol = 'REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    // Create a new RefTokenBridgeData with the same values but with the recipient as the caller
    IRefTokenBridge.RefTokenBridgeData memory _newRefTokenBridgeData = _refTokenBridgeData;
    _newRefTokenBridgeData.recipient = caller;

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _newRefTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.burn.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(address(refToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCallRevert(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(false)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
      abi.encode(_destinationChainId)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _newRefTokenBridgeData.token,
      _newRefTokenBridgeData.amount,
      _newRefTokenBridgeData.recipient,
      _newRefTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsNotDeployedAndRefTokenIsSentAndExecutionFailed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _anotherDestinationChainId,
    bytes memory _data
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);

    _refTokenMetadata.nativeAssetName = 'RefToken';
    _refTokenMetadata.nativeAssetSymbol = 'REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    // Create a new RefTokenBridgeData with the same values but with the recipient as the caller
    IRefTokenBridge.RefTokenBridgeData memory _newRefTokenBridgeData = _refTokenBridgeData;
    _newRefTokenBridgeData.recipient = caller;

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _newRefTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      address(refToken),
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(address(refToken), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCallRevert(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(false)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
      abi.encode(_destinationChainId)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _newRefTokenBridgeData.token,
      _newRefTokenBridgeData.amount,
      _newRefTokenBridgeData.recipient,
      _newRefTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(refTokenBridge.refTokenAddress(_refTokenMetadata.nativeAssetAddress), refToken);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsDeployedAndExecutionFailed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _anotherDestinationChainId,
    address _deployedRefToken,
    bytes memory _data,
    uint256 _destinationChainId
  ) external {
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    vm.assume(_deployedRefToken != refToken);
    _assumeFuzzable(_deployedRefToken);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenMetadata.nativeAssetName = 'DeployedRefToken';
    _refTokenMetadata.nativeAssetSymbol = 'DEPLOYED_REF';
    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;

    refTokenBridge.setRefTokenAddress(_refTokenMetadata.nativeAssetAddress, _deployedRefToken);
    refTokenBridge.setRefTokenMetadata(_deployedRefToken, _refTokenMetadata);

    // Create a new RefTokenBridgeData with the same values but with the recipient as the caller
    IRefTokenBridge.RefTokenBridgeData memory _newRefTokenBridgeData = _refTokenBridgeData;
    _newRefTokenBridgeData.recipient = caller;

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _newRefTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      _deployedRefToken,
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(_deployedRefToken, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCallRevert(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(false)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
      abi.encode(_destinationChainId)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _destinationChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    vm.expectEmit();
    emit IRefTokenBridge.TokensMinted(_deployedRefToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(_deployedRefToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      _newRefTokenBridgeData.token,
      _newRefTokenBridgeData.amount,
      _newRefTokenBridgeData.recipient,
      _newRefTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_deployedRefToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _anotherDestinationChainId);
    assertEq(_nativeAssetName, 'DeployedRefToken');
    assertEq(_nativeAssetSymbol, 'DEPLOYED_REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenMetadata.nativeAssetAddress), _deployedRefToken);
  }

  function test_UnlockRevertWhen_CallerIsNotValid(address _token, address _to, uint256 _amount) external {
    vm.prank(caller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidSender.selector);
    refTokenBridge.unlock(_token, _to, _amount);
  }

  function test_UnlockWhenCalledL2ToL2CrossDomainMessenger(address _token, address _to, uint256 _amount) external {
    _assumeFuzzable(_token);
    // Mocks and Expects
    _mockAndExpect(_token, abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount), abi.encode(true));

    // Emits
    vm.expectEmit();
    emit IRefTokenBridge.TokensUnlocked(_token, _to, _amount);

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.unlock(_token, _to, _amount);
  }

  function test_UnlockWhenCalledToken(address _token, address _to, uint256 _amount) external {
    _assumeFuzzable(_token);
    // Mocks and Expects
    _mockAndExpect(_token, abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount), abi.encode(true));

    // Emits
    vm.expectEmit();
    emit IRefTokenBridge.TokensUnlocked(_token, _to, _amount);

    vm.prank(_token);
    refTokenBridge.unlock(_token, _to, _amount);
  }

  // Unit test for the deployRefToken function
  function test_DeployRefToken(
    address _refTokenBridge,
    address _nativeAsset,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    _assumeFuzzable(_refTokenBridge);

    // Etch the ref token bridge code to the fuzzed address to fuzz also the deployer address
    vm.etch(_refTokenBridge, address(refTokenBridge).code);

    // Precalculate the ref token address
    (address _refTokenPrecalculated, bytes32 _salt, bytes32 _initCodeHash) =
      _precalculateRefTokenAddress(_refTokenBridge, _nativeAsset, _refTokenMetadata);
    refTokenDeployed[_salt][_initCodeHash] = true;

    // Emits
    vm.expectEmit(true, true, true, true, _refTokenBridge);
    emit IRefTokenBridge.RefTokenDeployed(_refTokenPrecalculated, _nativeAsset);

    address _refToken = RefTokenBridgeForTest(_refTokenBridge).deployRefToken(_nativeAsset, _refTokenMetadata);

    assertEq(_refToken, _refTokenPrecalculated);
  }
}

contract RefTokenBridgeForTest is RefTokenBridge {
  constructor(IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger) RefTokenBridge(_l2ToL2CrossDomainMessenger) {}

  function setRefTokenAddress(address _nativeToken, address _refToken) external {
    refTokenAddress[_nativeToken] = _refToken;
  }

  function setRefTokenMetadata(address _refToken, IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata) external {
    refTokenMetadata[_refToken] = _refTokenMetadata;
  }

  function deployRefToken(
    address _nativeAsset,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external returns (address) {
    return _deployRefToken(_nativeAsset, _refTokenMetadata);
  }
}
