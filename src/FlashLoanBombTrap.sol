// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Trap} from "drosera-contracts/Trap.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title FlashLoanBombTrap
/// @notice Detects flash loan attacks (Euler Finance style - $197M loss)
/// @dev Monitors lending pool TVL and triggers when single-block borrows exceed threshold

interface ILendingPool {
    function totalBorrows() external view returns (uint256);
}

struct CollectOutput {
    uint256 poolBalance;
    uint256 totalBorrows;
    uint256 blockNumber;
}

contract FlashLoanBombTrap is Trap {
    // USDC on mainnet
    address public constant MONITORED_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Aave V3 Pool on mainnet
    address public constant LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    // Trigger if borrows spike > 15% of pool TVL in one block
    uint256 public constant BORROW_SPIKE_BPS = 1500;

    constructor() {}

    function collect() external view override returns (bytes memory) {
        uint256 poolBalance;
        uint256 totalBorrows;

        try IERC20(MONITORED_TOKEN).balanceOf(LENDING_POOL) returns (uint256 bal) {
            poolBalance = bal;
        } catch {
            poolBalance = 0;
        }

        try ILendingPool(LENDING_POOL).totalBorrows() returns (uint256 borrows) {
            totalBorrows = borrows;
        } catch {
            totalBorrows = 0;
        }

        return abi.encode(CollectOutput({
            poolBalance: poolBalance,
            totalBorrows: totalBorrows,
            blockNumber: block.number
        }));
    }

    function shouldRespond(
        bytes[] calldata data
    ) external pure override returns (bool, bytes memory) {
        if (data.length < 2) return (false, bytes(""));

        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));

        // Check for borrow spike
        if (current.totalBorrows > previous.totalBorrows && previous.poolBalance > 0) {
            uint256 borrowIncrease = current.totalBorrows - previous.totalBorrows;

            // If borrowing increased by more than 15% of pool TVL in one block
            if ((borrowIncrease * 10000) / previous.poolBalance > BORROW_SPIKE_BPS) {
                return (true, bytes("Flash loan bomb detected: excessive single-block borrowing"));
            }
        }

        // Check for massive TVL drain alongside borrow spike
        if (previous.poolBalance > 0 && current.poolBalance < previous.poolBalance) {
            uint256 drain = previous.poolBalance - current.poolBalance;
            if ((drain * 10000) / previous.poolBalance > 2000) { // >20% drain
                return (true, bytes("Massive TVL drain alongside borrowing spike"));
            }
        }

        return (false, bytes(""));
    }
}
