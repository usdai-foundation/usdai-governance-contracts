// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title IMintableBurnable
 * @notice Interface for bridge mint/burn operations
 * @dev Used by LayerZero OFT adapters for cross-chain token transfers
 */
interface IMintableBurnable {
    /**
     * @notice Mint tokens (called by bridge when tokens arrive from another chain)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(
        address to,
        uint256 amount
    ) external;

    /**
     * @notice Burn tokens (called by bridge when tokens sent to another chain)
     * @param from Source address
     * @param amount Amount to burn
     */
    function burn(
        address from,
        uint256 amount
    ) external;
}
