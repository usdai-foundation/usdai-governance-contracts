// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

/**
 * @notice Base deployment script
 */
contract BaseScript is Script {
    /*--------------------------------------------------------------------------*/
    /* State                                                                    */
    /*--------------------------------------------------------------------------*/

    uint256 internal _broadcaster;
    mapping(uint256 => string) internal _chainIdToNetwork;

    /*--------------------------------------------------------------------------*/
    /* Constructor                                                              */
    /*--------------------------------------------------------------------------*/

    constructor() {
        _chainIdToNetwork[31337] = "local";
        _chainIdToNetwork[1] = "mainnet";
        _chainIdToNetwork[11155111] = "sepolia";
        _chainIdToNetwork[421614] = "arbitrum_sepolia";
        _chainIdToNetwork[42161] = "arbitrum";
    }

    modifier broadcast() {
        if (vm.envOr("BROADCAST", false)) {
            vm.startBroadcast();
        } else {
            vm.startPrank(msg.sender);
        }

        _;

        if (vm.envOr("BROADCAST", false)) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }
}
