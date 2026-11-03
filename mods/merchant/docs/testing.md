# Validation record — 2026-11-03

## Local checks

- Lua 5.4 syntax validation through development-only Lupa 2.8 for runtime scripts and the reflection probe.
- 33 local domain/adapter checks: discovery gates, world union/isolation, failed persistence, quantities/prices/balances, capacity, rollback contract, request replay, overflow, journal parsing, stable recipe identity, UObject path access, storefront ownership, signed native levels, malformed values, and partial-catalog rejection.
- A full Lua catalog-flow regression: pickup and learned outputs, no discovery from prior shop offers, transient unlock membership, native row contents, and reopening.
- Storefront binding checks require the provider bootstrap row and mandatory Items array.
- Packaging checks allowed paths, JSON, and ZIP entry/source SHA256 equality. No DLLs, game assets, saves, dumps, local paths, development grants, or runtime discovery journals enter the archive.
- Local deployment backs up the add-on and verifies installed file hashes. This is not a Vortex deployment test.

```powershell
python -m pip install --target mods/merchant/local/python -r mods/merchant/requirements-dev.txt
python mods/merchant/scripts/test.py
pwsh -NoProfile -File mods/merchant/scripts/package.ps1 -Force
```

The atomic inventory backend in the domain tests is a test double. Production uses native InventoryController operations. Local tests do not prove native transaction atomicity, RPC deduplication, capacity behavior, or UI correctness.

## Observed game sessions

| Version / observation | Result |
| --- | --- |
| Registered Coin and native grant | Native add returned true and balance changed from 0 to 1000; later save reload persistence was confirmed by the tester. The development grant is outside the public runtime. |
| dev.1 normal launch, 15:28–15:29 | Companion loaded, but the NPC was disabled by an invalid storefront; catalog access also called unsupported GetPathName. Failed gameplay test, unrelated to launch method. |
| dev.2 normal launch, 15:35–15:37 | NPC/vendor definitions loaded=4, errors=0; tester found the merchant. Catalog failed because a TArray callback index was treated as an output item. |
| dev.3, 15:42–15:48 | TArray iteration advanced, but catalog generation failed with invalid_power_level. The entire catalog was blocked by an item outside the assumed price range. Actual offending raw values were not captured. |
| dev.4 | Signed-level pricing and per-product rejection; local checks and full Lua flow pass. In-game confirmation is pending. |

## Next gameplay checks

1. Launch normally and load an authority world. Confirm Coin inventory persistence.
2. Find the fixed Coin Merchant through the M map; inspect the table/crates/barrel, grounding, collision, and idle animation.
3. Open the merchant. Known products should appear; undiscovered products should remain absent. Check `Catalog ready: N discovered offers` and absence of Lua errors.
4. Buy one product and verify exact Coin consumption and product count. Sell an ordinary item and verify the consumed slot/count and credited Coin.
5. Exercise insufficient funds, a full bag, quantity limits, 600 cm distance, protected-item sales, and fast repeated clicks. Confirm zero mutation on Count=0 / Slot=-1 rejection paths.
6. Reopen, discover another item, save/quit/reload. Coin and world discovery should persist; temporary shop recipes must not enter ordinary saved recipe unlocks.
7. Travel to a different world. Do not reuse the prior world's shared journal; the joining character's normal learned history intentionally contributes to the new world.

## Outstanding

Native catalog/DataTable/TSet/soft-reference integration; completed buy/sell and failure behavior; animation/decor; combat targeting; remote client catalog synchronization; dedicated server; Steam/Epic/Xbox store builds; clean Vortex install/deploy/update/removal; config and journal preservation during updates. Local Vortex/extension versions remain unknown.

The tester controls the game. Investigate `[DragonwildsMerchant] Catalog blocked`, `Purchase refused`, `Sale refused`, and related UE4SS errors without claiming unobserved gameplay success.
