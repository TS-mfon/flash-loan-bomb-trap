# Flash Loan Bomb Trap

A Drosera trap that detects flash loan attacks by monitoring lending pool borrow spikes and TVL drain patterns in a single block.

## Real-World Hack: Euler Finance ($197M Loss)

In March 2023, Euler Finance was exploited for approximately **$197 million** in one of the largest DeFi hacks in history. The attacker used flash loans to borrow massive amounts of DAI from Aave, deposited them into Euler, then exploited a vulnerability in Euler's `donateToReserves` function to create bad debt. The flash-loaned funds were used to artificially inflate borrow positions within a single transaction, draining the protocol's reserves before anyone could react.

The defining characteristic of the attack was the **extreme borrow spike relative to pool TVL** that occurred within a single Ethereum block. Normal lending operations never see borrowing volumes that represent 15% or more of the entire pool in one block. A trap monitoring for this anomaly could have triggered an emergency pause before the funds were extracted.

## Attack Vector: Flash Loan Bombing

Flash loan attacks follow a consistent pattern:

1. **Attacker takes out a flash loan** -- borrowing millions in tokens from Aave, dYdX, or another flash loan provider, requiring zero collateral.
2. **Attacker deposits into the target protocol** -- inflating their position or the protocol's apparent TVL.
3. **Attacker exploits a vulnerability** -- using the inflated position to trigger bad liquidations, mint unbacked tokens, manipulate pricing, or call a vulnerable function.
4. **Attacker extracts funds** -- withdrawing more than they deposited, draining the protocol's reserves.
5. **Flash loan is repaid** -- all within a single atomic transaction.

The telltale sign: **borrowing volume spikes far beyond normal in a single block**, and **pool TVL drops sharply**.

## How the Trap Works

### Data Collection (`collect()`)

Every block, the trap reads two metrics from the Aave V3 pool (`0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`):

- **`poolBalance`** -- The USDC balance held by the lending pool (measured via `IERC20.balanceOf()` on USDC at `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`)
- **`totalBorrows`** -- The total outstanding borrows reported by the pool's `totalBorrows()` function
- **`blockNumber`** -- The current block number

If either call reverts, the value defaults to zero so the trap avoids false positives from failed reads.

### Trigger Logic (`shouldRespond()`)

The trap compares current and previous block data and triggers on two conditions:

**Condition 1: Borrow Spike > 15% of Pool TVL**

```
borrow_increase = current_totalBorrows - previous_totalBorrows
spike_bps = (borrow_increase * 10000) / previous_poolBalance
TRIGGER if spike_bps > 1500 (15%)
```

This catches flash loan attacks where borrowing surges abnormally relative to the pool's total value.

**Condition 2: TVL Drain > 20%**

```
drain = previous_poolBalance - current_poolBalance
drain_bps = (drain * 10000) / previous_poolBalance
TRIGGER if drain_bps > 2000 (20%)
```

This catches the fund extraction phase of the attack, where the pool balance drops sharply as the attacker withdraws.

## Threshold Values

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `BORROW_SPIKE_BPS` | 1500 (15%) | Normal lending pools see gradual borrowing across many blocks. A 15% borrow spike in a single block is overwhelmingly indicative of flash loan activity rather than organic demand. |
| TVL drain threshold | 2000 (20%) | A 20% single-block drain is catastrophic and virtually never occurs during normal protocol operation. Even during market crashes, withdrawals are spread across many blocks. |
| `block_sample_size` | 10 | Provides context across 10 blocks to detect multi-transaction attacks that may spread across consecutive blocks. |

## Configuration (`drosera.toml`)

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps.flash_loan_bomb_trap]
path = "out/FlashLoanBombTrap.sol/FlashLoanBombTrap.json"
response_contract = "0x0000000000000000000000000000000000000000"
response_function = "emergencyPause()"
cooldown_period_blocks = 33
min_number_of_operators = 1
max_number_of_operators = 2
block_sample_size = 10
private_trap = false
whitelist = []
```

| Field | Description |
|-------|-------------|
| `ethereum_rpc` | RPC endpoint for the Ethereum chain being monitored (Hoodi testnet) |
| `drosera_rpc` | RPC endpoint for the Drosera relay network |
| `eth_chain_id` | Chain ID of the target network |
| `drosera_address` | Address of the Drosera protocol contract |
| `path` | Path to the compiled trap artifact (produced by `forge build`) |
| `response_contract` | Address of the contract to call when the trap triggers (set to zero address as placeholder) |
| `response_function` | Function signature to call on the response contract |
| `cooldown_period_blocks` | Minimum blocks between consecutive responses (prevents spam) |
| `min_number_of_operators` | Minimum Drosera operators required to reach consensus |
| `max_number_of_operators` | Maximum operators that can participate |
| `block_sample_size` | Number of consecutive blocks to collect data for |
| `private_trap` | Whether this trap is restricted to whitelisted operators |

## Architecture

```
+---------------------+         +---------------------+
|   Aave V3 Pool      |         |   USDC Token        |
| 0x87870Bca3F3f...   |         | 0xA0b86991c621...   |
+----------+----------+         +----------+----------+
           |                               |
           | totalBorrows()                | balanceOf(pool)
           v                               v
+----------+-------------------------------+----------+
|                                                     |
|                FlashLoanBombTrap                     |
|                                                     |
|  collect():                                         |
|  - poolBalance (USDC in pool)                       |
|  - totalBorrows (outstanding borrows)               |
|  - blockNumber                                      |
+-------------------------+---------------------------+
                          |
                          v
+-------------------------+---------------------------+
|              shouldRespond()                        |
|                                                     |
|  Block N vs Block N-1:                              |
|  - Borrow spike > 15% of TVL?  --> TRIGGER          |
|  - TVL drain > 20%?            --> TRIGGER          |
+-------------------------+---------------------------+
                          |
                          | if triggered
                          v
               +----------+----------+
               |  Response Contract   |
               |  emergencyPause()    |
               +---------------------+
```

## Build

```bash
npm install && forge build
```

## Test

```bash
forge test
```

## Dry Run

```bash
drosera dryrun
```

## Deploy

```bash
export DROSERA_PRIVATE_KEY=<your-private-key>
drosera apply
```

## License

MIT
