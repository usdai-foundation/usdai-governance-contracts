// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/**
 * @title IStakedChip
 * @notice Interface for the Staked CHIP (sCHIP) ERC4626 vault
 * @dev Extends ERC4626 with blacklist and bridging capabilities
 */
interface IStakedChip is IERC4626 {
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
    /* Events                                                                 */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Emitted when blacklist status is updated
     * @param account Account address
     * @param isBlacklisted New blacklist status
     */
    event BlacklistUpdated(address indexed account, bool isBlacklisted);

    /*------------------------------------------------------------------------*/
    /* Getters                                                                */
    /*------------------------------------------------------------------------*/

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
    /* Pause Admin API                                                        */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pause the contract
     */
    function pause() external;

    /**
     * @notice Unpause the contract
     */
    function unpause() external;
}
