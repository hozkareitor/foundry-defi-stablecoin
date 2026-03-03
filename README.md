# Decentralized Stable Coin (DSC)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundy-000000.svg)](https://getfoundry.sh/)

A decentralized, over-collateralized stablecoin protocol inspired by DAI but with no governance and minimal fees. DSC maintains a 1:1 peg with USD through algorithmic stability mechanisms.

## 🏗️ Overview

The DSC system consists of two main contracts:

- **DecentralizedStableCoin (DSC)**: The ERC20 stablecoin token
- **DSCEngine**: Core protocol engine managing collateral, minting, burning, and liquidations

### Key Features

- ✨ **Over-collateralized**: Minimum 150% collateralization ratio
- 🔒 **No governance**: Immutable after deployment
- ⚡ **Algorithmic stability**: Health factor based liquidation system
- 💰 **Supported collateral**: WETH and WBTC (extensible)
- 🛡️ **Secure**: CEI pattern, reentrancy guards, and OracleLib for price freshness

## 📊 Test Coverage

| Contract | Lines | Statements | Branches | Functions |
|----------|-------|------------|----------|-----------|
| DSCEngine | 91.85% | 88.33% | 71.43% | 100% |
| DecentralizedStableCoin | 94.74% | 94.12% | 80.00% | 100% |
| OracleLib | 100% | 100% | 100% | 100% |
| **Total** | **77.40%** | **75.56%** | **30.26%** | **89.87%** |

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/foundry-defi-stablecoin
cd foundry-defi-stablecoin

# Install dependencies
make install

# Build the project
make build

Testing
bash

# Run all tests
make test

# Run specific test
forge test --mt test_FunctionName -vvv

# Run fuzz/invariant tests
forge test --match-contract InvariantsTest

# Generate coverage report
make coverage

📁 Project Structure
text

foundry-defi-stablecoin/
├── src/
│   ├── DSCEngine.sol              # Core protocol engine
│   ├── DecentralizedStableCoin.sol # Stablecoin token
│   └── libraries/
│       └── OracleLib.sol           # Chainlink oracle utilities
├── test/
│   ├── unit/                       # Unit tests
│   │   ├── DSCEngineTest.t.sol
│   │   ├── DecentralizedStableCoinTest.t.sol
│   │   └── OracleLibTest.t.sol
│   ├── fuzz/                        # Fuzzing & invariant tests
│   │   ├── Handler.t.sol
│   │   └── InvariantsTest.t.sol
│   └── mocks/                       # Mock contracts
│       ├── ERC20Mock.sol
│       └── MockV3Aggregator.sol
├── script/                          # Deployment scripts
│   ├── DeployDSC.s.sol
│   └── HelperConfig.s.sol
└── foundry.toml                     # Foundry configuration

🌐 Deployment
Local Anvil
bash

# Start Anvil
make anvil

# In another terminal, deploy
make deploy

Sepolia Testnet
bash

# Configure .env file with:
# SEPOLIA_RPC_URL=your_rpc_url
# PRIVATE_KEY=your_private_key
# ETHERSCAN_API_KEY=your_etherscan_key

# Deploy and verify
make deploy ARGS="--network sepolia"

🧪 Invariants

The protocol maintains these critical invariants:

    Over-collateralization: Total collateral value ≥ total DSC supply

    Oracle freshness: All prices must be updated within the last 3 hours

    Health factor consistency: No user with health factor < 1 can mint new DSC

🔒 Security

    All external functions follow CEI pattern

    ReentrancyGuard on all state-changing functions

    OracleLib ensures price data freshness

    Comprehensive test suite with 94 passing tests

    Fuzzing and invariant testing with 10,000+ calls per invariant

📄 License

This project is licensed under the MIT License.
🙏 Acknowledgments

Built following Patrick Collins' Foundry course. The protocol design is inspired by MakerDAO's DAI.