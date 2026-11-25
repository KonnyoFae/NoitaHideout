"""Verify the supplied art is imported intact and animation extents are valid."""
from pathlib import Path
import json
import struct
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / "mods/noita_hideout/files"
SOURCE = ROOT / "resources/Blades"


def png_size(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR"
    return struct.unpack(">II", data[16:24])


class KatanaAssets(unittest.TestCase):
    def test_weapon_masters_and_grip_pivots(self):
        for kind, source in (("hf_blade", "HFBlade"), ("hf_murasama", "HFMurasama"), ("dragon_king", "RelicBlade")):
            with self.subTest(kind=kind):
                image = FILES / "items" / (kind + ".png")
                self.assertEqual(image.read_bytes(), (SOURCE / (source + ".png")).read_bytes())
                side = 65 if kind == "dragon_king" else 64
                self.assertEqual(png_size(image), (side, side))
                self.assertEqual(png_size(FILES / "items" / (kind + "_icon.png")), (16, 16))
                sprite = ET.parse(FILES / "items" / (kind + "_sprite.xml")).getroot()
                self.assertEqual(ROOT / sprite.get("filename"), image)
                self.assertEqual((sprite.get("offset_x"), sprite.get("offset_y")), ("56", "32"))
                frame = sprite.find("RectAnimation")
                self.assertEqual((frame.get("frame_width"), frame.get("frame_height"), frame.get("frame_count")), (str(side), str(side), "1"))

    def test_slash_has_all_supplied_frames_and_no_damage_components(self):
        from PIL import Image

        with zipfile.ZipFile(SOURCE / "ShashEffect.resprite") as archive:
            doc = next(n for n in archive.namelist() if n.endswith("/document.json"))
            metadata = json.loads(archive.read(doc))
        sprite = ET.parse(FILES / "katana_fx_sprite.xml").getroot()
        self.assertEqual((sprite.get("offset_x"), sprite.get("offset_y")), ("0", "32"))
        animation = sprite.find("RectAnimation[@name='slash']")
        count = len(metadata["frameDatas"]) + 1
        self.assertEqual(int(animation.get("frame_count")), count)
        self.assertEqual(int(animation.get("frames_per_row")), count)
        self.assertEqual((animation.get("pos_x"), animation.get("pos_y")), ("0", "0"))
        self.assertEqual(animation.get("loop"), "0")
        w, h = int(animation.get("frame_width")), int(animation.get("frame_height"))
        with Image.open(ROOT / sprite.get("filename")) as sheet, Image.open(SOURCE / "ShashEffect.png") as source:
            self.assertEqual(sheet.size, (w * count, h))
            self.assertEqual(source.size, (w * (count - 1), h))
            rgba = sheet.convert("RGBA")
            self.assertIsNone(rgba.crop((0, 0, w, h)).getchannel("A").getbbox())
            self.assertEqual(rgba.crop((w, 0, sheet.width, h)).tobytes(), source.convert("RGBA").tobytes())
        entity = ET.parse(FILES / "katana_fx.xml").getroot()
        self.assertEqual({node.tag for node in entity}, {"SpriteComponent", "LifetimeComponent"})
        self.assertEqual(sprite.get("default_animation"), "slash")
        self.assertEqual(entity.find("SpriteComponent").get("rect_animation"), "slash")
        duration_ticks = round(count * 60 * float(animation.get("frame_wait")))
        self.assertEqual(entity.find("SpriteComponent").get("kill_entity_after_finished"), "1")
        self.assertGreaterEqual(int(entity.find("LifetimeComponent").get("lifetime")), duration_ticks + 2)


if __name__ == "__main__":
    unittest.main()
