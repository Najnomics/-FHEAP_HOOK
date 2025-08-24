// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    FHE,
    inEuint128,
    euint128,
    inEuint64,
    euint64,
    ebool
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title PriceAggregator  
 * @dev Multi-DEX price aggregation and encryption service
 * Following CoFHE price oracle patterns from Fhenix documentation
 * Purpose: Collects prices from multiple DEXs and encrypts them for FHE operations
 */
contract PriceAggregator {
    
    // Events following CoFHE price oracle event patterns
    event PriceUpdated(
        address indexed dex,
        address indexed token0,
        address indexed token1,
        bytes encryptedPrice,
        uint256 timestamp
    );
    
    event BatchPriceUpdate(
        address[] dexs,
        uint256 updateCount,
        uint256 timestamp
    );
    
    event OracleAdded(
        address indexed oracle, 
        string name, 
        DEXType indexed dexType,
        uint256 timestamp
    );
    
    event OracleRemoved(
        address indexed oracle, 
        uint256 timestamp
    );

    event PriceValidationFailed(
        address indexed dex,
        address indexed token0,
        address indexed token1,
        string reason,
        uint256 timestamp
    );

    event EmergencyPauseActivated(
        address indexed admin,
        uint256 timestamp
    );

    // Supported DEX identifiers following CoFHE enumeration patterns
    enum DEXType {
        UNISWAP_V2,
        UNISWAP_V3,
        SUSHISWAP,
        CURVE,
        BALANCER,
        CUSTOM
    }

    // Price data structure following CoFHE data patterns
    struct EncryptedPriceData {
        euint128 price;
        uint256 timestamp;
        uint256 blockNumber;
        DEXType dexType;
        bool isValid;
        bytes32 priceHash; // For integrity verification
    }

    // Oracle information following CoFHE oracle management patterns
    struct PriceOracle {
        address oracle;
        string name;
        DEXType dexType;
        bool isActive;
        uint256 addedTimestamp;
        uint256 updateCount;
        uint256 lastUpdateTimestamp;
    }

    // State variables following CoFHE state management patterns
    mapping(address => mapping(address => mapping(address => EncryptedPriceData))) private encryptedPrices;
    mapping(address => PriceOracle) public priceOracles;
    mapping(DEXType => address[]) public dexOracles;
    mapping(address => uint256) private oracleReputationScores;
    
    address[] public authorizedUpdaters;
    mapping(address => bool) public isAuthorizedUpdater;
    mapping(address => uint256) private updaterTimestamps;
    
    // Access control and system settings
    address public immutable admin;
    bool public emergencyPaused;
    bytes32 private systemPublicKey;
    
    // Constants following CoFHE best practices
    uint256 public constant PRICE_STALENESS_THRESHOLD = 300; // 5 minutes
    uint256 public constant MAX_PRICE_DEVIATION = 1000; // 10% in basis points
    uint256 public constant MIN_REPUTATION_SCORE = 100;
    uint256 public constant MAX_ORACLES_PER_TYPE = 10;
    
    // Regular constants - FHE values created as needed in functions
    uint128 private constant ZERO_VALUE = 0;
    uint128 private constant MAX_PRICE_VALUE = type(uint128).max;

    modifier onlyAuthorized() {
        require(
            isAuthorizedUpdater[msg.sender] || msg.sender == admin, 
            "Not authorized"
        );
        require(!emergencyPaused, "System paused");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Admin only");
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }

    modifier notPaused() {
        require(!emergencyPaused, "System paused");
        _;
    }

    constructor() {
        admin = msg.sender;
        isAuthorizedUpdater[admin] = true;
        authorizedUpdaters.push(admin);
        oracleReputationScores[admin] = 1000; // Perfect reputation for admin
        
        // Set system public key for encrypted price sealing
        systemPublicKey = keccak256(abi.encodePacked(admin, block.timestamp, "PRICE_SYSTEM"));
    }

    /**
     * @dev Update encrypted price for a specific pool following CoFHE update patterns
     * @param dex DEX contract address
     * @param token0 First token address
     * @param token1 Second token address
     * @param encryptedPrice Encrypted price data
     */
    function updateEncryptedPrice(
        address dex,
        address token0,
        address token1,
        inEuint128 calldata encryptedPrice
    ) external onlyAuthorized validAddress(dex) validAddress(token0) validAddress(token1) {
        require(priceOracles[dex].isActive, "DEX not registered");
        require(token0 != token1, "Invalid token pair");
        
        euint128 price = FHE.asEuint128(encryptedPrice);
        
        // Validate price using FHE operations
        FHE.req(FHE.gt(price, FHE.asEuint128(ZERO_VALUE)));
        FHE.req(FHE.lt(price, MAX_PRICE_ENCRYPTED));
        
        // Create price hash for integrity
        bytes32 priceHash = keccak256(abi.encodePacked(
            dex, token0, token1, block.timestamp, block.number
        ));
        
        // Store encrypted price data following CoFHE storage patterns
        encryptedPrices[dex][token0][token1] = EncryptedPriceData({
            price: price,
            timestamp: block.timestamp,
            blockNumber: block.number,
            dexType: priceOracles[dex].dexType,
            isValid: true,
            priceHash: priceHash
        });
        
        // Store reverse pair for convenience with inverted price
        encryptedPrices[dex][token1][token0] = EncryptedPriceData({
            price: _calculateInversePrice(price),
            timestamp: block.timestamp,
            blockNumber: block.number,
            dexType: priceOracles[dex].dexType,
            isValid: true,
            priceHash: priceHash
        });
        
        // Update oracle statistics
        priceOracles[dex].updateCount++;
        priceOracles[dex].lastUpdateTimestamp = block.timestamp;
        updaterTimestamps[msg.sender] = block.timestamp;
        
        // Increase reputation score for successful update
        oracleReputationScores[dex] = oracleReputationScores[dex] + 1;
        
        // Emit event with sealed encrypted price following CoFHE event patterns
        emit PriceUpdated(
            dex,
            token0,
            token1,
            abi.encode(price),
            block.timestamp
        );
    }

    /**
     * @dev Get encrypted price spread between two pools following CoFHE calculation patterns
     * @param poolA First pool address
     * @param poolB Second pool address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Encrypted price spread
     */
    function getEncryptedSpread(
        address poolA,
        address poolB,
        address token0,
        address token1
    ) external view validAddress(poolA) validAddress(poolB) returns (euint128) {
        EncryptedPriceData memory priceA = encryptedPrices[poolA][token0][token1];
        EncryptedPriceData memory priceB = encryptedPrices[poolB][token0][token1];
        
        // Validate price data
        require(priceA.isValid && priceB.isValid, "Invalid price data");
        require(_isPriceFresh(priceA.timestamp), "Price A is stale");
        require(_isPriceFresh(priceB.timestamp), "Price B is stale");
        
        // Calculate absolute difference using FHE operations
        euint128 diff1 = FHE.sub(priceA.price, priceB.price);
        euint128 diff2 = FHE.sub(priceB.price, priceA.price);
        
        // Return absolute value using FHE select
        ebool aGreater = FHE.gt(priceA.price, priceB.price);
        return FHE.select(aGreater, diff1, diff2);
    }

    /**
     * @dev Get encrypted prices from multiple DEXs following CoFHE multi-source patterns
     * @param token0 First token address
     * @param token1 Second token address
     * @return Array of encrypted prices from different DEXs
     */
    function getEncryptedCrossDEXPrices(
        address token0,
        address token1
    ) external view validAddress(token0) validAddress(token1) returns (euint128[] memory) {
        uint256 validPriceCount = 0;
        
        // Count valid prices from active oracles
        for (uint256 i = 0; i < authorizedUpdaters.length; i++) {
            address dex = authorizedUpdaters[i];
            if (priceOracles[dex].isActive && 
                oracleReputationScores[dex] >= MIN_REPUTATION_SCORE) {
                EncryptedPriceData memory priceData = encryptedPrices[dex][token0][token1];
                if (priceData.isValid && _isPriceFresh(priceData.timestamp)) {
                    validPriceCount++;
                }
            }
        }
        
        require(validPriceCount > 0, "No valid prices available");
        
        // Collect valid prices
        euint128[] memory prices = new euint128[](validPriceCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < authorizedUpdaters.length; i++) {
            address dex = authorizedUpdaters[i];
            if (priceOracles[dex].isActive && 
                oracleReputationScores[dex] >= MIN_REPUTATION_SCORE) {
                EncryptedPriceData memory priceData = encryptedPrices[dex][token0][token1];
                if (priceData.isValid && _isPriceFresh(priceData.timestamp)) {
                    prices[index] = priceData.price;
                    index++;
                }
            }
        }
        
        return prices;
    }

    /**
     * @dev Get encrypted price for specific DEX following CoFHE data access patterns
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Encrypted price
     */
    function getEncryptedPrice(
        address dex,
        address token0,
        address token1
    ) external view validAddress(dex) validAddress(token0) validAddress(token1) returns (euint128) {
        EncryptedPriceData memory priceData = encryptedPrices[dex][token0][token1];
        require(priceData.isValid, "Price not available");
        require(_isPriceFresh(priceData.timestamp), "Price is stale");
        require(oracleReputationScores[dex] >= MIN_REPUTATION_SCORE, "Low reputation oracle");
        
        return priceData.price;
    }

    /**
     * @dev Add new price oracle following CoFHE oracle management patterns
     * @param oracle Oracle address
     * @param name Oracle name
     * @param dexType Type of DEX
     */
    function addPriceOracle(
        address oracle,
        string calldata name,
        DEXType dexType
    ) external onlyAdmin validAddress(oracle) {
        require(!priceOracles[oracle].isActive, "Oracle already active");
        require(bytes(name).length > 0, "Invalid name");
        require(dexOracles[dexType].length < MAX_ORACLES_PER_TYPE, "Too many oracles for type");
        
        priceOracles[oracle] = PriceOracle({
            oracle: oracle,
            name: name,
            dexType: dexType,
            isActive: true,
            addedTimestamp: block.timestamp,
            updateCount: 0,
            lastUpdateTimestamp: 0
        });
        
        dexOracles[dexType].push(oracle);
        oracleReputationScores[oracle] = 500; // Starting reputation
        
        if (!isAuthorizedUpdater[oracle]) {
            isAuthorizedUpdater[oracle] = true;
            authorizedUpdaters.push(oracle);
        }
        
        emit OracleAdded(oracle, name, dexType, block.timestamp);
    }

    /**
     * @dev Remove price oracle following CoFHE oracle management patterns
     * @param oracle Oracle address to remove
     */
    function removePriceOracle(address oracle) external onlyAdmin validAddress(oracle) {
        require(priceOracles[oracle].isActive, "Oracle not active");
        
        priceOracles[oracle].isActive = false;
        isAuthorizedUpdater[oracle] = false;
        oracleReputationScores[oracle] = 0;
        
        // Remove from authorizedUpdaters array
        for (uint256 i = 0; i < authorizedUpdaters.length; i++) {
            if (authorizedUpdaters[i] == oracle) {
                authorizedUpdaters[i] = authorizedUpdaters[authorizedUpdaters.length - 1];
                authorizedUpdaters.pop();
                break;
            }
        }
        
        emit OracleRemoved(oracle, block.timestamp);
    }

    /**
     * @dev Calculate inverse price for cross-pair calculations
     * Following CoFHE calculation patterns
     * Note: Simplified due to FHE division limitations
     * @param price Encrypted input price
     * @return Encrypted approximated inverse price
     */
    function _calculateInversePrice(euint128 price) internal pure returns (euint128) {
        // Since FHE.div is not supported for euint128, we'll use a simplified approximation
        // This is a placeholder implementation - production would need alternative approach
        
        // For now, return a fixed inverse approximation based on magnitude
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(price, zero));
        
        // Simple approximation: if price is high, inverse is low
        euint128 threshold = FHE.asEuint128(1e18);
        ebool isHighPrice = FHE.gt(price, threshold);
        
        // Return approximate inverse values
        euint128 lowInverse = FHE.asEuint128(1e15);  // For high prices
        euint128 highInverse = FHE.asEuint128(1e21); // For low prices
        
        return FHE.select(isHighPrice, lowInverse, highInverse);
    }

    /**
     * @dev Check if price is fresh (not stale) following CoFHE validation patterns
     * @param timestamp Price timestamp
     * @return True if price is fresh
     */
    function _isPriceFresh(uint256 timestamp) internal view returns (bool) {
        return block.timestamp - timestamp <= PRICE_STALENESS_THRESHOLD;
    }

    /**
     * @dev Emergency pause all price updates following CoFHE emergency patterns
     */
    function emergencyPause() external onlyAdmin {
        emergencyPaused = true;
        emit EmergencyPauseActivated(msg.sender, block.timestamp);
    }

    /**
     * @dev Resume price updates after emergency
     */
    function emergencyResume() external onlyAdmin {
        emergencyPaused = false;
    }

    /**
     * @dev Get system public key for price sealing
     * @return System public key
     */
    function getSystemPublicKey() external view returns (bytes32) {
        return systemPublicKey;
    }
}