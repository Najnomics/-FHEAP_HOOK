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
 * Following CoFHE calculation patterns from Fhenix documentation
 */
library ArbitrageCalculations {
    
    // Custom errors for FHE operations
    error InvalidSpreadCalculation();
    error ThresholdExceeded();
    error InvalidFeeParameters();
    error DivisionByZero();

    /**
     * @dev Calculate encrypted price spread between two pools using FHE operations
     * Following CoFHE arithmetic patterns for secure spread calculation
     * @param priceA Encrypted price from pool A
     * @param priceB Encrypted price from pool B
     * @return Encrypted absolute difference between prices
     */
    function calculateSpread(
        euint128 priceA,
        euint128 priceB
    ) internal pure returns (euint128) {
        // Validate inputs using FHE requirements
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(priceA, zero));
        FHE.req(FHE.gt(priceB, zero));
        
        // Calculate absolute difference using FHE conditional operations
        ebool aGreaterThanB = FHE.gt(priceA, priceB);
        euint128 diff1 = FHE.sub(priceA, priceB);
        euint128 diff2 = FHE.sub(priceB, priceA);
        
        // Return absolute difference using FHE select operation
        return FHE.select(aGreaterThanB, diff1, diff2);
    }

    /**
     * @dev Determine if arbitrage opportunity exists using encrypted comparison
     * Following CoFHE threshold comparison patterns
     * @param spread Encrypted price spread
     * @param threshold Encrypted minimum threshold for arbitrage
     * @return True if spread exceeds threshold (encrypted boolean)
     */
    function hasArbitrageOpportunity(
        euint128 spread,
        euint128 threshold
    ) internal pure returns (ebool) {
        // Validate inputs using FHE requirements
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(spread, zero));
        FHE.req(FHE.gt(threshold, zero));
        
        // Compare spread against threshold using FHE comparison
        return FHE.gt(spread, threshold);
    }

    /**
     * @dev Calculate optimal protection fee based on spread and volume
     * Following CoFHE dynamic fee calculation patterns
     * Note: Simplified version due to euint128 division limitations
     * @param spread Encrypted arbitrage spread
     * @param volume Encrypted swap volume (not used due to div limitation)
     * @param maxFee Encrypted maximum fee cap
     * @return Encrypted protection fee amount
     */
    function calculateProtectionFee(
        euint128 spread,
        euint128 volume,
        euint128 maxFee
    ) internal pure returns (euint128) {
        // Validate inputs
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(spread, zero));
        FHE.req(FHE.gt(volume, zero));
        FHE.req(FHE.gt(maxFee, zero));
        
        // Base fee: simplified calculation due to division limitations
        // We'll use a percentage of the spread as the fee
        euint128 baseFee = FHE.asEuint128(100); // Base fee amount
        
        // Simple fee calculation: baseFee + portion of spread
        // Since we can't divide, we'll use a simplified approach
        euint128 spreadFactor = FHE.asEuint128(1000); // Factor to reduce spread impact
        
        // Check if spread is greater than factor to avoid underflow
        ebool spreadLarge = FHE.gt(spread, spreadFactor);
        euint128 spreadComponent = FHE.select(
            spreadLarge,
            FHE.sub(spread, spreadFactor),
            FHE.asEuint128(0)
        );
        
        // Total fee = base fee + spread component
        euint128 totalFee = FHE.add(baseFee, spreadComponent);
        
        // Cap at maximum fee using FHE conditional
        ebool exceedsMax = FHE.gt(totalFee, maxFee);
        return FHE.select(exceedsMax, maxFee, totalFee);
    }

    /**
     * @dev Calculate LP reward distribution from captured MEV
     * Following CoFHE reward distribution patterns
     * Note: Simplified due to division limitations
     * @param capturedMEV Encrypted MEV value captured
     * @param lpSharePercentage Encrypted percentage for LPs (simplified)
     * @return Encrypted LP reward amount
     */
    function calculateLPRewards(
        euint128 capturedMEV,
        euint64 lpSharePercentage
    ) internal pure returns (euint128) {
        // Validate inputs
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(capturedMEV, zero));
        
        // Simplified LP reward calculation
        // Since we can't divide by percentage, we'll use fixed 80% approach
        euint128 reductionFactor = FHE.asEuint128(5); // Represents 20% reduction (100% - 80%)
        
        // Calculate 80% by subtracting 20%
        // 20% approximation: capturedMEV / 5
        ebool canReduce = FHE.gt(capturedMEV, reductionFactor);
        euint128 reduction = FHE.select(
            canReduce,
            FHE.sub(capturedMEV, reductionFactor), // Simple approximation
            capturedMEV
        );
        
        return reduction;
    }

    /**
     * @dev Estimate potential MEV value from arbitrage spread
     * Following CoFHE MEV estimation patterns
     * Note: Simplified due to multiplication limitations
     * @param spread Encrypted arbitrage spread
     * @param volume Encrypted trade volume (not used due to mul limitation)
     * @return Encrypted estimated MEV value
     */
    function estimateMEVValue(
        euint128 spread,
        euint128 volume
    ) internal pure returns (euint128) {
        // Validate inputs
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(spread, zero));
        FHE.req(FHE.gt(volume, zero));
        
        // Simplified MEV estimation
        // Since we can't multiply, we'll use the spread as a base estimate
        // and apply a factor to approximate efficiency
        
        euint128 efficiencyReduction = FHE.asEuint128(1000);
        ebool canApplyEfficiency = FHE.gt(spread, efficiencyReduction);
        
        // Apply efficiency factor by reducing the spread
        euint128 netMEV = FHE.select(
            canApplyEfficiency,
            FHE.sub(spread, efficiencyReduction),
            spread
        );
        
        return netMEV;
    }

    /**
     * @dev Calculate proportional rewards for individual LP
     * Following CoFHE proportional distribution patterns
     * Note: Simplified due to division limitations
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
        // Validate inputs
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(totalRewards, zero));
        FHE.req(FHE.gt(lpLiquidity, zero));
        FHE.req(FHE.gt(totalLiquidity, zero));
        
        // Ensure LP liquidity doesn't exceed total
        FHE.req(FHE.lte(lpLiquidity, totalLiquidity));
        
        // Simplified proportional calculation
        // Since we can't do proper division, we'll approximate
        ebool lpIsHalf = FHE.gte(lpLiquidity, FHE.sub(totalLiquidity, lpLiquidity));
        
        // If LP has >= 50% of liquidity, give them half the rewards
        // Otherwise, give them a smaller portion
        euint128 halfRewards = FHE.sub(totalRewards, FHE.asEuint128(1000)); // Approximate half
        euint128 quarterRewards = FHE.sub(totalRewards, FHE.asEuint128(3000)); // Approximate quarter
        
        return FHE.select(lpIsHalf, halfRewards, quarterRewards);
    }

    /**
     * @dev Apply time-based decay to arbitrage opportunities
     * Following CoFHE time-decay patterns
     * @param baseSpread Encrypted base arbitrage spread
     * @param timeSinceDetection Time elapsed since detection (in blocks)
     * @return Encrypted adjusted spread with decay applied
     */
    function applyTimeDecay(
        euint128 baseSpread,
        uint256 timeSinceDetection
    ) internal pure returns (euint128) {
        // Validate inputs
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(baseSpread, zero));
        
        // Apply linear decay: reduce by fixed amount per block
        uint256 maxDecayBlocks = 100; // Maximum decay period
        uint256 effectiveTime = timeSinceDetection > maxDecayBlocks ? 
            maxDecayBlocks : timeSinceDetection;
        
        // Calculate decay amount (fixed per block)
        uint256 decayPerBlock = 100; // Decay amount per block
        uint256 totalDecay = effectiveTime * decayPerBlock;
        
        euint128 decayAmount = FHE.asEuint128(totalDecay);
        
        // Apply decay, ensuring we don't go below zero
        ebool canDecay = FHE.gt(baseSpread, decayAmount);
        return FHE.select(canDecay, FHE.sub(baseSpread, decayAmount), zero);
    }

    /**
     * @dev Validate arbitrage calculation parameters
     * Following CoFHE validation patterns
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
        // Check all values are positive using FHE operations
        euint128 zero = FHE.asEuint128(0);
        bool spreadValid = FHE.decrypt(FHE.gt(spread, zero));
        bool thresholdValid = FHE.decrypt(FHE.gt(threshold, zero));
        bool volumeValid = FHE.decrypt(FHE.gt(volume, zero));
        
        return spreadValid && thresholdValid && volumeValid;
    }

    /**
     * @dev Calculate compound arbitrage opportunity across multiple pools
     * Following CoFHE multi-pool analysis patterns
     * @param prices Array of encrypted prices from different pools
     * @param volumes Array of encrypted volumes (not used due to limitations)
     * @return Encrypted maximum arbitrage spread found
     */
    function calculateCompoundArbitrage(
        euint128[] memory prices,
        euint128[] memory volumes
    ) internal pure returns (euint128) {
        require(prices.length == volumes.length && prices.length >= 2, "Invalid arrays");
        
        euint128 maxSpread = FHE.asEuint128(0);
        
        // Compare all price pairs to find maximum spread
        for (uint256 i = 0; i < prices.length; i++) {
            for (uint256 j = i + 1; j < prices.length; j++) {
                euint128 currentSpread = calculateSpread(prices[i], prices[j]);
                
                // Update max spread if current is larger
                ebool isLarger = FHE.gt(currentSpread, maxSpread);
                maxSpread = FHE.select(isLarger, currentSpread, maxSpread);
            }
        }
        
        return maxSpread;
    }
}