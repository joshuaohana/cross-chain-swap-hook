// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapHook} from "../src/Swap.sol";

contract SideLiquidityProvideTest is BaseTest {
    function test_deposit_side_liquidity() public {
        // arrange: deposit 10 token0
        Balances memory balancesBefore = getBalances();
        uint256 preBridgedLiquidityBefore = hook.preBridgedLiquidity(address(token0));
        uint256 reservedPreBridgedLiquidityBefore = hook.reservedPreBridgedLiquidity(address(token0));
        token0.approve(address(hook), 10 ether);

        // act: deposit 10 token0
        hook.depositPreBridgedLiquidity(address(token0), 10 ether);

        // assert: funds leave user, go to hook reserves, and user's allocation is updated
        Balances memory balancesAfter = getBalances();
        uint256 preBridgedLiquidityAfter = hook.preBridgedLiquidity(address(token0));
        uint256 reservedPreBridgedLiquidityAfter = hook.reservedPreBridgedLiquidity(address(token0));
        assertEq(balancesAfter.token0User, balancesBefore.token0User - 10 ether, "User should have spent 10 token0");
        assertEq(balancesAfter.token0Hook, balancesBefore.token0Hook + 10 ether, "Hook should have received 10 token0");

        assertEq(preBridgedLiquidityAfter, preBridgedLiquidityBefore + 10 ether, "Hook should have received 10 token0");
        assertEq(
            reservedPreBridgedLiquidityAfter,
            reservedPreBridgedLiquidityBefore,
            "Reserved pre-bridged liquidity should not change"
        );
        assertEq(
            hook.preBridgedLiquidityDeposits(address(this), address(token0)),
            10 ether,
            "User allocation should be 10 token0"
        );
    }

    function test_withdraw_side_liquidity() public {
        // arrange: deposit 10 token0
        Balances memory balancesBefore = getBalances();
        uint256 preBridgedLiquidityBefore = hook.preBridgedLiquidity(address(token0));
        uint256 reservedPreBridgedLiquidityBefore = hook.reservedPreBridgedLiquidity(address(token0));
        token0.approve(address(hook), 10 ether);

        // act: deposit then withdraw 10 token0
        hook.depositPreBridgedLiquidity(address(token0), 10 ether);
        hook.withdrawPreBridgedLiquidity(address(token0), 10 ether);

        // assert: funds leave hook reserves, go to user, and user's allocation is updated
        Balances memory balancesAfter = getBalances();
        uint256 preBridgedLiquidityAfter = hook.preBridgedLiquidity(address(token0));
        uint256 reservedPreBridgedLiquidityAfter = hook.reservedPreBridgedLiquidity(address(token0));
        assertEq(balancesAfter.token0User, balancesBefore.token0User, "User's token0 balance should not change");
        assertEq(balancesAfter.token0Hook, balancesBefore.token0Hook, "Hook's token0 balance should not change");

        assertEq(preBridgedLiquidityAfter, preBridgedLiquidityBefore, "Hook's pre-bridged liquidity should not change");
        assertEq(
            reservedPreBridgedLiquidityAfter,
            reservedPreBridgedLiquidityBefore,
            "Hook's reserved pre-bridged liquidity should not change"
        );
        assertEq(hook.preBridgedLiquidityDeposits(address(this), address(token0)), 0, "User allocation should be 0");
    }
}
