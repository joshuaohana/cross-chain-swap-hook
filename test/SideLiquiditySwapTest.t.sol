// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapHook} from "../src/Swap.sol";

contract SideLiquidityUsageTest is BaseTest {
    function test_swap_insufficientLiquidity() public {
        Balances memory balancesBefore = getBalances();

        // Arrange: no side liquidity regular pool
        uint256 amountOutMinimum = 9 ether;
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) =
            prepSwapWithoutSideLiquidity(10 ether, amountOutMinimum);

        // Act: swap
        token0.approve(address(swapRouter), 10 ether);
        vm.recordLogs();
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        // Assert: SwapIntent NOT emitted and swap completes normally
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool swapIntentEmitted = false;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == SwapHook.SwapIntent.selector) {
                swapIntentEmitted = true;
                break;
            }
        }
        assertEq(swapIntentEmitted, false, "SwapIntent should not be emitted");

        // asset user spent 10 token0, received 10 token1
        Balances memory balancesAfter = getBalances();
        assertEq(balancesAfter.token0User, balancesBefore.token0User - 10 ether, "User should have spent 10 token0");
        assertGt(
            balancesAfter.token1User,
            balancesBefore.token1User + amountOutMinimum,
            "User should have received more than 9 token1"
        );
    }

    // TODO test reserves are updated correctly

    function test_swap_betterPriceFound_insufficientLiquidity() public {
        // Arrange:
        // - no side liquidity

        // TODO uneeded test but just a double check?
    }

    function test_swap_betterPriceFound_sufficientLiquidity() public {
        // Arrange:
        // - have side liquidity

        // act: do swap with betterPriceFound = true

        // assert:
        // - SwapIntent emitted
        // - swap completes off-chain
        // - reserves/pending are updated correctly
        // - user receives expected token1

        // assert

        // before swap, nothing
        // after swap, see event

        // while waiting for off-chain bot, see pending swap
        // reserved pre-bridged liquidity is updated
        // hook gets token0

        // completeSwap with betterPriceFound = true
        // hook keeps token0
        // hook gives token1 to user from its balance
        // reserved amt updated
        // pre-bridged liquidity balance updated

        // user ends up down token0 by amountIn, and up token1 > amountOutMinimum
    }
}
