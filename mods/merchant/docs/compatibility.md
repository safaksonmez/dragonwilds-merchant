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
| Dynamic shop | Latest catalog fix awaits gameplay verification; completed transactions unverified |
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
- [NPC loader](https://github.com/gh0sted5456-us/RuneSchema/blob/5eb80dfe2e12512b60850b3eeb1fedb4e95c69dd/source/raw/src/Loader/DragonWildsNpcLoader.cpp), [NpcCatalog](https://github.com/gh0sted5456-us/RuneSchema/blob/5eb80dfe2e12512b60850b3eeb1fedb4e95c69dd/source/raw/include/Loader/NpcCatalog.h), [recipe loader](https://github.com/gh0sted5456-us/RuneSchema/blob/5eb80dfe2e12512b60850b3eeb1fedb4e95c69dd/source/raw/src/Loader/DragonWildsRecipeModLoader.cpp)
- [Vortex package rules](https://www.nexusmods.com/site/mods/1273)
- [UE4SS UObject](https://docs.ue4ss.com/dev/lua-api/classes/uobject.html), [TArray](https://docs.ue4ss.com/dev/lua-api/classes/tarray.html), [TSet](https://docs.ue4ss.com/dev/lua-api/classes/tset.html), [UDataTable](https://docs.ue4ss.com/dev/lua-api/classes/udatatable.html), [RegisterHook](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)
- [UE4SS property bindings](https://github.com/UE4SS-RE/RE-UE4SS/blob/236adf2667832375877669faac4b78872b4736b0/UE4SS/src/LuaType/LuaUObject.cpp), [TArray implementation](https://github.com/UE4SS-RE/RE-UE4SS/blob/236adf2667832375877669faac4b78872b4736b0/UE4SS/src/LuaType/LuaTArray.cpp)
