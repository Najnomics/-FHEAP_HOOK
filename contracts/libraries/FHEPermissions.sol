// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    FHE,
    euint128,
    ebool
} from "@fhenixprotocol/contracts/FHE.sol";
import {Permit} from "@fhenixprotocol/contracts/access/Permit.sol";

/**
 * @title FHEPermissions
 * @dev Access control and permission management for encrypted data
 * Following CoFHE permission patterns from Fhenix documentation
 * Purpose: Manages who can access encrypted arbitrage data and LP rewards
 */
contract FHEPermissions {
    using Permit for Permit.Permission;

    // Events following CoFHE permission event patterns
    event AccessGranted(
        address indexed user, 
        bytes32 indexed accessType, 
        uint256 timestamp
    );
    
    event AccessRevoked(
        address indexed user, 
        bytes32 indexed accessType, 
        uint256 timestamp
    );
    
    event PermitCreated(
        address indexed user, 
        bytes32 indexed dataType, 
        bytes32 publicKey,
        uint256 timestamp
    );

    event PublicKeyRegistered(
        address indexed user,
        bytes32 publicKey,
        uint256 timestamp
    );

    event EmergencyAccessRevoked(
        address indexed user,
        address indexed revokedBy,
        uint256 timestamp
    );

    // Access types following CoFHE access control patterns
    bytes32 public constant ADMIN_ACCESS = keccak256("admin");
    bytes32 public constant LP_REWARDS_ACCESS = keccak256("lp_rewards");
    bytes32 public constant MEV_DATA_ACCESS = keccak256("mev_data");
    bytes32 public constant ARBITRAGE_DATA_ACCESS = keccak256("arbitrage_data");
    bytes32 public constant PRICE_DATA_ACCESS = keccak256("price_data");
    bytes32 public constant THRESHOLD_ACCESS = keccak256("threshold_access");

    // State variables following CoFHE state management patterns
    mapping(address => mapping(bytes32 => bool)) private userAccess;
    mapping(address => Permit.Permission) private userPermits;
    mapping(address => bytes32) private userPublicKeys;
    mapping(bytes32 => mapping(address => bool)) private dataTypeAccess;
    mapping(address => uint256) private permissionTimestamps;
    
    // Global system settings
    address public immutable admin;
    bytes32 private globalPublicKey;
    bool public emergencyPaused;
    
    // Access control modifiers following CoFHE patterns
    modifier onlyAdmin() {
        require(msg.sender == admin || userAccess[msg.sender][ADMIN_ACCESS], "Not authorized");
        _;
    }

    modifier notPaused() {
        require(!emergencyPaused, "System paused");
        _;
    }

    modifier validPublicKey(bytes32 publicKey) {
        require(publicKey != bytes32(0), "Invalid public key");
        _;
    }

    constructor() {
        admin = msg.sender;
        
        // Grant admin full access following CoFHE admin setup patterns
        userAccess[admin][ADMIN_ACCESS] = true;
        userAccess[admin][LP_REWARDS_ACCESS] = true;
        userAccess[admin][MEV_DATA_ACCESS] = true;
        userAccess[admin][ARBITRAGE_DATA_ACCESS] = true;
        userAccess[admin][PRICE_DATA_ACCESS] = true;
        userAccess[admin][THRESHOLD_ACCESS] = true;
        
        permissionTimestamps[admin] = block.timestamp;
        
        // Set global public key for system-wide encrypted data
        globalPublicKey = keccak256(abi.encodePacked(admin, block.timestamp, "FHEAP_GLOBAL"));
    }

    /**
     * @dev Grant access to LP for viewing encrypted rewards
     * Following CoFHE LP access patterns
     * @param lp LP address to grant access
     * @param publicKey LP's public key for encryption
     */
    function grantLPAccess(
        address lp, 
        bytes32 publicKey
    ) external onlyAdmin notPaused validPublicKey(publicKey) {
        // Grant LP rewards access
        userAccess[lp][LP_REWARDS_ACCESS] = true;
        userPublicKeys[lp] = publicKey;
        permissionTimestamps[lp] = block.timestamp;
        
        // Create permit for encrypted data access
        userPermits[lp] = Permit.Permission({
            issuer: lp,
            permitted: address(this),
            publicKey: publicKey
        });
        
        emit AccessGranted(lp, LP_REWARDS_ACCESS, block.timestamp);
        emit PublicKeyRegistered(lp, publicKey, block.timestamp);
    }

    /**
     * @dev Grant general access permissions following CoFHE access patterns
     * @param user User address
     * @param accessType Type of access to grant
     */
    function grantAccess(
        address user, 
        string calldata accessType
    ) external onlyAdmin notPaused {
        bytes32 accessHash = keccak256(bytes(accessType));
        
        // Validate access type
        require(_isValidAccessType(accessHash), "Invalid access type");
        
        userAccess[user][accessHash] = true;
        permissionTimestamps[user] = block.timestamp;
        
        emit AccessGranted(user, accessHash, block.timestamp);
    }

    /**
     * @dev Grant batch access to multiple users following CoFHE batch patterns
     * @param users Array of user addresses
     * @param accessType Type of access to grant
     */
    function batchGrantAccess(
        address[] calldata users,
        string calldata accessType
    ) external onlyAdmin notPaused {
        bytes32 accessHash = keccak256(bytes(accessType));
        require(_isValidAccessType(accessHash), "Invalid access type");
        
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                userAccess[users[i]][accessHash] = true;
                permissionTimestamps[users[i]] = block.timestamp;
                emit AccessGranted(users[i], accessHash, block.timestamp);
            }
        }
    }

    /**
     * @dev Revoke access permissions following CoFHE revocation patterns
     * @param user User address
     * @param accessType Type of access to revoke
     */
    function revokeAccess(
        address user, 
        string calldata accessType
    ) external onlyAdmin {
        bytes32 accessHash = keccak256(bytes(accessType));
        userAccess[user][accessHash] = false;
        
        // Clear public key if revoking LP access
        if (accessHash == LP_REWARDS_ACCESS) {
            userPublicKeys[user] = bytes32(0);
        }
        
        emit AccessRevoked(user, accessHash, block.timestamp);
    }

    /**
     * @dev Create permit for encrypted data access following CoFHE permit patterns
     * @param user User requesting access
     * @param dataType Type of encrypted data
     * @return Permission struct for data access
     */
    function createDataPermit(
        address user,
        bytes32 dataType
    ) external onlyAdmin notPaused returns (Permit.Permission memory) {
        require(hasAccess(user, dataType), "Access denied");
        require(userPublicKeys[user] != bytes32(0), "No public key registered");
        
        Permit.Permission memory permission = Permit.Permission({
            issuer: user,
            permitted: address(this),
            publicKey: userPublicKeys[user]
        });
        
        userPermits[user] = permission;
        
        emit PermitCreated(user, dataType, userPublicKeys[user], block.timestamp);
        return permission;
    }

    /**
     * @dev Seal encrypted data for specific user following CoFHE sealing patterns
     * @param data Encrypted data to seal
     * @param user Target user address
     * @return Sealed data bytes
     */
    function sealForUser(
        euint128 data,
        address user
    ) external view returns (bytes memory) {
        bytes32 publicKey = userPublicKeys[user];
        require(publicKey != bytes32(0), "No public key registered");
        return data.seal(publicKey);
    }

    /**
     * @dev Seal data with global public key following CoFHE global sealing patterns
     * @param data Encrypted data to seal
     * @return Sealed data bytes
     */
    function sealWithGlobalKey(euint128 data) external view returns (bytes memory) {
        return data.seal(globalPublicKey);
    }

    /**
     * @dev Verify access permissions following CoFHE verification patterns
     * @param user User address to check
     * @param accessType Type of access to verify
     * @return True if user has access
     */
    function hasAccess(
        address user,
        string memory accessType
    ) public view returns (bool) {
        bytes32 accessHash = keccak256(bytes(accessType));
        return hasAccess(user, accessHash);
    }

    /**
     * @dev Verify access permissions (bytes32 version) following CoFHE patterns
     * @param user User address to check
     * @param accessType Type of access to verify (as bytes32)
     * @return True if user has access
     */
    function hasAccess(
        address user,
        bytes32 accessType
    ) public view returns (bool) {
        return userAccess[user][accessType] && !emergencyPaused;
    }

    /**
     * @dev Register public key for user following CoFHE key management patterns
     * @param publicKey User's public key for encryption
     */
    function registerPublicKey(
        bytes32 publicKey
    ) external notPaused validPublicKey(publicKey) {
        userPublicKeys[msg.sender] = publicKey;
        permissionTimestamps[msg.sender] = block.timestamp;
        
        emit PublicKeyRegistered(msg.sender, publicKey, block.timestamp);
    }

    /**
     * @dev Update public key for user following CoFHE key update patterns
     * @param user User address (admin can update any user's key)
     * @param newPublicKey New public key
     */
    function updatePublicKey(
        address user,
        bytes32 newPublicKey
    ) external validPublicKey(newPublicKey) {
        require(
            msg.sender == user || userAccess[msg.sender][ADMIN_ACCESS],
            "Not authorized"
        );
        
        bytes32 oldKey = userPublicKeys[user];
        userPublicKeys[user] = newPublicKey;
        
        // Update permit if exists
        if (userPermits[user].publicKey == oldKey) {
            userPermits[user].publicKey = newPublicKey;
        }
        
        emit PublicKeyRegistered(user, newPublicKey, block.timestamp);
    }

    /**
     * @dev Get user's registered public key following CoFHE key retrieval patterns
     * @param user User address
     * @return User's public key
     */
    function getUserPublicKey(address user) external view returns (bytes32) {
        return userPublicKeys[user];
    }

    /**
     * @dev Get global public key for system-wide encrypted data
     * @return Global public key
     */
    function getGlobalPublicKey() external view returns (bytes32) {
        return globalPublicKey;
    }

    /**
     * @dev Check if user has valid permit for data type following CoFHE permit validation
     * @param user User address
     * @param dataType Data type to check
     * @return True if valid permit exists
     */
    function hasValidPermit(
        address user,
        bytes32 dataType
    ) external view returns (bool) {
        return hasAccess(user, dataType) && 
               userPublicKeys[user] != bytes32(0) &&
               userPermits[user].publicKey != bytes32(0);
    }

    /**
     * @dev Get all access types for a user following CoFHE access enumeration patterns
     * @param user User address
     * @return Array of access types the user has
     */
    function getUserAccess(address user) external view returns (bytes32[] memory) {
        bytes32[] memory allTypes = new bytes32[](6);
        allTypes[0] = ADMIN_ACCESS;
        allTypes[1] = LP_REWARDS_ACCESS;
        allTypes[2] = MEV_DATA_ACCESS;
        allTypes[3] = ARBITRAGE_DATA_ACCESS;
        allTypes[4] = PRICE_DATA_ACCESS;
        allTypes[5] = THRESHOLD_ACCESS;
        
        uint256 count = 0;
        for (uint256 i = 0; i < allTypes.length; i++) {
            if (userAccess[user][allTypes[i]]) {
                count++;
            }
        }
        
        bytes32[] memory userTypes = new bytes32[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allTypes.length; i++) {
            if (userAccess[user][allTypes[i]]) {
                userTypes[index] = allTypes[i];
                index++;
            }
        }
        
        return userTypes;
    }

    /**
     * @dev Get permission timestamp for user
     * @param user User address
     * @return Timestamp when permissions were last updated
     */
    function getPermissionTimestamp(address user) external view returns (uint256) {
        return permissionTimestamps[user];
    }

    /**
     * @dev Emergency access revocation following CoFHE emergency patterns
     * @param user User to revoke all access from
     */
    function emergencyRevokeAllAccess(address user) external onlyAdmin {
        // Revoke all access types
        userAccess[user][ADMIN_ACCESS] = false;
        userAccess[user][LP_REWARDS_ACCESS] = false;
        userAccess[user][MEV_DATA_ACCESS] = false;
        userAccess[user][ARBITRAGE_DATA_ACCESS] = false;
        userAccess[user][PRICE_DATA_ACCESS] = false;
        userAccess[user][THRESHOLD_ACCESS] = false;
        
        // Clear public key and permits
        userPublicKeys[user] = bytes32(0);
        delete userPermits[user];
        
        emit EmergencyAccessRevoked(user, msg.sender, block.timestamp);
        
        // Emit individual revocation events
        emit AccessRevoked(user, ADMIN_ACCESS, block.timestamp);
        emit AccessRevoked(user, LP_REWARDS_ACCESS, block.timestamp);
        emit AccessRevoked(user, MEV_DATA_ACCESS, block.timestamp);
        emit AccessRevoked(user, ARBITRAGE_DATA_ACCESS, block.timestamp);
        emit AccessRevoked(user, PRICE_DATA_ACCESS, block.timestamp);
        emit AccessRevoked(user, THRESHOLD_ACCESS, block.timestamp);
    }

    /**
     * @dev Emergency pause system following CoFHE emergency patterns
     */
    function emergencyPause() external onlyAdmin {
        emergencyPaused = true;
    }

    /**
     * @dev Resume system after emergency pause
     */
    function emergencyResume() external onlyAdmin {
        emergencyPaused = false;
    }

    /**
     * @dev Update global public key (admin only) following CoFHE key management
     * @param newGlobalKey New global public key
     */
    function updateGlobalPublicKey(
        bytes32 newGlobalKey
    ) external onlyAdmin validPublicKey(newGlobalKey) {
        globalPublicKey = newGlobalKey;
    }

    /**
     * @dev Check if access type is valid
     * @param accessType Access type hash to validate
     * @return True if access type is valid
     */
    function _isValidAccessType(bytes32 accessType) internal pure returns (bool) {
        return accessType == ADMIN_ACCESS ||
               accessType == LP_REWARDS_ACCESS ||
               accessType == MEV_DATA_ACCESS ||
               accessType == ARBITRAGE_DATA_ACCESS ||
               accessType == PRICE_DATA_ACCESS ||
               accessType == THRESHOLD_ACCESS;
    }

    /**
     * @dev Get system status following CoFHE status patterns
     * @return admin address, paused status, total users with permissions
     */
    function getSystemStatus() external view returns (
        address adminAddress,
        bool isPaused,
        bytes32 globalKey
    ) {
        return (admin, emergencyPaused, globalPublicKey);
    }
}