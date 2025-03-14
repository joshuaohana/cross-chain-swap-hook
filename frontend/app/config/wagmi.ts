import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors";
import { CHAIN_ID, RPC_URL } from "./contracts";

const anvil = {
  id: CHAIN_ID,
  name: "Anvil",
  nativeCurrency: {
    name: "Ethereum",
    symbol: "ETH",
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: [RPC_URL],
    },
    public: {
      http: [RPC_URL],
    },
  },
} as const;

const getConnectors = () => {
  if (typeof window !== "undefined") {
    return [injected()];
  }
  return [];
};

export const config = createConfig({
  chains: [anvil],
  connectors: getConnectors(),
  transports: {
    [anvil.id]: http(RPC_URL),
  },
});
