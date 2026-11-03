"""Generate native RuneSchema recipes/rows from verified asset references.

Only paths ship, never cooked game content, saves, or discovery history.
Regenerate after changing the fixed native prices or supported item roster.
"""
from pathlib import Path
import base64
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src" / "DragonwildsMerchant"
TABLE = "/Game/Gameplay/World/Vendors/DT_VendorDataTable.DT_VendorDataTable"
ROW = "DWM_CoinMerchant_v1"
COIN = "/Game/RuneSchema/DragonwildsMerchant/Items/dwm_coin.dwm_coin"
BUY, SELL = 10, 4
TITLE = "Valley Trader"
HEADER = "/Game/Art/UI/Craft/T_DeathShop_Banner.T_DeathShop_Banner"
CATEGORIES = (
    "Melee Weapons", "Ranged Weapons", "Magic Weapons", "Headgear", "Body Armour", "Leg Armour",
    "Capes", "Shields", "Jewellery", "Tools", "Ammunition", "Runes", "Fish", "Food & Ingredients",
    "Drinks", "Potions", "Seeds & Farming", "Metals & Minerals", "Wood & Plants", "Animal Materials",
    "Textiles", "Crafting Materials", "Blueprints", "Vestiges", "Patterns", "Skill Tomes",
    "Quest Items & Keys", "Miscellaneous",
)


def category(path, kind):
    lower = path.lower()
    if "/quest/" in lower or "/resources/key/" in lower: return "Quest Items & Keys"
    if kind == "ConsumableRecipeUnlocker":
        return "Patterns" if "/cape/" in lower or "/patterns/" in lower else "Vestiges"
    if "/plans/" in lower or "/decorations/" in lower: return "Blueprints"
    if "/tomes/" in lower or kind == "JournalItemData": return "Skill Tomes"
    if kind == "PotionItemData": return "Potions"
    if kind == "DrinkItemData": return "Drinks"
    if "/fishes/" in lower or "/resources/fish/" in lower: return "Fish"
    if kind == "FoodItemData": return "Food & Ingredients"
    if kind in {"SeedHeldEquipmentData", "HeldTreeSeedData"}: return "Seeds & Farming"
    if kind in {"RangedAmmoData", "FishingBaitAmmoData"}: return "Ammunition"
    if kind == "MagicAmmoData": return "Runes"
    if kind == "ShieldData": return "Shields"
    if kind == "TrinketItemData" or "/jewell" in lower or "/jewler" in lower: return "Jewellery"
    if kind == "WearableEquipmentData":
        if "/cape/" in lower: return "Capes"
        if "/head/" in lower: return "Headgear"
        if "/body/" in lower: return "Body Armour"
        return "Leg Armour"
    if kind == "HeldEquipmentData":
        if any(f"/{tool}/" in lower for tool in ("pickaxe", "hatchet", "torch", "farming")): return "Tools"
        if "/bow/" in lower or "/crossbow/" in lower: return "Ranged Weapons"
        if "/staff/" in lower or "/wand/" in lower: return "Magic Weapons"
        return "Melee Weapons"
    if kind in {"SpadeToolEquipmentData", "FishingRodHeldEquipmentData", "HarvestToolEquipmentData", "HeldContainerEquipmentData", "WhetstoneItemData"}: return "Tools"
    if "/resources/metal/" in lower or "/metal/" in lower or "/resources/mineral/" in lower: return "Metals & Minerals"
    if any(f"/{part}/" in lower for part in ("plant", "herb", "wood", "agility")): return "Wood & Plants"
    if "/animal/" in lower: return "Animal Materials"
    if "/textiles/" in lower: return "Textiles"
    if "/resources/" in lower or kind == "FuelItemData" or "/components/" in lower: return "Crafting Materials"
    return "Miscellaneous"


def recipe_path(key):
    # RuneSchema RuntimeRecipePath, source commit 5eb80dfe: safe key + FNV suffix.
    value = 14695981039346656037
    for byte in key.encode():
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    name = f"RSRecipe_{key}_{value:016x}"
    return f"/Game/RuneSchema/DragonwildsMerchant/Recipes/{name}.{name}"


def generate():
    document = json.loads((ROOT / "assets" / "native-item-paths.json").read_text(encoding="utf-8"))
    paths = document["paths"]
    kinds = document["kinds"]
    assert paths == sorted(set(paths)) and len(paths) > 0
    assert set(kinds) == set(paths)
    recipes, sales, manifest = {}, [], []
    grouped = {label: [] for label in CATEGORIES}
    for item in paths:
        assert re.fullmatch(r"/(?:" + "|".join(document["mounts"]) + r")/Gameplay/[A-Za-z0-9_./-]+\.[A-Za-z0-9_-]+", item), item
        assert item != COIN
        digest = hashlib.sha256(("DragonwildsMerchant/native-buy/v1/" + item).encode()).digest()
        key = "DWM_Buy_" + digest[:8].hex()
        identity = base64.urlsafe_b64encode(digest[:16]).decode().rstrip("=")
        path = recipe_path(key)
        assert key not in recipes
        recipes[key] = {
            "PersistenceID": identity, "Unlock": False,
            "Properties": {
                "ItemsConsumed": [{"ItemData": COIN, "Count": BUY}],
                "ItemsCreated": [{"ItemData": item, "Count": 1}],
                "ExtraItemsCreated": [], "bIgnoreAutomaticUnlocks": True,
                "bIgnoreNotification": True, "ChanceToProduceExtraItems": 0,
                "SkillXPAwardedOnCraft": 0, "CraftTime": 0,
                "MinProcessingTime": 0, "MaxProcessingTime": 0, "CraftQuantityMultiplier": 1,
            },
        }
        grouped[category(item, kinds[item])].append(path)
        sales.append({"ItemData": item, "Currency": COIN, "CurrencyPerItem": SELL, "ReputationPerItem": 0})
        manifest.append(f'    ["{item}"] = {{path = "{path}", id = "{identity}", buy_price = {BUY}, sell_price = {SELL}}},')
    groups = [{"Label": label, "Collection": refs} for label, refs in grouped.items() if refs]
    assert all(len(group["Collection"]) <= 128 for group in groups), "Split oversized categories by meaning"
    row = {"DisplayNameOverride": TITLE, "VendorHeaderImage": HEADER, "bIsVendor": True,
           "bHaveRepairOption": False, "bHaveMasterworkOption": False,
           "LabeledRecipes": groups, "SellableItems": []}
    for folder in ["recipes", "raw"]:
        (SOURCE / folder).mkdir(exist_ok=True)
    (SOURCE / "recipes" / "20-merchant-recipes.json").write_bytes((json.dumps(recipes, indent=2) + "\n").encode())
    (SOURCE / "raw" / "20-merchant-row.json").write_bytes((json.dumps({TABLE: {ROW: row}}, indent=2) + "\n").encode())
    late = {"$DWMRuntimeSales": 1, TABLE: {ROW: {"$PatchOnly": True, "SellableItems": sales}}}
    (SOURCE / "ue4ss" / "DragonwildsMerchant" / "Data" / "native-sales.json").write_bytes((json.dumps(late, indent=2) + "\n").encode())
    lua = '-- Generated by scripts/build-native-content.py. No native UObject writes in Lua.\nreturn {\n'
    lua += f'    buy_price = {BUY}, sell_price = {SELL}, product_count = {len(paths)},\n    by_item = {{\n'
    lua += "\n".join(manifest) + "\n    },\n}\n"
    (SOURCE / "ue4ss" / "DragonwildsMerchant" / "Scripts" / "merchant" / "data" / "native_content.lua").write_bytes(lua.encode())
    print(f"Generated {len(paths)} native buy recipes, {len(groups)} categories, and native sell entries")


if __name__ == "__main__":
    generate()
