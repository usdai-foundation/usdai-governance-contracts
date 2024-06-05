// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IMintableBurnable} from "./IMintableBurnable.sol";

/**
 * @title IChip
 * @notice Interface for the CHIP ERC20 token
 * @author Permian Labs
 */
interface IChip is IERC20, IMintableBurnable {
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
    /* Structures                                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @custom:storage-location erc7201:Chip.supply
     */
    struct Supply {
        uint256 bridged;
    }

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

    /**
     * @notice Get bridged supply (tokens on other chains)
     * @return Amount of tokens bridged to other chains
     */
    function bridgedSupply() external view returns (uint256);
}
