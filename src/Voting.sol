// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract VotingToken is ERC20 {
    address private votingContract;
    // Can only let each user mint once
    mapping(address => bool) private minted;
    constructor(address _votingContract) ERC20("LPDao Voting Token", "VOTE") {
        votingContract = _votingContract;
    }

    modifier onlyVotingContract() {
        require(msg.sender == votingContract, "Not the manager");
        _;
    }

    function mint(address to, uint256 amount) external onlyVotingContract {
        require(!minted[to], "Already minted");
        minted[to] = true;
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVotingContract {
        _burn(from, amount);
    }
}


interface IProxy {
    function checkSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata) external returns (bool, bool, uint);
    function checkAddLiquidity(address depositor, PoolKey calldata key, IPoolManager.ModifyLiquidityParams calldata, bytes calldata) external returns (bool);
    function upgradeToAndCall(address, bytes memory) external;
}

contract Voting {
    IProxy public proxy;
    address public fundManager;

    uint public constant VOTING_DURATION = 1 weeks;
    uint public constant ACTION_DELAY = 1 weeks;

    struct Proposal {
        address proposedAddress;
        bytes data;
        VotingToken votingToken;
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
    // Track how much each user has deposited
    mapping(address => uint) public depositedLiquidity;

    modifier onlyFundManager() {
        require(msg.sender == fundManager, "Not the fund manager");
        _;
    }

    event ProposalCreated(uint proposalId, address proposedAddress, bool isManagerProposal);
    event VoteCast(uint proposalId, address voter, uint amount, bool voteFor);
    event ManagerUpdated(address newManager);
    event ProxyUpdated(address newProxy);

    function setProxy(address _proxy) external {
        // Only allow it to be set once, think it's ok not to have any access control
        // as there's no benefit to someone frontrunning and setting it to a random address
        require(address(proxy) == address(0), "Proxy already set");
        require(_proxy != address(0), "Invalid proxy address");
        proxy = IProxy(_proxy);
    }

    function setFundManager(address _fundManager) external {
        // Only allow it to be set once on initialization so we don't have to wait
        // a week to get it set
        require(address(fundManager) == address(0), "Fund manager already set");
        require(_fundManager != address(0), "Invalid fund manager address");
        fundManager = _fundManager;
    }

    function proposeNewManager(address _newFundManager) external {
        require(_newFundManager != address(0), "Invalid address");
        require(_newFundManager != fundManager, "Already the manager");
        require(depositedLiquidity[msg.sender] > 0, "Must be a DAO participant to propose new manager!");
        
        VotingToken votingToken = new VotingToken(address(this));

        proposals[proposalCount] = Proposal({
            proposedAddress: _newFundManager,
            data: bytes(""),
            votingToken: votingToken,
            votesFor: 0,
            votesAgainst: 0,
            active: true,
            isManagerProposal: true,
            createdAt: block.timestamp,
            actionAvailableAt: block.timestamp + VOTING_DURATION + ACTION_DELAY
        });
        emit ProposalCreated(proposalCount, _newFundManager, true);
        proposalCount++;
    }

    function proposeNewProxy(address _newProxy, bytes memory _data) external onlyFundManager {
        VotingToken votingToken = new VotingToken(address(this));

        proposals[proposalCount] = Proposal({
            proposedAddress: _newProxy,
            data: _data,
            votingToken: votingToken,
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
        Proposal storage proposal = proposals[_proposalId];
        uint256 amount = depositedLiquidity[msg.sender];
        // mint function stores address to prevent double minting
        proposal.votingToken.mint(msg.sender, amount);
    }

    function voteOnProposal(uint _proposalId, uint amount, bool _voteFor) external {
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
        // This will revert if the user doesn't have enough tokens
        proposal.votingToken.burn(msg.sender, amount);

        emit VoteCast(_proposalId, msg.sender, amount, _voteFor);
    }

    function updateManager(uint _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.active, "Proposal is not active");
        require(proposal.isManagerProposal, "Not a manager proposal");
        require(block.timestamp >= proposal.actionAvailableAt, "Action period has not started");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal not approved");

        fundManager = proposal.proposedAddress;
        proposal.active = false;

        emit ManagerUpdated(fundManager);
    }

    function updateProxy(uint _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.active, "Proposal is not active");
        require(!proposal.isManagerProposal, "Not a proxy proposal");
        require(block.timestamp >= proposal.actionAvailableAt, "Action period has not started");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal not approved");

        proxy.upgradeToAndCall(proposal.proposedAddress, proposal.data);

        proposal.active = false;

        emit ProxyUpdated(proposal.proposedAddress);
    }
}
