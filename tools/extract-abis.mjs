// Regenerates frontend/src/abi/index.ts from Foundry build artifacts.
// Run from repo root AFTER `forge build`:  node tools/extract-abis.mjs
import fs from "node:fs";
const names = ["IssuerRegistry", "CredentialRegistry", "SoulboundCertificate"];
let out = "// Auto-generated from Foundry artifacts. Regenerate with: node tools/extract-abis.mjs\n";
for (const name of names) {
  const artifact = JSON.parse(fs.readFileSync(`contracts/out/${name}.sol/${name}.json`, "utf8"));
  const varName = name.charAt(0).toLowerCase() + name.slice(1) + "Abi";
  out += `export const ${varName} = ${JSON.stringify(artifact.abi, null, 2)} as const;\n\n`;
}
fs.mkdirSync("frontend/src/abi", { recursive: true });
fs.writeFileSync("frontend/src/abi/index.ts", out);
console.log("frontend/src/abi/index.ts regenerated");
