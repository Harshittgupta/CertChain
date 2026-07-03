// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title IssuerRegistry
/// @notice An open, permissionless registry of credential issuers (colleges, companies, hackathons...).
///
/// Design notes for learners:
/// - Anyone can register as an issuer. Trust does NOT come from being in this list; it comes from
///   (a) which address signed a credential and (b) whether verifiers choose to trust that address.
/// - `verified` is an optional endorsement flag set by the protocol owner (think "blue tick").
///   Verifiers may require it, or ignore it entirely. Keeping registration permissionless while
///   layering optional endorsements on top is a common web3 pattern (compare: ENS + curated lists).
/// - Issuers can pause themselves (`setActive(false)`) if a key is compromised. Downstream
///   contracts (CredentialRegistry) refuse to accept new credentials from inactive issuers, and
///   verification of existing credentials fails while the issuer is paused.
contract IssuerRegistry is Ownable {
    struct Issuer {
        string name; // "KJ Somaiya College of Engineering"
        string ensName; // "kjsce.eth" - display convenience only, not proof of ENS ownership
        string metadataURI; // ipfs:// or https:// document describing the issuer
        uint64 registeredAt; // block timestamp of registration; 0 means "not registered"
        bool active; // issuer-controlled kill switch
        bool verified; // protocol-owner endorsement, optional to rely on
    }

    mapping(address => Issuer) private _issuers;

    event IssuerRegistered(address indexed issuer, string name, string ensName, string metadataURI);
    event IssuerProfileUpdated(address indexed issuer, string name, string ensName, string metadataURI);
    event IssuerActiveSet(address indexed issuer, bool active);
    event IssuerVerifiedSet(address indexed issuer, bool verified);

    error AlreadyRegistered();
    error NotRegistered();
    error EmptyName();

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier onlyRegistered() {
        if (_issuers[msg.sender].registeredAt == 0) revert NotRegistered();
        _;
    }

    /// @notice Register the calling address as an issuer. One profile per address, forever.
    function register(string calldata name, string calldata ensName, string calldata metadataURI) external {
        if (bytes(name).length == 0) revert EmptyName();
        if (_issuers[msg.sender].registeredAt != 0) revert AlreadyRegistered();
        _issuers[msg.sender] = Issuer({
            name: name,
            ensName: ensName,
            metadataURI: metadataURI,
            registeredAt: uint64(block.timestamp),
            active: true,
            verified: false
        });
        emit IssuerRegistered(msg.sender, name, ensName, metadataURI);
    }

    /// @notice Update display fields. The address (the actual root of trust) never changes.
    function updateProfile(string calldata name, string calldata ensName, string calldata metadataURI)
        external
        onlyRegistered
    {
        if (bytes(name).length == 0) revert EmptyName();
        Issuer storage issuer = _issuers[msg.sender];
        issuer.name = name;
        issuer.ensName = ensName;
        issuer.metadataURI = metadataURI;
        emit IssuerProfileUpdated(msg.sender, name, ensName, metadataURI);
    }

    /// @notice Issuer-controlled circuit breaker. Deactivate if your key leaks; verification of
    ///         your credentials fails while inactive, which is exactly what you want in a breach.
    function setActive(bool active) external onlyRegistered {
        _issuers[msg.sender].active = active;
        emit IssuerActiveSet(msg.sender, active);
    }

    /// @notice Protocol-owner endorsement flag. Purely additive trust signal.
    function setVerified(address issuer, bool verified) external onlyOwner {
        if (_issuers[issuer].registeredAt == 0) revert NotRegistered();
        _issuers[issuer].verified = verified;
        emit IssuerVerifiedSet(issuer, verified);
    }

    // ---------------------------------------------------------------- views

    function isRegistered(address issuer) public view returns (bool) {
        return _issuers[issuer].registeredAt != 0;
    }

    /// @notice The check downstream contracts care about: registered AND not self-paused.
    function isActive(address issuer) public view returns (bool) {
        Issuer storage record = _issuers[issuer];
        return record.registeredAt != 0 && record.active;
    }

    function isVerified(address issuer) external view returns (bool) {
        return _issuers[issuer].verified;
    }

    function getIssuer(address issuer) external view returns (Issuer memory) {
        if (_issuers[issuer].registeredAt == 0) revert NotRegistered();
        return _issuers[issuer];
    }
}
