import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

class SwapBot {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private hookContract: ethers.Contract;

  private readonly RPC_URL = process.env.RPC_URL;
  private readonly PRIVATE_KEY = process.env.PRIVATE_KEY;
  private readonly HOOK_ADDRESS = process.env.HOOK_ADDRESS;
  private readonly TOKEN0_ADDRESS = process.env.TOKEN0_ADDRESS;
  private readonly TOKEN1_ADDRESS = process.env.TOKEN1_ADDRESS;

  private readonly hookAbi = [
    "event SwapIntent(bytes32 indexed swapId, address indexed owner, address indexed tokenIn, address tokenOut, uint256 amountIn)",
    "function completeSwap(bytes32 swapId, bool betterPriceFound) external",
  ];

  private readonly erc20Abi = [
    "function balanceOf(address account) external view returns (uint256)",
  ];

  constructor() {
    if (!this.RPC_URL || !this.PRIVATE_KEY || !this.HOOK_ADDRESS) {
      throw new Error(
        "Missing required environment variables: RPC_URL, PRIVATE_KEY, or HOOK_ADDRESS"
      );
    }

    this.provider = new ethers.JsonRpcProvider(this.RPC_URL);
    this.wallet = new ethers.Wallet(this.PRIVATE_KEY, this.provider);
    this.hookContract = new ethers.Contract(
      this.HOOK_ADDRESS,
      this.hookAbi,
      this.wallet
    );
  }

  async listen(): Promise<void> {
    try {
      console.log(`Bot listening on ${this.RPC_URL}...`);

      this.hookContract.on(
        "SwapIntent",
        async (
          swapId: string,
          owner: string,
          tokenIn: string,
          tokenOut: string,
          amountIn: ethers.BigNumberish,
          event: ethers.EventLog
        ) => {
          try {
            console.log(
              `\n---\nSwapIntent detected: swapId=${swapId}, owner=${owner}, tokenIn=${tokenIn}, tokenOut=${tokenOut}, amountIn=${ethers.formatEther(
                amountIn
              )} ether`
            );
            console.log("BEFORE");
            await this.printBalances();

            // complete the swap
            await this.hookContract.completeSwap(swapId, false, {
              swapId: 0,
              txnId: 0,
              chainId: 0,
              tokenOut: 0,
              amountOut: 0,
            });

            console.log("AFTER");
            await this.printBalances();
          } catch (error: unknown) {
            console.error(`Error completing swap: ${(error as Error).message}`);
          }
        }
      );

      this.provider.on("error", (error: Error) => {
        console.error(`Provider error: ${error.message}`);
      });
    } catch (error: unknown) {
      throw new Error(`Bot failed to start: ${(error as Error).message}`);
    }
  }

  async printBalances(): Promise<void> {
    if (!this.TOKEN0_ADDRESS || !this.TOKEN1_ADDRESS) {
      console.error(
        "Missing TOKEN0_ADDRESS or TOKEN1_ADDRESS in environment variables"
      );
      return;
    }

    try {
      const token0Contract = new ethers.Contract(
        this.TOKEN0_ADDRESS,
        this.erc20Abi,
        this.provider
      );
      const token1Contract = new ethers.Contract(
        this.TOKEN1_ADDRESS,
        this.erc20Abi,
        this.provider
      );

      // Get balances for wallet
      const walletToken0Balance = await token0Contract.balanceOf(
        this.wallet.address
      );
      const walletToken1Balance = await token1Contract.balanceOf(
        this.wallet.address
      );

      // Get balances for hook
      const hookToken0Balance = await token0Contract.balanceOf(
        this.HOOK_ADDRESS
      );
      const hookToken1Balance = await token1Contract.balanceOf(
        this.HOOK_ADDRESS
      );

      console.log("\nWallet Balances:");
      console.log(
        `Token0 (${this.TOKEN0_ADDRESS}): ${ethers.formatEther(
          walletToken0Balance
        )}`
      );
      console.log(
        `Token1 (${this.TOKEN1_ADDRESS}): ${ethers.formatEther(
          walletToken1Balance
        )}`
      );

      console.log("\nHook Balances:");
      console.log(
        `Token0 (${this.TOKEN0_ADDRESS}): ${ethers.formatEther(
          hookToken0Balance
        )}`
      );
      console.log(
        `Token1 (${this.TOKEN1_ADDRESS}): ${ethers.formatEther(
          hookToken1Balance
        )}`
      );
    } catch (error: unknown) {
      console.error(`Error fetching balances: ${(error as Error).message}`);
    }
  }

  async start(): Promise<void> {
    try {
      await this.listen();
      await this.printBalances();
    } catch (error: unknown) {
      console.error(`Bot failed to start: ${(error as Error).message}`);
      process.exit(1);
    }
  }
}

// Usage
const bot = new SwapBot();
bot.start().catch((error: Error) => {
  console.error(`Bot failed to start: ${error.message}`);
  process.exit(1);
});
