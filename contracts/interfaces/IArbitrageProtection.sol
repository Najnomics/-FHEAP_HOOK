// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    euint128,
    euint64,
    ebool
} from "@fhenixprotocol/contracts/FHE.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title IArbitrageProtection
 * @dev Interface for FHE-based arbitrage protection functionality
 */
interface IArbitrageProtection {
    
    // Events
    event ArbitrageDetected(
        PoolId indexed poolId,
        bytes32 encryptedSpread,
        uint256 timestamp
    );
    
    event ProtectionTriggered(
        PoolId indexed poolId,
        bytes32 encryptedFee,
        bytes32 encryptedMEVCaptured,
        uint256 timestamp
    );
    
    event LPRewardsDistributed(
        PoolId indexed poolId,
        bytes32 encryptedTotalRewards,
        uint256 recipientCount,
        uint256 timestamp
    );

    // Core Functions
    
    /**
     * @dev Get encrypted MEV captured for a pool
     * @param poolId Pool identifier
     * @param publicKey User's public key for sealing
     * @return Sealed encrypted MEV data
     */
    function getEncryptedMEVCaptured(
        PoolId poolId,
        bytes32 publicKey
    ) external view returns (bytes memory);

    /**
     * @dev Get encrypted LP rewards for an address
     * @param poolId Pool identifier
     * @param lp LP address
     * @param publicKey User's public key for sealing
     * @return Sealed encrypted reward data
     */
    function getEncryptedLPRewards(
        PoolId poolId,
        address lp,
        bytes32 publicKey
    ) external view returns (bytes memory);

    /**
     * @dev Check if protection is currently active for a pool
     * @param poolId Pool identifier
     * @return True if protection is active
     */
    function isProtectionActive(PoolId poolId) external view returns (bool);

    /**
     * @dev Get protection threshold for a pool
     * @param poolId Pool identifier
     * @return Encrypted threshold value
     */
    function getEncryptedThreshold(PoolId poolId) external view returns (euint128);

    /**
     * @dev Update protection threshold for a pool
     * @param poolId Pool identifier
     * @param newThreshold New encrypted threshold
     */
    function updateProtectionThreshold(
        PoolId poolId,
        euint128 newThreshold
    ) external;

    /**
     * @dev Grant access permissions for encrypted data
     * @param user User address to grant access
     * @param accessType Type of access to grant
     */
    function grantAccess(address user, string calldata accessType) external;
}