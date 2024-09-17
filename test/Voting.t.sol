// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Voting, VotingToken} from "../src/Voting.sol";

contract VotingMock is Voting {
    constructor() {}

    function setDepositedLiquidity(address user, uint256 amount) external {
        depositedLiquidity[user] = amount;
    }
}

contract VotingTest is Test {
    VotingMock voting;
    VotingToken votingToken;
    address manager = address(1);
    address voter1 = address(2);
    address voter2 = address(3);
    address newManager = address(4);
    address proxy = address(5);

    function setUp() public {
        // Deploy the Voting contract
        voting = new VotingMock();
        
        // Fund voter1 and voter2
        vm.deal(voter1, 100 ether);
        vm.deal(voter2, 100 ether);
        
        // Deposit liquidity (simulated by directly setting the deposit mapping)
        voting.setDepositedLiquidity(voter1, 10);
        voting.setDepositedLiquidity(voter2, 10);
    }

    function testSetProxy() public {
        // Ensure that proxy is set correctly
        voting.setProxy(proxy);
        assertEq(address(voting.proxy()), proxy);
    }

    function testProposeNewManager() public {
        // voter1 proposes a new manager
        vm.prank(voter1);
        voting.proposeNewManager(newManager);
        
        (address proposedAddress,,,,,, bool active,,) = voting.proposals(0);
        assertEq(proposedAddress, newManager);
        assertTrue(active);
    }

    function testGetTokensForVote() public {
        // Propose new manager and mint tokens for voting
        vm.prank(voter1);
        voting.proposeNewManager(newManager);

        vm.prank(voter1);
        voting.getTokensForVote(0);
        
        // Check token balance
        (address proposedAddress,,
        VotingToken votingToken,
        uint votesFor,
        uint votesAgainst,
        bool active,
        bool isManagerProposal,
        uint createdAt,
        uint actionAvailableAt) = voting.proposals(0);
        assertEq(votingToken.balanceOf(voter1), 10);
    }

    function testVoteOnProposal() public {
        // Propose a new manager and vote on the proposal
        vm.prank(voter1);
        voting.proposeNewManager(newManager);

        vm.prank(voter1);
        voting.getTokensForVote(0);

        // voter1 votes for the proposal
        vm.prank(voter1);
        voting.voteOnProposal(0, 10, true);

        // Verify vote count
        (address proposedAddress,,
        VotingToken votingToken,
        uint votesFor,
        uint votesAgainst,
        bool active,
        bool isManagerProposal,
        uint createdAt,
        uint actionAvailableAt) = voting.proposals(0);

        assertEq(votesFor, 10);
        assertEq(votesAgainst, 0);
    }

    function testUpdateManager() public {
        // Propose a new manager and vote to approve
        vm.prank(voter1);
        voting.proposeNewManager(newManager);
        vm.prank(voter1);
        voting.getTokensForVote(0);
        vm.prank(voter1);
        voting.voteOnProposal(0, 10, true);

        // Forward time to allow the action
        vm.warp(block.timestamp + 2 weeks);

        // Update the manager
        vm.prank(voter1);
        voting.updateManager(0);

        // Check that the manager was updated
        assertEq(voting.fundManager(), newManager);
    }
}
