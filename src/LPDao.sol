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
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Address} from "v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Voting} from "./Voting.sol";


contract LPDao is BaseHook, Voting {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;


    using Address for address;

    // Mapping from poolId to user to their deposit balance
    mapping(PoolId => mapping(address => uint256)) public userDepositBalance;


    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;
    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    event Deposit(address indexed user, address indexed token, PoolId indexed poolId, uint256 amount);
    event Withdraw(address indexed user, address indexed token, PoolId indexed poolId, uint256 amount);

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
    }


    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
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
        beforeSwapCount[key.toId()]++;

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
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        beforeAddLiquidityCount[key.toId()]++;

        // (bool success, bytes memory data) = proxy.delegatecall(
        //     abi.encodeWithSignature("checkAddLiquidity(uint256)", 33)
        // );
        // require(success, "Delegatecall failed");
        // bool decision = abi.decode(data, (bool));
        // require(decision, "Decision failed");

        return BaseHook.beforeAddLiquidity.selector;
    }

    // Fallback function to forward calls to the proxy
    fallback() external payable {
        require(msg.sender == manager, "Only pool manager can interact with proxy");

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
