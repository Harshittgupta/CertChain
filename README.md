# CertChain

An on-chain credential and attestation protocol on Ethereum. Institutions register as issuers and publish credentials (degrees, certificates, memberships) as cryptographically signed attestations. Anyone in the world can verify a credential in seconds without contacting the issuer, and no one, including the platform, can forge or tamper with a record. Trust that comes from mathematics instead of middlemen.

Built with Foundry, OpenZeppelin v5, wagmi, and viem. Runs entirely on free infrastructure: local anvil or the Sepolia testnet.

## What is inside

```
certchain/
  contracts/            Foundry project
    src/
      IssuerRegistry.sol        who can issue (permissionless registry + optional endorsement)
      CredentialRegistry.sol    EIP-712 attestations, revocation, merkle batch issuance
      SoulboundCertificate.sol  non-transferable ERC-721 with fully on-chain SVG art
    test/                       39 tests: forgery, tampering, revocation, expiry,
                                merkle proofs, soulbound enforcement, fuzzing
    script/                     Deploy.s.sol and DemoSeed.s.sol
  frontend/             Vite + React + TypeScript + wagmi + viem
    src/components/             Verify tab, Issuer desk, My credentials
    src/lib/credential.ts       client-side EIP-712 hashing that mirrors the contract
  tools/extract-abis.mjs        regenerates frontend ABIs after contract changes
```

## Quickstart: full local demo in about two minutes

Prerequisites: [Foundry](https://book.getfoundry.sh/getting-started/installation) (`curl -L https://foundry.paradigm.xyz | bash` then `foundryup`), Node 18+, and a browser wallet like MetaMask.

Terminal 1: start a local chain.

```bash
anvil
```

Terminal 2: deploy and seed demo data. The private key below is anvil's well-known test key 0 (never use it anywhere real).

```bash
cd contracts
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

export ISSUER_REGISTRY=0x5FbDB2315678afecb367f032d93F642f64180aa3
export CREDENTIAL_REGISTRY=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
export CERTIFICATE=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
forge script script/DemoSeed.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

On a fresh anvil chain those three addresses are deterministic, and they are also the frontend defaults, so no configuration is needed. The seed script prints a demo credential id: copy it.

Terminal 3: run the frontend.

```bash
cd frontend
npm install
npm run dev
```

In MetaMask: add a network with RPC `http://127.0.0.1:8545` and chain id `31337`, and import the private key above as an account. Then open the app, paste the demo credential id into the Verify tab, and watch the stamp come down. Issue yourself more credentials from the Issuer desk, mint the soulbound certificate from My credentials, revoke it, and watch the on-chain SVG flip to REVOKED.

Run the test suite, invariant tests, and coverage reports:

```bash
cd contracts && forge test -vv
forge coverage
```

### Test Coverage Summary

- **`IssuerRegistry.sol`**: 100% Lines (31/31), 100% Functions (9/9)
- **`SoulboundCertificate.sol`**: 97.56% Lines (40/41), 100% Functions (9/9)
- **`CredentialRegistry.sol`**: 94.94% Lines (75/79), 93.75% Functions (15/16)
- **Overall Core Contracts**: ~96.5% Line Coverage across core protocol contracts.

## Deploy to Sepolia (still free)

1. Get Sepolia test ETH from a faucet (Google Cloud, Alchemy, or QuickNode faucets all work).
2. Get a free RPC endpoint from Alchemy, Infura, or QuickNode, or use a public one.
3. Use a throwaway private key that holds only test ETH. Never paste a real key into anything.

```bash
cd contracts
cp .env.example .env        # fill PRIVATE_KEY and SEPOLIA_RPC_URL, then:
source .env
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

Optionally verify source on Etherscan by appending `--verify --etherscan-api-key $ETHERSCAN_API_KEY` (free key from etherscan.io).

Point the frontend at your deployment:

```bash
cd frontend
cp .env.example .env        # fill the three VITE_ addresses, RPC url, and deploy block
npm run dev                 # or npm run build for a static bundle you can host on Vercel
```

Setting `VITE_DEPLOY_BLOCK` to the block you deployed in keeps the My-credentials event scan fast on public RPCs.

## Architecture

```
            registers, one time                    signs EIP-712 credentials
  College ─────────────────────► IssuerRegistry ◄────────────────────────────┐
                                      ▲                                      │
                                      │ isActive(issuer)?                    │
                                      │                                      │
  Verifier ──── verify(id) ────► CredentialRegistry ◄──── issue / issueWithSig / issueBatch
                                      ▲
                                      │ verify(id) must pass
                                      │
  Student ──── mint(id) ───────► SoulboundCertificate ──► on-chain SVG in the wallet
```

Three issuance modes, three cost profiles:

| Mode | Who pays gas | On-chain footprint | Use case |
|---|---|---|---|
| `issue()` | Issuer | Full record | Single important credential |
| `issueWithSig()` | Anyone (often the student) | Full record | Issuer signs for free off-chain, holder anchors it |
| `issueBatch()` | Issuer, once | One 32-byte merkle root | Certify 5,000 students in one transaction |

And a fourth path that touches the chain only to read: `verifySigned()` checks a bare signed credential that was never anchored at all. The signature travels as a small JSON "credential file" the student can email or print as a QR code. Revocation still works, because revoking the credential id kills the anchored record and the floating signature at once.

Key mechanisms worth studying in the code:

- EIP-712 typed signatures (`CredentialRegistry.hashCredential`, mirrored in `frontend/src/lib/credential.ts`). The domain separator binds every signature to this contract and chain, so a CertChain signature cannot be replayed elsewhere.
- Meta-transactions (`issueWithSig`): separating signature authority from gas payment.
- Merkle batches using OpenZeppelin's StandardMerkleTree double-hash leaf format, with per-leaf revocation.
- Soulbound enforcement in a single choke point (`SoulboundCertificate._update`), which is why approvals cannot bypass it.
- Fully on-chain metadata: `tokenURI` builds base64 JSON and SVG at read time from live state, so a revoked credential's certificate image flips to a red REVOKED seal by itself.

## Security properties the tests actually check

Forged signatures are rejected. Tampering with any signed field invalidates the signature. Only the named issuer can issue directly, only the credential's issuer can revoke, revocation is permanent, expired credentials fail verification, credentials from paused or unregistered issuers fail verification, invalid merkle proofs fail, revoked leaves fail while their siblings survive, soulbound tokens cannot move even with approvals, and two fuzz tests hammer the id and signature logic with random inputs. Read `contracts/test/` with a coffee: the negative tests teach more than the positive ones.

Known simplifications, on purpose: revocation reasons are not stored, the schema registry is just a hash of a label, `_escape` in the SVG is crude, and there is no upgradeability. Each is a deliberate scope cut for a learning project, and each is a good interview talking point.

## Extension ideas (good Tokyo material)

- Rebuild the credential layer on EAS (the Ethereum Attestation Service) instead of a custom registry, and keep only the UX. At a hackathon, building on the sponsor's rails scores better than reinventing them.
- ZK selective disclosure: prove "CGPA above 8" without revealing the CGPA, using the dataHash as commitment.
- Real ENS integration: resolve issuer ENS names instead of storing display strings.
- An indexer (Ponder or a subgraph) so My-credentials does not scan raw logs.
- Schema registry contract with typed fields instead of free-form JSON.

## A note on using this for ETHGlobal

ETHGlobal requires projects to be built at the event. This repo is practice material: read it, break it, re-type it from memory, extend it. The judges will ask you why `_update` and not `transferFrom`, why the leaf is double-hashed, why the domain separator matters. If you can answer those from your own head, this project has done its job.

MIT licensed. Built as a pre-hackathon learning project.
