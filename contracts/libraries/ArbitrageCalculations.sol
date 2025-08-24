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
    
    // FHE Constants following CoFHE best practices
    euint128 private constant ZERO = FHE.asEuint128(0);
    euint128 private constant BASIS_POINTS_DIVISOR = FHE.asEuint128(10000);
    euint128 private constant PERCENTAGE_MULTIPLIER = FHE.asEuint128(100);
    
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
        FHE.req(FHE.gt(priceA, ZERO));
        FHE.req(FHE.gt(priceB, ZERO));
        
        // Calculate absolute difference using FHE conditional operations
        ebool aGreaterThanB = FHE.gt(priceA, priceB);
        euint128 diff1 = FHE.sub(priceA, priceB);
        euint128 diff2 = FHE.sub(priceB, priceA);
        
        // Return absolute difference using FHE select operation
        return FHE.select(aGreaterThanB, diff1, diff2);
    }

    /**
     * @dev Calculate percentage-based spread for better arbitrage analysis
     * Following CoFHE percentage calculation patterns
     * @param priceA Encrypted price from pool A
     * @param priceB Encrypted price from pool B
     * @return Encrypted percentage spread in basis points
     */
    function calculatePercentageSpread(
        euint128 priceA,
        euint128 priceB
    ) internal pure returns (euint128) {
        // Get absolute spread
        euint128 absoluteSpread = calculateSpread(priceA, priceB);
        
        // Calculate average price for percentage calculation
        euint128 averagePrice = FHE.div(FHE.add(priceA, priceB), FHE.asEuint128(2));
        
        // Validate average price is not zero
        FHE.req(FHE.gt(averagePrice, ZERO));
        
        // Calculate percentage: (spread / average) * 10000 (basis points)
        euint128 percentage = FHE.div(
            FHE.mul(absoluteSpread, BASIS_POINTS_DIVISOR),
            averagePrice
        );
        
        return percentage;
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
        FHE.req(FHE.gt(spread, ZERO));
        FHE.req(FHE.gt(threshold, ZERO));
        
        // Compare spread against threshold using FHE comparison
        return FHE.gt(spread, threshold);
    }

    /**
     * @dev Advanced arbitrage opportunity detection with multiple conditions
     * Following CoFHE multi-condition analysis patterns
     * @param spread Encrypted arbitrage spread
     * @param threshold Encrypted minimum threshold
     * @param volume Encrypted trade volume
     * @param minVolume Encrypted minimum volume requirement
     * @return True if all arbitrage conditions are met
     */
    function hasAdvancedArbitrageOpportunity(
        euint128 spread,
        euint128 threshold,
        euint128 volume,
        euint128 minVolume
    ) internal pure returns (ebool) {
        // Check basic arbitrage opportunity
        ebool spreadExceedsThreshold = hasArbitrageOpportunity(spread, threshold);
        
        // Check volume requirement
        ebool volumeAdequate = FHE.gt(volume, minVolume);
        
        // Combine conditions using FHE boolean operations
        return FHE.and(spreadExceedsThreshold, volumeAdequate);
    }

    /**
     * @dev Calculate optimal protection fee based on spread and volume
     * Following CoFHE dynamic fee calculation patterns
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
        // Validate inputs
        FHE.req(FHE.gt(spread, ZERO));
        FHE.req(FHE.gt(volume, ZERO));
        FHE.req(FHE.gt(maxFee, ZERO));
        
        // Base fee: 0.1% (10 basis points)
        euint128 baseFee = FHE.asEuint128(10);
        
        // Dynamic component based on spread size
        // Fee increases with spread: spread / volume * 10000 (basis points)
        euint128 dynamicComponent = FHE.div(
            FHE.mul(spread, BASIS_POINTS_DIVISOR),
            volume
        );
        
        // Total fee = base fee + dynamic component
        euint128 totalFee = FHE.add(baseFee, dynamicComponent);
        
        // Cap at maximum fee using FHE conditional
        ebool exceedsMax = FHE.gt(totalFee, maxFee);
        return FHE.select(exceedsMax, maxFee, totalFee);
    }

    /**
     * @dev Calculate tiered protection fee with multiple spread ranges
     * Following CoFHE tiered calculation patterns
     * @param spread Encrypted arbitrage spread
     * @param volume Encrypted swap volume
     * @return Encrypted tiered protection fee
     */
    function calculateTieredProtectionFee(
        euint128 spread,
        euint128 volume
    ) internal pure returns (euint128) {
        // Define spread tiers in basis points
        euint128 lowTier = FHE.asEuint128(50);    // 0.5%
        euint128 midTier = FHE.asEuint128(100);   // 1.0%
        euint128 highTier = FHE.asEuint128(200);  // 2.0%
        
        // Calculate percentage spread
        euint128 percentageSpread = FHE.div(
            FHE.mul(spread, BASIS_POINTS_DIVISOR),
            volume
        );
        
        // Determine fee rate based on spread tier
        ebool isLowTier = FHE.lt(percentageSpread, lowTier);
        ebool isMidTier = FHE.and(
            FHE.gte(percentageSpread, lowTier),
            FHE.lt(percentageSpread, midTier)
        );
        
        // Fee rates: 0.1%, 0.2%, 0.5%
        euint128 lowFeeRate = FHE.asEuint128(10);   // 0.1%
        euint128 midFeeRate = FHE.asEuint128(20);   // 0.2%
        euint128 highFeeRate = FHE.asEuint128(50);  // 0.5%
        
        // Select appropriate fee rate
        euint128 feeRate = FHE.select(
            isLowTier,
            lowFeeRate,
            FHE.select(isMidTier, midFeeRate, highFeeRate)
        );
        
        // Calculate final fee: (volume * feeRate) / 10000
        return FHE.div(FHE.mul(volume, feeRate), BASIS_POINTS_DIVISOR);
    }

    /**
     * @dev Calculate LP reward distribution from captured MEV
     * Following CoFHE reward distribution patterns
     * @param capturedMEV Encrypted MEV value captured
     * @param lpSharePercentage Encrypted percentage for LPs (in basis points)
     * @return Encrypted LP reward amount
     */
    function calculateLPRewards(
        euint128 capturedMEV,
        euint64 lpSharePercentage
    ) internal pure returns (euint128) {
        // Validate inputs
        FHE.req(FHE.gt(capturedMEV, ZERO));
        
        // Convert percentage to euint128 for calculation
        euint128 sharePercent = FHE.asEuint128(lpSharePercentage);
        
        // Validate share percentage is reasonable (0-100%)
        FHE.req(FHE.lte(sharePercent, FHE.asEuint128(10000))); // Max 100%
        
        // Calculate LP share: (capturedMEV * lpSharePercentage) / 10000
        euint128 lpRewards = FHE.div(
            FHE.mul(capturedMEV, sharePercent),
            BASIS_POINTS_DIVISOR
        );
        
        return lpRewards;
    }

    /**
     * @dev Estimate potential MEV value from arbitrage spread
     * Following CoFHE MEV estimation patterns
     * @param spread Encrypted arbitrage spread
     * @param volume Encrypted trade volume
     * @return Encrypted estimated MEV value
     */
    function estimateMEVValue(
        euint128 spread,
        euint128 volume
    ) internal pure returns (euint128) {
        // Validate inputs
        FHE.req(FHE.gt(spread, ZERO));
        FHE.req(FHE.gt(volume, ZERO));
        
        // MEV estimation with efficiency factor (80% - accounting for gas, slippage)
        euint128 efficiencyFactor = FHE.asEuint128(8000); // 80%
        
        // Calculate gross MEV: spread represents the arbitrage opportunity
        euint128 grossMEV = FHE.mul(spread, volume);
        
        // Apply efficiency factor: grossMEV * 0.8
        euint128 netMEV = FHE.div(
            FHE.mul(grossMEV, efficiencyFactor),
            BASIS_POINTS_DIVISOR
        );
        
        return netMEV;
    }

    /**
     * @dev Calculate proportional rewards for individual LP
     * Following CoFHE proportional distribution patterns
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
        FHE.req(FHE.gt(totalRewards, ZERO));
        FHE.req(FHE.gt(lpLiquidity, ZERO));
        FHE.req(FHE.gt(totalLiquidity, ZERO));
        
        // Ensure LP liquidity doesn't exceed total
        FHE.req(FHE.lte(lpLiquidity, totalLiquidity));
        
        // Proportional calculation: (totalRewards * lpLiquidity) / totalLiquidity
        euint128 numerator = FHE.mul(totalRewards, lpLiquidity);
        return FHE.div(numerator, totalLiquidity);
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
        FHE.req(FHE.gt(baseSpread, ZERO));
        
        // Apply linear decay: 1% per block (for simplicity in FHE)
        uint256 decayRate = 9900; // 99% retention per block
        uint256 maxDecayBlocks = 100; // Maximum decay period
        
        // Cap time for reasonable decay calculation
        uint256 effectiveTime = timeSinceDetection > maxDecayBlocks ? 
            maxDecayBlocks : timeSinceDetection;
        
        // Calculate decay multiplier
        uint256 decayMultiplier = decayRate;
        for (uint256 i = 1; i < effectiveTime; i++) {
            decayMultiplier = (decayMultiplier * decayRate) / 10000;
        }
        
        // Apply decay to spread
        euint128 decayFactor = FHE.asEuint128(decayMultiplier);
        return FHE.div(
            FHE.mul(baseSpread, decayFactor),
            BASIS_POINTS_DIVISOR
        );
    }

    /**
     * @dev Calculate optimal batch size for MEV protection
     * Following CoFHE optimization patterns
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
        // Validate inputs
        FHE.req(FHE.gt(totalVolume, ZERO));
        FHE.req(FHE.gt(protectionBudget, ZERO));
        
        // Estimate gas cost per protection transaction
        uint256 estimatedGasPerTx = 200000;
        uint256 costPerTx = gasPrice * estimatedGasPerTx;
        
        // Decrypt budget for calculation (in production, this would use FHE throughout)
        uint256 budget = FHE.decrypt(protectionBudget);
        uint256 maxTransactions = budget / costPerTx;
        
        // Ensure reasonable batch size (1-10 transactions)
        if (maxTransactions == 0) return 1;
        if (maxTransactions > 10) return 10;
        
        return maxTransactions;
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
        bool spreadValid = FHE.decrypt(FHE.gt(spread, ZERO));
        bool thresholdValid = FHE.decrypt(FHE.gt(threshold, ZERO));
        bool volumeValid = FHE.decrypt(FHE.gt(volume, ZERO));
        
        return spreadValid && thresholdValid && volumeValid;
    }

    /**
     * @dev Calculate compound arbitrage opportunity across multiple pools
     * Following CoFHE multi-pool analysis patterns
     * @param prices Array of encrypted prices from different pools
     * @param volumes Array of encrypted volumes
     * @return Encrypted maximum arbitrage spread found
     */
    function calculateCompoundArbitrage(
        euint128[] memory prices,
        euint128[] memory volumes
    ) internal pure returns (euint128) {
        require(prices.length == volumes.length && prices.length >= 2, "Invalid arrays");
        
        euint128 maxSpread = ZERO;
        
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