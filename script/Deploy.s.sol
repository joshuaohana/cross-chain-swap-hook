// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapHook} from "../src/Swap.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

contract DeployScript is Script {
    using CurrencyLibrary for Currency;

    PoolManager public manager;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    PoolSwapTest public swapRouter;
    MockERC20 public token0;
    MockERC20 public token1;
    Currency public token0Currency;
    Currency public token1Currency;
    SwapHook public hook;
    PoolKey public key;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        // anvil account 0
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        manager = new PoolManager(msg.sender);
        console.log("PoolManager deployed at:", address(manager));

        modifyLiquidityRouter = new PoolModifyLiquidityTest(IPoolManager(address(manager)));
        console.log("ModifyLiquidityRouter deployed at:", address(modifyLiquidityRouter));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));
        console.log("SwapRouter deployed at:", address(swapRouter));

        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token0Currency = Currency.wrap(address(token0));
        token1 = new MockERC20("Test Token 1", "TEST1", 18);
        token1Currency = Currency.wrap(address(token1));
        console.log("Token0 deployed at:", address(token0));
        console.log("Token1 deployed at:", address(token1));

        // mint tokens to anvil account 0
        token0.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 1000 ether);
        token1.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 1000 ether);

        // Deploy hook with CREATE2
        uint160 flags = uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_SWAP_FLAG); // 0x3000
        bytes memory hookCreationCode = abi.encodePacked(type(SwapHook).creationCode, abi.encode(address(manager)));
        (address hookAddress, bytes32 salt) = mineHookAddress(hookCreationCode, flags);
        hook = deployHook(hookCreationCode, salt, hookAddress);
        console.log("SwapHook deployed at:", address(hook));

        key = PoolKey({currency0: token0Currency, currency1: token1Currency, fee: 3000, tickSpacing: 60, hooks: hook});
        manager.initialize(key, SQRT_PRICE_1_1);
        console.log("Pool initialized");

        token0.approve(address(modifyLiquidityRouter), 1000 ether);
        token1.approve(address(modifyLiquidityRouter), 1000 ether);

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 token0toAdd = 11 ether;
        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(sqrtPriceAtTickLower, sqrtPriceAtTickUpper, token0toAdd);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta * 2)),
                salt: bytes32(0)
            }),
            bytes("")
        );
        console.log("Liquidity added to pool");

        vm.stopBroadcast();
    }

    function mineHookAddress(bytes memory creationCode, uint160 targetFlags) internal view returns (address, bytes32) {
        bytes32 initCodeHash = keccak256(creationCode);
        console.log("Init code hash:", uint256(initCodeHash));
        for (uint256 i = 0; i < 100000; i++) {
            bytes32 salt = keccak256(abi.encodePacked(msg.sender, i));
            address predictedAddress = vm.computeCreate2Address(salt, initCodeHash);
            if (isValidHookAddress(predictedAddress, targetFlags)) {
                console.log("Mined hook address:", predictedAddress);
                console.log(
                    "Flags check (addr & ALL_HOOK_MASK):", uint160(predictedAddress) & uint160(Hooks.ALL_HOOK_MASK)
                );
                return (predictedAddress, salt);
            }
            if (i % 10000 == 9999) {
                // Log every 10k iterations
                console.log("Iteration:", i + 1);
                console.log("Last address:", predictedAddress);
                console.log("Last flags check:", uint160(predictedAddress) & uint160(Hooks.ALL_HOOK_MASK));
            }
        }
        revert("Failed to mine a valid hook address within 100k attempts");
    }

    function deployHook(bytes memory creationCode, bytes32 salt, address expectedAddress) internal returns (SwapHook) {
        address deployedAddress;
        assembly {
            let codeSize := mload(creationCode)
            let codeStart := add(creationCode, 0x20)
            deployedAddress := create2(0, codeStart, codeSize, salt)
        }
        require(deployedAddress == expectedAddress, "CREATE2 address mismatch");
        require(deployedAddress != address(0), "CREATE2 deployment failed");
        return SwapHook(deployedAddress);
    }

    function isValidHookAddress(address hookAddress, uint160 targetFlags) internal pure returns (bool) {
        uint160 addr = uint160(hookAddress);
        // Must exactly match targetFlags (0x3000) within ALL_HOOK_MASK (0x5555)
        return addr != 0 && (addr & uint160(Hooks.ALL_HOOK_MASK)) == targetFlags;
    }
}
