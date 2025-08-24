// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    euint128,
    inEuint128
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title IPriceOracle
 * @dev Interface for FHE-enabled price oracle functionality
 */
interface IPriceOracle {
    
    // DEX Types
    enum DEXType {
        UNISWAP_V2,
        UNISWAP_V3,
        SUSHISWAP,
        CURVE,
        BALANCER,
        CUSTOM
    }

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

    // Core Functions
    
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
    ) external;

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
    ) external view returns (euint128);

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
    ) external;

    /**
     * @dev Get encrypted prices from multiple DEXs
     * @param token0 First token address
     * @param token1 Second token address
     * @return Array of encrypted prices from different DEXs
     */
    function getEncryptedCrossDEXPrices(
        address token0,
        address token1
    ) external view returns (euint128[] memory);

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
    ) external view returns (euint128);

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
    ) external;

    /**
     * @dev Remove price oracle
     * @param oracle Oracle address to remove
     */
    function removePriceOracle(address oracle) external;

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
    ) external view returns (uint256);
}