"use client";

import { useState, ChangeEvent, useEffect } from "react";
import { useAccount, usePublicClient, useWalletClient } from "wagmi";
import { parseEther } from "viem";
import {
  TOKEN0_SYMBOL,
  TOKEN1_SYMBOL,
  TOKEN0_ADDRESS,
  TOKEN1_ADDRESS,
  HOOK_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  TICK_MATH_MIN_SQRT_PRICE,
  DEFAULT_POOL_FEE,
  DEFAULT_TICK_SPACING,
} from "../config/contracts";
import ERC20ABI from "../abis/ERC20.json";

export default function SwapInterface() {
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();

  const [inputAmount, setInputAmount] = useState<string>("");
  const [swapDirection, setSwapDirection] = useState<"0to1" | "1to0">("0to1");
  const [isApproving, setIsApproving] = useState<boolean>(false);
  const [isSwapping, setIsSwapping] = useState<boolean>(false);
  const [swapStatus, setSwapStatus] = useState<string>("");
  const [allowance, setAllowance] = useState<bigint>(BigInt(0));

  // TODO Placeholder for swap rate calculation
  const rate = 1.05;

  // Get the current allowance when component mounts or when address/swap direction changes
  useEffect(() => {
    if (isConnected && address) {
      fetchAllowance();
    }
  }, [address, swapDirection, isConnected]);

  const fetchAllowance = async () => {
    if (!address || !publicClient) return;

    try {
      const tokenAddress =
        swapDirection === "0to1" ? TOKEN0_ADDRESS : TOKEN1_ADDRESS;

      const allowance = await publicClient.readContract({
        address: tokenAddress as `0x${string}`,
        abi: ERC20ABI,
        functionName: "allowance",
        args: [address, SWAP_ROUTER_ADDRESS as `0x${string}`],
      });

      setAllowance(allowance as bigint);
    } catch (error) {
      console.error("Error fetching allowance:", error);
    }
  };

  // Calculate output amount based on input and rate
  const calculateOutputAmount = () => {
    if (!inputAmount || isNaN(parseFloat(inputAmount))) return "0.00";
    return (parseFloat(inputAmount) * rate).toFixed(4);
  };

  // Swap token direction
  const toggleSwapDirection = () => {
    setSwapDirection(swapDirection === "0to1" ? "1to0" : "0to1");
  };

  // Handle input change with validation
  const handleInputChange = (e: ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only numbers and decimals
    if (value === "" || /^\d*\.?\d*$/.test(value)) {
      setInputAmount(value);
    }
  };

  // Handle token approval
  const handleApprove = async () => {
    if (
      !isConnected ||
      !address ||
      !walletClient ||
      !inputAmount ||
      !publicClient
    )
      return;

    try {
      setIsApproving(true);
      setSwapStatus("Approving tokens...");

      const tokenAddress =
        swapDirection === "0to1" ? TOKEN0_ADDRESS : TOKEN1_ADDRESS;
      const amountToApprove = parseEther(inputAmount);

      const hash = await walletClient.writeContract({
        address: tokenAddress as `0x${string}`,
        abi: ERC20ABI,
        functionName: "approve",
        args: [SWAP_ROUTER_ADDRESS as `0x${string}`, amountToApprove],
      });

      setSwapStatus(`Approval transaction submitted: ${hash}`);

      // Wait for transaction to be mined
      await publicClient.waitForTransactionReceipt({ hash });

      setSwapStatus("Tokens approved! You can now swap.");
      fetchAllowance();
    } catch (error) {
      console.error("Error approving tokens:", error);
      setSwapStatus(`Error: ${(error as Error).message}`);
    } finally {
      setIsApproving(false);
    }
  };

  // Handle actual swap
  const handleSwap = async () => {
    if (
      !isConnected ||
      !address ||
      !walletClient ||
      !inputAmount ||
      !publicClient
    )
      return;

    try {
      setIsSwapping(true);
      setSwapStatus("Initiating swap...");

      const amountSpecified = parseEther(inputAmount);
      const zeroForOne = swapDirection === "0to1"; // If 0to1, we're swapping token0 for token1

      // Create properly encoded hook data using the abi encoder from viem
      // This replaces our simple implementation that was causing errors
      // We encode just the address string without the 0x prefix inside the data
      const addressWithout0x = address.substring(2).toLowerCase();
      const hookData = `0x${addressWithout0x.padStart(
        64,
        "0"
      )}` as `0x${string}`;

      // Construct swap parameters
      const swapParams = {
        zeroForOne,
        amountSpecified: -amountSpecified, // Negative for exact output, as in the script
        sqrtPriceLimitX96: BigInt(TICK_MATH_MIN_SQRT_PRICE),
      };

      // Create PoolKey similar to the script
      const poolKey = {
        currency0: TOKEN0_ADDRESS as `0x${string}`,
        currency1: TOKEN1_ADDRESS as `0x${string}`,
        fee: DEFAULT_POOL_FEE,
        tickSpacing: DEFAULT_TICK_SPACING,
        hooks: HOOK_ADDRESS as `0x${string}`,
      };

      // Call swap on the SwapRouter
      const hash = await walletClient.writeContract({
        address: SWAP_ROUTER_ADDRESS as `0x${string}`,
        abi: [
          {
            inputs: [
              {
                components: [
                  { name: "currency0", type: "address" },
                  { name: "currency1", type: "address" },
                  { name: "fee", type: "uint24" },
                  { name: "tickSpacing", type: "int24" },
                  { name: "hooks", type: "address" },
                ],
                name: "key",
                type: "tuple",
              },
              {
                components: [
                  { name: "zeroForOne", type: "bool" },
                  { name: "amountSpecified", type: "int256" },
                  { name: "sqrtPriceLimitX96", type: "uint160" },
                ],
                name: "params",
                type: "tuple",
              },
              {
                components: [
                  { name: "takeClaims", type: "bool" },
                  { name: "settleUsingBurn", type: "bool" },
                ],
                name: "settings",
                type: "tuple",
              },
              { name: "hookData", type: "bytes" },
            ],
            name: "swap",
            outputs: [{ name: "", type: "tuple" }],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "swap",
        args: [
          poolKey,
          swapParams,
          { takeClaims: false, settleUsingBurn: false },
          hookData,
        ],
      });

      setSwapStatus(`Swap transaction submitted: ${hash}`);

      // Wait for transaction to be mined
      await publicClient.waitForTransactionReceipt({ hash });

      setSwapStatus("Swap completed successfully!");
      setInputAmount("");
    } catch (error) {
      console.error("Error performing swap:", error);
      setSwapStatus(`Error: ${(error as Error).message}`);
    } finally {
      setIsSwapping(false);
    }
  };

  // Check if approval is needed
  const needsApproval = () => {
    if (!inputAmount) return false;
    try {
      const amountBigInt = parseEther(inputAmount);
      return amountBigInt > allowance;
    } catch {
      return true;
    }
  };

  return (
    <div className="bg-gray-800 p-6 rounded-xl shadow-xl">
      <h2 className="text-xl font-bold mb-6">Swap</h2>

      <div className="space-y-4">
        {/* Input token */}
        <div className="p-4 bg-gray-700 rounded-lg">
          <div className="flex justify-between mb-2">
            <label className="text-gray-400">From</label>
            <span className="text-blue-400 cursor-pointer text-sm">Max</span>
          </div>
          <div className="flex items-center">
            <input
              type="text"
              value={inputAmount}
              onChange={handleInputChange}
              placeholder="0.00"
              className="bg-transparent text-xl font-medium focus:outline-none w-full"
              disabled={!isConnected || isSwapping || isApproving}
            />
            <div className="flex items-center bg-gray-600 px-3 py-1 rounded-lg">
              <span>
                {swapDirection === "0to1" ? TOKEN0_SYMBOL : TOKEN1_SYMBOL}
              </span>
            </div>
          </div>
        </div>

        {/* Swap direction button */}
        <div className="flex justify-center">
          <button
            onClick={toggleSwapDirection}
            disabled={isSwapping || isApproving}
            className="bg-gray-700 p-2 rounded-full hover:bg-gray-600 transition-colors disabled:opacity-50"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4"
              />
            </svg>
          </button>
        </div>

        {/* Output token */}
        <div className="p-4 bg-gray-700 rounded-lg">
          <div className="flex justify-between mb-2">
            <label className="text-gray-400">To (estimated)</label>
            <span className="text-gray-400 text-sm">
              Rate: 1 {swapDirection === "0to1" ? TOKEN0_SYMBOL : TOKEN1_SYMBOL}{" "}
              = {rate}{" "}
              {swapDirection === "0to1" ? TOKEN1_SYMBOL : TOKEN0_SYMBOL}
            </span>
          </div>
          <div className="flex items-center">
            <input
              type="text"
              value={calculateOutputAmount()}
              readOnly
              className="bg-transparent text-xl font-medium focus:outline-none w-full"
            />
            <div className="flex items-center bg-gray-600 px-3 py-1 rounded-lg">
              <span>
                {swapDirection === "0to1" ? TOKEN1_SYMBOL : TOKEN0_SYMBOL}
              </span>
            </div>
          </div>
        </div>

        {/* Status message */}
        {swapStatus && (
          <div className="text-sm text-center p-2 bg-gray-700 rounded-lg">
            {swapStatus}
          </div>
        )}

        {/* Action buttons */}
        <div className="space-y-2">
          {isConnected &&
            inputAmount &&
            parseFloat(inputAmount) > 0 &&
            needsApproval() && (
              <button
                onClick={handleApprove}
                disabled={isApproving || isSwapping}
                className={`w-full py-3 rounded-lg font-medium ${
                  isApproving
                    ? "bg-gray-600 cursor-not-allowed"
                    : "bg-blue-600 hover:bg-blue-700"
                } transition-colors`}
              >
                {isApproving ? "Approving..." : "Approve"}
              </button>
            )}

          <button
            onClick={handleSwap}
            disabled={
              !isConnected ||
              !inputAmount ||
              parseFloat(inputAmount) === 0 ||
              isSwapping ||
              isApproving ||
              needsApproval()
            }
            className={`w-full py-3 rounded-lg font-medium ${
              isConnected &&
              inputAmount &&
              parseFloat(inputAmount) > 0 &&
              !isSwapping &&
              !isApproving &&
              !needsApproval()
                ? "bg-gradient-to-r from-blue-500 to-purple-600 hover:from-blue-600 hover:to-purple-700"
                : "bg-gray-600 cursor-not-allowed"
            } transition-colors`}
          >
            {!isConnected
              ? "Connect Wallet to Swap"
              : !inputAmount || parseFloat(inputAmount) === 0
              ? "Enter an Amount"
              : needsApproval()
              ? "Approve First"
              : isSwapping
              ? "Swapping..."
              : "Swap"}
          </button>
        </div>
      </div>
    </div>
  );
}
