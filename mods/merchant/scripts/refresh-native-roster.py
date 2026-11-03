"""Refresh reference metadata from a local UE4SS dump; never package the dump."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MOUNTS = {"Game", "Fishing", "Agility", "DowdunReach", "UmbralSands", "ScornedWilderness"}


def extract(text):
    classes = {m[1]: (m[2], m[3]) for m in re.finditer(
        r"^\[([A-Fa-f0-9]+)\] (?:Class|BlueprintGeneratedClass) (\S+).*?\[sps: ([A-Fa-f0-9]+)\]", text, re.M)}
    base = next(address for address, (path, _) in classes.items() if path == "/Script/Dominion.ItemData")
    items = {}
    for match in re.finditer(r"^\[[A-Fa-f0-9]+\] (\w+) (/[^ ]+) .*?\[c: ([A-Fa-f0-9]+)\]", text, re.M):
        path, current, chain = match[2], match[3], []
        while current in classes and current not in chain:
            chain.append(current)
            current = classes[current][1]
        if base not in chain or path.split("/")[1] not in MOUNTS or "Default__" in path or ":" in path:
            continue
        kind = next(classes[address][0] for address in chain if classes[address][0].startswith("/Script/Dominion."))
        items[path] = kind.rsplit(".", 1)[1]
    return dict(sorted(items.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dump", type=Path)
    parser.add_argument("--game-build", required=True)
    args = parser.parse_args()
    kinds = extract(args.dump.read_text(encoding="utf-8"))
    assert kinds, "No ItemData references found"
    document = {
        "game_build": args.game_build,
        "source": "Local UE4SS world reflection dump: native and BlueprintGeneratedClass ancestry verified to Dominion.ItemData; asset references and nearest native class only.",
        "mounts": sorted(MOUNTS), "paths": list(kinds), "kinds": kinds,
    }
    (ROOT / "assets" / "native-item-paths.json").write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"Recorded {len(kinds)} verified ItemData references across {len(MOUNTS)} content mounts")
