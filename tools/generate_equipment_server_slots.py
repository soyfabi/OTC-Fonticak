#!/usr/bin/env python3
"""Generate EquipmentServerSlots.lua from TFS items.xml."""

import re
import sys
from pathlib import Path

SLOT_MAP = {
    "head": 1,
    "neck": 2,
    "necklace": 2,
    "amulet": 2,
    "backpack": 3,
    "armor": 4,
    "body": 4,
    "shield": 5,
    "right-hand": 5,
    "hand": 6,
    "left-hand": 6,
    "legs": 7,
    "feet": 8,
    "ring": 9,
    "ammo": 10,
}

WEAPON_TYPE_SLOT = {
    "shield": 5,
    "ammo": 10,
    "ammunition": 10,
    "sword": 6,
    "axe": 6,
    "club": 6,
    "distance": 6,
    "wand": 6,
    "fist": 6,
    "quiver": 5,
}


def parse_item_ids(open_tag: str):
    single = re.search(r'\bid="(\d+)"', open_tag)
    if single:
        return [int(single.group(1))]
    from_id = re.search(r'\bfromid="(\d+)"', open_tag)
    to_id = re.search(r'\btoid="(\d+)"', open_tag)
    if from_id and to_id:
        start, end = int(from_id.group(1)), int(to_id.group(1))
        if end - start > 5000:
            return []
        return list(range(start, end + 1))
    return []


def attr_values(block: str, key: str):
    return re.findall(
        rf'<attribute key="{key}" value="([^"]+)"',
        block,
        flags=re.IGNORECASE,
    )


def resolve_slot(block: str):
    for slot in attr_values(block, "slot"):
        mapped = SLOT_MAP.get(slot.lower())
        if mapped:
            return mapped

    slot_types = [s.lower() for s in attr_values(block, "slotType")]
    weapon_types = [w.lower() for w in attr_values(block, "weaponType")]

    for weapon_type in weapon_types:
        mapped = WEAPON_TYPE_SLOT.get(weapon_type)
        if mapped:
            return mapped

    if "two-handed" in slot_types:
        for weapon_type in weapon_types:
            if weapon_type in ("distance", "sword", "axe", "club", "wand"):
                return 6

    return None


def parse_items_xml(path: Path):
    text = path.read_text(encoding="utf-8")
    mapping = {}
    pos = 0
    while True:
        start = text.find("<item ", pos)
        if start == -1:
            break
        open_end = text.find(">", start)
        if open_end == -1:
            break
        close = text.find("</item>", open_end)
        if close == -1:
            break
        open_tag = text[start:open_end + 1]
        block = text[open_end + 1:close]
        pos = close + len("</item>")

        item_ids = parse_item_ids(open_tag)
        if not item_ids:
            continue

        inv_slot = resolve_slot(block)
        if inv_slot is None:
            continue

        for item_id in item_ids:
            mapping[item_id] = inv_slot

    return mapping


def emit_lua(mapping, out_path: Path):
    lines = ["return {"]
    for item_id in sorted(mapping):
        lines.append(f"  [{item_id}] = {mapping[item_id]},")
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    items_xml = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        r"C:\Users\fabim\Downloads\forgottenserver-downgrade-1.8-8.60\data\items\items.xml"
    )
    out_lua = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        r"C:\Users\fabim\Downloads\OTC-Fonticak\modules\game_actionbar\logics\EquipmentServerSlots.lua"
    )

    mapping = parse_items_xml(items_xml)
    emit_lua(mapping, out_lua)

    checks = [3350, 3349, 3409, 3051, 3552]
    print(f"Wrote {len(mapping)} entries to {out_lua}")
    for item_id in checks:
        print(f"  [{item_id}] = {mapping.get(item_id, 'MISSING')}")


if __name__ == "__main__":
    main()
