// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {SwapHook} from "../src/Swap.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract CompleteSwapScript is Script {
    using CurrencyLibrary for Currency;

    address constant POOL_MANAGER = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    ERC20 constant TOKEN0 = ERC20(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9);
    ERC20 constant TOKEN1 = ERC20(0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9);
    SwapHook constant HOOK = SwapHook(0xa85aa8Fc8d79f889a4801502C5E8F12665f34088);

    PoolKey poolKey = PoolKey({
        currency0: Currency.wrap(address(TOKEN0)),
        currency1: Currency.wrap(address(TOKEN1)),
        fee: 3000,
        tickSpacing: 60,
        hooks: IHooks(address(HOOK))
    });

    function run() external {
        bytes32 swapId = 0x808136e1c9625eeb32c5373038bfe3aae26a9514fa0652cd1e214fd43296b45a;
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        // Wallet address (Anvil account 0)
        address wallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        uint256 token0UserBalanceBefore = TOKEN0.balanceOf(wallet);
        uint256 token1UserBalanceBefore = TOKEN1.balanceOf(wallet);
        uint256 token0HookBalanceBefore = TOKEN0.balanceOf(address(HOOK));
        uint256 token1HookBalanceBefore = TOKEN1.balanceOf(address(HOOK));

        console.log("Before CompleteSwap:");
        console.log("User Token0:", token0UserBalanceBefore / 1e18, "ether");
        console.log("User Token1:", token1UserBalanceBefore / 1e18, "ether");
        console.log("Hook Token0:", token0HookBalanceBefore / 1e18, "ether");
        console.log("Hook Token1:", token1HookBalanceBefore / 1e18, "ether");

        // Complete the swap
        uint256 amountOut = HOOK.completeSwap(
            swapId, false, SwapHook.OffChainSwap({swapId: 0, txnId: 0, chainId: 0, tokenOut: address(0), amountOut: 0})
        ); // no better price found
        console.log("Swap completed, amountOut:", amountOut / 1e18, "ether");

        // Record balances after completing swap
        uint256 token0UserBalanceAfter = TOKEN0.balanceOf(wallet);
        uint256 token1UserBalanceAfter = TOKEN1.balanceOf(wallet);
        uint256 token0HookBalanceAfter = TOKEN0.balanceOf(address(HOOK));
        uint256 token1HookBalanceAfter = TOKEN1.balanceOf(address(HOOK));

        console.log("After CompleteSwap:");
        console.log("User Token0:", token0UserBalanceAfter / 1e18, "ether");
        console.log("User Token1:", token1UserBalanceAfter / 1e18, "ether");
        console.log("Hook Token0:", token0HookBalanceAfter / 1e18, "ether");
        console.log("Hook Token1:", token1HookBalanceAfter / 1e18, "ether");

        vm.stopBroadcast();
    }
}
