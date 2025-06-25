// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';

contract IntegrationRefTokenBridgeTest is IntegrationBase {
  function setUp() public virtual override {
    super.setUp();

    // Set up user funds
    vm.deal(address(_op), _user, 1000 ether);
  }

  function test_sendOpToUnichainWithRefTokenNotDeployed() public {
    // Check that the bridge has no OP
    uint256 _bridgeBalanceBefore = _op.balanceOf(address(_refTokenBridge));
    assertEq(_bridgeBalanceBefore, 0);

    // Check that the user has OP
    uint256 _userBalanceBefore = _op.balanceOf(_user);
    assertEq(_userBalanceBefore, 1000 ether);

    // Check that ref token is not deployed
    address _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    assertEq(_refOp, address(0));

    // Send OP to Unichain
    vm.prank(_user);
    _refTokenBridge.send(_opChainId, _unichainChainId, _user, 500 ether, _recipient);

    // Check that the OP is on the recipient
    assertEq(_op.balanceOf(_user), _userBalanceBefore - 500 ether);
    // Check that the OP is on the bridge
    assertEq(_op.balanceOf(address(_refTokenBridge)), _bridgeBalanceBefore + 500 ether);

    // Check that ref op was deployed
    _refOp = _refTokenBridge.nativeToRefToken(address(_op), _opChainId);
    // Check that the ref token is deployed
    assertEq(_refTokenBridge.nativeToRefToken(address(_op), _opChainId), _refOp);
  }
}
