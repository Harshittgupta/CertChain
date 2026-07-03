import {
  encodeAbiParameters,
  keccak256,
  stringToBytes,
  type Address,
  type Hex,
} from "viem";

/** Mirrors the Solidity struct exactly. bigint fields map to uint64/uint256. */
export interface Credential {
  issuer: Address;
  recipient: Address;
  schemaId: Hex;
  dataHash: Hex;
  uri: string;
  issuedAt: bigint;
  expiresAt: bigint;
  nonce: bigint;
}

/**
 * EIP-712 type description. This MUST match CREDENTIAL_TYPEHASH in CredentialRegistry.sol
 * byte-for-byte (same fields, same order, same type names) or signatures will not verify.
 */
export const credentialTypes = {
  Credential: [
    { name: "issuer", type: "address" },
    { name: "recipient", type: "address" },
    { name: "schemaId", type: "bytes32" },
    { name: "dataHash", type: "bytes32" },
    { name: "uri", type: "string" },
    { name: "issuedAt", type: "uint64" },
    { name: "expiresAt", type: "uint64" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

export const eip712Domain = (chainId: number, verifyingContract: Address) =>
  ({ name: "CertChain", version: "1", chainId, verifyingContract }) as const;

/** keccak256 of a human schema label - "BTECH_DEGREE_V1" -> bytes32 schemaId. */
export const schemaIdOf = (label: string): Hex => keccak256(stringToBytes(label.trim()));

/** keccak256 of the raw credential JSON - the on-chain commitment to off-chain data. */
export const dataHashOf = (json: string): Hex => keccak256(stringToBytes(json));

/** Client-side mirror of CredentialRegistry.credentialId() - must produce identical ids. */
export function credentialIdOf(credential: Credential): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "address" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" }, // keccak256(bytes(uri)) - dynamic types are hashed
        { type: "uint64" },
        { type: "uint64" },
        { type: "uint256" },
      ],
      [
        credential.issuer,
        credential.recipient,
        credential.schemaId,
        credential.dataHash,
        keccak256(stringToBytes(credential.uri)),
        credential.issuedAt,
        credential.expiresAt,
        credential.nonce,
      ],
    ),
  );
}

/**
 * The portable "credential file": everything a verifier needs, in one JSON blob the
 * student can email, print as a QR, or upload to the Verify tab. Chain state is only
 * consulted for issuer status + revocation.
 */
export interface CredentialFile {
  certchain: "credential-file-v1";
  chainId: number;
  verifyingContract: Address;
  schemaLabel: string;
  data: string; // the raw JSON the dataHash commits to
  credential: {
    issuer: Address;
    recipient: Address;
    schemaId: Hex;
    dataHash: Hex;
    uri: string;
    issuedAt: string; // bigints serialized as decimal strings
    expiresAt: string;
    nonce: string;
  };
  signature: Hex;
}

export function toCredentialFile(
  credential: Credential,
  signature: Hex,
  chainId: number,
  verifyingContract: Address,
  schemaLabel: string,
  data: string,
): CredentialFile {
  return {
    certchain: "credential-file-v1",
    chainId,
    verifyingContract,
    schemaLabel,
    data,
    credential: {
      ...credential,
      issuedAt: credential.issuedAt.toString(),
      expiresAt: credential.expiresAt.toString(),
      nonce: credential.nonce.toString(),
    },
    signature,
  };
}

export function fromCredentialFile(file: CredentialFile): { credential: Credential; signature: Hex } {
  const raw = file.credential;
  return {
    credential: {
      issuer: raw.issuer,
      recipient: raw.recipient,
      schemaId: raw.schemaId,
      dataHash: raw.dataHash,
      uri: raw.uri,
      issuedAt: BigInt(raw.issuedAt),
      expiresAt: BigInt(raw.expiresAt),
      nonce: BigInt(raw.nonce),
    },
    signature: file.signature,
  };
}

export function downloadJson(filename: string, value: unknown) {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

export const shortHex = (value: string, chars = 6) =>
  value.length > 2 * chars + 2 ? `${value.slice(0, chars + 2)}...${value.slice(-chars)}` : value;
