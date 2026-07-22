import { useCallback, useEffect, useState } from "react";
import { useAccount, useChainId, usePublicClient, useWriteContract } from "wagmi";
import { parseAbiItem, type Hex } from "viem";
import { addresses, deployBlock } from "../config";
import { credentialRegistryAbi, issuerRegistryAbi, soulboundCertificateAbi } from "../abi";
import { shortHex } from "../lib/credential";

const issuedEvent = parseAbiItem(
  "event CredentialIssued(bytes32 indexed credentialId, address indexed issuer, address indexed recipient, bytes32 schemaId, bytes32 dataHash, string uri, uint64 issuedAt, uint64 expiresAt)"
);

interface OwnedCredential {
  id: Hex;
  issuer: Hex;
  issuerName: string;
  issuedAt: number;
  ok: boolean;
  reason: string;
  minted: boolean;
  image?: string; // decoded on-chain SVG data URI, when minted
}

export function WalletTab() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [items, setItems] = useState<OwnedCredential[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [note, setNote] = useState<React.ReactNode>("");
  const [pendingTx, setPendingTx] = useState("");
  const [title, setTitle] = useState("Bachelor of Technology");

  const getEtherscanLink = (hash: string) =>
    chainId === 11155111 ? `https://sepolia.etherscan.io/tx/${hash}` : null;

  const load = useCallback(async () => {
    if (!client || !address) return;
    setLoading(true);
    setError("");
    try {
      let logs;
      try {
        logs = await client.getLogs({
          address: addresses.credentialRegistry,
          event: issuedEvent,
          args: { recipient: address },
          fromBlock: deployBlock,
          toBlock: "latest",
        });
      } catch {
        // Fallback for public RPC block range limits: query in windows
        const currentBlock = await client.getBlockNumber();
        const chunkSize = 50000n;
        logs = [];
        for (let start = deployBlock; start <= currentBlock; start += chunkSize) {
          const end = start + chunkSize - 1n > currentBlock ? currentBlock : start + chunkSize - 1n;
          const chunk = await client.getLogs({
            address: addresses.credentialRegistry,
            event: issuedEvent,
            args: { recipient: address },
            fromBlock: start,
            toBlock: end,
          });
          logs.push(...chunk);
        }
      }

      const owned: OwnedCredential[] = [];
      for (const log of logs) {
        const id = log.args.credentialId!;
        const issuer = log.args.issuer!;
        const [ok, reason] = await client.readContract({
          address: addresses.credentialRegistry,
          abi: credentialRegistryAbi,
          functionName: "verify",
          args: [id],
        });
        let issuerName = "unregistered issuer";
        try {
          const profile = await client.readContract({
            address: addresses.issuerRegistry,
            abi: issuerRegistryAbi,
            functionName: "getIssuer",
            args: [issuer],
          });
          issuerName = profile.name;
        } catch {
          /* keep fallback */
        }
        let minted = false;
        let image: string | undefined;
        try {
          await client.readContract({
            address: addresses.certificate,
            abi: soulboundCertificateAbi,
            functionName: "ownerOf",
            args: [BigInt(id)],
          });
          minted = true;
          const uri = await client.readContract({
            address: addresses.certificate,
            abi: soulboundCertificateAbi,
            functionName: "tokenURI",
            args: [BigInt(id)],
          });
          const metadata = JSON.parse(atob(uri.split(",")[1]));
          image = metadata.image;
        } catch {
          /* not minted */
        }
        owned.push({
          id,
          issuer,
          issuerName,
          issuedAt: Number(log.args.issuedAt ?? 0n),
          ok,
          reason,
          minted,
          image,
        });
      }
      setItems(owned.reverse());
    } catch (err) {
      setError(
        `Failed to scan logs from RPC: ${err instanceof Error ? err.message.split("\n")[0] : String(err)}`
      );
    } finally {
      setLoading(false);
    }
  }, [client, address]);

  useEffect(() => {
    void load();
  }, [load]);

  async function mint(id: Hex) {
    setError("");
    setNote("");
    setPendingTx("");
    try {
      const hash = await writeContractAsync({
        address: addresses.certificate,
        abi: soulboundCertificateAbi,
        functionName: "mint",
        args: [id, title],
      });

      const etherscanUrl = getEtherscanLink(hash);
      setPendingTx(hash);
      setNote(
        <span>
          Minting transaction submitted ({shortHex(hash, 8)}). Waiting for block confirmation...{" "}
          {etherscanUrl && (
            <a href={etherscanUrl} target="_blank" rel="noreferrer">
              View on Etherscan
            </a>
          )}
        </span>
      );

      await client!.waitForTransactionReceipt({ hash });
      setPendingTx("");
      setNote(
        <span>
          Certificate minted! Tx:{" "}
          {etherscanUrl ? (
            <a href={etherscanUrl} target="_blank" rel="noreferrer">
              {shortHex(hash, 8)}
            </a>
          ) : (
            shortHex(hash, 8)
          )}
          . It is soulbound: it can never be transferred.
        </span>
      );
      await load();
    } catch (err) {
      setPendingTx("");
      setError(err instanceof Error ? err.message.split("\n")[0] : String(err));
    }
  }

  if (!isConnected) {
    return <p className="empty-note">Connect a wallet to see credentials issued to your address.</p>;
  }

  return (
    <section>
      <p className="lede">
        Credentials issued to {shortHex(address ?? "")} - read straight from CredentialIssued events.
        Signed-only and batch credentials live in files, not here; that is the point of those modes.
      </p>

      <label className="inline-label">
        Certificate title for minting
        <input value={title} onChange={(event) => setTitle(event.target.value)} />
      </label>

      {loading && <p className="empty-note">Reading event logs from deploy block {deployBlock.toString()}...</p>}
      {!loading && items.length === 0 && !error && (
        <p className="empty-note">
          Nothing on-chain for this address yet. Ask an issuer to issue you a credential, or open the
          Issuer tab and issue one to yourself to try the flow.
        </p>
      )}

      <div className="credential-grid">
        {items.map((item) => (
          <article key={item.id} className={`credential-card ${item.ok ? "" : "is-invalid"}`}>
            {item.image ? (
              <img className="cert-image" src={item.image} alt="On-chain certificate" />
            ) : (
              <div className="cert-placeholder eyebrow">no certificate minted</div>
            )}
            <dl className="detail-list">
              <div><dt className="eyebrow">issuer</dt><dd>{item.issuerName}</dd></div>
              <div><dt className="eyebrow">credential</dt><dd className="mono">{shortHex(item.id, 8)}</dd></div>
              <div><dt className="eyebrow">issued</dt><dd>{new Date(item.issuedAt * 1000).toLocaleDateString()}</dd></div>
              <div><dt className="eyebrow">status</dt><dd>{item.ok ? "valid" : item.reason}</dd></div>
            </dl>
            {!item.minted && item.ok && (
              <button className="primary" disabled={Boolean(pendingTx)} onClick={() => mint(item.id)}>
                {pendingTx ? "Minting..." : "Mint soulbound certificate"}
              </button>
            )}
          </article>
        ))}
      </div>

      {note && <p className="ok-note">{note}</p>}
      {error && <p className="error-note">{error}</p>}
    </section>
  );
}
