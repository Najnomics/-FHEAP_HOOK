// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockFHE
 * @dev Mock FHE operations for local testing without actual encryption
 * Purpose: Enables rapid development and testing without FHE computational overhead
 */
contract MockFHE {
    
    // Mock encrypted values storage
    mapping(bytes32 => uint256) private mockValues;
    mapping(bytes32 => bool) private mockBooleans;
    
    uint256 private nonceCounter = 1;
    
    // Events for debugging
    event MockFHEOperation(string operation, uint256 result, uint256 timestamp);
    event MockFHEComparison(string operation, bool result, uint256 timestamp);

    /**
     * @dev Simulate FHE addition
     * @param a First operand
     * @param b Second operand
     * @return Mock encrypted result
     */
    function add(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Simulate FHE subtraction
     * @param a First operand
     * @param b Second operand
     * @return Mock encrypted result
     */
    function sub(uint256 a, uint256 b) external pure returns (uint256) {
        return a > b ? a - b : 0; // Prevent underflow
    }

    /**
     * @dev Simulate FHE multiplication
     * @param a First operand
     * @param b Second operand
     * @return Mock encrypted result
     */
    function mul(uint256 a, uint256 b) external pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Simulate FHE division
     * @param a Dividend
     * @param b Divisor
     * @return Mock encrypted result
     */
    function div(uint256 a, uint256 b) external pure returns (uint256) {
        require(b != 0, "Division by zero");
        return a / b;
    }

    /**
     * @dev Simulate FHE greater than comparison
     * @param a First operand
     * @param b Second operand
     * @return True if a > b
     */
    function gt(uint256 a, uint256 b) external pure returns (bool) {
        return a > b;
    }

    /**
     * @dev Simulate FHE less than comparison
     * @param a First operand
     * @param b Second operand
     * @return True if a < b
     */
    function lt(uint256 a, uint256 b) external pure returns (bool) {
        return a < b;
    }

    /**
     * @dev Simulate FHE equality comparison
     * @param a First operand
     * @param b Second operand
     * @return True if a == b
     */
    function eq(uint256 a, uint256 b) external pure returns (bool) {
        return a == b;
    }

    /**
     * @dev Simulate FHE select operation (ternary)
     * @param condition Boolean condition
     * @param trueValue Value if condition is true
     * @param falseValue Value if condition is false
     * @return Selected value
     */
    function select(bool condition, uint256 trueValue, uint256 falseValue) 
        external pure returns (uint256) {
        return condition ? trueValue : falseValue;
    }

    /**
     * @dev Simulate FHE minimum operation
     * @param a First operand
     * @param b Second operand
     * @return Minimum value
     */
    function min(uint256 a, uint256 b) external pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Simulate FHE maximum operation
     * @param a First operand
     * @param b Second operand
     * @return Maximum value
     */
    function max(uint256 a, uint256 b) external pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Simulate FHE encryption (asEuint128)
     * @param value Plaintext value to encrypt
     * @return Mock encrypted value
     */
    function asEuint128(uint256 value) external pure returns (uint256) {
        // In mock, encrypted value is just the plaintext
        return value;
    }

    /**
     * @dev Simulate FHE encryption (asEuint64)
     * @param value Plaintext value to encrypt
     * @return Mock encrypted value
     */
    function asEuint64(uint64 value) external pure returns (uint64) {
        return value;
    }

    /**
     * @dev Simulate FHE boolean encryption
     * @param value Boolean value to encrypt
     * @return Mock encrypted boolean
     */
    function asEbool(bool value) external pure returns (bool) {
        return value;
    }

    /**
     * @dev Simulate FHE decryption
     * @param encryptedValue Mock encrypted value
     * @return Decrypted plaintext value
     */
    function decrypt(uint256 encryptedValue) external pure returns (uint256) {
        // In mock, decryption just returns the value
        return encryptedValue;
    }

    /**
     * @dev Simulate FHE requirement check
     * @param condition Encrypted boolean condition
     */
    function req(bool condition) external pure {
        require(condition, "FHE requirement failed");
    }

    /**
     * @dev Simulate FHE data sealing for user
     * @param value Value to seal
     * @param publicKey User's public key
     * @return Sealed data (mock)
     */
    function seal(uint256 value, bytes32 publicKey) external pure returns (bytes memory) {
        // Mock sealing - just encode the value with the public key
        return abi.encodePacked(value, publicKey);
    }

    /**
     * @dev Generate mock encrypted value with unique identifier
     * @param value Plaintext value
     * @return Mock encrypted identifier
     */
    function generateMockEncrypted(uint256 value) external returns (bytes32) {
        bytes32 identifier = keccak256(abi.encodePacked(value, nonceCounter, block.timestamp));
        mockValues[identifier] = value;
        nonceCounter++;
        return identifier;
    }

    /**
     * @dev Get mock encrypted value by identifier
     * @param identifier Mock encrypted identifier
     * @return Stored value
     */
    function getMockValue(bytes32 identifier) external view returns (uint256) {
        return mockValues[identifier];
    }

    /**
     * @dev Set mock boolean value
     * @param identifier Mock encrypted identifier
     * @param value Boolean value to store
     */
    function setMockBoolean(bytes32 identifier, bool value) external {
        mockBooleans[identifier] = value;
    }

    /**
     * @dev Get mock boolean value
     * @param identifier Mock encrypted identifier
     * @return Stored boolean value
     */
    function getMockBoolean(bytes32 identifier) external view returns (bool) {
        return mockBooleans[identifier];
    }

    /**
     * @dev Batch mock operations for testing
     * @param values Array of values to encrypt
     * @return Array of mock encrypted identifiers
     */
    function batchMockEncrypt(uint256[] calldata values) external returns (bytes32[] memory) {
        bytes32[] memory identifiers = new bytes32[](values.length);
        
        for (uint256 i = 0; i < values.length; i++) {
            bytes32 identifier = keccak256(abi.encodePacked(values[i], nonceCounter, block.timestamp, i));
            mockValues[identifier] = values[i];
            identifiers[i] = identifier;
            nonceCounter++;
        }
        
        return identifiers;
    }

    /**
     * @dev Simulate complex FHE arbitrage calculation
     * @param priceA Mock encrypted price A
     * @param priceB Mock encrypted price B
     * @param threshold Mock encrypted threshold
     * @return hasArbitrageOpportunity Mock result
     * @return spread Mock encrypted spread
     */
    function mockArbitrageCalculation(
        uint256 priceA,
        uint256 priceB,
        uint256 threshold
    ) external pure returns (bool hasArbitrageOpportunity, uint256 spread) {
        spread = priceA > priceB ? priceA - priceB : priceB - priceA;
        hasArbitrageOpportunity = spread > threshold;
        return (hasArbitrageOpportunity, spread);
    }

    /**
     * @dev Reset all mock data (for testing)
     */
    function resetMockData() external {
        nonceCounter = 1;
        // Note: mappings cannot be fully cleared in Solidity
        // In a real test environment, this would redeploy the contract
    }
}