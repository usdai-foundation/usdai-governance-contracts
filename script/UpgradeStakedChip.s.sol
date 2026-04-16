// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {StakedChip} from "src/StakedChip.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeStakedChip is Deployer {
    function run(
        address usdai
    ) public broadcast useDeployment returns (address) {
        if (_deployment.chip == address(0)) revert MissingDependency();
        if (_deployment.stakedChip == address(0)) revert MissingDependency();

        // Deploy StakedChip implemetation
        StakedChip stakedChipImpl = new StakedChip(usdai, _deployment.chip);
        console.log("StakedChip implementation", address(stakedChipImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.stakedChip, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin)
                .upgradeAndCall(ITransparentUpgradeableProxy(_deployment.stakedChip), address(stakedChipImpl), "");
            console.log("Upgraded proxy %s implementation to: %s\n", _deployment.stakedChip, address(stakedChipImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.stakedChip),
                    address(stakedChipImpl),
                    ""
                )
            );
        }

        return address(stakedChipImpl);
    }
}
