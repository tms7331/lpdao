// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
    address weth;

    event Deposit(address indexed user, address indexed token, PoolId indexed poolId, uint amount);
    event Withdraw(address indexed user, address indexed token, PoolId indexed poolId, uint amount);

    struct LPPosition {
        address user;
        PoolKey poolKey;
        uint token0Amount;
        uint token1Amount;
    }
    mapping(uint tokenId => LPPosition position) public userPositions;

    constructor(IPoolManager _poolManager, IPositionManager _posm, IAllowanceTransfer _permit2, address _weth) BaseHook(_poolManager) {
        posm = _posm;
        permit2 = _permit2;
        weth = _weth;
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
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint).max);
        // 2. Then, the caller must approve POSM as a spender of permit2. TODO: This could also be a signature.
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }


    function depositLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint amount0, uint amount1, uint liquidity) external returns (uint tokenId) {
        uint bal = IERC20(Currency.unwrap(key.currency0)).balanceOf(msg.sender);
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount0);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amount1);

        BalanceDelta delta;
        (tokenId, delta) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidity,
            type(uint).max,
            type(uint).max,
            address(this),
            block.timestamp,
            ""
        );

        // Delta amounts are NEGATIVE
        // Refund any extra tokens back to them
        uint amount0Refund = amount0 - uint(uint128(-delta.amount0()));
        uint amount1Refund = amount1 - uint(uint128(-delta.amount1()));
        if (amount0Refund > 0) {
            IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, amount0Refund);
        }
        if (amount1Refund > 0) {
            IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, amount1Refund);
        }

        LPPosition memory lpp = LPPosition({
            user: msg.sender,
            poolKey: key,
            token0Amount: uint128(-delta.amount0()),
            token1Amount: uint128(-delta.amount1())
        });
        userPositions[tokenId] = lpp;
    }

    function withdrawLiquidity(uint tokenId) external {
        LPPosition memory lpp = userPositions[tokenId];
        require(lpp.user == msg.sender, "Not authorized");
        PoolKey memory key = lpp.poolKey;

        // TODO - let them set the min amounts?
        uint amount0Min = 0;
        uint amount1Min = 0;
        BalanceDelta delta = posm.burn(
            tokenId,
            amount0Min,
            amount1Min,
            address(this),
            block.timestamp,
            ""
        );

        uint endingToken0Amount = uint128(delta.amount0());
        uint endingToken1Amount = uint128(delta.amount1());

        // Have to call slot0...
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = StateLibrary.getSlot0(poolManager, key.toId());
        int profit = calculateProfit(
                    lpp.token0Amount,
                    lpp.token1Amount,
                    endingToken0Amount,
                    endingToken1Amount,
                    sqrtPriceX96
                );

        // Send 20% of profit to the fundManager, and return rest to the user

        // TODO - profit is calculated in token1, but logic below will fail if their
        // position doesn't have enough token1

        IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, endingToken0Amount);

        // Only transfer if profit > 0!!
        if (profit > 0) {
            // Remember - this is in token1!
            uint fundManagerProfit = uint(profit) / 5;
            IERC20(Currency.unwrap(key.currency1)).transfer(fundManager, uint(fundManagerProfit));
            endingToken1Amount -= fundManagerProfit;
        }
        IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, endingToken1Amount);

        delete userPositions[tokenId];
    }

    function beforeInitialize(address initializer, PoolKey calldata key, uint160, bytes calldata) external override returns (bytes4) {
        require(initializer == fundManager, "Only fund manager can initialize");
        require(key.currency0 == Currency.wrap(weth) || key.currency1 == Currency.wrap(weth), "One currency must be WETH");
        // Our beforeSwap logic relies on pool fees being dynamic
        require(key.fee.isDynamicFee(), "Pool must have dynamic fee");

        // This does a max approval, would it ever be possible to use all of it?
        approvePosmCurrency(key.currency0);
        approvePosmCurrency(key.currency1);

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
            uint overrideFee = fee | uint(LPFeeLibrary.OVERRIDE_FEE_FLAG);
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
        // 'depositor' is actually posm.  Is there some way to constrain it to the hook?
        // require(depositor == address(this), "Only this contract can add liquidity");
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
