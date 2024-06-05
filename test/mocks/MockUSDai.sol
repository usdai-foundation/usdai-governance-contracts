// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";
import {IMintableBurnable} from "usdai-contracts/src/interfaces/IMintableBurnable.sol";

/**
 * @title Mock USDai ERC20
 * @author MetaStreet Foundation
 */
contract MockUSDai is
    IUSDai,
    IMintableBurnable,
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable,
    AccessControlUpgradeable
{
    /*------------------------------------------------------------------------*/
    /* Constant */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Minter role
     */
    bytes32 internal constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");

    /**
     * @notice Base yield recipient role
     */
    bytes32 internal constant BASE_YIELD_RECIPIENT_ROLE = keccak256("BASE_YIELD_RECIPIENT_ROLE");

    /**
     * @notice Blacklist admin role
     */
    bytes32 internal constant BLACKLIST_ADMIN_ROLE = keccak256("BLACKLIST_ADMIN_ROLE");

    /**
     * @notice Base yield accrual storage location
     * @dev keccak256(abi.encode(uint256(keccak256("USDai.baseYieldAccrual")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant BASE_YIELD_ACCRUAL_STORAGE_LOCATION =
        0xad76c5b481cb106971e0ae4c23a09cb5b1dc9dba5fad96d9694630df5e853900;

    /**
     * @notice Supply cap
     * @dev keccak256(abi.encode(uint256(keccak256("USDai.supply")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant SUPPLY_STORAGE_LOCATION =
        0x5fc387bd350b82c09f22bee4c04d61669980ce519c352560e36bc6144f9cf800;

    /**
     * @notice Blacklist storage location
     * @dev keccak256(abi.encode(uint256(keccak256("USDai.blacklist")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant BLACKLIST_STORAGE_LOCATION =
        0xd21f45001ca28b8905ef527bd860800b2646ce7faf578b00aa2e89af23551500;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USD.ai Constructor
     */
    constructor() {
        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     */
    function initialize() public initializer {
        __ERC20_init("USD.ai", "USDai");
        __ERC20Permit_init("USD.ai");
        __Multicall_init();
        __AccessControl_init();

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Non-zero value modifier
     * @param value Value to check
     */
    modifier nonZeroUint(
        uint256 value
    ) {
        if (value == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Non-zero address modifier
     * @param value Value to check
     */
    modifier nonZeroAddress(
        address value
    ) {
        if (value == address(0)) revert InvalidAddress();
        _;
    }

    /**
     * @notice Not blacklisted modifier
     * @param value Value to check
     */
    modifier notBlacklisted(
        address value
    ) {
        if (_getBlacklistStorage().blacklist[value]) {
            revert BlacklistedAddress(value);
        }
        _;
    }

    /*------------------------------------------------------------------------*/
    /* Getters  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get implementation name
     * @return Implementation name
     */
    function implementationName() external pure returns (string memory) {
        return "Mock USDai";
    }

    /**
     * @notice Get implementation version
     * @return Implementation version
     */
    function implementationVersion() external pure returns (string memory) {
        return "1.0";
    }

    /**
     * @inheritdoc IUSDai
     */
    function swapAdapter() external pure returns (address) {
        return address(0);
    }

    /**
     * @inheritdoc IUSDai
     */
    function baseToken() external pure returns (address) {
        return address(0);
    }

    /**
     * @inheritdoc IUSDai
     */
    function bridgedSupply() public view returns (uint256) {
        return _getSupplyStorage().bridged;
    }

    /**
     * @inheritdoc IUSDai
     */
    function supplyCap() public view returns (uint256) {
        return _getSupplyStorage().cap;
    }

    /**
     * @inheritdoc IUSDai
     */
    function baseYieldAccrued() public view returns (uint256) {
        return _getBaseYieldAccrualStorage().accrued;
    }

    /**
     * @inheritdoc IUSDai
     */
    function isBlacklisted(
        address account
    ) external view returns (bool) {
        return _getBlacklistStorage().blacklist[account];
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to USDai supply storage
     *
     * @return $ Reference to supply storage
     */
    function _getSupplyStorage() internal pure returns (Supply storage $) {
        assembly {
            $.slot := SUPPLY_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to USDai base yield accrual storage
     *
     * @return $ Reference to base yield accrual storage
     */
    function _getBaseYieldAccrualStorage() internal pure returns (BaseYieldAccrual storage $) {
        assembly {
            $.slot := BASE_YIELD_ACCRUAL_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to USDai blacklist storage
     *
     * @return $ Reference to blacklist storage
     */
    function _getBlacklistStorage() internal pure returns (Blacklist storage $) {
        assembly {
            $.slot := BLACKLIST_STORAGE_LOCATION
        }
    }

    /**
     * @notice Deposit
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum USDai amount minimum
     * @param recipient Recipient address
     * @return USDai amount
     */
    function _deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata
    )
        internal
        virtual
        nonZeroUint(depositAmount)
        nonZeroUint(usdaiAmountMinimum)
        nonZeroAddress(recipient)
        returns (uint256)
    {
        /* Transfer token in from sender to this contract */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        uint256 usdaiAmount = IERC20Metadata(depositToken).decimals() == 6 ? depositAmount * 1e12 : depositAmount;

        /* Check that the USDai amount is greater than the minimum */
        if (usdaiAmount < usdaiAmountMinimum) revert InvalidAmount();

        /* Mint to the recipient */
        _mint(recipient, usdaiAmount);

        /* Emit deposited event */
        emit Deposited(msg.sender, recipient, depositToken, depositAmount, usdaiAmountMinimum);

        return usdaiAmount;
    }

    /**
     * @notice Withdraw
     * @param withdrawToken Withdraw token
     * @param usdaiAmount USD.ai amount
     * @param withdrawAmountMinimum Minimum withdraw amount
     * @param recipient Recipient address
     * @return Withdraw amount
     */
    function _withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient,
        bytes calldata
    ) internal nonZeroUint(usdaiAmount) nonZeroUint(withdrawAmountMinimum) nonZeroAddress(recipient) returns (uint256) {
        /* Burn USD.ai tokens */
        _burn(msg.sender, usdaiAmount);

        /* Transfer token output from this contract to the recipient address */
        IERC20(withdrawToken).transfer(recipient, withdrawAmountMinimum);

        /* Emit withdrawn event */
        emit Withdrawn(msg.sender, recipient, withdrawToken, usdaiAmount, withdrawAmountMinimum);

        return withdrawAmountMinimum;
    }

    /*------------------------------------------------------------------------*/
    /* ERC20Upgradeable overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override notBlacklisted(msg.sender) notBlacklisted(from) notBlacklisted(to) {
        super._update(from, to, value);
    }

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient
    ) external returns (uint256) {
        return _deposit(depositToken, depositAmount, usdaiAmountMinimum, recipient, msg.data[0:0]);
    }

    /**
     * @inheritdoc IUSDai
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata data
    ) external returns (uint256) {
        return _deposit(depositToken, depositAmount, usdaiAmountMinimum, recipient, data);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient
    ) external returns (uint256) {
        return _withdraw(withdrawToken, usdaiAmount, withdrawAmountMinimum, recipient, msg.data[0:0]);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient,
        bytes calldata data
    ) external returns (uint256) {
        return _withdraw(withdrawToken, usdaiAmount, withdrawAmountMinimum, recipient, data);
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
    /* Base Yield Recipient API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function harvest() external onlyRole(BASE_YIELD_RECIPIENT_ROLE) returns (uint256) {
        _getBaseYieldAccrualStorage().accrued = 0;

        /* Emit harvested event */
        emit Harvested(0);

        return 0;
    }

    /*------------------------------------------------------------------------*/
    /* Blacklist Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function setBlacklist(
        address account,
        bool isBlacklisted_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getBlacklistStorage().blacklist[account] = isBlacklisted_;

        emit BlacklistUpdated(account, isBlacklisted_);
    }

    /*------------------------------------------------------------------------*/
    /* Base Escrow API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function setRateTiers(
        RateTier[] memory rateTiers
    ) external {
        /* Set rate tiers */
        _getBaseYieldAccrualStorage().rateTiers = rateTiers;

        /* Emit rate tiers set event */
        emit BaseYieldRateTiersSet(rateTiers);
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Set supply cap
     * @param cap Supply cap
     */
    function setSupplyCap(
        uint256 cap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getSupplyStorage().cap = cap;

        /* Emit supply cap set event */
        emit SupplyCapSet(cap);
    }

    /**
     * @notice Convert base token
     * @param amount Amount
     */
    function convertBaseToken(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        /* Emit base token converted event */
        emit BaseTokenConverted(msg.sender, amount);
    }

    /*------------------------------------------------------------------------*/
    /* ERC165 */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC165Upgradeable
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IUSDai).interfaceId
            || interfaceId == type(IMintableBurnable).interfaceId || super.supportsInterface(interfaceId);
    }
}
