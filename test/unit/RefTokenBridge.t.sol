// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Helpers} from 'test/utils/Helpers.t.sol';

import {IL2ToL2CrossDomainMessenger} from 'optimism/L2/IL2ToL2CrossDomainMessenger.sol';

import {IRefToken, IRefTokenBridge, RefTokenBridge} from 'src/contracts/RefTokenBridge.sol';

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

  function setUp() public override {
    super.setUp();
    l2ToL2CrossDomainMessenger = IL2ToL2CrossDomainMessenger(makeAddr('L2ToL2CrossDomainMessenger'));
    refTokenBridge = new RefTokenBridgeForTest(l2ToL2CrossDomainMessenger);

    refTokenMetadata = IRefTokenBridge.RefTokenMetadata({
      nativeAssetChainId: block.chainid,
      nativeAssetName: refTokenName,
      nativeAssetSymbol: refTokenSymbol,
      nativeAssetDecimals: refTokenDecimals
    });
    refToken = _precalculateRefTokenAddress(address(refTokenBridge), nativeAsset, refTokenMetadata);
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
    uint256 _destinationChainId
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _refTokenBridgeData.destinationExecutor = address(0);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, refTokenMetadata);

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.name.selector),
      abi.encode(refTokenMetadata.nativeAssetName)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.symbol.selector),
      abi.encode(refTokenMetadata.nativeAssetSymbol)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.decimals.selector),
      abi.encode(refTokenMetadata.nativeAssetDecimals)
    );

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
    vm.expectEmit();
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
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetChainId, block.chainid);
    assertEq(_nativeAssetName, 'RefToken');
    assertEq(_nativeAssetSymbol, 'REF');
    assertEq(_nativeAssetDecimals, 18);
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken);
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
    vm.expectEmit();
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
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

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
    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(_refTokenBridgeData.token, _refTokenBridgeData.amount);

    vm.expectEmit();
    emit IRefTokenBridge.MessageSent(
      refToken,
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
    bytes memory _data
  ) external {
    _assumeFuzzable(_refTokenBridgeData.token);
    _assumeFuzzable(_refTokenBridgeData.recipient);
    _assumeFuzzable(_refTokenBridgeData.destinationExecutor);

    _refTokenBridgeData.amount = bound(_refTokenBridgeData.amount, 1, type(uint256).max);
    _destinationChainId = bound(_destinationChainId, 1, type(uint256).max);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relayAndExecute.selector, _refTokenBridgeData, refTokenMetadata, _data);

    // Mocks and Expects
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.name.selector),
      abi.encode(refTokenMetadata.nativeAssetName)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.symbol.selector),
      abi.encode(refTokenMetadata.nativeAssetSymbol)
    );
    _mockAndExpect(
      _refTokenBridgeData.token,
      abi.encodeWithSelector(IERC20Metadata.decimals.selector),
      abi.encode(refTokenMetadata.nativeAssetDecimals)
    );

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
    vm.expectEmit();
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
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

    assertEq(_nativeAssetChainId, block.chainid, '1');
    assertEq(_nativeAssetName, 'RefToken', '2');
    assertEq(_nativeAssetSymbol, 'REF', '3');
    assertEq(_nativeAssetDecimals, 18, '4');
    assertEq(refTokenBridge.refTokenAddress(_refTokenBridgeData.token), refToken, '5');
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
    vm.expectEmit();
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
      uint256 _nativeAssetChainId,
      string memory _nativeAssetName,
      string memory _nativeAssetSymbol,
      uint8 _nativeAssetDecimals
    ) = refTokenBridge.refTokenMetadata(refToken);

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
    uint256 _anotherDestinationChainId,
    uint8 _nativeAssetDecimals,
    bytes memory _data
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
      nativeAssetChainId: block.chainid,
      nativeAssetName: 'RefToken',
      nativeAssetSymbol: 'REF',
      nativeAssetDecimals: _nativeAssetDecimals
    });

    refTokenBridge.setRefTokenMetadata(refToken, _refTokenMetadata);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relayAndExecute.selector, _refTokenBridgeData, _refTokenMetadata, _data);

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
    vm.expectEmit();
    emit IRefTokenBridge.TokensBurned(_refTokenBridgeData.token, _refTokenBridgeData.amount);

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

  function test_UnlockRevertWhen_CallerIsNotValid(address _token, address _to, uint256 _amount) external {
    vm.prank(caller);
    vm.expectRevert(IRefTokenBridge.RefTokenBridge_InvalidSender.selector);
    refTokenBridge.unlock(_token, _to, _amount);
  }

  function test_UnlockWhenCalledRefTokenBridge(address _token, address _to, uint256 _amount) external {
    _assumeFuzzable(_token);
    // Mocks and Expects
    _mockAndExpect(_token, abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount), abi.encode(true));

    // Emits
    vm.expectEmit();
    emit IRefTokenBridge.TokensUnlocked(_token, _to, _amount);

    vm.prank(address(refTokenBridge));
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
    address _refTokenPrecalculated = _precalculateRefTokenAddress(_refTokenBridge, _nativeAsset, _refTokenMetadata);

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
