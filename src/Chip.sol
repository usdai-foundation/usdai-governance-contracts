// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC5267} from "openzeppelin-contracts/contracts/interfaces/IERC5267.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IVotes} from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {
    ERC165Upgradeable
} from "openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable,
    NoncesUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20VotesUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {VotesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/governance/utils/VotesUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";

import {IChip} from "./interfaces/IChip.sol";

/**
 * @title Chip ERC20
 * @author USD.AI Foundation
 */
contract Chip is
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    AccessControlUpgradeable,
    IChip
{
    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Revoke delegate admin role
     */
    bytes32 public constant REVOKE_DELEGATE_ADMIN_ROLE = keccak256("REVOKE_DELEGATE_ADMIN_ROLE");

    /**
     * @notice Transfer admin role
     */
    bytes32 public constant TRANSFER_ADMIN_ROLE = keccak256("TRANSFER_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Immutables                                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai
     */
    IUSDai private immutable _usdai;

    /*------------------------------------------------------------------------*/
    /* Chip ERC20 Constructor                                                 */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param usdai_ Address of USDai contract
     */
    constructor(
        address usdai_
    ) {
        _disableInitializers();

        _usdai = IUSDai(usdai_);
    }

    /*------------------------------------------------------------------------*/
    /* Initializer                                                            */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Chip ERC20 initializer
     * @param initialSupply Initial supply
     * @param treasury Treasury address (receives initial supply)
     * @param admin Admin address
     */
    function initialize(
        uint256 initialSupply,
        address treasury,
        address admin
    ) external initializer {
        __ERC20_init("Chip", "CHIP");
        __ERC20Permit_init("Chip");
        __ERC20Votes_init();
        __AccessControl_init();

        _mint(treasury, initialSupply);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers                                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Check if address is blacklisted
     * @param account Address to check
     */
    function _isBlacklisted(
        address account
    ) internal view {
        if (_usdai.isBlacklisted(account)) revert BlacklistedAddress(account);
    }

    /*------------------------------------------------------------------------*/
    /* Getters                                                                */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IChip
     */
    function isBlacklisted(
        address account
    ) public view returns (bool) {
        return _usdai.isBlacklisted(account);
    }

    /*------------------------------------------------------------------------*/
    /* VotesUpgradeable Overrides                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Current clock value (timestamp)
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Current clock value (timestamp)
     */
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /*------------------------------------------------------------------------*/
    /* ERC20PermitUpgradeable Overrides                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC20PermitUpgradeable
     */
    function nonces(
        address owner
    ) public view virtual override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    /*------------------------------------------------------------------------*/
    /* ERC20Upgradeable Overrides                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        /* Check if transfer is allowed */
        require(totalSupply() == 0 || hasRole(TRANSFER_ADMIN_ROLE, msg.sender), "Transfer not allowed");

        _isBlacklisted(msg.sender);
        _isBlacklisted(from);
        _isBlacklisted(to);

        super._update(from, to, value);
    }

    /*------------------------------------------------------------------------*/
    /* VotesUpgradeable Overrides                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc VotesUpgradeable
     */
    function _delegate(
        address account,
        address delegatee
    ) internal override(VotesUpgradeable) {
        _isBlacklisted(account);
        _isBlacklisted(delegatee);

        super._delegate(account, delegatee);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API                                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IChip
     */
    function revokeDelegate(
        address account
    ) external onlyRole(REVOKE_DELEGATE_ADMIN_ROLE) {
        /* Check if account is blacklisted */
        if (!isBlacklisted(account)) {
            revert InvalidAddress();
        }

        /* Revoke delegate */
        super._delegate(account, address(0));
    }

    /*------------------------------------------------------------------------*/
    /* ERC165                                                                 */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC165Upgradeable
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IChip).interfaceId
            || interfaceId == type(IVotes).interfaceId || interfaceId == type(IERC20Permit).interfaceId
            || interfaceId == type(IERC5267).interfaceId || super.supportsInterface(interfaceId);
    }
}
