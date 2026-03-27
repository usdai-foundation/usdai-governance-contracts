// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {
    ERC165Upgradeable
} from "openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol";
import {
    ERC4626Upgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC5267} from "openzeppelin-contracts/contracts/interfaces/IERC5267.sol";
import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";

import {IStakedChip} from "./interfaces/IStakedChip.sol";
import {IChip} from "./interfaces/IChip.sol";

/**
 * @title StakedChip
 * @notice ERC4626 vault for staking CHIP
 * @author Permian Labs
 */
contract StakedChip is
    ERC165Upgradeable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    IStakedChip
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Amount of shares to lock for initial deposit
     */
    uint128 private constant LOCKED_SHARES = 1e6;

    /**
     * @notice Role for pausing/unpausing the contract
     */
    bytes32 internal constant PAUSE_ADMIN_ROLE = keccak256("PAUSE_ADMIN_ROLE");

    /**
     * @notice Fixed point scale for share price calculations
     */
    uint256 private constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Deposits storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedChip.deposits")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSITS_STORAGE_LOCATION =
        0x54aad2b89cd1cb1eaa0b1b6a26d98f54fa85698ac9e197e6e09b7d10a0f5d800;

    /*------------------------------------------------------------------------*/
    /* Immutables                                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai
     */
    IUSDai private immutable _usdai;

    /**
     * @notice Underlying CHIP token
     */
    IChip private immutable _chip;

    /*------------------------------------------------------------------------*/
    /* Structures                                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @custom:storage-location erc7201:stakedChip.deposits
     */
    struct Deposits {
        uint256 balance;
    }

    /*------------------------------------------------------------------------*/
    /* Constructor                                                            */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param usdai_ Address of USDai token
     * @param chip_ Address of CHIP token
     */
    constructor(
        address usdai_,
        address chip_
    ) {
        _disableInitializers();

        _usdai = IUSDai(usdai_);
        _chip = IChip(chip_);
    }

    /*------------------------------------------------------------------------*/
    /* Initializer                                                            */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the StakedChip contract
     * @param admin Admin address (receives DEFAULT_ADMIN_ROLE)
     */
    function initialize(
        address admin
    ) external initializer {
        __ERC4626_init(_chip);
        __ERC20_init("Staked Chip", "sCHIP");
        __ERC20Permit_init("Staked Chip");
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers                                                              */
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

    /*------------------------------------------------------------------------*/
    /* Internal helpers                                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to ERC-7201 deposits storage
     *
     * @return $ Reference to deposits storage
     */
    function _getDepositsStorage() internal pure returns (Deposits storage $) {
        assembly {
            $.slot := DEPOSITS_STORAGE_LOCATION
        }
    }

    /**
     * @notice CHIP deposit balance in this contract
     * @return CHIP deposit balance
     */
    function _depositBalance() internal view returns (uint256) {
        return _getDepositsStorage().balance;
    }

    /**
     * @notice Compute share price
     * @return Share price
     */
    function _sharePrice() internal view returns (uint256) {
        return totalSupply() == 0 ? FIXED_POINT_SCALE : (_depositBalance() * FIXED_POINT_SCALE) / totalSupply();
    }

    /**
     * @notice Deposit assets
     * @param amount Amount to deposit
     * @param receiver Receiver address
     * @param minShares Minimum shares
     * @return Shares minted
     */
    function _deposit(
        uint256 amount,
        address receiver,
        uint256 minShares
    ) internal whenNotPaused nonReentrant nonZeroUint(amount) nonZeroAddress(receiver) returns (uint256) {
        /* Compute shares */
        uint256 shares = convertToShares(amount);

        /* If shares is 0 or less than min shares, revert */
        if (shares == 0 || shares < minShares) revert InvalidAmount();

        /* If initial deposit, mint locked shares */
        _mintLockedShares();

        /* Mint shares */
        _mint(receiver, shares);

        /* Update deposits balance */
        _getDepositsStorage().balance += amount;

        /* Deposit assets */
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit Deposit */
        emit Deposit(msg.sender, receiver, amount, shares);

        return shares;
    }

    /**
     * @notice Mint shares
     * @param shares Shares to mint
     * @param receiver Receiver address
     * @param maxAmount Maximum amount
     * @return assets Assets minted
     */
    function _mint(
        uint256 shares,
        address receiver,
        uint256 maxAmount
    ) internal whenNotPaused nonReentrant nonZeroUint(shares) nonZeroAddress(receiver) returns (uint256 assets) {
        /* Compute amount */
        uint256 amount = convertToAssets(shares);

        /* If amount is 0 or more than max amount, revert */
        if (amount == 0 || amount > maxAmount) revert InvalidAmount();

        /* If initial deposit, mint locked shares */
        _mintLockedShares();

        /* Mint shares */
        _mint(receiver, shares);

        /* Update deposits balance */
        _getDepositsStorage().balance += amount;

        /* Deposit assets */
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit Deposit */
        emit Deposit(msg.sender, receiver, amount, shares);

        return amount;
    }

    /**
     * @notice Mint locked shares
     */
    function _mintLockedShares() internal {
        if (totalSupply() == 0) _mint(address(0xdead), LOCKED_SHARES);
    }

    /**
     * @notice Check if address is blacklisted and revert if so
     * @param account Address to check
     */
    function _isBlacklisted(
        address account
    ) internal view {
        if (_usdai.isBlacklisted(account)) {
            revert BlacklistedAddress(account);
        }
    }

    /*------------------------------------------------------------------------*/
    /* Getters                                                                */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedChip
     */
    function isBlacklisted(
        address account
    ) public view returns (bool) {
        return _usdai.isBlacklisted(account);
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626 Overrides                                                      */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC4626Upgradeable
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        /* If no shares exist, compute initial deposit shares (subtract locked shares) */
        if (totalSupply() == 0) return assets - LOCKED_SHARES;

        return Math.mulDiv(assets, totalSupply(), _depositBalance(), rounding);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override returns (uint256) {
        /* If no shares exist, compute initial deposit assets (add locked shares cost) */
        if (totalSupply() == 0) return LOCKED_SHARES + shares;

        return Math.mulDiv(shares, _depositBalance(), totalSupply(), rounding);
    }

    /**
     * @inheritdoc IERC4626
     */
    function totalAssets() public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return _getDepositsStorage().balance;
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewRedeem(
        uint256 shares
    ) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        if (totalSupply() == 0) return 0;

        return super.previewRedeem(shares);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewWithdraw(
        uint256 assets
    ) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        if (totalSupply() == 0) return type(uint256).max;

        return super.previewWithdraw(assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override(ERC4626Upgradeable, IERC4626) whenNotPaused returns (uint256 shares) {
        shares = _deposit(assets, receiver, 0);
    }

    /**
     * @inheritdoc IERC4626
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override(ERC4626Upgradeable, IERC4626) whenNotPaused returns (uint256 assets) {
        assets = _mint(shares, receiver, type(uint256).max);
    }

    /**
     * @inheritdoc IERC4626
     */
    function withdraw(
        uint256 amount,
        address receiver,
        address owner
    )
        public
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused
        nonReentrant
        nonZeroUint(amount)
        nonZeroAddress(receiver)
        nonZeroAddress(owner)
        returns (uint256)
    {
        /* Withdraw amount */
        uint256 shares = super.withdraw(amount, receiver, owner);

        /* Update deposits balance */
        _getDepositsStorage().balance -= amount;

        /* Return shares */
        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused
        nonReentrant
        nonZeroUint(shares)
        nonZeroAddress(receiver)
        nonZeroAddress(owner)
        returns (uint256)
    {
        /* Redeem shares */
        uint256 assets = super.redeem(shares, receiver, owner);

        /* Update deposits balance */
        _getDepositsStorage().balance -= assets;

        return assets;
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626 Overload                                                       */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit with slippage protection
     * @dev Slippage control logic will be implemented at a later stage
     * @param amount Amount of assets to deposit
     * @param receiver Receiver of shares
     * @param minShares Minimum shares to receive
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 amount,
        address receiver,
        uint256 minShares
    ) external returns (uint256) {
        return _deposit(amount, receiver, minShares);
    }

    /**
     * @notice Mint with slippage protection
     * @dev Slippage control logic will be implemented at a later stage
     * @param shares Amount of shares to mint
     * @param receiver Receiver of shares
     * @param maxAmount Maximum assets to spend
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver,
        uint256 maxAmount
    ) external returns (uint256) {
        return _mint(shares, receiver, maxAmount);
    }

    /*------------------------------------------------------------------------*/
    /* ERC20Upgradeable Overrides                                             */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC4626Upgradeable
     */
    function decimals()
        public
        view
        virtual
        override(IERC20Metadata, ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return super.decimals();
    }

    /**
     * @notice Override ERC20 _update to enforce blacklist
     * @inheritdoc ERC20Upgradeable
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable) {
        _isBlacklisted(msg.sender);
        _isBlacklisted(from);
        _isBlacklisted(to);

        super._update(from, to, value);
    }

    /*------------------------------------------------------------------------*/
    /* Pause Admin API                                                        */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedChip
     */
    function pause() external onlyRole(PAUSE_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @inheritdoc IStakedChip
     */
    function unpause() external onlyRole(PAUSE_ADMIN_ROLE) {
        _unpause();
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
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC4626).interfaceId
            || interfaceId == type(IStakedChip).interfaceId || interfaceId == type(IERC20Permit).interfaceId
            || interfaceId == type(IERC5267).interfaceId || super.supportsInterface(interfaceId);
    }
}
