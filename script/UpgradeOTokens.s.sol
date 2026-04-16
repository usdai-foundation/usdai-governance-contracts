// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {OToken} from "src/omnichain/OToken.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeOTokens is Deployer {
    function run() public broadcast useDeployment returns (address, address) {
        if (_deployment.oTokenChip == address(0)) revert MissingDependency();
        if (_deployment.oAdapterChip == address(0)) revert MissingDependency();
        if (_deployment.oTokenStakedChip == address(0)) revert MissingDependency();
        if (_deployment.oAdapterStakedChip == address(0)) revert MissingDependency();

        // Deploy OToken implementations
        OToken oTokenChipImpl = new OToken(_deployment.oAdapterChip);
        console.log("Chip OToken implementation", address(oTokenChipImpl));

        OToken oTokenStakedChipImpl = new OToken(_deployment.oAdapterStakedChip);
        console.log("Staked Chip OToken implementation", address(oTokenStakedChipImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.oTokenChip, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin)
                .upgradeAndCall(ITransparentUpgradeableProxy(_deployment.oTokenChip), address(oTokenChipImpl), "");
            console.log("Upgraded proxy %s implementation to: %s\n", _deployment.oTokenChip, address(oTokenChipImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.oTokenChip),
                    address(oTokenChipImpl),
                    ""
                )
            );
        }

        /* Lookup proxy admin */
        proxyAdmin = address(uint160(uint256(vm.load(_deployment.oTokenStakedChip, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin)
                .upgradeAndCall(
                    ITransparentUpgradeableProxy(_deployment.oTokenStakedChip), address(oTokenStakedChipImpl), ""
                );
            console.log(
                "Upgraded proxy %s implementation to: %s\n", _deployment.oTokenStakedChip, address(oTokenStakedChipImpl)
            );
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.oTokenStakedChip),
                    address(oTokenStakedChipImpl),
                    ""
                )
            );
        }

        return (address(oTokenChipImpl), address(oTokenStakedChipImpl));
    }
}
