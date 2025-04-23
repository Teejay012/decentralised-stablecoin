# 💸 Decentralized Stablecoin Engine (DSCEngine)

A fully on-chain, overcollateralized **decentralized stablecoin system** built with Solidity and inspired by protocols like MakerDAO. This project includes mechanisms for minting, burning, depositing collateral, maintaining health factors, and triggering liquidations—all aiming to create a stablecoin that avoids centralized backing.

---

## 🚀 Features

- 🏦 **Overcollateralized Minting** — Users can deposit assets like WETH and WBTC to mint stablecoins.
- 🔐 **Health Factor Protection** — Prevents users from borrowing beyond safe limits.
- 💥 **Liquidation Mechanism** — Automatically liquidates undercollateralized positions with rewards to liquidators.
- 📉 **Secure Price Feeds** — Utilizes Chainlink-compatible oracle mocks for accurate testing.
- 🧪 **Comprehensive Testing** — Built using Foundry with unit tests, fuzzing, and scenario-based integration tests.

---

## 🧱 Contract Breakdown

| Contract                         | Description                                                      |
|----------------------------------|------------------------------------------------------------------|
| `DSCEngine.sol`                  | Core logic: minting, burning, collateral management, liquidation |
| `DecentralizedStableCoin.sol`    | ERC20 contract for the stablecoin                                |
| `ERC20Mock.sol`                  | Mock WETH/WBTC tokens for testing                                |
| `MockV3Aggregator.sol`           | Mock Chainlink price feeds                                       |

---

## Installation

```shell
git clone https://github.com/Teejay012/decentralised-stablecoin.git
cd decentralised-stablecoin
forge install
forge build
```

---

## 🔄 System Workflow

   1. User deposits WETH/WBTC as collateral.
   2. User mints stablecoin (DSC) based on collateral value.
   3. System tracks user's health factor.
   4. If health factor < 1, liquidation is allowed.
   5. Liquidators repay DSC to seize user's discounted collateral.

---

## 🧱 Directory Structure

```shell
.
├── src/
│   ├── DSCEngine.sol
│   ├── DecentralizedStableCoin.sol
│   └── test/
│       └── DSCEngineTest.t.sol
├── script/
├── lib/
├── foundry.toml

```

---

## ✍️ Author
TJ (@EtherEngineer)
Twitter: [@EtherEngineer](https://x.com/Tee_Jay4life)
Building DeFi from scratch. One smart contract at a time.

---

Let me know if you want:
- A custom logo
- Diagrams for liquidation/minting
- Frontend instructions
- A badge for test coverage or CI/CD

You’re ready to push this to GitHub now 🚀

## Information on Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
