import { describe, expect, test } from "vitest";
import { hashTypedData, type Address, type Hex } from "viem";
import {
  credentialIdOf,
  credentialTypes,
  eip712Domain,
  type Credential,
} from "../src/lib/credential";
import fixtures from "./fixtures/credential_fixtures.json";

describe("EIP-712 Mirror Differential Test", () => {
  test.each(fixtures)(
    "matches Solidity hashing for fixture: $uri",
    (fixture) => {
      const cred: Credential = {
        issuer: fixture.issuer as Address,
        recipient: fixture.recipient as Address,
        schemaId: fixture.schemaId as Hex,
        dataHash: fixture.dataHash as Hex,
        uri: fixture.uri,
        issuedAt: BigInt(fixture.issuedAt),
        expiresAt: BigInt(fixture.expiresAt),
        nonce: BigInt(fixture.nonce),
      };

      // 1. Assert credentialIdOf matches Solidity credentialId()
      const credId = credentialIdOf(cred);
      expect(credId).toBe(fixture.expectedCredentialId);

      // 2. Assert viem hashTypedData matches Solidity hashCredential() (_hashTypedDataV4)
      const typedDataHash = hashTypedData({
        domain: eip712Domain(
          fixture.chainId,
          fixture.verifyingContract as Address
        ),
        types: credentialTypes,
        primaryType: "Credential",
        message: cred,
      });
      expect(typedDataHash).toBe(fixture.expectedTypedDataHash);
    }
  );
});
