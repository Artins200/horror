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
        self.assertEqual(self.named("StarterPlayer", "StarterPlayer").findtext(
            "Properties/token[@name='CameraMode']"), "1")

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
        self.assertEqual(names.count("Wardrobe back"), 2)
        self.assertEqual(names.count("Carved wardrobe leaf"), 4)
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
        self.assertIn("Enum.CameraType.Scriptable", self.client)

    def test_character_camera_does_not_override_roblox_physics(self):
        self.assertIn("Workspace.Gravity = 196.2", self.server)
        self.assertIn("root.Anchored = false", self.server)
        self.assertIn("humanoid.AutoRotate = true", self.server)
        self.assertIn("hum.AutoRotate = true", self.server)
        self.assertNotRegex(self.client, r"\broot\.CFrame\s*=")
        self.assertIn("targetPosition.X", self.client)  # follow physics-driven planar position
        self.assertNotIn("rbxasset://sounds/", self.client)  # avoid missing Studio sound files

    def test_keys_crouching_monsters_and_avatar_arms_are_embedded(self):
        self.assertIn("local function makeDresser", self.server)
        self.assertIn('takePrompt.Name = "TakeKey"', self.server)
        self.assertIn('openPrompt.Name = "OpenDrawer"', self.server)
        self.assertIn('room.model:SetAttribute("KeyFound", true)', self.server)
        self.assertIn('closePrompt.Name = "CloseWardrobe"', self.server)
        self.assertIn('local function swingDoor(room, opening)', self.server)
        self.assertIn('local function swingCloset(closet, opening)', self.server)
        self.assertIn('info.crouching and CONFIG.CrouchSpeed', self.server)
        self.assertIn('and (state.hidden[player] or not info.crouching)', self.server)
        self.assertIn('local function cloneAvatarArm', self.client)
        self.assertIn('cloneAvatarArm(character, prefix .. "Hand"', self.client)
        self.assertIn('remote:FireServer("Crouch", on)', self.client)
        self.assertIn('remote:FireServer("Torch", flashlightOn)', self.client)
        self.assertIn('startMoth = function(room, epoch)', self.server)
        self.assertIn('info.torchOn and not state.hidden[player]', self.server)
        self.assertNotIn('viewPart("Left hand"', self.client)
        self.assertNotIn('"Whisper"', self.server + self.client)
        self.assertNotIn('play(heartbeat', self.client)
        self.assertNotIn('play(knock', self.client)
        warning_handler = self.client.split('elseif event == "Warning" then', 1)[1].split(
            'elseif event == "Safe" then', 1)[0]
        self.assertNotIn('play(', warning_handler, 'light-flicker warning must be silent')
        self.assertIn('function Layout.IsTurn(index)', self.layout)
        self.assertIn('function Layout.PathX(index, localZ)', self.layout)

    def test_both_filenames_open_the_same_fixed_place(self):
        binary = (ROOT / "Nocturne.rbxl").read_bytes()
        self.assertTrue(binary.startswith(b"<roblox!\x89\xff\r\n\x1a\n"))
        self.assertGreater(len(binary), 10_000)
        self.assertEqual(binary, (ROOT / "13123.rbxl").read_bytes())


if __name__ == "__main__":
    unittest.main()
