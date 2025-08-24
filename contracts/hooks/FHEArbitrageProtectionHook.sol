// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

// Fhenix FHE imports - following CoFHE patterns
import {
    FHE,
    inEuint128,
    euint128,
    inEuint64,
    euint64,
    inEbool,
    ebool
} from "@fhenixprotocol/contracts/FHE.sol";
import {PermissionedV2} from "@fhenixprotocol/contracts/access/PermissionedV2.sol";

import {ArbitrageCalculations} from "../libraries/ArbitrageCalculations.sol";
import {FHEPermissions} from "../libraries/FHEPermissions.sol";
import {PriceAggregator} from "../libraries/PriceAggregator.sol";
import {IArbitrageProtection} from "./interfaces/IArbitrageProtection.sol";

/**
 * @title FHEArbitrageProtectionHook - FHEAP Main Hook Contract
 * @dev Uniswap v4 Hook that uses Fully Homomorphic Encryption to detect and prevent 
 *      cross-pool arbitrage MEV extraction, protecting liquidity providers
 * 
 * Following CoFHE patterns from Fhenix documentation and cofhe-scaffold-eth template
 */
contract FHEArbitrageProtectionHook is BaseHook, IArbitrageProtection, PermissionedV2 {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using ArbitrageCalculations for *;
    using FHEPermissions for *;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    // Custom errors following Fhenix patterns
    error NotAuthorized();
    error InvalidThreshold();
    error ProtectionAlreadyActive();
    error InsufficientBalance();
    error StalePrice();
    error InvalidFHEData();

    // Events with encrypted data (following CoFHE event patterns)
    event ArbitrageDetected(
        PoolId indexed poolId,
        bytes encryptedSpread,
        uint256 timestamp
    );
    
    event ProtectionTriggered(
        PoolId indexed poolId,
        bytes encryptedFee,
        bytes encryptedMEVCaptured,
        uint256 timestamp
    );
    
    event LPRewardsDistributed(
        PoolId indexed poolId,
        bytes encryptedTotalRewards,
        uint256 recipientCount,
        uint256 timestamp
    );

    event ThresholdUpdated(
        PoolId indexed poolId,
        bytes encryptedNewThreshold,
        uint256 timestamp
    );

    // FHE Constants following CoFHE best practices
    euint128 private constant MINIMUM_ARBITRAGE_THRESHOLD = FHE.asEuint128(1000); // 0.1% in basis points
    euint128 private constant MAXIMUM_PROTECTION_FEE = FHE.asEuint128(30000); // 3% in basis points
    euint64 private constant LP_SHARE_PERCENTAGE = FHE.asEuint64(8000); // 80% to LPs
    euint128 private constant ZERO_ENCRYPTED = FHE.asEuint128(0);

    // State variables with FHE encryption
    mapping(PoolId => euint128) private encryptedThresholds;
    mapping(PoolId => euint128) private encryptedTotalMEVCaptured;
    mapping(PoolId => euint128) private encryptedTotalLPRewards;
    mapping(PoolId => mapping(address => euint128)) private encryptedLPRewards;
    mapping(PoolId => ebool) private protectionActive;
    mapping(PoolId => uint256) private lastProtectionBlock;
    
    // Price monitoring with CoFHE integration
    PriceAggregator public immutable priceAggregator;
    FHEPermissions public immutable permissions;
    
    // Protection cooldown (blocks) - following Fhenix recommended patterns
    uint256 public constant PROTECTION_COOLDOWN = 5; // 5 blocks ~1 minute
    uint256 public constant MAX_PRICE_AGE = 300; // 5 minutes in seconds

    constructor(
        IPoolManager _poolManager,
        address _priceAggregator,
        address _permissions
    ) BaseHook(_poolManager) {
        priceAggregator = PriceAggregator(_priceAggregator);
        permissions = FHEPermissions(_permissions);
    }

    /**
     * @dev Define which hook functions this contract implements
     * Following Uniswap v4 hook patterns with FHE integration
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @dev Initialize protection for a new pool with encrypted parameters
     * Following CoFHE initialization patterns
     */
    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24
    ) external override onlyPoolManager returns (bytes4) {
        PoolId poolId = key.toId();
        
        // Initialize encrypted state following FHE best practices
        encryptedThresholds[poolId] = MINIMUM_ARBITRAGE_THRESHOLD;
        protectionActive[poolId] = FHE.asEbool(false);
        encryptedTotalMEVCaptured[poolId] = ZERO_ENCRYPTED;
        encryptedTotalLPRewards[poolId] = ZERO_ENCRYPTED;
        
        return FHEArbitrageProtectionHook.afterInitialize.selector;
    }

    /**
     * @dev Analyze arbitrage risk before swap execution using FHE operations
     * Core FHE arbitrage detection following CoFHE patterns
     */
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        
        // Check protection cooldown
        if (block.number - lastProtectionBlock[poolId] < PROTECTION_COOLDOWN) {
            return (FHEArbitrageProtectionHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Analyze encrypted arbitrage risk using FHE operations
        _analyzeArbitrageRisk(key, params);
        
        return (FHEArbitrageProtectionHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev Distribute captured MEV to LPs after swap using encrypted calculations
     * Following CoFHE reward distribution patterns
     */
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        PoolId poolId = key.toId();
        
        // Check if protection was triggered (encrypted boolean check)
        ebool wasTriggered = protectionActive[poolId];
        
        // If protection was triggered, distribute MEV using FHE operations
        if (FHE.decrypt(wasTriggered)) {
            _distributeMEVProtection(key);
            
            // Reset protection status (encrypted boolean)
            protectionActive[poolId] = FHE.asEbool(false);
        }
        
        return (FHEArbitrageProtectionHook.afterSwap.selector, 0);
    }

    /**
     * @dev Analyze arbitrage risk using encrypted price data from multiple DEXs
     * Core FHE computation following CoFHE calculation patterns
     */
    function _analyzeArbitrageRisk(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) internal {
        PoolId poolId = key.toId();
        
        // Get encrypted current price using FHE operations
        euint128 currentPrice = _getCurrentEncryptedPrice(key);
        
        // Get encrypted cross-DEX prices for comparison
        euint128[] memory crossDEXPrices = priceAggregator.getEncryptedCrossDEXPrices(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1)
        );
        
        // Analyze each price comparison using FHE operations
        for (uint256 i = 0; i < crossDEXPrices.length; i++) {
            // Calculate encrypted spread using FHE subtraction
            euint128 encryptedSpread = ArbitrageCalculations.calculateSpread(
                currentPrice,
                crossDEXPrices[i]
            );
            
            // Check arbitrage opportunity using encrypted comparison
            ebool hasArbitrageOpportunity = ArbitrageCalculations.hasArbitrageOpportunity(
                encryptedSpread,
                encryptedThresholds[poolId]
            );
            
            // Trigger protection if opportunity detected (following CoFHE patterns)
            if (FHE.decrypt(hasArbitrageOpportunity)) {
                _triggerProtection(key, params, encryptedSpread);
                
                // Emit event with encrypted data
                emit ArbitrageDetected(
                    poolId,
                    _sealData(encryptedSpread),
                    block.timestamp
                );
                break;
            }
        }
    }

    /**
     * @dev Trigger arbitrage protection mechanism with encrypted calculations
     * Following CoFHE protection activation patterns
     */
    function _triggerProtection(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        euint128 encryptedSpread
    ) internal {
        PoolId poolId = key.toId();
        
        // Calculate swap amount using FHE operations
        euint128 swapAmount = FHE.asEuint128(uint128(params.amountSpecified < 0 ? 
            uint256(-params.amountSpecified) : uint256(params.amountSpecified)));
        
        // Calculate encrypted protection fee using FHE operations
        euint128 encryptedProtectionFee = ArbitrageCalculations.calculateProtectionFee(
            encryptedSpread,
            swapAmount,
            MAXIMUM_PROTECTION_FEE
        );
        
        // Estimate MEV value using encrypted calculations
        euint128 encryptedMEVCaptured = ArbitrageCalculations.estimateMEVValue(
            encryptedSpread,
            swapAmount
        );
        
        // Activate protection (encrypted boolean)
        protectionActive[poolId] = FHE.asEbool(true);
        lastProtectionBlock[poolId] = block.number;
        
        // Update totals using FHE addition
        encryptedTotalMEVCaptured[poolId] = FHE.add(
            encryptedTotalMEVCaptured[poolId],
            encryptedMEVCaptured
        );
        
        // Emit protection event with encrypted data following CoFHE patterns
        emit ProtectionTriggered(
            poolId,
            _sealData(encryptedProtectionFee),
            _sealData(encryptedMEVCaptured),
            block.timestamp
        );
    }

    /**
     * @dev Distribute captured MEV to liquidity providers using encrypted operations
     * Following CoFHE reward distribution patterns
     */
    function _distributeMEVProtection(PoolKey calldata key) internal {
        PoolId poolId = key.toId();
        
        // Get recent MEV captured using encrypted operations
        euint128 recentMEVCaptured = FHE.asEuint128(10000); // Placeholder - would be calculated from protection event
        
        // Calculate LP share using encrypted percentage calculation
        euint128 lpRewardTotal = ArbitrageCalculations.calculateLPRewards(
            recentMEVCaptured,
            LP_SHARE_PERCENTAGE
        );
        
        // Update total LP rewards using FHE addition
        encryptedTotalLPRewards[poolId] = FHE.add(
            encryptedTotalLPRewards[poolId],
            lpRewardTotal
        );
        
        // In production: distribute proportionally to LPs based on their liquidity
        // For now, emit event with encrypted total following CoFHE patterns
        emit LPRewardsDistributed(
            poolId,
            _sealData(lpRewardTotal),
            1, // Placeholder recipient count
            block.timestamp
        );
    }

    /**
     * @dev Get current encrypted price for the pool using FHE operations
     * Following CoFHE price encryption patterns
     */
    function _getCurrentEncryptedPrice(PoolKey calldata key) internal view returns (euint128) {
        // Get current price from pool state
        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(key.toId());
        
        // Convert to price and encrypt using FHE
        uint256 price = _sqrtPriceX96ToPrice(sqrtPriceX96);
        return FHE.asEuint128(price);
    }

    /**
     * @dev Convert sqrt price to regular price (optimized for FHE)
     */
    function _sqrtPriceX96ToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        // Simplified conversion optimized for FHE operations
        return (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
    }

    /**
     * @dev Seal encrypted data for events (simplified sealing)
     */
    function _sealData(euint128 data) internal pure returns (bytes memory) {
        // Simplified sealing for events - in production would use proper public key
        return abi.encode(FHE.decrypt(data));
    }

    // ===== IArbitrageProtection IMPLEMENTATION =====

    /**
     * @dev Get encrypted MEV captured for a pool with permit-based access
     * Following CoFHE data access patterns
     */
    function getEncryptedMEVCaptured(
        PoolId poolId,
        bytes32 publicKey
    ) external view override returns (bytes memory) {
        require(permissions.hasAccess(msg.sender, "mev_data"), "Not authorized");
        return abi.encode(encryptedTotalMEVCaptured[poolId]);
    }

    /**
     * @dev Get encrypted LP rewards with permit-based access
     * Following CoFHE permission patterns
     */
    function getEncryptedLPRewards(
        PoolId poolId,
        address lp,
        bytes32 publicKey
    ) external view override returns (bytes memory) {
        require(permissions.hasAccess(lp, "lp_rewards") || msg.sender == lp, "Not authorized");
        return abi.encode(encryptedLPRewards[poolId][lp]);
    }

    /**
     * @dev Check if protection is currently active (decrypted for public view)
     */
    function isProtectionActive(PoolId poolId) external view override returns (bool) {
        return FHE.decrypt(protectionActive[poolId]);
    }

    /**
     * @dev Get encrypted protection threshold for a pool
     */
    function getEncryptedThreshold(PoolId poolId) external view override returns (euint128) {
        return encryptedThresholds[poolId];
    }

    /**
     * @dev Update protection threshold with encrypted input
     * Following CoFHE parameter update patterns
     */
    function updateProtectionThreshold(
        PoolId poolId,
        euint128 newThreshold
    ) external override {
        require(permissions.hasAccess(msg.sender, "admin"), "Not authorized");
        
        // Validate threshold using FHE operations
        FHE.req(FHE.gt(newThreshold, ZERO_ENCRYPTED));
        FHE.req(FHE.lt(newThreshold, FHE.asEuint128(100000))); // Max 10%
        
        encryptedThresholds[poolId] = newThreshold;
        
        // Emit event with encrypted threshold following CoFHE patterns
        emit ThresholdUpdated(
            poolId,
            _sealData(newThreshold),
            block.timestamp
        );
    }

    /**
     * @dev Grant access permissions for encrypted data
     * Following CoFHE access control patterns
     */
    function grantAccess(address user, string calldata accessType) external override {
        require(permissions.hasAccess(msg.sender, "admin"), "Not authorized");
        permissions.grantAccess(user, accessType);
    }

    /**
     * @dev Create permit for encrypted data access following CoFHE patterns
     */
    function createPermit(address user, bytes32 publicKey) external {
        require(permissions.hasAccess(msg.sender, "admin"), "Not authorized");
        // Implementation would create proper permit for encrypted data access
    }

    /**
     * @dev Get sealed encrypted data for user following CoFHE sealing patterns
     */
    function getSealedData(
        PoolId poolId,
        string calldata dataType
    ) external view returns (bytes memory) {
        bytes32 dataTypeHash = keccak256(bytes(dataType));
        
        if (dataTypeHash == keccak256("mev_captured")) {
            require(permissions.hasAccess(msg.sender, "mev_data"), "Not authorized");
            return abi.encode(encryptedTotalMEVCaptured[poolId]);
        } else if (dataTypeHash == keccak256("lp_rewards")) {
            require(permissions.hasAccess(msg.sender, "lp_rewards"), "Not authorized");
            return abi.encode(encryptedLPRewards[poolId][msg.sender]);
        } else if (dataTypeHash == keccak256("threshold")) {
            return abi.encode(encryptedThresholds[poolId]);
        }
        
        revert("Invalid data type");
    }

    /**
     * @dev Emergency functions for admin following CoFHE emergency patterns
     */
    function emergencyPause(PoolId poolId) external {
        require(permissions.hasAccess(msg.sender, "admin"), "Not authorized");
        protectionActive[poolId] = FHE.asEbool(false);
        lastProtectionBlock[poolId] = block.number + PROTECTION_COOLDOWN;
    }

    function emergencyUpdateThreshold(PoolId poolId, inEuint128 calldata newThreshold) external {
        require(permissions.hasAccess(msg.sender, "admin"), "Not authorized");
        euint128 threshold = FHE.asEuint128(newThreshold);
        encryptedThresholds[poolId] = threshold;
    }
}