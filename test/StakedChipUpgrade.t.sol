// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

import {Chip} from "../src/Chip.sol";
import {StakedChip} from "../src/StakedChip.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakedChip Upgrade Tests
 * @notice Tests for UUPS upgrade functionality
 */
contract StakedChipUpgradeTest is Test {
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

        // Deploy mock USDai
        mockUsdai = new MockUSDai();

        // Deploy Chip
        vm.startPrank(admin);
        Chip chipImpl = new Chip(address(mockUsdai));
        bytes memory chipInitData = abi.encodeWithSelector(Chip.initialize.selector, 10000 ether, admin);
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

        // Transfer CHIP to test users
        assertTrue(chip.transfer(user1, 1000 ether));
        assertTrue(chip.transfer(user2, 1000 ether));
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Basic Upgrade Tests                                                    */
    /*------------------------------------------------------------------------*/

    function test_AdminCanUpgrade() public {
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));

        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify upgrade was successful (contract still works)
        assertEq(stakedChip.IMPLEMENTATION_VERSION(), "1.0");
    }

    function test_NonAdminCannotUpgrade() public {
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));

        vm.prank(user1);
        vm.expectRevert();
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
    }

    function test_UpgradeWithData() public {
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));

        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                address(stakedChip),
                address(newImpl),
                abi.encodeWithSignature("paused()")
            )
        );
        assertTrue(success, "Upgrade failed");

        // Verify upgrade was successful
        assertEq(stakedChip.IMPLEMENTATION_VERSION(), "1.0");
    }

    /*------------------------------------------------------------------------*/
    /* Storage Preservation Tests                                             */
    /*------------------------------------------------------------------------*/

    function test_UpgradePreservesBalances() public {
        // User1 deposits
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify balance preserved
        assertEq(stakedChip.balanceOf(user1), shares);
    }

    function test_UpgradePreservesTotalAssets() public {
        // Multiple deposits
        vm.prank(user1);
        chip.approve(address(stakedChip), 100 ether);
        vm.prank(user1);
        stakedChip.deposit(100 ether, user1);

        vm.prank(user2);
        chip.approve(address(stakedChip), 200 ether);
        vm.prank(user2);
        stakedChip.deposit(200 ether, user2);

        uint256 totalAssetsBefore = stakedChip.totalAssets();

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify total assets preserved
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);
    }

    function test_UpgradePreservesRoles() public {
        bytes32 pauseRole = keccak256("PAUSE_ADMIN_ROLE");

        // Grant role before upgrade
        vm.prank(admin);
        stakedChip.grantRole(pauseRole, user1);

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify roles preserved
        assertTrue(stakedChip.hasRole(0x00, admin)); // DEFAULT_ADMIN_ROLE
        assertTrue(stakedChip.hasRole(pauseRole, user1));
    }

    function test_UpgradePreservesLockedShares() public {
        // First deposit mints locked shares
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        uint256 deadBalanceBefore = stakedChip.balanceOf(address(0xdead));

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify locked shares preserved
        assertEq(stakedChip.balanceOf(address(0xdead)), deadBalanceBefore);
    }

    function test_UpgradePreservesPauseState() public {
        // Pause before upgrade
        vm.prank(admin);
        stakedChip.grantRole(keccak256("PAUSE_ADMIN_ROLE"), admin);
        vm.prank(admin);
        stakedChip.pause();

        assertTrue(stakedChip.paused());

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify pause state preserved
        assertTrue(stakedChip.paused());
    }

    function test_UpgradePreservesBridgedSupply() public {
        bytes32 bridgeRole = keccak256("BRIDGE_ADMIN_ROLE");

        // Setup: deposit and burn
        vm.prank(admin);
        stakedChip.grantRole(bridgeRole, admin);

        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        vm.prank(admin);
        stakedChip.burn(user1, shares);

        uint256 bridgedSupplyBefore = stakedChip.bridgedSupply();

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify bridged supply preserved
        assertEq(stakedChip.bridgedSupply(), bridgedSupplyBefore);
    }

    /*------------------------------------------------------------------------*/
    /* Post-Upgrade Functionality Tests                                       */
    /*------------------------------------------------------------------------*/

    function test_CanDepositAfterUpgrade() public {
        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Deposit after upgrade
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        assertTrue(shares > 0);
        vm.stopPrank();
    }

    function test_CanWithdrawAfterUpgrade() public {
        // Deposit before upgrade
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Withdraw after upgrade
        vm.prank(user1);
        uint256 assets = stakedChip.redeem(shares, user1, user1);

        assertTrue(assets > 0);
        assertEq(stakedChip.balanceOf(user1), 0);
    }

    function test_CanTransferAfterUpgrade() public {
        // Deposit before upgrade
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Transfer after upgrade
        vm.prank(user1);
        assertTrue(stakedChip.transfer(user2, shares / 2));

        assertEq(stakedChip.balanceOf(user2), shares / 2);
    }

    function test_AdminFunctionsWorkAfterUpgrade() public {
        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Test pause/unpause
        vm.prank(admin);
        stakedChip.grantRole(keccak256("PAUSE_ADMIN_ROLE"), admin);
        vm.prank(admin);
        stakedChip.pause();
        assertTrue(stakedChip.paused());

        vm.prank(admin);
        stakedChip.unpause();
        assertFalse(stakedChip.paused());
    }

    /*------------------------------------------------------------------------*/
    /* Upgrade to Extended Implementation Tests                               */
    /*------------------------------------------------------------------------*/

    function test_UpgradeToExtendedImplementation() public {
        // Deposit before upgrade
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // Upgrade to extended implementation
        StakedChipExtended newImpl = new StakedChipExtended(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Call new function
        StakedChipExtended extended = StakedChipExtended(address(stakedChip));
        assertEq(extended.newFunction(), "extended");
    }

    /*------------------------------------------------------------------------*/
    /* Multiple Upgrades Test                                                 */
    /*------------------------------------------------------------------------*/

    function test_MultipleUpgrades() public {
        // First deposit
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);
        vm.stopPrank();

        // First upgrade
        StakedChip newImpl1 = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success1,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl1), "")
        );
        assertTrue(success1, "First upgrade failed");

        assertEq(stakedChip.balanceOf(user1), shares);

        // Second upgrade
        StakedChip newImpl2 = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success2,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl2), "")
        );
        assertTrue(success2, "Second upgrade failed");

        assertEq(stakedChip.balanceOf(user1), shares);

        // Third upgrade
        StakedChip newImpl3 = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success3,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl3), "")
        );
        assertTrue(success3, "Third upgrade failed");

        assertEq(stakedChip.balanceOf(user1), shares);
    }

    /*------------------------------------------------------------------------*/
    /* Edge Cases                                                             */
    /*------------------------------------------------------------------------*/

    function test_UpgradeWithNoDeposits() public {
        // Upgrade before any deposits
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // First deposit after upgrade
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        uint256 shares = stakedChip.deposit(100 ether, user1);

        assertTrue(shares > 0);
        vm.stopPrank();
    }

    function test_UpgradeWhilePaused() public {
        // Pause first
        vm.prank(admin);
        stakedChip.grantRole(keccak256("PAUSE_ADMIN_ROLE"), admin);
        vm.prank(admin);
        stakedChip.pause();

        // Upgrade while paused
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Still paused after upgrade
        assertTrue(stakedChip.paused());

        // Can unpause and use normally
        vm.prank(admin);
        stakedChip.unpause();

        vm.startPrank(user1);
        chip.approve(address(stakedChip), 100 ether);
        stakedChip.deposit(100 ether, user1);
        vm.stopPrank();
    }

    function test_UpgradeWithLargeBalances() public {
        // Transfer large amounts (use 5000 ether which is within admin's balance)
        vm.prank(admin);
        assertTrue(chip.transfer(user1, 5000 ether));

        // Large deposit (user1 now has 6000 ether total)
        vm.startPrank(user1);
        chip.approve(address(stakedChip), 6000 ether);
        uint256 shares = stakedChip.deposit(6000 ether, user1);
        vm.stopPrank();

        // Upgrade
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        // Verify large balance preserved
        assertEq(stakedChip.balanceOf(user1), shares);
        assertEq(stakedChip.totalAssets(), 6000 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Implementation Version Test                                            */
    /*------------------------------------------------------------------------*/

    function test_ImplementationVersion() public {
        assertEq(stakedChip.IMPLEMENTATION_VERSION(), "1.0");

        // After upgrade, version should remain "1.0" (same implementation)
        StakedChip newImpl = new StakedChip(address(mockUsdai), address(chip));
        vm.prank(admin);
        (bool success,) = stakedChipProxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(stakedChip), address(newImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        assertEq(stakedChip.IMPLEMENTATION_VERSION(), "1.0");
    }
}

/**
 * @title StakedChipExtended
 * @notice Extended implementation for testing upgrades with new functions
 */
contract StakedChipExtended is StakedChip {
    constructor(
        address usdai_,
        address chip_
    ) StakedChip(usdai_, chip_) {}

    function newFunction() external pure returns (string memory) {
        return "extended";
    }
}

/**
 * @title StakedChipWithYield
 * @notice Implementation with yield strategy for testing
 */
contract StakedChipWithYield is StakedChip {
    uint256 private _yieldAmount;

    constructor(
        address usdai_,
        address chip_
    ) StakedChip(usdai_, chip_) {}

    function setYieldAmount(
        uint256 amount
    ) external {
        _yieldAmount = amount;
    }
}
