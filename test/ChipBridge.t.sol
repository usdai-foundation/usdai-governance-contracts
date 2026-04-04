// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {RateLimiter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    ITransparentUpgradeableProxy
} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Chip} from "../src/Chip.sol";
import {IChip} from "../src/interfaces/IChip.sol";
import {OLockAdapter} from "../src/omnichain/OLockAdapter.sol";
import {OToken} from "../src/omnichain/OToken.sol";
import {OAdapter} from "../src/omnichain/OAdapter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

/**
 * @title Chip Bridge Tests
 * @notice Tests for cross-chain bridging of CHIP via OLockAdapter (hub) <-> OAdapter + OToken (spoke)
 */
contract ChipBridgeTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    uint256 internal constant INITIAL_SUPPLY = 10_000 ether;
    uint256 internal constant INITIAL_USER_BALANCE = 1_000 ether;
    uint256 internal constant RATE_LIMIT = 500 ether;

    /*------------------------------------------------------------------------*/
    /* Endpoint IDs                                                           */
    /*------------------------------------------------------------------------*/

    uint32 internal hubEid = 1;
    uint32 internal spokeEid = 2;

    /*------------------------------------------------------------------------*/
    /* Contracts                                                              */
    /*------------------------------------------------------------------------*/

    MockUSDai internal mockUsdai;

    /* Hub chain */
    Chip internal chip;
    OLockAdapter internal oLockAdapter;

    /* Spoke chain */
    OToken internal oToken;
    OAdapter internal oAdapter;

    /*------------------------------------------------------------------------*/
    /* Actors                                                                 */
    /*------------------------------------------------------------------------*/

    address internal admin;
    address internal userHub;
    address internal userSpoke;
    address internal blacklisted;

    /*------------------------------------------------------------------------*/
    /* Setup                                                                  */
    /*------------------------------------------------------------------------*/

    function setUp() public virtual override {
        admin = makeAddr("admin");
        userHub = makeAddr("userHub");
        userSpoke = makeAddr("userSpoke");
        blacklisted = makeAddr("blacklisted");

        vm.deal(userHub, 1000 ether);
        vm.deal(userSpoke, 1000 ether);
        vm.deal(admin, 1000 ether);
        vm.deal(blacklisted, 1000 ether);

        /* Initialize TestHelperOz5 */
        super.setUp();

        /* Set up 2 endpoints (hub and spoke) */
        setUpEndpoints(2, LibraryType.UltraLightNode);

        /* Deploy MockUSDai with proxy so initialize() can be called */
        vm.startPrank(admin);
        MockUSDai mockUsdaiImpl = new MockUSDai();
        mockUsdai = MockUSDai(
            address(new ERC1967Proxy(address(mockUsdaiImpl), abi.encodeWithSelector(MockUSDai.initialize.selector)))
        );
        vm.stopPrank();

        /* Deploy hub Chip token */
        vm.startPrank(admin);
        Chip chipImpl = new Chip(address(mockUsdai));
        chip = Chip(
            address(
                new TransparentUpgradeableProxy(
                    address(chipImpl),
                    admin,
                    abi.encodeWithSelector(Chip.initialize.selector, INITIAL_SUPPLY, admin, admin)
                )
            )
        );
        vm.stopPrank();

        /* Deploy spoke OToken (admin holds DEFAULT_ADMIN_ROLE on OToken) */
        OToken oTokenImpl = new OToken(address(0));
        oToken = OToken(
            address(
                new TransparentUpgradeableProxy(
                    address(oTokenImpl),
                    admin,
                    abi.encodeWithSelector(OToken.initialize.selector, "Chip", "CHIP", admin)
                )
            )
        );

        /* Set up rate limit configs */
        RateLimiter.RateLimitConfig[] memory hubRateLimits = new RateLimiter.RateLimitConfig[](1);
        hubRateLimits[0] = RateLimiter.RateLimitConfig({dstEid: spokeEid, limit: RATE_LIMIT, window: 1 days});

        RateLimiter.RateLimitConfig[] memory spokeRateLimits = new RateLimiter.RateLimitConfig[](1);
        spokeRateLimits[0] = RateLimiter.RateLimitConfig({dstEid: hubEid, limit: RATE_LIMIT, window: 1 days});

        /* Deploy hub OLockAdapter wrapping Chip */
        oLockAdapter = OLockAdapter(
            _deployOApp(
                type(OLockAdapter).creationCode, abi.encode(address(chip), address(endpoints[hubEid]), address(this))
            )
        );
        oLockAdapter.setRateLimits(hubRateLimits);

        /* Deploy spoke OAdapter wrapping OToken */
        oAdapter = OAdapter(
            _deployOApp(
                type(OAdapter).creationCode, abi.encode(address(oToken), address(endpoints[spokeEid]), address(this))
            )
        );
        oAdapter.setRateLimits(spokeRateLimits);

        /* Upgrade OToken to use OAdapter */
        vm.startPrank(admin);
        oTokenImpl = new OToken(address(oAdapter));

        /* Lookup proxy admin from EIP-1967 storage slot */
        address proxyAdmin = address(uint160(uint256(vm.load(address(oToken), ERC1967Utils.ADMIN_SLOT))));

        ProxyAdmin(proxyAdmin)
            .upgradeAndCall(
                ITransparentUpgradeableProxy(address(oToken)),
                address(oTokenImpl),
                "" // No additional initialization data
            );
        vm.stopPrank();

        /* Wire OLockAdapter <-> OAdapter */
        address[] memory oApps = new address[](2);
        oApps[0] = address(oLockAdapter);
        oApps[1] = address(oAdapter);
        this.wireOApps(oApps);

        /* Grant OLockAdapter TRANSFER_ADMIN_ROLE on Chip (hub: lock/unlock), and
           grant admin TRANSFER_ADMIN_ROLE to distribute initial tokens */
        vm.startPrank(admin);
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), address(oLockAdapter));
        chip.grantRole(chip.TRANSFER_ADMIN_ROLE(), admin);
        chip.transfer(userHub, INITIAL_USER_BALANCE);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Helpers                                                                */
    /*------------------------------------------------------------------------*/

    function _buildSendParam(
        uint32 dstEid,
        address recipient,
        uint256 amount
    ) internal pure returns (SendParam memory) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        return SendParam(dstEid, addressToBytes32(recipient), amount, amount, options, "", "");
    }

    /*------------------------------------------------------------------------*/
    /* Initial State Tests                                                    */
    /*------------------------------------------------------------------------*/

    function test__Constructor() public view {
        /* Hub adapter */
        assertEq(oLockAdapter.owner(), address(this));
        assertEq(oLockAdapter.token(), address(chip));

        /* Spoke adapter */
        assertEq(oAdapter.owner(), address(this));
        assertEq(oAdapter.token(), address(oToken));

        /* User balances */
        assertEq(chip.balanceOf(userHub), INITIAL_USER_BALANCE);
        assertEq(oToken.balanceOf(userSpoke), 0);
    }

    function test__ApprovalRequired() public view {
        assertTrue(oLockAdapter.approvalRequired());
        assertFalse(oAdapter.approvalRequired());
    }

    /*------------------------------------------------------------------------*/
    /* Hub -> Spoke Send Tests                                                */
    /*------------------------------------------------------------------------*/

    function test__SendFromHubToSpoke() public {
        uint256 tokensToSend = 100 ether;
        uint256 chipTotalSupplyBefore = chip.totalSupply();

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        /* Approve OLockAdapter to spend Chip */
        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);

        /* Send */
        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));

        /* Verify packets are delivered to spoke chain */
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Hub: Chip locked in OLockAdapter — total supply unchanged */
        assertEq(chip.balanceOf(userHub), INITIAL_USER_BALANCE - tokensToSend);
        assertEq(chip.balanceOf(address(oLockAdapter)), tokensToSend);
        assertEq(chip.totalSupply(), chipTotalSupplyBefore);

        /* Spoke: OToken minted to recipient */
        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
    }

    function testFuzz__SendFromHubToSpoke(
        uint256 tokensToSend
    ) public {
        tokensToSend = bound(tokensToSend, 1e12, RATE_LIMIT);
        /* Align to OFT dust boundary (shared decimals = 6, so ld2sd rate = 1e12) */
        tokensToSend = (tokensToSend / 1e12) * 1e12;

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);

        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));

        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(chip.balanceOf(userHub), INITIAL_USER_BALANCE - tokensToSend);
        assertEq(chip.balanceOf(address(oLockAdapter)), tokensToSend);
        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
    }

    /*------------------------------------------------------------------------*/
    /* Spoke -> Hub Send Tests                                                */
    /*------------------------------------------------------------------------*/

    function test__SendFromSpokeToHub() public {
        uint256 tokensToSend = 100 ether;
        uint256 chipTotalSupplyBefore = chip.totalSupply();

        /* First bridge hub->spoke to give userSpoke some OToken */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
        assertEq(chip.totalSupply(), chipTotalSupplyBefore);

        /* Now bridge spoke->hub */
        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
        verifyPackets(hubEid, addressToBytes32(address(oLockAdapter)));

        /* Spoke: OToken burned */
        assertEq(oToken.balanceOf(userSpoke), 0);

        /* Hub: Chip unlocked and transferred to userHub — total supply unchanged throughout */
        assertEq(chip.balanceOf(userHub), INITIAL_USER_BALANCE);
        assertEq(chip.balanceOf(address(oLockAdapter)), 0);
        assertEq(chip.totalSupply(), chipTotalSupplyBefore);
    }

    /*------------------------------------------------------------------------*/
    /* Round Trip Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__RoundTrip() public {
        uint256 tokensToSend = 200 ether;

        uint256 hubBalanceBefore = chip.balanceOf(userHub);
        uint256 oTokenSupplyBefore = oToken.totalSupply();

        /* Hub -> Spoke */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Verify intermediary state: Chip locked, OToken minted */
        assertEq(chip.balanceOf(userHub), hubBalanceBefore - tokensToSend);
        assertEq(chip.balanceOf(address(oLockAdapter)), tokensToSend);
        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
        assertEq(oToken.totalSupply(), oTokenSupplyBefore + tokensToSend);

        /* Spoke -> Hub */
        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
        verifyPackets(hubEid, addressToBytes32(address(oLockAdapter)));

        /* Verify final state: restored to original */
        assertEq(chip.balanceOf(userHub), hubBalanceBefore);
        assertEq(chip.balanceOf(address(oLockAdapter)), 0);
        assertEq(oToken.balanceOf(userSpoke), 0);
        assertEq(oToken.totalSupply(), oTokenSupplyBefore);
    }

    function test__RoundTrip_DifferentRecipients() public {
        uint256 tokensToSend = 100 ether;
        address spokeSideRecipient = makeAddr("spokeSideRecipient");
        address hubSideRecipient = makeAddr("hubSideRecipient");
        vm.deal(spokeSideRecipient, 1000 ether);

        /* Hub -> Spoke (different recipient on spoke) */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, spokeSideRecipient, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(oToken.balanceOf(spokeSideRecipient), tokensToSend);

        /* Spoke -> Hub (different recipient on hub) */
        SendParam memory sendToHub = _buildSendParam(hubEid, hubSideRecipient, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(spokeSideRecipient);
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(spokeSideRecipient));
        verifyPackets(hubEid, addressToBytes32(address(oLockAdapter)));

        assertEq(chip.balanceOf(hubSideRecipient), tokensToSend);
    }

    /*------------------------------------------------------------------------*/
    /* Rate Limit Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__HubRateLimitEnforced() public {
        uint256 tokensToSend = RATE_LIMIT + 1e12;

        /* Give userHub enough Chip */
        vm.prank(admin);
        chip.transfer(userHub, tokensToSend);

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);

        vm.prank(userHub);
        vm.expectRevert();
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));
    }

    function test__SpokeRateLimitEnforced() public {
        /* First give userSpoke some OToken via hub->spoke bridge */
        uint256 bridgeAmount = RATE_LIMIT;
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, bridgeAmount);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), bridgeAmount);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Try to send more than the rate limit back */
        uint256 tokensToSend = RATE_LIMIT + 1e12;

        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        vm.expectRevert();
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
    }

    function test__RateLimitResetsAfterWindow() public {
        uint256 tokensToSend = RATE_LIMIT;

        /* Send at limit */
        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Advance time past window */
        vm.warp(block.timestamp + 1 days + 1);

        /* Send again at limit — should succeed */
        vm.prank(admin);
        chip.transfer(userHub, tokensToSend);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(oToken.balanceOf(userSpoke), tokensToSend * 2);
    }

    /*------------------------------------------------------------------------*/
    /* Blacklist Tests                                                        */
    /*------------------------------------------------------------------------*/

    function test__BlacklistedSenderCannotBridgeFromHub() public {
        uint256 tokensToSend = 100 ether;

        /* Give blacklisted user some Chip */
        vm.prank(admin);
        chip.transfer(blacklisted, tokensToSend);

        /* Blacklist the user */
        vm.prank(admin);
        mockUsdai.setBlacklist(blacklisted, true);

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(blacklisted);
        chip.approve(address(oLockAdapter), tokensToSend);

        /* Blacklisted user cannot bridge — Chip._update blocks transfer from blacklisted */
        vm.prank(blacklisted);
        vm.expectRevert();
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(blacklisted));
    }

    /*------------------------------------------------------------------------*/
    /* QuoteSend Tests                                                        */
    /*------------------------------------------------------------------------*/

    function test__QuoteSendHubToSpoke() public view {
        uint256 tokensToSend = 100 ether;
        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        assertGt(fee.nativeFee, 0);
        assertEq(fee.lzTokenFee, 0);
    }

    function test__QuoteSendSpokeToHub() public view {
        uint256 tokensToSend = 100 ether;
        SendParam memory sendParam = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory fee = oAdapter.quoteSend(sendParam, false);

        assertGt(fee.nativeFee, 0);
        assertEq(fee.lzTokenFee, 0);
    }

    /*------------------------------------------------------------------------*/
    /* Admin Tests                                                            */
    /*------------------------------------------------------------------------*/

    function test__OnlyOwnerCanSetRateLimits() public {
        RateLimiter.RateLimitConfig[] memory newLimits = new RateLimiter.RateLimitConfig[](1);
        newLimits[0] = RateLimiter.RateLimitConfig({dstEid: spokeEid, limit: 999 ether, window: 1 days});

        vm.prank(userHub);
        vm.expectRevert();
        oLockAdapter.setRateLimits(newLimits);
    }

    function test__OwnerCanUpdateRateLimits() public {
        uint256 newLimit = 999 ether;

        RateLimiter.RateLimitConfig[] memory newLimits = new RateLimiter.RateLimitConfig[](1);
        newLimits[0] = RateLimiter.RateLimitConfig({dstEid: spokeEid, limit: newLimit, window: 1 days});

        oLockAdapter.setRateLimits(newLimits);

        /* Verify new limit allows higher sends */
        vm.prank(admin);
        chip.transfer(userHub, newLimit);

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, newLimit);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), newLimit);
        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));

        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));
        assertEq(oToken.balanceOf(userSpoke), newLimit);
    }

    /*------------------------------------------------------------------------*/
    /* Chip Supply Invariant Tests                                            */
    /*------------------------------------------------------------------------*/

    function test__TotalSupplyPreservedOnBridge() public {
        uint256 totalSupplyBefore = chip.totalSupply();
        uint256 tokensToSend = 100 ether;

        /* Hub -> Spoke: Chip locked, not burned — total supply unchanged */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        chip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Chip total supply is unchanged since tokens are locked (not burned) */
        assertEq(chip.totalSupply(), totalSupplyBefore);

        /* OToken is minted on spoke */
        assertEq(oToken.totalSupply(), tokensToSend);
    }
}
