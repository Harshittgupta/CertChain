// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";
import {CredentialRegistry} from "../src/CredentialRegistry.sol";
import {SoulboundCertificate} from "../src/SoulboundCertificate.sol";

/// Usage (Sepolia):
///   export PRIVATE_KEY=0x...        # a throwaway key holding Sepolia test ETH
///   export SEPOLIA_RPC_URL=https...  # free Alchemy/Infura/public endpoint
///   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
///
/// Usage (local anvil):
///   anvil                                    # terminal 1
///   export PRIVATE_KEY=<anvil key 0>         # terminal 2
///   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract Deploy is Script {
    function run()
        external
        returns (IssuerRegistry issuers, CredentialRegistry credentials, SoulboundCertificate certificate)
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        issuers = new IssuerRegistry(deployer);
        credentials = new CredentialRegistry(issuers);
        certificate = new SoulboundCertificate(credentials, issuers);
        vm.stopBroadcast();

        console2.log("IssuerRegistry:      ", address(issuers));
        console2.log("CredentialRegistry:  ", address(credentials));
        console2.log("SoulboundCertificate:", address(certificate));
        console2.log("Deployer/admin:      ", deployer);
    }
}
