"""Offline checks for the committed Studio place; run with `npm test`."""

from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


class PlaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document = ET.parse(ROOT / "Nocturne.rbxlx")
        cls.xml = cls.document.getroot()
        cls.server = (ROOT / "src/ServerScriptService/NocturneServer.server.luau").read_text(encoding="utf-8")
        cls.client = (ROOT / "src/StarterPlayer/StarterPlayerScripts/NocturneClient.client.luau").read_text(encoding="utf-8")
        cls.perspective = (ROOT / "src/StarterPlayer/StarterPlayerScripts/NocturnePerspective.client.luau").read_text(encoding="utf-8")
        cls.layout = (ROOT / "src/ReplicatedStorage/NocturneLayout.luau").read_text(encoding="utf-8")

    def named(self, class_name, name):
        matches = [item for item in self.xml.findall(".//Item") if item.get("class") == class_name
                   and item.findtext("Properties/string[@name='Name']") == name]
        self.assertEqual(len(matches), 1, (class_name, name, len(matches)))
        return matches[0]

    def test_xml_place_has_playable_services(self):
        self.assertEqual(self.xml.tag, "roblox")
        for cls in ("Workspace", "Lighting", "ServerScriptService", "StarterPlayer",
                    "ReplicatedStorage", "SoundService"):
            self.named(cls, cls)
        workspace = self.named("Workspace", "Workspace")
        self.assertAlmostEqual(float(workspace.findtext("Properties/float[@name='Gravity']")), 196.2)
        self.assertEqual(workspace.findtext("Properties/bool[@name='StreamingEnabled']"), "false")
        self.assertEqual(len(self.xml.findall(".//Item[@class='SpawnLocation']")), 1)
        self.assertEqual(len(self.xml.findall(".//Item[@class='Camera']")), 1)

    def test_scripts_are_embedded_unmodified_and_enabled(self):
        for class_name, name, expected in (("Script", "NocturneServer", self.server),
                                            ("LocalScript", "NocturneClient", self.client),
                                            ("LocalScript", "NocturnePerspective", self.perspective),
                                            ("ModuleScript", "NocturneLayout", self.layout)):
            script = self.named(class_name, name)
            self.assertEqual(script.findtext("Properties/ProtectedString[@name='Source']"), expected)
            if class_name != "ModuleScript":
                self.assertEqual(script.findtext("Properties/bool[@name='Disabled']"), "false")
        self.assertIsNotNone(self.xml.find(".//Item[@class='ServerScriptService']/Item[@class='Script']"))
        self.assertIsNotNone(self.xml.find(
            ".//Item[@class='StarterPlayer']/Item[@class='StarterPlayerScripts']/Item[@class='LocalScript']"))
        self.assertIsNotNone(self.xml.find(
            ".//Item[@class='ReplicatedStorage']/Item[@class='ModuleScript']"))
        starter = self.named("StarterPlayer", "StarterPlayer")
        self.assertEqual(starter.findtext("Properties/token[@name='CameraMode']"), "1")
        self.assertEqual(float(starter.findtext("Properties/float[@name='CameraMinZoomDistance']")), 0.5)
        self.assertEqual(float(starter.findtext("Properties/float[@name='CameraMaxZoomDistance']")), 0.5)
        self.assertEqual(starter.findtext("Properties/bool[@name='EnableMouseLockOption']"), "false")

    def test_editor_preview_has_door_wardrobes_and_lights(self):
        preview = self.named("Model", "StudioPreview")
        parts = preview.findall(".//Item[@class='Part']")
        self.assertGreaterEqual(len(parts), 60)
        names = [part.findtext("Properties/string[@name='Name']") for part in parts]
        self.assertIn("Door 001", names)
        floor = [part for part in parts
                 if part.findtext("Properties/string[@name='Name']") == "Herringbone floor"]
        self.assertEqual(len(floor), 1)
        self.assertEqual(floor[0].findtext("Properties/bool[@name='CanCollide']"), "true")
        self.assertEqual(floor[0].findtext("Properties/bool[@name='Anchored']"), "true")
        spawn = self.named("SpawnLocation", "PreviewSpawn")
        self.assertEqual(spawn.findtext("Properties/bool[@name='CanCollide']"), "true")
        (sx, sy, sz), (x, y, z) = self.box(spawn)
        self.assertAlmostEqual(y + sy / 2, 0)
        self.assertAlmostEqual(z, 10)
        self.assertEqual(names.count("Wardrobe back"), 2)
        self.assertEqual(names.count("Lower wardrobe panel"), 4)
        self.assertEqual(names.count("Spaced wardrobe louvre"), 28)
        self.assertEqual(names.count("Sliding drawer front"), 3)
        self.assertGreaterEqual(len(preview.findall(".//Item[@class='PointLight']")), 4)
        self.assertIsNotNone(self.named("Atmosphere", "CorridorHaze"))

    @staticmethod
    def box(part):
        props = part.find("Properties")
        size = props.find("Vector3[@name='Size']")
        cf = props.find("CoordinateFrame[@name='CFrame']")
        return tuple(float(size.findtext(axis)) for axis in ("X", "Y", "Z")), tuple(
            float(cf.findtext(axis)) for axis in ("X", "Y", "Z"))

    def test_preview_stairs_are_enclosed_supported_and_connect_to_upper_floor(self):
        stair = self.named("Model", "PreviewEnclosedStair")
        parts = stair.findall(".//Item[@class='Part']")
        named = lambda text: [p for p in parts if p.findtext("Properties/string[@name='Name']") == text]
        treads = sorted(named("Solid stair tread"), key=lambda p: self.box(p)[1][2])
        ceilings = sorted(named("Stepped enclosed ceiling"), key=lambda p: self.box(p)[1][2])
        self.assertEqual(len(treads), 16)
        self.assertEqual(len(ceilings), 16)
        self.assertEqual(len(named("Solid enclosed stair flank")), 2)
        self.assertEqual(len(named("Lower stair landing")), 1)
        self.assertEqual(len(named("Upper stair landing")), 1)
        self.assertEqual(len(named("Solid wall below upper exit")), 1)
        self.assertEqual(len(named("Door 002 / upper landing")), 1)
        self.assertAlmostEqual(self.box(named("Door 002 / upper landing")[0])[1][1] - 5.1, 12)
        self.assertEqual(len(named("Stair wardrobe back")), 2)
        prev_end = 44.0
        prev_height = 0.0
        sequence = named("Lower stair landing") + treads + named("Upper stair landing")
        for part in sequence:
            self.assertEqual(part.findtext("Properties/bool[@name='CanCollide']"), "true")
            self.assertEqual(part.findtext("Properties/bool[@name='Anchored']"), "true")
            (sx, sy, sz), (_, y, z) = self.box(part)
            near, far = z - sz / 2, z + sz / 2
            walk_y = y + sy / 2
            self.assertLessEqual(near, prev_end + 0.03, "gap in stair floor")
            self.assertLessEqual(walk_y - prev_height, 0.75 + 1e-5, "unclimbable step")
            self.assertGreaterEqual(walk_y, prev_height - 1e-5, "route must only ascend")
            prev_end, prev_height = far, walk_y
        self.assertGreaterEqual(prev_end, 88)
        self.assertAlmostEqual(prev_height, 12)
        for flank in named("Solid enclosed stair flank"):
            (sx, sy, sz), (x, y, z) = self.box(flank)
            self.assertAlmostEqual(abs(x) - sx / 2, 6.5)  # no walkable outside ledge
            self.assertAlmostEqual(abs(x) + sx / 2, 15)
            self.assertGreaterEqual(sy, 28)
            self.assertLessEqual(z - sz / 2, 44)
            self.assertGreaterEqual(z + sz / 2, 88)
        # No open-sky strip at a step: a roof above every tread and both landings.
        self.assertEqual(len(named("Sealed ceiling riser")), 16)
        self.assertEqual(len(named("Lower enclosed ceiling")), 1)
        self.assertEqual(len(named("Upper enclosed ceiling")), 1)

    def test_hundred_door_boundaries_and_hiding_are_server_authoritative(self):
        self.assertIn("Doors = 100", self.server)
        self.assertIn("index >= CONFIG.Doors", self.server)
        self.assertIn("index ~= state.opened", self.server)
        self.assertIn("makeCloset(room, -1", self.server)
        self.assertIn("makeCloset(room, 1", self.server)
        self.assertIn("if root and not state.hidden[player]", self.server)
        self.assertIn("state.opened == CONFIG.Doors", self.server)
        self.assertIn("function() startRush(room, mySession)", self.server)
        self.assertIn("function() startBlind(room, mySession)", self.server)
        self.assertIn("function() startMoth(room, mySession)", self.server)
        self.assertIn("RunService:BindToRenderStep", self.client)
        self.assertIn("Enum.CameraType.Custom", self.client)
        self.assertIn("Enum.CameraType.Scriptable", self.client)  # only while hiding

    def test_character_camera_does_not_override_roblox_physics(self):
        self.assertIn("Workspace.Gravity = 196.2", self.server)
        self.assertIn("root.Anchored = false", self.server)
        self.assertIn("humanoid.AutoRotate = true", self.server)
        self.assertIn("hum.AutoRotate = true", self.server)
        self.assertIn('spawn.CanCollide = true', self.server)
        self.assertIn('state.world:SetAttribute("CameraBuild", "NativeFirstPerson-v6")', self.server)
        self.assertIn('player.CameraMode = Enum.CameraMode.LockFirstPerson', self.client)
        self.assertIn('camera.CameraSubject = humanoid', self.client)
        self.assertIn('camera.CameraType = Enum.CameraType.Custom', self.client)
        self.assertNotIn('Enum.CameraMode.Classic', self.client)
        self.assertIn('AvatarArmsFirstPerson', self.perspective)
        self.assertIn('player.CameraMode = Enum.CameraMode.LockFirstPerson', self.perspective)
        self.assertIn('camera.CameraSubject = humanoid', self.perspective)
        self.assertNotIn('Opening title card', self.client)
        self.assertNotRegex(self.client + self.perspective, r"\broot\.CFrame\s*=")
        self.assertNotIn('player.Character:GetDescendants()', self.perspective)
        self.assertNotIn("rbxasset://sounds/", self.client + self.perspective)
        render = self.client.split('RunService:BindToRenderStep(', 1)[1]
        self.assertNotIn('camera.CFrame =', render.split('if hidden and peekCF then', 1)[0])
        self.assertIn('if hidden and peekCF then', render)
        self.assertIn('camera.CameraType = Enum.CameraType.Scriptable', render)

    def test_keys_crouching_monsters_and_first_person_avatar_are_embedded(self):
        self.assertIn("local function makeDresser", self.server)
        self.assertIn('takePrompt.Name = "TakeKey"', self.server)
        self.assertIn('openPrompt.Name = "OpenDrawer"', self.server)
        self.assertIn('room.model:SetAttribute("KeyFound", true)', self.server)
        self.assertIn('closePrompt.Name = "CloseWardrobe"', self.server)
        self.assertIn('local function swingDoor(room, opening)', self.server)
        self.assertIn('local function swingCloset(closet, opening)', self.server)
        self.assertIn('info.crouching and CONFIG.CrouchSpeed', self.server)
        self.assertIn('state.hidden[player] or not info.crouching', self.server)
        self.assertIn('local function copyArm', self.perspective)
        self.assertIn('copyArm(prefix .. "Hand"', self.perspective)
        self.assertIn('copyArm("Left Arm"', self.perspective)
        self.assertIn('part.CanCollide = false', self.perspective)
        self.assertIn('humanoid.CameraOffset = Vector3.new', self.client)
        self.assertIn('remote:FireServer("Crouch", on)', self.client)
        self.assertIn('remote:FireServer("Torch", flashlightOn)', self.client)
        self.assertIn('startMoth = function(room, epoch)', self.server)
        self.assertIn('info.torchOn and not state.hidden[player]', self.server)
        self.assertNotIn('viewPart("Left hand"', self.client)
        self.assertNotIn('"Whisper"', self.server + self.client)
        self.assertNotIn('play(heartbeat', self.client)
        self.assertNotIn('play(knock', self.client)
        self.assertNotIn('elseif event == "Warning"', self.client)
        self.assertNotIn('remote:FireAllClients("Warning"', self.server)
        self.assertNotIn('remote:FireAllClients("Safe"', self.server)
        self.assertIn('function Layout.IsTurn(index, seed)', self.layout)
        self.assertIn('function Layout.PathX(index, localZ, seed)', self.layout)
        self.assertIn('local function planRooms(seed)', self.server)
        self.assertIn('local function walkRoute(position, destination, speed, dt, height)', self.server)
        self.assertIn('local function showScare(kind, source)', self.client)

    def test_no_hint_overlays_and_physical_lighting(self):
        self.assertNotIn('showNotice(', self.client)
        self.assertNotIn('"Controls",', self.client)
        self.assertNotIn('"Interaction status",', self.client)
        self.assertNotIn('"Threat flash",', self.client)
        self.assertNotIn('"Wardrobe controls",', self.client)
        self.assertNotIn('"End detail",', self.client)
        self.assertNotRegex(self.server, r'ActionText\s*=\s*"[^"]+"')
        self.assertNotRegex(self.server, r'ObjectText\s*=\s*"[^"]+"')
        self.assertIn('setLamp(lamp, rng:NextNumber() > 0.48)', self.server)
        self.assertIn('setLamp(lamp, lamp.normallyOn)', self.server)
        self.assertIn('model:SetAttribute("Dark", plan.dark)', self.server)
        self.assertIn('bulb.Material = Enum.Material.Glass', self.server)
        self.assertIn('MothGraceSeconds = 4', self.server)
        self.assertIn('task.wait(CONFIG.MothGraceSeconds / 8)', self.server)
        self.assertNotIn('remote:FireAllClients("Warning"', self.server)

    def test_keys_live_in_roblox_hands_only_until_used(self):
        self.assertIn('hand = character and (character:FindFirstChild("RightHand")', self.server)
        self.assertIn('grip.Part0 = hand', self.server)
        self.assertIn('player:SetAttribute("HeldKey", room.index + 1)', self.server)
        self.assertIn('if state.keys[player] == index then', self.server)
        self.assertIn('putBackKey(player)', self.server)
        self.assertIn('local visible = keyNumber ~= nil and not peek', self.perspective)
        self.assertIn('local keyModel', self.perspective)
        self.assertIn('local function makeViewKey()', self.perspective)
        self.assertIn('player:GetAttribute("KeyTurning")', self.perspective)
        self.assertIn('cameraCF = cf * CFrame.new(0, 5.0, -1.02)', self.server)
        self.assertIn('"Spaced wooden louvre"', self.server)

    def test_all_three_binary_filenames_open_the_same_place(self):
        binary = (ROOT / "Nocturne.rbxl").read_bytes()
        self.assertTrue(binary.startswith(b"<roblox!\x89\xff\r\n\x1a\n"))
        self.assertGreater(len(binary), 10_000)
        self.assertEqual(binary, (ROOT / "13123.rbxl").read_bytes())
        self.assertEqual(binary, (ROOT / "Nocturne-v6.rbxl").read_bytes())


if __name__ == "__main__":
    unittest.main()
