// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';

contract IntegrationRefTokenBridgeTest is IntegrationBase {
  function setUp() public virtual override {
    super.setUp();
  }

  function test_sendOpToUnichainWithRefTokenNotDeployed(uint256 _userBalance, uint256 _amountToBridge) public {
    _userBalance = bound(_userBalance, 1, type(uint128).max);
    _amountToBridge = bound(_amountToBridge, 1, _userBalance);

    // Set up user funds
    deal(address(_op), _user, _userBalance);

    // Check that the bridge has no OP
    uint256 _bridgeBalanceBefore = _op.balanceOf(address(_refTokenBridge));
    assertEq(_bridgeBalanceBefore, 0);

    // Check that the user has OP
    uint256 _userBalanceBefore = _op.balanceOf(_user);
    assertEq(_userBalanceBefore, _userBalance);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Approve the bridge to spend the OP
    vm.prank(_user);
    _op.approve(address(_refTokenBridge), _amountToBridge);

    // Send OP to Unichain
    vm.prank(_user);
    _refTokenBridge.send(_opChainId, _unichainChainId, address(_op), _amountToBridge, _recipient);

    // Check that the OP is on the recipient
    assertEq(_op.balanceOf(_user), _userBalanceBefore - _amountToBridge);
    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _bridgeBalanceBefore + _amountToBridge);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    // Check that the ref token is deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
  }
}
