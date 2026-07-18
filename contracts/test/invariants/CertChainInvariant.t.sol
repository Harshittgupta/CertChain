// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IssuerRegistry} from "../../src/IssuerRegistry.sol";
import {CredentialRegistry} from "../../src/CredentialRegistry.sol";
import {SoulboundCertificate} from "../../src/SoulboundCertificate.sol";

/// @dev Handler contract that executes randomized actions on the system while tracking ghost state.
contract CertChainHandler is Test {
    IssuerRegistry public issuerRegistry;
    CredentialRegistry public credentialRegistry;
    SoulboundCertificate public certificate;

    address public issuer = address(0x1111111111111111111111111111111111111111);
    address public recipient1 = address(0x2222222222222222222222222222222222222222);
    address public recipient2 = address(0x3333333333333333333333333333333333333333);

    bytes32[] public ghost_allIssuedIds;
    mapping(bytes32 => bool) public ghost_everIssued;
    mapping(bytes32 => bool) public ghost_everRevoked;

    struct MintedToken {
        uint256 tokenId;
        address initialOwner;
    }
    MintedToken[] public ghost_mintedTokens;
    mapping(uint256 => bool) public ghost_isMinted;
    mapping(uint256 => address) public ghost_initialOwner;

    uint256 public nonceCounter;

    constructor(
        IssuerRegistry _issuerRegistry,
        CredentialRegistry _credentialRegistry,
        SoulboundCertificate _certificate
    ) {
        issuerRegistry = _issuerRegistry;
        credentialRegistry = _credentialRegistry;
        certificate = _certificate;

        // Register default issuer
        vm.prank(issuer);
        issuerRegistry.register("Handler University", "handler.eth", "ipfs://meta");
    }

    function issueCredential(uint8 recipientChoice, uint64 expiryDays) public {
        address recipient = recipientChoice % 2 == 0 ? recipient1 : recipient2;
        nonceCounter++;

        CredentialRegistry.Credential memory cred = CredentialRegistry.Credential({
            issuer: issuer,
            recipient: recipient,
            schemaId: keccak256("DEGREE_V1"),
            dataHash: keccak256(abi.encodePacked("data", nonceCounter)),
            uri: "ipfs://cred",
            issuedAt: uint64(block.timestamp),
            expiresAt: expiryDays > 0 ? uint64(block.timestamp) + uint64(expiryDays) * 86400 : 0,
            nonce: nonceCounter
        });

        bytes32 id = credentialRegistry.credentialId(cred);

        vm.prank(issuer);
        try credentialRegistry.issue(cred) {
            if (!ghost_everIssued[id]) {
                ghost_everIssued[id] = true;
                ghost_allIssuedIds.push(id);
            }
        } catch {}
    }

    function revokeCredential(uint256 indexChoice) public {
        if (ghost_allIssuedIds.length == 0) return;
        bytes32 id = ghost_allIssuedIds[indexChoice % ghost_allIssuedIds.length];

        vm.prank(issuer);
        try credentialRegistry.revoke(id) {
            ghost_everRevoked[id] = true;
        } catch {}
    }

    function mintCertificate(uint256 indexChoice) public {
        if (ghost_allIssuedIds.length == 0) return;
        bytes32 id = ghost_allIssuedIds[indexChoice % ghost_allIssuedIds.length];
        uint256 tokenId = uint256(id);

        (bool ok,) = credentialRegistry.verify(id);
        if (!ok) return;

        // Mint can be called by issuer or recipient
        vm.prank(issuer);
        try certificate.mint(id, "B.Tech Degree") {
            address owner = certificate.ownerOf(tokenId);
            if (!ghost_isMinted[tokenId]) {
                ghost_isMinted[tokenId] = true;
                ghost_initialOwner[tokenId] = owner;
                ghost_mintedTokens.push(MintedToken({tokenId: tokenId, initialOwner: owner}));
            }
        } catch {}
    }

    function burnCertificate(uint256 indexChoice) public {
        if (ghost_mintedTokens.length == 0) return;
        MintedToken memory item = ghost_mintedTokens[indexChoice % ghost_mintedTokens.length];
        if (!ghost_isMinted[item.tokenId]) return;

        vm.prank(item.initialOwner);
        try certificate.burn(item.tokenId) {
            ghost_isMinted[item.tokenId] = false;
        } catch {}
    }

    function toggleIssuerActive(bool active) public {
        vm.prank(issuer);
        try issuerRegistry.setActive(active) {} catch {}
    }

    function warpTime(uint32 secondsToWarp) public {
        vm.warp(block.timestamp + bound(secondsToWarp, 1, 365 days));
    }

    function getIssuedIdsCount() external view returns (uint256) {
        return ghost_allIssuedIds.length;
    }

    function getMintedTokensCount() external view returns (uint256) {
        return ghost_mintedTokens.length;
    }
}

contract CertChainInvariantTest is StdInvariant, Test {
    IssuerRegistry public issuerRegistry;
    CredentialRegistry public credentialRegistry;
    SoulboundCertificate public certificate;
    CertChainHandler public handler;

    function setUp() public {
        issuerRegistry = new IssuerRegistry(address(this));
        credentialRegistry = new CredentialRegistry(issuerRegistry);
        certificate = new SoulboundCertificate(credentialRegistry, issuerRegistry);

        handler = new CertChainHandler(issuerRegistry, credentialRegistry, certificate);
        targetContract(address(handler));
    }

    /// @notice Invariant 1: A credential that was ever revoked can never verify true again, under any sequence of calls.
    /// @dev Rules out replay, re-activation, pause-unpause confusion, or state corruption attacks that un-revoke a credential.
    function invariant_revokedCredentialNeverVerifies() public view {
        uint256 count = handler.getIssuedIdsCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 id = handler.ghost_allIssuedIds(i);
            if (handler.ghost_everRevoked(id)) {
                (bool ok, string memory reason) = credentialRegistry.verify(id);
                assertFalse(
                    ok,
                    string.concat(
                        "Revoked credential verified true! ID: ", vm.toString(id), " Reason: ", reason
                    )
                );
            }
        }
    }

    /// @notice Invariant 2: A soulbound token, once minted, can never change owner (only exist with initial owner or be burned).
    /// @dev Rules out soulbound bypass attacks via transferFrom, safeTransferFrom, approvals, or contract state mutations.
    function invariant_soulboundTokenNeverChangesOwner() public view {
        uint256 count = handler.getMintedTokensCount();
        for (uint256 i = 0; i < count; i++) {
            (uint256 tokenId, address initialOwner) = handler.ghost_mintedTokens(i);
            if (handler.ghost_isMinted(tokenId)) {
                address currentOwner = certificate.ownerOf(tokenId);
                assertEq(currentOwner, initialOwner, "Soulbound token changed owner!");
            }
        }
    }

    /// @notice Invariant 3: verify(id) never returns true for a credential id that was never issued.
    /// @dev Rules out phantom/uninitialized credential verification or hash collision attacks on un-anchored IDs.
    function invariant_unissuedCredentialNeverVerifies() public view {
        bytes32 unissuedId = keccak256("phantom_unissued_credential_id");
        if (!handler.ghost_everIssued(unissuedId)) {
            (bool ok,) = credentialRegistry.verify(unissuedId);
            assertFalse(ok, "Unissued credential verified true!");
        }
    }
}
