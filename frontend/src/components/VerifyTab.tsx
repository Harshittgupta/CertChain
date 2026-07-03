import { useState } from "react";
import { usePublicClient } from "wagmi";
import { isHex, type Hex } from "viem";
import { addresses } from "../config";
import { credentialRegistryAbi, issuerRegistryAbi } from "../abi";
import { Stamp } from "./Stamp";
import {
  fromCredentialFile,
  schemaIdOf,
  dataHashOf,
  shortHex,
  type CredentialFile,
} from "../lib/credential";

type Mode = "id" | "file" | "batch";

interface Result {
  ok: boolean;
  reason: string;
  details: [string, string][];
}

export function VerifyTab() {
  const client = usePublicClient();
  const [mode, setMode] = useState<Mode>("id");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<Result | null>(null);

  // mode: id
  const [credentialId, setCredentialId] = useState("");
  // mode: file
  const [fileText, setFileText] = useState("");
  // mode: batch
  const [batchRoot, setBatchRoot] = useState("");
  const [batchRecipient, setBatchRecipient] = useState("");
  const [batchSchemaLabel, setBatchSchemaLabel] = useState("");
  const [batchData, setBatchData] = useState("");
  const [batchProof, setBatchProof] = useState("");

  async function issuerNameOf(issuer: Hex): Promise<string> {
    try {
      const profile = await client!.readContract({
        address: addresses.issuerRegistry,
        abi: issuerRegistryAbi,
        functionName: "getIssuer",
        args: [issuer],
      });
      return profile.name + (profile.verified ? " ✓ verified" : "");
    } catch {
      return "unregistered issuer";
    }
  }

  async function run(action: () => Promise<Result>) {
    setBusy(true);
    setError("");
    setResult(null);
    try {
      setResult(await action());
    } catch (err) {
      setError(err instanceof Error ? err.message.split("\n")[0] : String(err));
    } finally {
      setBusy(false);
    }
  }

  const verifyById = () =>
    run(async () => {
      const id = credentialId.trim() as Hex;
      if (!isHex(id) || id.length !== 66) throw new Error("A credential id is 32 bytes: 0x + 64 hex characters.");
      const [ok, reason] = await client!.readContract({
        address: addresses.credentialRegistry,
        abi: credentialRegistryAbi,
        functionName: "verify",
        args: [id],
      });
      const details: [string, string][] = [["credential id", shortHex(id, 10)]];
      if (reason !== "unknown credential") {
        const cred = await client!.readContract({
          address: addresses.credentialRegistry,
          abi: credentialRegistryAbi,
          functionName: "getCredential",
          args: [id],
        });
        details.push(
          ["issuer", `${await issuerNameOf(cred.issuer)} (${shortHex(cred.issuer)})`],
          ["recipient", shortHex(cred.recipient)],
          ["issued at", new Date(Number(cred.issuedAt) * 1000).toLocaleString()],
          ["expires", cred.expiresAt === 0n ? "never" : new Date(Number(cred.expiresAt) * 1000).toLocaleString()],
        );
      }
      return { ok, reason, details };
    });

  const verifyByFile = () =>
    run(async () => {
      let parsed: CredentialFile;
      try {
        parsed = JSON.parse(fileText);
      } catch {
        throw new Error("That is not valid JSON. Paste the whole credential file, braces and all.");
      }
      if (parsed.certchain !== "credential-file-v1") throw new Error("Not a CertChain credential file.");
      const { credential, signature } = fromCredentialFile(parsed);
      if (parsed.data && dataHashOf(parsed.data) !== credential.dataHash) {
        return {
          ok: false,
          reason: "attached data does not match the signed dataHash",
          details: [["dataHash (signed)", shortHex(credential.dataHash, 10)]],
        };
      }
      const [ok, reason] = await client!.readContract({
        address: addresses.credentialRegistry,
        abi: credentialRegistryAbi,
        functionName: "verifySigned",
        args: [credential, signature],
      });
      return {
        ok,
        reason,
        details: [
          ["issuer", `${await issuerNameOf(credential.issuer)} (${shortHex(credential.issuer)})`],
          ["recipient", shortHex(credential.recipient)],
          ["schema", parsed.schemaLabel || shortHex(credential.schemaId, 8)],
          ["signature", shortHex(signature, 8)],
        ],
      };
    });

  const verifyByBatch = () =>
    run(async () => {
      const root = batchRoot.trim() as Hex;
      const recipient = batchRecipient.trim() as Hex;
      if (!isHex(root) || root.length !== 66) throw new Error("Merkle root must be 0x + 64 hex characters.");
      if (!isHex(recipient)) throw new Error("Recipient must be an address.");
      let proof: Hex[];
      try {
        proof = JSON.parse(batchProof);
        if (!Array.isArray(proof)) throw new Error();
      } catch {
        throw new Error('Proof must be a JSON array of 32-byte hex values, e.g. ["0xabc...","0xdef..."].');
      }
      const [ok, reason] = await client!.readContract({
        address: addresses.credentialRegistry,
        abi: credentialRegistryAbi,
        functionName: "verifyInBatch",
        args: [root, recipient, schemaIdOf(batchSchemaLabel), dataHashOf(batchData), proof],
      });
      return {
        ok,
        reason,
        details: [
          ["batch root", shortHex(root, 10)],
          ["recipient", shortHex(recipient)],
          ["schema", batchSchemaLabel],
        ],
      };
    });

  return (
    <section>
      <p className="lede">
        Anyone can verify - no login, no phone call to a registrar, no trust in this website.
        The answer comes from the chain and from mathematics.
      </p>

      <div className="mode-switch" role="tablist" aria-label="Verification mode">
        <button role="tab" aria-selected={mode === "id"} className={mode === "id" ? "on" : ""} onClick={() => setMode("id")}>
          By credential id
        </button>
        <button role="tab" aria-selected={mode === "file"} className={mode === "file" ? "on" : ""} onClick={() => setMode("file")}>
          By credential file
        </button>
        <button role="tab" aria-selected={mode === "batch"} className={mode === "batch" ? "on" : ""} onClick={() => setMode("batch")}>
          By batch proof
        </button>
      </div>

      {mode === "id" && (
        <fieldset>
          <legend className="eyebrow">reads verify(bytes32) on-chain</legend>
          <label>
            Credential id
            <input
              className="mono"
              placeholder="0x...64 hex characters"
              value={credentialId}
              onChange={(event) => setCredentialId(event.target.value)}
            />
          </label>
          <button className="primary" disabled={busy || !client} onClick={verifyById}>
            {busy ? "Checking the registry..." : "Verify"}
          </button>
        </fieldset>
      )}

      {mode === "file" && (
        <fieldset>
          <legend className="eyebrow">reads verifySigned(credential, signature) - works even if never anchored on-chain</legend>
          <label>
            Credential file (JSON)
            <textarea
              className="mono"
              rows={9}
              placeholder='Paste the whole file the issuer produced with "Sign only", starting with {"certchain":"credential-file-v1"...'
              value={fileText}
              onChange={(event) => setFileText(event.target.value)}
            />
          </label>
          <button className="primary" disabled={busy || !client} onClick={verifyByFile}>
            {busy ? "Recovering signer..." : "Verify signature"}
          </button>
        </fieldset>
      )}

      {mode === "batch" && (
        <fieldset>
          <legend className="eyebrow">reads verifyInBatch(root, recipient, schemaId, dataHash, proof)</legend>
          <label>
            Batch merkle root
            <input className="mono" placeholder="0x..." value={batchRoot} onChange={(event) => setBatchRoot(event.target.value)} />
          </label>
          <label>
            Recipient address
            <input className="mono" placeholder="0x..." value={batchRecipient} onChange={(event) => setBatchRecipient(event.target.value)} />
          </label>
          <label>
            Schema label
            <input placeholder="BTECH_DEGREE_V1" value={batchSchemaLabel} onChange={(event) => setBatchSchemaLabel(event.target.value)} />
          </label>
          <label>
            Credential data (exact JSON that was hashed)
            <textarea className="mono" rows={3} value={batchData} onChange={(event) => setBatchData(event.target.value)} />
          </label>
          <label>
            Merkle proof (JSON array)
            <textarea className="mono" rows={3} placeholder='["0x...","0x..."]' value={batchProof} onChange={(event) => setBatchProof(event.target.value)} />
          </label>
          <button className="primary" disabled={busy || !client} onClick={verifyByBatch}>
            {busy ? "Walking the tree..." : "Verify proof"}
          </button>
        </fieldset>
      )}

      {error && <p className="error-note">{error}</p>}

      {result && (
        <div className="result-card">
          <Stamp ok={result.ok} reason={result.reason} />
          {result.details.length > 0 && (
            <dl className="detail-list">
              {result.details.map(([term, value]) => (
                <div key={term}>
                  <dt className="eyebrow">{term}</dt>
                  <dd>{value}</dd>
                </div>
              ))}
            </dl>
          )}
        </div>
      )}
    </section>
  );
}
