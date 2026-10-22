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
  "src/StarterPlayer/StarterPlayerScripts/NocturnePerspective.client.luau",
  "src/ReplicatedStorage/NocturneLayout.luau",
];
for (const filename of [...sourceFiles, "tests/StudioSmokeTest.server.luau",
  "tests/StudioAvatarCheck.client.luau", "tests/StudioItemCheck.client.luau",
  "tests/StudioEchoCheck.server.luau"]) {
  const source = fs.readFileSync(path.join(root, filename), "utf8");
  luaparse.parse(source, { luaVersion: "5.3", locations: true });
  console.log(`Lua syntax OK: ${filename}`);
}

function verify(place) {
  const instances = place.descendants(place.rootRef);
  const workspace = instances.find((x) => x.className === "Workspace");
  if (Math.abs((place.getProperty(workspace.referent, "Gravity")?.Float32 ?? 0) - 196.2) > 0.01
    || place.getProperty(workspace.referent, "StreamingEnabled")?.Bool !== false) {
    throw new Error("Gravity/streaming settings lost during place serialization");
  }
  const previewFloor = instances.find((x) => x.name === "Herringbone floor");
  if (!previewFloor || place.getProperty(previewFloor.referent, "Anchored")?.Bool !== true
    || place.getProperty(previewFloor.referent, "CanCollide")?.Bool !== true) {
    throw new Error("The editor preview floor must have anchored collision");
  }
  const spawn = instances.find((x) => x.className === "SpawnLocation" && x.name === "PreviewSpawn");
  const starter = instances.find((x) => x.className === "StarterPlayer");
  if (!spawn || !starter || place.getProperty(spawn.referent, "CanCollide")?.Bool !== true
    || place.getProperty(starter.referent, "CameraMode")?.Enum !== 1
    || place.getProperty(starter.referent, "EnableMouseLockOption")?.Bool !== false
    || Math.abs((place.getProperty(starter.referent, "CameraMinZoomDistance")?.Float32 ?? 0) - 0.5) > 0.01) {
    throw new Error("Native spawn and physically attached first-person camera were not serialized");
  }
  const scripts = instances.filter((x) =>
    ["Script", "LocalScript", "ModuleScript"].includes(x.className),
  );
  if (scripts.length !== 4) throw new Error(`Expected 4 embedded scripts; found ${scripts.length}`);
  for (const script of scripts) {
    const filename = script.className === "Script" ? sourceFiles[0]
      : script.name === "NocturneClient" ? sourceFiles[1]
        : script.name === "NocturnePerspective" ? sourceFiles[2] : sourceFiles[3];
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
console.log(`Studio serialization OK: ${xmlCount} instances, 3 running scripts and 1 layout module in both places`);
