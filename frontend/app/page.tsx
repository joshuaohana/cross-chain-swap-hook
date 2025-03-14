import ConnectWallet from "./components/ConnectWallet";
import TokenBalances from "./components/TokenBalances";
import SwapInterface from "./components/SwapInterface";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center p-6 pt-24 bg-gradient-to-b from-gray-900 to-black text-white">
      <div className="w-full max-w-5xl">
        <h1 className="text-5xl font-bold mb-2 bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-purple-600">
          Cross-Chain Arbitrage Swap
        </h1>
        <p className="text-gray-400 mb-12">
          Seamlessly get best swap price across multiple chains
        </p>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div className="col-span-1">
            <div className="mb-8">
              <ConnectWallet />
            </div>
            <div>
              <TokenBalances />
            </div>
          </div>

          {/* Right column - Swap interface */}
          <div className="col-span-1 md:col-span-2">
            <SwapInterface />
          </div>
        </div>
      </div>
    </main>
  );
}
