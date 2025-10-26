# 🪙 Presale Smart Contract

A secure and configurable **token presale** smart contract built in Solidity, supporting **USDT** and **USDC** payments.  
Developed using **OpenZeppelin** libraries for security and best practices.

---

## 📋 Overview

The `Presale` contract allows users to purchase project tokens during a limited sale period using stablecoins (USDT or USDC).  
It manages multiple **phases**, **blacklisting**, and **fund collection**, ensuring smooth and transparent presale operations.

---

## ⚙️ Features

✅ **Multi-phase presale system**  
- Each phase can have a cap, token price, and time limit.  
- Automatically updates to the next phase based on tokens sold or time elapsed.

✅ **Stablecoin payments (USDT / USDC)**  
- Buyers can use either USDT or USDC.  
- Handles different decimal formats safely.

✅ **Blacklist system**  
- Prevents specific addresses from participating.

✅ **Emergency withdrawals**  
- Owner can recover ERC20 or ETH in emergencies.

✅ **Secure transfers**  
- Uses `SafeERC20` to prevent token transfer failures.  
- Built on OpenZeppelin’s audited contracts (`Ownable`, `SafeERC20`, `IERC20`).

---

## 🧱 Contract Architecture

### State Variables

| Variable | Type | Description |
|-----------|------|-------------|
| `usdtAddress` | `address` | Address of the USDT token contract |
| `usdcAddress` | `address` | Address of the USDC token contract |
| `fundsReceiverAddress` | `address` | Wallet where collected funds are sent |
| `maxSellingAmount` | `uint256` | Maximum total tokens to sell during presale |
| `startingTime` | `uint256` | Timestamp when presale starts |
| `endingTime` | `uint256` | Timestamp when presale ends |
| `phases` | `uint256[][3]` | Each phase: `[cap, price, endTime]` |
| `currentPhase` | `uint256` | Current phase index |
| `totalSold` | `uint256` | Total tokens sold so far |
| `isBlackListed` | `mapping(address => bool)` | Tracks blacklisted users |
| `userTokenBalance` | `mapping(address => uint256)` | Tokens each user has purchased |

---

## 🔑 Key Functions

### 🧭 `buyWithStable(address tokenUsedToBuy_, uint256 amount_)`
Buy tokens with USDT or USDC.

- Validates presale timing and buyer status.
- Calculates how many tokens the user receives based on the current phase price.
- Transfers stablecoins to the `fundsReceiverAddress`.
- Emits a `TokenBought` event.

### ⚙️ `checkCurrentPhase(uint256 amount_)`
Private function that updates the current phase if:
- The current phase cap is reached, or
- The current phase end time has passed.

### 🚫 `blackList(address user_)` / `removeFromBlackList(address user_)`
Owner-only functions to manage blacklisted users.

### 💸 `emergencyERC20Withdraw(address token, uint256 amount)`
Owner-only function to recover ERC20 tokens from the contract.

### 🪙 `emergencyETHWithdraw()`
Owner-only function to recover any ETH accidentally sent to the contract.

---

## 🧮 Phases Example

The `phases` variable is an array of arrays.  
Each phase entry follows this structure:

```solidity
[ phaseCap, tokenPrice, phaseEndTimestamp ]
```

Example (3 phases):

```solidity
[
  [100_000 ether, 10_000, 1700000000], // Phase 1
  [200_000 ether, 12_000, 1710000000], // Phase 2
  [300_000 ether, 14_000, 1720000000]  // Phase 3
]
````

## 🚀 Deployment

### Prerequisites

- Node.js & npm
- Foundry or Hardhat
- OpenZeppelin contracts installed

## 🧠 Security Notes

- Only USDT and USDC are accepted as payment.
- Always verify phase configuration before deployment.
- Blacklisted users cannot buy.
- The contract uses SafeERC20 to protect against non-standard ERC20 implementations.
- Use emergencyWithdraw functions only when necessary.

## 👤 Author

Guillermo Pastor Küster | Blockchain Accelerator

💼 Project: Presale Smart Contract

📧 Contact: gpastor.kuster@gmail.com
