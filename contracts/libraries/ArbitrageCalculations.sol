// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    FHE,
    euint128,
    euint64,
    ebool
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title ArbitrageCalculations
 * @dev Library containing all FHE-based arbitrage detection and calculation logic
 */
library ArbitrageCalculations {
    
    /**
     * @dev Calculate encrypted price spread between two pools
     * @param priceA Encrypted price from pool A
     * @param priceB Encrypted price from pool B
     * @return Encrypted absolute difference between prices
     */
    function calculateSpread(
        euint128 priceA,
        euint128 priceB
    ) internal pure returns (euint128) {
        // Calculate absolute difference using FHE operations
        ebool aGreaterThanB = FHE.gt(priceA, priceB);
        euint128 diff1 = FHE.sub(priceA, priceB);
        euint128 diff2 = FHE.sub(priceB, priceA);
        
        // Return the absolute difference
        return FHE.select(aGreaterThanB, diff1, diff2);
    }

    /**
     * @dev Determine if arbitrage opportunity exists
     * @param spread Encrypted price spread
     * @param threshold Encrypted minimum threshold for arbitrage
     * @return True if spread exceeds threshold (encrypted boolean)
     */
    function hasArbitrageOpportunity(
        euint128 spread,
        euint128 threshold
    ) internal pure returns (ebool) {
        return FHE.gt(spread, threshold);
    }

    /**
     * @dev Calculate optimal protection fee based on spread and volume
     * @param spread Encrypted arbitrage spread
     * @param volume Encrypted swap volume
     * @param maxFee Encrypted maximum fee cap
     * @return Encrypted protection fee amount
     */
    function calculateProtectionFee(
        euint128 spread,
        euint128 volume,
        euint128 maxFee
    ) internal pure returns (euint128) {
        // Dynamic fee calculation: base fee + spread-based component
        euint128 baseFee = FHE.asEuint128(1000); // 0.1% base fee
        
        // Spread-based component (spread / volume * 10000 for basis points)
        euint128 spreadComponent = FHE.div(
            FHE.mul(spread, FHE.asEuint128(10000)),
            volume
        );
        
        // Total fee = base fee + spread component
        euint128 totalFee = FHE.add(baseFee, spreadComponent);
        
        // Cap at maximum fee
        ebool exceedsMax = FHE.gt(totalFee, maxFee);
        return FHE.select(exceedsMax, maxFee, totalFee);
    }

    /**
     * @dev Calculate LP reward distribution from captured MEV
     * @param capturedMEV Encrypted MEV value captured
     * @param lpSharePercentage Encrypted percentage for LPs (in basis points)
     * @return Encrypted LP reward amount
     */
    function calculateLPRewards(
        euint128 capturedMEV,
        euint64 lpSharePercentage
    ) internal pure returns (euint128) {
        // Convert percentage to euint128 for calculation
        euint128 sharePercent = FHE.asEuint128(lpSharePercentage);
        
        // Calculate LP share: (capturedMEV * lpSharePercentage) / 10000
        euint128 lpRewards = FHE.div(
            FHE.mul(capturedMEV, sharePercent),
            FHE.asEuint128(10000)
        );
        
        return lpRewards;
    }

    /**
     * @dev Estimate potential MEV value from arbitrage spread
     * @param spread Encrypted arbitrage spread
     * @param volume Encrypted trade volume
     * @return Encrypted estimated MEV value
     */
    function estimateMEVValue(
        euint128 spread,
        euint128 volume
    ) internal pure returns (euint128) {
        // MEV estimation: spread * volume * efficiency factor
        euint128 efficiencyFactor = FHE.asEuint128(8000); // 80% efficiency
        
        euint128 grossMEV = FHE.mul(spread, volume);
        euint128 netMEV = FHE.div(
            FHE.mul(grossMEV, efficiencyFactor),
            FHE.asEuint128(10000)
        );
        
        return netMEV;
    }

    /**
     * @dev Calculate proportional rewards for individual LP
     * @param totalRewards Encrypted total rewards to distribute
     * @param lpLiquidity Encrypted LP's liquidity amount
     * @param totalLiquidity Encrypted total pool liquidity
     * @return Encrypted individual LP reward
     */
    function calculateIndividualLPReward(
        euint128 totalRewards,
        euint128 lpLiquidity,
        euint128 totalLiquidity
    ) internal pure returns (euint128) {
        // Proportional calculation: (totalRewards * lpLiquidity) / totalLiquidity
        euint128 numerator = FHE.mul(totalRewards, lpLiquidity);
        return FHE.div(numerator, totalLiquidity);
    }

    /**
     * @dev Apply time-based decay to arbitrage opportunities
     * @param baseSpread Encrypted base arbitrage spread
     * @param timeSinceDetection Time elapsed since detection (in blocks)
     * @return Encrypted adjusted spread with decay applied
     */
    function applyTimeDecay(
        euint128 baseSpread,
        uint256 timeSinceDetection
    ) internal pure returns (euint128) {
        // Apply exponential decay: spread * (decay_factor ^ time)
        // Simplified linear decay for FHE efficiency
        uint256 decayRate = 9900; // 1% decay per block
        uint256 decayFactor = decayRate ** timeSinceDetection / (10000 ** timeSinceDetection);
        
        euint128 decayMultiplier = FHE.asEuint128(decayFactor);
        return FHE.div(
            FHE.mul(baseSpread, decayMultiplier),
            FHE.asEuint128(10000)
        );
    }

    /**
     * @dev Calculate optimal batch size for MEV protection
     * @param totalVolume Encrypted total volume to protect
     * @param gasPrice Current gas price
     * @param protectionBudget Encrypted available budget for protection
     * @return Optimal number of protection transactions
     */
    function calculateOptimalBatchSize(
        euint128 totalVolume,
        uint256 gasPrice,
        euint128 protectionBudget
    ) internal pure returns (uint256) {
        // Simplified calculation - in production would consider gas costs
        uint256 estimatedGasPerTx = 200000;
        uint256 costPerTx = gasPrice * estimatedGasPerTx;
        
        uint256 budget = FHE.decrypt(protectionBudget);
        uint256 maxTransactions = budget / costPerTx;
        
        // Ensure at least 1 transaction, max 10 for efficiency
        if (maxTransactions == 0) return 1;
        if (maxTransactions > 10) return 10;
        
        return maxTransactions;
    }

    /**
     * @dev Validate arbitrage calculation parameters
     * @param spread Encrypted spread value
     * @param threshold Encrypted threshold value
     * @param volume Encrypted volume value
     * @return True if all parameters are valid
     */
    function validateParameters(
        euint128 spread,
        euint128 threshold,
        euint128 volume
    ) internal pure returns (bool) {
        // Check all values are positive
        bool spreadValid = FHE.decrypt(FHE.gt(spread, FHE.asEuint128(0)));
        bool thresholdValid = FHE.decrypt(FHE.gt(threshold, FHE.asEuint128(0)));
        bool volumeValid = FHE.decrypt(FHE.gt(volume, FHE.asEuint128(0)));
        
        return spreadValid && thresholdValid && volumeValid;
    }
}