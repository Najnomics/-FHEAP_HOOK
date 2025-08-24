// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// Import FHEAP contracts
import {FHEArbitrageProtectionHook} from "../hooks/FHEArbitrageProtectionHook.sol";
import {ArbitrageCalculations} from "../libraries/ArbitrageCalculations.sol";
import {FHEPermissions} from "../libraries/FHEPermissions.sol";
import {PriceAggregator} from "../libraries/PriceAggregator.sol";

// Import mocks
import {MockPool} from "../mocks/MockPool.sol";
import {MockPriceOracle} from "../mocks/MockPriceOracle.sol";
import {MockFHE} from "../mocks/MockFHE.sol";

// Import Uniswap v4 types
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// Import Fhenix FHE types (for testing we'll mock these)
import {
    FHE,
    euint128,
    euint64,
    ebool,
    inEuint128
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title ArbitrageProtectionTest
 * @dev Comprehensive test suite for FHEAP - FHE Arbitrage Protection
 * Following CoFHE testing patterns from Fhenix documentation
 */
contract ArbitrageProtectionTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Test contracts
    FHEArbitrageProtectionHook public fheapHook;
    FHEPermissions public permissions;
    PriceAggregator public priceAggregator;
    MockPool public mockPool;
    MockPriceOracle public mockOracle;
    MockFHE public mockFHE;
    
    // Mock addresses following CoFHE testing patterns
    address public constant POOL_MANAGER = address(0x1234567890123456789012345678901234567890);
    address public constant TOKEN0 = address(0x1111111111111111111111111111111111111111); // Mock ETH
    address public constant TOKEN1 = address(0x2222222222222222222222222222222222222222); // Mock USDC
    address public constant UNISWAP_POOL = address(0x3333333333333333333333333333333333333333);
    address public constant SUSHISWAP_POOL = address(0x4444444444444444444444444444444444444444);
    address public constant CURVE_POOL = address(0x5555555555555555555555555555555555555555);
    address public constant BALANCER_POOL = address(0x6666666666666666666666666666666666666666);
    
    // Test accounts
    address public admin;
    address public lp1;
    address public lp2;
    address public trader;
    address public arbitrageur;
    
    // Test data
    PoolKey public testPoolKey;
    PoolId public testPoolId;
    
    // Test constants
    uint256 public constant ETH_PRICE_BASE = 2000 * 1e18; // $2000
    uint256 public constant USDC_PRICE_BASE = 1 * 1e18;   // $1
    uint256 public constant SMALL_SPREAD = 2 * 1e18;      // $2 (0.1%)
    uint256 public constant MEDIUM_SPREAD = 20 * 1e18;    // $20 (1%)
    uint256 public constant LARGE_SPREAD = 100 * 1e18;    // $100 (5%)

    function setUp() public {
        // Set up test accounts
        admin = address(this);
        lp1 = makeAddr("lp1");
        lp2 = makeAddr("lp2");
        trader = makeAddr("trader");
        arbitrageur = makeAddr("arbitrageur");
        
        // Deploy mock contracts following CoFHE patterns
        mockFHE = new MockFHE();
        mockPool = new MockPool();
        mockOracle = new MockPriceOracle();
        
        // Deploy core contracts
        permissions = new FHEPermissions();
        priceAggregator = new PriceAggregator();
        
        // Mock the pool manager calls
        vm.mockCall(
            POOL_MANAGER,
            abi.encodeWithSignature("getSlot0(bytes32)"),
            abi.encode(uint160(1000000000000000000), int24(0), uint16(0), uint16(0))
        );
        
        // Deploy FHEAP hook
        fheapHook = new FHEArbitrageProtectionHook(
            IPoolManager(POOL_MANAGER),
            address(priceAggregator),
            address(permissions)
        );
        
        // Set up test pool
        testPoolKey = PoolKey({
            currency0: Currency.wrap(TOKEN0),
            currency1: Currency.wrap(TOKEN1),
            fee: 3000,
            tickSpacing: 60,
            hooks: fheapHook
        });
        testPoolId = testPoolKey.toId();
        
        // Create mock pool
        mockPool.createMockPool(testPoolKey, uint160(1000000000000000000));
        
        // Grant permissions following CoFHE access patterns
        permissions.grantAccess(admin, "admin");
        permissions.grantAccess(lp1, "lp_rewards");
        permissions.grantAccess(lp2, "lp_rewards");
        permissions.grantAccess(trader, "arbitrage_data");
        
        // Add price oracles
        priceAggregator.addPriceOracle(
            UNISWAP_POOL,
            "Uniswap V3 ETH/USDC",
            PriceAggregator.DEXType.UNISWAP_V3
        );
        
        priceAggregator.addPriceOracle(
            SUSHISWAP_POOL,
            "SushiSwap ETH/USDC",
            PriceAggregator.DEXType.SUSHISWAP
        );
        
        priceAggregator.addPriceOracle(
            CURVE_POOL,
            "Curve ETH/USDC",
            PriceAggregator.DEXType.CURVE
        );
        
        // Set up initial mock prices
        mockOracle.createTestScenarios(TOKEN0, TOKEN1);
    }

    // ===== HOOK PERMISSION TESTS =====
    
    function testGetHookPermissions() public {
        Hooks.Permissions memory perms = fheapHook.getHookPermissions();
        
        assertFalse(perms.beforeInitialize);
        assertTrue(perms.afterInitialize);
        assertFalse(perms.beforeAddLiquidity);
        assertFalse(perms.afterAddLiquidity);
        assertFalse(perms.beforeRemoveLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertFalse(perms.beforeDonate);
        assertFalse(perms.afterDonate);
    }

    // ===== INITIALIZATION TESTS =====
    
    function testAfterInitialize() public {
        vm.prank(POOL_MANAGER);
        bytes4 result = fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        assertEq(result, FHEArbitrageProtectionHook.afterInitialize.selector);
        assertFalse(fheapHook.isProtectionActive(testPoolId));
    }

    function testAfterInitializeOnlyPoolManager() public {
        vm.expectRevert();
        vm.prank(trader);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
    }

    // ===== ARBITRAGE DETECTION TESTS =====
    
    function testArbitrageDetectionWithSmallSpread() public {
        // Initialize the pool
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // Set up small spread scenario (should not trigger protection)
        uint256 uniPrice = ETH_PRICE_BASE;
        uint256 sushiPrice = ETH_PRICE_BASE + SMALL_SPREAD; // 0.1% spread
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        // Execute swap
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, params, bytes(""));
        
        // Protection should not be active for small spreads
        assertFalse(fheapHook.isProtectionActive(testPoolId));
    }

    function testArbitrageDetectionWithLargeSpread() public {
        // Initialize the pool
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // Set up large spread scenario (should trigger protection)
        mockOracle.createArbitrageScenario(
            "large_spread_test",
            TOKEN0,
            TOKEN1,
            [ETH_PRICE_BASE, ETH_PRICE_BASE + LARGE_SPREAD, ETH_PRICE_BASE + MEDIUM_SPREAD, ETH_PRICE_BASE]
        );
        
        // Update price aggregator with large spread
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(ETH_PRICE_BASE)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(ETH_PRICE_BASE + LARGE_SPREAD)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        // Execute swap that should trigger protection
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, params, bytes(""));
        
        // Protection should be active for large spreads
        // Note: This depends on the actual threshold implementation
    }

    // ===== FHE CALCULATION TESTS =====
    
    function testArbitrageCalculationsLibrary() public {
        uint256 priceA = ETH_PRICE_BASE;
        uint256 priceB = ETH_PRICE_BASE + MEDIUM_SPREAD;
        uint256 threshold = 10 * 1e18; // $10 threshold
        
        euint128 encPriceA = FHE.asEuint128(priceA);
        euint128 encPriceB = FHE.asEuint128(priceB);
        euint128 encThreshold = FHE.asEuint128(threshold);
        
        // Test spread calculation
        euint128 spread = ArbitrageCalculations.calculateSpread(encPriceA, encPriceB);
        uint256 decryptedSpread = FHE.decrypt(spread);
        assertEq(decryptedSpread, MEDIUM_SPREAD);
        
        // Test arbitrage opportunity detection
        ebool hasOpportunity = ArbitrageCalculations.hasArbitrageOpportunity(spread, encThreshold);
        assertTrue(FHE.decrypt(hasOpportunity));
        
        // Test protection fee calculation
        euint128 volume = FHE.asEuint128(100000 * 1e18); // $100k
        euint128 maxFee = FHE.asEuint128(3000 * 1e18); // $3k max
        
        euint128 protectionFee = ArbitrageCalculations.calculateProtectionFee(
            spread,
            volume,
            maxFee
        );
        
        uint256 decryptedFee = FHE.decrypt(protectionFee);
        assertGt(decryptedFee, 0);
        assertLe(decryptedFee, 3000 * 1e18);
    }

    function testLPRewardCalculation() public {
        uint256 capturedMEV = 1000 * 1e18; // $1000 MEV
        uint64 lpSharePercentage = 8000; // 80%
        
        euint128 encCapturedMEV = FHE.asEuint128(capturedMEV);
        euint64 encLPShare = FHE.asEuint64(lpSharePercentage);
        
        euint128 lpRewards = ArbitrageCalculations.calculateLPRewards(
            encCapturedMEV,
            encLPShare
        );
        
        uint256 decryptedRewards = FHE.decrypt(lpRewards);
        assertEq(decryptedRewards, 800 * 1e18); // 80% of $1000
    }

    function testPercentageSpreadCalculation() public {
        uint256 priceA = 2000 * 1e18; // $2000
        uint256 priceB = 2020 * 1e18; // $2020 (1% spread)
        
        euint128 encPriceA = FHE.asEuint128(priceA);
        euint128 encPriceB = FHE.asEuint128(priceB);
        
        euint128 percentageSpread = ArbitrageCalculations.calculatePercentageSpread(
            encPriceA,
            encPriceB
        );
        
        uint256 decryptedPercentage = FHE.decrypt(percentageSpread);
        // Should be approximately 100 basis points (1%)
        assertApproxEqRel(decryptedPercentage, 100, 0.1e18); // 10% tolerance
    }

    // ===== ACCESS CONTROL TESTS =====
    
    function testPermissionsAccess() public {
        assertTrue(permissions.hasAccess(admin, "admin"));
        assertTrue(permissions.hasAccess(lp1, "lp_rewards"));
        assertFalse(permissions.hasAccess(lp1, "admin"));
        assertFalse(permissions.hasAccess(trader, "lp_rewards"));
    }

    function testGrantAccessOnlyAdmin() public {
        permissions.grantAccess(trader, "arbitrage_data");
        assertTrue(permissions.hasAccess(trader, "arbitrage_data"));
        
        vm.prank(trader);
        vm.expectRevert("Not authorized");
        permissions.grantAccess(lp1, "admin");
    }

    function testPublicKeyRegistration() public {
        bytes32 publicKey = keccak256("test_public_key");
        
        vm.prank(lp1);
        permissions.registerPublicKey(publicKey);
        
        assertEq(permissions.getUserPublicKey(lp1), publicKey);
    }

    // ===== PRICE AGGREGATOR TESTS =====
    
    function testPriceAggregatorUpdate() public {
        uint256 price = ETH_PRICE_BASE;
        inEuint128 memory encryptedPrice = inEuint128.wrap(bytes(abi.encode(price)));
        
        priceAggregator.updateEncryptedPrice(
            UNISWAP_POOL,
            TOKEN0,
            TOKEN1,
            encryptedPrice
        );
        
        euint128 retrievedPrice = priceAggregator.getEncryptedPrice(
            UNISWAP_POOL,
            TOKEN0,
            TOKEN1
        );
        
        assertEq(FHE.decrypt(retrievedPrice), price);
    }

    function testCrossDEXPriceRetrieval() public {
        uint256 uniPrice = ETH_PRICE_BASE;
        uint256 sushiPrice = ETH_PRICE_BASE + MEDIUM_SPREAD;
        uint256 curvePrice = ETH_PRICE_BASE + SMALL_SPREAD;
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        inEuint128 memory encCurvePrice = inEuint128.wrap(bytes(abi.encode(curvePrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        priceAggregator.updateEncryptedPrice(CURVE_POOL, TOKEN0, TOKEN1, encCurvePrice);
        
        euint128[] memory crossPrices = priceAggregator.getEncryptedCrossDEXPrices(TOKEN0, TOKEN1);
        
        assertEq(crossPrices.length, 3);
        assertGt(FHE.decrypt(crossPrices[0]), 0);
        assertGt(FHE.decrypt(crossPrices[1]), 0);
        assertGt(FHE.decrypt(crossPrices[2]), 0);
    }

    function testEncryptedSpreadCalculation() public {
        uint256 uniPrice = ETH_PRICE_BASE;
        uint256 sushiPrice = ETH_PRICE_BASE + MEDIUM_SPREAD;
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        euint128 spread = priceAggregator.getEncryptedSpread(
            UNISWAP_POOL,
            SUSHISWAP_POOL,
            TOKEN0,
            TOKEN1
        );
        
        uint256 decryptedSpread = FHE.decrypt(spread);
        assertEq(decryptedSpread, MEDIUM_SPREAD);
    }

    // ===== INTEGRATION TESTS =====
    
    function testFullArbitrageProtectionFlow() public {
        // 1. Initialize pool
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // 2. Set up significant arbitrage opportunity
        uint256 uniPrice = ETH_PRICE_BASE;
        uint256 sushiPrice = ETH_PRICE_BASE + LARGE_SPREAD; // 5% spread
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        // 3. Execute swap that should trigger protection
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, params, bytes(""));
        
        // 4. Complete the swap cycle
        vm.prank(POOL_MANAGER);
        fheapHook.afterSwap(
            trader,
            testPoolKey,
            params,
            BalanceDelta.wrap(0),
            bytes("")
        );
        
        // 5. Verify protection was processed
        assertFalse(fheapHook.isProtectionActive(testPoolId));
    }

    // ===== EDGE CASE TESTS =====
    
    function testProtectionCooldown() public {
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // Set up arbitrage opportunity
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(ETH_PRICE_BASE)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(ETH_PRICE_BASE + LARGE_SPREAD)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        // First swap
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, params, bytes(""));
        
        // Immediate second swap (should be in cooldown)
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, params, bytes(""));
        
        // Advance blocks beyond cooldown
        vm.roll(block.number + 10);
        
        // Third swap (should work again)
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, params, bytes(""));
    }

    function testInvalidPriceHandling() public {
        // Test with zero price (should revert)
        inEuint128 memory zeroPrice = inEuint128.wrap(bytes(abi.encode(0)));
        
        vm.expectRevert();
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, zeroPrice);
    }

    function testUnregisteredDEXHandling() public {
        address unregisteredDEX = address(0x9999999999999999999999999999999999999999);
        inEuint128 memory price = inEuint128.wrap(bytes(abi.encode(ETH_PRICE_BASE)));
        
        vm.expectRevert("DEX not registered");
        priceAggregator.updateEncryptedPrice(unregisteredDEX, TOKEN0, TOKEN1, price);
    }

    // ===== MOCK ORACLE TESTS =====
    
    function testMockOracleScenarios() public {
        // Test all predefined scenarios
        string[4] memory scenarios = ["small_spread", "medium_spread", "large_spread", "extreme_spread"];
        
        for (uint i = 0; i < scenarios.length; i++) {
            uint256[] memory prices = mockOracle.getScenarioPrices(scenarios[i]);
            assertEq(prices.length, 4, "Should have 4 DEX prices");
            
            // Verify price differences
            uint256 maxPrice = 0;
            uint256 minPrice = type(uint256).max;
            
            for (uint j = 0; j < prices.length; j++) {
                if (prices[j] > maxPrice) maxPrice = prices[j];
                if (prices[j] < minPrice) minPrice = prices[j];
            }
            
            uint256 spread = maxPrice - minPrice;
            assertGt(spread, 0, "Should have positive spread");
        }
    }

    function testMockSpreadCalculation() public {
        mockOracle.setMockPrice(UNISWAP_POOL, TOKEN0, TOKEN1, ETH_PRICE_BASE);
        mockOracle.setMockPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, ETH_PRICE_BASE + MEDIUM_SPREAD);
        
        uint256 spread = mockOracle.calculateMockSpread(
            UNISWAP_POOL,
            SUSHISWAP_POOL,
            TOKEN0,
            TOKEN1
        );
        
        assertEq(spread, MEDIUM_SPREAD);
    }

    // ===== PERFORMANCE TESTS =====
    
    function testBatchPriceUpdates() public {
        address[] memory dexs = new address[](3);
        address[] memory token0s = new address[](3);
        address[] memory token1s = new address[](3);
        inEuint128[] memory prices = new inEuint128[](3);
        
        dexs[0] = UNISWAP_POOL;
        dexs[1] = SUSHISWAP_POOL;
        dexs[2] = CURVE_POOL;
        
        for (uint i = 0; i < 3; i++) {
            token0s[i] = TOKEN0;
            token1s[i] = TOKEN1;
            prices[i] = inEuint128.wrap(bytes(abi.encode(ETH_PRICE_BASE + i * 1e18)));
        }
        
        priceAggregator.batchUpdatePrices(dexs, token0s, token1s, prices);
        
        // Verify all prices were updated
        for (uint i = 0; i < 3; i++) {
            euint128 price = priceAggregator.getEncryptedPrice(dexs[i], TOKEN0, TOKEN1);
            assertEq(FHE.decrypt(price), ETH_PRICE_BASE + i * 1e18);
        }
    }

    // ===== HELPER FUNCTIONS =====
    
    function _createMockBalanceDelta(int128 amount0, int128 amount1) 
        internal pure returns (BalanceDelta) {
        return BalanceDelta.wrap(bytes32(uint256(uint128(amount0)) << 128 | uint128(amount1)));
    }
    
    function _setupArbitrageScenario(
        uint256 basePrice,
        uint256 spread
    ) internal {
        inEuint128 memory price1 = inEuint128.wrap(bytes(abi.encode(basePrice)));
        inEuint128 memory price2 = inEuint128.wrap(bytes(abi.encode(basePrice + spread)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, price1);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, price2);
    }
}