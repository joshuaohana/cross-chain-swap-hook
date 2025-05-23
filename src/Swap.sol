// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract SwapHook is BaseHook {
    using CurrencySettler for Currency;

    // track pre-bridged liquidity
    mapping(address => uint256) public preBridgedLiquidity; // token => qty
    mapping(address => uint256) public reservedPreBridgedLiquidity; // for pending txns

    // track single sided LPs
    mapping(address => mapping(address => uint256)) public preBridgedLiquidityDeposits; // wallet => token => qty

    mapping(bytes32 => PendingSwap) public pendingSwaps;

    struct PendingSwap {
        address owner;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        PoolKey key;
    }

    // reported by off-chain bot when better price found
    struct OffChainSwap {
        bytes32 swapId;
        bytes32 txnId;
        uint256 chainId;
        address tokenOut;
        uint256 amountOut;
    }

    // main event for off-chain bot to pick up
    event SwapIntent(
        bytes32 indexed swapId, address indexed owner, address indexed tokenIn, address tokenOut, uint256 amountIn
    );
    // liquidity events
    event PreBridgedLiquidityDeposit(address indexed wallet, address indexed token, uint256 amount);
    event PreBridgedLiquidityWithdraw(address indexed wallet, address indexed token, uint256 amount);

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // HANDLE PAUSE SWAP

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        require(params.amountSpecified < 0, "Exact output not supported");

        (address swapper, uint256 amountOutMinimum) = abi.decode(hookData, (address, uint256));
        uint256 amountIn = uint256(-params.amountSpecified);

        Currency tokenInCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        address tokenIn = Currency.unwrap(tokenInCurrency);
        address tokenOut = Currency.unwrap(params.zeroForOne ? key.currency1 : key.currency0);

        bytes32 swapId = keccak256(abi.encode(swapper, key, params, block.number));

        // do we have enough pre-bridged liquidity to process the output?
        if (preBridgedLiquidity[tokenOut] - reservedPreBridgedLiquidity[tokenOut] < amountOutMinimum) {
            // no, process normal swap
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // reserve amountOutMinimum from pre-bridged liquidity
        reservedPreBridgedLiquidity[tokenOut] += amountOutMinimum + (amountOutMinimum / 10);

        tokenInCurrency.take(poolManager, address(this), amountIn, false);

        PendingSwap storage swap = pendingSwaps[swapId];
        swap.owner = swapper;
        swap.tokenIn = tokenIn;
        swap.tokenOut = tokenOut;
        swap.amountIn = amountIn;
        swap.amountOutMinimum = amountOutMinimum;
        swap.key = key;

        emit SwapIntent(swapId, swapper, tokenIn, tokenOut, amountIn);
        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(int128(-params.amountSpecified), 0);
        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    // incoming from off-chain bot
    function completeSwap(bytes32 swapId, bool betterPriceFound, OffChainSwap memory offChainSwap)
        external
        returns (uint256 amountOut)
    {
        // ensure valid swap
        PendingSwap memory swap = pendingSwaps[swapId];
        require(swap.owner != address(0), "Swap does not exist");

        // if better price found, process off-chain
        if (betterPriceFound) {
            // revert("Better price found not yet implemented");
            if (offChainSwap.swapId == bytes32(0)) {
                revert("No swapId when better price found");
            }
            if (offChainSwap.swapId != swapId) {
                revert("SwapId mismatch");
            }

            return swapWithBridgedLiquidity(swapId, offChainSwap);
        } else {
            // adjust reservedPreBridgedLiquidity
            reservedPreBridgedLiquidity[swap.tokenOut] -= swap.amountOutMinimum + (swap.amountOutMinimum / 10);
            delete pendingSwaps[swapId];

            // maybe just pass everything in the data and unlockCallback handles it?
            bytes memory data = abi.encode(swap);
            bytes memory result = poolManager.unlock(data);
            amountOut = abi.decode(result, (uint256));

            return amountOut;
        }
    }

    function swapWithBridgedLiquidity(bytes32 swapId, OffChainSwap memory offChainSwap)
        internal
        returns (uint256 amountOut)
    {
        // double check sufficient side liquidity
        if (preBridgedLiquidity[offChainSwap.tokenOut] < offChainSwap.amountOut) {
            revert("Insufficient side liquidity");
        }

        PendingSwap memory swap = pendingSwaps[swapId];
        delete pendingSwaps[swapId];

        reservedPreBridgedLiquidity[swap.tokenOut] -= offChainSwap.amountOut + (offChainSwap.amountOut / 10);
        preBridgedLiquidity[swap.tokenOut] -= offChainSwap.amountOut;

        // actually send the token out
        ERC20(swap.tokenOut).transfer(swap.owner, offChainSwap.amountOut);

        return offChainSwap.amountOut;
    }

    // perform the swap normally
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only pool manager can unlock");

        PendingSwap memory swap = abi.decode(data, (PendingSwap));

        // charge fees as hook fees initially
        // as part of off-chain bot, track fees over time
        // every X hours, split them up and move them around from the bot
        // so like when we do the tx, keep the fee for the hook (to pay for bridging and bots)
        // and then decide how much goes to LPs

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: swap.tokenIn == Currency.unwrap(swap.key.currency0),
            amountSpecified: -int256(swap.amountIn),
            sqrtPriceLimitX96: swap.tokenIn == Currency.unwrap(swap.key.currency0)
                ? TickMath.MIN_SQRT_PRICE + 1
                : TickMath.MAX_SQRT_PRICE - 1
        });

        Currency tokenInCurrency = Currency.wrap(swap.tokenIn);
        tokenInCurrency.settle(poolManager, address(this), swap.amountIn, false);

        bytes memory hookData = abi.encode(swap.owner);
        BalanceDelta delta = poolManager.swap(swap.key, params, hookData);

        uint256 amountOut;

        if (params.zeroForOne) {
            require(delta.amount1() > 0, "Invalid output delta"); // Output should be positive
            amountOut = uint256(int256(delta.amount1()));
        } else {
            require(delta.amount0() > 0, "Invalid output delta"); // Output should be positive
            amountOut = uint256(int256(delta.amount0()));
        }

        Currency tokenOutCurrency = Currency.wrap(swap.tokenOut);
        tokenOutCurrency.take(poolManager, swap.owner, amountOut, false);

        return abi.encode(amountOut);
    }

    function depositPreBridgedLiquidity(address token, uint256 amount) external {
        ERC20(token).transferFrom(msg.sender, address(this), amount);
        preBridgedLiquidity[token] += amount;
        preBridgedLiquidityDeposits[msg.sender][token] += amount;
        emit PreBridgedLiquidityDeposit(msg.sender, token, amount);
    }

    function withdrawPreBridgedLiquidity(address token, uint256 amount) external {
        require(
            preBridgedLiquidity[token] - reservedPreBridgedLiquidity[token] >= amount,
            "Insufficient pre-bridged liquidity"
        );
        require(preBridgedLiquidityDeposits[msg.sender][token] >= amount, "Insufficient pre-bridged liquidity deposits");
        ERC20(token).transfer(msg.sender, amount);
        preBridgedLiquidityDeposits[msg.sender][token] -= amount;
        preBridgedLiquidity[token] -= amount;
        emit PreBridgedLiquidityWithdraw(msg.sender, token, amount);
    }
}
