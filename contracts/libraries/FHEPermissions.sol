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
 * Purpose: Manages who can access encrypted arbitrage data and LP rewards
 */
contract FHEPermissions {
    using Permit for Permit.Permission;

    // Events
    event AccessGranted(address indexed user, bytes32 indexed accessType, uint256 timestamp);
    event AccessRevoked(address indexed user, bytes32 indexed accessType, uint256 timestamp);
    event PermitCreated(address indexed user, bytes32 indexed dataType, uint256 timestamp);

    // Access types
    bytes32 public constant ADMIN_ACCESS = keccak256("admin");
    bytes32 public constant LP_REWARDS_ACCESS = keccak256("lp_rewards");
    bytes32 public constant MEV_DATA_ACCESS = keccak256("mev_data");
    bytes32 public constant ARBITRAGE_DATA_ACCESS = keccak256("arbitrage_data");
    bytes32 public constant PRICE_DATA_ACCESS = keccak256("price_data");

    // State variables
    mapping(address => mapping(bytes32 => bool)) private userAccess;
    mapping(address => Permit.Permission) private userPermits;
    mapping(address => bytes32) private userPublicKeys;
    mapping(bytes32 => mapping(address => bool)) private dataTypeAccess;
    
    address public immutable admin;
    
    modifier onlyAdmin() {
        require(msg.sender == admin || userAccess[msg.sender][ADMIN_ACCESS], "Not authorized");
        _;
    }

    constructor() {
        admin = msg.sender;
        // Grant admin full access
        userAccess[admin][ADMIN_ACCESS] = true;
        userAccess[admin][LP_REWARDS_ACCESS] = true;
        userAccess[admin][MEV_DATA_ACCESS] = true;
        userAccess[admin][ARBITRAGE_DATA_ACCESS] = true;
        userAccess[admin][PRICE_DATA_ACCESS] = true;
    }

    /**
     * @dev Grant access to LP for viewing encrypted rewards
     * @param lp LP address to grant access
     * @param publicKey LP's public key for encryption
     */
    function grantLPAccess(address lp, bytes32 publicKey) external onlyAdmin {
        userAccess[lp][LP_REWARDS_ACCESS] = true;
        userPublicKeys[lp] = publicKey;
        
        emit AccessGranted(lp, LP_REWARDS_ACCESS, block.timestamp);
    }

    /**
     * @dev Grant general access permissions
     * @param user User address
     * @param accessType Type of access to grant
     */
    function grantAccess(address user, string calldata accessType) external onlyAdmin {
        bytes32 accessHash = keccak256(bytes(accessType));
        userAccess[user][accessHash] = true;
        
        emit AccessGranted(user, accessHash, block.timestamp);
    }

    /**
     * @dev Revoke access permissions
     * @param user User address
     * @param accessType Type of access to revoke
     */
    function revokeAccess(address user, string calldata accessType) external onlyAdmin {
        bytes32 accessHash = keccak256(bytes(accessType));
        userAccess[user][accessHash] = false;
        
        emit AccessRevoked(user, accessHash, block.timestamp);
    }

    /**
     * @dev Create permit for encrypted data access
     * @param user User requesting access
     * @param dataType Type of encrypted data
     * @return Permission struct for data access
     */
    function createDataPermit(
        address user,
        bytes32 dataType
    ) external returns (Permit.Permission memory) {
        require(hasAccess(user, dataType), "Access denied");
        
        Permit.Permission memory permission = Permit.Permission({
            issuer: user,
            permitted: address(this),
            publicKey: userPublicKeys[user]
        });
        
        userPermits[user] = permission;
        
        emit PermitCreated(user, dataType, block.timestamp);
        return permission;
    }

    /**
     * @dev Seal encrypted data for specific user
     * @param data Encrypted data to seal
     * @param user Target user address
     * @return Sealed data bytes
     */
    function sealForUser(
        euint128 data,
        address user
    ) external view returns (bytes memory) {
        require(userPublicKeys[user] != bytes32(0), "No public key registered");
        return data.seal(userPublicKeys[user]);
    }

    /**
     * @dev Verify access permissions
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
     * @dev Verify access permissions (bytes32 version)
     * @param user User address to check
     * @param accessType Type of access to verify (as bytes32)
     * @return True if user has access
     */
    function hasAccess(
        address user,
        bytes32 accessType
    ) public view returns (bool) {
        return userAccess[user][accessType];
    }

    /**
     * @dev Batch grant access to multiple users
     * @param users Array of user addresses
     * @param accessType Type of access to grant
     */
    function batchGrantAccess(
        address[] calldata users,
        string calldata accessType
    ) external onlyAdmin {
        bytes32 accessHash = keccak256(bytes(accessType));
        
        for (uint256 i = 0; i < users.length; i++) {
            userAccess[users[i]][accessHash] = true;
            emit AccessGranted(users[i], accessHash, block.timestamp);
        }
    }

    /**
     * @dev Register public key for user
     * @param publicKey User's public key for encryption
     */
    function registerPublicKey(bytes32 publicKey) external {
        userPublicKeys[msg.sender] = publicKey;
    }

    /**
     * @dev Get user's registered public key
     * @param user User address
     * @return User's public key
     */
    function getUserPublicKey(address user) external view returns (bytes32) {
        return userPublicKeys[user];
    }

    /**
     * @dev Check if user has valid permit for data type
     * @param user User address
     * @param dataType Data type to check
     * @return True if valid permit exists
     */
    function hasValidPermit(
        address user,
        bytes32 dataType
    ) external view returns (bool) {
        return hasAccess(user, dataType) && userPublicKeys[user] != bytes32(0);
    }

    /**
     * @dev Get all access types for a user
     * @param user User address
     * @return Array of access types the user has
     */
    function getUserAccess(address user) external view returns (bytes32[] memory) {
        bytes32[] memory allTypes = new bytes32[](5);
        allTypes[0] = ADMIN_ACCESS;
        allTypes[1] = LP_REWARDS_ACCESS;
        allTypes[2] = MEV_DATA_ACCESS;
        allTypes[3] = ARBITRAGE_DATA_ACCESS;
        allTypes[4] = PRICE_DATA_ACCESS;
        
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
     * @dev Emergency access revocation (admin only)
     * @param user User to revoke all access from
     */
    function emergencyRevokeAllAccess(address user) external onlyAdmin {
        userAccess[user][ADMIN_ACCESS] = false;
        userAccess[user][LP_REWARDS_ACCESS] = false;
        userAccess[user][MEV_DATA_ACCESS] = false;
        userAccess[user][ARBITRAGE_DATA_ACCESS] = false;
        userAccess[user][PRICE_DATA_ACCESS] = false;
        
        // Clear public key
        userPublicKeys[user] = bytes32(0);
        
        emit AccessRevoked(user, ADMIN_ACCESS, block.timestamp);
        emit AccessRevoked(user, LP_REWARDS_ACCESS, block.timestamp);
        emit AccessRevoked(user, MEV_DATA_ACCESS, block.timestamp);
        emit AccessRevoked(user, ARBITRAGE_DATA_ACCESS, block.timestamp);
        emit AccessRevoked(user, PRICE_DATA_ACCESS, block.timestamp);
    }
}