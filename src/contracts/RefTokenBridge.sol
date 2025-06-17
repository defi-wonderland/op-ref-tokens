// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRefToken} from 'interfaces/IRefToken.sol';
import {IL2ToL2CrossDomainMessenger, IRefTokenBridge} from 'interfaces/IRefTokenBridge.sol';

import {IERC20Metadata} from 'interfaces/external/IERC20Metadata.sol';
import {IExecutor} from 'interfaces/external/IExecutor.sol';

import {PredeployAddresses} from '@interop-lib/src/libraries/PredeployAddresses.sol';
import {IERC20Solady as IERC20} from '@interop-lib/vendor/solady-v0.0.245/interfaces/IERC20.sol';
import {RefToken} from 'contracts/RefToken.sol';
import {IRefToken} from 'interfaces/IRefToken.sol';

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
    // TODO: Check refund address is not zero? Not sure

    _send(_nativeAssetChainId, _relayChainId, _token, _amount, _recipient, _executionData);
  }

  /**
   * @notice Relay token from the destination chain
   * @param _refToken The RefToken address
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the chain where it is relayed
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   */
  function relay(
    address _refToken,
    uint256 _amount,
    address _recipient,
    address _nativeAsset,
    uint256 _nativeAssetChainId
  ) external {
    _relay(_refToken, _recipient, _nativeAsset, _nativeAssetChainId, _amount, _recipient);
    emit MessageRelayed(_refToken, _amount, _recipient, address(0));
  }

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _refToken The token to be relayed
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient that will receive the token on the destination chain
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   * @param _executionData The data to be executed on the destination chain
   */
  function relayAndExecute(
    address _refToken,
    uint256 _amount,
    address _recipient,
    address _nativeAsset,
    uint256 _nativeAssetChainId,
    ExecutionData calldata _executionData
  ) external {
    _relay(_refToken, address(this), _nativeAsset, _nativeAssetChainId, _amount, _recipient);

    // Approve the destination executor to spend the RefToken amount
    IERC20(_refToken).approve(_executionData.destinationExecutor, _amount);

    // Execute the data on the destination chain executor
    try IExecutor(_executionData.destinationExecutor).execute(
      _refToken, _recipient, _amount, _executionData.destinationChainId, _executionData.data
    ) {
      emit MessageRelayed(_refToken, _amount, _recipient, _executionData.destinationExecutor);
    } catch {
      // If it failed and this is not the native asset chain, burn the token (otherwise there is no supply)
      if (block.chainid != _nativeAssetChainId) _burn(_refToken, address(this), _amount);

      // Send the tokens back to the refund address on the origin chain
      uint256 _relayChainId = L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSource();
      _sendMessage(_relayChainId, _refToken, _amount, _recipient, _nativeAsset, _nativeAssetChainId, _executionData);
    }

    // Revoke the approval for the destination executor after execution
    IERC20(_refToken).approve(_executionData.destinationExecutor, 0);
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
    emit TokensUnlocked(_nativeAsset, _to, _amount);
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
    if (_relayChainId == 0 || _relayChainId == block.chainid) revert RefTokenBridge_InvalidDestinationChainId();
    // TODO: relaychain id != nativeAssetChainId check needed here?

    address _refToken = getRefToken(_token, _nativeAssetChainId);
    // If the RefToken is not deployed, deploy it
    if (_refToken == address(0)) {
      if (_nativeAssetChainId != block.chainid) revert RefTokenBridge_InvalidNativeAssetChainId();
      _refToken = _deployRefToken(_token, block.chainid);
    }

    // If the chain is the native asset chain, but the `_token` is not the native asset, revert since there will not be
    // RefToken supply to burn on this chain
    address _nativeAsset = IRefToken(_refToken).metadata().nativeAsset;
    bool _isNativeAssetChain = block.chainid == _nativeAssetChainId;
    // TODO: Can be moved above for gas efficiency
    // if (_isNativeAssetChain && _token != _refTokenMetadata.nativeAsset) revert RefTokenBridge_NotNativeAsset();
    // if (!_isNativeAssetChain && _token != _refToken) revert RefTokenBridge_NotRefToken();

    // If the chain is the native asset chain, lock the native asset
    if (_isNativeAssetChain) _lock(_nativeAsset, _amount);
    // Otherwise, burn the RefToken
    else _burn(_refToken, msg.sender, _amount);

    _sendMessage(_relayChainId, _refToken, _amount, _recipient, _nativeAsset, _nativeAssetChainId, _executionData);
  }

  /**
   * @notice Deploys the RefToken
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   * @return _refToken The address of the RefToken
   */
  function _deployRefToken(address _nativeAsset, uint256 _nativeAssetChainId) internal returns (address _refToken) {
    // Deploy the RefToken deterministically
    bytes32 _salt = keccak256(abi.encode(_nativeAssetChainId, _nativeAsset));
    _refToken = address(
      new RefToken{salt: _salt}(
        address(this),
        IRefToken.RefTokenMetadata({
          nativeAsset: _nativeAsset,
          nativeAssetChainId: _nativeAssetChainId,
          nativeAssetName: IERC20Metadata(_nativeAsset).name(),
          nativeAssetSymbol: IERC20Metadata(_nativeAsset).symbol(),
          nativeAssetDecimals: IERC20Metadata(_nativeAsset).decimals()
        })
      )
    );

    // Store the RefToken address and metadata
    nativeToRefToken[_nativeAsset][_nativeAssetChainId] = _refToken;
    isRefTokenDeployed[_refToken] = true;

    emit RefTokenDeployed(_refToken, _nativeAsset, _nativeAssetChainId);
  }

  /**
   * @notice Sends the message to the destination chain
   * @param _relayChainId The relay chain ID
   * @param _refToken The RefToken address
   * @param _amount The amount of token to be sent
   * @param _recipient The recipient of the token
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   * @param _executionData The data to be executed on the destination chain
   */
  function _sendMessage(
    uint256 _relayChainId,
    address _refToken,
    uint256 _amount,
    address _recipient,
    address _nativeAsset,
    uint256 _nativeAssetChainId,
    ExecutionData memory _executionData
  ) internal {
    bytes memory _message;
    if (_executionData.destinationExecutor == address(0)) {
      // If there is no execution, we just `relay()` the RefToken
      _message =
        abi.encodeCall(IRefTokenBridge.relay, (_refToken, _amount, _recipient, _nativeAsset, _nativeAssetChainId));
    } else {
      // If there is execution, we `relayAndExecute()` the RefToken
      _message = abi.encodeCall(
        IRefTokenBridge.relayAndExecute,
        (_refToken, _amount, _recipient, _nativeAsset, _nativeAssetChainId, _executionData)
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
   * @param _nativeAsset The native asset to be relayed
   * @param _nativeAssetChainId The chain ID of the native asset
   * @param _amount The amount of token to be relayed
   * @param _recipient The recipient of the token
   */
  function _relay(
    address _refToken,
    address _mintTo,
    address _nativeAsset,
    uint256 _nativeAssetChainId,
    uint256 _amount,
    address _recipient
  ) internal {
    if (
      msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
        || L2_TO_L2_CROSS_DOMAIN_MESSENGER.crossDomainMessageSender() != address(this)
    ) {
      revert RefTokenBridge_Unauthorized();
    }

    if (block.chainid == _nativeAssetChainId) {
      // If we are on the native asset chain, we can just unlock the token. If this point is reached, the RefToken is
      // already deployed and its metadata is already set.
      unlock(_nativeAsset, _recipient, _amount);
    } else {
      // If the RefToken is not deployed, deploy it.
      if (nativeToRefToken[_nativeAsset][_nativeAssetChainId] == address(0)) {
        _refToken = _deployRefToken(_nativeAsset, _nativeAssetChainId);
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
   * @notice Internal function to lock the native asset
   * @dev This function is used to lock the token on the source chain
   * @param _nativeAsset The native asset to be locked
   * @param _amount The amount of token to be locked
   */
  function _lock(address _nativeAsset, uint256 _amount) internal {
    IERC20(_nativeAsset).transferFrom(msg.sender, address(this), _amount);
    emit TokensLocked(_nativeAsset, msg.sender, _amount);
  }
}
