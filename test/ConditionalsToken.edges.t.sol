// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @notice Edge cases beside the main suite: self-spending, the maximum allowance, zero amounts
/// through `transferFrom`, failed calls leaving no trace, and transfers to the token itself.
contract ConditionalsTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    ConditionalsToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ConditionalsToken();
    }

    function test_ownerNeedsAllowanceToTransferFromItself() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 0));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRevertsFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(0), BOB, 1);
    }

    function test_spendingAllowanceEmitsNoApproval() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10 ether);
        vm.recordLogs();
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 4 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "only the Transfer is emitted");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
    }

    function test_wholeSupplyThroughMaxAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, SUPPLY);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max);
    }

    function test_allowanceOneBelowMaxIsSpent() public {
        uint256 allowed = type(uint256).max - 1;
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowed);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
        assertEq(token.allowance(DEPLOYER, ALICE), allowed - 1);
    }

    function test_approveZeroRevokes() public {
        vm.startPrank(DEPLOYER);
        token.approve(ALICE, 5 ether);
        token.approve(ALICE, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_failedTransferFromKeepsAllowanceAndBalances() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 2 ether);
        vm.prank(ALICE);
        token.approve(BOB, 5 ether);
        vm.prank(BOB);
        vm.expectRevert();
        token.transferFrom(ALICE, BOB, 3 ether);
        assertEq(token.allowance(ALICE, BOB), 5 ether);
        assertEq(token.balanceOf(ALICE), 2 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_tokensSentToTheTokenAreHeldNotBurned() public {
        vm.prank(DEPLOYER);
        token.transfer(address(token), 3 ether);
        assertEq(token.balanceOf(address(token)), 3 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferAboveBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1)
        );
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, SUPPLY + 1);
    }

    function test_maxUintTransferReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, type(uint256).max);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactly(address spender, uint256 first, uint256 second) public {
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.startPrank(ALICE);
        token.approve(spender, first);
        assertEq(token.allowance(ALICE, spender), first);
        token.approve(spender, second);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, spender), second);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_roundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.transfer(DEPLOYER, amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
