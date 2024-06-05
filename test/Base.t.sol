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
 * @author Permian Labs
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
        vm.startPrank(users.deployer);

        // Deploy mock USDai for blacklist reference
        mockUsdai = new MockUSDai();

        Chip chipImpl = new Chip(address(mockUsdai));
        bytes memory initData = abi.encodeWithSelector(Chip.initialize.selector, 10000 ether, users.deployer);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(chipImpl), users.deployer, initData);
        chip = Chip(address(proxy));
        proxyAdmin = address(
            uint160(
                uint256(
                    vm.load(address(proxy), bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))
                )
            )
        );

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
