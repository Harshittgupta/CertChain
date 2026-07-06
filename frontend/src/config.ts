import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected, mock } from "wagmi/connectors";
import { defineChain, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Local anvil chain. `anvil` + the Deploy script from a fresh chain always produces the
 * same deterministic addresses, which are the defaults below - so the local demo needs
 * zero configuration: run anvil, deploy, `npm run dev`, done.
 */
export const anvilLocal = defineChain({
  id: 31337,
  name: "Anvil (local)",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
});

const enableDevWallet = import.meta.env.VITE_ENABLE_DEV_WALLET === "true";

// Dev-only wallet using Anvil test key 0
const devAccount = privateKeyToAccount(
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
);

export const config = createConfig({
  chains: [anvilLocal, sepolia],
  connectors: [
    ...(enableDevWallet
      ? [
          mock({
            accounts: [devAccount.address],
          }),
        ]
      : []),
    injected(),
  ],
  transports: {
    [anvilLocal.id]: http("http://127.0.0.1:8545"),
    // Leave VITE_SEPOLIA_RPC_URL unset to use viem's default public Sepolia RPC
    // (fine for demos; get a free Alchemy/Infura endpoint for anything sustained).
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC_URL || undefined),
  },
});

const env = import.meta.env;

/** Contract addresses. Defaults = deterministic first-three-deploys on a fresh anvil. */
export const addresses = {
  issuerRegistry: (env.VITE_ISSUER_REGISTRY ||
    "0x5FbDB2315678afecb367f032d93F642f64180aa3") as Address,
  credentialRegistry: (env.VITE_CREDENTIAL_REGISTRY ||
    "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512") as Address,
  certificate: (env.VITE_CERTIFICATE ||
    "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0") as Address,
};

/** Block to scan credential events from (set after deploying to Sepolia to keep log queries fast). */
export const deployBlock = BigInt(env.VITE_DEPLOY_BLOCK || "0");
