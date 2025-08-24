// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title MockPool
 * @dev Mock pool contract for testing FHEAP functionality
 * Following CoFHE testing patterns from Fhenix documentation
 */
contract MockPool {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Events following CoFHE mock patterns
    event MockSwapExecuted(
        address indexed trader,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    event MockLiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        uint256 timestamp
    );

    event MockPriceUpdated(
        uint160 newSqrtPriceX96,
        int24 newTick,
        uint256 timestamp
    );

    // Pool state following CoFHE mock state patterns
    struct PoolState {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 protocolFee;
        uint16 lpFee;
        uint128 liquidity;
        bool initialized;
    }

    // Mock liquidity position
    struct LiquidityPosition {
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        uint256 timestamp;
    }

    // State variables
    mapping(PoolId => PoolState) public poolStates;
    mapping(PoolId => mapping(address => LiquidityPosition)) public liquidityPositions;
    mapping(PoolId => uint256) public totalVolume;
    mapping(PoolId => uint256) public totalFees;
    
    // Mock pricing data
    mapping(address => uint256) public tokenPrices; // Token address -> price in wei
    
    // Pool creation tracking
    PoolKey[] public pools;
    mapping(PoolId => bool) public poolExists;

    constructor() {
        // Initialize some mock token prices for testing
        _setMockTokenPrice(address(0x1111111111111111111111111111111111111111), 2000 * 1e18); // Mock ETH
        _setMockTokenPrice(address(0x2222222222222222222222222222222222222222), 1 * 1e18);    // Mock USDC
    }

    /**
     * @dev Create a mock pool following CoFHE testing patterns
     * @param key Pool key containing currencies and parameters
     * @param sqrtPriceX96 Initial price
     * @return poolId The created pool ID
     */
    function createMockPool(
        PoolKey calldata key,
        uint160 sqrtPriceX96
    ) external returns (PoolId poolId) {
        poolId = key.toId();
        require(!poolExists[poolId], "Pool already exists");

        // Initialize pool state 
        poolStates[poolId] = PoolState({
            sqrtPriceX96: sqrtPriceX96,
            tick: _sqrtPriceToTick(sqrtPriceX96),
            protocolFee: 500, // 0.05%
            lpFee: 3000,      // 0.3%
            liquidity: 0,
            initialized: true
        });

        pools.push(key);
        poolExists[poolId] = true;

        emit MockPriceUpdated(sqrtPriceX96, _sqrtPriceToTick(sqrtPriceX96), block.timestamp);
    }

    /**
     * @dev Mock swap execution following CoFHE swap patterns
     * @param poolId Pool to swap in
     * @param zeroForOne Direction of swap
     * @param amountSpecified Amount to swap
     * @return amountOut Amount received
     */
    function mockSwap(
        PoolId poolId,
        bool zeroForOne,
        int256 amountSpecified
    ) external returns (uint256 amountOut) {
        require(poolExists[poolId], "Pool does not exist");
        
        PoolState storage state = poolStates[poolId];
        require(state.initialized, "Pool not initialized");

        uint256 amountIn = uint256(amountSpecified < 0 ? -amountSpecified : amountSpecified);
        
        // Simple mock pricing: apply fee and simulate price impact
        uint256 feeAmount = (amountIn * state.lpFee) / 1000000;
        amountOut = amountIn - feeAmount;
        
        // Simulate price impact (1% for testing)
        amountOut = (amountOut * 99) / 100;

        // Update pool state with mock price change
        if(zeroForOne) {
            state.sqrtPriceX96 = uint160((uint256(state.sqrtPriceX96) * 99) / 100); // Price decreases
        } else {
            state.sqrtPriceX96 = uint160((uint256(state.sqrtPriceX96) * 101) / 100); // Price increases
        }
        state.tick = _sqrtPriceToTick(state.sqrtPriceX96);

        // Update statistics
        totalVolume[poolId] += amountIn;
        totalFees[poolId] += feeAmount;

        // Get pool currencies for event (simplified)
        address tokenIn = zeroForOne ? address(0x1111111111111111111111111111111111111111) : 
                                     address(0x2222222222222222222222222222222222222222);
        address tokenOut = zeroForOne ? address(0x2222222222222222222222222222222222222222) : 
                                      address(0x1111111111111111111111111111111111111111);

        emit MockSwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, block.timestamp);
        emit MockPriceUpdated(state.sqrtPriceX96, state.tick, block.timestamp);
    }

    /**
     * @dev Add mock liquidity following CoFHE liquidity patterns
     * @param poolId Pool to add liquidity to
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @return liquidity Liquidity minted
     */
    function addMockLiquidity(
        PoolId poolId,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint128 liquidity) {
        require(poolExists[poolId], "Pool does not exist");
        
        // Simple liquidity calculation (geometric mean)
        liquidity = uint128(_sqrt(amount0 * amount1));
        
        // Update pool state
        poolStates[poolId].liquidity += liquidity;
        
        // Update user position
        LiquidityPosition storage position = liquidityPositions[poolId][msg.sender];
        position.liquidity += liquidity;
        position.amount0 += amount0;
        position.amount1 += amount1;
        position.timestamp = block.timestamp;

        emit MockLiquidityAdded(msg.sender, amount0, amount1, liquidity, block.timestamp);
    }

    /**
     * @dev Get pool state following CoFHE state access patterns
     * @param poolId Pool ID
     * @return sqrtPriceX96 Current price
     * @return tick Current tick
     * @return protocolFee Protocol fee
     * @return lpFee LP fee
     */
    function getSlot0(PoolId poolId) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 protocolFee,
        uint16 lpFee
    ) {
        PoolState memory state = poolStates[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    /**
     * @dev Get mock price for arbitrage testing
     * @param poolId Pool ID
     * @return price Mock price for testing arbitrage detection
     */
    function getMockPrice(PoolId poolId) external view returns (uint256 price) {
        require(poolExists[poolId], "Pool does not exist");
        
        PoolState memory state = poolStates[poolId];
        // Convert sqrtPriceX96 to regular price (simplified)
        price = (uint256(state.sqrtPriceX96) * uint256(state.sqrtPriceX96)) >> 192;
    }

    /**
     * @dev Set price manually for testing arbitrage scenarios
     * @param poolId Pool ID
     * @param newSqrtPriceX96 New price to set
     */
    function setMockPrice(PoolId poolId, uint160 newSqrtPriceX96) external {
        require(poolExists[poolId], "Pool does not exist");
        
        poolStates[poolId].sqrtPriceX96 = newSqrtPriceX96;
        poolStates[poolId].tick = _sqrtPriceToTick(newSqrtPriceX96);
        
        emit MockPriceUpdated(newSqrtPriceX96, _sqrtPriceToTick(newSqrtPriceX96), block.timestamp);
    }

    /**
     * @dev Set mock token price for arbitrage testing
     * @param token Token address
     * @param price Price in wei
     */
    function setMockTokenPrice(address token, uint256 price) external {
        _setMockTokenPrice(token, price);
    }

    /**
     * @dev Get mock token price
     * @param token Token address
     * @return price Token price in wei
     */
    function getMockTokenPrice(address token) external view returns (uint256 price) {
        return tokenPrices[token];
    }

    /**
     * @dev Simulate arbitrage opportunity by setting different prices
     * @param poolId1 First pool ID
     * @param poolId2 Second pool ID  
     * @param price1 Price for first pool
     * @param price2 Price for second pool
     */
    function createArbitrageOpportunity(
        PoolId poolId1,
        PoolId poolId2,
        uint160 price1,
        uint160 price2
    ) external {
        require(poolExists[poolId1] && poolExists[poolId2], "Pools must exist");
        
        setMockPrice(poolId1, price1);
        setMockPrice(poolId2, price2);
    }

    /**
     * @dev Get all pools for testing
     * @return allPools Array of all pool keys
     */
    function getAllPools() external view returns (PoolKey[] memory allPools) {
        return pools;
    }

    /**
     * @dev Get pool statistics for testing
     * @param poolId Pool ID
     * @return volume Total volume
     * @return fees Total fees
     * @return liquidity Current liquidity
     */
    function getPoolStats(PoolId poolId) external view returns (
        uint256 volume,
        uint256 fees,
        uint128 liquidity
    ) {
        return (
            totalVolume[poolId],
            totalFees[poolId],
            poolStates[poolId].liquidity
        );
    }

    /**
     * @dev Get liquidity position for user
     * @param poolId Pool ID
     * @param user User address
     * @return position Liquidity position details
     */
    function getLiquidityPosition(
        PoolId poolId,
        address user
    ) external view returns (LiquidityPosition memory position) {
        return liquidityPositions[poolId][user];
    }

    /**
     * @dev Reset pool for testing
     * @param poolId Pool ID
     */
    function resetPool(PoolId poolId) external {
        require(poolExists[poolId], "Pool does not exist");
        
        delete poolStates[poolId];
        totalVolume[poolId] = 0;
        totalFees[poolId] = 0;
    }

    // Internal helper functions

    function _setMockTokenPrice(address token, uint256 price) internal {
        tokenPrices[token] = price;
    }

    function _sqrtPriceToTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // Simplified tick calculation for testing
        // In production, this would use complex logarithmic calculations
        if (sqrtPriceX96 > 1000000000000000000) { // ~1.0 price
            tick = int24(int256((uint256(sqrtPriceX96) - 1000000000000000000) / 1000000000000000));
        } else {
            tick = -int24(int256((1000000000000000000 - uint256(sqrtPriceX96)) / 1000000000000000));
        }
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}