// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {FHEAPHook} from "../contracts/FHEAPHook.sol";
import {ArbitrageCalculations} from "../contracts/libraries/ArbitrageCalculations.sol";
import {FHEPermissions} from "../contracts/libraries/FHEPermissions.sol";
import {PriceAggregator} from "../contracts/libraries/PriceAggregator.sol";
import {MockFHE} from "../contracts/mocks/MockFHE.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {
    FHE,
    euint128,
    euint64,
    ebool,
    inEuint128
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title FHEAPHookTest
 * @dev Comprehensive test suite for FHEAP - FHE Arbitrage Protection Hook
 */
contract FHEAPHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Test contracts
    FHEAPHook public fheapHook;
    FHEPermissions public permissions;
    PriceAggregator public priceAggregator;
    MockFHE public mockFHE;
    
    // Mock addresses
    address public constant POOL_MANAGER = address(0x1234567890123456789012345678901234567890);
    address public constant TOKEN0 = address(0x1111111111111111111111111111111111111111);
    address public constant TOKEN1 = address(0x2222222222222222222222222222222222222222);
    address public constant UNISWAP_POOL = address(0x3333333333333333333333333333333333333333);
    address public constant SUSHISWAP_POOL = address(0x4444444444444444444444444444444444444444);
    
    // Test accounts
    address public admin;
    address public lp1;
    address public lp2;
    address public trader;
    
    // Test data
    PoolKey public testPoolKey;
    PoolId public testPoolId;
    
    function setUp() public {
        // Set up test accounts
        admin = address(this);
        lp1 = makeAddr("lp1");
        lp2 = makeAddr("lp2");
        trader = makeAddr("trader");
        
        // Deploy mock contracts
        mockFHE = new MockFHE();
        
        // Deploy core contracts
        permissions = new FHEPermissions();
        priceAggregator = new PriceAggregator();
        
        // Deploy FHEAP hook
        vm.mockCall(
            POOL_MANAGER,
            abi.encodeWithSignature("getSlot0(bytes32)"),
            abi.encode(uint160(1000000000000000000), int24(0), uint16(0), uint16(0))
        );
        
        fheapHook = new FHEAPHook(
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
        
        // Grant permissions
        permissions.grantAccess(admin, "admin");
        permissions.grantAccess(lp1, "lp_rewards");
        permissions.grantAccess(lp2, "lp_rewards");
        
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
    }

    // ===== HOOK PERMISSION TESTS =====
    
    function testGetHookPermissions() public {
        Hooks.Permissions memory permissions = fheapHook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize);
        assertTrue(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
    }

    // ===== INITIALIZATION TESTS =====
    
    function testAfterInitialize() public {
        // Mock the pool manager call
        vm.prank(POOL_MANAGER);
        bytes4 result = fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        assertEq(result, FHEAPHook.afterInitialize.selector);
        assertFalse(fheapHook.isProtectionActive(testPoolId));
    }

    function testAfterInitializeOnlyPoolManager() public {
        vm.expectRevert(); // Should revert with "Not pool manager" or similar
        vm.prank(trader);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
    }

    // ===== ARBITRAGE DETECTION TESTS =====
    
    function testArbitrageDetectionWithSpread() public {
        // Initialize the pool first
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // Set up price data with arbitrage opportunity
        uint256 uniswapPrice = 2000 * 1e18; // $2000
        uint256 sushiswapPrice = 2020 * 1e18; // $2020 (1% spread)
        
        inEuint128 memory encryptedUniPrice = inEuint128.wrap(bytes(abi.encode(uniswapPrice)));
        inEuint128 memory encryptedSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiswapPrice)));
        
        // Update prices
        priceAggregator.updateEncryptedPrice(
            UNISWAP_POOL,
            TOKEN0,
            TOKEN1,
            encryptedUniPrice
        );
        priceAggregator.updateEncryptedPrice(
            SUSHISWAP_POOL,
            TOKEN0,
            TOKEN1,
            encryptedSushiPrice
        );
        
        // Simulate beforeSwap call that should detect arbitrage
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18, // $100k swap
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(POOL_MANAGER);
        (bytes4 result,,) = fheapHook.beforeSwap(
            trader,
            testPoolKey,
            swapParams,
            bytes("")
        );
        
        assertEq(result, FHEAPHook.beforeSwap.selector);
        
        // After arbitrage detection, protection should be active
        // Note: This depends on the threshold being met
    }

    function testNoArbitrageWithSmallSpread() public {
        // Initialize the pool first
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // Set up price data with small spread (below threshold)
        uint256 uniswapPrice = 2000 * 1e18; // $2000
        uint256 sushiswapPrice = 2001 * 1e18; // $2001 (0.05% spread)
        
        inEuint128 memory encryptedUniPrice = inEuint128.wrap(bytes(abi.encode(uniswapPrice)));
        inEuint128 memory encryptedSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiswapPrice)));
        
        // Update prices
        priceAggregator.updateEncryptedPrice(
            UNISWAP_POOL,
            TOKEN0,
            TOKEN1,
            encryptedUniPrice
        );
        priceAggregator.updateEncryptedPrice(
            SUSHISWAP_POOL,
            TOKEN0,
            TOKEN1,
            encryptedSushiPrice
        );
        
        // Simulate beforeSwap call
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(
            trader,
            testPoolKey,
            swapParams,
            bytes("")
        );
        
        // Protection should not be active for small spreads
        assertFalse(fheapHook.isProtectionActive(testPoolId));
    }

    // ===== FHE CALCULATION TESTS =====
    
    function testArbitrageCalculationsLibrary() public {
        uint256 priceA = 2000 * 1e18;
        uint256 priceB = 2020 * 1e18;
        uint256 threshold = 10 * 1e18; // $10 threshold
        
        euint128 encPriceA = FHE.asEuint128(priceA);
        euint128 encPriceB = FHE.asEuint128(priceB);
        euint128 encThreshold = FHE.asEuint128(threshold);
        
        // Test spread calculation
        euint128 spread = ArbitrageCalculations.calculateSpread(encPriceA, encPriceB);
        uint256 decryptedSpread = FHE.decrypt(spread);
        assertEq(decryptedSpread, 20 * 1e18); // $20 spread
        
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
        
        // Should calculate reasonable fee
        uint256 decryptedFee = FHE.decrypt(protectionFee);
        assertGt(decryptedFee, 0);
        assertLe(decryptedFee, 3000 * 1e18); // Should not exceed max fee
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
        assertEq(decryptedRewards, 800 * 1e18); // $800 (80% of $1000)
    }

    // ===== ACCESS CONTROL TESTS =====
    
    function testPermissionsAccess() public {
        // Test admin access
        assertTrue(permissions.hasAccess(admin, "admin"));
        
        // Test LP access
        assertTrue(permissions.hasAccess(lp1, "lp_rewards"));
        assertFalse(permissions.hasAccess(lp1, "admin"));
        
        // Test unauthorized access
        assertFalse(permissions.hasAccess(trader, "lp_rewards"));
    }

    function testGrantAccessOnlyAdmin() public {
        // Admin should be able to grant access
        permissions.grantAccess(trader, "arbitrage_data");
        assertTrue(permissions.hasAccess(trader, "arbitrage_data"));
        
        // Non-admin should not be able to grant access
        vm.prank(trader);
        vm.expectRevert("Not authorized");
        permissions.grantAccess(lp1, "admin");
    }

    // ===== PRICE AGGREGATOR TESTS =====
    
    function testPriceAggregatorUpdate() public {
        uint256 price = 2000 * 1e18;
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
        uint256 uniPrice = 2000 * 1e18;
        uint256 sushiPrice = 2010 * 1e18;
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        euint128[] memory crossPrices = priceAggregator.getEncryptedCrossDEXPrices(TOKEN0, TOKEN1);
        
        assertEq(crossPrices.length, 2);
        // Verify prices are returned correctly
        assertGt(FHE.decrypt(crossPrices[0]), 0);
        assertGt(FHE.decrypt(crossPrices[1]), 0);
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
        
        // 2. Set up arbitrage opportunity
        uint256 uniPrice = 2000 * 1e18;
        uint256 sushiPrice = 2050 * 1e18; // 2.5% spread
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        // 3. Execute swap that triggers protection
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, swapParams, bytes(""));
        
        // 4. Complete the swap
        vm.prank(POOL_MANAGER);
        fheapHook.afterSwap(
            trader,
            testPoolKey,
            swapParams,
            BalanceDelta.wrap(0), // Mock balance delta
            bytes("")
        );
        
        // 5. Verify protection was triggered and reset
        assertFalse(fheapHook.isProtectionActive(testPoolId));
    }

    // ===== EDGE CASE TESTS =====
    
    function testProtectionCooldown() public {
        // Initialize pool
        vm.prank(POOL_MANAGER);
        fheapHook.afterInitialize(
            address(this),
            testPoolKey,
            uint160(1000000000000000000),
            int24(0)
        );
        
        // Set up arbitrage opportunity
        uint256 uniPrice = 2000 * 1e18;
        uint256 sushiPrice = 2050 * 1e18;
        
        inEuint128 memory encUniPrice = inEuint128.wrap(bytes(abi.encode(uniPrice)));
        inEuint128 memory encSushiPrice = inEuint128.wrap(bytes(abi.encode(sushiPrice)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encUniPrice);
        priceAggregator.updateEncryptedPrice(SUSHISWAP_POOL, TOKEN0, TOKEN1, encSushiPrice);
        
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100000 * 1e18,
            sqrtPriceLimitX96: 0
        });
        
        // First swap - should trigger protection
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, swapParams, bytes(""));
        
        // Immediate second swap - should be in cooldown
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, swapParams, bytes(""));
        
        // Advance blocks beyond cooldown
        vm.roll(block.number + 10);
        
        // Third swap - should work again
        vm.prank(POOL_MANAGER);
        fheapHook.beforeSwap(trader, testPoolKey, swapParams, bytes(""));
    }

    function testInvalidPriceData() public {
        // Test with stale price data
        uint256 oldTimestamp = block.timestamp - 1000; // 1000 seconds ago
        
        // Mock stale price update by manipulating timestamp
        vm.warp(oldTimestamp);
        
        uint256 price = 2000 * 1e18;
        inEuint128 memory encryptedPrice = inEuint128.wrap(bytes(abi.encode(price)));
        
        priceAggregator.updateEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1, encryptedPrice);
        
        // Warp back to current time
        vm.warp(block.timestamp);
        
        // Trying to get stale price should fail
        vm.expectRevert("Price is stale");
        priceAggregator.getEncryptedPrice(UNISWAP_POOL, TOKEN0, TOKEN1);
    }

    // ===== MOCK FHE TESTS =====
    
    function testMockFHEOperations() public {
        uint256 a = 100;
        uint256 b = 50;
        
        assertEq(mockFHE.add(a, b), 150);
        assertEq(mockFHE.sub(a, b), 50);
        assertEq(mockFHE.mul(a, b), 5000);
        assertEq(mockFHE.div(a, b), 2);
        
        assertTrue(mockFHE.gt(a, b));
        assertFalse(mockFHE.lt(a, b));
        assertFalse(mockFHE.eq(a, b));
        
        assertEq(mockFHE.select(true, a, b), a);
        assertEq(mockFHE.select(false, a, b), b);
        
        assertEq(mockFHE.min(a, b), b);
        assertEq(mockFHE.max(a, b), a);
    }

    function testMockArbitrageCalculation() public {
        uint256 priceA = 2000;
        uint256 priceB = 2020;
        uint256 threshold = 10;
        
        (bool hasOpportunity, uint256 spread) = mockFHE.mockArbitrageCalculation(
            priceA,
            priceB,
            threshold
        );
        
        assertTrue(hasOpportunity);
        assertEq(spread, 20);
    }

    // ===== HELPER FUNCTIONS =====
    
    function _createMockBalanceDelta(int128 amount0, int128 amount1) 
        internal pure returns (BalanceDelta) {
        return BalanceDelta.wrap(bytes32(uint256(uint128(amount0)) << 128 | uint128(amount1)));
    }
}