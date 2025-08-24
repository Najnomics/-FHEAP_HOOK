// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    FHE,
    inEuint128,
    euint128,
    inEuint64,
    euint64
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title PriceAggregator  
 * @dev Multi-DEX price aggregation and encryption service
 * Purpose: Collects prices from multiple DEXs and encrypts them for FHE operations
 */
contract PriceAggregator {
    
    // Events
    event PriceUpdated(
        address indexed dex,
        address indexed token0,
        address indexed token1,
        bytes32 encryptedPrice,
        uint256 timestamp
    );
    
    event BatchPriceUpdate(
        address[] dexs,
        uint256 updateCount,
        uint256 timestamp
    );
    
    event OracleAdded(address indexed oracle, string name, uint256 timestamp);
    event OracleRemoved(address indexed oracle, uint256 timestamp);

    // Supported DEX identifiers
    enum DEXType {
        UNISWAP_V2,
        UNISWAP_V3,
        SUSHISWAP,
        CURVE,
        BALANCER,
        CUSTOM
    }

    // Price data structure
    struct EncryptedPriceData {
        euint128 price;
        uint256 timestamp;
        uint256 blockNumber;
        DEXType dexType;
        bool isValid;
    }

    // Oracle information
    struct PriceOracle {
        address oracle;
        string name;
        DEXType dexType;
        bool isActive;
        uint256 addedTimestamp;
    }

    // State variables
    mapping(address => mapping(address => mapping(address => EncryptedPriceData))) private encryptedPrices;
    mapping(address => PriceOracle) public priceOracles;
    mapping(DEXType => address[]) public dexOracles;
    
    address[] public authorizedUpdaters;
    mapping(address => bool) public isAuthorizedUpdater;
    
    address public immutable admin;
    uint256 public constant PRICE_STALENESS_THRESHOLD = 300; // 5 minutes
    uint256 public constant MAX_PRICE_DEVIATION = 1000; // 10% in basis points

    modifier onlyAuthorized() {
        require(isAuthorizedUpdater[msg.sender] || msg.sender == admin, "Not authorized");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Admin only");
        _;
    }

    constructor() {
        admin = msg.sender;
        isAuthorizedUpdater[admin] = true;
        authorizedUpdaters.push(admin);
    }

    /**
     * @dev Update encrypted price for a specific pool
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
    ) external onlyAuthorized {
        require(priceOracles[dex].isActive, "DEX not registered");
        
        euint128 price = FHE.asEuint128(encryptedPrice);
        
        // Validate price is not zero
        FHE.req(FHE.gt(price, FHE.asEuint128(0)));
        
        // Store encrypted price data
        encryptedPrices[dex][token0][token1] = EncryptedPriceData({
            price: price,
            timestamp: block.timestamp,
            blockNumber: block.number,
            dexType: priceOracles[dex].dexType,
            isValid: true
        });
        
        // Store reverse pair for convenience
        encryptedPrices[dex][token1][token0] = EncryptedPriceData({
            price: FHE.div(FHE.asEuint128(1e36), price), // Inverse price
            timestamp: block.timestamp,
            blockNumber: block.number,
            dexType: priceOracles[dex].dexType,
            isValid: true
        });
        
        emit PriceUpdated(
            dex,
            token0,
            token1,
            _encryptedToBytes32(price),
            block.timestamp
        );
    }

    /**
     * @dev Get encrypted price spread between two pools
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
    ) external view returns (euint128) {
        EncryptedPriceData memory priceA = encryptedPrices[poolA][token0][token1];
        EncryptedPriceData memory priceB = encryptedPrices[poolB][token0][token1];
        
        require(priceA.isValid && priceB.isValid, "Invalid price data");
        require(_isPriceFresh(priceA.timestamp), "Price A is stale");
        require(_isPriceFresh(priceB.timestamp), "Price B is stale");
        
        // Calculate absolute difference
        euint128 diff1 = FHE.sub(priceA.price, priceB.price);
        euint128 diff2 = FHE.sub(priceB.price, priceA.price);
        
        // Return absolute value using select
        return FHE.select(FHE.gt(priceA.price, priceB.price), diff1, diff2);
    }

    /**
     * @dev Batch update multiple pool prices
     * @param dexs Array of DEX addresses
     * @param token0s Array of first token addresses
     * @param token1s Array of second token addresses
     * @param encryptedPrices Array of encrypted prices
     */
    function batchUpdatePrices(
        address[] calldata dexs,
        address[] calldata token0s,
        address[] calldata token1s,
        inEuint128[] calldata encryptedPrices
    ) external onlyAuthorized {
        require(
            dexs.length == token0s.length &&
            token0s.length == token1s.length &&
            token1s.length == encryptedPrices.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < dexs.length; i++) {
            this.updateEncryptedPrice(dexs[i], token0s[i], token1s[i], encryptedPrices[i]);
        }
        
        emit BatchPriceUpdate(dexs, dexs.length, block.timestamp);
    }

    /**
     * @dev Get encrypted prices from multiple DEXs for cross-comparison
     * @param token0 First token address
     * @param token1 Second token address
     * @return Array of encrypted prices from different DEXs
     */
    function getEncryptedCrossDEXPrices(
        address token0,
        address token1
    ) external view returns (euint128[] memory) {
        uint256 validPriceCount = 0;
        
        // Count valid prices
        for (uint256 i = 0; i < authorizedUpdaters.length; i++) {
            address dex = authorizedUpdaters[i];
            if (priceOracles[dex].isActive) {
                EncryptedPriceData memory priceData = encryptedPrices[dex][token0][token1];
                if (priceData.isValid && _isPriceFresh(priceData.timestamp)) {
                    validPriceCount++;
                }
            }
        }
        
        // Collect valid prices
        euint128[] memory prices = new euint128[](validPriceCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < authorizedUpdaters.length; i++) {
            address dex = authorizedUpdaters[i];
            if (priceOracles[dex].isActive) {
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
     * @dev Get encrypted price for specific DEX and token pair
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Encrypted price
     */
    function getEncryptedPrice(
        address dex,
        address token0,
        address token1
    ) external view returns (euint128) {
        EncryptedPriceData memory priceData = encryptedPrices[dex][token0][token1];
        require(priceData.isValid, "Price not available");
        require(_isPriceFresh(priceData.timestamp), "Price is stale");
        
        return priceData.price;
    }

    /**
     * @dev Add new price oracle
     * @param oracle Oracle address
     * @param name Oracle name
     * @param dexType Type of DEX
     */
    function addPriceOracle(
        address oracle,
        string calldata name,
        DEXType dexType
    ) external onlyAdmin {
        require(oracle != address(0), "Invalid oracle address");
        require(!priceOracles[oracle].isActive, "Oracle already active");
        
        priceOracles[oracle] = PriceOracle({
            oracle: oracle,
            name: name,
            dexType: dexType,
            isActive: true,
            addedTimestamp: block.timestamp
        });
        
        dexOracles[dexType].push(oracle);
        
        if (!isAuthorizedUpdater[oracle]) {
            isAuthorizedUpdater[oracle] = true;
            authorizedUpdaters.push(oracle);
        }
        
        emit OracleAdded(oracle, name, block.timestamp);
    }

    /**
     * @dev Remove price oracle
     * @param oracle Oracle address to remove
     */
    function removePriceOracle(address oracle) external onlyAdmin {
        require(priceOracles[oracle].isActive, "Oracle not active");
        
        priceOracles[oracle].isActive = false;
        isAuthorizedUpdater[oracle] = false;
        
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
     * @dev Check if price is fresh (not stale)
     * @param timestamp Price timestamp
     * @return True if price is fresh
     */
    function _isPriceFresh(uint256 timestamp) internal view returns (bool) {
        return block.timestamp - timestamp <= PRICE_STALENESS_THRESHOLD;
    }

    /**
     * @dev Convert encrypted value to bytes32 for events
     * @param value Encrypted value
     * @return bytes32 representation
     */
    function _encryptedToBytes32(euint128 value) internal pure returns (bytes32) {
        // In real implementation, this would properly encode the encrypted value
        // For now, using decrypted value for events (not ideal for production)
        return bytes32(uint256(FHE.decrypt(value)));
    }

    /**
     * @dev Get price age in seconds
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Age of price in seconds
     */
    function getPriceAge(
        address dex,
        address token0,
        address token1
    ) external view returns (uint256) {
        EncryptedPriceData memory priceData = encryptedPrices[dex][token0][token1];
        if (!priceData.isValid) return type(uint256).max;
        
        return block.timestamp - priceData.timestamp;
    }

    /**
     * @dev Get all registered DEX addresses for a specific type
     * @param dexType Type of DEX
     * @return Array of DEX addresses
     */
    function getDEXsByType(DEXType dexType) external view returns (address[] memory) {
        return dexOracles[dexType];
    }

    /**
     * @dev Get total number of authorized updaters
     * @return Number of authorized updaters
     */
    function getAuthorizedUpdaterCount() external view returns (uint256) {
        return authorizedUpdaters.length;
    }

    /**
     * @dev Emergency pause all price updates
     */
    function emergencyPause() external onlyAdmin {
        // Remove all authorized updaters except admin
        for (uint256 i = 0; i < authorizedUpdaters.length; i++) {
            if (authorizedUpdaters[i] != admin) {
                isAuthorizedUpdater[authorizedUpdaters[i]] = false;
            }
        }
        
        // Clear the array and keep only admin
        delete authorizedUpdaters;
        authorizedUpdaters.push(admin);
    }
}