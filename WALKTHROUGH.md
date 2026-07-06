# CertChain Browser Walkthrough & Verification Log

Date: 2026-07-24
Environment: Local Anvil Chain (ID 31337) + Vite React Frontend with Dev Wallet Connector

## Overview

This walkthrough validates all primary end-to-end user flows in CertChain using an automated browser subagent and local Anvil chain deployment.

## Dev-Only Wallet Connector

To enable wallet interaction without manual MetaMask prompts in local test environments, a dev-only wallet connector was added:
- Gated behind `VITE_ENABLE_DEV_WALLET=true` in `frontend/.env`.
- Uses Anvil test key 0 (`0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`), mapping to `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`.
- Completely disabled when the flag is unset or false.

## Verification Checklist & Results

### 1. Verify Tab (Demo Credential)
- **Action**: Pasted the demo credential ID (`0x403786ddbd5270cf59c009dece3820f8085e5f07fb78ed2672eaecd9cee5e73b`) into the Verify tab.
- **Result**: Passed. Displays green `VALID` rubber-stamp graphic, correctly resolving the issuer name ("Demo University") and recipient address on-chain.

### 2. Issuer Desk (Registration & On-Chain Issuance)
- **Action**: Connected Dev Wallet as issuer (`0xf39Fd...`). Issued credential on-chain to recipient `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`.
- **Result**: Passed. Transaction confirmed in block and returned deterministic credential ID `0xd3b4f888eecfb2ce567eae092baf089a60723676f46eeaa65cf4dcac3f45b210`.

### 3. Sign-Only Flow (Off-Chain EIP-712 Attestation)
- **Action**: Form 02 -> "Sign only (no gas)". Generated signed EIP-712 attestation off-chain.
- **Result**: Passed. Downloaded JSON credential file (`certchain-credential-0xd3b4.json`), which verified successfully off-chain via `verifySigned`.

### 4. Merkle Batch Issuance
- **Action**: Form 03 -> Entered 3 batch entries for student recipients:
  - `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | {"name":"Student 1"}`
  - `0x70997970C51812dc3A010C7d01b50e0d17dc79C8 | {"name":"Student 2"}`
  - `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | {"name":"Student 3"}`
  Clicked "Commit batch root".
- **Result**: Passed. Merkle root was committed on-chain in 1 transaction, and proofs JSON was downloaded client-side (`certchain-batch-0x...json`).

### 5. My Credentials & Soulbound NFT Minting
- **Action**: Navigated to "My credentials" tab. Found on-chain credential issued to the connected wallet. Set title "B.Tech. Computer Engineering" and clicked "Mint soulbound certificate".
- **Result**: Passed. Soulbound token minted directly to holder wallet. Base64-decoded `tokenURI` rendered the dynamic on-chain SVG certificate showing green `VALID` seal.

### 6. Revocation & Dynamic On-Chain SVG Seal Update
- **Action**: Navigated to Issuer Desk -> Form 04 (Revoke). Entered credential ID `0xd3b4f88...` and clicked "Revoke credential". Re-checked in Verify tab and My credentials tab.
- **Result**: Passed. 
  - Verify tab instantly updated status to `INVALID / revoked by issuer` with a red stamp.
  - My credentials tab dynamically re-rendered the on-chain SVG certificate, automatically flipping the seal from green `VALID` to red `REVOKED`.

### 7. Visual & Mobile Layout Inspection
- **Result**: Passed. Paper-and-ink registrar design rendered cleanly. At narrow mobile widths (down to 360px), layout collapses gracefully into single-column cards with accessible touch targets and clear focus states.

## Summary of Fixes Made
- Added dev wallet mock connector support in `frontend/src/config.ts` gated by `VITE_ENABLE_DEV_WALLET`.
- Updated `frontend/src/components/Masthead.tsx` button formatting for dev wallet connectivity.
