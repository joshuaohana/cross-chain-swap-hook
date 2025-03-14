// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapHook} from "../src/Swap.sol";

contract SideLiquidityProvideTest is BaseTest {
    
    function test_deposit_side_liquidity() public {
        // TODO

        // funds leave user
        // funds go to hook reserves
        // user's allocation is updated
    }

    function test_withdraw_side_liquidity() public {
        // TODO

        // funds leave hook reserves
        // funds go to user
        // user's allocation is updated
    }
}
