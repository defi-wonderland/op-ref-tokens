// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

import {IExecutor, IRefToken, IRefTokenBridge, RefTokenBridge} from 'src/contracts/RefTokenBridge.sol';

import {IERC20, IERC20Metadata} from 'openzeppelin/token/ERC20/extensions/IERC20Metadata.sol';

contract RefTokenBridgeUnit is Helpers {
  address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

  /// Contracts
  IL2ToL2CrossDomainMessenger public l2ToL2CrossDomainMessenger;
  RefTokenBridgeForTest public refTokenBridge;

  /// Variables
  address public refToken;
  IRefTokenBridge.RefTokenMetadata public refTokenMetadata;

  mapping(address _refToken => bool _deployed) public refTokenDeployed;

  function setUp() public {
    l2ToL2CrossDomainMessenger = IL2ToL2CrossDomainMessenger(makeAddr('L2ToL2CrossDomainMessenger'));
    refTokenBridge = new RefTokenBridgeForTest(l2ToL2CrossDomainMessenger);

    refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetAddress: nativeAsset,
      nativeAssetChainId: nativeAssetChainId,
      nativeAssetName: nativeAssetName,
      nativeAssetSymbol: nativeAssetSymbol,
      nativeAssetDecimals: nativeAssetDecimals
    });

    refToken = _precalculateRefTokenAddress(address(refTokenBridge), nativeAsset, refTokenMetadata);
    vm.label(refToken, 'Setup RefToken');
  }

  /// Functions
  function test_ConstructorWhenConstructorIsSet(IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger) external {
    refTokenBridge = new RefTokenBridgeForTest(_l2ToL2CrossDomainMessenger);

    assertEq(address(refTokenBridge.L2_TO_L2_CROSS_DOMAIN_MESSENGER()), address(_l2ToL2CrossDomainMessenger));
  }

  function test_SendRevertWhen_DestinationIdIsTheBlockChainId(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    vm.assume(_refTokenBridgeData.token != address(0));
    vm.assume(_refTokenBridgeData.recipient != address(0));
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = block.chainid;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendRevertWhen_AmountIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _refTokenBridgeData.amount = 0;
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidAmount.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendRevertWhen_RecipientIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _refTokenBridgeData.recipient = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRecipient.selector);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);
  }

  function test_SendRevertWhen_DestinationChainIdIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    vm.assume(_refTokenBridgeData.token != address(0));
    vm.assume(_refTokenBridgeData.recipient != address(0));
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = 0;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
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

    _refTokenMetadata.nativeAssetAddress = _refTokenBridgeData.token;
    _refTokenMetadata.nativeAssetChainId = block.chainid;

    address _precalculatedRefToken =
      _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata.nativeAssetAddress, _refTokenMetadata);
    vm.assume(!refTokenDeployed[_precalculatedRefToken]);
    vm.assume(_precalculatedRefToken.code.length == 0);
    refTokenDeployed[_precalculatedRefToken] = true;

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

    vm.expectCall(_precalculatedRefToken, abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector));

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

    vm.expectEmit(address(refTokenBridge));
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
    ) = refTokenBridge.refTokenMetadata(_precalculatedRefToken);

    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(_nativeAssetChainId, _refTokenMetadata.nativeAssetChainId);
    assertEq(_nativeAssetName, _refTokenMetadata.nativeAssetName);
    assertEq(_nativeAssetSymbol, _refTokenMetadata.nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, _refTokenMetadata.nativeAssetDecimals);
    assertEq(refTokenBridge.nativeToRefToken(_refTokenBridgeData.token), _precalculatedRefToken);
  }

  function test_SendWhenCallingWithTheNativeTokenAnyTimeAfterTheCreationOfTheRefToken(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _refTokenBridgeData.destinationExecutor = address(0);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetAddress: _refTokenBridgeData.token,
      nativeAssetChainId: block.chainid,
      nativeAssetName: 'RefToken',
      nativeAssetSymbol: 'REF',
      nativeAssetDecimals: 18
    });

    refTokenBridge.setRefTokenAddress(_refTokenBridgeData.token, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, _refTokenMetadata);

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

    vm.expectEmit(address(refTokenBridge));
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
    assertEq(refTokenBridge.nativeToRefToken(_refTokenBridgeData.token), refToken);
  }

  function test_SendWhenCalledWithARefToken(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _anotherDestinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);

    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;
    _refTokenBridgeData.token = refToken;

    _refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetAddress: _refTokenMetadata.nativeAssetAddress,
      nativeAssetChainId: block.chainid,
      nativeAssetName: 'RefToken',
      nativeAssetSymbol: 'REF',
      nativeAssetDecimals: 18
    });

    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, _refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_anotherDestinationChainId)
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
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensBurned(_refTokenBridgeData.token, caller, _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      refToken,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );

    vm.prank(caller);
    refTokenBridge.send(_refTokenBridgeData, _destinationChainId);

    // TODO: Missing assertions
  }

  function test_SendAndExecuteRevertWhen_DestinationIdIsTheBlockChainId(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    vm.assume(_refTokenBridgeData.token != address(0));
    vm.assume(_refTokenBridgeData.amount != 0);
    vm.assume(_refTokenBridgeData.recipient != address(0));
    _refTokenBridgeData.destinationExecutor = address(0);

    _destinationChainId = block.chainid;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);
  }

  function test_SendAndExecuteRevertWhen_AmountIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _refTokenBridgeData.amount = 0;

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidAmount.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);
  }

  function test_SendAndExecuteRevertWhen_RecipientIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    vm.assume(_refTokenBridgeData.token != address(0));
    vm.assume(_refTokenBridgeData.amount != 0);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _refTokenBridgeData.recipient = address(0);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidRecipient.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);
  }

  function test_SendAndExecuteRevertWhen_DestinationChainIdIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _destinationChainId = 0;
    vm.assume(_refTokenBridgeData.token != address(0));
    vm.assume(_refTokenBridgeData.amount != 0);
    vm.assume(_refTokenBridgeData.recipient != address(0));
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationChainId.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);
  }

  function test_SendAndExecuteRevertWhen_DestinationExecutorIsZero(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _refTokenBridgeData.destinationExecutor = address(0);
    vm.assume(_refTokenBridgeData.token != address(0));
    vm.assume(_refTokenBridgeData.amount != 0);
    vm.assume(_refTokenBridgeData.recipient != address(0));
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidDestinationExecutor.selector);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);
  }

  function test_SendAndExecuteWhenCalledWithANativeTokenFirstTime(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _executionChainId = bound(_executionChainId, 1, type(uint256).max);

    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);
    _refTokenMetadata.nativeAssetAddress = _refTokenBridgeData.token;
    _refTokenMetadata.nativeAssetChainId = block.chainid;

    address _precalculatedRefToken =
      _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata.nativeAssetAddress, _refTokenMetadata);
    vm.assume(!refTokenDeployed[_precalculatedRefToken]);
    vm.assume(_precalculatedRefToken.code.length == 0);
    refTokenDeployed[_precalculatedRefToken] = true;

    bytes memory _message = abi.encodeWithSelector(
      IRefTokenBridge.relayAndExecute.selector,
      _refTokenBridgeData,
      _refTokenMetadata,
      _destinationChainId,
      _refundAddress,
      _data
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

    vm.expectCall(_precalculatedRefToken, abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector));

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _executionChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(_precalculatedRefToken, _refTokenMetadata.nativeAssetAddress);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensLocked(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _executionChainId
    );

    vm.prank(caller);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);

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
    assertEq(refTokenBridge.nativeToRefToken(_refTokenBridgeData.token), _precalculatedRefToken);
  }

  function test_SendAndExecuteWhenCalledWithANativeTokenFollowingSuccessions(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _executionChainId = bound(_executionChainId, 1, type(uint256).max);
    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetAddress: _refTokenBridgeData.token,
      nativeAssetChainId: block.chainid,
      nativeAssetName: 'RefToken',
      nativeAssetSymbol: 'REF',
      nativeAssetDecimals: 18
    });

    refTokenBridge.setRefTokenAddress(_refTokenBridgeData.token, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message = abi.encodeWithSelector(
      IRefTokenBridge.relayAndExecute.selector,
      _refTokenBridgeData,
      _refTokenMetadata,
      _destinationChainId,
      _refundAddress,
      _data
    );

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
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _executionChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensLocked(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _executionChainId
    );

    vm.prank(caller);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);

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
    assertEq(_nativeAssetAddress, _refTokenBridgeData.token);
    assertEq(refTokenBridge.nativeToRefToken(_refTokenBridgeData.token), refToken);
  }

  function test_SendAndExecuteWhenCalledWithARefToken(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    uint256 _executionChainId,
    uint256 _anotherDestinationChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);
    _executionChainId = bound(_executionChainId, 1, type(uint256).max);
    _anotherDestinationChainId = bound(_anotherDestinationChainId, 1, type(uint256).max);

    _refTokenMetadata.nativeAssetChainId = _anotherDestinationChainId;
    _refTokenBridgeData.token = refToken;

    _refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetAddress: _refTokenMetadata.nativeAssetAddress,
      nativeAssetChainId: block.chainid,
      nativeAssetName: 'RefToken',
      nativeAssetSymbol: 'REF',
      nativeAssetDecimals: 18
    });

    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message = abi.encodeWithSelector(
      IRefTokenBridge.relayAndExecute.selector,
      _refTokenBridgeData,
      _refTokenMetadata,
      _destinationChainId,
      _refundAddress,
      _data
    );

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.NATIVE_ASSET_CHAIN_ID.selector),
      abi.encode(_anotherDestinationChainId)
    );

    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IRefToken.burn.selector, caller, _refTokenBridgeData.amount),
      abi.encode(true)
    );
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(
        IL2ToL2CrossDomainMessenger.sendMessage.selector, _executionChainId, address(refTokenBridge), _message
      ),
      abi.encode(true)
    );

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensBurned(_refTokenBridgeData.token, caller, _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      refToken,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _executionChainId
    );

    vm.prank(caller);
    refTokenBridge.sendAndExecute(_refTokenBridgeData, _executionChainId, _destinationChainId, _refundAddress, _data);
  }

  function test_RelayRevertWhen_CrossDomainSenderIsNotTheRefTokenBridgeAndIsNotValidCaller(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    vm.prank(address(caller));
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidMessenger.selector);
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);
  }

  function test_RelayRevertWhen_SenderIsNotTheL2ToL2CrossDomainMessenger(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(caller))
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidMessenger.selector);
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

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensUnlocked(
      _refTokenBridgeData.token, _refTokenBridgeData.recipient, _refTokenBridgeData.amount
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);
  }

  function test_RelayWhenCalledToRelayWithARefTokenAndIsNotDeployedAndRefTokenIsSent(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) external {
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    if (block.chainid == _refTokenMetadata.nativeAssetChainId) ++_refTokenMetadata.nativeAssetChainId;

    address _precalculatedRefToken =
      _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata.nativeAssetAddress, _refTokenMetadata);
    vm.assume(!refTokenDeployed[_precalculatedRefToken]);
    vm.assume(_precalculatedRefToken.code.length == 0);
    refTokenDeployed[_precalculatedRefToken] = true;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    vm.expectCall(
      address(_precalculatedRefToken),
      abi.encodeWithSelector(IRefToken.mint.selector, _refTokenBridgeData.recipient, _refTokenBridgeData.amount)
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensMinted(
      _precalculatedRefToken, _refTokenBridgeData.recipient, _refTokenBridgeData.amount
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, _refTokenMetadata);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_precalculatedRefToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _refTokenMetadata.nativeAssetChainId);
    assertEq(_nativeAssetName, _refTokenMetadata.nativeAssetName);
    assertEq(_nativeAssetSymbol, _refTokenMetadata.nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, _refTokenMetadata.nativeAssetDecimals);
    assertEq(refTokenBridge.nativeToRefToken(_refTokenMetadata.nativeAssetAddress), _precalculatedRefToken);
  }

  function test_RelayWhenCalledToRelayWithARefTokenAndIsDeployed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    address _deployedRefToken
  ) external {
    vm.assume(refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    vm.assume(_deployedRefToken != refToken);
    _assumeFuzzable(_deployedRefToken);

    refTokenBridge.setRefTokenAddress(refTokenMetadata.nativeAssetAddress, _deployedRefToken);
    refTokenBridge.setRefTokenMetadata(_deployedRefToken, refTokenMetadata);

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

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensMinted(_deployedRefToken, _refTokenBridgeData.recipient, _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relay(_refTokenBridgeData, refTokenMetadata);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_deployedRefToken);

    assertEq(_nativeAssetAddress, refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, refTokenMetadata.nativeAssetChainId);
    assertEq(_nativeAssetName, refTokenMetadata.nativeAssetName);
    assertEq(_nativeAssetSymbol, refTokenMetadata.nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, refTokenMetadata.nativeAssetDecimals);
    assertEq(refTokenBridge.nativeToRefToken(refTokenMetadata.nativeAssetAddress), _deployedRefToken);
  }

  function test_RelayAndExecuteRevertWhen_CrossDomainSenderIsNotTheRefTokenBridgeAndIsNotValidCaller(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    vm.prank(address(caller));
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidMessenger.selector);
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, _destinationChainId, caller, _data);
  }

  function test_RelayAndExecuteRevertWhen_SenderIsNotTheL2ToL2CrossDomainMessenger(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(caller))
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidMessenger.selector);
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, _destinationChainId, caller, _data);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteTheTokensToTheNativeChain(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);
    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    _assumeFuzzable(_refTokenMetadata.nativeAssetAddress);
    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    _refTokenMetadata.nativeAssetChainId = block.chainid;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      _refTokenMetadata.nativeAssetAddress, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true)
    );

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, _destinationChainId, caller, _data);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsNotDeployedAndRefTokenIsSent(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    vm.assume(_refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);
    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);
    if (block.chainid == _refTokenMetadata.nativeAssetChainId) ++_refTokenMetadata.nativeAssetChainId;

    // Precalculate the ref token address, check and store it
    address _precalculatedRefToken =
      _precalculateRefTokenAddress(address(refTokenBridge), _refTokenMetadata.nativeAssetAddress, _refTokenMetadata);
    vm.assume(!refTokenDeployed[_precalculatedRefToken]);
    vm.assume(_precalculatedRefToken.code.length == 0);
    refTokenDeployed[_precalculatedRefToken] = true;

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    // Using expectCall instead of _mockAndExpect because the ref token is not deployed yet, mocking something will
    // create a collsion on deployment
    vm.expectCall(
      address(_precalculatedRefToken),
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount)
    );
    vm.expectCall(address(_precalculatedRefToken), abi.encodeWithSelector(IERC20.approve.selector));

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokenDeployed(_precalculatedRefToken, _refTokenMetadata.nativeAssetAddress);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensMinted(_precalculatedRefToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, _refTokenMetadata, _destinationChainId, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(_precalculatedRefToken);

    assertEq(_nativeAssetAddress, _refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _refTokenMetadata.nativeAssetChainId);
    assertEq(_nativeAssetName, _refTokenMetadata.nativeAssetName);
    assertEq(_nativeAssetSymbol, _refTokenMetadata.nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, _refTokenMetadata.nativeAssetDecimals);
    assertEq(refTokenBridge.nativeToRefToken(_refTokenMetadata.nativeAssetAddress), _precalculatedRefToken);
  }

  // Relay and execute on the non-native asset chain when the ref token is deployed
  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsDeployed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    vm.assume(refTokenMetadata.nativeAssetAddress != _refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);
    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    refTokenBridge.setRefTokenAddress(refTokenMetadata.nativeAssetAddress, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      refToken,
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(refToken, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    _mockAndExpect(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(true)
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensMinted(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, refTokenMetadata, _destinationChainId, caller, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, nativeAssetChainId);
    assertEq(_nativeAssetName, nativeAssetName);
    assertEq(_nativeAssetSymbol, nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, nativeAssetDecimals);
    assertEq(refTokenBridge.nativeToRefToken(refTokenMetadata.nativeAssetAddress), refToken);
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteTheTokensToTheNativeChainAndExecutionFailed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    bytes memory _data,
    uint256 _destinationChainId,
    uint256 _sourceChainId,
    address _refundAddress
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);
    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    _assumeFuzzable(refTokenMetadata.nativeAssetAddress);
    if (_sourceChainId == block.chainid) ++_sourceChainId;

    refTokenMetadata.nativeAssetChainId = block.chainid;

    _refTokenBridgeData.token = nativeAsset;

    refTokenBridge.setRefTokenAddress(refTokenMetadata.nativeAssetAddress, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, refTokenMetadata);

    // Create a new RefTokenBridgeData with the same values but with the recipient as the refund address bc it failed
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeDataOnFailure = _refTokenBridgeData;
    _refTokenBridgeDataOnFailure.recipient = _refundAddress;

    bytes memory _message = abi.encodeCall(IRefTokenBridge.relay, (_refTokenBridgeDataOnFailure, refTokenMetadata));

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(nativeAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCallRevert(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(false)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
      abi.encode(_sourceChainId)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_sourceChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token, _refTokenBridgeData.amount, _refundAddress, address(0), 0
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, refTokenMetadata, _destinationChainId, _refundAddress, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, refTokenMetadata.nativeAssetAddress, '1');
    assertEq(_nativeAssetChainId, block.chainid, '2');
    assertEq(_nativeAssetName, refTokenMetadata.nativeAssetName, '2');
    assertEq(_nativeAssetSymbol, refTokenMetadata.nativeAssetSymbol, '3');
    assertEq(_nativeAssetDecimals, refTokenMetadata.nativeAssetDecimals, '4');
    assertEq(refTokenBridge.nativeToRefToken(refTokenMetadata.nativeAssetAddress), refToken, '5');
  }

  function test_RelayAndExecuteWhenCalledToRelayAndExecuteWithARefTokenAndIsDeployedAndExecutionFailed(
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeData,
    uint256 _sourceChainId,
    uint256 _destinationChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _sourceChainId = bound(_sourceChainId, 1, type(uint256).max - 1);
    _refTokenBridgeData.token = nativeAsset;
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);
    vm.assume(_refTokenBridgeData.destinationExecutor != PERMIT2);

    refTokenMetadata.nativeAssetChainId = _sourceChainId;
    if (_sourceChainId == _destinationChainId) ++_destinationChainId;

    refTokenBridge.setRefTokenAddress(refTokenMetadata.nativeAssetAddress, refToken);
    refTokenBridge.setRefTokenMetadata(refToken, refTokenMetadata);

    // Create a new RefTokenBridgeData with the same values but with the recipient as the refund address bc it failed
    IRefTokenBridge.RefTokenBridgeData memory _refTokenBridgeDataOnFailure = _refTokenBridgeData;
    _refTokenBridgeDataOnFailure.recipient = _refundAddress;

    bytes memory _message = abi.encodeCall(IRefTokenBridge.relay, (_refTokenBridgeDataOnFailure, refTokenMetadata));

    // Mocks and Expects
    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSender.selector),
      abi.encode(address(refTokenBridge))
    );

    _mockAndExpect(
      refToken,
      abi.encodeWithSelector(IRefToken.mint.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(refToken, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

    vm.mockCallRevert(
      _refTokenBridgeData.destinationExecutor,
      abi.encodeWithSelector(IExecutor.execute.selector, _data),
      abi.encode(false)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeWithSelector(IL2ToL2CrossDomainMessenger.crossDomainMessageSource.selector),
      abi.encode(_sourceChainId)
    );

    _mockAndExpect(
      refToken,
      abi.encodeWithSelector(IRefToken.burn.selector, address(refTokenBridge), _refTokenBridgeData.amount),
      abi.encode(true)
    );

    _mockAndExpect(
      address(l2ToL2CrossDomainMessenger),
      abi.encodeCall(IL2ToL2CrossDomainMessenger.sendMessage, (_sourceChainId, address(refTokenBridge), _message)),
      abi.encode(true)
    );

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensMinted(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.RefTokensBurned(refToken, address(refTokenBridge), _refTokenBridgeData.amount);

    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.MessageSent(
      _refTokenBridgeData.token, _refTokenBridgeData.amount, _refundAddress, address(0), 0
    );

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.relayAndExecute(_refTokenBridgeData, refTokenMetadata, _destinationChainId, _refundAddress, _data);

    (
      address _nativeAssetAddress,
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetAddress, refTokenMetadata.nativeAssetAddress);
    assertEq(_nativeAssetChainId, _sourceChainId);
    assertEq(_nativeAssetName, refTokenMetadata.nativeAssetName);
    assertEq(_nativeAssetSymbol, refTokenMetadata.nativeAssetSymbol);
    assertEq(_nativeAssetDecimals, refTokenMetadata.nativeAssetDecimals);
    assertEq(refTokenBridge.nativeToRefToken(refTokenMetadata.nativeAssetAddress), refToken, 'a');
  }

  function test_UnlockRevertWhen_CallerIsNotValid(
    address _notValidCaller,
    address _token,
    address _to,
    uint256 _amount
  ) external {
    vm.assume(_notValidCaller != address(l2ToL2CrossDomainMessenger) && _notValidCaller != _token);

    vm.prank(_notValidCaller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidSender.selector);
    refTokenBridge.unlock(_token, _to, _amount);
  }

  function test_UnlockWhenCalledL2ToL2CrossDomainMessenger(address _token, address _to, uint256 _amount) external {
    _assumeFuzzable(_token);
    // Mocks and Expects
    _mockAndExpect(_token, abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount), abi.encode(true));

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensUnlocked(_token, _to, _amount);

    vm.prank(address(l2ToL2CrossDomainMessenger));
    refTokenBridge.unlock(_token, _to, _amount);
  }

  function test_UnlockWhenCalledToken(address _token, address _to, uint256 _amount) external {
    _assumeFuzzable(_token);
    // Mocks and Expects
    _mockAndExpect(_token, abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount), abi.encode(true));

    // Emits
    vm.expectEmit(address(refTokenBridge));
    emit IRefTokenBridge.TokensUnlocked(_token, _to, _amount);

    vm.prank(_token);
    refTokenBridge.unlock(_token, _to, _amount);
  }
}

contract RefTokenBridgeForTest is RefTokenBridge {
  constructor(IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger) RefTokenBridge(_l2ToL2CrossDomainMessenger) {}

  function setRefTokenAddress(address _nativeToken, address _refToken) external {
    nativeToRefToken[_nativeToken] = _refToken;
  }

  function setRefTokenMetadata(address _refToken, IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata) external {
    refTokenMetadata[_refToken] = _refTokenMetadata;
  }
}
