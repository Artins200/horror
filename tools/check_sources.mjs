// Offline verification: Lua syntax, binary/xml roundtrip and identical scripts.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";
import { readXml, readBinary } from "rbx-dom";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceFiles = [
  "src/ServerScriptService/NocturneServer.server.luau",
  "src/StarterPlayer/StarterPlayerScripts/NocturneClient.client.luau",
  "src/ReplicatedStorage/NocturneLayout.luau",
];
for (const filename of sourceFiles) {
  const source = fs.readFileSync(path.join(root, filename), "utf8");
  luaparse.parse(source, { luaVersion: "5.3", locations: true });
  console.log(`Lua syntax OK: ${filename}`);
}

function verify(place) {
  const scripts = place.descendants(place.rootRef).filter((x) =>
    ["Script", "LocalScript", "ModuleScript"].includes(x.className),
  );
  if (scripts.length !== 3) throw new Error(`Expected 3 embedded scripts; found ${scripts.length}`);
  for (const script of scripts) {
    const filename = script.className === "Script" ? sourceFiles[0]
      : script.className === "LocalScript" ? sourceFiles[1] : sourceFiles[2];
    const pathInPlace = place.fullPath(script.referent);
    if (script.className === "LocalScript" && !pathInPlace.includes("StarterPlayerScripts")) {
      throw new Error(`Client script not in StarterPlayerScripts: ${pathInPlace}`);
    }
    const embedded = place.getProperty(script.referent, "Source")?.String;
    if (embedded !== fs.readFileSync(path.join(root, filename), "utf8")) {
      throw new Error(`${filename} differs from the copy in ${pathInPlace}`);
    }
    if (script.className !== "ModuleScript" && place.getProperty(script.referent, "Disabled")?.Bool !== false) {
      throw new Error(`${script.name} is disabled`);
    }
  }
  return place.instanceCount;
}
const xml = readXml(fs.readFileSync(path.join(root, "Nocturne.rbxlx")));
const binary = readBinary(fs.readFileSync(path.join(root, "Nocturne.rbxl")));
const xmlCount = verify(xml);
const binaryCount = verify(binary);
if (xmlCount !== binaryCount) throw new Error("XML and binary have different instance counts");
console.log(`Studio serialization OK: ${xmlCount} instances, 2 running scripts and 1 layout module in both places`);
