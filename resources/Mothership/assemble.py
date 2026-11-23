"""Build the two-deck Noita pixel scene from the original hand-drawn PNGs."""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
PARTS = ROOT / "resources/ShipComponents"
OUT = ROOT / "mods/noita_hideout/files/travel"
TILE = (128, 84)
CROP = (0, 43, 128, 127)
DECKS = (("Cockpit", "MedsHub", "Bedroom"), ("PortalRoom", "PortalControlsHub"))
# Vanilla templebrick_noedge_static and air wang colors from data/materials.xml.
HULL, AIR = (120, 108, 68, 255), (0, 0, 66, 255)


def build():
    width, height = TILE
    art = Image.new("RGBA", (3 * width, 2 * height))
    mask = Image.new("RGBA", art.size, (255, 255, 255, 0))
    cells = ImageDraw.Draw(mask)
    for deck, rooms in enumerate(DECKS):
        y0 = deck * height
        for column, name in enumerate(rooms):
            with Image.open(PARTS / (name + ".png")) as src:
                assert src.size == (128, 128), name
                img = src.convert("RGBA")
                _, top, _, bottom = img.getbbox()
                assert (top, bottom) == (CROP[1], CROP[3]), name
                art.alpha_composite(img.crop(CROP), (column * width, y0))
        # Fill the hull silhouette around each deck's walkable space.
        deck_right = len(rooms) * width - 1
        alpha = art.getchannel("A")
        for y in range(height):
            box = alpha.crop((0, y0 + y, deck_right + 1, y0 + y + 1)).getbbox()
            assert box is not None
            cells.line((box[0], y0 + y, deck_right, y0 + y), fill=HULL)
            if 20 <= y < 60:
                # Follow the opposite slopes of the cockpit and portal room noses.
                left = max(5, 49 - y) if deck == 0 else max(17, y - 3)
                assert left >= box[0] + 3
                cells.line((left, y0 + y, deck_right - 3, y0 + y), fill=AIR)
    # Only the medical room's lower hatch and the control room's upper hatch connect.
    cells.rectangle((201, 60, 225, 103), fill=AIR)
    # Leave the artist's transparent exterior notches clear of default brick pixels.
    mask.paste((255, 255, 255, 0), (0, 0, *art.size), ImageChops.invert(art.getchannel("A")))

    # Flood with a 9 x 19 player profile, including both decks and the hatch.
    air = mask.getchannel("B").point(lambda b: 255 if b == AIR[2] else 0)
    wide = air.filter(ImageFilter.MinFilter(9))
    body = ImageChops.darker(wide, ImageChops.offset(wide, 0, -5))
    body = ImageChops.darker(body, ImageChops.offset(wide, 0, 5))
    ImageDraw.floodfill(body, (173, 50), 128)
    for point in [(45, 50), (316, 50), (213, 81), (224, 134), (91, 134)]:
        assert body.getpixel(point) == 128, point
    for x, floor in [(173, 60), (224, 144), (91, 144)]:
        for dx in range(-4, 5):
            assert mask.getpixel((x + dx, floor)) == HULL
            assert all(mask.getpixel((x + dx, floor - dy)) == AIR for dy in range(1, 21))
    assert mask.getpixel((316, 134))[3] == 0  # no lower stern room
    art.save(OUT / "cabin_background.png")
    mask.save(OUT / "cabin_materials.png")


if __name__ == "__main__":
    build()
