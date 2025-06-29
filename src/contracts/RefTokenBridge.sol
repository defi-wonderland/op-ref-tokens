// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {RefToken} from 'contracts/RefToken.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';
import {IL2ToL2CrossDomainMessenger, IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';
import {IERC20Metadata} from 'interfaces/external/IERC20Metadata.sol';
import {IExecutor} from 'interfaces/external/IExecutor.sol';

/**
 * @title RefTokenBridge
 * @notice A bridge for bridging locked native assets and ERC-20s across OP-Stack chains.
 */
contract RefTokenBridge is IRefTokenBridge {
  /**
   * @notice The L2 to L2 cross domain messenger address
   */
  IL2ToL2CrossDomainMessenger public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER =
    IL2ToL2CrossDomainMessenger(PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

  /**
   * @notice Whether the RefToken is deployed
   */
  mapping(address _refToken => bool _isDeployed) public isRefTokenDeployed;

  /**
   * @notice The RefToken metadata by a given pair of native token and RefToken
   */
  mapping(address _nativeToken => mapping(uint256 _nativeAssetChainId => address _refToken)) public nativeToRefToken;

  /**
   * @notice Send token to the relay chain
   * @dev The native asset MUST implement the IERC20Metadata interface for this function to work
   * @param _nativeAssetChainId The chain where the native asset is locked
   * @param _relayChainId The chain where the tokens will be relayed to
   * @param _token The input token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the relay chain
   */
  function send(
    uint256 _nativeAssetChainId,
    uint256 _relayChainId,
    address _token,
    uint256 _amount,
    address _recipient
  ) external {
    ExecutionData memory _emptyExecutionData;
    _send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _emptyExecutionData);
  }

  /**
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @dev The native asset MUST implement the IERC20Metadata interface for this function to work
   * @param _nativeAssetChainId The chain where the native asset is locked
   * @param _relayChainId The chain where the tokens will be relayed
   * @param _token The input token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _executionData The data to be executed on the destination chain
   */
  function sendAndExecute(
    uint256 _nativeAssetChainId,
    uint256 _relayChainId,
    address _token,
    uint256 _amount,
    address _recipient,
    ExecutionData calldata _executionData
  ) external {
    if (_executionData.destinationExecutor == address(0)) revert RefTokenBridge_InvalidDestinationExecutor();
    if (_executionData.destinationChainId == 0 || _executionData.destinationChainId == block.chainid) {
      revert RefTokenBridge_InvalidExecutionChainId();
    }
    if (_executionData.refundAddress == address(0)) revert RefTokenBridge_InvalidRefundAddress();

    _send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  /**
   * @notice Relay token from the destination chain
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the chain where it is relayed
   * @param _refTokenMetadata The metadata of the RefToken
   */
  function relay(uint256 _amount, address _recipient, IRefToken.RefTokenMetadata memory _refTokenMetadata) external {
    (address _token, bool _unlock) = _relay(_recipient, _amount, _refTokenMetadata);
    if (_unlock) unlock(_refTokenMetadata.nativeAsset, _recipient, _amount);
    emit MessageRelayed(_token, _amount, _recipient, address(0));
  }

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _executionData The data to be executed on the destination chain
   */
  function relayAndExecute(
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata calldata _refTokenMetadata,
    ExecutionData calldata _executionData
  ) external {
    (address _token,) = _relay(address(this), _amount, _refTokenMetadata);

    // Approve the destination executor to spend the RefToken amount
    IERC20(_token).approve(_executionData.destinationExecutor, _amount);

    // Execute the data on the destination chain executor
    try IExecutor(_executionData.destinationExecutor).execute(
      _token, _recipient, _amount, _executionData.destinationChainId, _executionData.data
    ) {
      emit MessageRelayed(_token, _amount, _recipient, _executionData.destinationExecutor);
    } catch {
      // If it failed and this is not the native asset chain, burn the token (otherwise there is no supply)
      if (block.chainid != _refTokenMetadata.nativeAssetChainId) _burn(_token, address(this), _amount);

      // Send the tokens back to the refund address on the origin chain, without executing anything, just relaying
      uint256 _relayChainId = L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSource();
      ExecutionData memory _emptyExecutionData;
      _sendMessage(_token, _relayChainId, _amount, _executionData.refundAddress, _refTokenMetadata, _emptyExecutionData);
    }

    // Revoke the approval for the destination executor after execution
    IERC20(_token).approve(_executionData.destinationExecutor, 0);
  }

  /**
   * @notice Internal function to unlock the token
   * @dev This function is used to unlock the token on the source chain
   * @param _nativeAsset The native asset to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _nativeAsset, address _to, uint256 _amount) public {
    address _refToken = nativeToRefToken[_nativeAsset][block.chainid];
    if (msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER) && msg.sender != _refToken) {
      revert RefTokenBridge_Unauthorized();
    }

    IERC20(_nativeAsset).transfer(_to, _amount);
    emit NativeAssetUnlocked(_nativeAsset, _to, _amount);
  }

  /**
   * @notice Gets the RefToken
   * @param _token Either the native asset or the RefToken
   * @param _nativeAssetChainId The chain ID of the native asset
   * @return _refToken The address of the RefToken, zero address if the RefToken is not deployed
   */
  function getRefToken(address _token, uint256 _nativeAssetChainId) public view returns (address _refToken) {
    // If the input token is the RefToken, return the RefToken
    if (isRefTokenDeployed[_token]) _refToken = _token;
    // If the input token is the native asset, return the RefToken
    else _refToken = nativeToRefToken[_token][_nativeAssetChainId];
  }

  /**
   * @notice Internal function to send a message
   * @param _nativeAssetChainId The chain where the native asset is locked
   * @param _relayChainId The relay chain ID
   * @param _token The token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _executionData The data to be executed on the destination chain
   */
  function _send(
    uint256 _nativeAssetChainId,
    uint256 _relayChainId,
    address _token,
    uint256 _amount,
    address _recipient,
    ExecutionData memory _executionData
  ) internal {
    if (_amount == 0) revert RefTokenBridge_InvalidAmount();
    if (_recipient == address(0)) revert RefTokenBridge_InvalidRecipient();
    if (_relayChainId == 0 || _relayChainId == block.chainid) revert RefTokenBridge_InvalidRelayChainId();

    IRefToken.RefTokenMetadata memory _refTokenMetadata;
    address _refToken = getRefToken(_token, _nativeAssetChainId);
    // If the RefToken is not deployed, deploy it
    if (_refToken == address(0)) {
      // If deploying, the native asset chain id must match the block chain id
      if (_nativeAssetChainId != block.chainid) revert RefTokenBridge_InvalidNativeAssetChainId();

      _refTokenMetadata = IRefToken.RefTokenMetadata({
        nativeAsset: _token,
        nativeAssetChainId: _nativeAssetChainId,
        nativeAssetName: IERC20Metadata(_token).name(),
        nativeAssetSymbol: IERC20Metadata(_token).symbol(),
        nativeAssetDecimals: IERC20Metadata(_token).decimals()
      });
      _refToken = _deployRefToken(_refTokenMetadata);
    } else {
      _refTokenMetadata = IRefToken(_refToken).metadata();
    }

    // RefToken supply to burn on this chain
    bool _isNativeAssetChain = block.chainid == _nativeAssetChainId;
    if (_isNativeAssetChain && _token != _refTokenMetadata.nativeAsset) revert RefTokenBridge_NotNativeAsset();
    if (!_isNativeAssetChain && _token != _refToken) revert RefTokenBridge_NotRefToken();

    // If the chain is the native asset chain, lock the native asset
    if (_isNativeAssetChain) _lock(_refTokenMetadata.nativeAsset, _amount);
    // Otherwise, burn the RefToken
    else _burn(_refToken, msg.sender, _amount);

    _sendMessage(_token, _relayChainId, _amount, _recipient, _refTokenMetadata, _executionData);
  }

  /**
   * @notice Deploys the RefToken
   * @param _refTokenMetadata The metadata of the RefToken
   * @return _refToken The address of the RefToken
   */
  function _deployRefToken(IRefToken.RefTokenMetadata memory _refTokenMetadata) internal returns (address _refToken) {
    // Deploy the RefToken deterministically
    bytes32 _salt = keccak256(abi.encode(_refTokenMetadata.nativeAssetChainId, _refTokenMetadata.nativeAsset));
    _refToken = address(
      new RefToken{salt: _salt}(
        address(this),
        IRefToken.RefTokenMetadata({
          nativeAsset: _refTokenMetadata.nativeAsset,
          nativeAssetChainId: _refTokenMetadata.nativeAssetChainId,
          nativeAssetName: _refTokenMetadata.nativeAssetName,
          nativeAssetSymbol: _refTokenMetadata.nativeAssetSymbol,
          nativeAssetDecimals: _refTokenMetadata.nativeAssetDecimals
        })
      )
    );

    // Store the RefToken address and metadata
    nativeToRefToken[_refTokenMetadata.nativeAsset][_refTokenMetadata.nativeAssetChainId] = _refToken;
    isRefTokenDeployed[_refToken] = true;

    emit RefTokenDeployed(_refToken, _refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId);
  }

  /**
   * @notice Sends the message to the destination chain
   * @param _token The token to be sent, either the native asset or the RefToken
   * @param _relayChainId The relay chain ID
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _executionData The data to be executed on the destination chain
   */
  function _sendMessage(
    address _token,
    uint256 _relayChainId,
    uint256 _amount,
    address _recipient,
    IRefToken.RefTokenMetadata memory _refTokenMetadata,
    ExecutionData memory _executionData
  ) internal {
    bytes memory _message;
    if (_executionData.destinationExecutor == address(0)) {
      // If there is no execution, we just `relay()` the RefToken
      _message = abi.encodeCall(IRefTokenBridge.relay, (_amount, _recipient, _refTokenMetadata));
    } else {
      // If there is execution, we `relayAndExecute()` the RefToken
      _message =
        abi.encodeCall(IRefTokenBridge.relayAndExecute, (_amount, _recipient, _refTokenMetadata, _executionData));
    }

    // Send the message
    L2_TO_L2_CROSS_DOMAIN_MESSENGER.sendMessage(_relayChainId, address(this), _message);
    emit MessageSent(_token, _amount, _recipient, _executionData.destinationExecutor, _relayChainId);
  }

  /**
   * @notice Relays the RefTokenBridge message, either unlocking the native asset or minting the RefToken
   * @param _mintTo The address to mint the token to
   * @param _amount The amount of token to be relayed
   * @param _refTokenMetadata The metadata of the RefToken
   * @return _token The token to be relayed, either the native asset or the RefToken
   * @return _unlock Whether the subsequent flow is unlocking the native asset or not
   */
  function _relay(
    address _mintTo,
    uint256 _amount,
    IRefToken.RefTokenMetadata memory _refTokenMetadata
  ) internal returns (address _token, bool _unlock) {
    if (
      msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        || L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSender() != address(this)
    ) {
      revert RefTokenBridge_Unauthorized();
    }

    // If the chain is the native asset chain, the token to interact with is the native asset
    if (block.chainid == _refTokenMetadata.nativeAssetChainId) {
      _token = _refTokenMetadata.nativeAsset;
      // If on the `relay()` function, the subsequent flow is unlocking the native asset
      _unlock = true;
    } else {
      // Otherwise, the token to interact with is the RefToken, and we need to mint it
      _token = getRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId);
      // If the RefToken is not deployed, deploy it.
      if (_token == address(0)) _token = _deployRefToken(_refTokenMetadata);

      // Mint the RefToken to the recipient
      _mint(_token, _mintTo, _amount);
    }
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
    emit RefTokenMinted(_token, _to, _amount);
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
    emit RefTokenBurned(_token, _to, _amount);
  }

  /**
   * @notice Internal function to lock the native asset
   * @dev This function is used to lock the token on the source chain
   * @param _nativeAsset The native asset to be locked
   * @param _amount The amount of token to be locked
   */
  function _lock(address _nativeAsset, uint256 _amount) internal {
    IERC20(_nativeAsset).transferFrom(msg.sender, address(this), _amount);
    emit NativeAssetLocked(_nativeAsset, msg.sender, _amount);
  }
}
