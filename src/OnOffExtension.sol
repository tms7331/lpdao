// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";


contract OnOffExtension {
    using PoolIdLibrary for PoolKey;
    mapping(PoolId => bool) public activePool;
    mapping(PoolId => mapping(address => bool)) public depositWhitelist;
    address public fundManager;
    bool depositWhitelistActive;
    bool swapCheckActive;

    modifier onlyFundManager() {
        require(msg.sender == fundManager, "Only manager can call this function");
        _;
    }

    constructor(address _fundManager) {
        fundManager = _fundManager;
    }

    function setDepositWhitelistActive(bool _active) external onlyFundManager {
        depositWhitelistActive = _active;
    }

    function setSwapCheckActive(bool _active) external onlyFundManager {
        swapCheckActive = _active;
    }

    function setPoolActive(PoolId poolId, bool _active) external onlyFundManager {
        activePool[poolId] = _active;
    }

    function setDepositWhitelist(PoolId poolId, address user, bool _whitelisted) external onlyFundManager {
        depositWhitelist[poolId][user] = _whitelisted;
    }

    function checkAddLiquidity(address depositor, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata) public view returns (bool) {
        return !depositWhitelistActive || depositWhitelist[key.toId()][depositor];
    }

    function checkSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata) public view returns (bool, bool, uint) {
        return (!swapCheckActive || activePool[key.toId()], false, 0);
    }
}
