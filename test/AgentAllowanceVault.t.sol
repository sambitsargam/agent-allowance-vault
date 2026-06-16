// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentAllowanceVault} from "../src/AgentAllowanceVault.sol";

/// @dev Minimal ERC20 for tests.
contract MockERC20 {
    string public name = "Mock PROS";
    string public symbol = "mPROS";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract AgentAllowanceVaultTest is Test {
    AgentAllowanceVault vault;
    MockERC20 token;

    address owner = address(this);
    address agent = makeAddr("agent");
    address merchant = makeAddr("merchant");
    address attacker = makeAddr("attacker");

    uint256 constant CAP = 100 ether;
    uint256 constant MAX_TX = 40 ether;
    uint256 constant PERIOD = 1 days;

    function setUp() public {
        token = new MockERC20();
        vault = new AgentAllowanceVault(address(token));
        token.mint(owner, 1000 ether);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(500 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_DeployAndFund() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.vaultBalance(), 500 ether);
        assertEq(vault.asset(), address(token));
        assertFalse(vault.isNative());
    }

    function test_GrantAndPayWithinBudget() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        assertEq(vault.remainingAllowance(agent), CAP);

        vm.prank(agent);
        uint256 remaining = vault.pay(merchant, 30 ether);

        assertEq(remaining, 70 ether);
        assertEq(token.balanceOf(merchant), 30 ether);
        assertEq(vault.remainingAllowance(agent), 70 ether);
    }

    function test_BudgetResetsAfterPeriod() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.prank(agent);
        vault.pay(merchant, 40 ether);
        assertEq(vault.remainingAllowance(agent), 60 ether);

        vm.warp(block.timestamp + PERIOD + 1);
        assertEq(vault.remainingAllowance(agent), CAP);

        vm.prank(agent);
        vault.pay(merchant, 40 ether);
        assertEq(vault.remainingAllowance(agent), 60 ether); // fresh period
        assertEq(token.balanceOf(merchant), 80 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            GUARDRAILS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_OverPerTxLimit() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgentAllowanceVault.PerTxLimitExceeded.selector, 41 ether, MAX_TX)
        );
        vault.pay(merchant, 41 ether);
    }

    function test_RevertWhen_OverBudget() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.startPrank(agent);
        vault.pay(merchant, 40 ether);
        vault.pay(merchant, 40 ether); // 80 spent
        vm.expectRevert(
            abi.encodeWithSelector(AgentAllowanceVault.BudgetExceeded.selector, 40 ether, 20 ether)
        );
        vault.pay(merchant, 40 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedAgentPays() public {
        vm.prank(attacker);
        vm.expectRevert(AgentAllowanceVault.NotAuthorizedAgent.selector);
        vault.pay(merchant, 1 ether);
    }

    function test_RevertWhen_AllowanceExpired() public {
        uint64 expiry = uint64(block.timestamp + 1 hours);
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, expiry);
        vm.warp(block.timestamp + 2 hours);
        vm.prank(agent);
        vm.expectRevert(AgentAllowanceVault.AllowanceExpired.selector);
        vault.pay(merchant, 1 ether);
    }

    function test_RevertWhen_Revoked() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vault.revokeAllowance(agent);
        vm.prank(agent);
        vm.expectRevert(AgentAllowanceVault.NotAuthorizedAgent.selector);
        vault.pay(merchant, 1 ether);
    }

    function test_RevertWhen_Paused() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vault.setPaused(true);
        vm.prank(agent);
        vm.expectRevert(AgentAllowanceVault.ContractPaused.selector);
        vault.pay(merchant, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                       OVER-BUDGET APPROVAL FLOW
    //////////////////////////////////////////////////////////////*/

    function test_RequestApproveFlow() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);

        vm.prank(agent);
        uint256 id = vault.requestPayment(merchant, 250 ether); // way over cap

        vault.approvePayment(id);
        assertEq(token.balanceOf(merchant), 250 ether);

        AgentAllowanceVault.PendingPayment memory p = vault.getPendingPayment(id);
        assertTrue(p.executed);
    }

    function test_RevertWhen_NonOwnerApproves() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.prank(agent);
        uint256 id = vault.requestPayment(merchant, 250 ether);

        vm.prank(attacker);
        vm.expectRevert(AgentAllowanceVault.NotOwner.selector);
        vault.approvePayment(id);
    }

    function test_CancelByAgent() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.startPrank(agent);
        uint256 id = vault.requestPayment(merchant, 250 ether);
        vault.cancelPayment(id);
        vm.stopPrank();

        vm.expectRevert(AgentAllowanceVault.PaymentAlreadySettled.selector);
        vault.approvePayment(id);
    }

    function test_RevertWhen_DoubleApprove() public {
        vault.grantAllowance(agent, CAP, MAX_TX, PERIOD, 0);
        vm.prank(agent);
        uint256 id = vault.requestPayment(merchant, 10 ether);
        vault.approvePayment(id);
        vm.expectRevert(AgentAllowanceVault.PaymentAlreadySettled.selector);
        vault.approvePayment(id);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN / OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_OnlyOwnerWithdraws() public {
        vm.prank(attacker);
        vm.expectRevert(AgentAllowanceVault.NotOwner.selector);
        vault.withdraw(attacker, 1 ether);

        vault.withdraw(owner, 100 ether);
        assertEq(vault.vaultBalance(), 400 ether);
    }

    function test_TwoStepOwnership() public {
        address newOwner = makeAddr("newOwner");
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), owner); // not yet

        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner);
    }

    function test_RevertWhen_WrongAcceptOwnership() public {
        vault.transferOwnership(makeAddr("newOwner"));
        vm.prank(attacker);
        vm.expectRevert(AgentAllowanceVault.NotOwner.selector);
        vault.acceptOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZING
    //////////////////////////////////////////////////////////////*/

    function testFuzz_NeverExceedsCapWithinPeriod(uint256 a1, uint256 a2) public {
        vault.grantAllowance(agent, CAP, 0, PERIOD, 0);
        a1 = bound(a1, 1, CAP);
        a2 = bound(a2, 1, CAP);

        vm.startPrank(agent);
        vault.pay(merchant, a1);
        if (a1 + a2 > CAP) {
            vm.expectRevert();
            vault.pay(merchant, a2);
        } else {
            vault.pay(merchant, a2);
            assertLe(token.balanceOf(merchant), CAP);
        }
        vm.stopPrank();
    }
}
