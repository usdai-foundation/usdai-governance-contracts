// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
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
import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";

import {IMintableBurnable} from "./interfaces/IMintableBurnable.sol";
import {IChip} from "./interfaces/IChip.sol";

/**
 * @title Chip ERC20
 * @author Permian Labs
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
     * @notice Minter role
     */
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    /**
     * @notice Supply storage location
     * @dev keccak256(abi.encode(uint256(keccak256("Chip.supply")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 internal constant SUPPLY_STORAGE_LOCATION =
        0x25e3ea3bbcfa85dc079d44d06a216d667f5646f959266c4577b71f193d2cc900;

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
     * @param totalSupply Total supply
     * @param admin Admin address (receives DEFAULT_ADMIN_ROLE)
     */
    function initialize(
        uint256 totalSupply,
        address admin
    ) external initializer {
        __ERC20_init("Chip", "CHIP");
        __ERC20Permit_init("Chip");
        __ERC20Votes_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _mint(admin, totalSupply);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers                                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Helper function to get supply storage
     * @return $ Supply storage
     */
    function _getSupplyStorage() internal pure returns (Supply storage $) {
        assembly {
            $.slot := SUPPLY_STORAGE_LOCATION
        }
    }

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

    /**
     * @inheritdoc IChip
     */
    function bridgedSupply() external view returns (uint256) {
        return _getSupplyStorage().bridged;
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
        _isBlacklisted(msg.sender);
        _isBlacklisted(from);
        _isBlacklisted(to);

        super._update(from, to, value);
    }

    /*------------------------------------------------------------------------*/
    /* Minter API                                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IMintableBurnable
     */
    function mint(
        address to,
        uint256 amount
    ) external onlyRole(BRIDGE_ADMIN_ROLE) {
        _mint(to, amount);

        /* Update bridged supply */
        _getSupplyStorage().bridged -= amount;
    }

    /**
     * @inheritdoc IMintableBurnable
     */
    function burn(
        address from,
        uint256 amount
    ) external onlyRole(BRIDGE_ADMIN_ROLE) {
        _burn(from, amount);

        /* Update bridged supply */
        _getSupplyStorage().bridged += amount;
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
            || interfaceId == type(IMintableBurnable).interfaceId || super.supportsInterface(interfaceId);
    }
}
