// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CredentialRegistry} from "./CredentialRegistry.sol";
import {IssuerRegistry} from "./IssuerRegistry.sol";

/// @title SoulboundCertificate
/// @notice An optional, visual layer on top of the CredentialRegistry: any VALID anchored
///         credential can be minted as a non-transferable ("soulbound") NFT in the recipient's
///         wallet. The certificate image is generated fully on-chain as SVG - no IPFS, no server.
///
/// Design notes for learners:
/// - tokenId == uint256(credentialId). One credential, one possible certificate, no counters.
/// - Soulbound is enforced in `_update`, the single choke point every transfer/mint/burn passes
///   through in OpenZeppelin's ERC721 v5. Allow from==0 (mint) and to==0 (burn), refuse the rest.
/// - `tokenURI` reads LIVE state: if the underlying credential is revoked after minting, the
///   certificate image itself flips to a red REVOKED stamp. The NFT cannot lie about its status.
contract SoulboundCertificate is ERC721 {
    using Strings for uint256;
    using Strings for address;

    CredentialRegistry public immutable credentialRegistry;
    IssuerRegistry public immutable issuerRegistry;

    /// @dev Human-readable certificate title, chosen at mint ("Bachelor of Technology, Computer Engineering").
    mapping(uint256 tokenId => string) private _titles;

    event CertificateMinted(uint256 indexed tokenId, address indexed recipient, string title);

    error Soulbound();
    error NotEligible();
    error CredentialNotValid(string reason);

    constructor(CredentialRegistry credentials, IssuerRegistry issuers)
        ERC721("CertChain Certificate", "CERT")
    {
        credentialRegistry = credentials;
        issuerRegistry = issuers;
    }

    /// @notice Mint the certificate for an anchored, currently-valid credential. Only the
    ///         credential's recipient or its issuer may trigger the mint; it always lands in the
    ///         recipient's wallet regardless of who calls.
    function mint(bytes32 credentialId, string calldata title) external returns (uint256 tokenId) {
        (bool ok, string memory reason) = credentialRegistry.verify(credentialId);
        if (!ok) revert CredentialNotValid(reason);
        CredentialRegistry.Credential memory cred = credentialRegistry.getCredential(credentialId);
        if (msg.sender != cred.recipient && msg.sender != cred.issuer) revert NotEligible();
        tokenId = uint256(credentialId);
        _titles[tokenId] = title;
        _safeMint(cred.recipient, tokenId); // reverts with ERC721InvalidSender if already minted
        emit CertificateMinted(tokenId, cred.recipient, title);
    }

    /// @notice Holders may burn their own certificate (the underlying credential is untouched).
    function burn(uint256 tokenId) external {
        if (msg.sender != ownerOf(tokenId)) revert NotEligible();
        delete _titles[tokenId];
        _burn(tokenId);
    }

    /// @dev The soulbound enforcement point. Every mint, burn, and transfer in OZ v5 flows
    ///      through _update; blocking wallet-to-wallet moves here blocks them everywhere
    ///      (transferFrom, safeTransferFrom, approvals are useless, the lot).
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    // ------------------------------------------------------------------ on-chain metadata

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        bytes32 credentialId = bytes32(tokenId);
        CredentialRegistry.Credential memory cred = credentialRegistry.getCredential(credentialId);
        (bool ok,) = credentialRegistry.verify(credentialId);

        string memory issuerName = issuerRegistry.isRegistered(cred.issuer)
            ? issuerRegistry.getIssuer(cred.issuer).name
            : "Unregistered issuer";

        string memory json = string.concat(
            '{"name":"',
            _titles[tokenId],
            '","description":"CertChain on-chain certificate. Verifiable forever against the CredentialRegistry.",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(_svg(tokenId, issuerName, cred.recipient, ok))),
            '","attributes":[',
            '{"trait_type":"Issuer","value":"',
            issuerName,
            '"},{"trait_type":"Status","value":"',
            ok ? "Valid" : "Revoked or invalid",
            '"},{"trait_type":"Issued at","value":',
            uint256(cred.issuedAt).toString(),
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev A restrained "engraved certificate" card: paper ground, ledger rules, ink text and a
    ///      status seal. Split into helpers to keep the stack shallow.
    function _svg(uint256 tokenId, string memory issuerName, address recipient, bool valid)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">',
            '<rect width="600" height="400" fill="#FAF9F4"/>',
            '<rect x="14" y="14" width="572" height="372" fill="none" stroke="#1E5C46" stroke-width="2"/>',
            '<rect x="22" y="22" width="556" height="356" fill="none" stroke="#1E5C46" stroke-width="0.75"/>',
            '<text x="300" y="70" text-anchor="middle" font-family="Georgia,serif" font-size="15" letter-spacing="6" fill="#1E5C46">CERTCHAIN REGISTRY</text>',
            '<line x1="80" y1="90" x2="520" y2="90" stroke="#D9D6CB" stroke-width="1"/>',
            _svgBody(tokenId, issuerName, recipient),
            _svgSeal(valid),
            "</svg>"
        );
    }

    function _svgBody(uint256 tokenId, string memory issuerName, address recipient)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '<text x="300" y="150" text-anchor="middle" font-family="Georgia,serif" font-size="26" fill="#1C2321">',
            _escape(issuerName),
            "</text>",
            '<text x="300" y="185" text-anchor="middle" font-family="Georgia,serif" font-size="14" font-style="italic" fill="#1C2321">hereby certifies the holder of</text>',
            '<text x="300" y="215" text-anchor="middle" font-family="monospace" font-size="14" fill="#1E5C46">',
            recipient.toHexString(),
            "</text>",
            '<text x="300" y="345" text-anchor="middle" font-family="monospace" font-size="9" fill="#8A8676">credential ',
            tokenId.toHexString(32),
            "</text>"
        );
    }

    function _svgSeal(bool valid) internal pure returns (string memory) {
        string memory ink = valid ? "#1E5C46" : "#8C2B2B";
        return string.concat(
            '<g transform="rotate(-8 300 275)">',
            '<circle cx="300" cy="275" r="46" fill="none" stroke="',
            ink,
            '" stroke-width="2.5"/><circle cx="300" cy="275" r="38" fill="none" stroke="',
            ink,
            '" stroke-width="1"/>',
            '<text x="300" y="281" text-anchor="middle" font-family="Georgia,serif" font-size="16" letter-spacing="3" fill="',
            ink,
            '">',
            valid ? "VALID" : "REVOKED",
            "</text></g>"
        );
    }

    /// @dev Minimal escaping so issuer names cannot break the SVG/JSON. Angle brackets, quotes
    ///      and ampersands are replaced with spaces - crude but safe for a learning project.
    function _escape(string memory input) internal pure returns (string memory) {
        bytes memory raw = bytes(input);
        for (uint256 i = 0; i < raw.length; i++) {
            bytes1 char = raw[i];
            if (char == "<" || char == ">" || char == '"' || char == "&" || char == "'") {
                raw[i] = " ";
            }
        }
        return string(raw);
    }
}
