// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";


contract AuctionExtension {
    using PoolIdLibrary for PoolKey;

    uint256 public constant MINIMUM_BID = 0.01 ether;
    address public hook;
    address public poolManager;
    // PoolKey => block number => winning bid
    mapping(PoolId => mapping(uint256 => Bid)) public winningBids;

    struct Bid {
        address bidder;
        uint256 amount;
    }

    constructor(address _hook, address _poolManager) {
        hook = _hook;
        poolManager = _poolManager;
    }

    // Function to place a bid in a specific pool for a specific block number
    function placeBid(PoolKey calldata key, uint256 blockNumber) external payable {
        require(msg.value >= MINIMUM_BID, "Bid too low!");

        Bid memory currentWinningBid = winningBids[key.toId()][blockNumber];
        require(msg.value > currentWinningBid.amount, "Bid must be higher than current winning bid");


        // If we have a previous bid, need to refund that user's ETH
        // Security issue - if winning bidder is a contract without a receive function this could fail?
        if (currentWinningBid.amount > 0) {
            (bool success, ) = currentWinningBid.bidder.call{value: currentWinningBid.amount}("");
            require(success, "ETH transfer failed");
        }

        winningBids[key.toId()][blockNumber] = Bid({
            bidder: msg.sender,
            amount: msg.value
        });
    }

    function checkAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata) public view returns (bool) {
        return true;
    }

    function checkSwap(address swapper, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata) public returns (bool, bool, uint) {
        require(msg.sender == hook, "Only hook!");
        PoolId poolId = key.toId();
        Bid memory currentWinningBid = winningBids[poolId][block.number];
        uint bidEthAmount = currentWinningBid.amount;
        // If bid is 0 - there was no bid or we already processed it
        if (bidEthAmount == 0) {
            return (true, false, 0);
        }
        // Otherwise we need to check that the swap is from the auction winner
        require(swapper == currentWinningBid.bidder, "Only auction winner can call this function");

        // If we've made it here - it's the winning bidder, let the swap go through and donate funds to pool
        delete winningBids[poolId][block.number];

        // Also want to donate the ETH to the pool
        if (Currency.unwrap(key.currency0) == address(0)) {
            IPoolManager(poolManager).donate(key, bidEthAmount, 0, "");
        } else {
            // We check that one of the currencies will be ETH in the hook
            IPoolManager(poolManager).donate(key, 0, bidEthAmount, "");
        }

        return (true, false, 0);
    }

    function donateBid(PoolKey calldata key, uint256 blockNumber) external {
        // If they win a bid but don't swap, their bid amount is locked in the contract
        // So let anyone call this to donate past bids...
        PoolId poolId = key.toId();
        Bid memory currentWinningBid = winningBids[poolId][blockNumber];
        require(blockNumber < block.number, "Must be a past block");
        require(currentWinningBid.amount > 0, "No bid to donate");
        uint bidEthAmount = currentWinningBid.amount;
        delete winningBids[poolId][block.number];

        if (Currency.unwrap(key.currency0) == address(0)) {
            IPoolManager(poolManager).donate(key, bidEthAmount, 0, "");
        } else {
            // We check that one of the currencies will be ETH in the hook
            IPoolManager(poolManager).donate(key, 0, bidEthAmount, "");
        }
    }
}

