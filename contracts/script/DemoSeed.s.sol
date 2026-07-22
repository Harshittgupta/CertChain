// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {SoulboundCertificate} from "../src/SoulboundCertificate.sol";

/// Seeds a fresh deployment with demo data so the frontend has something to show:
/// registers the deployer as "Demo University", issues one credential to DEMO_RECIPIENT
/// (defaults to the deployer itself), and mints its soulbound certificate.
///
///   export PRIVATE_KEY=0x...
///   export ISSUER_REGISTRY=0x... CREDENTIAL_REGISTRY=0x... CERTIFICATE=0x...
///   forge script script/DemoSeed.s.sol --rpc-url <RPC> --broadcast
contract DemoSeed is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address recipient = vm.envOr("DEMO_RECIPIENT", deployer);

        IssuerRegistry issuers = IssuerRegistry(vm.envAddress("ISSUER_REGISTRY"));
        CredentialRegistry credentials = CredentialRegistry(vm.envAddress("CREDENTIAL_REGISTRY"));
        SoulboundCertificate certificate = SoulboundCertificate(vm.envAddress("CERTIFICATE"));

        vm.startBroadcast(deployerKey);

        if (!issuers.isRegistered(deployer)) {
            issuers.register("Demo University", "demo-university.eth", "");
        }

        CredentialRegistry.Credential memory cred = CredentialRegistry.Credential({
            issuer: deployer,
            recipient: recipient,
            schemaId: keccak256(bytes("BTECH_DEGREE_V1")),
            dataHash: keccak256(
                bytes("{\"degree\":\"B.Tech\",\"branch\":\"Computer Engineering\",\"year\":2027}")
            ),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: 0
        });
        bytes32 validId = credentials.issue(cred);
        certificate.mint(validId, "Bachelor of Technology, Computer Engineering");

        // Seed a second credential and immediately revoke it for testing INVALID verification
        CredentialRegistry.Credential memory revokedCred = CredentialRegistry.Credential({
            issuer: deployer,
            recipient: recipient,
            schemaId: keccak256(bytes("DIPLOMA_V1")),
            dataHash: keccak256(bytes("{\"course\":\"Web3 Development\",\"status\":\"revoked\"}")),
            uri: "",
            issuedAt: uint64(block.timestamp),
            expiresAt: 0,
            nonce: 1
        });
        bytes32 revokedId = credentials.issue(revokedCred);
        credentials.revoke(revokedId);

        vm.stopBroadcast();

        console2.log("Valid demo credential id:");
        console2.logBytes32(validId);
        (bool okValid, string memory reasonValid) = credentials.verify(validId);
        console2.log("Valid verify() =>", okValid, reasonValid);

        console2.log("Revoked demo credential id:");
        console2.logBytes32(revokedId);
        (bool okRev, string memory reasonRev) = credentials.verify(revokedId);
        console2.log("Revoked verify() =>", okRev, reasonRev);
    }
}
