"use client";

import React from "react";
import { useAccount, useReadContract } from "wagmi";
import { formatEther } from "viem";
import {
  TOKEN0_ADDRESS,
  TOKEN1_ADDRESS,
  HOOK_ADDRESS,
  TOKEN0_SYMBOL,
  TOKEN1_SYMBOL,
} from "../config/contracts";
import ERC20_ABI from "../abis/ERC20.json";

export default function TokenBalances() {
  const { address, isConnected } = useAccount();

  // User token balances
  const { data: token0Balance } = useReadContract({
    address: TOKEN0_ADDRESS as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [address || "0x0000000000000000000000000000000000000000"],
  });

  const { data: token1Balance } = useReadContract({
    address: TOKEN1_ADDRESS as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [address || "0x0000000000000000000000000000000000000000"],
  });

  // Hook token balances
  const { data: hookToken0Balance } = useReadContract({
    address: TOKEN0_ADDRESS as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [HOOK_ADDRESS],
  });

  const { data: hookToken1Balance } = useReadContract({
    address: TOKEN1_ADDRESS as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [HOOK_ADDRESS],
  });

  // Format a BigInt balance to a human-readable string
  const formatBalance = (balance: bigint | undefined) => {
    if (!balance) return "0.00";
    return parseFloat(formatEther(balance)).toFixed(4);
  };

  return (
    <div className="bg-gray-800 p-6 rounded-xl shadow-xl">
      <h2 className="text-xl font-bold mb-4">Token Balances</h2>

      {/* User balances */}
      <div className="mb-6">
        <h3 className="text-lg font-semibold mb-2 text-gray-300">
          Your Wallet
        </h3>
        {isConnected ? (
          <div className="space-y-2">
            <div className="flex justify-between items-center">
              <span className="text-gray-400">{TOKEN0_SYMBOL}:</span>
              <span className="font-mono">
                {formatBalance(token0Balance as bigint)}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-gray-400">{TOKEN1_SYMBOL}:</span>
              <span className="font-mono">
                {formatBalance(token1Balance as bigint)}
              </span>
            </div>
          </div>
        ) : (
          <p className="text-gray-400">Connect wallet to view</p>
        )}
      </div>

      {/* Hook contract balances */}
      <div>
        <h3 className="text-lg font-semibold mb-2 text-gray-300">
          Hook Contract
        </h3>
        <div className="space-y-2">
          <div className="flex justify-between items-center">
            <span className="text-gray-400">{TOKEN0_SYMBOL}:</span>
            <span className="font-mono">
              {formatBalance(hookToken0Balance as bigint)}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">{TOKEN1_SYMBOL}:</span>
            <span className="font-mono">
              {formatBalance(hookToken1Balance as bigint)}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
