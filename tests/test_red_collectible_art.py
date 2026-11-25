from pathlib import Path
import json
import struct
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "mods/noita_hideout/files/items"
MASTERS = ROOT / "resources/Relics"
RELICS = (("salvage_bell", "SalvageBell"), ("rewind_watch", "RewindWatch"),
          ("stasis_hourglass", "hourglass"), ("dustless_duster", "duster"), ("mana_reactor", "ReactorCore"))


class CollectibleArt(unittest.TestCase):
    def test_handheld_animation_uses_authored_frames(self):
        for kind, sheet in RELICS:
            with self.subTest(kind=kind):
                with ZipFile(MASTERS / f"{sheet}.resprite") as project:
                    metadata = json.loads(project.read(next(p for p in project.namelist() if p.endswith("/document.json"))))
                frames = len(metadata["frameDatas"])
                entity = ET.parse(ITEMS / f"{kind}.xml")
                self.assertIn(f"noita_hideout_{kind}", entity.getroot().attrib["tags"].split(","))
                self.assertIn("nh_red_relic", entity.getroot().attrib["tags"].split(","))
                sprite = entity.find("SpriteComponent")
                target = entity.find("SpriteAnimatorComponent").attrib["target_sprite_comp_name"]
                self.assertTrue({target, "enabled_in_world", "enabled_in_hand"} <= set(sprite.attrib["_tags"].split(",")))
                self.assertEqual(float(sprite.attrib["special_scale_x"]), 0.5)
                definition = ET.parse(ROOT / sprite.attrib["image_file"])
                image = (ROOT / definition.getroot().attrib["filename"]).read_bytes()
                self.assertEqual(image, (MASTERS / f"{sheet}.png").read_bytes())
                self.assertEqual(struct.unpack(">II", image[16:24]), (32 * frames, 32))
                anim = definition.find("RectAnimation[@name='activate']")
                self.assertEqual((int(anim.attrib["frame_count"]), int(anim.attrib["frames_per_row"])), (frames, frames))
                for frame in metadata["frameDatas"]:
                    self.assertAlmostEqual(float(anim.attrib["frame_wait"]), frame["durationExact"] / metadata["frameRate"])
                self.assertEqual(anim.attrib["loop"], "0")
                icon = (ROOT / entity.find("ItemComponent").attrib["ui_sprite"]).read_bytes()
                self.assertEqual(struct.unpack(">II", icon[16:24]), (16, 16))

    def test_static_inventory_art_matches_first_frame(self):
        from PIL import Image
        for kind, sheet in RELICS:
            with self.subTest(kind=kind):
                with Image.open(MASTERS / f"{sheet}.png") as source:
                    idle = source.convert("RGBA").crop((0, 0, 32, 32))
                with Image.open(ITEMS / f"{kind}.png") as icon:
                    self.assertEqual(icon.convert("RGBA").tobytes(), idle.tobytes())
                base = idle.resize((16, 16), Image.Resampling.NEAREST)
                item = ET.parse(ITEMS / f"{kind}.xml").find("ItemComponent")
                self.assertEqual(item.attrib["uses_remaining"], "90")
                self.assertEqual(item.attrib["ui_sprite"], f"mods/noita_hideout/files/items/{kind}_icon.png")
                with Image.open(ROOT / item.attrib["ui_sprite"]) as image:
                    native = image.convert("RGBA")
                self.assertEqual(native.size, base.size)
                # The engine paints the numerator at x=0 and x=4. The hotbar
                # art supplies only /90, using the same three-by-six numerals.
                rows = ("...#...#.", "./#.#.#.#", "./.##.#.#", "/...#.#.#", "/.#.#.#.#", "...#...#.")
                overlay = Image.new("RGBA", base.size)
                overlay.paste((26, 21, 24, 194), (0, 0, 16, 6))
                for y, row in enumerate(rows):
                    for x, dot in enumerate(row):
                        if dot != ".":
                            color = (245, 177, 84, 255) if dot == "/" else (226, 219, 208, 255)
                            overlay.putpixel((7+x, y), color)
                self.assertEqual(native.tobytes(), Image.alpha_composite(base, overlay).tobytes())

    def test_reactor_status_icon_has_no_durability_suffix(self):
        from PIL import Image
        effect = ET.parse(ITEMS.parent / "mana_reactor_effect.xml").find("UIIconComponent")
        with Image.open(ROOT / effect.attrib["icon_sprite_file"]) as icon, Image.open(ITEMS / "mana_reactor.png") as idle:
            self.assertEqual(icon.size, (16, 16))
            self.assertEqual(icon.convert("RGBA").tobytes(), idle.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST).tobytes())
