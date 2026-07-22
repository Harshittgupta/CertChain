# Sepolia Testnet Verification Walkthrough

This document records the end-to-end verification results of CertChain deployed on Sepolia testnet.

---

## 1. Read-Only Visitor Verification (No Wallet Connected)

- **Test:** Paste seeded valid credential ID into the **Verify** tab without connecting a browser wallet.
- **Seeded ID:** `0xeb781c69349019ac718b331e258cae7dee329cf36b86a6a141c58086977df6e0`
- **Result:** Read contract query succeeded using configured RPC transport. Displayed green `VALID` rubber-stamp seal, issuer name `Demo University`, recipient address, and issue date.
- **Test (Revoked Credential):** Paste seeded revoked credential ID `0x667cd04972d3ea8f93614c454f15a0f1d66e6eae124080bdcd642219c9b4719d`.
- **Result:** Displayed red `INVALID` rubber-stamp seal with explicit reason `revoked by issuer`.

---

## 2. Network Handling & Switch Prompt

- **Test:** Connect wallet while configured to Ethereum Mainnet or alternative chain ID.
- **Result:** Masthead displayed warning banner: `⚠️ You are connected to unsupported chain (id 1). Please switch to Sepolia.` along with a `Switch to Sepolia` button.
- **Action:** Clicking `Switch to Sepolia` triggered wallet network switch request and switched active chain to Sepolia (Chain ID 11155111).

---

## 3. Real Latency & Pending Transaction Feedback

- **Test:** Issue credential and mint soulbound certificate on Sepolia.
- **Observation:** Unlike local Anvil which confirms instantly in 0ms, Sepolia block time is ~12 seconds.
- **Feedback UI:**
  1. Action buttons immediately set busy/disabled state to prevent double-submits.
  2. Displayed pending note: `Transaction submitted (0x...). Waiting for block confirmation... View on Etherscan`.
  3. Upon block inclusion, toast updated with block confirmation message and clickable Sepolia Etherscan transaction link.

---

## 4. Event Scanning & On-Chain SVG Rendering

- **Test:** Open **My Credentials** tab on Sepolia.
- **Scanning:** Logs queried from deployment block `11342345` to `latest`. Automatically falls back to 50,000 block window chunking if public RPC query caps log range.
- **Result:** Discovered seeded credential `0xeb78...`, decoded base64 metadata, and rendered live on-chain SVG certificate seal.

---

## 5. Dev Wallet Production Guard Verification

- **Test:** Inspect production JavaScript bundle built in `frontend/dist/`.
- **Grep check:** Executed `grep_search` for `0xac0974` across all production output files in `dist/`.
- **Result:** `0` matches found. Dev wallet connector and Anvil private key string are completely excluded from production build artifacts.
