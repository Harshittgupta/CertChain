// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IssuerRegistry} from "./IssuerRegistry.sol";

/// @title CredentialRegistry
/// @notice The heart of CertChain. Credentials are EIP-712 typed statements signed by an issuer.
///         They can be anchored on-chain (issue / issueWithSig), verified from a bare signature
///         without ever touching the chain (verifySigned), or issued in bulk as a merkle batch
///         where thousands of credentials cost one transaction (issueBatch + verifyInBatch).
///
/// The three issuance modes, and why each exists:
/// 1. `issue`         - issuer pays gas, credential is anchored on-chain. Simple, fully on-chain.
/// 2. `issueWithSig`  - issuer signs off-chain for free; ANYONE (e.g. the student) can submit the
///                      signature and pay the gas. This is the classic EIP-712 meta-transaction
///                      pattern: signature authority is separated from gas payment.
/// 3. `issueBatch`    - issuer publishes one merkle root covering N credentials. Each credential
///                      is later proven with a merkle proof. O(1) gas for the issuer, O(log N)
///                      proof size for the holder. This is how you certify 5,000 students cheaply.
///
/// Verification never requires the issuer's cooperation. That is the entire point.
contract CredentialRegistry is EIP712 {
    // ------------------------------------------------------------------ types

    enum Status {
        None, // never anchored on-chain (may still be valid as a bare signature!)
        Active,
        Revoked
    }

    struct Credential {
        address issuer; // who vouches for this statement
        address recipient; // who the statement is about
        bytes32 schemaId; // keccak256 of a human schema label, e.g. keccak256("BTECH_DEGREE_V1")
        bytes32 dataHash; // keccak256 of the off-chain credential JSON (name, grades, ...)
        string uri; // optional pointer to that JSON (ipfs:// | https:// | "")
        uint64 issuedAt; // issuer-declared issuance time
        uint64 expiresAt; // 0 = never expires
        uint256 nonce; // lets an issuer create otherwise-identical credentials as distinct records
    }

    /// @dev EIP-712 type string. Field order here MUST match the struct hash below, and the
    ///      frontend's `signTypedData` types must match this string byte-for-byte.
    bytes32 public constant CREDENTIAL_TYPEHASH = keccak256(
        "Credential(address issuer,address recipient,bytes32 schemaId,bytes32 dataHash,string uri,uint64 issuedAt,uint64 expiresAt,uint256 nonce)"
    );

    struct Batch {
        address issuer;
        uint64 issuedAt;
        bool revoked;
        string uri; // optional pointer describing the batch (e.g. "Class of 2027 diplomas")
    }

    // ------------------------------------------------------------------ state

    IssuerRegistry public immutable issuerRegistry;

    mapping(bytes32 credentialId => Status) public statusOf;
    mapping(bytes32 credentialId => Credential) private _credentials;

    mapping(bytes32 merkleRoot => Batch) public batches;
    /// @dev keccak256(root, leaf) => revoked. Lets an issuer revoke ONE credential inside a batch.
    mapping(bytes32 => bool) public batchLeafRevoked;

    // ------------------------------------------------------------------ events / errors

    event CredentialIssued(
        bytes32 indexed credentialId,
        address indexed issuer,
        address indexed recipient,
        bytes32 schemaId,
        bytes32 dataHash,
        string uri,
        uint64 issuedAt,
        uint64 expiresAt
    );
    event CredentialRevoked(bytes32 indexed credentialId, address indexed issuer);
    event BatchIssued(bytes32 indexed merkleRoot, address indexed issuer, string uri);
    event BatchRevoked(bytes32 indexed merkleRoot, address indexed issuer);
    event BatchLeafRevoked(bytes32 indexed merkleRoot, bytes32 indexed leaf, address indexed issuer);

    error NotActiveIssuer();
    error IssuerMismatch();
    error InvalidSignature();
    error AlreadyIssued();
    error UnknownCredential();
    error AlreadyRevoked();
    error NotCredentialIssuer();
    error BatchAlreadyExists();
    error UnknownBatch();
    error NotBatchIssuer();

    constructor(IssuerRegistry registry) EIP712("CertChain", "1") {
        issuerRegistry = registry;
    }

    // ------------------------------------------------------------------ hashing

    /// @notice Deterministic identifier of a credential: same content => same id, forever.
    ///         Dynamic types (the uri string) are hashed before encoding so the id is fixed-size.
    function credentialId(Credential memory cred) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                cred.issuer,
                cred.recipient,
                cred.schemaId,
                cred.dataHash,
                keccak256(bytes(cred.uri)),
                cred.issuedAt,
                cred.expiresAt,
                cred.nonce
            )
        );
    }

    /// @notice The EIP-712 digest an issuer actually signs. Domain-bound to this contract and
    ///         chain, so a signature for CertChain on Sepolia is useless anywhere else.
    function hashCredential(Credential memory cred) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CREDENTIAL_TYPEHASH,
                    cred.issuer,
                    cred.recipient,
                    cred.schemaId,
                    cred.dataHash,
                    keccak256(bytes(cred.uri)), // EIP-712: dynamic types are encoded as their hash
                    cred.issuedAt,
                    cred.expiresAt,
                    cred.nonce
                )
            )
        );
    }

    // ------------------------------------------------------------------ issuance

    /// @notice Direct on-chain issuance. Caller must BE the issuer named in the credential.
    function issue(Credential calldata cred) external returns (bytes32 id) {
        if (msg.sender != cred.issuer) revert IssuerMismatch();
        id = _issue(cred);
    }

    /// @notice Meta-transaction issuance: anyone may anchor a credential the issuer signed
    ///         off-chain. The issuer never spends gas; authority comes from the signature alone.
    function issueWithSig(Credential calldata cred, bytes calldata signature) external returns (bytes32 id) {
        address signer = ECDSA.recover(hashCredential(cred), signature);
        if (signer != cred.issuer) revert InvalidSignature();
        id = _issue(cred);
    }

    function _issue(Credential calldata cred) internal returns (bytes32 id) {
        if (!issuerRegistry.isActive(cred.issuer)) revert NotActiveIssuer();
        id = credentialId(cred);
        if (statusOf[id] != Status.None) revert AlreadyIssued();
        statusOf[id] = Status.Active;
        _credentials[id] = cred;
        emit CredentialIssued(
            id, cred.issuer, cred.recipient, cred.schemaId, cred.dataHash, cred.uri, cred.issuedAt, cred.expiresAt
        );
    }

    /// @notice Revocation is issuer-only and permanent. There is deliberately no "un-revoke":
    ///         a credential whose validity can flap is worse than no credential at all.
    function revoke(bytes32 id) external {
        Status status = statusOf[id];
        if (status == Status.None) revert UnknownCredential();
        if (status == Status.Revoked) revert AlreadyRevoked();
        if (_credentials[id].issuer != msg.sender) revert NotCredentialIssuer();
        statusOf[id] = Status.Revoked;
        emit CredentialRevoked(id, msg.sender);
    }

    // ------------------------------------------------------------------ verification

    function getCredential(bytes32 id) external view returns (Credential memory) {
        if (statusOf[id] == Status.None) revert UnknownCredential();
        return _credentials[id];
    }

    /// @notice Verify an anchored credential. Returns a reason string so UIs can show WHY a
    ///         credential failed, not just that it did.
    function verify(bytes32 id) public view returns (bool ok, string memory reason) {
        Status status = statusOf[id];
        if (status == Status.None) return (false, "unknown credential");
        if (status == Status.Revoked) return (false, "revoked by issuer");
        Credential storage cred = _credentials[id];
        if (!issuerRegistry.isActive(cred.issuer)) return (false, "issuer inactive or unregistered");
        if (cred.expiresAt != 0 && block.timestamp > cred.expiresAt) return (false, "expired");
        return (true, "valid");
    }

    /// @notice Verify a credential that may never have touched the chain: just the typed data
    ///         plus the issuer's signature. Revocation still applies (revoking the id kills both
    ///         the anchored record AND the floating signature - same id, same status slot).
    function verifySigned(Credential calldata cred, bytes calldata signature)
        external
        view
        returns (bool ok, string memory reason)
    {
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(hashCredential(cred), signature);
        if (err != ECDSA.RecoverError.NoError || signer != cred.issuer) return (false, "bad signature");
        if (!issuerRegistry.isActive(cred.issuer)) return (false, "issuer inactive or unregistered");
        if (statusOf[credentialId(cred)] == Status.Revoked) return (false, "revoked by issuer");
        if (cred.expiresAt != 0 && block.timestamp > cred.expiresAt) return (false, "expired");
        return (true, "valid");
    }

    // ------------------------------------------------------------------ merkle batches

    /// @notice Publish one root that commits to any number of credentials. The tree layout must
    ///         match `batchLeaf` (OpenZeppelin StandardMerkleTree with ["address","bytes32","bytes32"]).
    function issueBatch(bytes32 merkleRoot, string calldata uri) external {
        if (!issuerRegistry.isActive(msg.sender)) revert NotActiveIssuer();
        if (batches[merkleRoot].issuedAt != 0) revert BatchAlreadyExists();
        batches[merkleRoot] =
            Batch({issuer: msg.sender, issuedAt: uint64(block.timestamp), revoked: false, uri: uri});
        emit BatchIssued(merkleRoot, msg.sender, uri);
    }

    function revokeBatch(bytes32 merkleRoot) external {
        Batch storage batch = batches[merkleRoot];
        if (batch.issuedAt == 0) revert UnknownBatch();
        if (batch.issuer != msg.sender) revert NotBatchIssuer();
        if (batch.revoked) revert AlreadyRevoked();
        batch.revoked = true;
        emit BatchRevoked(merkleRoot, msg.sender);
    }

    /// @notice Revoke a single credential inside a batch without nuking the whole batch.
    function revokeBatchLeaf(bytes32 merkleRoot, bytes32 leaf) external {
        Batch storage batch = batches[merkleRoot];
        if (batch.issuedAt == 0) revert UnknownBatch();
        if (batch.issuer != msg.sender) revert NotBatchIssuer();
        bytes32 key = keccak256(abi.encodePacked(merkleRoot, leaf));
        if (batchLeafRevoked[key]) revert AlreadyRevoked();
        batchLeafRevoked[key] = true;
        emit BatchLeafRevoked(merkleRoot, leaf, msg.sender);
    }

    /// @notice Leaf encoding, double-hashed to match OpenZeppelin's StandardMerkleTree JS library
    ///         (the double hash prevents second-preimage attacks on the tree).
    function batchLeaf(address recipient, bytes32 schemaId, bytes32 dataHash) public pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(recipient, schemaId, dataHash))));
    }

    function verifyInBatch(
        bytes32 merkleRoot,
        address recipient,
        bytes32 schemaId,
        bytes32 dataHash,
        bytes32[] calldata proof
    ) external view returns (bool ok, string memory reason) {
        Batch storage batch = batches[merkleRoot];
        if (batch.issuedAt == 0) return (false, "unknown batch");
        if (batch.revoked) return (false, "batch revoked by issuer");
        if (!issuerRegistry.isActive(batch.issuer)) return (false, "issuer inactive or unregistered");
        bytes32 leaf = batchLeaf(recipient, schemaId, dataHash);
        if (batchLeafRevoked[keccak256(abi.encodePacked(merkleRoot, leaf))]) {
            return (false, "revoked by issuer");
        }
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) return (false, "invalid merkle proof");
        return (true, "valid");
    }

    // ------------------------------------------------------------------ misc

    /// @notice Expose the EIP-712 domain separator for frontends and debugging.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
