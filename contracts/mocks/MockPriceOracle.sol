// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    FHE,
    inEuint128,
    euint128,
    ebool
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title MockPriceOracle
 * @dev Mock price oracle for testing FHEAP price aggregation
 * Following CoFHE mock oracle patterns from Fhenix documentation
 */
contract MockPriceOracle {

    // Events following CoFHE mock event patterns
    event MockPriceSet(
        address indexed dex,
        address indexed token0,
        address indexed token1,
        uint256 price,
        bytes encryptedPrice,
        uint256 timestamp
    );

    event MockArbitrageScenario(
        string scenario,
        address[] dexs,
        uint256[] prices,
        uint256 maxSpread,
        uint256 timestamp
    );

    // Mock DEX identifiers
    enum MockDEXType {
        MOCK_UNISWAP_V3,
        MOCK_SUSHISWAP,
        MOCK_CURVE,
        MOCK_BALANCER
    }

    // Mock price data structure
    struct MockPriceData {
        uint256 price;
        euint128 encryptedPrice;
        uint256 timestamp;
        uint256 blockNumber;
        bool isValid;
        MockDEXType dexType;
    }

    // State variables for mock data
    mapping(address => mapping(address => mapping(address => MockPriceData))) public mockPrices;
    mapping(address => MockDEXType) public mockDEXTypes;
    mapping(address => string) public mockDEXNames;
    mapping(address => bool) public isDEXRegistered;
    
    // Mock scenarios for testing
    mapping(string => uint256[]) public arbitrageScenarios;
    
    address[] public registeredDEXs;
    bytes32 private mockSystemPublicKey;

    constructor() {
        // Set mock system public key
        mockSystemPublicKey = keccak256(abi.encodePacked("MOCK_SYSTEM_KEY", block.timestamp));
        
        // Register mock DEXs for testing
        _registerMockDEX(
            address(0x3333333333333333333333333333333333333333), 
            "Mock Uniswap V3", 
            MockDEXType.MOCK_UNISWAP_V3
        );
        _registerMockDEX(
            address(0x4444444444444444444444444444444444444444), 
            "Mock SushiSwap", 
            MockDEXType.MOCK_SUSHISWAP
        );
        _registerMockDEX(
            address(0x5555555555555555555555555555555555555555), 
            "Mock Curve", 
            MockDEXType.MOCK_CURVE
        );
        _registerMockDEX(
            address(0x6666666666666666666666666666666666666666), 
            "Mock Balancer", 
            MockDEXType.MOCK_BALANCER
        );
    }

    /**
     * @dev Set mock price for testing arbitrage detection
     * @param dex Mock DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @param price Price in wei (will be encrypted)
     */
    function setMockPrice(
        address dex,
        address token0,
        address token1,
        uint256 price
    ) external {
        require(isDEXRegistered[dex], "DEX not registered");
        require(price > 0, "Invalid price");
        
        // Encrypt the price using FHE
        euint128 encryptedPrice = FHE.asEuint128(price);
        
        // Store mock price data
        mockPrices[dex][token0][token1] = MockPriceData({
            price: price,
            encryptedPrice: encryptedPrice,
            timestamp: block.timestamp,
            blockNumber: block.number,
            isValid: true,
            dexType: mockDEXTypes[dex]
        });
        
        // Also store reverse pair
        mockPrices[dex][token1][token0] = MockPriceData({
            price: 1e36 / price, // Inverse price
            encryptedPrice: _calculateApproximateInverse(encryptedPrice),
            timestamp: block.timestamp,
            blockNumber: block.number,
            isValid: true,
            dexType: mockDEXTypes[dex]
        });

        emit MockPriceSet(
            dex, 
            token0, 
            token1, 
            price, 
            encryptedPrice.seal(mockSystemPublicKey), 
            block.timestamp
        );
    }

    /**
     * @dev Get encrypted mock price following CoFHE patterns
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Encrypted price
     */
    function getEncryptedMockPrice(
        address dex,
        address token0,
        address token1
    ) external view returns (euint128) {
        MockPriceData memory priceData = mockPrices[dex][token0][token1];
        require(priceData.isValid, "No mock price available");
        
        return priceData.encryptedPrice;
    }

    /**
     * @dev Get plaintext mock price for verification
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return price Plaintext price
     */
    function getMockPrice(
        address dex,
        address token0,
        address token1
    ) external view returns (uint256 price) {
        MockPriceData memory priceData = mockPrices[dex][token0][token1];
        require(priceData.isValid, "No mock price available");
        
        return priceData.price;
    }

    /**
     * @dev Get encrypted prices from all registered DEXs
     * @param token0 First token address
     * @param token1 Second token address
     * @return Array of encrypted prices from different mock DEXs
     */
    function getMockCrossDEXPrices(
        address token0,
        address token1
    ) external view returns (euint128[] memory) {
        uint256 validPriceCount = 0;
        
        // Count valid prices
        for (uint256 i = 0; i < registeredDEXs.length; i++) {
            if (mockPrices[registeredDEXs[i]][token0][token1].isValid) {
                validPriceCount++;
            }
        }
        
        require(validPriceCount > 0, "No mock prices available");
        
        // Collect valid prices
        euint128[] memory prices = new euint128[](validPriceCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < registeredDEXs.length; i++) {
            MockPriceData memory priceData = mockPrices[registeredDEXs[i]][token0][token1];
            if (priceData.isValid) {
                prices[index] = priceData.encryptedPrice;
                index++;
            }
        }
        
        return prices;
    }

    /**
     * @dev Create arbitrage testing scenario
     * @param scenario Scenario name
     * @param token0 First token address
     * @param token1 Second token address
     * @param prices Array of prices for each DEX
     */
    function createArbitrageScenario(
        string calldata scenario,
        address token0,
        address token1,
        uint256[] calldata prices
    ) external {
        require(prices.length == registeredDEXs.length, "Price count mismatch");
        
        uint256 minPrice = type(uint256).max;
        uint256 maxPrice = 0;
        
        // Set prices for each DEX
        for (uint256 i = 0; i < registeredDEXs.length; i++) {
            this.setMockPrice(registeredDEXs[i], token0, token1, prices[i]);
            
            if (prices[i] < minPrice) minPrice = prices[i];
            if (prices[i] > maxPrice) maxPrice = prices[i];
        }
        
        // Store scenario for reference
        arbitrageScenarios[scenario] = prices;
        
        uint256 maxSpread = maxPrice - minPrice;
        
        emit MockArbitrageScenario(
            scenario,
            registeredDEXs,
            prices,
            maxSpread,
            block.timestamp
        );
    }

    /**
     * @dev Create specific arbitrage scenarios for testing
     */
    function createTestScenarios(address token0, address token1) external {
        // Scenario 1: Small spread (0.1% - should not trigger)
        uint256[] memory smallSpread = new uint256[](4);
        smallSpread[0] = 2000 * 1e18; // Uniswap: $2000
        smallSpread[1] = 2002 * 1e18; // Sushi: $2002 (0.1% spread)
        smallSpread[2] = 2001 * 1e18; // Curve: $2001
        smallSpread[3] = 2000 * 1e18; // Balancer: $2000
        this.createArbitrageScenario("small_spread", token0, token1, smallSpread);
        
        // Scenario 2: Medium spread (1% - should trigger)
        uint256[] memory mediumSpread = new uint256[](4);
        mediumSpread[0] = 2000 * 1e18; // Uniswap: $2000
        mediumSpread[1] = 2020 * 1e18; // Sushi: $2020 (1% spread)
        mediumSpread[2] = 2010 * 1e18; // Curve: $2010
        mediumSpread[3] = 2005 * 1e18; // Balancer: $2005
        this.createArbitrageScenario("medium_spread", token0, token1, mediumSpread);
        
        // Scenario 3: Large spread (5% - should definitely trigger)
        uint256[] memory largeSpread = new uint256[](4);
        largeSpread[0] = 2000 * 1e18; // Uniswap: $2000
        largeSpread[1] = 2100 * 1e18; // Sushi: $2100 (5% spread)
        largeSpread[2] = 2050 * 1e18; // Curve: $2050
        largeSpread[3] = 2025 * 1e18; // Balancer: $2025
        this.createArbitrageScenario("large_spread", token0, token1, largeSpread);
        
        // Scenario 4: Extreme spread (10% - maximum protection)
        uint256[] memory extremeSpread = new uint256[](4);
        extremeSpread[0] = 2000 * 1e18; // Uniswap: $2000
        extremeSpread[1] = 2200 * 1e18; // Sushi: $2200 (10% spread)
        extremeSpread[2] = 2100 * 1e18; // Curve: $2100
        extremeSpread[3] = 2150 * 1e18; // Balancer: $2150
        this.createArbitrageScenario("extreme_spread", token0, token1, extremeSpread);
    }

    /**
     * @dev Get scenario prices for testing verification
     * @param scenario Scenario name
     * @return Array of prices used in the scenario
     */
    function getScenarioPrices(string calldata scenario) external view returns (uint256[] memory) {
        return arbitrageScenarios[scenario];
    }

    /**
     * @dev Calculate mock spread between two DEXs
     * @param dex1 First DEX address
     * @param dex2 Second DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Plaintext spread for testing verification
     */
    function calculateMockSpread(
        address dex1,
        address dex2,
        address token0,
        address token1
    ) external view returns (uint256) {
        uint256 price1 = mockPrices[dex1][token0][token1].price;
        uint256 price2 = mockPrices[dex2][token0][token1].price;
        
        require(price1 > 0 && price2 > 0, "Invalid prices");
        
        return price1 > price2 ? price1 - price2 : price2 - price1;
    }

    /**
     * @dev Calculate encrypted spread using FHE operations
     * @param dex1 First DEX address
     * @param dex2 Second DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Encrypted spread
     */
    function calculateEncryptedMockSpread(
        address dex1,
        address dex2,
        address token0,
        address token1
    ) external view returns (euint128) {
        euint128 price1 = mockPrices[dex1][token0][token1].encryptedPrice;
        euint128 price2 = mockPrices[dex2][token0][token1].encryptedPrice;
        
        // Calculate absolute difference using FHE operations
        euint128 diff1 = FHE.sub(price1, price2);
        euint128 diff2 = FHE.sub(price2, price1);
        
        // Return absolute value
        ebool price1Greater = FHE.gt(price1, price2);
        return FHE.select(price1Greater, diff1, diff2);
    }

    /**
     * @dev Register new mock DEX for testing
     * @param dex DEX address
     * @param name DEX name
     * @param dexType DEX type
     */
    function registerMockDEX(
        address dex,
        string calldata name,
        MockDEXType dexType
    ) external {
        _registerMockDEX(dex, name, dexType);
    }

    /**
     * @dev Get all registered mock DEXs
     * @return Array of registered DEX addresses
     */
    function getRegisteredDEXs() external view returns (address[] memory) {
        return registeredDEXs;
    }

    /**
     * @dev Get mock DEX information
     * @param dex DEX address
     * @return name DEX name
     * @return dexType DEX type
     * @return isRegistered Whether DEX is registered
     */
    function getMockDEXInfo(address dex) external view returns (
        string memory name,
        MockDEXType dexType,
        bool isRegistered
    ) {
        return (mockDEXNames[dex], mockDEXTypes[dex], isDEXRegistered[dex]);
    }

    /**
     * @dev Reset all mock prices for testing
     */
    function resetAllMockPrices() external {
        for (uint256 i = 0; i < registeredDEXs.length; i++) {
            // Reset would require iterating through token pairs
            // For simplicity, we'll just mark them as invalid
            // In a real implementation, you'd need a more sophisticated reset mechanism
        }
    }

    /**
     * @dev Get mock system public key for sealing
     * @return Mock system public key
     */
    function getMockSystemPublicKey() external view returns (bytes32) {
        return mockSystemPublicKey;
    }

    /**
     * @dev Internal function to register mock DEX
     */
    function _registerMockDEX(
        address dex,
        string memory name,
        MockDEXType dexType
    ) internal {
        require(dex != address(0), "Invalid DEX address");
        require(!isDEXRegistered[dex], "DEX already registered");
        
        mockDEXTypes[dex] = dexType;
        mockDEXNames[dex] = name;
        isDEXRegistered[dex] = true;
        registeredDEXs.push(dex);
    }

    /**
     * @dev Calculate approximate inverse for encrypted values
     * Note: Simplified due to FHE division limitations
     * @param encryptedPrice Input encrypted price
     * @return Approximate encrypted inverse
     */
    function _calculateApproximateInverse(euint128 encryptedPrice) internal pure returns (euint128) {
        // Simplified approximation since FHE.div is not supported for euint128
        euint128 zero = FHE.asEuint128(0);
        FHE.req(FHE.gt(encryptedPrice, zero));
        
        // Simple threshold-based inverse approximation
        euint128 threshold = FHE.asEuint128(1e18);
        ebool isHighPrice = FHE.gt(encryptedPrice, threshold);
        
        // Return approximate inverse values
        euint128 lowInverse = FHE.asEuint128(1e15);  // For high prices
        euint128 highInverse = FHE.asEuint128(1e21); // For low prices
        
        return FHE.select(isHighPrice, lowInverse, highInverse);
    }

    /**
     * @dev Batch set prices for efficient testing
     * @param dexs Array of DEX addresses
     * @param token0 First token address
     * @param token1 Second token address
     * @param prices Array of prices
     */
    function batchSetMockPrices(
        address[] calldata dexs,
        address token0,
        address token1,
        uint256[] calldata prices
    ) external {
        require(dexs.length == prices.length, "Array length mismatch");
        
        for (uint256 i = 0; i < dexs.length; i++) {
            this.setMockPrice(dexs[i], token0, token1, prices[i]);
        }
    }
}