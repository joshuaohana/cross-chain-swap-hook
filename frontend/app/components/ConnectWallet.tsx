"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";
import { injected } from "wagmi/connectors";
import { useState, useEffect } from "react";

export default function ConnectWallet() {
  const { address, isConnected } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  // Format address for display (0x1234...5678)
  const formatAddress = (address: string | undefined) => {
    if (!address) return "";
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  // if not mounted, render placeholder with the same structure to avoid hydration mismatch
  if (!mounted) {
    return (
      <div className="bg-gray-800 p-6 rounded-xl shadow-xl">
        <h2 className="text-xl font-bold mb-4">Wallet</h2>
        <div>
          <p className="text-gray-300 mb-4">Connect your wallet to start</p>
          <button
            disabled
            className="w-full py-2 px-4 bg-gray-600 text-white rounded-lg"
          >
            Loading...
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-gray-800 p-6 rounded-xl shadow-xl">
      <h2 className="text-xl font-bold mb-4">Wallet</h2>

      {isConnected ? (
        <div>
          <p className="flex items-center mb-4">
            <span className="w-3 h-3 rounded-full bg-green-500 mr-2"></span>
            <span className="text-gray-300">
              Connected: {formatAddress(address)}
            </span>
          </p>
          <button
            onClick={() => disconnect()}
            className="w-full py-2 px-4 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors"
          >
            Disconnect
          </button>
        </div>
      ) : (
        <div>
          <p className="text-gray-300 mb-4">Connect your wallet to start</p>
          <button
            onClick={() => connect({ connector: injected() })}
            className="w-full py-2 px-4 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
          >
            Connect Wallet
          </button>
        </div>
      )}
    </div>
  );
}
