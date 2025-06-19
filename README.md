# RefTokens – Native Cross-Chain Liquidity for the Superchain

`RefTokenBridge • RefToken • SuperchainERC20`

> ⚠️ **Caution**  
> The contracts have **NOT** been audited yet. This is a work in progress, and cannot be considered production-ready.

---

## What are RefTokens?

`RefTokens` turn any native ERC20 token into a cross-chain asset inside the OP Superchain. Instead of physically bridging tokens, we **bridge intent**:

1.  **Lock** the native token on its origin chain.
2.  **Mint** a deterministic `RefToken` on the destination chain.
3.  **Execute** external protocol logic (Uniswap swaps, LP-adds, etc.) in the same transaction.
4.  **Deliver** the result to _any_ Superchain L2 or roll back and unlock if it reverts.

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

## How it Works

The design introduces `RefTokens`, a standardized remote ERC-20 representation, and a per-chain `RefTokenBridge` that locks, mints, and routes tokens as part of atomic cross-chain executions.

### Core Components

1.  **RefToken**

    - An ERC-20 representation uniquely tied to an original asset on an origin chain `(originChainId, originTokenAddress)`. Its contract address is deterministically derived using `CREATE2`, meaning a `RefToken` (e.g., OP on OPM) will have the same address on any destination chain. This prevents front-running and simplifies integration.

2.  **RefTokenBridge**

    - The bridge in charge of the lock/mint & burn/release mechanism.
    - **On the source chain**: It locks native tokens and initiates a cross-chain message.
    - **On the destination chain**: It receives the message, mints the corresponding `RefToken`, and dispatches the action to an executor. It also handles burning `RefTokens` to unlock the native asset on the origin.

3.  **AppActionExecutor** (pluggable)
    - A contract responsible for executing application-specific logic (e.g., a Uniswap swap) using the `RefToken` on the destination chain. This decouples protocol logic from the bridge.

Any `Executor` that wants to use this system will have to implement this interface:

```solidity
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

### Flows

1.  **Cross-Chain Swap (OP ⇒ UNI)**
    ![flow-1](https://github.com/user-attachments/assets/057bb48f-e117-4b57-bf75-718221ae45b7)

    A user locks native `OP` on the origin chain → `refOP` is minted on the destination chain → a `UniSwapperExecutor` swaps `refOP` to `UNI` → `UNI` is sent to the recipient.

2.  **Execute Swap (OP ⇒ WETH) + Cross-Chain Swap (WETH ⇒ UNI)**
    ![flow-2](https://github.com/user-attachments/assets/6fa9313b-953f-441c-b438-b735e2c7a734)

    A user first swaps `OP` for `WETH` on the origin chain → then locks the native `WETH` → `refWETH` is minted on the destination chain → it's swapped to `UNI` → `UNI` is sent to the recipient.

3.  **Send without execute**
    ![flow-3](https://github.com/user-attachments/assets/c00eace3-7bd4-47d4-ba62-fe80c6fedce1)

    Lock a native token → mint the corresponding `RefToken` on the destination chain → send it directly to the recipient (no fallback execution).

4.  **Failure Rollback**
    ![flow-4](https://github.com/user-attachments/assets/250e31ac-7081-466b-b737-c98a9f9cacd4)

    Assuming that the first steps were executed properly, after that the message got relayed on Unichain chain:

    If the downstream call on the destination chain reverts, the freshly minted `RefToken` is burned and a message is sent back to the origin chain to unlock the original asset.

    > ⚠️ This is a fallback mechanism if the `AppActionExecutor` call fails. It won't protect funds from a buggy implementation with an undesired output that didn't revert.

5.  **Post-Launch SuperchainTokenBridge Integration**
    ![flow-5](https://github.com/user-attachments/assets/a6e34b6e-50c4-44b6-8c65-27a886d0e4e0)

    Once the canonical bridge is live, `crosschainBurn` + `crosschainMint` will let users seamlessly redeem locked native assets for the real thing via the official bridge.

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

### Modules

| Module                    | Responsibility                                          |
| ------------------------- | ------------------------------------------------------- |
| **RefToken**              | Cross-chain representation of a native token.           |
| **RefTokenBridge**        | Lock / mint / burn / unlock logic & rollback messaging. |
| **AppActionExecutor**     | Protocol-specific logic (swap, LP, etc.).               |
| **SuperchainTokenBridge** | Future integration for unified ERC-20 bridging.         |

---

### Periphery

- **UniSwapperExecutor** – Reference executor for Uniswap v4.
- **Create2Deployer** – Helper for deterministic `RefToken` deployment.
- **Libraries** – Encoding helpers and cross-domain messenger utilities.

### Failure-Mode Analysis

- A malicious or buggy `AppActionExecutor` can lead to user fund loss.
- The `RefTokenBridge` is the most critical contract: it must never mint more than it has locked.
- Liquidity can become fragmented if the same underlying asset originates from multiple chains.
- A rollback returns the _locked_ asset, which may differ from the asset originally supplied by the user in multi-hop scenarios (e.g. user supplies OP, it's swapped to WETH, WETH is bridged, action fails, user gets WETH back, not OP).

---

## Risks & Uncertainties

1.  **Liquidity Fragmentation** – Different origins create distinct `RefToken` addresses for the same underlying asset (e.g., `USDT` from OP Mainnet and `USDT` from Base will be different `RefTokens` on a third chain).
2.  **Execution Re-entrancy** – Executors must not call bridge methods in the same transaction to avoid re-entrancy bugs.

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

1.  Fill in `.env` with RPC URLs, private keys and Etherscan keys.
2.  Import the deployer key into Foundry:

```bash
cast wallet import $OPTIMISM_DEPLOYER_NAME --interactive
```

3.  Deploy:

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

Built with ❤️ by Wonderland
