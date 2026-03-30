// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IUSDai} from "usdai-contracts/src/interfaces/IUSDai.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

import {Chip} from "../src/Chip.sol";

/**
 * @title Base test setup
 * @author USD.AI Foundation
 * @author Modified from https://github.com/PaulRBerg/prb-proxy/blob/main/test/Base.t.sol
 *
 * @dev Sets up users and token contracts
 */
abstract contract BaseTest is Test {
    /**
     * @notice User accounts
     */
    struct Users {
        address payable deployer;
        address payable user1;
        address payable user2;
    }

    Users internal users;
    Chip internal chip;
    MockUSDai internal mockUsdai;
    address internal proxyAdmin;

    function setUp() public virtual {
        users = Users({deployer: createUser("deployer"), user1: createUser("user1"), user2: createUser("user2")});

        deployChip();
    }

    function deployChip() internal {
        // Create a separate proxy admin address
        address proxyAdminAddr = makeAddr("proxyAdmin");

        vm.startPrank(proxyAdminAddr);

        // Deploy mock USDai for blacklist reference
        mockUsdai = new MockUSDai();

        Chip chipImpl = new Chip(address(mockUsdai));
        bytes memory initData =
            abi.encodeWithSelector(Chip.initialize.selector, 10000 ether, users.deployer, users.deployer);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(chipImpl), proxyAdminAddr, initData);
        chip = Chip(address(proxy));
        proxyAdmin = address(
            uint160(
                uint256(
                    vm.load(address(proxy), bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))
                )
            )
        );

        vm.stopPrank();

        // Transfer ProxyAdmin ownership to deployer so they can upgrade
        vm.prank(proxyAdminAddr);
        (bool success,) = proxyAdmin.call(abi.encodeWithSignature("transferOwnership(address)", users.deployer));
        require(success, "Failed to transfer ProxyAdmin ownership");

        // Grant TRANSFER_ADMIN_ROLE to all test users (from the contract admin, not proxy admin)
        vm.startPrank(users.deployer);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), users.deployer);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), users.user1);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), users.user2);
        vm.stopPrank();
    }

    function createUser(
        string memory name
    ) internal returns (address payable addr) {
        addr = payable(makeAddr(name));
        vm.label({account: addr, newLabel: name});
        vm.deal({account: addr, newBalance: 100 ether});
    }
}
