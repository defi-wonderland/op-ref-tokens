// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRefToken} from '../interfaces/IRefToken.sol';
import {IL2ToL2CrossDomainMessenger, IRefTokenBridge} from '../interfaces/IRefTokenBridge.sol';
import {RefToken} from './RefToken.sol';

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
  mapping(address _nativeToken => address _refToken) public refTokenAddress;

  /**
   * @notice Constructs the RefTokenBridge contract
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
   * @param _destinationChainId The destination chain ID
   * @param _data The data to be executed on the destination chain
   */
  function sendAndExecute(
    RefTokenBridgeData calldata _refTokenBridgeData,
    uint256 _destinationChainId,
    bytes memory _data
  ) external {
    _sendDataCheck(_refTokenBridgeData, _destinationChainId);
    if (_refTokenBridgeData.destinationExecutor == address(0)) {
      revert RefTokenBridge_InvalidData();
    }

    (RefTokenMetadata memory _refTokenMetadata, address _refToken) = _getRefTokenMetadata(_refTokenBridgeData.token);

    bytes memory _message =
      abi.encodeWithSelector(IRefTokenBridge.relayAndExecute.selector, _refTokenBridgeData, _refTokenMetadata, _data);

    _sendMessage(_refTokenBridgeData, _refToken, _destinationChainId, _message);
  }

  /**
   * @notice Relay token from the destination chain
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   */
  function relay(RefTokenBridgeData calldata _refTokenBridgeData) external {
    if (tx.origin != address(this) && msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)) {
      revert RefTokenBridge_InvalidMessage();
    }
  }

  /**
   * @notice Relay token from the destination chain and execute in the destination chain executor
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _data The data to be executed on the destination chain
   */
  function relayAndExecute(RefTokenBridgeData calldata _refTokenBridgeData, bytes memory _data) external {
    if (tx.origin != address(this) && msg.sender != address(L2_TO_L2_CROSS_DOMAIN_MESSENGER)) {
      revert RefTokenBridge_InvalidMessage();
    }
  }

  /**
   * @notice Locks the native asset token on the origin chain
   * @param _token The token to be locked
   * @param _amount The amount of token to be locked
   */
  function _lock(address _token, uint256 _amount) internal {
    IRefToken(_token).transferFrom(msg.sender, address(this), _amount);

    emit TokensLocked(_token, _amount);
  }

  /**
   * @notice Unlocks the token
   * @dev This function is used to unlock the token on the source chain
   * @param _token The token to be unlocked
   * @param _to The address to unlock the token to
   * @param _amount The amount of token to be unlocked
   */
  function unlock(address _token, address _to, uint256 _amount) public {
    if (msg.sender != address(this) && msg.sender != _token) {
      revert RefTokenBridge_InvalidSender();
    }

    IRefToken(_token).transfer(_to, _amount);

    emit TokensUnlocked(_token, _to, _amount);
  }

  /**
   * @notice Mints the RefToken
   * @dev This function is used to mint the RefToken on the destination chain
   * @param _token The token to be minted
   * @param _amount The amount of token to be minted
   */
  function _mint(address _token, uint256 _amount) internal {}

  /**
   * @notice Burns the RefToken
   * @dev This function is used to burn the RefToken on the destination chain
   * @param _token The token to be burned
   * @param _amount The amount of token to be burned
   */
  function _burn(address _token, uint256 _amount) internal {
    IRefToken(_token).burn(msg.sender, _amount);

    emit TokensBurned(_token, _amount);
  }

  /**
   * @notice Gets the RefToken metadata and address
   * @param _token The token to get the metadata and address from
   * @return _refTokenMetadata The RefToken metadata
   * @return _refToken The RefToken address
   */
  function _getRefTokenMetadata(address _token)
    internal
    returns (RefTokenMetadata memory _refTokenMetadata, address _refToken)
  {
    // If the RefToken is already deployed, and the native token is passed as token, return the RefToken metadata and address
    _refToken = refTokenAddress[_token];
    if (_refToken != address(0)) {
      return (refTokenMetadata[_refToken], _refToken);
    }

    // If the RefToken is already deployed, and the ref token is passed as token, return the RefToken metadata and address
    _refTokenMetadata = refTokenMetadata[_token];
    if (_refTokenMetadata.nativeAssetChainId != 0) {
      return (_refTokenMetadata, _token);

      // If the RefToken is not deployed, create a new RefToken
    } else {
      _refTokenMetadata = RefTokenMetadata({
        nativeAssetChainId: block.chainid,
        nativeAssetName: IRefToken(_token).name(),
        nativeAssetSymbol: IRefToken(_token).symbol(),
        nativeAssetDecimals: IRefToken(_token).decimals()
      });

      // Deploy the RefToken
      _refToken = _deployRefToken(_token, _refTokenMetadata);

      // Store the RefToken metadata and address
      refTokenMetadata[_refToken] = _refTokenMetadata;
      refTokenAddress[_token] = _refToken;
    }
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
   * @notice Checks the data for the send function
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _destinationChainId The destination chain ID
   */
  function _sendDataCheck(RefTokenBridgeData calldata _refTokenBridgeData, uint256 _destinationChainId) internal pure {
    if (
      _refTokenBridgeData.token == address(0) || _refTokenBridgeData.amount == 0
        || _refTokenBridgeData.recipient == address(0) || _destinationChainId == 0
    ) {
      revert RefTokenBridge_InvalidData();
    }
  }

  /**
   * @notice Sends a cross-chain message to the destination chain through the L2 to L2 cross domain messenger
   * @param _refTokenBridgeData The data structure for the RefTokenBridge
   * @param _refToken The RefToken address
   * @param _destinationChainId The destination chain ID
   * @param _message The message to be sent
   */
  function _sendMessage(
    RefTokenBridgeData calldata _refTokenBridgeData,
    address _refToken,
    uint256 _destinationChainId,
    bytes memory _message
  ) internal {
    // If the token is a RefToken, burn the token, otherwise lock the token
    if (block.chainid == IRefToken(_refToken).NATIVE_ASSET_CHAIN_ID()) {
      _lock(_refTokenBridgeData.token, _refTokenBridgeData.amount);
    } else {
      _burn(_refTokenBridgeData.token, _refTokenBridgeData.amount);
    }

    L2_TO_L2_CROSS_DOMAIN_MESSENGER.sendMessage(_destinationChainId, address(this), _message);

    emit MessageSent(
      _refTokenBridgeData.token,
      _refTokenBridgeData.amount,
      _refTokenBridgeData.recipient,
      _refTokenBridgeData.destinationExecutor,
      _destinationChainId
    );
  }
}
