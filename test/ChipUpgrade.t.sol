// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {BaseTest} from "./Base.t.sol";

import {Chip} from "src/Chip.sol";
import {
    ITransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeTest is BaseTest {
    function setUp() public override {
        /* Set up */
        BaseTest.setUp();
    }

    function test__Upgrade() external {
        vm.startPrank(users.deployer);

        /* Transfer token to user */
        assertEq(chip.balanceOf(users.user1), 0, "Invalid balance");
        assertTrue(chip.transfer(users.user1, 1 ether), "Transfer failed");
        assertEq(chip.balanceOf(users.user1), 1 ether, "Invalid balance");

        Chip newChipImpl = new Chip(address(mockUsdai));

        /* Upgrade using ProxyAdmin */
        (bool success,) = proxyAdmin.call(
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", address(chip), address(newChipImpl), "")
        );
        assertTrue(success, "Upgrade failed");

        assertEq(chip.balanceOf(users.user1), 1 ether, "Invalid balance");
        assertEq(chip.balanceOf(users.deployer), 10000 ether - 1 ether, "Invalid balance");

        vm.stopPrank();
    }
}
