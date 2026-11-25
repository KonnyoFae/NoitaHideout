"""Check source detail, world-space mounts and the quickbar size of supply weapons."""
from pathlib import Path
import json
import struct
import unittest
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "mods/noita_hideout/files/items"
SOURCE = ROOT / "resources/SupplyWeapons"

# The grip and muzzle are world-space points used by the live shooting code.
WEAPONS = {
    "heavy_mg": ("HeavyMachinegun.png", 12, (1, 4), (11, 1.5)),
    "auto_grenade": ("grenade.png", 12, (2, 7), (10, -2)),
    "missile_launcher": ("missile.png", 12, (4, 7), (7, -3)),
    "heavy_plasma": ("heavyPlasma.png", 12, (3, 7), (9, -4)),
    "railgun": ("Railgun.png", 16, (4, 9), (11, -3)),
    "bfg": ("BFG.png", 16, (4, 10), (11, -3)),
}


def png_size(path):
    with path.open("rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR", path
    return struct.unpack(">II", header[16:24])


def assert_art(test, actual, source, first_frame=False):
    if not first_frame and actual.read_bytes() == source.read_bytes():
        return
    from PIL import Image
    with Image.open(actual) as installed, Image.open(source) as master:
        if first_frame:
            master = master.crop((0, 0, master.height, master.height))
        test.assertEqual(installed.size, master.size)
        test.assertEqual(installed.convert("RGBA").tobytes(), master.convert("RGBA").tobytes())


class SupportWeaponSprites(unittest.TestCase):
    def test_smart_darts_keep_needle_art_and_tip_pivot(self):
        shots = ITEMS.parent / "projectiles"
        for kind, projectile, source in (
                ("sedative", "sedative_dart", "TranqNeedle"),
                ("pheromone", "smart_pheromone", "FeromornNeedle")):
            with self.subTest(kind=kind):
                art = shots / (kind + "_needle.png")
                self.assertEqual(art.read_bytes(), (ROOT / "resources/SmartPistols" / (source + ".png")).read_bytes())
                flight = ET.parse(shots / (projectile + ".xml")).find("SpriteComponent")
                attached = ET.parse(shots / "dart_needle.xml").find("SpriteComponent")
                self.assertEqual(ROOT / flight.get("image_file"), art)
                for sprite in [flight, attached]:
                    self.assertEqual((sprite.get("offset_x"), sprite.get("offset_y")), ("12", "3"))
                    self.assertEqual(sprite.get("has_special_scale", "0"), "0")

    def test_smart_pistols_grip_recoil_ground_and_quickbar_match_the_two_masters(self):
        from PIL import Image
        for kind, filename in (("flare_gun", "FeromornPistol"), ("sedative_launcher", "TranqPistol")):
            with self.subTest(kind=kind):
                project = ROOT / "resources/SmartPistols" / filename
                with zipfile.ZipFile(project.with_suffix(".resprite")) as archive:
                    document = next(p for p in archive.namelist() if p.endswith("/document.json"))
                    metadata = json.loads(archive.read(document))
                self.assertEqual(metadata["canvasSize"], {"width": 32, "height": 32})
                frames = metadata["frameDatas"]
                self.assertEqual(len(frames), 2)
                entity = ET.parse(ITEMS / (kind + ".xml"))
                held = entity.find("Base/SpriteComponent")
                self.assertEqual((held.get("special_scale_x"), held.get("special_scale_y")), ("0.25", "0.25"))
                sprite = ET.parse(ROOT / held.get("image_file")).getroot()
                self.assertEqual((sprite.get("offset_x"), sprite.get("offset_y")), ("7", "20"))
                for index, name in enumerate(("default", "fire")):
                    animation = sprite.find(f"RectAnimation[@name='{name}']")
                    self.assertEqual((int(animation.get("pos_x")), int(animation.get("pos_y"))), (index * 32, 0))
                    self.assertEqual((animation.get("frame_width"), animation.get("frame_height"), animation.get("frame_count")), ("32", "32", "1"))
                    self.assertAlmostEqual(float(animation.get("frame_wait")), frames[index]["durationExact"] / metadata["frameRate"])
                hot = entity.find("HotspotComponent")
                self.assertEqual((float(hot.get("offset.x")), float(hot.get("offset.y"))), (6.25, -2.5))
                ground = entity.find("SpriteComponent")
                self.assertIn("enabled_in_world", ground.get("_tags").split(","))
                self.assertEqual((ground.get("offset_x"), ground.get("offset_y")), ("16", "16"))
                self.assertEqual((ground.get("special_scale_x"), ground.get("special_scale_y")), ("0.5", "0.5"))
                source = project.with_suffix(".png")
                assert_art(self, ROOT / sprite.get("filename"), source)
                assert_art(self, ROOT / ground.get("image_file"), source, first_frame=True)
                item = entity.find("Base/ItemComponent")
                self.assertEqual(item.get("uses_remaining"), "20")
                with Image.open(source) as master, Image.open(ROOT / item.get("ui_sprite")) as icon:
                    expected = master.convert("RGBA").crop((0, 0, 32, 32)).resize((16, 16), Image.Resampling.NEAREST)
                    self.assertEqual(icon.size, expected.size)
                    self.assertEqual(icon.convert("RGBA").tobytes(), expected.tobytes())
                shape = ROOT / entity.find("Base/PhysicsImageShapeComponent").get("image_file")
                with Image.open(shape) as mask:
                    self.assertEqual(mask.size, expected.size)
                    self.assertEqual(mask.convert("RGBA").getchannel("A").tobytes(),
                                     expected.getchannel("A").point(lambda a: int(a > 0)).tobytes())

    def test_hand_uses_original_texels_at_the_calibrated_grip(self):
        for kind, (filename, width, grip, muzzle) in WEAPONS.items():
            with self.subTest(kind=kind):
                xml = ET.parse(ITEMS / (kind + ".xml"))
                sprite = xml.find("Base/SpriteComponent")
                art = ROOT / sprite.attrib["image_file"]
                pivot = sprite
                if kind == "heavy_mg":
                    self.assertEqual(art, ITEMS / "heavy_mg_sprite.xml")
                    pivot = ET.parse(art).getroot()
                    art = ROOT / pivot.attrib["filename"]
                    idle = pivot.find("RectAnimation[@name='default']")
                    w, h = int(idle.attrib["frame_width"]), int(idle.attrib["frame_height"])
                    self.assertEqual((float(sprite.get("offset_x", 0)), float(sprite.get("offset_y", 0))), (0, 0))
                else:
                    w, h = png_size(art)
                assert_art(self, art, SOURCE / filename)
                sx = float(sprite.get("special_scale_x", 1))
                sy = float(sprite.get("special_scale_y", 1))
                self.assertEqual(float(pivot.attrib["offset_x"]) * sx, grip[0])
                self.assertEqual(float(pivot.attrib["offset_y"]) * sy, grip[1])
                self.assertEqual((w * sx, h * sy), (width, width))
                if w > width:
                    self.assertEqual(sprite.get("has_special_scale"), "1")
                hot = xml.find("HotspotComponent[@_tags='shoot_pos']")
                self.assertEqual((float(hot.attrib["offset.x"]), float(hot.attrib["offset.y"])), muzzle)
                item = xml.find("Base/ItemComponent")
                self.assertEqual(png_size(ROOT / item.attrib["ui_sprite"]), (16, 16))

    def test_ground_art_and_collision_keep_their_respective_sizes(self):
        for kind, (filename, width, _, _) in WEAPONS.items():
            with self.subTest(kind=kind):
                xml = ET.parse(ITEMS / (kind + ".xml"))
                shape = ROOT / xml.find("Base/PhysicsImageShapeComponent").attrib["image_file"]
                self.assertEqual(png_size(shape), (width, width))
                sprites = [s for s in xml.findall("SpriteComponent") if "enabled_in_world" in s.get("_tags", "").split(",")]
                if width == 16:
                    self.assertEqual(sprites, [])
                    assert_art(self, shape, SOURCE / filename)
                    continue
                self.assertEqual(len(sprites), 1)
                ground = sprites[0]
                self.assertNotIn("enabled_in_hand", ground.get("_tags", "").split(","))
                self.assertEqual(ground.get("has_special_scale"), "1")
                art = ROOT / ground.attrib["image_file"]
                assert_art(self, art, SOURCE / filename, first_frame=kind == "heavy_mg")
                for axis, dimension in zip("xy", png_size(art)):
                    self.assertEqual(float(ground.attrib["special_scale_" + axis]) * dimension, width)
                    self.assertEqual(float(ground.attrib["offset_" + axis]), dimension / 2)

    def test_heavy_mg_animation_timing_frames_and_icon_match_the_master(self):
        from PIL import Image
        master = SOURCE / "HeavyMachinegun.png"
        with zipfile.ZipFile(master.with_suffix(".resprite")) as project:
            document = next(p for p in project.namelist() if p.endswith("/document.json"))
            metadata = json.loads(project.read(document))
        width = metadata["canvasSize"]["width"]
        height = metadata["canvasSize"]["height"]
        frames = metadata["frameDatas"]
        self.assertEqual((width, height, len(frames)), (24, 24, 3))
        self.assertEqual(png_size(master), (width * len(frames), height))
        sprite = ET.parse(ITEMS / "heavy_mg_sprite.xml").getroot()
        self.assertEqual(sprite.attrib["default_animation"], "default")
        for name, count in (("default", 1), ("fire", len(frames))):
            anim = sprite.find(f"RectAnimation[@name='{name}']")
            self.assertEqual((int(anim.attrib["pos_x"]), int(anim.attrib["pos_y"])), (0, 0))
            self.assertEqual((int(anim.attrib["frame_width"]), int(anim.attrib["frame_height"])), (width, height))
            self.assertEqual((int(anim.attrib["frame_count"]), int(anim.attrib["frames_per_row"])), (count, count))
        fire = sprite.find("RectAnimation[@name='fire']")
        self.assertEqual(fire.attrib["loop"], "1")
        for frame in frames:
            self.assertAlmostEqual(float(fire.attrib["frame_wait"]), frame["durationExact"] / metadata["frameRate"])
        entity = ET.parse(ITEMS / "heavy_mg.xml")
        native_icon = ROOT / entity.find("Base/ItemComponent").attrib["ui_sprite"]
        with Image.open(master) as sheet, Image.open(native_icon) as icon:
            first = sheet.convert("RGBA").crop((0, 0, width, height))
            expected = first.resize((16, 16), Image.Resampling.NEAREST)
            self.assertEqual(icon.convert("RGBA").tobytes(), expected.tobytes())

    def test_physics_shape_stays_invisible_and_preserves_the_original_collision_cells(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow is required to decode the per-pixel collision masks")
        for kind, (_, width, _, _) in WEAPONS.items():
            if width == 16:
                continue
            with self.subTest(kind=kind):
                xml = ET.parse(ITEMS / (kind + ".xml"))
                shape = ROOT / xml.find("Base/PhysicsImageShapeComponent").attrib["image_file"]
                with Image.open(shape) as mask, Image.open(ITEMS / (kind + "_world.png")) as previous:
                    alpha = mask.convert("RGBA").getchannel("A")
                    self.assertEqual(alpha.getextrema(), (0, 1))
                    cells = previous.convert("RGBA").getchannel("A").point(lambda a: int(a > 0))
                    self.assertEqual(alpha.tobytes(), cells.tobytes())


if __name__ == "__main__":
    unittest.main()
