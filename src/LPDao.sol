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
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Address} from "v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Voting} from "./Voting.sol";

import {EasyPosm} from "../test/utils/EasyPosm.sol";


contract LPDao is BaseHook, Voting {
    using PoolIdLibrary for PoolKey;
    using EasyPosm for IPositionManager;
    using LPFeeLibrary for uint24;
    using Address for address;

    IPositionManager posm;
    IAllowanceTransfer permit2;

    event Deposit(address indexed user, address indexed token, PoolId indexed poolId, uint256 amount);
    event Withdraw(address indexed user, address indexed token, PoolId indexed poolId, uint256 amount);

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
        // TODO - have to make sure the tokenId belongs to msg.sender
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
        // TODO - have to send thse back to user
        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();
    }


    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata) external override returns (bytes4) {
        // TODO - enable
        // require(msg.sender == manager, "Only pool manager can initialize");
        // require(key.currency0 == Currency.wrap(address(0)) || key.currency1 == Currency.wrap(address(0)), "One currency must be ETH");
        
        // Our beforeSwap logic relies on pool fees being dynamic
        // require(key.fee.isDynamicFee(), "Pool must have dynamic fee");
        return BaseHook.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {

        // (bool success, bytes memory data) = proxy.delegatecall(
        //     abi.encodeWithSignature("checkSwap(uint256)", 33)
        // );
        // require(success, "Delegatecall failed");
        // bool decision = abi.decode(data, (bool));
        // require(decision, "Decision failed");

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }


    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override returns (bytes4) {

        int liqAmount = (params.tickUpper - params.tickLower) * params.liquidityDelta;
        // Here liquidityDelta will always be positive
        depositedLiquidity[msg.sender] += uint(liqAmount);

        // (bool success, bytes memory data) = proxy.delegatecall(
        //     abi.encodeWithSignature("checkAddLiquidity(uint256)", 33)
        // );
        // require(success, "Delegatecall failed");
        // bool decision = abi.decode(data, (bool));
        // require(decision, "Decision failed");

        return BaseHook.beforeAddLiquidity.selector;
    }


    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override returns (bytes4) {
        int liqAmount = (params.tickUpper - params.tickLower) * params.liquidityDelta;
        // Here liquidityDelta will always be negative
        depositedLiquidity[msg.sender] -= uint(-liqAmount);
        return BaseHook.beforeRemoveLiquidity.selector;
    }


    // Fallback function to forward calls to the proxy
    fallback() external payable {
        require(msg.sender == fundManager, "Only fund manager can interact with proxy");

        address _proxy = proxy;
        require(_proxy != address(0), "Proxy address not set");

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the proxy.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), _proxy, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
