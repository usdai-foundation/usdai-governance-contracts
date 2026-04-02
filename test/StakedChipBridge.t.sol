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
import {StakedChip} from "../src/StakedChip.sol";
import {IStakedChip} from "../src/interfaces/IStakedChip.sol";
import {OLockAdapter} from "../src/omnichain/OLockAdapter.sol";
import {OToken} from "../src/omnichain/OToken.sol";
import {OAdapter} from "../src/omnichain/OAdapter.sol";

import {MockUSDai} from "./mocks/MockUSDai.sol";

/**
 * @title StakedChip Bridge Tests
 * @notice Tests for cross-chain bridging of sCHIP via OLockAdapter (hub) <-> OAdapter + OToken (spoke)
 *
 * @dev Architecture:
 *   Hub:   StakedChip (ERC4626 vault over CHIP) + OLockAdapter (locks/unlocks sCHIP)
 *   Spoke: OToken (sCHIP representation) + OAdapter (mints/burns OToken)
 */
contract StakedChipBridgeTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    /*------------------------------------------------------------------------*/
    /* Constants                                                              */
    /*------------------------------------------------------------------------*/

    uint256 internal constant CHIP_SUPPLY = 10_000 ether;
    uint256 internal constant CHIP_PER_USER = 1_000 ether;
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
    StakedChip internal stakedChip;
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
    /* State                                                                  */
    /*------------------------------------------------------------------------*/

    /* sCHIP balance of userHub after initial CHIP deposit in setUp */
    uint256 internal userHubSChip;

    /*------------------------------------------------------------------------*/
    /* Setup                                                                  */
    /*------------------------------------------------------------------------*/

    function setUp() public virtual override {
        admin = makeAddr("admin");
        userHub = makeAddr("userHub");
        userSpoke = makeAddr("userSpoke");
        blacklisted = makeAddr("blacklisted");

        vm.deal(admin, 1000 ether);
        vm.deal(userHub, 1000 ether);
        vm.deal(userSpoke, 1000 ether);
        vm.deal(blacklisted, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        /* Deploy MockUSDai */
        vm.startPrank(admin);
        MockUSDai mockUsdaiImpl = new MockUSDai();
        mockUsdai = MockUSDai(
            address(new ERC1967Proxy(address(mockUsdaiImpl), abi.encodeWithSelector(MockUSDai.initialize.selector)))
        );
        vm.stopPrank();

        /* Deploy Chip */
        vm.startPrank(admin);
        Chip chipImpl = new Chip(address(mockUsdai));
        chip = Chip(
            address(
                new TransparentUpgradeableProxy(
                    address(chipImpl),
                    admin,
                    abi.encodeWithSelector(Chip.initialize.selector, CHIP_SUPPLY, admin, admin)
                )
            )
        );
        vm.stopPrank();

        /* Deploy StakedChip */
        vm.startPrank(admin);
        StakedChip stakedChipImpl = new StakedChip(address(mockUsdai), address(chip));
        stakedChip = StakedChip(
            address(
                new TransparentUpgradeableProxy(
                    address(stakedChipImpl), admin, abi.encodeWithSelector(StakedChip.initialize.selector, admin)
                )
            )
        );
        vm.stopPrank();

        /* Deploy spoke OToken representing sCHIP on remote chains */
        OToken oTokenImpl = new OToken(address(0));
        oToken = OToken(
            address(
                new TransparentUpgradeableProxy(
                    address(oTokenImpl),
                    admin,
                    abi.encodeWithSelector(OToken.initialize.selector, "Staked Chip", "sCHIP", admin)
                )
            )
        );

        /* Rate limit configs */
        RateLimiter.RateLimitConfig[] memory hubRateLimits = new RateLimiter.RateLimitConfig[](1);
        hubRateLimits[0] = RateLimiter.RateLimitConfig({dstEid: spokeEid, limit: RATE_LIMIT, window: 1 days});

        RateLimiter.RateLimitConfig[] memory spokeRateLimits = new RateLimiter.RateLimitConfig[](1);
        spokeRateLimits[0] = RateLimiter.RateLimitConfig({dstEid: hubEid, limit: RATE_LIMIT, window: 1 days});

        /* Deploy hub OLockAdapter wrapping StakedChip. */
        oLockAdapter = OLockAdapter(
            _deployOApp(
                type(OLockAdapter).creationCode,
                abi.encode(address(stakedChip), address(endpoints[hubEid]), address(this))
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

        /* Transfer Chip to user */
        vm.prank(admin);
        chip.transfer(userHub, CHIP_PER_USER);

        /* userHub deposits CHIP into StakedChip to receive sCHIP shares */
        vm.startPrank(userHub);
        chip.approve(address(stakedChip), CHIP_PER_USER);
        userHubSChip = stakedChip.deposit(CHIP_PER_USER, userHub);
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
        assertEq(oLockAdapter.owner(), address(this));
        assertEq(oLockAdapter.token(), address(stakedChip));

        assertEq(oAdapter.owner(), address(this));
        assertEq(oAdapter.token(), address(oToken));

        assertGt(stakedChip.balanceOf(userHub), 0);
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
        uint256 sChipTotalSupplyBefore = stakedChip.totalSupply();
        uint256 totalAssetsBefore = stakedChip.totalAssets();

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);

        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));

        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Hub: sCHIP locked in OLockAdapter — sCHIP total supply unchanged,
           underlying CHIP balance in vault unchanged */
        assertEq(stakedChip.balanceOf(userHub), userHubSChip - tokensToSend);
        assertEq(stakedChip.balanceOf(address(oLockAdapter)), tokensToSend);
        assertEq(stakedChip.totalSupply(), sChipTotalSupplyBefore);
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);

        /* Spoke: OToken minted to recipient */
        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
    }

    function testFuzz__SendFromHubToSpoke(
        uint256 tokensToSend
    ) public {
        tokensToSend = bound(tokensToSend, 1e12, RATE_LIMIT);
        /* Align to OFT dust boundary (shared decimals = 6, ld2sd rate = 1e12) */
        tokensToSend = (tokensToSend / 1e12) * 1e12;

        uint256 sChipTotalSupplyBefore = stakedChip.totalSupply();
        uint256 totalAssetsBefore = stakedChip.totalAssets();

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);

        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));

        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(stakedChip.balanceOf(userHub), userHubSChip - tokensToSend);
        assertEq(stakedChip.balanceOf(address(oLockAdapter)), tokensToSend);
        assertEq(stakedChip.totalSupply(), sChipTotalSupplyBefore);
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);
        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
    }

    /*------------------------------------------------------------------------*/
    /* Spoke -> Hub Send Tests                                                */
    /*------------------------------------------------------------------------*/

    function test__SendFromSpokeToHub() public {
        uint256 tokensToSend = 100 ether;
        uint256 sChipTotalSupplyBefore = stakedChip.totalSupply();
        uint256 totalAssetsBefore = stakedChip.totalAssets();

        /* Bridge hub->spoke to give userSpoke some OToken */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
        assertEq(stakedChip.totalSupply(), sChipTotalSupplyBefore);
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);

        /* Bridge spoke->hub */
        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
        verifyPackets(hubEid, addressToBytes32(address(oLockAdapter)));

        /* Spoke: OToken burned */
        assertEq(oToken.balanceOf(userSpoke), 0);

        /* Hub: sCHIP unlocked — total supply, total assets unchanged throughout */
        assertEq(stakedChip.balanceOf(userHub), userHubSChip);
        assertEq(stakedChip.balanceOf(address(oLockAdapter)), 0);
        assertEq(stakedChip.totalSupply(), sChipTotalSupplyBefore);
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);
    }

    /*------------------------------------------------------------------------*/
    /* Round Trip Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__RoundTrip() public {
        uint256 tokensToSend = 200 ether;

        uint256 sChipSupplyBefore = stakedChip.totalSupply();
        uint256 totalAssetsBefore = stakedChip.totalAssets();
        uint256 oTokenSupplyBefore = oToken.totalSupply();

        /* Hub -> Spoke */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Intermediary: sCHIP locked in adapter, OToken minted on spoke */
        assertEq(stakedChip.balanceOf(userHub), userHubSChip - tokensToSend);
        assertEq(stakedChip.balanceOf(address(oLockAdapter)), tokensToSend);
        assertEq(stakedChip.totalSupply(), sChipSupplyBefore);
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);
        assertEq(oToken.balanceOf(userSpoke), tokensToSend);
        assertEq(oToken.totalSupply(), oTokenSupplyBefore + tokensToSend);

        /* Spoke -> Hub */
        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
        verifyPackets(hubEid, addressToBytes32(address(oLockAdapter)));

        /* Final: all restored */
        assertEq(stakedChip.balanceOf(userHub), userHubSChip);
        assertEq(stakedChip.balanceOf(address(oLockAdapter)), 0);
        assertEq(stakedChip.totalSupply(), sChipSupplyBefore);
        assertEq(stakedChip.totalAssets(), totalAssetsBefore);
        assertEq(oToken.balanceOf(userSpoke), 0);
        assertEq(oToken.totalSupply(), oTokenSupplyBefore);
    }

    /*------------------------------------------------------------------------*/
    /* Vault Invariant Tests                                                  */
    /*------------------------------------------------------------------------*/

    function test__TotalAssetsUnaffectedByBridge() public {
        uint256 totalAssetsBefore = stakedChip.totalAssets();
        uint256 tokensToSend = 100 ether;

        /* Hub -> Spoke: CHIP backing stays in vault, only sCHIP shares move */
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        assertEq(stakedChip.totalAssets(), totalAssetsBefore);

        /* Spoke -> Hub: unlocking sCHIP also does not affect the CHIP in the vault */
        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
        verifyPackets(hubEid, addressToBytes32(address(oLockAdapter)));

        assertEq(stakedChip.totalAssets(), totalAssetsBefore);
    }

    function test__SharePriceUnaffectedByBridge() public {
        /* A second depositor establishes a reference point for share price */
        address user2 = makeAddr("user2");
        vm.deal(user2, 100 ether);
        uint256 user2ChipAmount = 200 ether;

        vm.startPrank(admin);
        chip.transfer(user2, user2ChipAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        chip.approve(address(stakedChip), user2ChipAmount);
        uint256 user2SChip = stakedChip.deposit(user2ChipAmount, user2);
        vm.stopPrank();

        uint256 sharePriceBefore = stakedChip.convertToAssets(1 ether);

        /* userHub bridges 100 ether of sCHIP to spoke */
        uint256 tokensToSend = 100 ether;
        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* totalAssets and totalSupply both unchanged, so share price is identical */
        assertEq(stakedChip.convertToAssets(1 ether), sharePriceBefore);

        /* user2's redemption value is unaffected */
        assertEq(stakedChip.convertToAssets(user2SChip), user2ChipAmount);
    }

    function test__NonBridgingDepositorCanStillWithdraw() public {
        /* user2 deposits independently */
        address user2 = makeAddr("user2");
        uint256 user2ChipAmount = 200 ether;

        vm.startPrank(admin);
        chip.transfer(user2, user2ChipAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        chip.approve(address(stakedChip), user2ChipAmount);
        uint256 user2SChip = stakedChip.deposit(user2ChipAmount, user2);
        vm.stopPrank();

        /* userHub bridges all their sCHIP to spoke */
        uint256 tokensToSend = 300 ether;
        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);
        vm.prank(userHub);
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* user2 redeems — must receive exactly what they put in since there is no yield */
        uint256 chipBefore = chip.balanceOf(user2);
        vm.prank(user2);
        uint256 received = stakedChip.redeem(user2SChip, user2, user2);

        assertEq(chip.balanceOf(user2) - chipBefore, received);
        assertEq(received, user2ChipAmount);
    }

    /*------------------------------------------------------------------------*/
    /* Rate Limit Tests                                                       */
    /*------------------------------------------------------------------------*/

    function test__HubRateLimitEnforced() public {
        uint256 tokensToSend = RATE_LIMIT + 1e12;

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, tokensToSend);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), tokensToSend);

        vm.prank(userHub);
        vm.expectRevert();
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userHub));
    }

    function test__SpokeRateLimitEnforced() public {
        /* Give userSpoke some OToken via hub->spoke bridge */
        uint256 bridgeAmount = RATE_LIMIT;
        SendParam memory sendToSpoke = _buildSendParam(spokeEid, userSpoke, bridgeAmount);
        MessagingFee memory feeToSpoke = oLockAdapter.quoteSend(sendToSpoke, false);

        vm.prank(userHub);
        stakedChip.approve(address(oLockAdapter), bridgeAmount);
        vm.prank(userHub);
        oLockAdapter.send{value: feeToSpoke.nativeFee}(sendToSpoke, feeToSpoke, payable(userHub));
        verifyPackets(spokeEid, addressToBytes32(address(oAdapter)));

        /* Try to bridge back more than the rate limit */
        uint256 tokensToSend = RATE_LIMIT + 1e12;

        SendParam memory sendToHub = _buildSendParam(hubEid, userHub, tokensToSend);
        MessagingFee memory feeToHub = oAdapter.quoteSend(sendToHub, false);

        vm.prank(userSpoke);
        vm.expectRevert();
        oAdapter.send{value: feeToHub.nativeFee}(sendToHub, feeToHub, payable(userSpoke));
    }

    /*------------------------------------------------------------------------*/
    /* Blacklist Tests                                                        */
    /*------------------------------------------------------------------------*/

    function test__BlacklistedSenderCannotBridgeFromHub() public {
        uint256 chipAmount = 100 ether;

        /* Give blacklisted user some CHIP and let them deposit before blacklisting */
        vm.startPrank(admin);
        chip.transfer(blacklisted, chipAmount);
        vm.stopPrank();

        vm.startPrank(blacklisted);
        chip.approve(address(stakedChip), chipAmount);
        uint256 sChipAmount = stakedChip.deposit(chipAmount, blacklisted);
        vm.stopPrank();

        /* Now blacklist them */
        vm.prank(admin);
        mockUsdai.setBlacklist(blacklisted, true);

        SendParam memory sendParam = _buildSendParam(spokeEid, userSpoke, sChipAmount);
        MessagingFee memory fee = oLockAdapter.quoteSend(sendParam, false);

        vm.prank(blacklisted);
        stakedChip.approve(address(oLockAdapter), sChipAmount);

        /* Blacklisted user cannot bridge — StakedChip._update blocks transfer from blacklisted */
        vm.prank(blacklisted);
        vm.expectRevert();
        oLockAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(blacklisted));
    }

    function test__BlacklistedRecipientCannotReceiveOnHub() public {
        uint256 tokensToSend = 100 ether;

        /* Simulate sCHIP locked in OLockAdapter (as if a hub->spoke bridge occurred) */
        vm.prank(userHub);
        stakedChip.transfer(address(oLockAdapter), tokensToSend);

        /* Blacklist the intended hub recipient */
        vm.prank(admin);
        mockUsdai.setBlacklist(blacklisted, true);

        /* OLockAdapter cannot unlock sCHIP to a blacklisted address —
           this is what would happen when lzReceive tries to credit the recipient */
        vm.prank(address(oLockAdapter));
        vm.expectRevert(abi.encodeWithSelector(IStakedChip.BlacklistedAddress.selector, blacklisted));
        stakedChip.transfer(blacklisted, tokensToSend);

        /* Confirm tokens remain locked */
        assertEq(stakedChip.balanceOf(blacklisted), 0);
        assertEq(stakedChip.balanceOf(address(oLockAdapter)), tokensToSend);
    }
}
