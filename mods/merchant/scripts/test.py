"""Run domain tests on Lua 5.4. Lupa is a development-only dependency."""
from pathlib import Path
import json
import importlib.util
import tempfile
import sys

MOD_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MOD_ROOT / "local" / "python"))
try:
    from lupa.lua54 import LuaRuntime
except ImportError:
    raise SystemExit(
        "Install the local test runtime: python -m pip install --target mods/merchant/local/python lupa==2.8"
    )

runtime = LuaRuntime(unpack_returned_tuples=True)
scripts = MOD_ROOT / "src" / "DragonwildsMerchant" / "ue4ss" / "DragonwildsMerchant" / "Scripts"
runtime.execute("package.path = ... .. '/?.lua;' .. package.path", scripts.as_posix())
compile_lua = runtime.eval("function(source, name) return load(source, name) end")
sources = list(scripts.rglob("*.lua")) + list((MOD_ROOT / "tools").rglob("*.lua"))
for path in sources:
    result = compile_lua(path.read_text(encoding="utf-8"), "@" + path.as_posix())
    if isinstance(result, tuple):
        raise SystemExit(result[1])
print(f"Lua 5.4 syntax checked: {len(sources)} files", flush=True)
runtime.execute((MOD_ROOT / "tests" / "run.lua").read_text(encoding="utf-8"))
runtime.execute((MOD_ROOT / "tests" / "native_catalog_flow.lua").read_text(encoding="utf-8"))

content = MOD_ROOT / "src" / "DragonwildsMerchant"
store = json.loads((content / "vendors" / "10-coin-store.json").read_text())
npc = json.loads((content / "npc" / "10-bramblemead-merchant.json").read_text())
assert store["Id"] == npc["VendorID"] == "coin_store"
assert isinstance(store.get("Items"), list), "RuneSchema LoadVendors requires Items"
assert store["Items"] == [], "Only live world discovery may populate the catalog"
assert store["RowName"] == "DWM_CoinMerchant_bootstrap_v1"
assert store["VendorProperties"]["CraftingDataRowHandle"]["RowName"] == "DWM_CoinMerchant_v1"
assert store["VendorProperties"]["bHaveRepairOption"] is False
assert store["VendorProperties"]["bHaveMasterworkOption"] is False
print("RuneSchema storefront binding contract checked", flush=True)

spec = importlib.util.spec_from_file_location("native_builder", MOD_ROOT / "scripts" / "build-native-content.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
recipes = json.loads((content / "recipes" / "20-merchant-recipes.json").read_text())
row = json.loads((content / "raw" / "20-merchant-row.json").read_text())[builder.TABLE][builder.ROW]
paths = json.loads((MOD_ROOT / "assets" / "native-item-paths.json").read_text())["paths"]
sales_document = json.loads((content / "ue4ss" / "DragonwildsMerchant" / "Data" / "native-sales.json").read_text())
late_row = sales_document[builder.TABLE][builder.ROW]
assert late_row["$PatchOnly"] is True
sales = late_row["SellableItems"]
assert row["SellableItems"] == [], "Early raw row must not depend on the later Coin clone"
assert len(recipes) == len(sales) == len(paths) == 1543
assert row["bIsVendor"] is True
assert row["DisplayNameOverride"] == store["MerchantName"] == npc["DisplayName"] == builder.TITLE
assert row["VendorHeaderImage"] == store["VendorHeaderImage"] == builder.HEADER
labels = [group["Label"] for group in row["LabeledRecipes"]]
assert labels == list(builder.CATEGORIES) and len(labels) == len(set(labels))
assert all(0 < len(group["Collection"]) <= 128 for group in row["LabeledRecipes"])
document = json.loads((MOD_ROOT / "assets" / "native-item-paths.json").read_text(encoding="utf-8"))
assert set(document["kinds"]) == set(paths)
assert any(path.startswith("/Fishing/") for path in paths)
assert sum(kind == "FoodItemData" for kind in document["kinds"].values()) == 137
refs = [ref for group in row["LabeledRecipes"] for ref in group["Collection"]]
assert set(refs) == {builder.recipe_path(key) for key in recipes}
assert len(refs) == len(set(refs)) == len(recipes)
assert {sale["ItemData"] for sale in sales} == set(paths)
assert all(sale["Currency"] == builder.COIN and sale["CurrencyPerItem"] == builder.SELL for sale in sales)
for recipe in recipes.values():
    assert recipe["Unlock"] is False
    fields = recipe["Properties"]
    assert fields["bIgnoreAutomaticUnlocks"] is True
    assert fields["ItemsConsumed"] == [{"ItemData": builder.COIN, "Count": builder.BUY}]
    assert fields["ItemsCreated"][0]["ItemData"] in paths
    assert fields["ItemsCreated"][0]["Count"] == 1
by_ref = {builder.recipe_path(key): recipe["Properties"]["ItemsCreated"][0]["ItemData"] for key, recipe in recipes.items()}
for group in row["LabeledRecipes"]:
    for ref in group["Collection"]:
        product = by_ref[ref]
        assert builder.category(product, document["kinds"][product]) == group["Label"]
fish = "/Fishing/Gameplay/Items/Fishes/Sardine/ITEM_Resources_Fish_Raw_Sardine.ITEM_Resources_Fish_Raw_Sardine"
meal = "/Game/Gameplay/Items/Consumables/Food/Items/v3/ITEM_Consumable_Sandwich_Steak.ITEM_Consumable_Sandwich_Steak"
assert fish in paths and meal in paths
assert builder.category(fish, document["kinds"][fish]) == "Fish"
assert builder.category(meal, document["kinds"][meal]) == "Food & Ingredients"
roster_spec = importlib.util.spec_from_file_location("roster", MOD_ROOT / "scripts" / "refresh-native-roster.py")
roster = importlib.util.module_from_spec(roster_spec)
roster_spec.loader.exec_module(roster)
fixture = """[A] Class /Script/Dominion.ItemData [sps: 0]
[B] Class /Script/Dominion.FoodItemData [sps: A]
[C] BlueprintGeneratedClass /Game/Test/BP_Food.BP_Food_C [sps: B]
[D] BP_Food_C /Game/Gameplay/Test/Meal.Meal [c: C]
[E] BP_Food_C /Game/Test/BP_Food.Default__BP_Food_C [c: C]
[F] ItemData /Fishing/Gameplay/Test/Fish.Fish [c: A]
[1] ItemData /FutureMajorVersion/Gameplay/Test/Future.Future [c: A]
[2] Texture2D /Game/Gameplay/Test/Icon.Icon [c: 9]
"""
assert roster.extract(fixture) == {"/Fishing/Gameplay/Test/Fish.Fish": "ItemData", "/Game/Gameplay/Test/Meal.Meal": "FoodItemData"}
for source in scripts.rglob("*.lua"):
    text = source.read_text()
    assert ":AddRow(" not in text and "StaticConstructObject(" not in text, source
print(f"{len(paths)} native references, 28 semantic categories, banner, Blueprint ancestry, content mounts, and discovery-safe defaults passed", flush=True)

test_cache = MOD_ROOT / "local" / "test-sandboxes"
test_cache.mkdir(parents=True, exist_ok=True)
assert test_cache.resolve().is_relative_to(MOD_ROOT.resolve())
with tempfile.TemporaryDirectory(prefix="dwm-sales-test-", dir=test_cache) as directory:
    assert Path(directory).resolve().is_relative_to(test_cache.resolve())
    framework = Path(directory) / "RuneSchema"
    parent = framework / "mods" / "DragonwildsMerchant"
    package = parent / "ue4ss" / "DragonwildsMerchant"
    (framework / "settings").mkdir(parents=True)
    (parent / "raw").mkdir(parents=True)
    (package / "Data").mkdir(parents=True)
    ini = framework / "settings" / "settings.ini"
    ini.write_text("[RuneSchema]\nenableAutoReload = false\n", encoding="utf-8")
    runtime_file = parent / "raw" / "90-dwm-runtime-sales.json"
    runtime_file.write_text("{\"stale\":true}", encoding="utf-8")
    (package / "Data" / "native-sales.json").write_text(json.dumps(sales_document), encoding="utf-8")
    runtime.execute('''
        local root = ...
        local sales = require("merchant.integrations.deferred_sales")
        local ok, reason = pcall(sales.prepare, root)
        assert(not ok and tostring(reason):find("enableAutoReload=true",1,true))
        local f = assert(io.open(root.."/../../raw/90-dwm-runtime-sales.json","rb"))
        assert(f:read("*a") == "{}\\n"); f:close()
    ''', package.as_posix())
    assert ini.read_text() == "[RuneSchema]\nenableAutoReload = false\n"
    ini.write_text("[RuneSchema]\nenableAutoReload = true\n", encoding="utf-8")
    runtime.execute('''
        local root, count = ...
        local sales = require("merchant.integrations.deferred_sales")
        sales.prepare(root)
        assert(not sales.ensure(root,0,count))
        local f = assert(io.open(root.."/../../raw/90-dwm-runtime-sales.json","rb"))
        assert(f:read("*a"):find('"$DWMRuntimeSales"',1,true)); f:close()
        assert(not sales.ensure(root,0,count))
        assert(sales.ensure(root,count,count))
    ''', package.as_posix(), len(paths))
    assert ini.read_text() == "[RuneSchema]\nenableAutoReload = true\n"
print("Deferred Coin sales: startup reset, explicit dependency, one-shot request, native count acknowledgement passed", flush=True)
