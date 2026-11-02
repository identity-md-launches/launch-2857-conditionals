// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @notice Drives the token with random transfers, approvals and pulls among a fixed set of actors,
/// and keeps its own ledger (ghost balances and allowances) of what each call should have done.
/// Failure paths are exercised too: every call that should revert is checked to revert with the
/// expected error and to leave every balance, allowance and the supply untouched.
contract ConditionalsHandler is Test {
    ConditionalsToken internal immutable token;

    address[] internal actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostSuccessfulTransfers;
    uint256 public ghostExpectedReverts;
    uint256 public ghostUnexpectedOutcomes;

    constructor(ConditionalsToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ------------------------------------------------------------------ succeeding paths

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");

        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore, "self transfer changed balance");
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount, "sender not debited exactly");
            assertEq(token.balanceOf(to), toBefore + amount, "recipient not credited exactly");
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
        ++ghostSuccessfulTransfers;
    }

    /// @dev Liveness: a holder can always move everything it holds.
    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = ghostBalance[from];

        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer of whole balance returned false");
        if (from != to) {
            ghostBalance[from] = 0;
            ghostBalance[to] += amount;
            assertEq(token.balanceOf(from), 0, "whole-balance transfer left a residue");
        }
        ++ghostSuccessfulTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) amount = type(uint256).max;

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        ghostAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount, "approve did not set the allowance exactly");
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        amount = bound(amount, 0, allowed < held ? allowed : held);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "transferFrom returned false");

        if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
        assertEq(token.allowance(owner, spender), ghostAllowance[owner][spender], "allowance not spent exactly");
        if (owner != to) {
            ghostBalance[owner] -= amount;
            ghostBalance[to] += amount;
        }
        ++ghostSuccessfulTransfers;
    }

    /// @dev Round trip: A sends x to B and B sends it back; both end where they started.
    function roundTrip(uint256 aSeed, uint256 bSeed, uint256 amount) external {
        address a = _actor(aSeed);
        address b = _actor(bSeed);
        amount = bound(amount, 0, ghostBalance[a]);
        uint256 aBefore = token.balanceOf(a);
        uint256 bBefore = token.balanceOf(b);

        vm.prank(a);
        token.transfer(b, amount);
        vm.prank(b);
        token.transfer(a, amount);

        assertEq(token.balanceOf(a), aBefore, "round trip changed sender");
        assertEq(token.balanceOf(b), bBefore, "round trip changed recipient");
        ghostSuccessfulTransfers += 2;
    }

    // ------------------------------------------------------------------ failing paths

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        try token.transfer(to, amount) {
            ++ghostUnexpectedOutcomes;
        } catch (bytes memory reason) {
            _expectReason(
                reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
            );
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(address(0), amount) {
            ++ghostUnexpectedOutcomes;
        } catch (bytes memory reason) {
            _expectReason(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            ++ghostUnexpectedOutcomes;
        } catch (bytes memory reason) {
            _expectReason(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        }
    }

    function transferFromAboveAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed == type(uint256).max) return; // an infinite allowance cannot be exceeded
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            ++ghostUnexpectedOutcomes;
        } catch (bytes memory reason) {
            _expectReason(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        }
    }

    function transferFromAboveBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[owner];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        // Give the spender enough allowance, so the balance check is the one that must fail.
        vm.prank(owner);
        token.approve(spender, type(uint256).max);
        ghostAllowance[owner][spender] = type(uint256).max;

        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            ++ghostUnexpectedOutcomes;
        } catch (bytes memory reason) {
            _expectReason(
                reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
            );
        }
    }

    function _expectReason(bytes memory actual, bytes memory expected) internal {
        if (keccak256(actual) != keccak256(expected)) ++ghostUnexpectedOutcomes;
        else ++ghostExpectedReverts;
    }
}

contract ConditionalsTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    ConditionalsToken internal token;
    ConditionalsHandler internal handler;
    address internal constant DEPLOYER = address(0xFAC7);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ConditionalsToken();

        address[] memory actors = new address[](6);
        actors[0] = DEPLOYER;
        actors[1] = address(0xA11CE);
        actors[2] = address(0xB0B);
        actors[3] = address(0xCA41);
        actors[4] = address(0xD157);
        // Tokens sent to the token contract itself are simply held there; it is an actor too.
        actors[5] = address(token);

        // Spread part of the supply so every actor starts with something to move.
        vm.startPrank(DEPLOYER);
        token.transfer(actors[1], SUPPLY / 4);
        token.transfer(actors[2], SUPPLY / 8);
        token.transfer(actors[3], 1);
        vm.stopPrank();

        handler = new ConditionalsHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_supplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, token.totalSupply());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchLedger() public view {
        for (uint256 i; i < handler.actorCount(); ++i) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a));
            assertLe(token.balanceOf(a), SUPPLY);
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchLedger() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address o = handler.actorAt(i);
                address s = handler.actorAt(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_noUnexpectedOutcome() public view {
        assertEq(handler.ghostUnexpectedOutcomes(), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_nothingLeaksOutsideTheActors() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(address(token).balance, 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataIsFixed() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
    }
}
