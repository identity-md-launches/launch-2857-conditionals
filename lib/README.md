# Vendored dependencies

These are ordinary files committed to the repository, not git submodules, so the project builds
with no network access.

| Directory | Source | Version | Licence |
|---|---|---|---|
| `forge-std/` | https://github.com/foundry-rs/forge-std | v1.11.0 (`src/` only, tests and scripts dropped) | MIT / Apache-2.0 |
| `openzeppelin-contracts/` | https://github.com/OpenZeppelin/openzeppelin-contracts | v5.4.0, the ERC-20 subset only | MIT |

The OpenZeppelin subset is exactly the files `ERC20.sol` transitively imports: `ERC20.sol`,
`IERC20.sol`, `extensions/IERC20Metadata.sol`, `utils/Context.sol` and
`interfaces/draft-IERC6093.sol`. They are unmodified copies of the release files.
