// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IExecutor} from 'interfaces/external/IExecutor.sol';

contract UniSwapExecutor is IExecutor {
  error InvalidSelector();
  error ExecutionFailed();

  bytes4 public constant UNIV4_SWAP_SELECTOR = bytes4(keccak256('swap(address,address,uint256,uint160,bytes)'));

  function execute(bytes calldata _data) external {
    (address _target, bytes memory _payload) = abi.decode(_data, (address, bytes));

    bytes4 _selector;
    assembly {
      _selector := mload(add(_payload, 32)) // Skip length prefix
    }

    if (!_isAllowedSelector(_target, _selector)) {
      revert InvalidSelector();
    }

    (bool _success, bytes memory _result) = _target.call(_payload);
    if (!_success) {
      revert ExecutionFailed();
    }
  }

  function _isAllowedSelector(address _target, bytes4 _selector) internal pure returns (bool _isAllowed) {
    _isAllowed = _selector == UNIV4_SWAP_SELECTOR;
  }
}
