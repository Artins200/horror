#!/usr/bin/env python3
"""Build the standalone Roblox Studio XML place from the editable Luau sources.

Run from anywhere with `python3 tools/build_place.py`. The committed .rbxlx is a
real, self-contained place: no Rojo install, plugin, or external asset download
is necessary to open and play it. Python's standard library is sufficient.
"""

from __future__ import annotations

import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "src/ServerScriptService/NocturneServer.server.luau"
CLIENT = ROOT / "src/StarterPlayer/StarterPlayerScripts/NocturneClient.client.luau"
LAYOUT = ROOT / "src/ReplicatedStorage/NocturneLayout.luau"
OUTPUT = ROOT / "Nocturne.rbxlx"

NEXT_ID = 0


def item(parent: ET.Element, class_name: str, name: str) -> ET.Element:
    global NEXT_ID
    NEXT_ID += 1
    instance = ET.SubElement(parent, "Item", {"class": class_name, "referent": f"RBX{NEXT_ID}"})
    prop(instance, "string", "Name", name)
    return instance


def prop(instance: ET.Element, tag: str, name: str, value: object) -> ET.Element:
    props = instance.find("Properties")
    if props is None:
        props = ET.SubElement(instance, "Properties")
    p = ET.SubElement(props, tag, {"name": name})
    p.text = str(value)
    return p


def bool_prop(instance: ET.Element, name: str, value: bool) -> None:
    prop(instance, "bool", name, "true" if value else "false")


def vector_prop(instance: ET.Element, tag: str, name: str, values: tuple[float, float, float]) -> None:
    p = prop(instance, tag, name, "")
    for axis, value in zip(("X", "Y", "Z"), values):
        ET.SubElement(p, axis).text = str(value)


def color_prop(instance: ET.Element, name: str, rgb: tuple[int, int, int]) -> None:
    p = prop(instance, "Color3", name, "")
    for axis, value in zip(("R", "G", "B"), rgb):
        ET.SubElement(p, axis).text = f"{value / 255:.9f}"


def cframe_prop(
    instance: ET.Element, name: str, position: tuple[float, float, float],
    rotation: tuple[float, ...] = (1, 0, 0, 0, 1, 0, 0, 0, 1),
) -> None:
    p = prop(instance, "CoordinateFrame", name, "")
    for axis, value in zip(("X", "Y", "Z"), position):
        ET.SubElement(p, axis).text = str(value)
    for axis, value in zip(("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"), rotation):
        ET.SubElement(p, axis).text = str(value)


MATERIAL = {"wood": 512, "planks": 528, "marble": 784, "slate": 800, "concrete": 816,
            "metal": 1088, "fabric": 1312, "neon": 288, "smooth": 272}


def part(
    parent: ET.Element, name: str, size: tuple[float, float, float],
    center: tuple[float, float, float], color: tuple[int, int, int],
    material: str = "smooth", transparency: float = 0, collides: bool = True,
    rotation: tuple[float, ...] = (1, 0, 0, 0, 1, 0, 0, 0, 1),
) -> ET.Element:
    p = item(parent, "Part", name)
    bool_prop(p, "Anchored", True)
    bool_prop(p, "CanCollide", collides)
    color_prop(p, "Color", color)
    vector_prop(p, "Vector3", "Size", size)
    cframe_prop(p, "CFrame", center, rotation)
    prop(p, "token", "Material", MATERIAL[material])
    prop(p, "float", "Transparency", transparency)
    prop(p, "token", "TopSurface", 0)
    prop(p, "token", "BottomSurface", 0)
    return p


def light(parent: ET.Element, position: tuple[float, float, float], brightness: float = 1.6) -> None:
    part(parent, "Tarnished brass lamp", (1.3, 0.25, 1.3), position, (90, 67, 44), "metal")
    bulb = part(parent, "Filament", (0.65, 0.55, 0.65),
                (position[0], position[1] - 0.3, position[2]), (255, 189, 106), "neon", collides=False)
    point = item(bulb, "PointLight", "WarmPointLight")
    prop(point, "float", "Brightness", brightness)
    prop(point, "float", "Range", 22)
    color_prop(point, "Color", (255, 193, 113))
    bool_prop(point, "Shadows", True)


def preview_room(workspace: ET.Element) -> None:
    """One editor-visible foyer; the server removes this and generates real rooms."""
    room = item(workspace, "Model", "StudioPreview")
    W, L, H = 30, 44, 16
    plaster, wood, brass = (43, 52, 54), (44, 31, 29), (136, 100, 62)
    part(room, "Herringbone floor", (W, 1, L), (0, -0.5, L / 2), wood, "planks")
    part(room, "Crimson runner", (7.4, 0.06, L - 6), (0, 0.055, L / 2), (72, 27, 38), "fabric", collides=False)
    for x in (-3.5, 3.5):
        part(room, "Runner edge", (0.1, 0.07, L - 6), (x, 0.095, L / 2), brass, "fabric", collides=False)
    part(room, "Heavy ceiling", (W, 0.9, L), (0, H + 0.45, L / 2), (26, 22, 24), "wood")
    part(room, "Entrance wall", (W, H, 0.72), (0, H / 2, 0.45), plaster, "concrete")
    for side in (-1, 1):
        part(room, "Panelled side wall", (0.75, H, L), (side * (W / 2 - 0.38), H / 2, L / 2), plaster, "concrete")
        part(room, "Dark wainscot", (0.13, 4.2, L - 0.7),
             (side * (W / 2 - 0.83), 2.1, L / 2), (28, 21, 23), "wood")
        part(room, "Gilt picture rail", (0.25, 0.22, L - 0.7),
             (side * (W / 2 - 0.9), 11.5, L / 2), brass, "metal")
        part(room, "Oak skirting", (0.3, 0.3, L - 0.7),
             (side * (W / 2 - 0.92), 0.18, L / 2), (82, 60, 46), "wood")
        for dz in (5.5, 15, 29, 38.5):
            part(room, "Recessed wall panel", (0.08, 6.1, 7),
                 (side * (W / 2 - 0.81), 7.65, dz), (39, 48, 49), "concrete")
        for dz in (12, 32):
            light(room, (side * (W / 2 - 2.5), 11.5, dz))
        part(room, "Doorway wall", ((W - 7.4) / 2, H, 0.72),
             (side * (W + 7.4) / 4, H / 2, L - 0.45), plaster, "concrete")
        part(room, "Brass jamb", (0.32, 10.8, 1), (side * 3.7, 5.4, L - 0.45), brass, "metal")
    part(room, "Doorway arch", (7.4, H - 10.8, 0.72),
         (0, (H + 10.8) / 2, L - 0.45), plaster, "concrete")
    part(room, "Door 001", (6.6, 10.2, 0.42), (0, 5.1, L - 0.65), (72, 51, 40), "planks")
    plate = part(room, "Door number plaque", (2.4, 1.7, 0.09),
                 (0, 8.25, L - 1.02), (27, 22, 24), "metal")
    plaque_gui = item(plate, "SurfaceGui", "EngravedNumber")
    prop(plaque_gui, "token", "Face", 5)  # Enum.NormalId.Front = 5
    canvas = prop(plaque_gui, "Vector2", "CanvasSize", "")
    ET.SubElement(canvas, "X").text = "512"
    ET.SubElement(canvas, "Y").text = "512"
    numbers = item(plaque_gui, "TextLabel", "001")
    prop(numbers, "string", "Text", "001")
    size = prop(numbers, "UDim2", "Size", "")
    for name, value in (("XS", 1), ("XO", 0), ("YS", 1), ("YO", 0)):
        ET.SubElement(size, name).text = str(value)
    prop(numbers, "float", "BackgroundTransparency", 1)
    bool_prop(numbers, "TextScaled", True)
    color_prop(numbers, "TextColor3", (206, 165, 104))
    prop(numbers, "token", "Font", 8)  # Garamond
    for side, dz in ((-1, 21), (1, 24)):
        x = side * (W / 2 - 2.45)
        part(room, "Wardrobe back", (0.24, 8.5, 3.8),
             (x + side * 1.4, 4.25, dz), (28, 22, 24), "wood")
        for offset in (-1.83, 1.83):
            part(room, "Wardrobe side", (2.9, 8.5, 0.2),
                 (x, 4.25, dz + offset), (46, 31, 28), "wood")
        part(room, "Wardrobe roof", (3.05, 0.24, 3.9),
             (x, 8.52, dz), (25, 20, 22), "wood")
        for j in range(10):
            part(room, "Louvred wardrobe door", (0.12, 0.37, 3.4),
                 (x - side * 1.52, 1.26 + j * 0.71, dz), (72, 51, 40), "wood", collides=False)
    light(room, (0, H - 1.7, L / 2), 1.2)


def preview_stair(workspace: ET.Element) -> None:
    """The first actual connection to a second storey, visible in Studio edit mode.

    It is intentionally solid at BOTH sides and beneath the upper landing. The
    playable server generator creates equivalent stairs every six rooms.
    """
    room = item(workspace, "Model", "PreviewEnclosedStair")
    z, length, height, rise, width = 44, 44, 16, 12, 13
    start, finish, steps = 7, 37, 16
    wall, wood, brass = (43, 52, 54), (44, 31, 29), (136, 100, 62)
    part(room, "Stair foundation", (30, 1.3, length), (0, -0.95, z + length / 2), wall, "concrete")
    tilt = -math.atan2(rise, finish - start)
    rail_rotation = (1, 0, 0, 0, math.cos(tilt), -math.sin(tilt),
                     0, math.sin(tilt), math.cos(tilt))
    for side in (-1, 1):
        part(room, "Continuous wall handrail", (0.25, 0.25, math.hypot(finish - start, rise)),
             (side * (width / 2 - 0.53), 3.2 + rise / 2, z + (start + finish) / 2),
             brass, "metal", collides=False, rotation=rail_rotation)
        part(room, "Solid enclosed stair flank", ((30 - width) / 2, height + rise, length),
             (side * (30 + width) / 4, (height + rise) / 2, z + length / 2), wall, "concrete")
        for wall_z, wall_y, wall_height in ((z + 0.45, 14, 28), (z + length - 0.45, 20, 16)):
            part(room, "Doorway side masonry", ((30 - 7.4) / 2, wall_height, 0.8),
                 (side * (30 + 7.4) / 4, wall_y, wall_z), wall, "concrete")
            door_y = 0 if wall_z < z + length / 2 else rise
            part(room, "Structural door jamb", (0.33, 10.8, 1),
                 (side * 3.7, door_y + 5.4, wall_z), brass, "metal")
        for dz in (4, 12, 22, 32, 40):
            surface = 0 if dz <= start else rise if dz >= finish else rise * math.ceil((dz - start) / 30 * steps) / steps
            part(room, "Interior stair pilaster", (0.24, 9, 0.48),
                 (side * (width / 2 - 0.13), surface + 4.5, z + dz), wood, "wood")
        for dz, y in ((5, 10.6), (17, 14.35), (29, 19.6), (40, 22.6)):
            light(room, (side * (width / 2 - 1.3), y, z + dz), 1.2)
    part(room, "Lower arch lintel", (7.4, height + rise - 10.8, 0.8),
         (0, (height + rise + 10.8) / 2, z + 0.45), wall, "concrete")
    part(room, "Solid wall below upper exit", (30, rise, 0.8),
         (0, rise / 2, z + length - 0.45), wall, "concrete")
    part(room, "Upper arch lintel", (7.4, height - 10.8, 0.8),
         (0, rise + (height + 10.8) / 2, z + length - 0.45), wall, "concrete")
    part(room, "Lower stair landing", (width, 1, start),
         (0, -0.5, z + start / 2), wood, "planks")
    part(room, "Upper stair landing", (width, 1, length - finish),
         (0, rise - 0.5, z + (finish + length) / 2), wood, "planks")
    part(room, "Lower enclosed ceiling", (width, 0.9, start),
         (0, height + 0.45, z + start / 2), (27, 22, 24), "wood")
    part(room, "Upper enclosed ceiling", (width, 0.9, length - finish),
         (0, rise + height + 0.45, z + (finish + length) / 2), (27, 22, 24), "wood")
    depth = (finish - start) / steps
    for i in range(1, steps + 1):
        near = z + start + (i - 1) * depth
        far = near + depth
        tread_y = i * rise / steps
        part(room, "Solid stair tread", (width + 0.05, tread_y + 0.2, depth + 0.05),
             (0, (tread_y - 0.2) / 2, (near + far) / 2), wood, "planks")
        part(room, "Stepped enclosed ceiling", (width + 0.05, 0.9, depth + 0.05),
             (0, tread_y + height + 0.45, (near + far) / 2), (27, 22, 24), "wood")
        part(room, "Sealed ceiling riser", (width, rise / steps + 0.12, 0.17),
             (0, height + (i - 0.5) * rise / steps, near), (27, 22, 24), "wood")
        part(room, "Carpeted tread", (6.6, 0.05, depth - 0.04),
             (0, tread_y + 0.035, (near + far) / 2), (70, 25, 36), "fabric", collides=False)
        part(room, "Brass tread nosing", (width - 0.3, 0.08, 0.14),
             (0, tread_y + 0.045, near + 0.08), brass, "metal", collides=False)
    part(room, "Door 002 / upper landing", (6.6, 10.2, 0.42),
         (0, rise + 5.1, z + length - 0.65), (72, 51, 40), "planks")
    for side, dz, floor in ((-1, 3.4, 0), (1, 40.4, rise)):
        x = side * (width / 2 - 2.45)
        part(room, "Stair wardrobe back", (0.24, 8.5, 3.8),
             (x + side * 1.4, floor + 4.25, z + dz), (28, 22, 24), "wood")
        for offset in (-1.83, 1.83):
            part(room, "Stair wardrobe side", (0.2, 8.5, 2.9),
                 (x, floor + 4.25, z + dz + offset), wood, "wood")
        part(room, "Stair wardrobe roof", (3.05, 0.24, 3.9),
             (x, floor + 8.52, z + dz), (27, 22, 24), "wood")


def build() -> Path:
    root = ET.Element("roblox", {"xmlns:xmime": "http://www.w3.org/2005/05/xmlmime", "version": "4"})
    ET.SubElement(root, "External").text = "null"
    ET.SubElement(root, "External").text = "nil"
    workspace = item(root, "Workspace", "Workspace")
    camera = item(workspace, "Camera", "Camera")
    prop(workspace, "Ref", "CurrentCamera", camera.get("referent"))
    # Look down the first corridor. CFrame uses row-major R00..R22.
    pos, target = (2.5, 6.8, 5.5), (0, 5.1, 41)
    dx, dy, dz = (target[i] - pos[i] for i in range(3))
    d = math.sqrt(dx * dx + dy * dy + dz * dz)
    lx, ly, lz = dx / d, dy / d, dz / d
    rx, ry, rz = -lz, 0, lx
    rd = math.sqrt(rx * rx + rz * rz)
    rx, rz = rx / rd, rz / rd
    ux, uy, uz = ry * lz - rz * ly, rz * lx - rx * lz, rx * ly - ry * lx
    cframe_prop(camera, "CFrame", pos, (rx, ux, -lx, ry, uy, -ly, rz, uz, -lz))
    prop(camera, "float", "FieldOfView", 74)
    preview_room(workspace)
    preview_stair(workspace)
    spawn = part(workspace, "PreviewSpawn", (4, 0.4, 4), (0, -0.75, 7),
                 (72, 51, 40), "wood", transparency=1, collides=False)
    spawn.set("class", "SpawnLocation")
    bool_prop(spawn, "Neutral", True)
    prop(spawn, "int", "Duration", 0)

    lighting = item(root, "Lighting", "Lighting")
    prop(lighting, "float", "ClockTime", 0)
    prop(lighting, "float", "Brightness", 0.7)
    color_prop(lighting, "Ambient", (12, 17, 22))
    color_prop(lighting, "OutdoorAmbient", (6, 9, 14))
    color_prop(lighting, "FogColor", (14, 21, 27))
    prop(lighting, "float", "FogStart", 15)
    prop(lighting, "float", "FogEnd", 95)
    bool_prop(lighting, "GlobalShadows", True)
    atmosphere = item(lighting, "Atmosphere", "CorridorHaze")
    prop(atmosphere, "float", "Density", 0.39)
    prop(atmosphere, "float", "Haze", 2.3)
    color_prop(atmosphere, "Color", (108, 128, 137))
    color_prop(atmosphere, "Decay", (34, 24, 27))
    grading = item(lighting, "ColorCorrectionEffect", "ColdShadowsWarmLights")
    color_prop(grading, "TintColor", (214, 227, 238))
    prop(grading, "float", "Contrast", 0.22)
    prop(grading, "float", "Saturation", -0.32)
    bloom = item(lighting, "BloomEffect", "WarmBloom")
    prop(bloom, "float", "Intensity", 0.37)
    prop(bloom, "float", "Size", 26)
    prop(bloom, "float", "Threshold", 1.6)

    server_service = item(root, "ServerScriptService", "ServerScriptService")
    server_script = item(server_service, "Script", "NocturneServer")
    prop(server_script, "ProtectedString", "Source", SERVER.read_text(encoding="utf-8"))
    bool_prop(server_script, "Disabled", False)
    starter_player = item(root, "StarterPlayer", "StarterPlayer")
    prop(starter_player, "token", "CameraMode", 1)  # LockFirstPerson
    player_scripts = item(starter_player, "StarterPlayerScripts", "StarterPlayerScripts")
    client_script = item(player_scripts, "LocalScript", "NocturneClient")
    prop(client_script, "ProtectedString", "Source", CLIENT.read_text(encoding="utf-8"))
    bool_prop(client_script, "Disabled", False)
    replicated = item(root, "ReplicatedStorage", "ReplicatedStorage")
    layout_module = item(replicated, "ModuleScript", "NocturneLayout")
    prop(layout_module, "ProtectedString", "Source", LAYOUT.read_text(encoding="utf-8"))
    item(root, "SoundService", "SoundService")

    ET.indent(root, space="  ")
    OUTPUT.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
    return OUTPUT


if __name__ == "__main__":
    output = build()
    print(f"Built {output.relative_to(ROOT)} ({output.stat().st_size:,} bytes)")
