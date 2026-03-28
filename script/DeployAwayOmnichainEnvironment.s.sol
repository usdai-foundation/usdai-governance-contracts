// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.33;

import {console} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {OToken} from "src/omnichain/OToken.sol";
import {OAdapter} from "src/omnichain/OAdapter.sol";

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

contract DeployAwayOmnichainEnvironment is Deployer {
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address internal constant CHIP_ADDRESS = 0x0C1c1C109FE34733fca54b82d7B46B75CFb71F6e;
    address internal constant STAKED_CHIP_ADDRESS = 0x0D2d2D20962F2468566F4D1a4DdeB482915C4D4A;
    bytes32 internal constant CHIP_SALT = 0x783b08aa21de056717173f72e04be0e91328a07b00f082be5c69d6c6033fe67d;
    bytes32 internal constant STAKED_CHIP_SALT = 0x783b08aa21de056717173f72e04be0e91328a07b0061a79c75082f7101364696;

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
        // Deploy OToken implemetation
        OToken otokenImpl = new OToken();

        // Prepare Create3 Calldata for OToken CHIP
        if (CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, CHIP_SALT))) != CHIP_ADDRESS) {
            revert InvalidParameter();
        }
        bytes memory otokenChipCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            CHIP_SALT,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(
                    address(otokenImpl),
                    deployer,
                    abi.encodeWithSelector(OToken.initialize.selector, "Chip", "CHIP", admin)
                )
            )
        );

        // Prepare Create3 Calldata for OToken Staked CHIP
        if (CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, STAKED_CHIP_SALT))) != STAKED_CHIP_ADDRESS) {
            revert InvalidParameter();
        }
        bytes memory otokenStakedChipCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            STAKED_CHIP_SALT,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(
                    address(otokenImpl),
                    deployer,
                    abi.encodeWithSelector(OToken.initialize.selector, "Staked Chip", "sCHIP", admin)
                )
            )
        );

        // Prepare Create3 Calldata for CHIP OAdapter
        if (CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, OADAPTER_CHIP_SALT))) != OADAPTER_CHIP_ADDRESS)
        {
            revert InvalidParameter();
        }
        bytes memory oadapterChipCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            OADAPTER_CHIP_SALT,
            abi.encodePacked(type(OAdapter).creationCode, abi.encode(CHIP_ADDRESS, lzEndpoint, admin))
        );

        // Prepare Create3 Calldata for Staked CHIP OAdapter
        if (
            CREATEX.computeCreate3Address(keccak256(abi.encode(deployer, OADAPTER_STAKED_CHIP_SALT)))
                != OADAPTER_STAKED_CHIP_ADDRESS
        ) revert InvalidParameter();
        bytes memory oadapterStakedChipCalldata = abi.encodeWithSelector(
            ICreateX.deployCreate3.selector,
            OADAPTER_STAKED_CHIP_SALT,
            abi.encodePacked(type(OAdapter).creationCode, abi.encode(STAKED_CHIP_ADDRESS, lzEndpoint, admin))
        );

        // Prepare grant role calldata
        bytes memory grantRoleChipCalldata = abi.encodeWithSelector(
            IAccessControl.grantRole.selector, keccak256(bytes("BRIDGE_ADMIN_ROLE")), OADAPTER_CHIP_ADDRESS
        );
        bytes memory grantRoleStakedChipCalldata = abi.encodeWithSelector(
            IAccessControl.grantRole.selector, keccak256(bytes("BRIDGE_ADMIN_ROLE")), OADAPTER_STAKED_CHIP_ADDRESS
        );

        // Print calldata
        console.log("from deployer multisig");
        console.log("target", address(CREATEX));
        console.log("OToken CHIP calldata");
        console.logBytes(otokenChipCalldata);
        console.log("OToken Staked CHIP calldata");
        console.logBytes(otokenStakedChipCalldata);
        console.log("OAdapter CHIP calldata");
        console.logBytes(oadapterChipCalldata);
        console.log("OAdapter Staked CHIP calldata");
        console.logBytes(oadapterStakedChipCalldata);
        console.log("");
        console.log("from admin multisig");
        console.log("target", CHIP_ADDRESS);
        console.log("Grant Bridge Admin Role CHIP calldata");
        console.logBytes(grantRoleChipCalldata);
        console.log("");
        console.log("target", STAKED_CHIP_ADDRESS);
        console.log("Grant Bridge Admin Role Staked CHIP calldata");
        console.logBytes(grantRoleStakedChipCalldata);

        // Log deployment
        _deployment.oTokenChip = CHIP_ADDRESS;
        _deployment.oTokenStakedChip = STAKED_CHIP_ADDRESS;
        _deployment.oAdapterChip = OADAPTER_CHIP_ADDRESS;
        _deployment.oAdapterStakedChip = OADAPTER_STAKED_CHIP_ADDRESS;
    }
}
