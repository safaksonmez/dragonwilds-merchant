"""Development-only, backed-up offline Coin grant. Never ship in the mod ZIP."""
import argparse
import base64
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid
from datetime import datetime

COIN_ID = "o-67GWCBTUeTPasJ-o_1Sw"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path)
    parser.add_argument("--character-guid", required=True)
    parser.add_argument("--target", type=int, default=1000)
    args = parser.parse_args()
    assert os.name == "nt", "This offline tool checks Windows game processes."
    processes = subprocess.check_output(["tasklist", "/FO", "CSV", "/NH"], text=True)
    assert not any("dragonwilds" in row[0].lower() for row in csv.reader(io.StringIO(processes)) if row), "Close the game first."
    path = args.save.resolve(strict=True)
    assert path.suffix.lower() == ".json" and path.parent.name == "SaveCharacters", "Expected a character save."
    assert 1 <= args.target <= 999999, "Invalid target balance."
    original = path.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    assert data["meta_data"]["char_guid"] == args.character_guid, "Character identity mismatch."
    inventory = data["GameProgress"]["Inventory"]
    assert isinstance(inventory, dict) and isinstance(inventory["MaxSlotIndex"], int)
    slots = [value for key, value in inventory.items() if key.isdigit() and isinstance(value, dict)]
    before = sum(value.get("Count", 1) for value in slots if value.get("ItemData") == COIN_ID)
    if before >= args.target:
        print(f"Coin already present: {before}; no save changes.")
        return
    free = next((str(i) for i in range(inventory["MaxSlotIndex"] + 1) if str(i) not in inventory), None)
    assert free is not None, "No empty inventory slot; refusing to replace an item."
    # Native saves use 22-character URL-safe, unpadded 128-bit compact GUIDs.
    guid = base64.urlsafe_b64encode(uuid.uuid4().bytes).decode("ascii").rstrip("=")
    assert all(value.get("GUID") != guid for value in slots)
    inventory[free] = {"GUID": guid, "ItemData": COIN_ID, "Count": args.target - before}
    encoded = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    backup_dir = Path(__file__).resolve().parents[1] / "local" / "backups" / ("before-offline-coin-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    backup_dir.mkdir(parents=True)
    shutil.copy2(path, backup_dir / path.name)
    assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(original).digest(), "Save changed during grant."
    temporary = path.with_name(path.name + ".dwm-tmp")
    assert not temporary.exists(), "A previous temporary save needs inspection."
    with temporary.open("xb") as file:
        file.write(encoded)
        file.flush()
        os.fsync(file.fileno())
    os.replace(temporary, path)
    written = json.loads(path.read_text(encoding="utf-8"))
    after = sum(value.get("Count", 1) for key, value in written["GameProgress"]["Inventory"].items()
                if key.isdigit() and isinstance(value, dict) and value.get("ItemData") == COIN_ID)
    assert after == args.target, "Coin save readback failed."
    print(f"Coin save verified: {before} -> {after}; new slot={free}; backup={backup_dir / path.name}")


if __name__ == "__main__":
    main()
