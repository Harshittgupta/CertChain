import { useAccount, useChainId, useConnect, useDisconnect } from "wagmi";
import { shortHex } from "../lib/credential";

export function Masthead() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, error } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();

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
          connectors.map((connector) => (
            <button key={connector.uid} className="quiet" onClick={() => connect({ connector })}>
              {connector.name.toLowerCase().includes("mock") ? "Connect Dev Wallet" : `Connect ${connector.name}`}
            </button>
          ))
        )}
      </div>
      {error && <p className="error-note">{error.message.split("\n")[0]} - is a browser wallet installed?</p>}
    </header>
  );
}
