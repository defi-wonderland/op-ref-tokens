// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PrecomputeRefToken} from './PrecomputeRefToken.t.sol';
import {Test} from 'forge-std/Test.sol';

/**
 * @title Helpers
 * @notice Contains helper functions for tests
 */
contract Helpers is Test, PrecomputeRefToken {
  /// EOAs
  address public caller = makeAddr('caller');
  address public recipient = makeAddr('recipient');

  /// Variables
  uint256 public nativeAssetChainId = 2;
  string public nativeAssetName = 'Native Asset';
  string public nativeAssetSymbol = 'NA';
  uint8 public nativeAssetDecimals = 18;
  address public nativeAsset = makeAddr('NativeAsset');

  /// Constants
  address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

  /**
   * @notice Ensures that a fuzzed address can be used for deployment and calls
   *
   * @param _address The address to check
   */
  function _assumeFuzzable(address _address) internal pure {
    assumeNotForgeAddress(_address);
    assumeNotZeroAddress(_address);
    assumeNotPrecompile(_address);
  }

  /**
   * @notice Sets up a mock and expects a call to it
   *
   * @param _receiver The address to have a mock on
   * @param _calldata The calldata to mock and expect
   * @param _returned The data to return from the mocked call
   */
  function _mockAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
    vm.mockCall(_receiver, _calldata, _returned);
    vm.expectCall(_receiver, _calldata);
  }

  /**
   * @notice Sets up a mock revert and expects a call to it
   *
   * @param _receiver The address to have a mock on
   * @param _calldata The calldata to mock and expect
   * @param _returned The data to return from the mocked call
   */
  function _mockRevertAndExpect(address _receiver, bytes memory _calldata, bytes memory _returned) internal {
    vm.mockCallRevert(_receiver, _calldata, _returned);
    vm.expectCall(_receiver, _calldata);
  }

  /**
   * @notice Creates a mock contract, labels it and erases the bytecode
   *
   * @param _name The label to use for the mock contract
   * @return _contract The address of the mock contract
   */
  function _mockContract(string memory _name) internal returns (address _contract) {
    _contract = makeAddr(_name);
    vm.etch(_contract, hex'69');
  }

  /**
   * @notice Sets an expectation for an event to be emitted
   *
   * @param _contract The contract to expect the event on
   */
  function _expectEmit(address _contract) internal {
    vm.expectEmit(true, true, true, true, _contract);
  }

  /**
   * @notice Excludes address(0) from the address
   *
   * @param _addr The address to exclude
   * @return _boundedAddress The address excluding address(0)
   *
   */
  function _excludingAddressZero(address _addr) internal returns (address _boundedAddress) {
    _boundedAddress = _boundAddressBetween(_addr, address(1), address(type(uint160).max));
  }

  /**
   * @notice Clamps an address between a start and end range
   *
   * @param _addr The address to clamp
   * @param _startRange The start of the range
   * @param _endRange The end of the range
   * @return _boundedAddress The clamped address
   *
   */
  function _boundAddressBetween(
    address _addr,
    address _startRange,
    address _endRange
  ) internal returns (address _boundedAddress) {
    _boundedAddress = address(uint160(bound(uint160(_addr), uint160(_startRange), uint160(_endRange))));

    vm.label(_boundedAddress, 'random address');
  }

  /**
   * @notice Generates a random address that is not equal to a specific address (ie contract)
   *
   * @param _address1 The address to bound
   * @param _constantAddress The constant address to bound against
   * @return _address1 The bounded address
   */
  function _boundNotEq(address _address1, address _constantAddress) internal returns (address) {
    _address1 = _excludingAddressZero(_address1);

    while (_address1 == _constantAddress) {
      unchecked {
        uint160 _seed = uint160(bytes20(keccak256(abi.encodePacked(_address1, _constantAddress))));
        _address1 = address(_seed);
      }
      _address1 = _excludingAddressZero(_address1);
    }

    vm.label(_address1, 'random address');

    return _address1;
  }
}
