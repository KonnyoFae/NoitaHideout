"""Verify the turret menu textures against the atlas used for the other support cards."""
import argparse
from pathlib import Path
import struct

from PIL import Image


def render(word, atlas, glyphs):
    mask = Image.new("L", (600, 100))
    pen = 2
    for char in word:
        x, y, width, height, left, top, advance = glyphs[ord(char)]
        if width and height:
            glyph = atlas.crop((int(x), int(y), int(x + width), int(y + height)))
            mask.paste(glyph, (round(pen + left), round(55 + top)))
        pen += advance
    mask = mask.crop(mask.getbbox())
    image = Image.new("RGBA", mask.size, "white")
    image.putalpha(mask)
    return image


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("atlas", type=Path, help="path to notosans_zhcn_48.png")
    parser.add_argument("--write", action="store_true", help="regenerate the turret labels")
    args = parser.parse_args()
    labels = Path(__file__).resolve().parents[1] / "mods/noita_hideout/files/support_labels"
    table = args.atlas.with_suffix(".bin").read_bytes()
    glyphs = {row[0]: row[1:] for row in struct.iter_unpack(">I7f", table[65:])}
    with Image.open(args.atlas) as sheet:
        assert sheet.mode == "L", "This atlas stores glyph coverage in its grayscale channel"
        for key, word in (
            ("necrobot_zh", "复活机器人"), ("necrobot_en", "Necrobot"),
            ("mg_turret_zh", "召唤机枪塔"), ("mg_turret_en", "Summon MG Turret"),
            ("chaingun_turret_zh", "召唤链炮塔"), ("chaingun_turret_en", "Summon Chaingun Turret"),
            ("missile_turret_zh", "召唤连发导弹塔"), ("missile_turret_en", "Summon Missile Turret"),
        ):
            expected = render(word, sheet, glyphs)
            path = labels / (key + ".png")
            if args.write and not key.startswith("necrobot"):
                expected.save(path)
            with Image.open(path) as actual:
                assert actual.size == expected.size and actual.convert("RGBA").tobytes() == expected.tobytes(), key
    print("Matched both reference labels and all turret labels pixel for pixel.")
