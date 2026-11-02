# Conditionals (COND)

A fixed-supply ERC-20 token for an IMD custom token launch on Ethereum.

| Property | Value |
|---|---|
| Solidity contract | `ConditionalsToken` (`src/ConditionalsToken.sol`) |
| `name()` | `Conditionals` |
| `symbol()` | `COND` |
| `decimals()` | `18` |
| `totalSupply()` | `1_000_000_000 * 10**18` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minting | once, the whole supply, to `msg.sender`, in the constructor |
| Owner / admin | none |

## Behaviour

The contract is the unmodified OpenZeppelin v5.4.0 `ERC20` with a constructor that mints the
whole supply to the deployer. It adds no other function. In particular there is:

- no owner, minter, or role of any kind, and no `mint` after the constructor, so the supply can
  never grow;
- no pause, blocklist, freeze, lock, seize or `burnFrom`, so nobody but a holder (or a spender the
  holder approved) can move or block a holder's balance;
- no tax, fee, reflection or burn on transfer: every transfer delivers exactly the amount sent;
- no `receive`/`fallback`, so plain ETH sent to the token is refused;
- no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` in the runtime code, and no proxy or upgrade path;
- no external call in the constructor, so it deploys on an empty chain.

`transferFrom` moves tokens only within the allowance the owner granted the caller; the usual
OpenZeppelin custom errors (`ERC20InsufficientBalance`, `ERC20InsufficientAllowance`,
`ERC20InvalidReceiver`, `ERC20InvalidSpender`) are raised on failure.

## Assumptions

- **The deployer gets everything.** At launch the deployer is the IMD `ProjectFactory`, which
  receives the whole supply and distributes it: 10% to the launch's MerkleDistributor, 85% to seed
  the single-sided pool, and the remaining 5% to the requester's `remainderTo` address. The token
  itself does no allocation and holds nothing.
- **The token exempts nobody because it taxes nobody.** The factory, the pool manager and the
  distributor need no special treatment; the launch flows arrive whole by construction. For the
  same reason the constructor takes no `$factory`, `$poolManager` or `$launchNumber` argument.
- **Immutability is the feature.** There is no key that can change anything after deployment.
  If a future need arises for a mint, pause or blocklist, it cannot be added to this contract; a
  new contract would be required.
- The compiler is pinned to `solc = "0.8.26"` with `bytecode_hash = "none"` and
  `cbor_metadata = false` so the built bytecode is reproducible and carries no metadata hash.

## Deployment parameters

| Parameter | Value |
|---|---|
| Chain | Ethereum mainnet (chain id 1) |
| Constructor arguments | none |
| `token.totalSupply` (manifest, minor units) | `1000000000000000000000000000` |
| `token.decimals` (manifest) | `18` |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee / tick spacing | `12500` / `60` (launch policy) |
| Economics | `poolBps` 8500, `initialMarketCapWei` 4500 IMD, `remainderTo` `0xd6302976e590b9b947da8774b7f1246164e0ce98` |

The launch manifest (`launch.json`) is written by the manifest step after this work is accepted;
it is deliberately not part of this repository.

`script/DeployConditionalsToken.s.sol` deploys the token for local or stand-alone use. Its
`deploy()` function takes no configuration and reads no environment, and the tests call it
directly. `run()` wraps it in a broadcast for `forge script`. On the IMD launch the factory deploys
the token from its built bytecode; this script is not used there.

## After launch

Nothing. The token has no owner-settable value and no setter. There is no operational step to take
and no key to hold or rotate.

## Operational responsibilities

- **Requester**: the 5% remainder arrives at `remainderTo`; keep that wallet's key safe. There is
  no admin action available on the token, so nothing else to operate.
- **IMD deployer / factory**: deploys the token, forwards the swarm share, seeds the pool and
  forwards the remainder. None of this is performed from this repository.
- **Holders**: a transfer to the zero address is refused, but a transfer to any other wrong
  address is final; the token cannot recover funds.
- **Explorer verification**: an open item for the deployer after launch, using the pinned
  compiler settings in `foundry.toml` (`solc` 0.8.26, optimizer on, 200 runs, `cancun`,
  `bytecode_hash = "none"`, `cbor_metadata = false`).

## Build and test

```sh
forge build
forge test
forge fmt --check
```

Tests live in `test/ConditionalsToken.t.sol` and cover metadata and supply, success and failure
paths of `transfer`, `approve` and `transferFrom`, the launch flows arriving whole, the absence of
any mint, owner or privileged function, the runtime-code opcode scan, and fuzzed conservation of
supply. They read no environment variables and pass in any order and in parallel. The verifier's
fuzz seed was used locally:

```sh
FOUNDRY_FUZZ_SEED=0x1ffa0fe5fe7160cbb4d857ba7ee13bbc09f5b31878863a0e3d6ff160febd6f91 forge test
```

Slither and Mythril were not available on the build machine and were not run; `forge build`,
`forge test` and `forge fmt --check` were. Passing tests are not a security audit.

## Dependencies

Vendored as ordinary files under `lib/` (see `lib/README.md`): forge-std v1.11.0 and the ERC-20
subset of OpenZeppelin Contracts v5.4.0. No git submodules; the project builds offline.
