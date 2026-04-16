// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {Chip} from "src/Chip.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeChip is Deployer {
    function run(
        address usdai
    ) public broadcast useDeployment returns (address) {
        if (_deployment.chip == address(0)) revert MissingDependency();

        // Deploy Chip implemetation
        Chip chipImpl = new Chip(usdai);
        console.log("Chip implementation", address(chipImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.chip, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(_deployment.chip), address(chipImpl), "");
            console.log("Upgraded proxy %s implementation to: %s\n", _deployment.chip, address(chipImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.chip),
                    address(chipImpl),
                    ""
                )
            );
        }

        return address(chipImpl);
    }
}
