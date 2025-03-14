// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Vm} from "forge-std/Vm.sol";
import {SwapHook} from "../src/Swap.sol";

contract FullSwapTest is BaseTest {
    // full basic swap workflow with no better price found
    function test_regular_full_swap() public {
        // setup swap
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) = prepSwapWithSideLiquidity(10 ether, 9 ether);
        Balances memory balancesBefore = getBalances();

        vm.recordLogs();

        // perform swap
        token0.approve(address(swapRouter), 10 ether);
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );
        Balances memory balancesAfterSwap = getBalances();

        // check event logs
        uint256 blockNumber = block.number;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        SwapIntentDetails memory swapIntentDetails = getSwapIntentDetails(logs);

        assertNotEq(swapIntentDetails.swapId, bytes32(0), "SwapIntent event should be emitted");
        bytes32 calculatedSwapId = keccak256(abi.encode(address(this), key, swapParams, blockNumber));
        assertEq(calculatedSwapId, swapIntentDetails.swapId, "swapId should be the same as the one in the event");
        assertEq(swapIntentDetails.owner, address(this), "emittedOwner should be the same as the sender");
        assertEq(swapIntentDetails.tokenIn, address(token0), "emittedTokenIn should be the same as the token0");
        assertEq(swapIntentDetails.tokenOut, address(token1), "emittedTokenOut should be the same as the token1");
        assertEq(swapIntentDetails.amountIn, 10 ether, "emittedAmountIn should be the same as the amount specified");

        // assert that the first half of the swap worked
        // user has same token1, 10 eth less token0
        // hook has 10 eth token0, 0 token1

        assertEq(
            balancesAfterSwap.token0User,
            balancesBefore.token0User - 10 ether,
            "user token0 balance should decrease by 10 eth after swap"
        );
        assertEq(
            balancesAfterSwap.token1User,
            balancesBefore.token1User,
            "user token1 balance should remain the same after swap, because pause"
        );

        assertEq(
            balancesAfterSwap.token0Hook,
            balancesBefore.token0Hook + 10 ether,
            "hook token0 balance should increase by 10 eth after swap"
        );
        assertEq(
            balancesAfterSwap.token1Hook,
            balancesBefore.token1Hook,
            "hook token1 balance should remain the same after swap, because pause"
        );

        // complete the swap
        uint256 amountOut = hook.completeSwap(swapIntentDetails.swapId, false); // no better price found

        // then assert that the swap "completed"
        // hook should have same as before
        // user has -10 token0, +10 token1

        Balances memory balancesAfterComplete = getBalances();

        assertEq(
            balancesAfterComplete.token0User,
            balancesBefore.token0User - 10 ether,
            "user token0 balance should decrease by 10 eth after completeSwap"
        );
        assertEq(
            balancesAfterComplete.token1User,
            balancesBefore.token1User + amountOut,
            "user token1 balance should increase by 10 eth after completeSwap"
        );
        assertEq(
            balancesAfterComplete.token0Hook,
            balancesBefore.token0Hook,
            "hook token0 balance should remain the same after completeSwap"
        );
        assertEq(
            balancesAfterComplete.token1Hook,
            balancesBefore.token1Hook,
            "hook token1 balance should remain the same after completeSwap"
        );
    }

    // test when not enough pre-bridged liquidity
    // expect emit SwapIntent to NOT happen
    // expect normal swap to complete

    // test when enough pre-bridged liquidity
    // expect emit SwapIntent to happen

    // test with better price found
    // expect user to get output from pre-bridged liquidity, and it to beat expected output
}
