import { useState } from "react";
import { useAccount, useChainId, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { sepolia } from "wagmi/chains";
import { shortHex } from "../lib/credential";

export function Masthead() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, error } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const chainId = useChainId();

  const [hasTriedConnect, setHasTriedConnect] = useState(false);

  const isSupportedChain = chainId === 11155111 || chainId === 31337;
  const chainLabel = chainId === 31337 ? "anvil · local" : chainId === 11155111 ? "sepolia" : `chain ${chainId}`;

  return (
    <header className="masthead">
      <p className="eyebrow">an on-chain credential registry</p>
      <h1>CERTCHAIN</h1>
      <p className="tagline">Trust that comes from mathematics instead of middlemen.</p>
      <div className="masthead-rule" aria-hidden="true" />
      <div className="wallet-line">
        <span className="eyebrow">{chainLabel}</span>
        {isConnected ? (
          <>
            <span className="mono">{shortHex(address ?? "")}</span>
            <button className="quiet" onClick={() => disconnect()}>Disconnect</button>
          </>
        ) : (
          connectors.map((connector) => {
            const label = connector.name.toLowerCase().includes("mock")
              ? "Connect Dev Wallet"
              : connector.name.toLowerCase().includes("injected")
              ? "Connect Wallet (MetaMask)"
              : `Connect ${connector.name}`;
            return (
              <button
                key={connector.uid}
                className="quiet"
                onClick={() => {
                  setHasTriedConnect(true);
                  connect({ connector });
                }}
              >
                {label}
              </button>
            );
          })
        )}
      </div>

      {isConnected && !isSupportedChain && (
        <p className="error-note" style={{ marginTop: "1rem", textAlign: "center" }}>
          ⚠️ You are connected to unsupported chain (id {chainId}). Please switch to Sepolia.{" "}
          <button
            className="primary"
            style={{ marginLeft: "0.5rem", padding: "0.2rem 0.6rem" }}
            onClick={() => switchChain({ chainId: sepolia.id })}
          >
            Switch to Sepolia
          </button>
        </p>
      )}

      {error && hasTriedConnect && (
        <p className="error-note" style={{ marginTop: "0.75rem", textAlign: "center" }}>
          {error.message.includes("Provider not found")
            ? "No browser wallet (like MetaMask) found. Verification works without a wallet below!"
            : error.message.split("\n")[0]}
        </p>
      )}
    </header>
  );
}
