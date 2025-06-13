// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRefToken} from 'interfaces/IRefToken.sol';
import {IL2ToL2CrossDomainMessenger, IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';

import {IERC20Metadata} from 'interfaces/external/IERC20Metadata.sol';
import {IExecutor} from 'interfaces/external/IExecutor.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {RefToken} from 'contracts/RefToken.sol';

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
   * @notice The RefToken metadata
   */
  mapping(address _refToken => RefTokenMetadata _refTokenMetadata) public refTokenMetadata;

  /**
   * @notice The RefToken address
   */
  mapping(address _nativeToken => address _refToken) public nativeToRefToken;

  /**
   * @notice Send token to the relay chain
   * @dev The native asset MUST implement the IERC20Metadata interface for this function to work
   * @param _relayChainId The chain where the tokens will be relayed to
   * @param _token The input token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the relay chain
   */
  function send(uint256 _relayChainId, address _token, uint256 _amount, address _recipient) external {
    ExecutionData memory _emptyExecutionData;
    _send(_relayChainId, _token, _amount, _recipient, _emptyExecutionData);
  }

  /**
   * @notice Send token to the destination chain and execute in the destination chain executor
   * @dev The native asset MUST implement the IERC20Metadata interface for this function to work
   * @param _relayChainId The chain where the tokens will be relayed
   * @param _token The input token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _executionData The data to be executed on the destination chain
   */
  function sendAndExecute(
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
    // TODO: Check refund address is not zero? Not sure

    _send(_relayChainId, _token, _amount, _recipient, _executionData);
  }

  /**
   * @notice Relay token from the destination chain
   * @param _refToken The RefToken address
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the chain where it is relayed
   * @param _refTokenMetadata The metadata of the RefToken
   */
  function relay(
    address _refToken,
    uint256 _amount,
    address _recipient,
    RefTokenMetadata calldata _refTokenMetadata
  ) external {
    _relay(_refToken, _recipient, _refTokenMetadata, _amount, _recipient);
    emit MessageRelayed(_refToken, _amount, _recipient, address(0));
  }

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _refToken The token to be relayed
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _executionData The data to be executed on the destination chain
   */
  function relayAndExecute(
    address _refToken,
    uint256 _amount,
    address _recipient,
    RefTokenMetadata calldata _refTokenMetadata,
    ExecutionData calldata _executionData
  ) external {
    _relay(_refToken, address(this), _refTokenMetadata, _amount, _recipient);

    // Approve the destination executor to spend the RefToken amount
    IERC20(_refToken).approve(_executionData.destinationExecutor, _amount);

    // Execute the data on the destination chain executor
    try IExecutor(_executionData.destinationExecutor).execute(
      _refToken, _recipient, _amount, _executionData.destinationChainId, _executionData.data
    ) {
      emit MessageRelayed(_refToken, _amount, _recipient, _executionData.destinationExecutor);
    } catch {
      // If it failed and this is not the native asset chain, burn the token (otherwise there is no supply)
      if (block.chainid != _refTokenMetadata.nativeAssetChainId) _burn(_refToken, address(this), _amount);

      // Send the tokens back to the refund address on the origin chain
      uint256 _relayChainId = L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSource();
      _sendMessage(_relayChainId, _refToken, _amount, _recipient, _refTokenMetadata, _executionData);
    }

    // Revoke the approval for the destination executor after execution
    IERC20(_refToken).approve(_executionData.destinationExecutor, 0);
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
   * @notice Gets the RefToken and its metadata
   * @param _token Either the native asset or the RefToken
   * @return _refToken The address of the RefToken, zero address if the RefToken is not deployed
   * @return _refTokenMetadata The metadata of the RefToken, empty if the RefToken is not deployed
   */
  function getRefToken(address _token)
    public
    view
    returns (address _refToken, RefTokenMetadata memory _refTokenMetadata)
  {
    _refToken = nativeToRefToken[_token];

    // If the input token is the native asset, use the queried RefToken to get the metadata
    if (_refToken != address(0)) _refTokenMetadata = refTokenMetadata[_refToken];
    // If the input token is the RefToken, use it to get the metadata
    else _refTokenMetadata = refTokenMetadata[_token];
  }

  /**
   * @notice Internal function to send a message
   * @param _relayChainId The relay chain ID
   * @param _token The token to be sent, either the native asset or the RefToken
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _executionData The data to be executed on the destination chain
   */
  function _send(
    uint256 _relayChainId,
    address _token,
    uint256 _amount,
    address _recipient,
    ExecutionData memory _executionData
  ) internal {
    if (_amount == 0) revert RefTokenBridge_InvalidAmount();
    if (_recipient == address(0)) revert RefTokenBridge_InvalidRecipient();
    if (_relayChainId == 0 || _relayChainId == block.chainid) {
      revert RefTokenBridge_InvalidDestinationChainId();
    }

    (address _refToken, RefTokenMetadata memory _refTokenMetadata) = getRefToken(_token);
    if (_refToken == address(0)) {
      // If the RefToken is not deployed, deploy it while storing and retrieving its address and metadata
      (_refToken, _refTokenMetadata) = _deployRefToken(_token, block.chainid);
    }

    // If the chain is the native asset chain, but the `_token` is not the native asset, revert since there will not be
    // RefToken supply to burn on this chain
    bool _isNativeAssetChain = block.chainid == IRefToken(_refToken).NATIVE_ASSET_CHAIN_ID();
    if (_isNativeAssetChain && _token != _refTokenMetadata.nativeAsset) revert RefTokenBridge_NotNativeAsset();

    // If the chain is the native asset chain, lock the native asset
    if (_isNativeAssetChain) _lock(_refTokenMetadata.nativeAsset, _amount);
    // Otherwise, burn the RefToken
    else _burn(_refToken, msg.sender, _amount);

    _sendMessage(_relayChainId, _token, _amount, _recipient, _refTokenMetadata, _executionData);
  }

  /**
   * @notice Deploys the RefToken
   * @param _refTokenMetadata The metadata of the RefToken
   * @return _refToken The address of the RefToken
   */
  function _deployRefToken(
    address _nativeAsset,
    uint256 _nativeAssetChainId
  ) internal returns (address _refToken, RefTokenMetadata memory _refTokenMetadata) {
    // Get the RefToken metadata
    _refTokenMetadata = RefTokenMetadata({
      nativeAsset: _nativeAsset,
      nativeAssetChainId: _nativeAssetChainId,
      nativeAssetName: IERC20Metadata(_nativeAsset).name(),
      nativeAssetSymbol: IERC20Metadata(_nativeAsset).symbol(),
      nativeAssetDecimals: IERC20Metadata(_nativeAsset).decimals()
    });

    // Deploy the RefToken deterministically
    bytes32 _salt = keccak256(abi.encode(_nativeAssetChainId, _nativeAsset));
    _refToken = address(
      new RefToken{salt: _salt}(
        address(this),
        _refTokenMetadata.nativeAssetChainId,
        _refTokenMetadata.nativeAssetName,
        _refTokenMetadata.nativeAssetSymbol,
        _refTokenMetadata.nativeAssetDecimals
      )
    );

    // Store the RefToken address and metadata
    nativeToRefToken[_refTokenMetadata.nativeAsset] = _refToken;
    refTokenMetadata[_refToken] = _refTokenMetadata;

    emit RefTokenDeployed(_refToken, _refTokenMetadata.nativeAsset);
  }

  /**
   * @notice Sends the message to the destination chain
   * @param _relayChainId The relay chain ID
   * @param _refToken The RefToken address
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _executionData The data to be executed on the destination chain
   */
  function _sendMessage(
    uint256 _relayChainId,
    address _refToken,
    uint256 _amount,
    address _recipient,
    RefTokenMetadata memory _refTokenMetadata,
    ExecutionData memory _executionData
  ) internal {
    bytes memory _message;
    if (_executionData.destinationExecutor == address(0)) {
      // If there is no execution, we just `relay()` the RefToken
      _message = abi.encodeCall(IRefTokenBridge.relay, (_refToken, _amount, _recipient, _refTokenMetadata));
    } else {
      // If there is execution, we `relayAndExecute()` the RefToken
      _message = abi.encodeCall(
        IRefTokenBridge.relayAndExecute, (_refToken, _amount, _recipient, _refTokenMetadata, _executionData)
      );
    }

    // Send the message
    L2_TO_L2_CROSS_DOMAIN_MESSENGER.sendMessage(_relayChainId, address(this), _message);
    emit MessageSent(_refToken, _amount, _recipient, _executionData.destinationExecutor, _relayChainId);
  }

  /**
   * @notice Relays the RefTokenBridge message, either unlocking the native asset or minting the RefToken
   * @param _refToken The RefToken address
   * @param _mintTo The address to mint the token to
   * @param _refTokenMetadata The metadata of the RefToken
   * @param _amount The amount of token to be relayed
   * @param _recipient The recipient of the token
   */
  function _relay(
    address _refToken,
    address _mintTo,
    RefTokenMetadata calldata _refTokenMetadata,
    uint256 _amount,
    address _recipient
  ) internal {
    if (
      msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        || L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSender() != address(this)
    ) {
      revert RefTokenBridge_Unauthorized();
    }

    if (block.chainid == _refTokenMetadata.nativeAssetChainId) {
      // If we are on the native asset chain, we can just unlock the token. If this point is reached, the RefToken is
      // already deployed and its metadata is already set.
      unlock(_refTokenMetadata.nativeAsset, _recipient, _amount);
    } else {
      // If the RefToken is not deployed, deploy it.
      // TODO: For gas efficiency, should we check code.length equals zero instead?
      if (refTokenMetadata[_refToken].nativeAssetChainId == 0) {
        (_refToken,) = _deployRefToken(_refTokenMetadata.nativeAsset, _refTokenMetadata.nativeAssetChainId);
      }

      // Mint the RefToken to the recipient
      _mint(_refToken, _mintTo, _amount);
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
   * @notice Internal function to lock the token
   * @dev This function is used to lock the token on the source chain
   * @param _token The token to be locked
   * @param _amount The amount of token to be locked
   */
  function _lock(address _token, uint256 _amount) internal {
    IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    emit TokensLocked(_token, _amount);
  }
}
