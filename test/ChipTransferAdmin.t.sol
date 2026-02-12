// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

import {Chip} from "../src/Chip.sol";
import {IChip} from "../src/interfaces/IChip.sol";

/**
 * @title Chip Transfer Admin Tests
 * @notice Tests for TRANSFER_ADMIN_ROLE functionality in Chip token
 */
contract ChipTransferAdminTest is Test {
    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    uint256 constant INITIAL_SUPPLY = 10_000 ether;
    bytes32 public transferAdminRole;

    /*------------------------------------------------------------------------*/
    /* State Variables                                                        */
    /*------------------------------------------------------------------------*/

    Chip public chip;
    MockUSDai public mockUsdai;

    address public admin;
    address public proxyAdmin;
    address public transferAdmin;
    address public user1;
    address public user2;

    /*------------------------------------------------------------------------*/
    /* Setup                                                                  */
    /*------------------------------------------------------------------------*/

    function setUp() public {
        admin = makeAddr("admin");
        proxyAdmin = makeAddr("proxyAdmin");
        transferAdmin = makeAddr("transferAdmin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(proxyAdmin);

        // Deploy mock USDai
        MockUSDai mockUsdaiImpl = new MockUSDai();
        bytes memory usdaiInitData = abi.encodeWithSelector(MockUSDai.initialize.selector);
        mockUsdai = MockUSDai(address(new ERC1967Proxy(address(mockUsdaiImpl), usdaiInitData)));

        // Deploy Chip with proxyAdmin as the proxy admin and admin as the contract admin
        Chip chipImpl = new Chip(address(mockUsdai));
        bytes memory chipInitData = abi.encodeWithSelector(Chip.initialize.selector, INITIAL_SUPPLY, admin);
        TransparentUpgradeableProxy chipProxy = new TransparentUpgradeableProxy(address(chipImpl), proxyAdmin, chipInitData);
        chip = Chip(address(chipProxy));

        vm.stopPrank();

        // Cache the role to avoid multiple calls
        transferAdminRole = chip.TRANSFER_ADMIN_ROLE();
    }

    /*------------------------------------------------------------------------*/
    /* Initialize Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__InitializeMintWorks() public view {
        // Verify that the initial mint in initialize() worked
        assertEq(chip.totalSupply(), INITIAL_SUPPLY);
        assertEq(chip.balanceOf(admin), INITIAL_SUPPLY);
    }

    function test__InitializeGrantsDefaultAdminRole() public view {
        // Verify that the admin received DEFAULT_ADMIN_ROLE
        assertTrue(chip.hasRole(chip.DEFAULT_ADMIN_ROLE(), admin));
    }

    /*------------------------------------------------------------------------*/
    /* Transfer Restriction Tests - No TRANSFER_ADMIN_ROLE                   */
    /*------------------------------------------------------------------------*/

    function test__AdminCannotTransferWithoutTransferAdminRole() public {
        // Admin has DEFAULT_ADMIN_ROLE but not TRANSFER_ADMIN_ROLE
        vm.prank(admin);
        vm.expectRevert("Transfer not allowed");
        chip.transfer(user1, 100 ether);
    }

    function test__UserCannotTransferWithoutTransferAdminRole() public {
        // First grant TRANSFER_ADMIN_ROLE to admin to set up the test
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // Now user1 has tokens but no TRANSFER_ADMIN_ROLE
        assertEq(chip.balanceOf(user1), 1000 ether);

        // User1 should not be able to transfer
        vm.prank(user1);
        vm.expectRevert("Transfer not allowed");
        chip.transfer(user2, 100 ether);
    }

    function test__ApproveAndTransferFromFailsWithoutTransferAdminRole() public {
        // Set up: give user1 some tokens
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // User1 approves user2 to spend tokens
        vm.prank(user1);
        chip.approve(user2, 500 ether);

        // User2 tries to transferFrom but doesn't have TRANSFER_ADMIN_ROLE
        vm.prank(user2);
        vm.expectRevert("Transfer not allowed");
        chip.transferFrom(user1, user2, 100 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Transfer Success Tests - With TRANSFER_ADMIN_ROLE                     */
    /*------------------------------------------------------------------------*/

    function test__TransferAdminCanTransfer() public {
        // Grant TRANSFER_ADMIN_ROLE to both admin and transferAdmin
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.grantRole(transferAdminRole, transferAdmin);
        // Transfer tokens to transferAdmin
        chip.transfer(transferAdmin, 1000 ether);
        vm.stopPrank();

        // TransferAdmin should be able to transfer
        vm.prank(transferAdmin);
        chip.transfer(user1, 500 ether);

        assertEq(chip.balanceOf(transferAdmin), 500 ether);
        assertEq(chip.balanceOf(user1), 500 ether);
    }

    function test__TransferAdminCanTransferFrom() public {
        // Set up: admin has TRANSFER_ADMIN_ROLE
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, 1000 ether);
        chip.grantRole(transferAdminRole, transferAdmin);
        vm.stopPrank();

        // User1 approves transferAdmin
        vm.prank(user1);
        chip.approve(transferAdmin, 500 ether);

        // TransferAdmin should be able to transferFrom
        vm.prank(transferAdmin);
        chip.transferFrom(user1, user2, 300 ether);

        assertEq(chip.balanceOf(user1), 700 ether);
        assertEq(chip.balanceOf(user2), 300 ether);
    }

    function test__MultipleTransferAdminsCanTransfer() public {
        // Grant TRANSFER_ADMIN_ROLE to multiple addresses
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.grantRole(transferAdminRole, transferAdmin);
        chip.grantRole(transferAdminRole, user1);

        // Distribute tokens
        chip.transfer(transferAdmin, 1000 ether);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // All should be able to transfer
        vm.prank(admin);
        chip.transfer(user2, 500 ether);

        vm.prank(transferAdmin);
        chip.transfer(user2, 500 ether);

        vm.prank(user1);
        chip.transfer(user2, 500 ether);

        assertEq(chip.balanceOf(user2), 1500 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Role Management Tests                                                  */
    /*------------------------------------------------------------------------*/

    function test__GrantTransferAdminRole() public {
        // Admin grants TRANSFER_ADMIN_ROLE to user1
        vm.prank(admin);
        chip.grantRole(transferAdminRole, user1);

        assertTrue(chip.hasRole(transferAdminRole, user1));
    }

    function test__RevokeTransferAdminRole() public {
        // Grant then revoke TRANSFER_ADMIN_ROLE
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.grantRole(transferAdminRole, user1);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // User1 can transfer
        vm.prank(user1);
        chip.transfer(user2, 100 ether);
        assertEq(chip.balanceOf(user2), 100 ether);

        // Revoke role
        vm.prank(admin);
        chip.revokeRole(transferAdminRole, user1);

        // User1 can no longer transfer
        vm.prank(user1);
        vm.expectRevert("Transfer not allowed");
        chip.transfer(user2, 100 ether);
    }

    function test__OnlyDefaultAdminCanGrantTransferAdminRole() public {
        // Non-admin cannot grant TRANSFER_ADMIN_ROLE
        vm.prank(user1);
        vm.expectRevert();
        chip.grantRole(transferAdminRole, user2);
    }

    /*------------------------------------------------------------------------*/
    /* Edge Cases                                                             */
    /*------------------------------------------------------------------------*/

    function test__TransferToSelfRequiresTransferAdminRole() public {
        // Set up: give user1 some tokens
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // User1 cannot transfer to self without role
        vm.prank(user1);
        vm.expectRevert("Transfer not allowed");
        chip.transfer(user1, 100 ether);
    }

    function test__TransferZeroRequiresTransferAdminRole() public {
        // Set up: give user1 some tokens
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // User1 cannot transfer zero without role
        vm.prank(user1);
        vm.expectRevert("Transfer not allowed");
        chip.transfer(user2, 0);
    }

    /*------------------------------------------------------------------------*/
    /* Bridge Admin Integration Tests                                         */
    /*------------------------------------------------------------------------*/

    function test__BridgeAdminMintRequiresTransferAdminToMove() public {
        // Set up: grant roles and transfer tokens to user1 first
        vm.startPrank(admin);
        chip.grantRole(chip.BRIDGE_ADMIN_ROLE(), admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, 1000 ether);

        // Burn tokens to increase bridged supply, then mint back
        chip.burn(user1, 500 ether);
        chip.mint(user1, 500 ether);
        vm.stopPrank();

        assertEq(chip.balanceOf(user1), 1000 ether);

        // User1 cannot transfer minted tokens without TRANSFER_ADMIN_ROLE
        vm.prank(user1);
        vm.expectRevert("Transfer not allowed");
        chip.transfer(user2, 100 ether);
    }

    function test__BridgeAdminBurnRequiresTransferAdminForSetup() public {
        // Set up: give user1 some tokens
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.grantRole(chip.BRIDGE_ADMIN_ROLE(), admin);
        chip.transfer(user1, 1000 ether);
        vm.stopPrank();

        // Bridge admin can burn
        vm.prank(admin);
        chip.burn(user1, 500 ether);

        assertEq(chip.balanceOf(user1), 500 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Fuzz Tests                                                             */
    /*------------------------------------------------------------------------*/

    function testFuzz_TransferAdminCanTransferAnyAmount(
        uint256 amount
    ) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);

        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, amount);
        vm.stopPrank();

        assertEq(chip.balanceOf(user1), amount);
        assertEq(chip.balanceOf(admin), INITIAL_SUPPLY - amount);
    }

    function testFuzz_NonTransferAdminCannotTransferAnyAmount(
        uint256 amount
    ) public {
        amount = bound(amount, 0, INITIAL_SUPPLY);

        // Set up: give user1 some tokens
        vm.startPrank(admin);
        chip.grantRole(transferAdminRole, admin);
        chip.transfer(user1, INITIAL_SUPPLY / 2);
        vm.stopPrank();

        // User1 cannot transfer any amount
        if (amount <= chip.balanceOf(user1)) {
            vm.prank(user1);
            vm.expectRevert("Transfer not allowed");
            chip.transfer(user2, amount);
        }
    }
}
