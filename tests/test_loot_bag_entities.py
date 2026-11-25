"""Check the effective Noita XML of enemy drops and the other bag-shaped items."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


REPO = Path(__file__).resolve().parents[1]
ITEMS = REPO / "mods/noita_hideout/files/items"


def components(entity):
    result = []
    for node in entity:
        if node.tag != "Base":
            result.append(node)
            continue
        inherited = components(ET.parse(REPO / node.attrib["file"]).getroot())
        applied = {}
        for override in node:
            matches = [comp for comp in inherited if comp.tag == override.tag]
            index = applied.get(override.tag, 0)
            if index >= len(matches):
                raise AssertionError(f"missing base component {override.tag}")
            matches[index].attrib.update(override.attrib)
            applied[override.tag] = index + 1
        result.extend(inherited)
    return result


class LootBagEntities(unittest.TestCase):
    def test_enemy_drops_hover_and_can_be_picked_up(self):
        for kind in ("travel_satchel", "travel_pack", "loot_case"):
            with self.subTest(kind=kind):
                root = ET.parse(ITEMS / (kind + ".xml")).getroot()
                tags = set(root.attrib["tags"].split(","))
                self.assertTrue({"nh_loot_bag", "item_pickup", "noita_hideout_" + kind} <= tags)
                self.assertNotIn("item_physics", tags)
                parts = components(root)
                self.assertFalse([c.tag for c in parts if "Physics" in c.tag or c.tag == "VelocityComponent"])

                def only(tag):
                    matches = [c for c in parts if c.tag == tag]
                    self.assertEqual(len(matches), 1, tag)
                    return matches[0]

                item = only("ItemComponent")
                self.assertEqual(item.get("is_pickable"), "1")
                self.assertEqual(item.get("preferred_inventory"), "QUICK")
                self.assertEqual(item.get("uses_remaining"), "1")
                self.assertIn("enabled_in_world", item.get("_tags", "").split(","))
                self.assertNotEqual(item.get("_enabled"), "0")
                image = REPO / item.attrib["ui_sprite"]
                self.assertEqual(image, ITEMS / (kind + ".png"))
                self.assertTrue(image.is_file())
                for mode in ("enabled_in_world", "enabled_in_hand"):
                    sprites = [c for c in parts if c.tag == "SpriteComponent" and mode in c.get("_tags", "").split(",")]
                    self.assertTrue(sprites, mode)
                    for sprite in sprites:
                        self.assertEqual(REPO / sprite.attrib["image_file"], image)
                        if "item" in sprite.get("_tags", "").split(","):
                            # Noita replaces this sprite's image even when the ability omits sprite_file.
                            self.assertEqual(only("AbilityComponent").get("sprite_file"), item.attrib["ui_sprite"],
                                             f"{kind}: item sprite would be overwritten by AbilityComponent.sprite_file")
                    if mode == "enabled_in_world":
                        self.assertTrue(any(c.get("_enabled", "1") == "1" for c in sprites))
                pickup = only("LuaComponent")
                self.assertEqual(pickup.get("script_item_picked_up"), "mods/noita_hideout/files/bag_pickup.lua")
                self.assertEqual(pickup.get("execute_every_n_frame"), "-1")

    def test_supply_and_gift_boxes_keep_their_ground_physics(self):
        crates = ("supply_pack", "improved_supply_pack", "advanced_supply_pack")
        gifts = ("gift_box_1", "gift_box_2", "gift_box_3")
        for kind in crates + gifts:
            with self.subTest(kind=kind):
                root = ET.parse(ITEMS / (kind + ".xml")).getroot()
                self.assertIn("item_physics", root.attrib["tags"].split(","))
                parts = {c.tag: c for c in components(root)}
                self.assertIn("PhysicsBodyComponent", parts)
                self.assertEqual(REPO / parts["PhysicsImageShapeComponent"].attrib["image_file"], ITEMS / (kind + ".png"))

    def test_every_collection_card_floats_and_keeps_its_identity(self):
        companions = ("bee", "cat", "dog", "dragon", "dryad", "flower_fairy", "griffin", "minotaur", "slime")
        tarot = ("chariot", "devil", "garden", "hermit", "magician", "moon", "sun", "tower")
        expected = set(companions) | {"tarot_" + name for name in tarot}
        seen = set()
        for path in ITEMS.glob("card_*.xml"):
            root = ET.parse(path).getroot()
            tags = set(root.get("tags", "").split(","))
            if "noita_hideout_summon_card" not in tags:
                continue
            species = path.stem.removeprefix("card_")
            seen.add(species)
            with self.subTest(species=species):
                self.assertTrue({"item_pickup", "nh_companion_" + species} <= tags)
                self.assertTrue(tags.isdisjoint({"item_physics", "nh_loot_bag"}))
                parts = components(root)
                self.assertFalse([c for c in parts if "Physics" in c.tag or c.tag in ("VelocityComponent", "LuaComponent")])
                self.assertEqual(len(parts), len({c.tag for c in parts}))
                by_type = {c.tag: c for c in parts}
                sprite, item = by_type["SpriteComponent"], by_type["ItemComponent"]
                self.assertEqual(set(sprite.get("_tags").split(",")), {"enabled_in_world", "enabled_in_hand"})
                self.assertNotEqual(sprite.get("_enabled"), "0")
                image = path.stem + ("_world.png" if species in companions else ".png")
                self.assertEqual(REPO / sprite.get("image_file"), ITEMS / image)
                self.assertTrue((ITEMS / image).is_file())
                self.assertEqual(REPO / item.get("ui_sprite"), path.with_suffix(".png"))
                self.assertEqual(item.get("item_name"), "$nh_card_" + species)
                self.assertEqual(item.get("uses_remaining"), "80" if species in companions else "40")
                self.assertEqual(item.get("preferred_inventory"), "QUICK")
                self.assertEqual(item.get("is_pickable"), "1")
                self.assertEqual(by_type["AbilityComponent"].get("throw_as_item"), "0")
        self.assertEqual(seen, expected)

    def test_all_five_red_relics_already_float(self):
        for kind in ("salvage_bell", "rewind_watch", "stasis_hourglass", "dustless_duster", "mana_reactor"):
            with self.subTest(kind=kind):
                root = ET.parse(ITEMS / (kind + ".xml")).getroot()
                self.assertNotIn("item_physics", root.get("tags").split(","))
                parts = components(root)
                self.assertFalse([c for c in parts if "Physics" in c.tag or c.tag == "VelocityComponent"])
                sprite = next(c for c in parts if c.tag == "SpriteComponent")
                self.assertIn("enabled_in_world", sprite.get("_tags").split(","))
                item = next(c for c in parts if c.tag == "ItemComponent")
                self.assertEqual(item.get("uses_remaining"), "90")
                self.assertEqual(item.get("is_pickable"), "1")


if __name__ == "__main__":
    unittest.main()
