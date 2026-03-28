// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import {console} from "forge-std/Script.sol";

import {OLockAdapter} from "src/omnichain/OLockAdapter.sol";

import {Deployer} from "./utils/Deployer.s.sol";

interface ICreateX {
    function computeCreate3Address(
        bytes32 salt
    ) external view returns (address computedAddress);
    function deployCreate3(
        bytes32 salt,
        bytes memory initCode
    ) external payable returns (address newContract);
}

contract DeployHomeOmnichainEnvironment is Deployer {
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address internal constant CHIP_ADDRESS = 0x0C1c1C109FE34733fca54b82d7B46B75CFb71F6e;
    address internal constant STAKED_CHIP_ADDRESS = 0x0D2d2D20962F2468566F4D1a4DdeB482915C4D4A;

    address internal constant OADAPTER_CHIP_ADDRESS = 0xffC1002994B1e9A744036d0abDAefe8356B7cF4e;
    address internal constant OADAPTER_STAKED_CHIP_ADDRESS = 0xffD200386C2297C43d46842e800F67DecEcF75A9;
    bytes32 internal constant OADAPTER_CHIP_SALT = 0x783b08aa21de056717173f72e04be0e91328a07b00aa354762db16d403baf293;
    bytes32 internal constant OADAPTER_STAKED_CHIP_SALT =
        0x783b08aa21de056717173f72e04be0e91328a07b00f93969aec90dc100df076a;

    function run(
        address deployer,
        address lzEndpoint,
        address admin
    ) public broadcast useDeployment {
        // Prepare Create3 Calldata for CHIP OAdapter
        if (CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, OADAPTER_CHIP_SALT))) != OADAPTER_CHIP_ADDRESS)
        {
            revert InvalidParameter();
        }
        bytes memory oadapterChipCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            OADAPTER_CHIP_SALT,
            abi.encodePacked(type(OLockAdapter).creationCode, abi.encode(CHIP_ADDRESS, lzEndpoint, admin))
        );

        // Prepare Create3 Calldata for Staked CHIP OAdapter
        if (
            CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, OADAPTER_STAKED_CHIP_SALT)))
                != OADAPTER_STAKED_CHIP_ADDRESS
        ) revert InvalidParameter();
        bytes memory oadapterStakedChipCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            OADAPTER_STAKED_CHIP_SALT,
            abi.encodePacked(type(OLockAdapter).creationCode, abi.encode(STAKED_CHIP_ADDRESS, lzEndpoint, admin))
        );

        // Print calldata
        console.log("from deployer multisig");
        console.log("target", address(CREATEX));
        console.log("OAdapter CHIP calldata");
        console.logBytes(oadapterChipCalldata);
        console.log("OAdapter Staked CHIP calldata");
        console.logBytes(oadapterStakedChipCalldata);
        console.log("");

        // Log deployment
        _deployment.oAdapterChip = OADAPTER_CHIP_ADDRESS;
        _deployment.oAdapterStakedChip = OADAPTER_STAKED_CHIP_ADDRESS;
    }
}
