# RefTokens – Native Cross-Chain Liquidity for the Superchain

`RefTokenBridge • RefToken • SuperchainERC20`

> ⚠️ **Caution**  
> The contracts have **NOT** been audited yet.  
> Use at your own risk.

---

## Overview

`RefTokens` turn any native ERC2O token into a first-class cross-chain asset inside the OP Superchain.  
Instead of physically bridging tokens, we **bridge intent**:

1. **Lock** the native token on its origin chain.
2. **Mint** a deterministic `RefToken` on the destination chain.
3. **Execute** downstream protocol logic (Uniswap swaps, LP-adds, etc.) in the same transaction.
4. **Deliver** the result to _any_ Superchain L2 or roll back and unlock if it reverts.

---

## Setup

This repository uses **Foundry** for development and **Yarn** for scripting.

```bash
git clone git@github.com:defi-wonderland/op-ref-tokens.git
cd ref-tokens
yarn install
yarn build
```

---

## Available Commands

| Yarn Command                   | Description                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| `yarn build`                   | Compile all contracts.                                                               |
| `yarn build:optimized`         | Compile with the `optimized` Foundry profile (via IR).                               |
| `yarn coverage`                | Generate a coverage report.                                                          |
| `yarn deploy:optimism`         | Deploy to OP Mainnet (set `$OPTIMISM_RPC` & secrets in `.env`).                      |
| `yarn deploy:optimism-sepolia` | Deploy to OP Sepolia testnet.                                                        |
| `yarn test`                    | Run unit **and** integration tests.                                                  |
| `yarn test:unit`               | Run only unit tests.                                                                 |
| `yarn test:unit:deep`          | Unit tests with 5 000 fuzz runs.                                                     |
| `yarn test:integration`        | Run integration tests (fork).                                                        |
| `yarn test:fuzz`               | Run Echidna fuzzing campaign.                                                        |
| `yarn test:symbolic`           | Run Halmos symbolic execution tests.                                                 |
| `yarn lint:bulloak`            | Run Bulloak on every \*.tree file under /test and automatically apply fixes (--fix). |
| `yarn lint:check`              | Solidity & formatting lints (read-only).                                             |
| `yarn lint:fix`                | Auto-fix lint & formatting issues.                                                   |

> Make sure `OPTIMISM_RPC`, `OPTIMISM_DEPLOYER_NAME`, etc. are exported or present in `.env` before running deploy or integration tests.

---

## Design

### Core Components

1. **RefToken**

   - ERC-20 compliant, address derived with `CREATE2` from `(originChainId, originToken)`.
   - Implements `SuperchainERC20` hooks for future `SuperchainTokenBridge` upgrades.

2. **RefTokenBridge**

   - Custodies locked native assets on the source chain.
   - Mints / burns `RefTokens` on source and destination.
   - Rolls back if the downstream call fails (burns and unlocks).

3. **AppActionExecutor** (pluggable)
   - Receives freshly-minted `RefTokens` that have been approved.
   - Executes arbitrary protocol logic.
   - Example: `UniSwapperExecutor` that performs a Uniswap v4 hook-based swap.

Any `Executor` that wants to use this system will have to implement this interface:

```
interface IExecutor {
  function execute(
    address _token,
    address _recipient,
    uint256 _amount,
    uint256 _destinationChainId,
    bytes calldata _data
  ) external;
}
```

---

### Flows

1. **Cross-Chain Swap (OP ⇒ UNI)**  
   lock native OP → mint `refOP` on Unichain → swap to UNI → deliver to recipient.

2. **Execute Swap (OP ⇒ WETH) + Cross-Chain Swap (WETH ⇒ UNI)**  
   user uses OP executor to swap OP→WETH → lock native WETH → mint `refWETH` on Unichain → swap to UNI → deliver to recipient.

3. **Plain Send**  
   lock token → mint `RefToken` to recipient (no downstream execution).

4. **Failure Rollback**  
   downstream call reverts → burn `RefToken` → unlock original asset on source.

5. **Post-Launch SuperchainTokenBridge**  
   once the canonical bridge is live, `crosschainBurn` + `crosschainMint` let users seamlessly redeem locked native assets.

---

### Modules

| Module                    | Responsibility                                          |
| ------------------------- | ------------------------------------------------------- |
| **RefTokenBridge**        | Lock / mint / burn / unlock logic & rollback messaging. |
| **AppActionExecutor**     | Protocol-specific logic (swap, LP, etc.).               |
| **SuperchainTokenBridge** | Future integration for unified ERC-20 bridging.         |

---

### Periphery

- **UniSwapperExecutor** – Reference executor for Uniswap v4.
- **Create2Deployer** – Helper for deterministic `RefToken` deployment.
- **Libraries** – Encoding helpers and cross-domain messenger utilities.

---

## Failure-Mode Analysis

- Malicious or buggy `AppActionExecutor` → user fund loss.
- `RefTokenBridge` is the single most critical contract: it must never mint more than it has locked.
- Liquidity fragmentation if the same underlying asset originates from multiple chains.
- Rollback returns the _locked_ asset, which may differ from the asset originally supplied by the user in multi-hop scenarios.

---

## Risks & Uncertainties

1. **Liquidity Fragmentation** – different origins create distinct `RefToken` addresses.
2. **Execution Re-entrancy** – executors must not call bridge methods in the same tx.
3. **Paused Canonical Bridges** – until official bridges are live, redemption only works via the originating `RefTokenBridge`.

---

## Build

Fast compile:

```bash
yarn build
```

Optimised (IR):

```bash
yarn build:optimized
```

---

## Running Tests

```bash
# All tests
yarn test

# Only unit
yarn test:unit

# Deep fuzz (5 000 runs)
yarn test:unit:deep

# Integration (fork)
yarn test:integration
```

Static analysis & coverage:

```bash
yarn coverage
yarn lint:check
```

---

## Deploy & Verify

1. Fill in `.env` with RPC URLs, private keys and Etherscan keys.
2. Import the deployer key into Foundry:

```bash
cast wallet import $OPTIMISM_DEPLOYER_NAME --interactive
```

3. Deploy:

```bash
yarn deploy:optimism      # mainnet
yarn deploy:optimism-sepolia
```

Broadcast files land in `./broadcast`.

See the Foundry Book for advanced flags.

---

## Licensing

Primary license: **MIT** – see [LICENSE](./LICENSE).

---

## Contributors

Built with ❤️ by

- @0x Discotech
- @Ashitaka h
