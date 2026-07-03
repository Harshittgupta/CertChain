// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IssuerRegistry} from "../src/IssuerRegistry.sol";

contract IssuerRegistryTest is Test {
    IssuerRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal college = makeAddr("college");
    address internal randomUser = makeAddr("randomUser");

    function setUp() public {
        registry = new IssuerRegistry(admin);
    }

    function test_register_storesProfileAndActivates() public {
        vm.prank(college);
        registry.register("KJ Somaiya College of Engineering", "kjsce.eth", "ipfs://issuer-doc");

        IssuerRegistry.Issuer memory issuer = registry.getIssuer(college);
        assertEq(issuer.name, "KJ Somaiya College of Engineering");
        assertEq(issuer.ensName, "kjsce.eth");
        assertTrue(issuer.active);
        assertFalse(issuer.verified);
        assertTrue(registry.isRegistered(college));
        assertTrue(registry.isActive(college));
    }

    function test_register_revertsOnDuplicate() public {
        vm.startPrank(college);
        registry.register("College", "", "");
        vm.expectRevert(IssuerRegistry.AlreadyRegistered.selector);
        registry.register("College again", "", "");
        vm.stopPrank();
    }

    function test_register_revertsOnEmptyName() public {
        vm.prank(college);
        vm.expectRevert(IssuerRegistry.EmptyName.selector);
        registry.register("", "", "");
    }

    function test_setActive_togglesAndGatesIsActive() public {
        vm.startPrank(college);
        registry.register("College", "", "");
        registry.setActive(false);
        vm.stopPrank();

        assertTrue(registry.isRegistered(college));
        assertFalse(registry.isActive(college));

        vm.prank(college);
        registry.setActive(true);
        assertTrue(registry.isActive(college));
    }

    function test_setActive_revertsForUnregistered() public {
        vm.prank(randomUser);
        vm.expectRevert(IssuerRegistry.NotRegistered.selector);
        registry.setActive(false);
    }

    function test_setVerified_onlyOwner() public {
        vm.prank(college);
        registry.register("College", "", "");

        vm.prank(randomUser);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        registry.setVerified(college, true);

        vm.prank(admin);
        registry.setVerified(college, true);
        assertTrue(registry.isVerified(college));
    }

    function test_setVerified_revertsForUnregisteredTarget() public {
        vm.prank(admin);
        vm.expectRevert(IssuerRegistry.NotRegistered.selector);
        registry.setVerified(randomUser, true);
    }

    function test_updateProfile_changesFieldsOnly() public {
        vm.startPrank(college);
        registry.register("Old name", "", "");
        registry.updateProfile("New name", "new.eth", "ipfs://new");
        vm.stopPrank();

        IssuerRegistry.Issuer memory issuer = registry.getIssuer(college);
        assertEq(issuer.name, "New name");
        assertEq(issuer.ensName, "new.eth");
        assertEq(issuer.metadataURI, "ipfs://new");
    }

    function test_getIssuer_revertsForUnregistered() public {
        vm.expectRevert(IssuerRegistry.NotRegistered.selector);
        registry.getIssuer(randomUser);
    }
}
