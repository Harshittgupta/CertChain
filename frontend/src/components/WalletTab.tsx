import { useCallback, useEffect, useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { parseAbiItem, type Hex } from "viem";
import { addresses, deployBlock } from "../config";
import { credentialRegistryAbi, issuerRegistryAbi, soulboundCertificateAbi } from "../abi";
import { shortHex } from "../lib/credential";

const issuedEvent = parseAbiItem(
  "event CredentialIssued(bytes32 indexed credentialId, address indexed issuer, address indexed recipient, bytes32 schemaId, bytes32 dataHash, string uri, uint64 issuedAt, uint64 expiresAt)",
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
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [items, setItems] = useState<OwnedCredential[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [note, setNote] = useState("");
  const [title, setTitle] = useState("Bachelor of Technology");

  const load = useCallback(async () => {
    if (!client || !address) return;
    setLoading(true);
    setError("");
    try {
      const logs = await client.getLogs({
        address: addresses.credentialRegistry,
        event: issuedEvent,
        args: { recipient: address },
        fromBlock: deployBlock,
        toBlock: "latest",
      });
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
      setError(err instanceof Error ? err.message.split("\n")[0] : String(err));
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
    try {
      const hash = await writeContractAsync({
        address: addresses.certificate,
        abi: soulboundCertificateAbi,
        functionName: "mint",
        args: [id, title],
      });
      await client!.waitForTransactionReceipt({ hash });
      setNote(`Certificate minted in tx ${shortHex(hash, 8)}. It is soulbound: it can never be transferred.`);
      await load();
    } catch (err) {
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

      {loading && <p className="empty-note">Reading the event log...</p>}
      {!loading && items.length === 0 && (
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
              <button className="primary" onClick={() => mint(item.id)}>Mint soulbound certificate</button>
            )}
          </article>
        ))}
      </div>

      {note && <p className="ok-note">{note}</p>}
      {error && <p className="error-note">{error}</p>}
    </section>
  );
}
