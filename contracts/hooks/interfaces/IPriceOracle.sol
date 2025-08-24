// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    euint128,
    inEuint128
} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title IPriceOracle
 * @dev Interface for FHE-enabled price oracle functionality
 * Following CoFHE oracle patterns from Fhenix documentation
 */
interface IPriceOracle {
    
    // DEX Types following CoFHE enumeration patterns
    enum DEXType {
        UNISWAP_V2,
        UNISWAP_V3,
        SUSHISWAP,
        CURVE,
        BALANCER,
        CUSTOM
    }

    // Events following CoFHE event patterns with encrypted data
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
        DEXType dexType,
        uint256 timestamp
    );

    event OracleRemoved(
        address indexed oracle,
        uint256 timestamp
    );

    // Core Functions following CoFHE price oracle patterns
    
    /**
     * @dev Update encrypted price for a specific pool
     * @param dex DEX contract address
     * @param token0 First token address
     * @param token1 Second token address
     * @param encryptedPrice Encrypted price data following CoFHE input patterns
     */
    function updateEncryptedPrice(
        address dex,
        address token0,
        address token1,
        inEuint128 calldata encryptedPrice
    ) external;

    /**
     * @dev Get encrypted price spread between two pools using FHE operations
     * @param poolA First pool address
     * @param poolB Second pool address
     * @param token0 First token address
     * @param token1 Second token address
     * @return Encrypted price spread following CoFHE calculation patterns
     */
    function getEncryptedSpread(
        address poolA,
        address poolB,
        address token0,
        address token1
    ) external view returns (euint128);

    /**
     * @dev Batch update multiple pool prices following CoFHE batch patterns
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
     * @dev Get encrypted prices from multiple DEXs for cross-DEX arbitrage analysis
     * @param token0 First token address
     * @param token1 Second token address
     * @return Array of encrypted prices from different DEXs following CoFHE array patterns
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
     * @return Encrypted price following CoFHE data access patterns
     */
    function getEncryptedPrice(
        address dex,
        address token0,
        address token1
    ) external view returns (euint128);

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
    ) external;

    /**
     * @dev Remove price oracle following CoFHE oracle management patterns
     * @param oracle Oracle address to remove
     */
    function removePriceOracle(address oracle) external;

    /**
     * @dev Get price age in seconds for staleness checking
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

    /**
     * @dev Get all registered DEX addresses for a specific type
     * @param dexType Type of DEX
     * @return Array of DEX addresses
     */
    function getDEXsByType(DEXType dexType) external view returns (address[] memory);

    /**
     * @dev Check if price data is fresh (not stale)
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @return True if price is fresh following CoFHE validation patterns
     */
    function isPriceFresh(
        address dex,
        address token0,
        address token1
    ) external view returns (bool);

    /**
     * @dev Get encrypted price with sealed data for authorized access
     * @param dex DEX address
     * @param token0 First token address
     * @param token1 Second token address
     * @param publicKey User's public key for sealing
     * @return Sealed encrypted price data following CoFHE sealing patterns
     */
    function getSealedPrice(
        address dex,
        address token0,
        address token1,
        bytes32 publicKey
    ) external view returns (bytes memory);

    /**
     * @dev Emergency pause all price updates following CoFHE emergency patterns
     */
    function emergencyPause() external;

    /**
     * @dev Get total number of authorized price updaters
     * @return Number of authorized updaters
     */
    function getAuthorizedUpdaterCount() external view returns (uint256);
}