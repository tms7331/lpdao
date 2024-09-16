// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {AuctionExtension} from "../src/AuctionExtension.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

contract FakePoolManager {
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        returns (BalanceDelta)
    {
        BalanceDelta zeroDelta = BalanceDelta.wrap(0);
        return zeroDelta;
    }
}


contract AuctionExtensionTest is Test {
    AuctionExtension auction;
    address hook = address(0x456);
    address poolManager;
    PoolKey key;
    
    address user1 = address(0x111);
    address user2 = address(0x222);
    uint256 blockNumber = 100;
    uint256 minBid = 0.01 ether;

    function setUp() public {
        // Set up initial values for the PoolKey (mocked)

        FakePoolManager fakePoolManager = new FakePoolManager();
        poolManager = address(fakePoolManager);

        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(0xABC)), 3000, 60, IHooks(hook));

        // Deploy Auction contract
        auction = new AuctionExtension(hook, poolManager);

        // Label addresses for easier debugging
        vm.label(hook, "Hook");
        vm.label(poolManager, "Pool Manager");
        vm.label(user1, "User 1");
        vm.label(user2, "User 2");
    }

    function testCannotBidBelowMinimum() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("Bid too low!");
        auction.placeBid{value: 0.005 ether}(key, blockNumber);
    }

    function testPlaceBid() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        auction.placeBid{value: minBid}(key, blockNumber);

        (address bidder, uint256 amount) = auction.winningBids(key.toId(), blockNumber);
        assertEq(bidder, user1);
        assertEq(amount, minBid);
    }


    function testOutbidAndRefundPreviousBidder() public {
        // First bid by user1
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        auction.placeBid{value: minBid}(key, blockNumber);

        // Second bid by user2 with higher value
        vm.deal(user2, 2 ether);
        vm.prank(user2);

        uint256 user1BalanceBefore = user1.balance;
        auction.placeBid{value: 0.02 ether}(key, blockNumber);
        
        (address bidder, uint256 amount) = auction.winningBids(key.toId(), blockNumber);
        assertEq(bidder, user2);
        assertEq(amount, 0.02 ether);

        uint256 user1BalanceAfter = user1.balance;
        // Make sure we refunded the first user
        assertEq(user1BalanceAfter, user1BalanceBefore + minBid);
    }


    function testSwapByWinningBidder() public {
        // Place a bid first
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        auction.placeBid{value: minBid}(key, blockNumber);

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 0.01 ether, sqrtPriceLimitX96: 0});

        // Ensure only hook can call checkSwap
        vm.prank(user1);
        vm.expectRevert("Only hook!");
        auction.checkSwap(user1, key, swapParams, "");

        // Simulate the hook making the call and the winner performing the swap
        vm.roll(blockNumber);
        vm.prank(hook);
        auction.checkSwap(user1, key, swapParams, "");

        // Check the bid amount is reset after swap
        (address bidder, uint256 amount) = auction.winningBids(key.toId(), blockNumber);
        assertEq(amount, 0);
    }

}