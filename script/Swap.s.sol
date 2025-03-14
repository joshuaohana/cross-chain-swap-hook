// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

contract SwapScript is Script {
    using CurrencyLibrary for Currency;

    // Deployed contract addresses from your Anvil instance
    address constant POOL_MANAGER = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    PoolSwapTest constant SWAP_ROUTER = PoolSwapTest(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0);
    ERC20 constant TOKEN0 = ERC20(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
    ERC20 constant TOKEN1 = ERC20(0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9);
    address constant HOOK = 0xa85aa8Fc8d79f889a4801502C5E8F12665f34088;

    // Pool key matching your deployment
    PoolKey poolKey = PoolKey({
        currency0: Currency.wrap(address(TOKEN0)),
        currency1: Currency.wrap(address(TOKEN1)),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(HOOK)
    });

    function run() external {
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        // Wallet address (Anvil account 0)
        address wallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        // Record balances before swap
        uint256 token0UserBalanceBefore = TOKEN0.balanceOf(wallet);
        uint256 token1UserBalanceBefore = TOKEN1.balanceOf(wallet);
        uint256 token0HookBalanceBefore = TOKEN0.balanceOf(HOOK);
        uint256 token1HookBalanceBefore = TOKEN1.balanceOf(HOOK);

        console.log("Before Swap:");
        console.log("User Token0:", token0UserBalanceBefore / 1e18, "ether");
        console.log("User Token1:", token1UserBalanceBefore / 1e18, "ether");
        console.log("Hook Token0:", token0HookBalanceBefore / 1e18, "ether");
        console.log("Hook Token1:", token1HookBalanceBefore / 1e18, "ether");

        // Approve SwapRouter to spend 10 ether of Token0
        TOKEN0.approve(address(SWAP_ROUTER), 10 ether);
        console.log("Approved SwapRouter for 10 Token0");

        // Swap parameters from your test
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true, // Swap Token0 for Token1
            amountSpecified: -10 ether, // Exact output of 10 Token0
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // Minimum price limit
        });

        // Hook data (same as test)
        bytes memory hookData = abi.encode(wallet);

        // Perform the swap
        SWAP_ROUTER.swap(
            poolKey, swapParams, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), hookData
        );
        console.log("Swap executed");

        // Record balances after swap
        uint256 token0UserBalanceAfter = TOKEN0.balanceOf(wallet);
        uint256 token1UserBalanceAfter = TOKEN1.balanceOf(wallet);
        uint256 token0HookBalanceAfter = TOKEN0.balanceOf(HOOK);
        uint256 token1HookBalanceAfter = TOKEN1.balanceOf(HOOK);

        console.log("After Swap:");
        console.log("User Token0:", token0UserBalanceAfter / 1e18, "ether");
        console.log("User Token1:", token1UserBalanceAfter / 1e18, "ether");
        console.log("Hook Token0:", token0HookBalanceAfter / 1e18, "ether");
        console.log("Hook Token1:", token1HookBalanceAfter / 1e18, "ether");

        vm.stopBroadcast();
    }
}
