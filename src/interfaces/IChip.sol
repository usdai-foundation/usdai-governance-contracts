// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IChip
 * @notice Interface for the CHIP ERC20 token
 * @author USD.AI Foundation
 */
interface IChip is IERC20 {
    /*------------------------------------------------------------------------*/
    /* Errors                                                                 */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Blacklisted address
     * @param value Address
     */
    error BlacklistedAddress(address value);

    /*------------------------------------------------------------------------*/
    /* Getters                                                                */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get implementation version
     * @return Version string
     */
    function IMPLEMENTATION_VERSION() external pure returns (string memory);

    /**
     * @notice Check if an address is blacklisted
     * @dev Checks both local blacklist and USDai blacklist
     * @param account Address to check
     * @return True if address is blacklisted
     */
    function isBlacklisted(
        address account
    ) external view returns (bool);

    /*------------------------------------------------------------------------*/
    /* Permissioned API                                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Revoke delegate
     * @param account Delegatee address to revoke
     */
    function revokeDelegate(
        address account
    ) external;
}
