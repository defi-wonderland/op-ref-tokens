# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building and Testing
- `yarn build` - Standard compilation
- `yarn build:optimized` - Optimized compilation via IR (used for production)
- `yarn test` - Run all tests (unit + integration)
- `yarn test:unit` - Unit tests only
- `yarn test:integration` - Integration tests with forked networks
- `yarn test:fuzz` - Run Medusa fuzzing campaign
- `yarn test:symbolic` - Run Halmos symbolic execution

### Code Quality
- `yarn lint:check` - Check Solidity and formatting lints
- `yarn lint:fix` - Auto-fix linting issues
- `yarn lint:bulloak` - Generate test structures from .tree files
- `yarn coverage` - Generate test coverage reports

### Deployment
- `yarn deploy:optimism` - Deploy to OP Mainnet
- `yarn deploy:optimism-sepolia` - Deploy to OP Sepolia testnet

## Project Architecture

**RefTokens** is a cross-chain liquidity protocol for the Optimism Superchain that enables native asset bridging through "intent bridging" rather than physical token transfers.

### Core Architecture Pattern

The protocol follows a **lock-mint-execute-unlock** flow:
1. **Lock** native tokens on origin chain via RefTokenBridge
2. **Mint** RefTokens deterministically on destination chain
3. **Execute** application logic through pluggable executors
4. **Rollback** mechanism if execution fails

### Key Contracts

- **RefTokenBridge** (`/src/contracts/RefTokenBridge.sol`) - Main bridge contract handling the cross-chain mechanics
- **RefToken** (`/src/contracts/RefToken.sol`) - SuperchainERC20-compatible token representing locked native assets
- **UniSwapExecutor** (`/src/external/UniSwapExecutor.sol`) - Reference executor for Uniswap V4 swaps

### Pluggable Executor System

The bridge uses a pluggable executor pattern where any contract implementing `IExecutor.execute()` can be used for application-specific logic. This decouples bridging from execution, allowing for flexible DeFi integrations.

### Deterministic Deployment

RefTokens use CREATE2 for consistent addresses across chains, preventing front-running and simplifying integrations. The deployment salt is configurable via `REF_TOKEN_BRIDGE_SALT` environment variable.

## Testing Methodology

### Test Structure
- **Unit tests** (`/test/unit/`) - Use Bulloak `.tree` files for test structure specification
- **Integration tests** (`/test/integration/`) - Fork-based testing with real protocols
- **Invariant tests** (`/test/invariants/`) - Property-based testing with Medusa
- **Symbolic execution** - Halmos integration for formal verification

### Test Development Workflow
1. Create `.tree` files in unit test directories to specify test structure
2. Run `yarn lint:bulloak` to generate test files from .tree specifications
3. Implement test logic in generated files
4. Use integration tests for end-to-end scenarios with forked networks

## Configuration Files

- **foundry.toml** - Multiple profiles for different build configurations
- **medusa.json** - Fuzz testing configuration with property-based testing
- **remappings.txt** - Import path mappings for dependencies
- **.solhint.json** - Solidity linting rules (120 char line length, single quotes)

## Environment Variables for Deployment

- `OPTIMISM_RPC` - OP Mainnet RPC URL
- `OPTIMISM_DEPLOYER_NAME` - Foundry account name for deployment
- `ETHERSCAN_API_KEY` - For contract verification
- `REF_TOKEN_BRIDGE_SALT` - CREATE2 salt for deterministic deployment

## Code Conventions

- Use single quotes in Solidity code
- 120 character line length limit
- Follow conventional commit message format
- All contracts should be well-documented with NatSpec
- Use Solhint rules defined in `.solhint.json`

## Security Note

⚠️ This protocol is currently a work in progress and has not been audited. The codebase includes comprehensive testing infrastructure with unit tests, integration tests, fuzz testing, and symbolic execution to ensure robustness.