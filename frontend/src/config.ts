import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected, mock } from "wagmi/connectors";
import { defineChain, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Local anvil chain configuration.
 */
export const anvilLocal = defineChain({
  id: 31337,
  name: "Anvil (local)",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
});

const env = import.meta.env;
const enableDevWallet = env.VITE_ENABLE_DEV_WALLET === "true";

// Read dev key dynamically only when dev wallet is explicitly enabled
const devKey = enableDevWallet
  ? env.VITE_DEV_KEY || "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  : undefined;

// Default chain selection: Sepolia in production/hosted mode or when configured
const isSepoliaDefault =
  env.VITE_DEFAULT_CHAIN === "sepolia" ||
  env.PROD ||
  env.VITE_CREDENTIAL_REGISTRY !== undefined;

export const config = createConfig({
  chains: isSepoliaDefault ? [sepolia, anvilLocal] : [anvilLocal, sepolia],
  connectors: [
    ...(enableDevWallet && devKey
      ? [
          mock({
            accounts: [privateKeyToAccount(devKey as `0x${string}`).address],
          }),
        ]
      : []),
    injected(),
  ],
  transports: {
    [anvilLocal.id]: http("http://127.0.0.1:8545"),
    [sepolia.id]: http(env.VITE_SEPOLIA_RPC_URL || undefined),
  },
});

/** Contract addresses with defaults for deployed Sepolia network when running hosted/production. */
export const addresses = {
  issuerRegistry: (env.VITE_ISSUER_REGISTRY ||
    (isSepoliaDefault
      ? "0xA5A93F550FC33abD66147107e884D8331820a0E3"
      : "0x5FbDB2315678afecb367f032d93F642f64180aa3")) as Address,
  credentialRegistry: (env.VITE_CREDENTIAL_REGISTRY ||
    (isSepoliaDefault
      ? "0xD928b9FE38e42B29B725Bcf003F4B68c6db4cFCb"
      : "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512")) as Address,
  certificate: (env.VITE_CERTIFICATE ||
    (isSepoliaDefault
      ? "0x452DEFAfD0821FcBFD78A3a5a5F181d34A9e42Ea"
      : "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0")) as Address,
};

/** Block to scan credential events from. Defaults to Sepolia deploy block in hosted mode. */
export const deployBlock = BigInt(
  env.VITE_DEPLOY_BLOCK || (isSepoliaDefault ? "11342345" : "0")
);
