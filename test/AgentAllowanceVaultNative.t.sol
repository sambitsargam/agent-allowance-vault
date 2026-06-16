// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentAllowanceVault} from "../src/AgentAllowanceVault.sol";

/// @dev Native-PHRS vault tests (asset == address(0)).
contract AgentAllowanceVaultNativeTest is Test {
    AgentAllowanceVault vault;

    address owner = address(this);
    address agent = makeAddr("agent");
    address merchant = makeAddr("merchant");
    address attacker = makeAddr("attacker");

    uint256 constant CAP = 1 ether;
    uint256 constant MAX_TX = 0.4 ether;
    uint256 constant PERIOD = 1 days;

    function setUp() public {
        vault = new AgentAllowanceVault(address(0)); // native vault
        vm.deal(owner, 100 ether);
        vault.depositNative{value: 10 ether}();
    }

    receive() external payable {} // owner can receive native on withdraw

    function test_IsNativeAndFunded() public view {
        assertTrue(vault.isNative());
        assertEq(vault.vaultBalance(), 10 ether);
    }

    function test_PlainTransferFundsVault() public {
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vault.vaultBalance(), 11 ether);
    }

    function test_AgentPaysNativeWithinBudget() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        uint256 before = merchant.balance;

        vm.prank(agent);
        uint256 remaining = vault.pay(merchant, 0.3 ether);

        assertEq(remaining, 0.7 ether);
        assertEq(merchant.balance - before, 0.3 ether);
        assertEq(vault.vaultBalance(), 9.7 ether);
    }

    function test_RevertWhen_OverPerTxLimitNative() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentAllowanceVault.PerTxLimitExceeded.selector, 0.5 ether, MAX_TX
            )
        );
        vault.pay(merchant, 0.5 ether);
    }

    function test_RequestApproveNative() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        uint256 before = merchant.balance;

        vm.prank(agent);
        uint256 id = vault.requestPayment(merchant, 5 ether); // over cap

        vault.approvePayment(id);
        assertEq(merchant.balance - before, 5 ether);
    }

    function test_OwnerWithdrawNative() public {
        uint256 before = owner.balance;
        vault.withdraw(owner, 2 ether);
        assertEq(owner.balance - before, 2 ether);
        assertEq(vault.vaultBalance(), 8 ether);
    }

    function test_RevertWhen_DepositErc20OnNativeVault() public {
        vm.expectRevert(AgentAllowanceVault.NotERC20Vault.selector);
        vault.deposit(1 ether);
    }

    function test_RevertWhen_AttackerWithdrawsNative() public {
        vm.prank(attacker);
        vm.expectRevert(AgentAllowanceVault.NotOwner.selector);
        vault.withdraw(attacker, 1 ether);
    }
}
