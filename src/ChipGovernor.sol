// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Governor} from "openzeppelin-contracts/contracts/governance/Governor.sol";
import {GovernorVotes} from "openzeppelin-contracts/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorCountingSimple
} from "openzeppelin-contracts/contracts/governance/extensions/GovernorCountingSimple.sol";
import {
    GovernorVotesQuorumFraction
} from "openzeppelin-contracts/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {
    GovernorTimelockControl
} from "openzeppelin-contracts/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorSettings} from "openzeppelin-contracts/contracts/governance/extensions/GovernorSettings.sol";
import {IVotes} from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

/**
 * @title Chip Governor
 * @author Permian Labs
 */
contract ChipGovernor is
    Governor,
    GovernorVotes,
    GovernorCountingSimple,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    GovernorSettings
{
    /*------------------------------------------------------------------------*/
    /* Chip Governor Constructor                                              */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param governorName_ Governor name
     * @param token_ Votes-enabled token contract
     * @param timelock_ Timelock controller contract
     * @param quorumFraction_ Fraction of token supply for quorum (percent)
     * @param votingDelay_ Voting delay (EIP-6372 clock units)
     * @param votingPeriod_ Voting period (EIP-6372 clock units)
     * @param proposalThreshold_ Proposal threshold (votes)
     */
    constructor(
        string memory governorName_,
        IVotes token_,
        TimelockController timelock_,
        uint256 quorumFraction_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_
    )
        Governor(governorName_)
        GovernorVotes(token_)
        GovernorTimelockControl(timelock_)
        GovernorVotesQuorumFraction(quorumFraction_)
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
    {}

    /*------------------------------------------------------------------------*/
    /* Overrides                                                              */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc Governor
     */
    function proposalThreshold() public view override(GovernorSettings, Governor) returns (uint256) {
        return super.proposalThreshold();
    }

    /**
     * @inheritdoc Governor
     */
    function state(
        uint256 proposalId
    ) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    /**
     * @inheritdoc Governor
     */
    function proposalNeedsQueuing(
        uint256 proposalId
    ) public view virtual override(Governor, GovernorTimelockControl) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @inheritdoc Governor
     */
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @inheritdoc Governor
     */
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @inheritdoc Governor
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @inheritdoc Governor
     */
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
