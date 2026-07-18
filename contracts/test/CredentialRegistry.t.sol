// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";

contract CredentialRegistryTest is Test {
    IssuerRegistry internal issuers;
    CredentialRegistry internal registry;

    // Issuer with a known private key so we can produce real EIP-712 signatures.
    uint256 internal collegePk = 0xA11CE;
    address internal college;
    uint256 internal malloryPk = 0xBAD;
    address internal mallory; // attacker

    address internal admin = makeAddr("admin");
    address internal student = makeAddr("student");

    bytes32 internal constant SCHEMA = keccak256("BTECH_DEGREE_V1");

    function setUp() public {
        college = vm.addr(collegePk);
        mallory = vm.addr(malloryPk);

        issuers = new IssuerRegistry(admin);
        registry = new CredentialRegistry(issuers);

        vm.prank(college);
        issuers.register("Test College", "college.eth", "");
    }

    function _credential(address recipient, uint256 nonce)
        internal
        view
        returns (CredentialRegistry.Credential memory)
    {
        return CredentialRegistry.Credential({
            issuer: college,
            recipient: recipient,
            schemaId: SCHEMA,
            dataHash: keccak256("{\"degree\":\"B.Tech\",\"branch\":\"Computer Engineering\"}"),
            uri: "ipfs://credential-json",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: nonce
        });
    }

    function _sign(uint256 pk, CredentialRegistry.Credential memory cred)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, registry.hashCredential(cred));
        return abi.encodePacked(r, s, v);
    }

    // ------------------------------------------------------------ direct issuance

    function test_issue_direct_success() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        vm.prank(college);
        bytes32 id = registry.issue(cred);

        assertEq(uint8(registry.statusOf(id)), uint8(CredentialRegistry.Status.Active));
        (bool ok, string memory reason) = registry.verify(id);
        assertTrue(ok);
        assertEq(reason, "valid");
        assertEq(registry.getCredential(id).recipient, student);
    }

    function test_issue_revertsIfCallerIsNotNamedIssuer() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        vm.prank(mallory);
        vm.expectRevert(CredentialRegistry.IssuerMismatch.selector);
        registry.issue(cred);
    }

    function test_issue_revertsIfIssuerNotRegistered() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        cred.issuer = mallory; // mallory never registered
        vm.prank(mallory);
        vm.expectRevert(CredentialRegistry.NotActiveIssuer.selector);
        registry.issue(cred);
    }

    function test_issue_revertsIfIssuerDeactivated() public {
        vm.prank(college);
        issuers.setActive(false);

        CredentialRegistry.Credential memory cred = _credential(student, 0);
        vm.prank(college);
        vm.expectRevert(CredentialRegistry.NotActiveIssuer.selector);
        registry.issue(cred);
    }

    function test_issue_revertsOnDuplicate() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        vm.startPrank(college);
        registry.issue(cred);
        vm.expectRevert(CredentialRegistry.AlreadyIssued.selector);
        registry.issue(cred);
        vm.stopPrank();
    }

    function test_issue_sameContentDifferentNonceAreDistinct() public {
        vm.startPrank(college);
        bytes32 first = registry.issue(_credential(student, 0));
        bytes32 second = registry.issue(_credential(student, 1));
        vm.stopPrank();
        assertTrue(first != second);
    }

    // ------------------------------------------------------------ signature issuance

    function test_issueWithSig_anyoneCanSubmitIssuerSignature() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        bytes memory signature = _sign(collegePk, cred);

        // The STUDENT submits and pays gas; the college only ever signed off-chain.
        vm.prank(student);
        bytes32 id = registry.issueWithSig(cred, signature);

        (bool ok,) = registry.verify(id);
        assertTrue(ok);
    }

    function test_issueWithSig_rejectsForgedSignature() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        bytes memory forged = _sign(malloryPk, cred); // mallory signs, claims to be college

        vm.prank(mallory);
        vm.expectRevert(CredentialRegistry.InvalidSignature.selector);
        registry.issueWithSig(cred, forged);
    }

    function test_issueWithSig_rejectsTamperedContent() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        bytes memory signature = _sign(collegePk, cred);

        cred.recipient = mallory; // tamper AFTER signing: signature no longer matches
        vm.prank(mallory);
        vm.expectRevert(CredentialRegistry.InvalidSignature.selector);
        registry.issueWithSig(cred, signature);
    }

    // ------------------------------------------------------------ revocation

    function test_revoke_byIssuer_flipsVerification() public {
        vm.startPrank(college);
        bytes32 id = registry.issue(_credential(student, 0));
        registry.revoke(id);
        vm.stopPrank();

        (bool ok, string memory reason) = registry.verify(id);
        assertFalse(ok);
        assertEq(reason, "revoked by issuer");
    }

    function test_revoke_revertsForNonIssuer() public {
        vm.prank(college);
        bytes32 id = registry.issue(_credential(student, 0));

        vm.prank(mallory);
        vm.expectRevert(CredentialRegistry.NotCredentialIssuer.selector);
        registry.revoke(id);
    }

    function test_revoke_revertsForUnknownAndDouble() public {
        vm.prank(college);
        vm.expectRevert(CredentialRegistry.UnknownCredential.selector);
        registry.revoke(bytes32(uint256(123)));

        vm.startPrank(college);
        bytes32 id = registry.issue(_credential(student, 0));
        registry.revoke(id);
        vm.expectRevert(CredentialRegistry.AlreadyRevoked.selector);
        registry.revoke(id);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ verification edge cases

    function test_verify_unknownCredential() public view {
        (bool ok, string memory reason) = registry.verify(bytes32(uint256(1)));
        assertFalse(ok);
        assertEq(reason, "unknown credential");
    }

    function test_verify_failsWhileIssuerPaused_recoversAfter() public {
        vm.prank(college);
        bytes32 id = registry.issue(_credential(student, 0));

        vm.prank(college);
        issuers.setActive(false);
        (bool ok, string memory reason) = registry.verify(id);
        assertFalse(ok);
        assertEq(reason, "issuer inactive or unregistered");

        vm.prank(college);
        issuers.setActive(true);
        (ok,) = registry.verify(id);
        assertTrue(ok);
    }

    function test_verify_expiry() public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        cred.expiresAt = uint64(block.timestamp + 30 days);
        vm.prank(college);
        bytes32 id = registry.issue(cred);

        (bool ok,) = registry.verify(id);
        assertTrue(ok);

        vm.warp(block.timestamp + 31 days);
        string memory reason;
        (ok, reason) = registry.verify(id);
        assertFalse(ok);
        assertEq(reason, "expired");
    }

    function test_verifySigned_pureSignatureFlow_neverAnchored() public {
        CredentialRegistry.Credential memory cred = _credential(student, 7);
        bytes memory signature = _sign(collegePk, cred);

        // Never issued on-chain, still verifiable:
        (bool ok, string memory reason) = registry.verifySigned(cred, signature);
        assertTrue(ok);
        assertEq(reason, "valid");

        // Bad signature fails:
        (ok, reason) = registry.verifySigned(cred, _sign(malloryPk, cred));
        assertFalse(ok);
        assertEq(reason, "bad signature");
    }

    function test_verifySigned_respectsRevocationOfFloatingCredential() public {
        CredentialRegistry.Credential memory cred = _credential(student, 7);
        bytes memory signature = _sign(collegePk, cred);

        // Issuer anchors + revokes the same content; the floating signature dies with it.
        vm.startPrank(college);
        bytes32 id = registry.issue(cred);
        registry.revoke(id);
        vm.stopPrank();

        (bool ok, string memory reason) = registry.verifySigned(cred, signature);
        assertFalse(ok);
        assertEq(reason, "revoked by issuer");
    }

    // ------------------------------------------------------------ merkle batches

    /// @dev Commutative pair hash, identical to OpenZeppelin MerkleProof's internal ordering.
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function test_batch_issueVerifyAndRevocations() public {
        address studentB = makeAddr("studentB");
        bytes32 dataA = keccak256("marks-json-A");
        bytes32 dataB = keccak256("marks-json-B");

        bytes32 leafA = registry.batchLeaf(student, SCHEMA, dataA);
        bytes32 leafB = registry.batchLeaf(studentB, SCHEMA, dataB);
        bytes32 root = _hashPair(leafA, leafB);

        vm.prank(college);
        registry.issueBatch(root, "Class of 2027");

        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = leafB;

        (bool ok, string memory reason) = registry.verifyInBatch(root, student, SCHEMA, dataA, proofA);
        assertTrue(ok);
        assertEq(reason, "valid");

        // Wrong data => invalid proof
        (ok, reason) = registry.verifyInBatch(root, student, SCHEMA, keccak256("forged"), proofA);
        assertFalse(ok);
        assertEq(reason, "invalid merkle proof");

        // Revoke ONE leaf: A dies, B lives
        vm.prank(college);
        registry.revokeBatchLeaf(root, leafA);
        (ok, reason) = registry.verifyInBatch(root, student, SCHEMA, dataA, proofA);
        assertFalse(ok);
        assertEq(reason, "revoked by issuer");

        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = leafA;
        (ok,) = registry.verifyInBatch(root, studentB, SCHEMA, dataB, proofB);
        assertTrue(ok);

        // Revoke whole batch: everything dies
        vm.prank(college);
        registry.revokeBatch(root);
        (ok, reason) = registry.verifyInBatch(root, studentB, SCHEMA, dataB, proofB);
        assertFalse(ok);
        assertEq(reason, "batch revoked by issuer");
    }

    function test_batch_fourLeafTreeWithTwoStepProof() public {
        address[4] memory recipients = [student, makeAddr("s2"), makeAddr("s3"), makeAddr("s4")];
        bytes32[4] memory leaves;
        for (uint256 i = 0; i < 4; i++) {
            leaves[i] = registry.batchLeaf(recipients[i], SCHEMA, keccak256(abi.encode("marks", i)));
        }
        bytes32 left = _hashPair(leaves[0], leaves[1]);
        bytes32 right = _hashPair(leaves[2], leaves[3]);
        bytes32 root = _hashPair(left, right);

        vm.prank(college);
        registry.issueBatch(root, "");

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = right;
        (bool ok,) = registry.verifyInBatch(
            root, recipients[0], SCHEMA, keccak256(abi.encode("marks", uint256(0))), proof
        );
        assertTrue(ok);
    }

    function test_batch_gates() public {
        bytes32 root = keccak256("root");

        vm.prank(mallory); // not an issuer
        vm.expectRevert(CredentialRegistry.NotActiveIssuer.selector);
        registry.issueBatch(root, "");

        vm.prank(college);
        registry.issueBatch(root, "");

        vm.prank(college);
        vm.expectRevert(CredentialRegistry.BatchAlreadyExists.selector);
        registry.issueBatch(root, "");

        vm.prank(mallory);
        vm.expectRevert(CredentialRegistry.NotBatchIssuer.selector);
        registry.revokeBatch(root);

        vm.prank(college);
        vm.expectRevert(CredentialRegistry.UnknownBatch.selector);
        registry.revokeBatch(keccak256("no-such-root"));
    }

    // ------------------------------------------------------------ fuzz

    /// @notice For ANY recipient/data/nonce, issue -> verify roundtrips, and the id is stable.
    function testFuzz_issueVerifyRoundtrip(address recipient, bytes32 dataHash, uint256 nonce) public {
        CredentialRegistry.Credential memory cred = _credential(recipient, nonce);
        cred.dataHash = dataHash;

        vm.prank(college);
        bytes32 id = registry.issue(cred);

        assertEq(id, registry.credentialId(cred));
        (bool ok,) = registry.verify(id);
        assertTrue(ok);
    }

    /// @notice A signature over one credential NEVER validates a different credential.
    function testFuzz_signatureDoesNotTransfer(bytes32 otherData) public {
        CredentialRegistry.Credential memory cred = _credential(student, 0);
        vm.assume(otherData != cred.dataHash);
        bytes memory signature = _sign(collegePk, cred);

        CredentialRegistry.Credential memory other = cred;
        other.dataHash = otherData;
        (bool ok, string memory reason) = registry.verifySigned(other, signature);
        assertFalse(ok);
        assertEq(reason, "bad signature");
    }
}
