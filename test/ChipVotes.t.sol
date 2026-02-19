// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

import {IVotes} from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

import {Chip} from "../src/Chip.sol";
import {IChip} from "../src/interfaces/IChip.sol";

/**
 * @title Chip Voting Tests
 * @notice Tests for ERC20Votes functionality in Chip token
 */
contract ChipVotesTest is Test {
    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    uint256 constant INITIAL_SUPPLY = 10_000 ether;

    /*------------------------------------------------------------------------*/
    /* State Variables                                                        */
    /*------------------------------------------------------------------------*/

    Chip public chip;
    MockUSDai public mockUsdai;

    address public admin;
    address public user1;
    address public user2;
    address public user3;

    /*------------------------------------------------------------------------*/
    /* Setup                                                                  */
    /*------------------------------------------------------------------------*/

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        address proxyAdmin = makeAddr("proxyAdmin");
        vm.startPrank(proxyAdmin);

        // Deploy mock USDai
        MockUSDai mockUsdaiImpl = new MockUSDai();
        bytes memory usdaiInitData = abi.encodeWithSelector(MockUSDai.initialize.selector);
        mockUsdai = MockUSDai(address(new ERC1967Proxy(address(mockUsdaiImpl), usdaiInitData)));

        // Deploy Chip
        Chip chipImpl = new Chip(address(mockUsdai));
        bytes memory chipInitData = abi.encodeWithSelector(Chip.initialize.selector, INITIAL_SUPPLY, admin, admin);
        TransparentUpgradeableProxy chipProxy =
            new TransparentUpgradeableProxy(address(chipImpl), proxyAdmin, chipInitData);
        chip = Chip(address(chipProxy));

        // Grant admin role on mockUsdai for blacklist tests
        mockUsdai.grantRole(mockUsdai.DEFAULT_ADMIN_ROLE(), admin);

        vm.stopPrank();

        // Grant TRANSFER_ADMIN_ROLE and transfer tokens to test users
        vm.startPrank(admin);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), admin);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), user1);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), user2);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), user3);
        chip.transfer(user1, 1000 ether);
        chip.transfer(user2, 1000 ether);
        chip.transfer(user3, 500 ether);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Clock Mode Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__ClockReturnsTimestamp() public view {
        assertEq(chip.clock(), uint48(block.timestamp));
    }

    function test__ClockModeReturnsTimestamp() public view {
        assertEq(chip.CLOCK_MODE(), "mode=timestamp");
    }

    function test__ClockAdvancesWithTime() public {
        uint48 clockBefore = chip.clock();

        vm.warp(block.timestamp + 100);

        uint48 clockAfter = chip.clock();
        assertEq(clockAfter - clockBefore, 100);
    }

    /*------------------------------------------------------------------------*/
    /* Delegation Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__NoDelegateByDefault() public view {
        assertEq(chip.delegates(user1), address(0));
    }

    function test__NoVotesWithoutDelegation() public view {
        // User1 has tokens but no votes (hasn't delegated)
        assertEq(chip.balanceOf(user1), 1000 ether);
        assertEq(chip.getVotes(user1), 0);
    }

    function test__SelfDelegateActivatesVotes() public {
        vm.prank(user1);
        chip.delegate(user1);

        assertEq(chip.delegates(user1), user1);
        assertEq(chip.getVotes(user1), 1000 ether);
    }

    function test__DelegateToAnother() public {
        vm.prank(user1);
        chip.delegate(user2);

        assertEq(chip.delegates(user1), user2);
        assertEq(chip.getVotes(user1), 0);
        assertEq(chip.getVotes(user2), 1000 ether);
    }

    function test__MultipleDelegatorsToSameDelegate() public {
        vm.prank(user1);
        chip.delegate(user3);

        vm.prank(user2);
        chip.delegate(user3);

        assertEq(chip.getVotes(user3), 2000 ether);
    }

    function test__ChangeDelegation() public {
        // User1 delegates to user2
        vm.prank(user1);
        chip.delegate(user2);
        assertEq(chip.getVotes(user2), 1000 ether);

        // User1 changes delegation to user3
        vm.prank(user1);
        chip.delegate(user3);

        assertEq(chip.getVotes(user2), 0);
        assertEq(chip.getVotes(user3), 1000 ether);
    }

    function test__DelegateEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IVotes.DelegateChanged(user1, address(0), user2);

        vm.prank(user1);
        chip.delegate(user2);
    }

    function test__DelegateVotesChangedEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IVotes.DelegateVotesChanged(user2, 0, 1000 ether);

        vm.prank(user1);
        chip.delegate(user2);
    }

    /*------------------------------------------------------------------------*/
    /* Transfer Updates Votes Tests                                           */
    /*------------------------------------------------------------------------*/

    function test__TransferUpdatesVotes() public {
        // User1 self-delegates
        vm.prank(user1);
        chip.delegate(user1);
        assertEq(chip.getVotes(user1), 1000 ether);

        // User1 transfers to user2
        vm.prank(user1);
        chip.transfer(user2, 300 ether);

        // User1's votes decreased
        assertEq(chip.getVotes(user1), 700 ether);
        // User2 has no votes (not delegated)
        assertEq(chip.getVotes(user2), 0);
    }

    function test__TransferFromDelegatedToDelegated() public {
        // Both users self-delegate
        vm.prank(user1);
        chip.delegate(user1);

        vm.prank(user2);
        chip.delegate(user2);

        assertEq(chip.getVotes(user1), 1000 ether);
        assertEq(chip.getVotes(user2), 1000 ether);

        // User1 transfers to user2
        vm.prank(user1);
        chip.transfer(user2, 400 ether);

        assertEq(chip.getVotes(user1), 600 ether);
        assertEq(chip.getVotes(user2), 1400 ether);
    }

    function test__TransferFromUndelegatedToDelegated() public {
        // Only user2 self-delegates
        vm.prank(user2);
        chip.delegate(user2);

        assertEq(chip.getVotes(user1), 0);
        assertEq(chip.getVotes(user2), 1000 ether);

        // User1 (undelegated) transfers to user2 (delegated)
        vm.prank(user1);
        chip.transfer(user2, 500 ether);

        assertEq(chip.getVotes(user1), 0);
        assertEq(chip.getVotes(user2), 1500 ether);
    }

    function test__TransferWithThirdPartyDelegate() public {
        // User1 delegates to user3
        vm.prank(user1);
        chip.delegate(user3);

        assertEq(chip.getVotes(user3), 1000 ether);

        // User1 transfers tokens
        vm.prank(user1);
        chip.transfer(user2, 400 ether);

        // User3's votes decrease since user1 has fewer tokens
        assertEq(chip.getVotes(user3), 600 ether);
    }

    /*------------------------------------------------------------------------*/
    /* getPastVotes Tests                                                     */
    /*------------------------------------------------------------------------*/

    function test__GetPastVotesBasic() public {
        uint256 timestamp = 1000;
        vm.warp(timestamp);

        // User1 self-delegates
        vm.prank(user1);
        chip.delegate(user1);

        // Record timestamp after delegation
        uint256 timestamp1 = timestamp;

        // Warp forward so we can query history
        timestamp += 1;
        vm.warp(timestamp);

        // Query past votes at delegation time
        assertEq(chip.getPastVotes(user1, timestamp1), 1000 ether);
    }

    function test__GetPastVotesAfterTransfer() public {
        uint256 timestamp = 1000;
        vm.warp(timestamp);

        // User1 self-delegates
        vm.prank(user1);
        chip.delegate(user1);

        // Record timestamp after delegation
        uint256 timestamp1 = timestamp;

        // Warp and transfer
        timestamp += 1;
        vm.warp(timestamp);
        uint256 timestamp2 = timestamp;

        vm.prank(user1);
        chip.transfer(user2, 300 ether);

        // Warp again to query
        timestamp += 1;
        vm.warp(timestamp);

        // At delegation time: 1000 ether
        assertEq(chip.getPastVotes(user1, timestamp1), 1000 ether);
        // At transfer time (after transfer): 700 ether
        assertEq(chip.getPastVotes(user1, timestamp2), 700 ether);
    }

    function test__GetPastVotesRevertsForFuture() public {
        vm.prank(user1);
        chip.delegate(user1);

        vm.expectRevert();
        chip.getPastVotes(user1, block.timestamp);

        vm.expectRevert();
        chip.getPastVotes(user1, block.timestamp + 1);
    }

    /*------------------------------------------------------------------------*/
    /* getPastTotalSupply Tests                                               */
    /*------------------------------------------------------------------------*/

    function test__GetPastTotalSupply() public {
        uint256 timestamp = 1000;
        vm.warp(timestamp);
        uint256 timestamp1 = timestamp;

        timestamp += 100;
        vm.warp(timestamp);

        assertEq(chip.getPastTotalSupply(timestamp1), INITIAL_SUPPLY);
    }

    function test__GetPastTotalSupplyAfterBurn() public {
        // Grant bridge role
        vm.startPrank(admin);
        chip.grantRole(chip.BRIDGE_ADMIN_ROLE(), admin);
        vm.stopPrank();

        uint256 timestamp = 1000;
        vm.warp(timestamp);
        uint256 timestamp1 = timestamp;

        timestamp += 100;
        vm.warp(timestamp);
        uint256 timestamp2 = timestamp;

        vm.prank(admin);
        chip.burn(user1, 200 ether);

        timestamp += 1;
        vm.warp(timestamp);

        assertEq(chip.getPastTotalSupply(timestamp1), INITIAL_SUPPLY);
        assertEq(chip.getPastTotalSupply(timestamp2), INITIAL_SUPPLY - 200 ether);
    }

    /*------------------------------------------------------------------------*/
    /* delegateBySig Tests                                                    */
    /*------------------------------------------------------------------------*/

    function test__DelegateBySig() public {
        uint256 privateKey = 0x1234;
        address signer = vm.addr(privateKey);

        // Transfer tokens to signer
        vm.prank(admin);
        chip.transfer(signer, 100 ether);

        uint256 nonce = chip.nonces(signer);
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 domainSeparator = chip.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"), user2, nonce, expiry)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        chip.delegateBySig(user2, nonce, expiry, v, r, s);

        assertEq(chip.delegates(signer), user2);
        assertEq(chip.getVotes(user2), 100 ether);
    }

    function test__DelegateBySigRevertsExpired() public {
        uint256 privateKey = 0x1234;
        address signer = vm.addr(privateKey);

        vm.prank(admin);
        chip.transfer(signer, 100 ether);

        uint256 nonce = chip.nonces(signer);
        uint256 expiry = block.timestamp - 1; // Already expired

        bytes32 domainSeparator = chip.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"), user2, nonce, expiry)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        vm.expectRevert();
        chip.delegateBySig(user2, nonce, expiry, v, r, s);
    }

    /*------------------------------------------------------------------------*/
    /* Blacklist Integration Tests                                            */
    /*------------------------------------------------------------------------*/

    function test__BlacklistedCannotDelegate() public {
        vm.prank(admin);
        mockUsdai.setBlacklist(user1, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user1));
        chip.delegate(user2);
    }

    function test__CannotDelegateToBlacklisted() public {
        vm.prank(admin);
        mockUsdai.setBlacklist(user2, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user2));
        chip.delegate(user2);
    }

    function test__BlacklistedCannotTransfer() public {
        vm.prank(admin);
        mockUsdai.setBlacklist(user1, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAddress(address)", user1));
        chip.transfer(user2, 100 ether);
    }

    /*------------------------------------------------------------------------*/
    /* revokeDelegate Tests                                                   */
    /*------------------------------------------------------------------------*/

    function test__RevokeDelegateRequiresRole() public {
        vm.prank(user1);
        vm.expectRevert();
        chip.revokeDelegate(user2);
    }

    function test__RevokeDelegateRequiresBlacklisted() public {
        vm.startPrank(admin);
        chip.grantRole(chip.REVOKE_DELEGATE_ADMIN_ROLE(), admin);

        // User2 is not blacklisted - should revert with InvalidAddress
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        chip.revokeDelegate(user2);
        vm.stopPrank();
    }

    function test__RevokeDelegate() public {
        // User1 self-delegates
        vm.prank(user1);
        chip.delegate(user1);
        assertEq(chip.getVotes(user1), 1000 ether);

        // Grant role and blacklist user1
        vm.startPrank(admin);
        chip.grantRole(chip.REVOKE_DELEGATE_ADMIN_ROLE(), admin);
        mockUsdai.setBlacklist(user1, true);

        // Revoke delegate
        chip.revokeDelegate(user1);
        vm.stopPrank();

        // User1 should have no votes
        assertEq(chip.getVotes(user1), 0);
    }

    /*------------------------------------------------------------------------*/
    /* Checkpoint Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__CheckpointsCreatedOnDelegation() public {
        vm.prank(user1);
        chip.delegate(user1);

        // Should have at least one checkpoint
        assertGe(chip.numCheckpoints(user1), 1);
    }

    function test__MultipleCheckpointsOnTransfers() public {
        vm.prank(user1);
        chip.delegate(user1);

        uint32 checkpointsBefore = chip.numCheckpoints(user1);

        // Warp and transfer multiple times
        vm.warp(block.timestamp + 100);
        vm.prank(user1);
        chip.transfer(user2, 100 ether);

        vm.warp(block.timestamp + 100);
        vm.prank(user1);
        chip.transfer(user2, 100 ether);

        uint32 checkpointsAfter = chip.numCheckpoints(user1);

        assertGt(checkpointsAfter, checkpointsBefore);
    }

    /*------------------------------------------------------------------------*/
    /* Edge Cases                                                             */
    /*------------------------------------------------------------------------*/

    function test__DelegateToZeroAddress() public {
        // First delegate to someone
        vm.prank(user1);
        chip.delegate(user2);
        assertEq(chip.getVotes(user2), 1000 ether);

        // Then delegate to zero (effectively undelegating)
        vm.prank(user1);
        chip.delegate(address(0));

        assertEq(chip.delegates(user1), address(0));
        assertEq(chip.getVotes(user2), 0);
    }

    function test__DelegateToSelf() public {
        vm.prank(user1);
        chip.delegate(user1);

        assertEq(chip.delegates(user1), user1);
        assertEq(chip.getVotes(user1), 1000 ether);
    }

    function test__DelegateWithZeroBalance() public {
        address noTokens = makeAddr("noTokens");

        vm.prank(noTokens);
        chip.delegate(user2);

        assertEq(chip.delegates(noTokens), user2);
        assertEq(chip.getVotes(user2), 0);
    }

    function test__TransferEntireBalance() public {
        vm.prank(user1);
        chip.delegate(user1);

        assertEq(chip.getVotes(user1), 1000 ether);

        // Transfer entire balance
        vm.prank(user1);
        chip.transfer(user2, 1000 ether);

        assertEq(chip.getVotes(user1), 0);
        assertEq(chip.balanceOf(user1), 0);
    }

    /*------------------------------------------------------------------------*/
    /* Fuzz Tests                                                             */
    /*------------------------------------------------------------------------*/

    function testFuzz_DelegateAndTransfer(
        uint256 transferAmount
    ) public {
        transferAmount = bound(transferAmount, 1, 1000 ether);

        vm.prank(user1);
        chip.delegate(user1);

        vm.prank(user2);
        chip.delegate(user2);

        uint256 user1VotesBefore = chip.getVotes(user1);
        uint256 user2VotesBefore = chip.getVotes(user2);

        vm.prank(user1);
        chip.transfer(user2, transferAmount);

        assertEq(chip.getVotes(user1), user1VotesBefore - transferAmount);
        assertEq(chip.getVotes(user2), user2VotesBefore + transferAmount);
    }

    function testFuzz_MultipleDelegations(
        uint8 numDelegators
    ) public {
        numDelegators = uint8(bound(numDelegators, 1, 10));

        uint256 totalDelegated;

        for (uint8 i = 0; i < numDelegators; i++) {
            address delegator = makeAddr(string(abi.encodePacked("delegator", i)));

            uint256 amount = 100 ether;
            vm.prank(admin);
            chip.transfer(delegator, amount);

            vm.prank(delegator);
            chip.delegate(user1);

            totalDelegated += amount;
        }

        assertEq(chip.getVotes(user1), totalDelegated);
    }
}
