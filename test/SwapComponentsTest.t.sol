// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapHook} from "../src/Swap.sol";

contract SwapComponentsTest is BaseTest {
    function test_beforeSwap_emitsSwapIntent() public {
        // Arrange: Set up swap params for token0 -> token1
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) = prepSwapWithSideLiquidity(10 ether, 9 ether);

        // Act: Call _beforeSwap via swapRouter.swap
        vm.recordLogs();
        token0.approve(address(swapRouter), 10 ether);
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        // Assert: Check SwapIntent event emitted with correct swapId, owner, tokenIn, tokenOut, amountIn
        Vm.Log[] memory logs = vm.getRecordedLogs();
        SwapIntentDetails memory swapIntentDetails = getSwapIntentDetails(logs);

        assertNotEq(swapIntentDetails.swapId, bytes32(0), "SwapIntent event should be emitted");
        bytes32 calculatedSwapId = keccak256(abi.encode(address(this), key, swapParams, block.number));
        assertEq(calculatedSwapId, swapIntentDetails.swapId, "swapId should match calculation");
        assertEq(swapIntentDetails.owner, address(this), "owner should be this contract");
        assertEq(swapIntentDetails.tokenIn, address(token0), "tokenIn should be token0");
        assertEq(swapIntentDetails.tokenOut, address(token1), "tokenOut should be token1");
        assertEq(swapIntentDetails.amountIn, 10 ether, "amountIn should match amount specified");
    }

    function test_beforeSwap_takesTokenIn() public {
        // Arrange: Approve token0 for swapRouter, set swap params
        Balances memory balancesBefore = getBalances();
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) = prepSwapWithSideLiquidity(10 ether, 9 ether);

        // Act: Call swapRouter.swap to trigger _beforeSwap
        token0.approve(address(swapRouter), 10 ether);
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        // Assert: Hook balance of token0 increases by amountIn, user balance decreases
        Balances memory balancesAfter = getBalances();
        assertEq(
            balancesAfter.token0User,
            balancesBefore.token0User - 10 ether,
            "User token0 balance should decrease by 10 ether"
        );
        assertEq(
            balancesAfter.token0Hook,
            balancesBefore.token0Hook + 10 ether,
            "Hook token0 balance should increase by 10 ether"
        );
    }

    function test_beforeSwap_revertsOnExactOutput() public {
        // Arrange: Set swap params with positive amountSpecified (exact output)
        bytes memory hookData = abi.encode(address(this));
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 10 ether, // positive = exact output
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Act & Assert: Call swapRouter.swap, expect revert
        token0.approve(address(swapRouter), 20 ether); // More than enough for an output of 10 ether
        vm.expectRevert(); // Just expect any revert, rather than a specific message
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );
    }

    function test_completeSwap_localSwap_clearsPendingSwap() public {
        // Arrange: Trigger a swap to create a pendingSwap, get swapId
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) = prepSwapWithSideLiquidity(10 ether, 9 ether);

        vm.recordLogs();
        token0.approve(address(swapRouter), 10 ether);
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        SwapIntentDetails memory swapIntentDetails = getSwapIntentDetails(logs);

        // Act: Call completeSwap(swapId, false)
        hook.completeSwap(swapIntentDetails.swapId, false);

        // Assert: pendingSwaps[swapId] is cleared (owner = address(0))
        (address owner,,,,) = hook.pendingSwaps(swapIntentDetails.swapId);
        assertEq(owner, address(0), "Pending swap should be cleared after completion");
    }

    function test_completeSwap_localSwap_sendsTokenOut() public {
        // Arrange: Trigger a swap, note initial balances
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) = prepSwapWithSideLiquidity(10 ether, 9 ether);
        Balances memory balancesBefore = getBalances();

        vm.recordLogs();
        token0.approve(address(swapRouter), 10 ether);
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        SwapIntentDetails memory swapIntentDetails = getSwapIntentDetails(logs);

        // Act: Call completeSwap(swapId, false)
        uint256 amountOut = hook.completeSwap(swapIntentDetails.swapId, false);

        // Assert: User receives token1, hook token0 balance resets
        Balances memory balancesAfter = getBalances();

        assertEq(
            balancesAfter.token0User,
            balancesBefore.token0User - 10 ether,
            "User token0 balance should decrease by 10 ether"
        );
        assertEq(
            balancesAfter.token1User,
            balancesBefore.token1User + amountOut,
            "User token1 balance should increase by amountOut"
        );
        assertEq(
            balancesAfter.token0Hook, balancesBefore.token0Hook, "Hook token0 balance should be reset to original value"
        );
    }

    function test_completeSwap_revertsOnInvalidSwapId() public {
        // Arrange: Use a random swapId not in pendingSwaps
        bytes32 randomSwapId = keccak256(abi.encode("nonexistent swap"));

        // Act & Assert: Call completeSwap(randomSwapId, false), expect revert
        vm.expectRevert("Swap does not exist");
        hook.completeSwap(randomSwapId, false);
    }

    function test_unlockCallback_executesLocalSwap() public {
        // Arrange: Trigger a swap, get swapId
        (IPoolManager.SwapParams memory swapParams, bytes memory hookData) = prepSwapWithSideLiquidity(10 ether, 9 ether);

        Balances memory balancesBefore = getBalances();

        vm.recordLogs();
        token0.approve(address(swapRouter), 10 ether);
        swapRouter.swap(
            key, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        SwapIntentDetails memory swapIntentDetails = getSwapIntentDetails(logs);

        // Assert that the first part (token take) happened correctly
        Balances memory balancesAfterSwapStart = getBalances();
        assertEq(
            balancesAfterSwapStart.token0User,
            balancesBefore.token0User - 10 ether,
            "User token0 balance should decrease by amountIn"
        );
        assertEq(
            balancesAfterSwapStart.token0Hook,
            balancesBefore.token0Hook + 10 ether,
            "Hook token0 balance should increase by amountIn"
        );

        // Act: Complete the swap which will trigger unlockCallback internally
        uint256 amountOut = hook.completeSwap(swapIntentDetails.swapId, false);

        // Assert: The swap completed successfully
        Balances memory balancesAfterComplete = getBalances();

        assertEq(
            balancesAfterComplete.token0User,
            balancesBefore.token0User - 10 ether,
            "User token0 balance should remain decreased after complete"
        );
        assertEq(
            balancesAfterComplete.token1User,
            balancesBefore.token1User + amountOut,
            "User token1 balance should increase by amountOut"
        );
        assertEq(
            balancesAfterComplete.token0Hook,
            balancesBefore.token0Hook,
            "Hook token0 balance should be reset to original"
        );

        assertGt(amountOut, 0, "Amount out should be greater than zero");
    }
}
