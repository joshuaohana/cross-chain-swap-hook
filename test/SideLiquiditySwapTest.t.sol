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

        uint256 amountOut = 9 ether;
        uint256 amountOutMinimum = 9 ether;
        uint256 amountOutReserves = amountOutMinimum + (amountOutMinimum / 10);

        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) =
            prepSwapWithSideLiquidity(10 ether, amountOutMinimum);
        Balances memory balancesBefore = getBalances();
        uint256 startingToken1SideLiquidity = hook.preBridgedLiquidity(address(token1));

        // act: do swap with betterPriceFound = true
        token0.approve(address(swapRouter), 10 ether);
        vm.recordLogs();
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        // assert:
        // - SwapIntent emitted
        // - swap completes off-chain
        // - reserves/pending are updated correctly
        // - user receives expected token1

        // assert
        Balances memory balancesMidSwap = getBalances();

        // before swap, nothing
        // after swap, see event

        Vm.Log[] memory logs = vm.getRecordedLogs();
        SwapIntentDetails memory swapIntentDetails = getSwapIntentDetails(logs);

        assertNotEq(swapIntentDetails.swapId, bytes32(0), "SwapIntent event should be emitted");

        // while waiting for off-chain bot, see pending swap
        // reserved pre-bridged liquidity is updated
        assertEq(
            hook.reservedPreBridgedLiquidity(address(token1)),
            amountOutReserves,
            "Reserved pre-bridged liquidity should be 9"
        );
        // hook gets token0
        assertEq(balancesMidSwap.token0User, balancesBefore.token0User - 10 ether, "User should have spent 10 token0");
        assertEq(
            balancesMidSwap.token0Hook, balancesBefore.token0Hook + 10 ether, "Hook should have received 10 token0"
        );

        // completeSwap with betterPriceFound = true
        hook.completeSwap(
            swapIntentDetails.swapId,
            true,
            SwapHook.OffChainSwap({
                swapId: swapIntentDetails.swapId,
                txnId: 0, // TODO verify
                chainId: 0, // TODO verify
                tokenOut: address(token1),
                amountOut: amountOut
            })
        );

        Balances memory balancesAfter = getBalances();
        // hook keeps token0
        assertEq(balancesAfter.token0Hook, balancesMidSwap.token0Hook, "Hook should have kept token0");
        // hook gives token1 to user from its balance
        assertEq(
            balancesAfter.token1User, balancesBefore.token1User + amountOutMinimum, "User should have received 9 token1"
        );
        // reserved amt updated
        assertEq(hook.reservedPreBridgedLiquidity(address(token1)), 0, "Reserved pre-bridged liquidity should be 0");
        // pre-bridged liquidity balance updated
        assertEq(
            hook.preBridgedLiquidity(address(token1)),
            startingToken1SideLiquidity - amountOut,
            "Pre-bridged liquidity should be deducted"
        );

        // user ends up down token0 by amountIn, and up token1 > amountOutMinimum
    }
}
