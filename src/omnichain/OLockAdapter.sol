// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OFTAdapter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import {RateLimiter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/utils/RateLimiter.sol";

/**
 * @title Omnichain Lock Adapter
 * @author USD.AI Foundation
 */
contract OLockAdapter is OFTAdapter, RateLimiter {
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @dev OLockAdapter contructor
     * @param token_ Wrapped token address
     * @param lzEndpoint_ LayerZero endpoint address
     * @param delegate_ Delegate/owner address
     */
    constructor(
        address token_,
        address lzEndpoint_,
        address delegate_
    ) OFTAdapter(token_, lzEndpoint_, delegate_) Ownable(delegate_) {}

    /*------------------------------------------------------------------------*/
    /* Overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc OFTAdapter
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _checkAndUpdateRateLimit(_dstEid, amountSentLD);
        // @dev Lock tokens by moving them into this contract from the caller.
        innerToken.safeTransferFrom(_from, address(this), amountSentLD);
    }

    /*------------------------------------------------------------------------*/
    /* Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @dev Sets the rate limits based on RateLimitConfig array. Only callable by the owner.
     * @param _rateLimitConfigs An array of RateLimitConfig structures defining the rate limits.
     */
    function setRateLimits(
        RateLimitConfig[] calldata _rateLimitConfigs
    ) external onlyOwner {
        _setRateLimits(_rateLimitConfigs);
    }
}
