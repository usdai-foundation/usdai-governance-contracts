// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import {console, stdJson} from "forge-std/Script.sol";

import {BaseScript} from "./Base.s.sol";

contract Deployer is BaseScript {
    /*--------------------------------------------------------------------------*/
    /* Errors                                                                   */
    /*--------------------------------------------------------------------------*/

    error AlreadyDeployed();

    error MissingDependency();

    error InvalidParameter();

    /*--------------------------------------------------------------------------*/
    /* Structures                                                               */
    /*--------------------------------------------------------------------------*/

    struct Deployment {
        address chip;
        address governor;
        address timelock;
        address stakedChip;
    }

    /*--------------------------------------------------------------------------*/
    /* State Variables                                                          */
    /*--------------------------------------------------------------------------*/

    Deployment internal _deployment;

    /*--------------------------------------------------------------------------*/
    /* Modifier                                                                 */
    /*--------------------------------------------------------------------------*/

    /**
     * @dev Add useDeployment modifier to deployment script run() function to
     *      deserialize deployments json and make properties available to read,
     *      write and modify. Changes are re-serialized at end of script.
     */
    modifier useDeployment() {
        console.log("Using deployment:\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        _deserialize();

        _;

        _serialize();

        console.log("Deployment completed\n");
    }

    /*--------------------------------------------------------------------------*/
    /* Internal Helpers                                                         */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Internal helper to get deployment file path for current network
     *
     * @return Path
     */
    function _getJsonFilePath() internal view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/deployments/", _chainIdToNetwork[block.chainid], ".json"));
    }

    /**
     * @notice Internal helper to read and return json string
     *
     * @return Json string
     */
    function _getJson() internal view returns (string memory) {
        string memory path = _getJsonFilePath();

        string memory json = "{}";

        /// forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.readFile(path) returns (string memory _json) {
            json = _json;
        } catch {
            console.log("No json file found at: %s\n", path);
        }

        return json;
    }

    /*--------------------------------------------------------------------------*/
    /* API                                                                      */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Serialize the _deployment storage struct
     */
    function _serialize() internal {
        /* Initialize json string */
        string memory json = "";

        /* Serialize Chip */
        json = stdJson.serialize("", "Chip", _deployment.chip);
        /* Serialize ChipGovernor */
        json = stdJson.serialize("", "ChipGovernor", _deployment.governor);
        /* Serialize TimelockController */
        json = stdJson.serialize("", "TimelockController", _deployment.timelock);
        /* Serialize StakedChip */
        json = stdJson.serialize("", "StakedChip", _deployment.stakedChip);

        console.log("Writing json to file: %s\n", json);
        vm.writeJson(json, _getJsonFilePath());
    }

    /**
     * @notice Deserialize the deployment json
     *
     * @dev Deserialization loads the json into the _deployment struct
     */
    function _deserialize() internal {
        string memory json = _getJson();

        /* Deserialize Chip */
        try vm.parseJsonAddress(json, ".Chip") returns (address chip_) {
            _deployment.chip = chip_;
        } catch {
            console.log("Could not parse Chip");
        }

        /* Deserialize ChipGovernor */
        try vm.parseJsonAddress(json, ".ChipGovernor") returns (address governor_) {
            _deployment.governor = governor_;
        } catch {
            console.log("Could not parse ChipGovernor");
        }

        /* Deserialize TimelockController */
        try vm.parseJsonAddress(json, ".TimelockController") returns (address timelock_) {
            _deployment.timelock = timelock_;
        } catch {
            console.log("Could not parse TimelockController");
        }

        /* Deserialize StakedChip */
        try vm.parseJsonAddress(json, ".StakedChip") returns (address stakedChip_) {
            _deployment.stakedChip = stakedChip_;
        } catch {
            console.log("Could not parse StakedChip");
        }
    }
}
