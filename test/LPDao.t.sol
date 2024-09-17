// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";

import {LPDao} from "../src/LPDao.sol";
import {OnOffExtension} from "../src/OnOffExtension.sol";


contract LPDaoTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    LPDao hook;
    MockERC20 weth;
    MockERC20 alt;
    PoolId poolId;

    address user1 = address(0x123);
    address user2 = address(0x456);
    uint256 amount = 1e18;

    address fundManager = address(1234);

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);
        // fakeWeth = new MyERC20();

        weth = MockERC20(Currency.unwrap(currency0));
        alt = MockERC20(Currency.unwrap(currency1));
        // fakeWeth = Currency.unwrap(currency0);

        // Deploy the hook to an address with the correct flags
        address payable flags = payable(address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        ));
        bytes memory constructorArgs = abi.encode(manager, posm, permit2, Currency.unwrap(currency0)); //Add all the necessary constructor arguments from the hook
        deployCodeTo("LPDao.sol:LPDao", constructorArgs, flags);
        hook = LPDao(flags);

        hook.setFundManager(fundManager);

        // Create the pool
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = key.toId();

        vm.prank(fundManager);
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        OnOffExtension onOffHook = new OnOffExtension(fundManager);
        hook.setProxy(address(onOffHook));
    }

    function testDepositLiquidity() public {
        // Simulate user approval and transfer before deposit
        weth.mint(user1, amount);
        alt.mint(user1, amount);
        vm.prank(user1);
        weth.approve(address(hook), amount);
        vm.prank(user1);
        alt.approve(address(hook), amount);
        
        vm.prank(user1);
        uint256 tokenId = hook.depositLiquidity(key, -100020, 100020, amount, amount, amount);

        // Check if deposit was successful

        (address user,,
        uint token0Amount,
        uint token1Amount) = hook.userPositions(tokenId);
        assertEq(user, user1);
        // Got these numbers from a console.log...
        assertEq(token0Amount, 993267104342174101);
        assertEq(token1Amount, 993267104342174101);
    }

    function testWithdrawLiquidity() public {
        // First deposit - same logic as previous test
        weth.mint(user1, amount);
        alt.mint(user1, amount);
        vm.prank(user1);
        weth.approve(address(hook), amount);
        vm.prank(user1);
        alt.approve(address(hook), amount);
        vm.prank(user1);
        uint256 tokenId = hook.depositLiquidity(key, -100020, 100020, amount, amount, amount);

        // Now try to withdraw liquidity
        vm.prank(user1);
        hook.withdrawLiquidity(tokenId);

        // Verify that the liquidity was withdrawn and userPositions is cleared
        (address user,,
        uint token0Amount,
        uint token1Amount) = hook.userPositions(tokenId);

        assertEq(user, address(0)); // Should be cleared after withdrawal
    }
}

