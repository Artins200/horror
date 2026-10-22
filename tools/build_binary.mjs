// Optional binary export, using the open-source rbx-dom serializer.
// The .rbxlx from build_place.py can be opened in Studio without Node at all.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readXml, readBinary } from "rbx-dom";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const xmlPath = path.join(root, "Nocturne.rbxlx");
const output = path.join(root, "Nocturne.rbxl");
// Keep the uploaded filename as an alias so opening the old filename cannot
// accidentally launch the abandoned, open-sided endless staircase again.
const originalName = path.join(root, "13123.rbxl");
const releaseName = path.join(root, "Nocturne-v12.rbxl"); // v11 remains available for comparison
const dom = readXml(fs.readFileSync(xmlPath));

function assertSources(place) {
  const scripts = place.descendants(place.rootRef).filter((x) =>
    ["Script", "LocalScript", "ModuleScript"].includes(x.className),
  );
  if (scripts.length !== 4) throw new Error(`Expected four scripts; got ${scripts.length}`);
  for (const script of scripts) {
    const filename = script.className === "Script"
      ? "src/ServerScriptService/NocturneServer.server.luau"
      : script.name === "NocturneClient"
        ? "src/StarterPlayer/StarterPlayerScripts/NocturneClient.client.luau"
        : script.name === "NocturnePerspective"
          ? "src/StarterPlayer/StarterPlayerScripts/NocturnePerspective.client.luau"
          : "src/ReplicatedStorage/NocturneLayout.luau";
    const expected = fs.readFileSync(path.join(root, filename), "utf8");
    const source = place.getProperty(script.referent, "Source");
    if (source?.String !== expected) throw new Error(`Source mismatch for ${script.name}`);
    if (script.className !== "ModuleScript" && place.getProperty(script.referent, "Disabled")?.Bool !== false) {
      throw new Error(`${script.name} is disabled`);
    }
  }
}

assertSources(dom);
const binary = dom.toBinary({ compression: "zstd" });
const check = readBinary(binary);
assertSources(check);
if (check.instanceCount !== dom.instanceCount) throw new Error("Instances lost in binary conversion");
fs.writeFileSync(output, binary);
fs.writeFileSync(originalName, binary);
fs.writeFileSync(releaseName, binary);
console.log(`Built ${path.basename(output)}, ${path.basename(originalName)} and ${path.basename(releaseName)} (${binary.length.toLocaleString()} bytes; ${check.instanceCount} instances)`);
