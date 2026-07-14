# CertChain Security Notes & Slither Analysis Triage

Date: 2026-07-24  
Analyzer: Slither v0.11.5  
Target: `contracts/` (`IssuerRegistry.sol`, `CredentialRegistry.sol`, `SoulboundCertificate.sol`)

---

## Executive Summary

Static analysis with Slither identified 12 findings in the core source contracts (and additional findings in vendored OpenZeppelin dependencies). All findings have been audited and triaged below into real issues, false positives, and accepted risks.

---

## Detailed Detector Triage

### 1. `incorrect-equality` (Medium)
- **Locations**:
  - `IssuerRegistry.sol#42`: `_issuers[msg.sender].registeredAt == 0` in `onlyRegistered()`
  - `IssuerRegistry.sol#105`: `_issuers[issuer].registeredAt == 0` in `getIssuer()`
- **Triage**: **False Positive**. `registeredAt` is a block timestamp populated upon registration (`uint64(block.timestamp)`). Since `block.timestamp > 0` on EVM chains, `0` serves as the explicit sentinel value for an unregistered address.

### 2. `unused-return` (Medium)
- **Locations**:
  - `SoulboundCertificate.sol#80`: `(bool ok,) = credentialRegistry.verify(credentialId)`
  - `CredentialRegistry.sol#205`: `(address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(...)`
- **Triage**: **Accepted Design Intent**.
  - In `SoulboundCertificate.tokenURI`, only the boolean status `ok` is required to select between the green `VALID` or red `REVOKED` seal on the generated on-chain SVG certificate; the detailed text reason is deliberately omitted.
  - In `CredentialRegistry.verifySigned`, OpenZeppelin's `tryRecover` returns a 3-tuple `(signer, err, errorParameter)`. The code checks `err != ECDSA.RecoverError.NoError`, making `errorParameter` intentionally unused.

### 3. `reentrancy-events` (Low)
- **Location**: `SoulboundCertificate.sol#54-55` in `mint()`
- **Triage**: **Accepted Risk**. `_safeMint` invokes `onERC721Received` if the recipient is a contract. State variable `_titles[tokenId]` is set prior to `_safeMint`, and `_safeMint` itself enforces uniqueness via `_requireUnowned(tokenId)`, preventing duplicate mint reentrancy. Emitting `CertificateMinted` after `_safeMint` ensures event emission only occurs on completed mints.

### 4. `timestamp` (Low / Informational)
- **Locations**:
  - `CredentialRegistry.sol#193, 209`: `cred.expiresAt != 0 && block.timestamp > cred.expiresAt`
  - `CredentialRegistry.sol#219`: `batches[merkleRoot].issuedAt != 0`
  - `IssuerRegistry.sol#49, 91, 105`: `registeredAt` comparisons
- **Triage**: **Accepted Risk**. `block.timestamp` is used for coarse-grained expiration dates (spanning days to years) and registration checks. Minor miner timestamp drift (a few seconds) presents no security risk for credential validity.

### 5. `pragma` (Informational)
- **Locations**: Pragma versions in `src/` (`^0.8.24`) vs vendored OpenZeppelin (`^0.8.20`).
- **Triage**: **Accepted Configuration**. Compiler version is strictly pinned to `0.8.30` in `foundry.toml`, ensuring deterministic builds across all dependencies.

---

## Conclusion

No unhandled critical or high severity vulnerabilities exist in the core smart contracts. All 12 findings represent intentional patterns or false positives.
