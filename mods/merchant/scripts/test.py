"""Run domain tests on Lua 5.4. Lupa is a development-only dependency."""
from pathlib import Path
import json
import importlib.util
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
print("RuneSchema storefront binding contract checked", flush=True)

spec = importlib.util.spec_from_file_location("native_builder", MOD_ROOT / "scripts" / "build-native-content.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
recipes = json.loads((content / "recipes" / "20-merchant-recipes.json").read_text())
row = json.loads((content / "raw" / "20-merchant-row.json").read_text())[builder.TABLE][builder.ROW]
paths = json.loads((MOD_ROOT / "assets" / "native-item-paths.json").read_text())["paths"]
assert len(recipes) == len(row["SellableItems"]) == len(paths) == 572
assert row["bIsVendor"] is True
refs = [ref for group in row["LabeledRecipes"] for ref in group["Collection"]]
assert set(refs) == {builder.recipe_path(key) for key in recipes}
assert len(refs) == len(set(refs)) == len(recipes)
assert {sale["ItemData"] for sale in row["SellableItems"]} == set(paths)
for recipe in recipes.values():
    assert recipe["Unlock"] is False
    fields = recipe["Properties"]
    assert fields["bIgnoreAutomaticUnlocks"] is True
    assert fields["ItemsConsumed"] == [{"ItemData": builder.COIN, "Count": builder.BUY}]
    assert fields["ItemsCreated"][0]["ItemData"] in paths
    assert fields["ItemsCreated"][0]["Count"] == 1
for source in scripts.rglob("*.lua"):
    text = source.read_text()
    assert ":AddRow(" not in text and "StaticConstructObject(" not in text, source
print("572 native recipe/row references, discovery-safe defaults, and forbidden Lua mutation checks passed", flush=True)
