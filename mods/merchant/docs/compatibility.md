# Compatibility and research — 2026-11-03

| Area | Evidence / status |
| --- | --- |
| Game / engine | Mapping name `RSDragonwilds-5.6.1-248854+++dominion+staging-f6d5f942.usmap`; UE 5.6 |
| UE4SS | Local log: 3.0.1 Beta, Git SHA f6d5f942 |
| RuneSchema | 0.8.0.3; custom Coin asset created=1, errors=0 |
| Dependency ZIP SHA256 | `4d9808e67666e416c4413f0164321ed1f18aa0efb9e320497be262d0fd5db22e` |
| Storefront | Tester-provided local Win64 installation; official Steam/Epic/Xbox builds not validated |
| Vortex / extension | Local versions unknown; no clean installation test |
| NPC | Fixed merchant observed; new animation/decor presentation remains unverified |
| Coin | Native grant and subsequent save persistence confirmed |
| Dynamic shop | dev.2: 333 discovered offers on repeated opening; tester confirmed visibility and a purchase. Exact deltas and sales unverified |
| Multiplayer | Remote client catalog synchronization is not implemented |

## Runtime findings

Evidence is kept in ignored local world/object dumps and logs, never distributed. Reflected symbols prove API shape, not successful gameplay behavior.

- DominionPlayerController: IsLocalController, HasAuthority, GetInventory, GetProgressComponent, GetInventoryController, BP_OnPlayerControllerReady, Client_ToggleCraftingMenu(CraftingStationComponent).
- World identity: Pawn:GetWorld().GameState.WorldInfo.WorldId with FGuid A/B/C/D fields.
- ProgressComponent: HasPickedUpItem, IsRecipeUnlocked, ItemsPickedUp, RecipesUnlocked, RecipesUnlockedThatShouldNotPersist, UnlockRecipes, Client_OnItemFirstPickup, Client_HandleItemPickupsLoadedFromPersistence.
- InventoryComponent: GetNumItemsByData, AddItemByData, CanAddItemByData, GetItemFromSlot. Native Coin add and readback succeeded.
- RecipeData construction and an ItemsCreated struct-array assignment succeeded in a small live probe.
- InventoryController: CraftRecipe / Server_CraftRecipe (station, recipe, count, bonus count, XP multipliers, inventories), Server_SellItemFromInventory(inventory, slot, station, instigator). Signatures are dump-verified; the new trade path is unverified.
- Native table `/Game/Gameplay/World/Vendors/DT_VendorDataTable.DT_VendorDataTable`; CraftingStationDataTableRow contains DisplayNameOverride, LabeledRecipes, SellableItems, bIsVendor, and repair/masterwork flags.
- LabeledCraftableCategory contains FText Label and a RecipeData soft-reference Collection. SellableItem contains ItemData, Currency, CurrencyPerItem, ReputationPerItem.
- KismetSystemLibrary.Conv_ObjectToSoftObjectReference is reflected. UE4SS soft setters expect TSoftObjectPtr userdata; native conversion is used rather than a Lua path table.
- InteractableNPC is a neutral WorldActor rather than a combat AI pawn. The fixed XY `[47000,178000]` location was found by the tester.

## Corrected integration assumptions

### Coin registration order — 0.3.0-dev.1

The 16:39–16:42 session loaded all 572 recipes without errors, but raw row creation ran before /assets registered Coin and failed to resolve SellableItem.Currency. The row was rejected; Repair/Ascension tabs appeared from the component defaults. dev.2 keeps the early row free of hard Coin references and applies its native sales patch later through RuneSchema auto-reload. MainLoader source confirms Add/Modified JSON events queue reload work for the engine tick; RawTableLoader.ReloadDocument applies existing-row patches. The generated file is reset before raw startup, and shared auto-reload must be enabled before launch. Both native component tab flags are explicitly false. This is not yet an observed successful trade.

### Installed Lua row writer failure and native-content migration

In dev.4, 534 shop recipes reached the native unlock set, but the catalog failed its row readback. The F9 diagnostic observed the Lua-created row as `bIsVendor=false`, groups=0, sales=0, despite nonempty AddRow input; the provider-created bootstrap row correctly reported vendor=true. Direct detached-row assignment then crashed with access violation `0xc0000005` in `UE4SS.dll+0xc6e189` on 2026-11-03 at 16:08. The diagnostic command was replaced with a no-op. No further detached-row mutation is used.

0.3.0-dev.1 moves row creation and exact item amounts to the supported RuneSchema `/raw` and `/recipes` loaders. The 572 source item paths were filtered from the world reflection dump by ItemData class inheritance, excluding CDOs and unrelated asset classes. Generated recipe paths follow RuneSchema's `RuntimeRecipePath` algorithm in source commit 5eb80dfe. `Unlock: false` and `bIgnoreAutomaticUnlocks: true` leave discovery availability under Lua control. The provider binds the row via native VendorProperties; Lua only reads it. Prices are fixed at 10/4 for the native-content prototype. This replacement is not yet an observed gameplay pass.

dev.3 progressed beyond discovery iteration but reported `invalid_power_level` during catalog pricing in the 15:42–15:48 session. The 0–100 pricing bound was an implementation assumption, not a reflected ItemData constraint. The dump identifies ItemData.PowerLevel as an IntProperty. Actual offending raw values were not captured before the tester closed the game. dev.4 prices signed native int32 levels with an explicit nonnegative economic tier, performs overflow checks, and excludes malformed/overflowing products individually. It logs product path/value/reason for remaining exclusions. This is not a claim that all future native catalog stages have passed.

The dev.1 normal launch loaded the companion successfully, but RuneSchema rejected the vendor JSON and disabled the NPC with a missing-store error. LoadVendors/AddStore require Items, even for an empty store. dev.2 restores `Items: []` and a provider-owned `DWM_CoinMerchant_bootstrap_v1` row. Lua generates `DWM_CoinMerchant_v1` separately and binds the existing station before menu entry. The new cache/binding behavior still requires native verification.

This UE4SS UObject binding exposes GetFullName, not GetPathName. dev.2 derives paths from the documented `Class /Package.Object:Subobject` full-name format. The original unsupported call was observed in the live log.

In dev.2, NPC definitions loaded with no errors, but catalog generation failed with `attempt to index a number value (local 'output')`. TArray.ForEach supplies `(index, element)`; TSet.ForEach supplies only `(element)`. dev.3 corrects that distinction and adds a full catalog-flow regression. Lua TArray indexes are 1-based.

## Asset and package identity

Coin path: `/Game/RuneSchema/DragonwildsMerchant/Items/dwm_coin.dwm_coin`.
InternalName: `dwm_coin`. PersistenceID: `o-67GWCBTUeTPasJ-o_1Sw`. Keep these stable.

The donor is `/Game/Gameplay/Items/Resources/Currency/ITEM_Currency_SoulFragment.ITEM_Currency_SoulFragment`. RuneSchema registers a separate clone; the vanilla asset is not modified. Model, Wise Old Man idle, fletching table, and Garou crate/barrel paths were found in the world dump. Only references ship, not extracted game files.

RuneSchema is required to register persistent Coin and provide the neutral NPC/map/interaction integration. A prior attempt to construct a station component from Lua hung the session; that approach was abandoned. The implementation uses the provider-owned station and no raw offsets or OptionalProperty writes.

The 0.1 Lua scaffold became a RuneSchema parent plus nested Lua companion in 0.2. ZIP root is `DragonwildsMerchant/`, with assets/npc/vendors and `ue4ss/DragonwildsMerchant/Scripts/main.lua`. Installation target is `ue4ss/Mods/RuneSchema/mods/DragonwildsMerchant/`. A second top-level UE4SS copy conflicts. Shared loader binaries and settings are not packaged.

## Primary sources

Research date: 2026-11-03. Source research is not a local gameplay pass.

- [RuneSchema 0.8.0.3](https://github.com/gh0sted5456-us/RuneSchema/releases/tag/0.8.0.3)
- [RuneSchema Lua companions](https://github.com/gh0sted5456-us/RuneSchema/blob/main/docs/UE4SS-LUA-COMPANIONS.md)
- [Raw row loader](https://github.com/gh0sted5456-us/RuneSchema/blob/main/docs/reference/loaders/raw.md), [recipe loader contract](https://github.com/gh0sted5456-us/RuneSchema/blob/main/docs/reference/loaders/recipes.md): native row construction, recipe identity/amount verification, and separate placement/unlock policies.
- [NPC loader](https://github.com/gh0sted5456-us/RuneSchema/blob/5eb80dfe2e12512b60850b3eeb1fedb4e95c69dd/source/raw/src/Loader/DragonWildsNpcLoader.cpp), [NpcCatalog](https://github.com/gh0sted5456-us/RuneSchema/blob/5eb80dfe2e12512b60850b3eeb1fedb4e95c69dd/source/raw/include/Loader/NpcCatalog.h), [recipe loader](https://github.com/gh0sted5456-us/RuneSchema/blob/5eb80dfe2e12512b60850b3eeb1fedb4e95c69dd/source/raw/src/Loader/DragonWildsRecipeModLoader.cpp)
- [Vortex package rules](https://www.nexusmods.com/site/mods/1273)
- [UE4SS UObject](https://docs.ue4ss.com/dev/lua-api/classes/uobject.html), [TArray](https://docs.ue4ss.com/dev/lua-api/classes/tarray.html), [TSet](https://docs.ue4ss.com/dev/lua-api/classes/tset.html), [UDataTable](https://docs.ue4ss.com/dev/lua-api/classes/udatatable.html), [RegisterHook](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)
- [UE4SS property bindings](https://github.com/UE4SS-RE/RE-UE4SS/blob/236adf2667832375877669faac4b78872b4736b0/UE4SS/src/LuaType/LuaUObject.cpp), [TArray implementation](https://github.com/UE4SS-RE/RE-UE4SS/blob/236adf2667832375877669faac4b78872b4736b0/UE4SS/src/LuaType/LuaTArray.cpp)
