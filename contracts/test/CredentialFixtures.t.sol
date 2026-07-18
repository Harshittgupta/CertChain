// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";

contract CredentialFixturesTest is Test {
    IssuerRegistry public issuerRegistry;
    CredentialRegistry public credentialRegistry;

    function setUp() public {
        issuerRegistry = new IssuerRegistry(address(this));
        credentialRegistry = new CredentialRegistry(issuerRegistry);
    }

    function _buildJsonItem(CredentialRegistry.Credential memory cred) internal view returns (string memory) {
        bytes32 credId = credentialRegistry.credentialId(cred);
        bytes32 typedHash = credentialRegistry.hashCredential(cred);

        string memory part1 = string.concat(
            "  {\n",
            '    "issuer": "',
            vm.toString(cred.issuer),
            '",\n',
            '    "recipient": "',
            vm.toString(cred.recipient),
            '",\n',
            '    "schemaId": "',
            vm.toString(cred.schemaId),
            '",\n',
            '    "dataHash": "',
            vm.toString(cred.dataHash),
            '",\n'
        );

        string memory part2 = string.concat(
            '    "uri": "',
            cred.uri,
            '",\n',
            '    "issuedAt": "',
            vm.toString(cred.issuedAt),
            '",\n',
            '    "expiresAt": "',
            vm.toString(cred.expiresAt),
            '",\n',
            '    "nonce": "',
            vm.toString(cred.nonce),
            '",\n'
        );

        string memory part3 = string.concat(
            '    "chainId": 31337,\n',
            '    "verifyingContract": "',
            vm.toString(address(credentialRegistry)),
            '",\n',
            '    "expectedCredentialId": "',
            vm.toString(credId),
            '",\n',
            '    "expectedTypedDataHash": "',
            vm.toString(typedHash),
            '"\n  }'
        );

        return string.concat(part1, part2, part3);
    }

    function test_generateCredentialFixtures() public {
        CredentialRegistry.Credential[] memory creds = new CredentialRegistry.Credential[](5);

        // 1. Standard Credential
        creds[0] = CredentialRegistry.Credential({
            issuer: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            recipient: address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8),
            schemaId: keccak256("BTECH_DEGREE_V1"),
            dataHash: keccak256('{"degree":"B.Tech","branch":"CE"}'),
            uri: "ipfs://QmStandard123",
            issuedAt: 1700000000,
            expiresAt: 1800000000,
            nonce: 1
        });

        // 2. Zero Expiry
        creds[1] = CredentialRegistry.Credential({
            issuer: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            recipient: address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC),
            schemaId: keccak256("CERTIFICATE_V1"),
            dataHash: keccak256('{"course":"Web3"}'),
            uri: "ipfs://QmZeroExpiry456",
            issuedAt: 1700000000,
            expiresAt: 0,
            nonce: 42
        });

        // 3. Empty URI
        creds[2] = CredentialRegistry.Credential({
            issuer: address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8),
            recipient: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            schemaId: keccak256("MEMBERSHIP_V1"),
            dataHash: keccak256('{"role":"member"}'),
            uri: "",
            issuedAt: 1710000000,
            expiresAt: 1720000000,
            nonce: 0
        });

        // 4. Max Uint Values
        creds[3] = CredentialRegistry.Credential({
            issuer: address(0x90F79bf6eB2C4f870365E785982e18401e142851),
            recipient: address(0x15D34Aa5453880096437271111708F331D9236d4),
            schemaId: keccak256("MAX_VALS_V1"),
            dataHash: keccak256('{"max":true}'),
            uri: "https://certchain.org/max",
            issuedAt: type(uint64).max,
            expiresAt: type(uint64).max,
            nonce: type(uint256).max
        });

        // 5. Unicode in URI
        creds[4] = CredentialRegistry.Credential({
            issuer: address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            recipient: address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8),
            schemaId: keccak256("UNICODE_V1"),
            dataHash: keccak256('{"name":"Alice"}'),
            uri: unicode"ipfs://QmUnicode/📜/学位.json",
            issuedAt: 1700000000,
            expiresAt: 1900000000,
            nonce: 999
        });

        string memory json = "[\n";
        for (uint256 i = 0; i < creds.length; i++) {
            json = string.concat(json, _buildJsonItem(creds[i]), i < creds.length - 1 ? ",\n" : "\n");
        }
        json = string.concat(json, "]\n");

        vm.writeFile("test/fixtures/credential_fixtures.json", json);
        vm.writeFile("../frontend/test/fixtures/credential_fixtures.json", json);
    }
}
