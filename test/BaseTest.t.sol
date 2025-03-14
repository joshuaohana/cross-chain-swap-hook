// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SwapHook} from "../src/Swap.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract BaseTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    MockERC20 token0;
    MockERC20 token1;

    Currency token0Currency;
    Currency token1Currency;

    SwapHook hook;

    struct SwapIntentDetails {
        bytes32 swapId;
        address owner;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
    }

    struct Balances {
        uint256 token0User;
        uint256 token1User;
        uint256 token0Hook;
        uint256 token1Hook;
    }

    // SETUP

    // deploy uniswap, tokens, hook, init pool, add liquidity
    function setUp() public virtual {
        // deploy uniswap
        deployFreshManagerAndRouters();

        // Build test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token0Currency = Currency.wrap(address(token0));

        token1 = new MockERC20("Test Token 1", "TEST1", 18);
        token1Currency = Currency.wrap(address(token1));

        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);

        // Deploy hook
        uint160 flags = uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_SWAP_FLAG);
        deployCodeTo("Swap.sol", abi.encode(manager), address(flags));
        hook = SwapHook(address(flags));

        // Initialize pool
        (key,) = initPool(token0Currency, token1Currency, hook, 3000, SQRT_PRICE_1_1);

        token0.approve(address(modifyLiquidityRouter), 1000 ether);
        token1.approve(address(modifyLiquidityRouter), 1000 ether);

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 token0toAdd = 11 ether;
        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(sqrtPriceAtTickLower, sqrtPriceAtTickUpper, token0toAdd);

        // add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta * 2)),
                salt: bytes32(0)
            }),
            ""
        );
    }

    // builder HELPERS

    // how much token0 you're sending and minimum amount of token1 you'll accept
    function prepSwapWithSideLiquidity(int256 amountInAbs, uint256 amountOutMinimum) internal returns (IPoolManager.SwapParams memory, bytes memory) {
        // depositPreBridgedLiquidity with 100 ether
        hook.depositPreBridgedLiquidity(address(token1), amountOutMinimum + (amountOutMinimum / 10));

        // Arrange: Set up swap params for token0 -> token1
        bytes memory hookData = abi.encode(address(this), amountOutMinimum);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -amountInAbs,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        return (swapParams, hookData);
    }

    function prepSwapWithoutSideLiquidity(int256 amountInAbs, uint256 amountOutMinimum) internal view returns (IPoolManager.SwapParams memory, bytes memory) {
        // Arrange: Set up swap params for token0 -> token1
        bytes memory hookData = abi.encode(address(this), amountOutMinimum);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -amountInAbs,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        return (swapParams, hookData);
    }
    

    // static HELPERS

    function getBalances() internal view returns (Balances memory) {
        return Balances({
            token0User: token0.balanceOf(address(this)),
            token1User: token1.balanceOf(address(this)),
            token0Hook: token0.balanceOf(address(hook)),
            token1Hook: token1.balanceOf(address(hook))
        });
    }

    // returns first SwapIntent event in logs
    function getSwapIntentDetails(Vm.Log[] memory logs) internal view returns (SwapIntentDetails memory) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == SwapHook.SwapIntent.selector) {
                bytes32 swapId = bytes32(uint256(logs[i].topics[1]));
                address owner = address(uint160(uint256(logs[i].topics[2])));
                address tokenIn = address(uint160(uint256(logs[i].topics[3])));
                (address tokenOut, uint256 amountIn) = abi.decode(logs[i].data, (address, uint256));
                return SwapIntentDetails({
                    swapId: swapId,
                    owner: owner,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn
                });
            }
        }

        return SwapIntentDetails({
            swapId: bytes32(0),
            owner: address(0),
            tokenIn: address(0),
            tokenOut: address(0),
            amountIn: 0
        });
    }
}
