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
 * Following CoFHE interface patterns from Fhenix documentation
 */
interface IArbitrageProtection {
    
    // Events following CoFHE event patterns with encrypted data
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

    // Core Functions following CoFHE access patterns
    
    /**
     * @dev Get encrypted MEV captured for a pool with permit-based access
     * @param poolId Pool identifier
     * @param publicKey User's public key for sealing encrypted data
     * @return Sealed encrypted MEV data following CoFHE sealing patterns
     */
    function getEncryptedMEVCaptured(
        PoolId poolId,
        bytes32 publicKey
    ) external view returns (bytes memory);

    /**
     * @dev Get encrypted LP rewards for an address with permit-based access
     * @param poolId Pool identifier
     * @param lp LP address
     * @param publicKey User's public key for sealing encrypted data
     * @return Sealed encrypted reward data following CoFHE access patterns
     */
    function getEncryptedLPRewards(
        PoolId poolId,
        address lp,
        bytes32 publicKey
    ) external view returns (bytes memory);

    /**
     * @dev Check if protection is currently active for a pool
     * @param poolId Pool identifier
     * @return True if protection is active (decrypted for public access)
     */
    function isProtectionActive(PoolId poolId) external view returns (bool);

    /**
     * @dev Get encrypted protection threshold for a pool
     * @param poolId Pool identifier
     * @return Encrypted threshold value (encrypted type exposed for authorized calculations)
     */
    function getEncryptedThreshold(PoolId poolId) external view returns (euint128);

    /**
     * @dev Update protection threshold with encrypted input
     * @param poolId Pool identifier
     * @param newThreshold New encrypted threshold following CoFHE input patterns
     */
    function updateProtectionThreshold(
        PoolId poolId,
        euint128 newThreshold
    ) external;

    /**
     * @dev Grant access permissions for encrypted data
     * @param user User address to grant access
     * @param accessType Type of access to grant following CoFHE permission patterns
     */
    function grantAccess(address user, string calldata accessType) external;

    // Advanced CoFHE Functions
    
    /**
     * @dev Create permit for encrypted data access following CoFHE permit patterns
     * @param user User to create permit for
     * @param publicKey User's public key for encrypted data access
     */
    function createPermit(address user, bytes32 publicKey) external;

    /**
     * @dev Get sealed encrypted data following CoFHE data access patterns
     * @param poolId Pool identifier
     * @param dataType Type of encrypted data to retrieve
     * @return Sealed encrypted data for the requesting user
     */
    function getSealedData(
        PoolId poolId,
        string calldata dataType
    ) external view returns (bytes memory);

    // Emergency Functions following CoFHE emergency patterns
    
    /**
     * @dev Emergency pause protection for a pool
     * @param poolId Pool to pause protection for
     */
    function emergencyPause(PoolId poolId) external;
}