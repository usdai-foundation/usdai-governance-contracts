// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";

import {IMintableBurnable} from "../interfaces/IMintableBurnable.sol";

/**
 * @title Omnichain Token
 * @author USD.AI Foundation
 */
contract OToken is
    IMintableBurnable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardTransient,
    AccessControlUpgradeable,
    MulticallUpgradeable
{
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Minter role
     */
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Omnichain Token Constructor
     */
    constructor() {
        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initializer */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param admin Default admin address
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address admin
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __Multicall_init();
        __AccessControl_init();

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Minter API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IMintableBurnable
     */
    function mint(
        address to,
        uint256 amount
    ) external onlyRole(BRIDGE_ADMIN_ROLE) nonReentrant {
        _mint(to, amount);
    }

    /**
     * @inheritdoc IMintableBurnable
     */
    function burn(
        address from,
        uint256 amount
    ) external onlyRole(BRIDGE_ADMIN_ROLE) nonReentrant {
        _burn(from, amount);
    }
}
