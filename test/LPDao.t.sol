// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {LPDao} from "../src/LPDao.sol";
import {OnOffHook} from "../src/OnOffExtension.sol";

contract LPDaoTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    LPDao hook;
    PoolId poolId;

    address daoManager = address(1234);

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address payable flags = payable(address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        ));
        bytes memory constructorArgs = abi.encode(manager, posm, permit2); //Add all the necessary constructor arguments from the hook
        deployCodeTo("LPDao.sol:LPDao", constructorArgs, flags);
        hook = LPDao(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        OnOffHook onOffHook = new OnOffHook(daoManager);
        hook.setProxy(address(onOffHook));

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            10_000e18,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testLPDaoHooks() public {
        // positions were created in setup()
        // assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        // assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        // assertEq(hook.beforeSwapCount(poolId), 0);
        // assertEq(hook.afterSwapCount(poolId), 0);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        // assertEq(hook.beforeSwapCount(poolId), 1);
        // assertEq(hook.afterSwapCount(poolId), 1);
    }

    function testLiquidityHooks() public {
        // positions were created in setup()
        // assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        // assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        posm.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        // assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        // assertEq(hook.beforeRemoveLiquidityCount(poolId), 1);
    }


    function testDepositLiquidity() public {
        PoolKey memory k = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        int24 tLower = TickMath.minUsableTick(key.tickSpacing);
        int24 tUpper = TickMath.maxUsableTick(key.tickSpacing);
        uint256 amount = 10_000e18;
        IERC20(Currency.unwrap(key.currency0)).approve(address(hook), amount);
        IERC20(Currency.unwrap(key.currency1)).approve(address(hook), amount);
        hook.depositLiquidity(k, tLower, tUpper, amount);
        // If we make it here without reverting, we were successful...
    }



}
