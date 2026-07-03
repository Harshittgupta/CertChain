// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {SoulboundCertificate} from "../src/SoulboundCertificate.sol";

contract SoulboundCertificateTest is Test {
    IssuerRegistry internal issuers;
    CredentialRegistry internal registry;
    SoulboundCertificate internal certificate;

    address internal admin = makeAddr("admin");
    address internal college = makeAddr("college");
    address internal student = makeAddr("student");
    address internal mallory = makeAddr("mallory");

    bytes32 internal id;

    function setUp() public {
        issuers = new IssuerRegistry(admin);
        registry = new CredentialRegistry(issuers);
        certificate = new SoulboundCertificate(registry, issuers);

        vm.prank(college);
        issuers.register("Test College", "", "");

        CredentialRegistry.Credential memory cred = CredentialRegistry.Credential({
            issuer: college,
            recipient: student,
            schemaId: keccak256("BTECH_DEGREE_V1"),
            dataHash: keccak256("data"),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: 0
        });
        vm.prank(college);
        id = registry.issue(cred);
    }

    function test_mint_byRecipient_landsInRecipientWallet() public {
        vm.prank(student);
        uint256 tokenId = certificate.mint(id, "Bachelor of Technology");
        assertEq(tokenId, uint256(id));
        assertEq(certificate.ownerOf(tokenId), student);
        assertEq(certificate.balanceOf(student), 1);
    }

    function test_mint_byIssuer_stillLandsInRecipientWallet() public {
        vm.prank(college);
        certificate.mint(id, "Bachelor of Technology");
        assertEq(certificate.ownerOf(uint256(id)), student);
    }

    function test_mint_revertsForStranger() public {
        vm.prank(mallory);
        vm.expectRevert(SoulboundCertificate.NotEligible.selector);
        certificate.mint(id, "Nope");
    }

    function test_mint_revertsForRevokedCredential() public {
        vm.prank(college);
        registry.revoke(id);

        vm.prank(student);
        vm.expectRevert(
            abi.encodeWithSelector(SoulboundCertificate.CredentialNotValid.selector, "revoked by issuer")
        );
        certificate.mint(id, "Too late");
    }

    function test_mint_revertsOnDoubleMint() public {
        vm.prank(student);
        certificate.mint(id, "First");
        vm.prank(college);
        vm.expectRevert(); // ERC721InvalidSender: token already minted
        certificate.mint(id, "Second");
    }

    function test_transfer_alwaysReverts_soulbound() public {
        vm.prank(student);
        uint256 tokenId = certificate.mint(id, "Degree");

        vm.prank(student);
        vm.expectRevert(SoulboundCertificate.Soulbound.selector);
        certificate.transferFrom(student, mallory, tokenId);

        // Even with approval, transfers are dead: _update blocks them at the root.
        vm.prank(student);
        certificate.approve(mallory, tokenId);
        vm.prank(mallory);
        vm.expectRevert(SoulboundCertificate.Soulbound.selector);
        certificate.transferFrom(student, mallory, tokenId);
    }

    function test_burn_byHolderOnly() public {
        vm.prank(student);
        uint256 tokenId = certificate.mint(id, "Degree");

        vm.prank(mallory);
        vm.expectRevert(SoulboundCertificate.NotEligible.selector);
        certificate.burn(tokenId);

        vm.prank(student);
        certificate.burn(tokenId);
        assertEq(certificate.balanceOf(student), 0);
    }

    function test_tokenURI_isOnchainDataUri_andTracksLiveStatus() public {
        vm.prank(student);
        uint256 tokenId = certificate.mint(id, "Bachelor of Technology");

        string memory uriBefore = certificate.tokenURI(tokenId);
        assertTrue(_startsWith(uriBefore, "data:application/json;base64,"));

        // Revoke the underlying credential: the SAME token's metadata must now differ
        // (the seal flips to REVOKED). The NFT cannot lie about its status.
        vm.prank(college);
        registry.revoke(id);
        string memory uriAfter = certificate.tokenURI(tokenId);
        assertTrue(keccak256(bytes(uriBefore)) != keccak256(bytes(uriAfter)));
    }

    function _startsWith(string memory value, string memory prefix) internal pure returns (bool) {
        bytes memory valueBytes = bytes(value);
        bytes memory prefixBytes = bytes(prefix);
        if (valueBytes.length < prefixBytes.length) return false;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (valueBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }
}
