// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Voting {
    address public proxy;
    address public manager;

    uint public constant VOTING_DURATION = 1 weeks;
    uint public constant ACTION_DELAY = 1 weeks;

    struct Proposal {
        address proposedAddress;
        uint votesFor;
        uint votesAgainst;
        bool active;
        bool isManagerProposal;
        uint createdAt;
        uint actionAvailableAt;
    }

    uint public proposalCount;
    mapping(uint => Proposal) public proposals;
    mapping(uint => mapping(address => bool)) public hasVoted;

    modifier onlyManager() {
        require(msg.sender == manager, "Not the manager");
        _;
    }

    event ProposalCreated(uint proposalId, address proposedAddress, bool isManagerProposal);
    event VoteCast(uint proposalId, address voter, uint amount, bool voteFor);
    event ManagerUpdated(address newManager);
    event ProxyUpdated(address newProxy);

    function proposeNewManager(address _newManager) external {
        // TODO - only members/token holders should be able to propose new manager
        proposals[proposalCount] = Proposal({
            proposedAddress: _newManager,
            votesFor: 0,
            votesAgainst: 0,
            active: true,
            isManagerProposal: true,
            createdAt: block.timestamp,
            actionAvailableAt: block.timestamp + VOTING_DURATION + ACTION_DELAY
        });
        emit ProposalCreated(proposalCount, _newManager, true);
        proposalCount++;
    }

    function proposeNewProxy(address _newProxy) external onlyManager {
        proposals[proposalCount] = Proposal({
            proposedAddress: _newProxy,
            votesFor: 0,
            votesAgainst: 0,
            active: true,
            isManagerProposal: false,
            createdAt: block.timestamp,
            actionAvailableAt: block.timestamp + VOTING_DURATION + ACTION_DELAY
        });
        emit ProposalCreated(proposalCount, _newProxy, false);
        proposalCount++;
    }

    function getTokensForVote(uint _proposalId) external {
        // TODO - needs to calculate msg.sender's balances and mint tokens for them
    }

    function voteOnProposal(uint _proposalId, uint amount, bool _voteFor) external {
        // TODO - user needs to mint ERC20s and transfer them here
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.active, "Proposal is not active");
        require(block.timestamp <= proposal.createdAt + VOTING_DURATION, "Voting period has ended");
        require(!hasVoted[_proposalId][msg.sender], "Already voted on this proposal");

        hasVoted[_proposalId][msg.sender] = true;

        if (_voteFor) {
            proposal.votesFor += amount;
        } else {
            proposal.votesAgainst += amount;
        }

        emit VoteCast(_proposalId, msg.sender, amount, _voteFor);
    }

    function updateManager(uint _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.active, "Proposal is not active");
        require(proposal.isManagerProposal, "Not a manager proposal");
        require(block.timestamp >= proposal.actionAvailableAt, "Action period has not started");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal not approved");

        manager = proposal.proposedAddress;
        proposal.active = false;

        emit ManagerUpdated(manager);
    }

    function updateProxy(uint _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.active, "Proposal is not active");
        require(!proposal.isManagerProposal, "Not a proxy proposal");
        require(block.timestamp >= proposal.actionAvailableAt, "Action period has not started");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal not approved");

        proxy = proposal.proposedAddress;
        proposal.active = false;

        emit ProxyUpdated(proxy);
    }

    // TEMP - simplifies testing
    function setProxy(address _proxy) external {
        proxy = _proxy;
    }
}
