// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRefToken} from 'interfaces/IRefToken.sol';
import {IL2ToL2CrossDomainMessenger, IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from 'interfaces/external/IERC20Metadata.sol';
import {IExecutor} from 'interfaces/external/IExecutor.sol';

import {RefToken} from 'contracts/RefToken.sol';

/**
 * @title RefTokenBridge
 * @notice A bridge for bridging locked native assets and ERC-20s across OP-Stack chains.
 */
contract RefTokenBridge is IRefTokenBridge {
  /**
   * @notice The L2 to L2 cross domain messenger address
   */
  IL2ToL2CrossDomainMessenger public immutable L2_TO_L2_CROSS_DOMAIN_MESSENGER;

  /**
   * @notice The RefToken metadata
   */
  mapping(address _refToken => RefTokenMetadata _refTokenMetadata) public refTokenMetadata;

  /**
   * @notice The RefToken address
   */
  mapping(address _nativeToken => address _refToken) public nativeToRefToken;

  /**
   * @notice Constructor
   * @param _l2ToL2CrossDomainMessenger The L2 to L2 cross domain messenger address
   */
  constructor(IL2ToL2CrossDomainMessenger _l2ToL2CrossDomainMessenger) {
    L2_TO_L2_CROSS_DOMAIN_MESSENGER = _l2ToL2CrossDomainMessenger;
  }

  /**
   * @notice Send token to the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _destinationChainId The destination chain ID
   */
  function send(RefTokenBridgeData calldata _refTokenBridgeData, uint256 _destinationChainId) external {
    _sendDataCheck(_refTokenBridgeData, _destinationChainId);

    (RefTokenMetadata memory _refTokenMetadata, address _refToken) = _getRefTokenMetadata(_refTokenBridgeData.token);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relay.selector, _refTokenBridgeData, _refTokenMetadata);

    _sendMessage(_refTokenBridgeData, _refToken, _destinationChainId, _message);
  }

  /**
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _executionChainId The execution chain ID
   * @param _destinationChainId The destination chain ID
   * @param _refundAddress The address to refund the token to if the execution fails
   * @param _data The data to be executed on the destination chain
   */
  function sendAndExecute(
    RefTokenBridgeData calldata _refTokenBridgeData,
    uint256 _executionChainId,
    uint256 _destinationChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    _sendDataCheck(_refTokenBridgeData, _destinationChainId);
    if (_refTokenBridgeData.destinationExecutor == address(0)) revert RefTokenBridge_InvalidDestinationExecutor();
    if (_executionChainId == 0 || _executionChainId == block.chainid) revert RefTokenBridge_InvalidExecutionChainId();

    (RefTokenMetadata memory _refTokenMetadata, address _refToken) = _getRefTokenMetadata(_refTokenBridgeData.token);

    bytes memory _message = abi.encodeCall(
      IRefTokenBridge.relayAndExecute,
      (_refTokenBridgeData, _refTokenMetadata, _destinationChainId, _refundAddress, _data)
    );

    _sendMessage(_refTokenBridgeData, _refToken, _executionChainId, _message);
  }

  /**
   * @notice Relay token from the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _refTokenMetadata The metadata of the RefToken
   */
  function relay(RefTokenBridgeData calldata _refTokenBridgeData, RefTokenMetadata calldata _refTokenMetadata) external {
    if (
      msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        || L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSender() != address(this)
    ) {
      revert RefTokenBridge_InvalidMessenger();
    }

    if (block.chainid == _refTokenMetadata.nativeAssetChainId) {
      unlock(_refTokenBridgeData.token, _refTokenBridgeData.recipient, _refTokenBridgeData.amount);
    } else {
      address _refToken = nativeToRefToken[_refTokenMetadata.nativeAssetAddress];
      if (_refToken == address(0)) {
        _refToken = _setRefTokenMetadata(_refTokenMetadata.nativeAssetAddress, _refTokenMetadata);
      }
      _mint(_refToken, _refTokenBridgeData.recipient, _refTokenBridgeData.amount);
    }

    emit MessageRelayed(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor
    );
  }

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _destinationChainId The destination chain ID
   * @param _refundAddress The address to refund the token to if the execution fails
   * @param _data The data to be executed on the destination chain
   */
  function relayAndExecute(
    RefTokenBridgeData memory _refTokenBridgeData,
    RefTokenMetadata calldata _refTokenMetadata,
    uint256 _destinationChainId,
    address _refundAddress,
    bytes memory _data
  ) external {
    if (
      msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        || L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSender() != address(this)
    ) {
      revert RefTokenBridge_InvalidMessenger();
    }

    address _token;
    if (block.chainid == _refTokenMetadata.nativeAssetChainId) {
      _token = _refTokenMetadata.nativeAssetAddress;
    } else {
      _token = nativeToRefToken[_refTokenMetadata.nativeAssetAddress];
      if (_token == address(0)) _token = _setRefTokenMetadata(_refTokenMetadata.nativeAssetAddress, _refTokenMetadata);

      _mint(_token, address(this), _refTokenBridgeData.amount);
    }
    IERC20(_token).approve(_refTokenBridgeData.destinationExecutor, _refTokenBridgeData.amount);

    // Execute the data on the destination chain executor
    try IExecutor(_refTokenBridgeData.destinationExecutor).execute(
      _token, _refTokenBridgeData.recipient, _refTokenBridgeData.amount, _destinationChainId, _data
    ) {
      emit MessageRelayed(
        _refTokenBridgeData.token,
        _refTokenBridgeData.amount,
        _refTokenBridgeData.recipient,
        _refTokenBridgeData.destinationExecutor
      );
    } catch {
      // If the token is not the native asset, burn the token
      if (block.chainid != _refTokenMetadata.nativeAssetChainId) {
        _burn(_token, address(this), _refTokenBridgeData.amount);
      }

      _refTokenBridgeData.recipient = _refundAddress;

      bytes memory _message = abi.encodeCall(IRefTokenBridge.relay, (_refTokenBridgeData, _refTokenMetadata));

      // TODO: Just use `send()`?
      L2_TO_L2_CROSS_DOMAIN_MESSENGER.sendMessage(
        L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSource(), address(this), _message
      );

      // Destination executor and execution chain id are empty since we are just sending the tokens back to the
      // refund address without any execution
      emit MessageSent(
        _refTokenBridgeData.token, _refTokenBridgeData.amount, _refTokenBridgeData.recipient, address(0), 0
      );
    }

    IERC20(_token).approve(_refTokenBridgeData.destinationExecutor, 0);
  }

  /**
   * @notice Internal function to unlock the token
   * @dev This function is used to unlock the token on the source chain
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _token, address _to, uint256 _amount) public {
    if (msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER) && msg.sender != _token) {
      revert RefTokenBridge_InvalidSender();
    }

    IERC20(_token).transfer(_to, _amount);

    emit TokensUnlocked(_token, _to, _amount);
  }

  /**
   * @notice Internal function to lock the token
   * @dev This function is used to lock the token on the source chain
   * @param _token The token to be locked
   * @param _amount The amount of token to be locked
   */
  function _lock(address _token, uint256 _amount) internal {
    IERC20(_token).transferFrom(msg.sender, address(this), _amount);

    emit TokensLocked(_token, _amount);
  }

  /**
   * @notice Internal function to mint the RefToken
   * @dev This function is used to mint the RefToken on the destination chain
   * @param _token The token to be minted
   * @param _to The address to mint the token to
   * @param _amount The amount of token to be minted
   */
  function _mint(address _token, address _to, uint256 _amount) internal {
    IRefToken(_token).mint(_to, _amount);

    emit RefTokensMinted(_token, _to, _amount);
  }

  /**
   * @notice Internal function to burn the RefToken
   * @dev    This function is used to burn the RefToken on the destination chain
   * @param _token The token to be burned
   * @param _to The address to burn the token to
   * @param _amount The amount of token to be burned
   */
  function _burn(address _token, address _to, uint256 _amount) internal {
    IRefToken(_token).burn(_to, _amount);

    emit RefTokensBurned(_token, _to, _amount);
  }

  /**
   * @notice Internal function to get the RefToken metadata
   * @dev    If the token is the native asset, it should implement name() and symbol() methods
   * @param _token The token to get the metadata from
   * @return _refTokenMetadata The RefToken metadata
   * @return _refToken The RefToken address
   */
  function _getRefTokenMetadata(address _token)
    internal
    returns (RefTokenMetadata memory _refTokenMetadata, address _refToken)
  {
    // If the RefToken is already deployed, and the native token is passed as token, return the RefToken metadata and address
    _refToken = nativeToRefToken[_token];
    if (_refToken != address(0)) {
      return (refTokenMetadata[_refToken], _refToken);
    }

    // If the RefToken is already deployed, and the ref token is passed as token, return the RefToken metadata and address
    _refTokenMetadata = refTokenMetadata[_token];
    if (_refTokenMetadata.nativeAssetChainId != 0) {
      return (_refTokenMetadata, _token);

      // If the RefToken is not deployed, create a new RefToken
    } else {
      // `token` is the native asset address here because if the input is a RefToken, the RefToken is already deployed
      _refTokenMetadata = RefTokenMetadata({
        nativeAssetAddress: _token,
        nativeAssetChainId: block.chainid,
        nativeAssetName: IERC20Metadata(_token).name(),
        nativeAssetSymbol: IERC20Metadata(_token).symbol(),
        nativeAssetDecimals: IERC20Metadata(_token).decimals()
      });

      // Deploy the RefToken and store the RefToken address and metadata
      _refToken = _deployRefToken(_token, _refTokenMetadata);
      refTokenMetadata[_refToken] = _refTokenMetadata;
      nativeToRefToken[_token] = _refToken;
    }
  }

  /**
   * @notice Internal function to set the RefToken metadata and deploy the RefToken if it is not deployed
   * @param _nativeAsset The native asset address
   * @param _refTokenMetadata The metadata to set
   * @return _refToken The deployed RefToken address
   */
  function _setRefTokenMetadata(
    address _nativeAsset,
    RefTokenMetadata calldata _refTokenMetadata
  ) internal returns (address _refToken) {
    _refToken = _deployRefToken(_nativeAsset, _refTokenMetadata);

    nativeToRefToken[_nativeAsset] = _refToken;

    // If relay a native token and the RefToken is not deployed, create a new RefToken
    refTokenMetadata[_refToken] = _refTokenMetadata;
  }

  /**
   * @notice Internal function to send a message
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _refToken The RefToken address
   * @param _executionChainId The execution chain ID
   * @param _message The message to be sent
   */
  function _sendMessage(
    RefTokenBridgeData calldata _refTokenBridgeData,
    address _refToken,
    uint256 _executionChainId,
    bytes memory _message
  ) internal {
    // If the token is a RefToken, burn the token, otherwise lock the token
    if (block.chainid == IRefToken(_refToken).NATIVE_ASSET_CHAIN_ID()) {
      _lock(_refTokenBridgeData.token, _refTokenBridgeData.amount);
    } else {
      _burn(_refTokenBridgeData.token, msg.sender, _refTokenBridgeData.amount);
    }

    L2_TO_L2_CROSS_DOMAIN_MESSENGER.sendMessage(_executionChainId, address(this), _message);

    emit MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _executionChainId
    );
  }

  /**
   * @notice Deploys the RefToken
   * @param _nativeAsset The address of the native asset
   * @param _refTokenMetadata The metadata of the RefToken
   * @return _refToken The address of the RefToken
   */
  function _deployRefToken(
    address _nativeAsset,
    IRefTokenBridge.RefTokenMetadata memory _refTokenMetadata
  ) internal returns (address _refToken) {
    bytes32 _salt = keccak256(abi.encode(_refTokenMetadata.nativeAssetChainId, _nativeAsset));
    _refToken = address(
      new RefToken{salt: _salt}(
        address(this),
        _refTokenMetadata.nativeAssetChainId,
        _refTokenMetadata.nativeAssetName,
        _refTokenMetadata.nativeAssetSymbol,
        _refTokenMetadata.nativeAssetDecimals
      )
    );

    emit RefTokenDeployed(_refToken, _nativeAsset);
  }

  /**
   * @notice Internal function to check the data for the send function
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _destinationChainId The destination chain ID
   */
  function _sendDataCheck(RefTokenBridgeData calldata _refTokenBridgeData, uint256 _destinationChainId) internal view {
    if (_refTokenBridgeData.amount == 0) revert RefTokenBridge_InvalidAmount();
    if (_refTokenBridgeData.recipient == address(0)) revert RefTokenBridge_InvalidRecipient();
    if (_destinationChainId == 0 || _destinationChainId == block.chainid) {
      revert RefTokenBridge_InvalidDestinationChainId();
    }
  }
}
