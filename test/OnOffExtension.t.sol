// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {OnOffExtension} from "../src/OnOffExtension.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract OnOffHookTest is Test {
    OnOffExtension public onOff;
    address hook = address(0x456);
    address public fundManager = address(0x123);
    address public depositor = address(0x456);
    IPoolManager.SwapParams swapParams;
    PoolKey public key;
    PoolId public poolId;

    function setUp() public {
        // Initialize the hook contract with the fund manager address
        onOff = new OnOffExtension(fundManager);

        // Create a dummy PoolKey for testing
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(0xABC)), 3000, 60, IHooks(hook));
        poolId = key.toId();

        swapParams = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 0.01 ether, sqrtPriceLimitX96: 0});
    }

    function testSetDepositWhitelistActive() public {
        // Ensure only the fund manager can activate deposit whitelist
        vm.prank(fundManager);
        onOff.setDepositWhitelistActive(true);
        // No revert means the function succeeded
    }

    function testSetSwapCheckActive() public {
        // Ensure only the fund manager can activate swap check
        vm.prank(fundManager);
        onOff.setSwapCheckActive(true);
        // No revert means the function succeeded
    }

    function testSetPoolActive() public {
        // Set pool active using fund manager
        vm.prank(fundManager);
        onOff.setPoolActive(poolId, true);

        // Check that the pool is active
        bool isActive = onOff.activePool(poolId);
        assertTrue(isActive, "Pool should be active");
    }

    function testSetDepositWhitelist() public {
        // Set deposit whitelist for a user
        vm.prank(fundManager);
        onOff.setDepositWhitelist(poolId, depositor, true);

        // Check that the user is whitelisted
        bool isWhitelisted = onOff.depositWhitelist(poolId, depositor);
        assertTrue(isWhitelisted, "Depositor should be whitelisted");
    }

    function testCheckAddLiquidity() public {
        // Test when deposit whitelist is inactive
        bool canAddLiquidity = onOff.checkAddLiquidity(depositor, key, swapParams, "");
        assertTrue(canAddLiquidity, "Should allow liquidity addition when whitelist is inactive");

        // Activate deposit whitelist and set the user as whitelisted
        vm.prank(fundManager);
        onOff.setDepositWhitelistActive(true);
        vm.prank(fundManager);
        onOff.setDepositWhitelist(poolId, depositor, true);

        // Now check if the user can add liquidity when whitelist is active
        canAddLiquidity = onOff.checkAddLiquidity(depositor, key, swapParams, "");
        assertTrue(canAddLiquidity, "Should allow whitelisted depositor to add liquidity");

        // Check for a non-whitelisted user
        address nonWhitelisted = address(0x789);
        canAddLiquidity = onOff.checkAddLiquidity(nonWhitelisted, key, swapParams, "");
        assertFalse(canAddLiquidity, "Should not allow non-whitelisted user to add liquidity");
    }

    function testCheckSwap() public {
        // Test when swap check is inactive
        (bool canSwap, ,) = onOff.checkSwap(address(0), key, swapParams, "");
        assertTrue(canSwap, "Should allow swap when swap check is inactive");

        // Activate swap check and activate the pool
        vm.prank(fundManager);
        onOff.setSwapCheckActive(true);
        vm.prank(fundManager);
        onOff.setPoolActive(poolId, true);

        // Now check if swapping is allowed for active pool
        (canSwap, ,) = onOff.checkSwap(address(0), key, swapParams, "");
        assertTrue(canSwap, "Should allow swap for active pool");

        // Deactivate the pool and check again
        vm.prank(fundManager);
        onOff.setPoolActive(poolId, false);
        (canSwap, ,) = onOff.checkSwap(address(0), key, swapParams, "");
        assertFalse(canSwap, "Should not allow swap for inactive pool");
    }

    function testOnlyFundManagerCanModifySettings() public {
        // Attempt to modify settings from a non-fund manager address should fail
        vm.expectRevert("Only manager can call this function");
        onOff.setDepositWhitelistActive(true);

        vm.expectRevert("Only manager can call this function");
        onOff.setSwapCheckActive(true);

        vm.expectRevert("Only manager can call this function");
        onOff.setPoolActive(poolId, true);

        vm.expectRevert("Only manager can call this function");
        onOff.setDepositWhitelist(poolId, depositor, true);
    }
}
