import { useState } from "react";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useReadContract,
  useSignTypedData,
  useWriteContract,
} from "wagmi";
import { isAddress, isHex, type Address, type Hex } from "viem";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { addresses } from "../config";
import { credentialRegistryAbi, issuerRegistryAbi } from "../abi";
import {
  credentialIdOf,
  credentialTypes,
  dataHashOf,
  downloadJson,
  eip712Domain,
  schemaIdOf,
  shortHex,
  toCredentialFile,
  type Credential,
} from "../lib/credential";

export function IssuerTab() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();
  const { signTypedDataAsync } = useSignTypedData();

  const [note, setNote] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const profile = useReadContract({
    address: addresses.issuerRegistry,
    abi: issuerRegistryAbi,
    functionName: "getIssuer",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: Boolean(address), retry: false },
  });
  const registered = profile.isSuccess;

  // register()
  const [name, setName] = useState("");
  const [ensName, setEnsName] = useState("");
  const [metadataURI, setMetadataURI] = useState("");

  // issue()
  const [recipient, setRecipient] = useState("");
  const [schemaLabel, setSchemaLabel] = useState("BTECH_DEGREE_V1");
  const [dataJson, setDataJson] = useState('{"degree":"B.Tech","branch":"Computer Engineering"}');
  const [uri, setUri] = useState("");
  const [expiryDays, setExpiryDays] = useState("0");
  const [nonce, setNonce] = useState("0");

  // revoke()
  const [revokeId, setRevokeId] = useState("");

  // batch
  const [batchSchemaLabel, setBatchSchemaLabel] = useState("BTECH_DEGREE_V1");
  const [batchLines, setBatchLines] = useState("");
  const [batchUri, setBatchUri] = useState("Class of 2027");

  async function act(label: string, action: () => Promise<string>) {
    setBusy(true);
    setError("");
    setNote("");
    try {
      setNote(`${label}: ${await action()}`);
    } catch (err) {
      setError(err instanceof Error ? err.message.split("\n")[0] : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function waitFor(hash: Hex): Promise<string> {
    await client!.waitForTransactionReceipt({ hash });
    return `confirmed in tx ${shortHex(hash, 8)}`;
  }

  function buildCredential(): { credential: Credential; error?: string } {
    if (!address) return { credential: null as never, error: "Connect a wallet first." };
    if (!isAddress(recipient.trim())) return { credential: null as never, error: "Recipient must be a valid address." };
    const days = Number(expiryDays || "0");
    const now = BigInt(Math.floor(Date.now() / 1000));
    return {
      credential: {
        issuer: address,
        recipient: recipient.trim() as Address,
        schemaId: schemaIdOf(schemaLabel),
        dataHash: dataHashOf(dataJson),
        uri: uri.trim(),
        issuedAt: now,
        expiresAt: days > 0 ? now + BigInt(Math.floor(days * 86400)) : 0n,
        nonce: BigInt(nonce || "0"),
      },
    };
  }

  const register = () =>
    act("Registered", async () => {
      const hash = await writeContractAsync({
        address: addresses.issuerRegistry,
        abi: issuerRegistryAbi,
        functionName: "register",
        args: [name, ensName, metadataURI],
      });
      const outcome = await waitFor(hash);
      await profile.refetch();
      return outcome;
    });

  const issueOnChain = () =>
    act("Issued on-chain", async () => {
      const built = buildCredential();
      if (built.error) throw new Error(built.error);
      const id = credentialIdOf(built.credential);
      const hash = await writeContractAsync({
        address: addresses.credentialRegistry,
        abi: credentialRegistryAbi,
        functionName: "issue",
        args: [built.credential],
      });
      await waitFor(hash);
      return `credential id ${id} - share this id with the recipient`;
    });

  const signOnly = () =>
    act("Signed off-chain (zero gas)", async () => {
      const built = buildCredential();
      if (built.error) throw new Error(built.error);
      const signature = await signTypedDataAsync({
        domain: eip712Domain(chainId, addresses.credentialRegistry),
        types: credentialTypes,
        primaryType: "Credential",
        message: built.credential,
      });
      const file = toCredentialFile(
        built.credential,
        signature,
        chainId,
        addresses.credentialRegistry,
        schemaLabel,
        dataJson,
      );
      downloadJson(`certchain-credential-${shortHex(credentialIdOf(built.credential), 4)}.json`, file);
      return "credential file downloaded - the recipient can verify it forever, no transaction needed";
    });

  const revoke = () =>
    act("Revoked", async () => {
      const id = revokeId.trim() as Hex;
      if (!isHex(id) || id.length !== 66) throw new Error("A credential id is 0x + 64 hex characters.");
      const hash = await writeContractAsync({
        address: addresses.credentialRegistry,
        abi: credentialRegistryAbi,
        functionName: "revoke",
        args: [id],
      });
      return waitFor(hash);
    });

  const issueBatch = () =>
    act("Batch issued", async () => {
      const schemaId = schemaIdOf(batchSchemaLabel);
      const entries = batchLines
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean)
        .map((line, index) => {
          const pipe = line.indexOf("|");
          if (pipe < 0) throw new Error(`Line ${index + 1}: expected "address | data-json".`);
          const entryAddress = line.slice(0, pipe).trim();
          const entryData = line.slice(pipe + 1).trim();
          if (!isAddress(entryAddress)) throw new Error(`Line ${index + 1}: "${entryAddress}" is not an address.`);
          return { recipient: entryAddress as Address, data: entryData, dataHash: dataHashOf(entryData) };
        });
      if (entries.length < 2) throw new Error("A batch needs at least 2 lines (one credential per line).");

      const tree = StandardMerkleTree.of(
        entries.map((entry) => [entry.recipient, schemaId, entry.dataHash]),
        ["address", "bytes32", "bytes32"],
      );
      const hash = await writeContractAsync({
        address: addresses.credentialRegistry,
        abi: credentialRegistryAbi,
        functionName: "issueBatch",
        args: [tree.root as Hex, batchUri],
      });
      await waitFor(hash);
      downloadJson(`certchain-batch-${shortHex(tree.root, 4)}.json`, {
        certchain: "batch-proofs-v1",
        root: tree.root,
        schemaLabel: batchSchemaLabel,
        entries: entries.map((entry, index) => ({ ...entry, proof: tree.getProof(index) })),
      });
      return `${entries.length} credentials committed under root ${shortHex(tree.root, 8)} - proofs file downloaded, distribute each entry to its recipient`;
    });

  if (!isConnected) {
    return <p className="empty-note">Connect a wallet above to act as an issuer. On a local anvil chain, import one of the anvil test keys into your wallet.</p>;
  }

  return (
    <section>
      <fieldset>
        <legend className="eyebrow">form 01 · register() - one-time issuer profile for {shortHex(address ?? "")}</legend>
        {registered && profile.data ? (
          <dl className="detail-list">
            <div><dt className="eyebrow">name</dt><dd>{profile.data.name}{profile.data.verified ? " ✓ verified" : ""}</dd></div>
            <div><dt className="eyebrow">ens</dt><dd>{profile.data.ensName || "-"}</dd></div>
            <div><dt className="eyebrow">status</dt><dd>{profile.data.active ? "active" : "paused"}</dd></div>
          </dl>
        ) : (
          <>
            <label>
              Institution name
              <input placeholder="KJ Somaiya College of Engineering" value={name} onChange={(event) => setName(event.target.value)} />
            </label>
            <label>
              ENS name (display only, optional)
              <input placeholder="kjsce.eth" value={ensName} onChange={(event) => setEnsName(event.target.value)} />
            </label>
            <label>
              Metadata URI (optional)
              <input placeholder="ipfs://... or https://..." value={metadataURI} onChange={(event) => setMetadataURI(event.target.value)} />
            </label>
            <button className="primary" disabled={busy} onClick={register}>Register issuer</button>
          </>
        )}
      </fieldset>

      <fieldset disabled={!registered}>
        <legend className="eyebrow">form 02 · issue() or sign - one credential</legend>
        <label>
          Recipient address
          <input className="mono" placeholder="0x..." value={recipient} onChange={(event) => setRecipient(event.target.value)} />
        </label>
        <label>
          Schema label <span className="hint">hashed to bytes32 schemaId</span>
          <input value={schemaLabel} onChange={(event) => setSchemaLabel(event.target.value)} />
        </label>
        <label>
          Credential data (JSON) <span className="hint">only its keccak256 hash goes on-chain</span>
          <textarea className="mono" rows={3} value={dataJson} onChange={(event) => setDataJson(event.target.value)} />
        </label>
        <div className="field-row">
          <label>
            Expires in (days, 0 = never)
            <input inputMode="numeric" value={expiryDays} onChange={(event) => setExpiryDays(event.target.value)} />
          </label>
          <label>
            Nonce
            <input inputMode="numeric" value={nonce} onChange={(event) => setNonce(event.target.value)} />
          </label>
        </div>
        <label>
          URI (optional pointer to the data)
          <input placeholder="ipfs://..." value={uri} onChange={(event) => setUri(event.target.value)} />
        </label>
        <div className="button-row">
          <button className="primary" disabled={busy} onClick={issueOnChain}>Issue on-chain</button>
          <button disabled={busy} onClick={signOnly}>Sign only (no gas)</button>
        </div>
      </fieldset>

      <fieldset disabled={!registered}>
        <legend className="eyebrow">form 03 · issueBatch() - thousands of credentials, one transaction</legend>
        <label>
          Shared schema label
          <input value={batchSchemaLabel} onChange={(event) => setBatchSchemaLabel(event.target.value)} />
        </label>
        <label>
          One credential per line: <span className="mono hint">address | data-json</span>
          <textarea
            className="mono"
            rows={5}
            placeholder={'0xAbC... | {"name":"Asha","cgpa":9.1}\n0xDeF... | {"name":"Rohan","cgpa":8.7}'}
            value={batchLines}
            onChange={(event) => setBatchLines(event.target.value)}
          />
        </label>
        <label>
          Batch description
          <input value={batchUri} onChange={(event) => setBatchUri(event.target.value)} />
        </label>
        <button className="primary" disabled={busy} onClick={issueBatch}>Commit batch root</button>
      </fieldset>

      <fieldset disabled={!registered}>
        <legend className="eyebrow">form 04 · revoke() - permanent, issuer-only</legend>
        <label>
          Credential id
          <input className="mono" placeholder="0x..." value={revokeId} onChange={(event) => setRevokeId(event.target.value)} />
        </label>
        <button className="danger" disabled={busy} onClick={revoke}>Revoke credential</button>
      </fieldset>

      {note && <p className="ok-note">{note}</p>}
      {error && <p className="error-note">{error}</p>}
    </section>
  );
}
