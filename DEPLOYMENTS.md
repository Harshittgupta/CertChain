# CertChain Deployment Ledger

## Sepolia Testnet Deployment

- **Chain ID:** 11155111 (Ethereum Sepolia Testnet)
- **Deployment Block:** 11342345
- **Deployer / Admin Address:** [0x6156ea0ba24ef78724698A85c74cC95455fACFb4](https://sepolia.etherscan.io/address/0x6156ea0ba24ef78724698A85c74cC95455fACFb4)

---

## Smart Contracts & Etherscan Verification

| Contract Name | Deployed Address | Source Verification |
|---|---|---|
| **IssuerRegistry** | [`0xA5A93F550FC33abD66147107e884D8331820a0E3`](https://sepolia.etherscan.io/address/0xA5A93F550FC33abD66147107e884D8331820a0E3) | [Verified on Etherscan](https://sepolia.etherscan.io/address/0xA5A93F550FC33abD66147107e884D8331820a0E3#code) |
| **CredentialRegistry** | [`0xD928b9FE38e42B29B725Bcf003F4B68c6db4cFCb`](https://sepolia.etherscan.io/address/0xD928b9FE38e42B29B725Bcf003F4B68c6db4cFCb) | [Verified on Etherscan](https://sepolia.etherscan.io/address/0xD928b9FE38e42B29B725Bcf003F4B68c6db4cFCb#code) |
| **SoulboundCertificate** | [`0x452DEFAfD0821FcBFD78A3a5a5F181d34A9e42Ea`](https://sepolia.etherscan.io/address/0x452DEFAfD0821FcBFD78A3a5a5F181d34A9e42Ea) | [Verified on Etherscan](https://sepolia.etherscan.io/address/0x452DEFAfD0821FcBFD78A3a5a5F181d34A9e42Ea#code) |

---

## Seeded Demo Credentials

### 1. Valid Credential (with Soulbound Certificate Minted)
- **Credential ID:** `0xeb781c69349019ac718b331e258cae7dee329cf36b86a6a141c58086977df6e0`
- **Issuer:** Demo University (`0x6156ea0ba24ef78724698A85c74cC95455fACFb4`)
- **Recipient:** `0x6156ea0ba24ef78724698A85c74cC95455fACFb4`
- **Verification Status:** `VALID`
- **Certificate Status:** Soulbound NFT Minted (Live SVG rendering)

### 2. Revoked Credential
- **Credential ID:** `0x667cd04972d3ea8f93614c454f15a0f1d66e6eae124080bdcd642219c9b4719d`
- **Issuer:** Demo University (`0x6156ea0ba24ef78724698A85c74cC95455fACFb4`)
- **Recipient:** `0x6156ea0ba24ef78724698A85c74cC95455fACFb4`
- **Verification Status:** `INVALID` (Reason: `revoked by issuer`)

---

## Hosted Application Environment

- **Live Deployed App:** [https://cert-chain-lake.vercel.app/](https://cert-chain-lake.vercel.app/)
- **Repository:** `https://github.com/Harshittgupta/CertChain.git`
- **Vercel Production Environment Variables:**
  - `VITE_ISSUER_REGISTRY` = `0xA5A93F550FC33abD66147107e884D8331820a0E3`
  - `VITE_CREDENTIAL_REGISTRY` = `0xD928b9FE38e42B29B725Bcf003F4B68c6db4cFCb`
  - `VITE_CERTIFICATE` = `0x452DEFAfD0821FcBFD78A3a5a5F181d34A9e42Ea`
  - `VITE_SEPOLIA_RPC_URL` = `https://eth-sepolia.g.alchemy.com/v2/...`
  - `VITE_DEPLOY_BLOCK` = `11342345`
  - `VITE_DEFAULT_CHAIN` = `sepolia`
