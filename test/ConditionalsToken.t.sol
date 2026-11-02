// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";
import {DeployConditionalsToken} from "../script/DeployConditionalsToken.s.sol";

contract ConditionalsTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_BPS = 1_000;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant CLAIMANT = address(0xC1A1);

    ConditionalsToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ConditionalsToken();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Conditionals");
        assertEq(token.TOKEN_SYMBOL(), "COND");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_supplyConstantIsOneBillionAtEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        ConditionalsToken fresh = new ConditionalsToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_deployScriptGivesSupplyToItsCaller() public {
        DeployConditionalsToken deployer = new DeployConditionalsToken();
        // `deploy()` creates the token from inside the script contract, so the script is the deployer.
        ConditionalsToken deployed = deployer.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(deployer)), SUPPLY);
        assertEq(deployed.name(), "Conditionals");
        assertEq(deployed.symbol(), "COND");
    }

    // ---------------------------------------------------------------- transfer

    function test_transferMovesBalanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(DEPLOYER, ALICE, 1_000 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1_000 ether));
        assertEq(token.balanceOf(ALICE), 1_000 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalanceLeavesZero() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 5 ether);
        vm.prank(ALICE);
        token.transfer(ALICE, 5 ether);
        assertEq(token.balanceOf(ALICE), 5 ether);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10 ether, 10 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 10 ether + 1);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------- approve and transferFrom

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(DEPLOYER, ALICE, 7 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(ALICE, 7 ether));
        assertEq(token.allowance(DEPLOYER, ALICE), 7 ether);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(DEPLOYER);
        token.approve(ALICE, 7 ether);
        token.approve(ALICE, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, ALICE), 3 ether);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10 ether);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(DEPLOYER, BOB, 4 ether);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 4 ether));
        assertEq(token.balanceOf(BOB), 4 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 4 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 6 ether);
    }

    function test_transferFromInfiniteAllowanceIsNotReduced() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 4 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 3 ether, 3 ether + 1)
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 3 ether + 1);
    }

    function test_transferFromRevertsAboveBalanceEvenWithAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 2 ether);
        vm.prank(ALICE);
        token.approve(BOB, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 2 ether, 2 ether + 1)
        );
        vm.prank(BOB);
        token.transferFrom(ALICE, CLAIMANT, 2 ether + 1);
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, address(0), 1);
    }

    function test_transferFromOnlyMovesWhatTheOwnerApproved() public {
        // No approval: even the deployer cannot pull from a holder.
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    // ---------------------------------------------------------------- launch flows

    /// @dev The flows the launch performs must arrive whole: no tax, no burn on transfer.
    function test_launchFlowsArriveWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * 8_500) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(DISTRIBUTOR, swarm));
        assertTrue(token.transfer(ALICE, pool)); // stands in for the pool manager
        assertTrue(token.transfer(BOB, remainder)); // stands in for remainderTo
        vm.stopPrank();

        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(ALICE), pool);
        assertEq(token.balanceOf(BOB), remainder);
        assertEq(token.balanceOf(DEPLOYER), 0);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(CLAIMANT), swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- no privileged surface

    function test_noCallIncreasesSupply() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(DEPLOYER);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.balanceOf(ALICE), held);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2));
        assertEq(token.balanceOf(BOB), held / 2);
        assertEq(token.balanceOf(ALICE), held - held / 2);
    }

    function test_noOwnerFunctionExists() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeWithSignature("renounceOwnership()"));
        assertFalse(ok);
    }

    function test_plainEtherIsRefused() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    /// @dev Same reachability scan the launch floor uses: no DELEGATECALL, CALLCODE or SELFDESTRUCT
    /// in reachable runtime code (push data is skipped, unreachable constants are not instructions).
    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(to, amount));
        assertEq(token.totalSupply(), SUPPLY);
        if (to == DEPLOYER) {
            assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        }
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 0, SUPPLY);
        amount = bound(amount, 0, allowance);
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowance);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, amount));
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.allowance(DEPLOYER, ALICE), allowance - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 0, SUPPLY - 1);
        amount = bound(amount, allowance + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, allowance, amount)
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, amount);
    }

    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        vm.prank(BOB);
        token.transfer(CLAIMANT, c);
        assertEq(
            token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CLAIMANT),
            SUPPLY
        );
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - a);
        assertEq(token.balanceOf(ALICE), a - b);
        assertEq(token.balanceOf(BOB), b - c);
        assertEq(token.balanceOf(CLAIMANT), c);
    }
}
