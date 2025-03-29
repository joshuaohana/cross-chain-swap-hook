// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SwapHook} from "../src/Swap.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

contract CrossChainSwapTest is BaseTest {
    using CurrencyLibrary for Currency;

    // Chain setups
    ChainSetup public chainA;
    ChainSetup public chainB;

    // Cross-chain data
    SwapIntentDetails private capturedSwapIntent;
    
    // Simulated chain IDs
    uint256 constant CHAIN_A_ID = 31337;
    uint256 constant CHAIN_B_ID = 31338;

    struct ChainBalances {
        uint256 token0User;
        uint256 token1User;
        uint256 token0Hook;
        uint256 token1Hook;
    }

    struct ChainSetup {
        PoolManager manager;
        PoolModifyLiquidityTest modifyLiquidityRouter;
        PoolSwapTest swapRouter;
        MockERC20 token0;
        MockERC20 token1;
        SwapHook hook;
        PoolKey key;
    }

    function setUp() public override {
        // Skip the BaseTest setUp to create our own environment
        
        // Set up Chain A environment
        vm.chainId(CHAIN_A_ID);
        console.log("Setting up Chain A with ID:", block.chainid);
        chainA = _setupChain("Chain A", "TKN0A", "TKN1A", false, 0);
        
        // Set up Chain B environment
        vm.chainId(CHAIN_B_ID);
        console.log("Setting up Chain B with ID:", block.chainid);
        chainB = _setupChain("Chain B", "TKN0B", "TKN1B", true, 50 ether);
    }

    // Common chain setup function for reuse
    function _setupChain(
        string memory chainName,
        string memory token0Symbol,
        string memory token1Symbol,
        bool addPreBridgedLiquidity,
        uint256 preBridgedAmount
    ) internal returns (ChainSetup memory setup) {
        // Deploy contracts
        setup.manager = new PoolManager(address(this));
        setup.modifyLiquidityRouter = new PoolModifyLiquidityTest(IPoolManager(address(setup.manager)));
        setup.swapRouter = new PoolSwapTest(IPoolManager(address(setup.manager)));
        
        // Create tokens
        setup.token0 = new MockERC20(string.concat("Token0 ", chainName), token0Symbol, 18);
        setup.token1 = new MockERC20(string.concat("Token1 ", chainName), token1Symbol, 18);
        
        // Mint tokens to test contract
        setup.token0.mint(address(this), 1000 ether);
        setup.token1.mint(address(this), 1000 ether);
        
        // Deploy hook (using BaseTest's simpler pattern)
        uint160 flags = uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_SWAP_FLAG);
        deployCodeTo("Swap.sol", abi.encode(address(setup.manager)), address(flags));
        setup.hook = SwapHook(address(flags));
        
        // Initialize pool
        setup.key = PoolKey({
            currency0: Currency.wrap(address(setup.token0)),
            currency1: Currency.wrap(address(setup.token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: setup.hook
        });
        setup.manager.initialize(setup.key, SQRT_PRICE_1_1);
        
        // Add liquidity to the pool
        setup.token0.approve(address(setup.modifyLiquidityRouter), 1000 ether);
        setup.token1.approve(address(setup.modifyLiquidityRouter), 1000 ether);
        
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 token0toAdd = 100 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower, sqrtPriceAtTickUpper, token0toAdd
        );
        
        setup.modifyLiquidityRouter.modifyLiquidity(
            setup.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta * 2)),
                salt: bytes32(0)
            }),
            bytes("")
        );
        
        // Add pre-bridged liquidity if needed (mainly for Chain B)
        if (addPreBridgedLiquidity && preBridgedAmount > 0) {
            setup.token1.mint(address(setup.hook), preBridgedAmount);
            vm.startPrank(address(this));
            setup.hook.depositPreBridgedLiquidity(address(setup.token1), preBridgedAmount);
            vm.stopPrank();
        }
    }
    
    function test_cross_chain_swap_with_better_price() public {
        // Start on Chain A
        vm.chainId(CHAIN_A_ID);
        console.log("Operating on Chain A with ID:", block.chainid);
        
        // Get initial balances on Chain A
        ChainBalances memory balancesABefore = _getChainBalances(chainA);
        
        // Setup swap params for token0A -> token1A
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -10 ether, // Exact input of 10 token0A
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Set amountOutMinimum to 9 ether token1A
        bytes memory hookData = abi.encode(address(this), 9 ether);
        
        // Approve tokens for swap
        chainA.token0.approve(address(chainA.swapRouter), 10 ether);
        
        // Record logs to capture the SwapIntent event
        vm.recordLogs();
        
        // Execute the swap on Chain A
        chainA.swapRouter.swap(
            chainA.key, 
            swapParams, 
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), 
            hookData
        );
        
        // Capture SwapIntent event details
        Vm.Log[] memory logs = vm.getRecordedLogs();
        capturedSwapIntent = _getSwapIntentDetails(logs);
        
        // Verify SwapIntent was emitted correctly
        assertNotEq(capturedSwapIntent.swapId, bytes32(0), "SwapIntent event should be emitted");
        assertEq(capturedSwapIntent.owner, address(this), "Owner should be the test contract");
        assertEq(capturedSwapIntent.tokenIn, address(chainA.token0), "TokenIn should be token0A");
        assertEq(capturedSwapIntent.tokenOut, address(chainA.token1), "TokenOut should be token1A");
        assertEq(capturedSwapIntent.amountIn, 10 ether, "AmountIn should be 10 ether");
        
        // Verify token0A was taken from user
        ChainBalances memory balancesAAfterSwap = _getChainBalances(chainA);
        assertEq(
            balancesAAfterSwap.token0User, 
            balancesABefore.token0User - 10 ether, 
            "User token0A balance should be reduced by 10 ether"
        );
        
        // Now switch to Chain B to simulate the cross-chain part
        vm.chainId(CHAIN_B_ID);
        console.log("Operating on Chain B with ID:", block.chainid);
        
        // Get initial balances on Chain B
        ChainBalances memory balancesBBefore = _getChainBalances(chainB);
        
        // Simulate better price found on Chain B
        // On Chain B, token1B would be the output token (equivalent to token1A on Chain A)
        // Let's say we found a better rate and can provide 9.5 ether instead of 9 ether
        uint256 betterAmountOut = 9.5 ether;
        
        // Create the OffChainSwap data structure with the better price
        SwapHook.OffChainSwap memory offChainSwap = SwapHook.OffChainSwap({
            swapId: capturedSwapIntent.swapId,
            txnId: bytes32(uint256(1)), // Some arbitrary txnId
            chainId: CHAIN_B_ID,
            tokenOut: address(chainB.token1), // The token we're giving out on Chain B
            amountOut: betterAmountOut // The better amount
        });
        
        // Complete the swap on Chain B
        uint256 amountOut = chainB.hook.completeSwap(
            capturedSwapIntent.swapId,
            true, // better price found
            offChainSwap
        );
        
        // Verify the results
        assertEq(amountOut, betterAmountOut, "Amount out should be the better amount");
        
        // Check balances after swap completion
        ChainBalances memory balancesBAfterComplete = _getChainBalances(chainB);
        
        // User should receive token1B on Chain B
        assertEq(
            balancesBAfterComplete.token1User,
            balancesBBefore.token1User + betterAmountOut,
            "User should receive the better amount of token1B on Chain B"
        );
        
        // Hook's pre-bridged liquidity should be reduced
        assertEq(
            balancesBAfterComplete.token1Hook,
            balancesBBefore.token1Hook - betterAmountOut,
            "Hook's token1B balance should be reduced by the output amount"
        );
        
        // Switch back to Chain A to verify the state there
        vm.chainId(CHAIN_A_ID);
        console.log("Back to Chain A with ID:", block.chainid);
        
        // The tokens on Chain A should still be in the hook
        ChainBalances memory balancesAFinal = _getChainBalances(chainA);
        assertEq(
            balancesAFinal.token0Hook,
            balancesAAfterSwap.token0Hook,
            "Hook's token0A balance should remain unchanged on Chain A"
        );
        
        // The cross-chain swap is complete!
        console.log("Cross-chain swap completed successfully!");
        console.log("Received amount on Chain B:", betterAmountOut / 1e18, "ether");
        console.log("Original minimum amount on Chain A:", 9, "ether");
        console.log("Price improvement:", (betterAmountOut - 9 ether) / 1e17, "%");
    }
    
    // Add a second test case for regular swap (no better price found)
    function test_cross_chain_swap_no_better_price() public {
        // Start on Chain A
        vm.chainId(CHAIN_A_ID);
        
        // Get initial balances on Chain A
        ChainBalances memory balancesABefore = _getChainBalances(chainA);
        
        // Setup swap params for token0A -> token1A
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -10 ether, // Exact input of 10 token0A
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Set amountOutMinimum to 9 ether token1A
        bytes memory hookData = abi.encode(address(this), 9 ether);
        
        // Approve tokens for swap
        chainA.token0.approve(address(chainA.swapRouter), 10 ether);
        
        // Record logs to capture the SwapIntent event
        vm.recordLogs();
        
        // Execute the swap on Chain A
        chainA.swapRouter.swap(
            chainA.key, 
            swapParams, 
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), 
            hookData
        );
        
        // Capture SwapIntent event details
        Vm.Log[] memory logs = vm.getRecordedLogs();
        capturedSwapIntent = _getSwapIntentDetails(logs);
        
        // Verify SwapIntent was emitted correctly
        assertNotEq(capturedSwapIntent.swapId, bytes32(0), "SwapIntent event should be emitted");
        
        // Now complete the swap on the same chain (no better price found)
        uint256 amountOut = chainA.hook.completeSwap(
            capturedSwapIntent.swapId,
            false, // No better price
            SwapHook.OffChainSwap({
                swapId: bytes32(0),
                txnId: bytes32(0),
                chainId: 0,
                tokenOut: address(0),
                amountOut: 0
            })
        );
        
        // Verify the regular swap completed
        ChainBalances memory balancesAAfterComplete = _getChainBalances(chainA);
        
        // User should have received token1A on Chain A
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertEq(
            balancesAAfterComplete.token1User,
            balancesABefore.token1User + amountOut,
            "User should receive token1A from regular swap"
        );
        
        console.log("Regular swap completed successfully on Chain A");
        console.log("Received amount:", amountOut / 1e18, "ether");
    }
    
    // Helper function to get balances for any chain
    function _getChainBalances(ChainSetup memory setup) internal view returns (ChainBalances memory) {
        return ChainBalances({
            token0User: setup.token0.balanceOf(address(this)),
            token1User: setup.token1.balanceOf(address(this)),
            token0Hook: setup.token0.balanceOf(address(setup.hook)),
            token1Hook: setup.token1.balanceOf(address(setup.hook))
        });
    }
    
    // Helper function to extract SwapIntent details from logs
    function _getSwapIntentDetails(Vm.Log[] memory logs) internal pure returns (SwapIntentDetails memory) {
        bytes32 swapIntentSelector = keccak256("SwapIntent(bytes32,address,address,address,uint256)");
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == swapIntentSelector) {
                // Extract data from topics and data field without using array slicing
                address tokenOut;
                uint256 amountIn;
                
                // Decode the full data field 
                bytes memory data = logs[i].data;
                assembly {
                    // Load the first 32 bytes of data (tokenOut)
                    tokenOut := mload(add(data, 32))
                    // Load the next 32 bytes of data (amountIn)
                    amountIn := mload(add(data, 64))
                }
                
                return SwapIntentDetails({
                    swapId: logs[i].topics[1],
                    owner: address(uint160(uint256(logs[i].topics[2]))),
                    tokenIn: address(uint160(uint256(logs[i].topics[3]))),
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

// Struct to store SwapIntent event details
struct SwapIntentDetails {
    bytes32 swapId;
    address owner;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
} 