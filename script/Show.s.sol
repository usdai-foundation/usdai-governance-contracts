// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import {console} from "forge-std/Script.sol";

import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract Show is Deployer {
    function run() public {
        console.log("Printing deployments\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        /* Deserialize */
        _deserialize();

        console.log("Chip:                 %s", _deployment.chip);
        console.log(
            "Chip impl:            %s",
            address(uint160(uint256(vm.load(_deployment.chip, ERC1967Utils.IMPLEMENTATION_SLOT))))
        );
        console.log("ChipGovernor:         %s", _deployment.governor);
        console.log("TimelockController:   %s", _deployment.timelock);

        console.log("StakedChip:           %s", _deployment.stakedChip);
        console.log(
            "StakedChip impl:              %s",
            address(uint160(uint256(vm.load(_deployment.stakedChip, ERC1967Utils.IMPLEMENTATION_SLOT))))
        );

        console.log("\nPrinting deployments completed");
    }
}
