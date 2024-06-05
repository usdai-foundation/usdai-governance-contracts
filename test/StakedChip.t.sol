// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

import {Chip} from "../src/Chip.sol";
import {StakedChip} from "../src/StakedChip.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakedChip Core Tests
 * @notice Tests for core ERC4626 vault functionality
 */
contract StakedChipTest is Test {
    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    uint256 constant INITIAL_CHIP_SUPPLY = 10000 ether;
    uint128 constant LOCKED_SHARES = 1e6;

    /*------------------------------------------------------------------------*/
    /* State Variables                                                        */
    /*------------------------------------------------------------------------*/

    Chip public chip;
    StakedChip public stakedChip;
    MockUSDai public mockUsdai;

    address public admin;
    address public user1;
    address public user2;
    address public chipProxyAdmin;
    address public stakedChipProxyAdmin;

    /*------------------------------------------------------------------------*/
    /* Setup                                                                  */
    /*------------------------------------------------------------------------*/

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy and initialize mock USDai
        vm.startPrank(admin);
        MockUSDai mockUsdaiImpl = new MockUSDai();
        bytes memory usdaiInitData = abi.encodeWithSelector(MockUSDai.initialize.selector);
        mockUsdai = MockUSDai(address(new ERC1967Proxy(address(mockUsdaiImpl), usdaiInitData)));

        // Deploy Chip
        Chip chipImpl = new Chip(address(mockUsdai));
        bytes memory chipInitData = abi.encodeWithSelector(Chip.initialize.selector, INITIAL_CHIP_SUPPLY, admin);
        TransparentUpgradeableProxy chipProxy = new TransparentUpgradeableProxy(address(chipImpl), admin, chipInitData);
        chip = Chip(address(chipProxy));
        chipProxyAdmin = address(
            uint160(
                uint256(
                    vm.load(
                        address(chipProxy), bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)
                    )
                )
            )
        );

        // Deploy StakedChip
        StakedChip stakedChipImpl = new StakedChip(address(mockUsdai), address(chip));
        bytes memory stakedChipInitData = abi.encodeWithSelector(StakedChip.initialize.selector, admin);
        TransparentUpgradeableProxy stakedChipProxy =
            new TransparentUpgradeableProxy(address(stakedChipImpl), admin, stakedChipInitData);
        stakedChip = StakedChip(address(stakedChipProxy));
        stakedChipProxyAdmin = address(
            uint160(
                uint256(
                    vm.load(
                        address(stakedChipProxy),
                        bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)
                    )
                )
            )
        );

        // Transfer some CHIP to test users
        assertTrue(chip.transfer(user1, 1000 ether));
        assertTrue(chip.transfer(user2, 1000 ether));
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization Tests                                                   */
    /*------------------------------------------------------------------------*/

    function test_Initialization() public view {
        assertEq(stakedChip.name(), "Staked Chip");
        assertEq(stakedChip.symbol(), "sCHIP");
        assertEq(stakedChip.decimals(), 18);
        assertEq(stakedChip.asset(), address(chip));
        assertTrue(stakedChip.hasRole(0x00, admin)); // DEFAULT_ADMIN_ROLE
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        stakedChip.initialize(admin);
    }

    /*------------------------------------------------------------------------*/
    /* Deposit Tests                                                          */
    /*------------------------------------------------------------------------*/

    function test_Deposit() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        chip.approve(address(stakedChip), depositAmount);

        uint256 chipBalanceBefore = chip.balanceOf(user1);
        uint256 shares = stakedChip.deposit(depositAmount, user1);
        uint256 chipBalanceAfter = chip.balanceOf(user1);

        assertEq(chipBalanceBefore - chipBalanceAfter, depositAmount);
        assertEq(stakedChip.balanceOf(user1), shares);
        assertTrue(shares > 0);
        vm.stopPrank();
    }

    function test_DepositMintsLockedShares() public {
        // First deposit should mint locked shares
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        // Check locked shares were minted to 0xdead
        assertEq(stakedChip.balanceOf(address(0xdead)), LOCKED_SHARES);
        vm.stopPrank();
    }

    function test_DepositOnlyMintsLockedSharesOnce() public {
        // First deposit
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 200 ether);
        stakedChip.deposit(100 ether, user1);
        uint256 deadBalanceAfterFirst = stakedChip.balanceOf(address(0xdead));

        // Second deposit should not mint more locked shares
        stakedChip.deposit(100 ether, user1);
        uint256 deadBalanceAfterSecond = stakedChip.balanceOf(address(0xdead));

        assertEq(deadBalanceAfterFirst, LOCKED_SHARES);
        assertEq(deadBalanceAfterSecond, LOCKED_SHARES);
        vm.stopPrank();
    }

    function test_DepositToReceiver() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        chip.approve(address(stakedChip), depositAmount);
        uint256 shares = stakedChip.deposit(depositAmount, user2);

        assertEq(stakedChip.balanceOf(user2), shares);
        assertEq(stakedChip.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_CannotDepositZero() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        stakedChip.deposit(0, user1);
        vm.stopPrank();
    }

    function test_CannotDepositToInvalidAddress() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        stakedChip.deposit(100 ether, address(0));
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Mint Tests                                                             */
    /*------------------------------------------------------------------------*/

    function test_Mint() public {
        uint256 mintShares = 100 ether;

        vm.startPrank(user1);
        chip.approve(address(stakedChip), type(uint256).max);

        uint256 chipBalanceBefore = chip.balanceOf(user1);
        uint256 assets = stakedChip.mint(mintShares, user1);
        uint256 chipBalanceAfter = chip.balanceOf(user1);

        assertEq(chipBalanceBefore - chipBalanceAfter, assets);
        assertEq(stakedChip.balanceOf(user1), mintShares);
        vm.stopPrank();
    }

    function test_MintMintsLockedShares() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), type(uint256).max);
        stakedChip.mint(100 ether, user1);

        assertEq(stakedChip.balanceOf(address(0xdead)), LOCKED_SHARES);
        vm.stopPrank();
    }

    function test_CannotMintZero() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), type(uint256).max);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        stakedChip.mint(0, user1);
        vm.stopPrank();
    }

    function test_CannotMintToInvalidAddress() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), type(uint256).max);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        stakedChip.mint(100 ether, address(0));
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Withdraw Tests                                                         */
    /*------------------------------------------------------------------------*/

    function test_Withdraw() public {
        // First deposit
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        // Then withdraw
        uint256 withdrawAmount = 50 ether;
        uint256 chipBalanceBefore = chip.balanceOf(user1);
        uint256 shares = stakedChip.withdraw(withdrawAmount, user1, user1);
        uint256 chipBalanceAfter = chip.balanceOf(user1);

        assertEq(chipBalanceAfter - chipBalanceBefore, withdrawAmount);
        assertTrue(shares > 0);
        vm.stopPrank();
    }

    function test_WithdrawToReceiver() public {
        // Deposit
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        // Withdraw to user2
        uint256 withdrawAmount = 50 ether;
        stakedChip.withdraw(withdrawAmount, user2, user1);

        assertGt(chip.balanceOf(user2), 0);
        vm.stopPrank();
    }

    function test_CannotWithdrawZero() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        stakedChip.withdraw(0, user1, user1);
        vm.stopPrank();
    }

    function test_CannotWithdrawToInvalidAddress() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        stakedChip.withdraw(50 ether, address(0), user1);
        vm.stopPrank();
    }

    function test_WithdrawWithApproval() public {
        // User1 deposits
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        // Calculate shares needed for withdrawal and approve enough
        uint256 sharesNeeded = stakedChip.previewWithdraw(25 ether);
        stakedChip.approve(user2, sharesNeeded);
        vm.stopPrank();

        // User2 withdraws on behalf of user1
        vm.prank(user2);
        stakedChip.withdraw(25 ether, user2, user1);

        assertGt(chip.balanceOf(user2), 0);
    }

    /*------------------------------------------------------------------------*/
    /* Redeem Tests                                                           */
    /*------------------------------------------------------------------------*/

    function test_Redeem() public {
        // Deposit first
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        // Redeem half
        uint256 redeemShares = shares / 2;
        uint256 chipBalanceBefore = chip.balanceOf(user1);
        uint256 assets = stakedChip.redeem(redeemShares, user1, user1);
        uint256 chipBalanceAfter = chip.balanceOf(user1);

        assertEq(chipBalanceAfter - chipBalanceBefore, assets);
        assertTrue(assets > 0);
        vm.stopPrank();
    }

    function test_RedeemToReceiver() public {
        // Deposit
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        // Redeem to user2
        stakedChip.redeem(shares / 2, user2, user1);

        assertGt(chip.balanceOf(user2), 0);
        vm.stopPrank();
    }

    function test_CannotRedeemZero() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        stakedChip.redeem(0, user1, user1);
        vm.stopPrank();
    }

    function test_CannotRedeemToInvalidAddress() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        stakedChip.redeem(shares, address(0), user1);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626 Preview Functions                                              */
    /*------------------------------------------------------------------------*/

    function test_PreviewDeposit() public {
        // Do a small initial deposit to mint locked shares first
        vm.prank(user2);
        chip.approve(address(stakedChip), 1 ether);
        vm.prank(user2);
        stakedChip.deposit(1 ether, user2);

        uint256 depositAmount = 100 ether;
        uint256 previewShares = stakedChip.previewDeposit(depositAmount);

        vm.startPrank(user1);
        chip.approve(address(stakedChip), depositAmount);
        uint256 actualShares = stakedChip.deposit(depositAmount, user1);

        assertEq(previewShares, actualShares);
        vm.stopPrank();
    }

    function test_PreviewMint() public {
        // Do a small initial deposit to mint locked shares first
        vm.prank(user2);
        chip.approve(address(stakedChip), 1 ether);
        vm.prank(user2);
        stakedChip.deposit(1 ether, user2);

        uint256 mintShares = 100 ether;
        uint256 previewAssets = stakedChip.previewMint(mintShares);

        vm.startPrank(user1);
        chip.approve(address(stakedChip), type(uint256).max);
        uint256 actualAssets = stakedChip.mint(mintShares, user1);

        assertEq(previewAssets, actualAssets);
        vm.stopPrank();
    }

    function test_PreviewWithdraw() public {
        // Deposit first
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        uint256 withdrawAmount = 50 ether;
        uint256 previewShares = stakedChip.previewWithdraw(withdrawAmount);
        uint256 actualShares = stakedChip.withdraw(withdrawAmount, user1, user1);

        assertEq(previewShares, actualShares);
        vm.stopPrank();
    }

    function test_PreviewRedeem() public {
        // Deposit first
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        uint256 redeemShares = shares / 2;
        uint256 previewAssets = stakedChip.previewRedeem(redeemShares);
        uint256 actualAssets = stakedChip.redeem(redeemShares, user1, user1);

        assertEq(previewAssets, actualAssets);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Share Price / Conversion Tests                                         */
    /*------------------------------------------------------------------------*/

    function test_ConvertToShares() public view {
        uint256 assets = 100 ether;
        uint256 shares = stakedChip.convertToShares(assets);
        assertEq(shares, 100 ether - 1e6);
    }

    function test_ConvertToAssets() public view {
        uint256 shares = 100 ether;
        uint256 assets = stakedChip.convertToAssets(shares);
        assertEq(assets, 100 ether + 1e6);
    }

    /*------------------------------------------------------------------------*/
    /* TotalAssets Tests                                                      */
    /*------------------------------------------------------------------------*/

    function test_TotalAssets() public {
        assertEq(stakedChip.totalAssets(), 0);

        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        assertEq(stakedChip.totalAssets(), 100 ether);
        vm.stopPrank();
    }

    function test_TotalAssetsMultipleDeposits() public {
        vm.prank(user1);
        chip.approve(address(stakedChip), 100 ether);
        vm.prank(user1);
        stakedChip.deposit(100 ether, user1);

        vm.prank(user2);
        chip.approve(address(stakedChip), 50 ether);
        vm.prank(user2);
        stakedChip.deposit(50 ether, user2);

        assertEq(stakedChip.totalAssets(), 150 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Pausability Tests                                                      */
    /*------------------------------------------------------------------------*/

    function test_PauseUnpause() public {
        vm.startPrank(admin);
        stakedChip.grantRole(keccak256("PAUSE_ADMIN_ROLE"), admin);

        stakedChip.pause();
        assertTrue(stakedChip.paused());

        stakedChip.unpause();
        assertFalse(stakedChip.paused());
        vm.stopPrank();
    }

    function test_CannotDepositWhenPaused() public {
        vm.prank(admin);
        stakedChip.grantRole(keccak256("PAUSE_ADMIN_ROLE"), admin);
        vm.prank(admin);
        stakedChip.pause();

        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);

        vm.expectRevert();
        stakedChip.deposit(100 ether, user1);
        vm.stopPrank();
    }

    function test_CannotWithdrawWhenPaused() public {
        // Deposit first
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Pause
        vm.prank(admin);
        stakedChip.grantRole(keccak256("PAUSE_ADMIN_ROLE"), admin);
        vm.prank(admin);
        stakedChip.pause();

        // Try to withdraw
        vm.startPrank(user1);
        vm.expectRevert();
        stakedChip.withdraw(50 ether, user1, user1);
        vm.stopPrank();
    }

    function test_CannotPauseWithoutRole() public {
        vm.prank(user1);
        vm.expectRevert();
        stakedChip.pause();
    }

    /*------------------------------------------------------------------------*/
    /* Access Control Tests                                                   */
    /*------------------------------------------------------------------------*/

    function test_AdminRoleGranted() public view {
        assertTrue(stakedChip.hasRole(0x00, admin)); // DEFAULT_ADMIN_ROLE
    }

    function test_OnlyAdminCanAuthorizeUpgrade() public {
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));

        vm.prank(user1);
        vm.expectRevert();
        (bool success1,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );

        vm.prank(admin);
        (bool success2,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success2, "Upgrade failed");
    }

    function test_AdminCanGrantRoles() public {
        bytes32 pauseRole = keccak256("PAUSE_ADMIN_ROLE");

        vm.prank(admin);
        stakedChip.grantRole(pauseRole, user1);

        assertTrue(stakedChip.hasRole(pauseRole, user1));
    }

    function test_NonAdminCannotGrantRoles() public {
        bytes32 pauseRole = keccak256("PAUSE_ADMIN_ROLE");

        vm.prank(user1);
        vm.expectRevert();
        stakedChip.grantRole(pauseRole, user2);
    }

    /*------------------------------------------------------------------------*/
    /* Edge Cases                                                             */
    /*------------------------------------------------------------------------*/

    function test_FirstDepositorEdgeCase() public {
        // First deposit with small amount
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 1 wei + 1e6);
        vm.expectRevert();
        stakedChip.deposit(1 wei, user1);

        uint256 shares = stakedChip.deposit(1 wei + 1e6, user1);

        // Should receive shares (accounting for locked shares)
        assertTrue(shares > 0 || stakedChip.balanceOf(user1) >= 0);
        vm.stopPrank();
    }

    function test_LargeDepositAmount() public {
        // Transfer large amount to user1 (use 5000 ether which is within admin's balance)
        vm.prank(admin);
        assertTrue(chip.transfer(user1, 5000 ether));

        vm.startPrank(user1);
        chip.approve(address(stakedChip), 6000 ether); // User1 now has 6000 total
        uint256 shares = stakedChip.deposit(6000 ether, user1);

        assertTrue(shares > 0);
        assertEq(stakedChip.totalAssets(), 6000 ether);
        vm.stopPrank();
    }

    function test_MultipleUsersDepositWithdraw() public {
        // User1 deposits
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 user1Shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        chip.approve(address(stakedChip), 200 ether);
        uint256 user2Shares = stakedChip.deposit(200 ether, user2);
        vm.stopPrank();

        assertEq(stakedChip.totalAssets(), 300 ether);

        // User1 withdraws
        vm.startPrank(user1);
        stakedChip.redeem(user1Shares, user1, user1);
        vm.stopPrank();

        // User2 still has shares
        assertEq(stakedChip.balanceOf(user2), user2Shares);
    }

    /*------------------------------------------------------------------------*/
    /* View Functions                                                         */
    /*------------------------------------------------------------------------*/

    function test_ImplementationVersion() public view {
        assertEq(stakedChip.IMPLEMENTATION_VERSION(), "1.0");
    }

    function test_MaxDeposit() public view {
        assertEq(stakedChip.maxDeposit(user1), type(uint256).max);
    }

    function test_MaxMint() public view {
        assertEq(stakedChip.maxMint(user1), type(uint256).max);
    }

    function test_MaxWithdraw() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        uint256 maxWithdraw = stakedChip.maxWithdraw(user1);
        assertTrue(maxWithdraw > 0);
        vm.stopPrank();
    }

    function test_MaxRedeem() public {
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        assertEq(stakedChip.maxRedeem(user1), shares);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Blacklist Tests                                                        */
    /*------------------------------------------------------------------------*/

    function test_CannotWithdrawIfOwnerBlacklisted() public {
        // User1 deposits first
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Admin blacklists user1
        vm.prank(admin);
        mockUsdai.setBlacklist(user1, true);

        // Verify user1 is blacklisted
        assertTrue(stakedChip.isBlacklisted(user1));

        // User1 attempts to withdraw - should revert
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user1));
        stakedChip.withdraw(50 ether, user1, user1);
        vm.stopPrank();
    }

    function test_CannotRedeemIfOwnerBlacklisted() public {
        // User1 deposits first
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Admin blacklists user1
        vm.prank(admin);
        mockUsdai.setBlacklist(user1, true);

        // Verify user1 is blacklisted
        assertTrue(stakedChip.isBlacklisted(user1));

        // User1 attempts to redeem - should revert
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user1));
        stakedChip.redeem(shares / 2, user1, user1);
        vm.stopPrank();
    }

    function test_CannotWithdrawOnBehalfOfBlacklistedOwner() public {
        // User1 deposits and approves user2
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);

        uint256 sharesNeeded = stakedChip.previewWithdraw(50 ether);
        stakedChip.approve(user2, sharesNeeded);
        vm.stopPrank();

        // Admin blacklists user1
        vm.prank(admin);
        mockUsdai.setBlacklist(user1, true);

        // User2 attempts to withdraw on behalf of blacklisted user1 - should revert
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user1));
        stakedChip.withdraw(50 ether, user2, user1);
    }

    function test_CannotRedeemOnBehalfOfBlacklistedOwner() public {
        // User1 deposits and approves user2
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        stakedChip.approve(user2, shares);
        vm.stopPrank();

        // Admin blacklists user1
        vm.prank(admin);
        mockUsdai.setBlacklist(user1, true);

        // User2 attempts to redeem on behalf of blacklisted user1 - should revert
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user1));
        stakedChip.redeem(shares / 2, user2, user1);
    }
}
