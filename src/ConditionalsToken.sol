// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Conditionals (COND)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, to the deployer, in the
/// constructor. There is no owner, no minter, no pause, no blocklist, no tax and no upgrade path:
/// after deployment the contract has no privileged function of any kind.
/// @dev The Solidity name `ConditionalsToken` is the identifier the launch records; the token's
/// own name and symbol are what `name()` and `symbol()` return. Everything the token does is the
/// unmodified OpenZeppelin v5 ERC-20 implementation.
contract ConditionalsToken is ERC20 {
    /// @notice The token name returned by `name()`.
    string public constant TOKEN_NAME = "Conditionals";

    /// @notice The token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "COND";

    /// @notice The number of decimals, as `decimals()` returns it.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice The whole supply in minor units: 1,000,000,000 tokens at 18 decimals.
    /// @dev This is minted exactly once, in the constructor, and can never grow afterwards.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints the entire supply to the deployer.
    /// @dev Takes no arguments and calls no other contract, so it runs on an empty chain. The
    /// deployer at launch is the factory, which then distributes the supply as the launch dictates.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
