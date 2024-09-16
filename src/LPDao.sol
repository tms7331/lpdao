// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {Address} from "v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
// TODO - horrible to import from test folder, copy this logic over here?
import {EasyPosm} from "../test/utils/EasyPosm.sol";
import {Voting} from "./Voting.sol";


contract LPDao is BaseHook, Voting {
    using PoolIdLibrary for PoolKey;
    using EasyPosm for IPositionManager;
    using LPFeeLibrary for uint24;
    using Address for address;

    IPositionManager posm;
    IAllowanceTransfer permit2;

    event Deposit(address indexed user, address indexed token, PoolId indexed poolId, uint256 amount);
    event Withdraw(address indexed user, address indexed token, PoolId indexed poolId, uint256 amount);

    struct LPPosition {
        address user;
        PoolKey poolKey;
        uint token0Amount;
        uint token1Amount;
    }
    mapping(uint tokenId => LPPosition position) public userPositions;

    constructor(IPoolManager _poolManager, IPositionManager _posm, IAllowanceTransfer _permit2) BaseHook(_poolManager) {
        posm = _posm;
        permit2 = _permit2;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }


    function approvePosmCurrency(Currency currency) internal {
        // Because POSM uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        // 2. Then, the caller must approve POSM as a spender of permit2. TODO: This could also be a signature.
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }


    function depositLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint256 amount) external returns (uint256 tokenId) {
        approvePosmCurrency(key.currency0);
        approvePosmCurrency(key.currency1);

        // Need to transfer the currendies to our contract
        // TODO - have to figure out actual amounts here, which might not be easy
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amount);

        uint256 MAX_SLIPPAGE_ADD_LIQUIDITY = type(uint256).max;
        uint256 MAX_SLIPPAGE_REMOVE_LIQUIDITY = 0;

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            amount,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp,
            ""
        );
    }

    function withdrawLiquidity(uint256 tokenId) external {
        LPPosition memory lpp = userPositions[tokenId];
        require(lpp.user == msg.sender, "Not authorized");
        PoolKey memory key = lpp.poolKey;

        // TODO - let them set the min amounts?
        uint256 amount0Min = 0;
        uint256 amount1Min = 0;
        BalanceDelta delta = posm.burn(
            tokenId,
            amount0Min,
            amount1Min,
            address(this),
            block.timestamp,
            ""
        );

        uint startingToken0Amount = lpp.token0Amount;
        uint startingToken1Amount = lpp.token1Amount;
        uint endingToken0Amount = uint128(delta.amount0());
        uint endingToken1Amount = uint128(delta.amount1());

        // Have to call slot0...
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = StateLibrary.getSlot0(poolManager, key.toId());
        int profit = calculateProfit(
                    startingToken0Amount,
                    startingToken1Amount,
                    endingToken0Amount,
                    endingToken1Amount,
                    sqrtPriceX96
                );

        // TODO - send back to user

    }


    function beforeInitialize(address initializer, PoolKey calldata key, uint160, bytes calldata) external override returns (bytes4) {
        // TODO - enable
        require(initializer == fundManager, "Only fund manager can initialize");
        require(key.currency0 == Currency.wrap(address(0)) || key.currency1 == Currency.wrap(address(0)), "One currency must be ETH");
        
        // Our beforeSwap logic relies on pool fees being dynamic
        require(key.fee.isDynamicFee(), "Pool must have dynamic fee");
        return BaseHook.beforeInitialize.selector;
    }

    function beforeSwap(address swapper, PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, bytes calldata data)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {

        (bool canSwap, bool feeAdj, uint fee) = proxy.checkSwap(swapper, key, swapParams, data);
        require(canSwap, "Swap not allowed");

        if (feeAdj) {
            uint overrideFee = fee | uint256(LPFeeLibrary.OVERRIDE_FEE_FLAG);
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, uint24(overrideFee));
        }
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function beforeAddLiquidity(
        address depositor,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata liqParams,
        bytes calldata data
    ) external override returns (bytes4) {
        bool canAddLiquidity = proxy.checkAddLiquidity(depositor, key, liqParams, data);
        require(canAddLiquidity, "Add liquidity not allowed");

        int liqAmount = (liqParams.tickUpper - liqParams.tickLower) * liqParams.liquidityDelta;
        // Here liquidityDelta will always be positive
        depositedLiquidity[depositor] += uint(liqAmount);
        return BaseHook.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address depositor,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata liqParams,
        bytes calldata
    ) external override returns (bytes4) {
        int liqAmount = (liqParams.tickUpper - liqParams.tickLower) * liqParams.liquidityDelta;
        // Here liquidityDelta will always be negative
        depositedLiquidity[depositor] -= uint(-liqAmount);
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function sqrt(uint x) internal pure returns (uint) {
        if (x == 0) return 0;
        uint z = (x + 1) / 2;
        uint y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function calculateProfit(
        uint startingToken0Amount,
        uint startingToken1Amount,
        uint endingToken0Amount,
        uint endingToken1Amount,
        uint sqrtPriceX96
    ) internal pure returns (int256) {
        /*
        Python test from ETH/USDT pool:
        Starting balances (say start price was 2000):
        2000 USDT
        1 ETH

        Ending balances (price 2298):
        2999.2 USDT
        1.30121 ETH

        Profit in USDT should be:
        999.2 USDT + .30121 * 2298 ETH = 1691 USDT

        Using sqrtPriceX96 math:
        sqrtPriceX96 = 3798623369673169567643029
        sv = 2000 * 10**6 + 1 * 10**18 * (sqrtPriceX96 / 2**96) ** 2
        ev =  2999.2 * 10**6 + 1.30121 * 10**18 * (sqrtPriceX96 / 2**96) ** 2
        ev - sv
        >>> 1691608977.4882383
        >>> _/10**6
        1691.6089774882382

        To save precision use the sqrt of the amounts:
        1 * 10**18 * (sqrtPriceX96 / 2**96) ** 2
        is equivalent to
        ((1 * 10**18)**.5 * sqrtPriceX96 / 2**96) ** 2
        */
        uint Q96 = 2**96;
        uint startingValue = startingToken1Amount + FullMath.mulDiv(sqrt(startingToken0Amount), sqrtPriceX96, Q96) ** 2;
        uint endingValue = endingToken1Amount + FullMath.mulDiv(sqrt(endingToken0Amount), sqrtPriceX96, Q96) ** 2;
        int256 profit = int(endingValue) - int(startingValue);
        return profit;
    }
}
