# Merchant design

## Accepted behavior

- Start with one merchant in Bramblemead Valley; additional regions are future work.
- Use a fixed authored XY position `[47000, 178000]`, RuneSchema surface grounding (`$`) for Z, and yaw 180. Random placement was superseded. `npc/*.json` is the placement source of truth.
- Show the merchant on the M map. Use a neutral InteractableNPC base rather than a combat AI pawn.
- Keep Coin separate from existing currencies, with a stable persistent asset identity and no public starter grant.
- Merge authority-visible participants' discovery history monotonically within a world. Native pickup history or a learned recipe output unlocks a product. Shop recipes cannot unlock their own outputs.
- Allow discovered quest/bound products to be listed for purchase, but prevent selling quest/player-bound items. Exclude Coin itself from the catalog.
- Use native inventory buying/selling, rather than sequential Lua wallet/inventory edits.

## Runtime architecture

RuneSchema creates the Coin asset, merchant, native recipes, and merchant row. Generated `recipes/20-merchant-recipes.json` and `raw/20-merchant-row.json` reference 1,543 ItemData paths verified in build 248854. The catalog uses 28 product categories and the Valley Trader row points to the native vendor banner. No cooked assets or per-player discovery data ship. Prices are fixed at 10 Coin buy / 4 Coin sell in this prototype; regenerate native content when changing prices.

The provider creates an empty bootstrap row from mandatory `Items: []`. Its `VendorProperties.CraftingDataRowHandle` binds the component to the separate native-authored `DWM_CoinMerchant_v1` row. Lua validates this binding but never writes the detached row or its handle.

The early raw row contains soft recipe references and no hard Coin references. After the /assets currency clone is ready, Lua copies its packaged sales template to the mod-owned `raw/90-dwm-runtime-sales.json`. RuneSchema's native auto-reload consumes that file on its engine tick. The companion clears that generated file before startup raw parsing, requires `enableAutoReload=true`, and waits for exact native sale counts/currencies/prices before granting shop availability. Eight 500 ms retries are the limit. No Lua UObject row mutation is used. Repair and Masterwork flags are false on both the row and the component.

Lua reads pickup/learned-recipe history, persists the world discovery union, verifies native recipe identities/prices/outputs, and marks only discovered products available. Native shop recipes enter `RecipesUnlockedThatShouldNotPersist` before `RecipesUnlocked`; fail-closed cleanup revokes only owned shop availability. Vanilla learned recipes remain untouched. The full native row does not by itself grant recipe unlocks (`Unlock: false`, `bIgnoreAutomaticUnlocks: true`).

Native InventoryController owns the exchange. Lua guards authority, world, distance, quantity, native prices, balance, capacity, ownership, protected items, and Coin overflow. Count=0 / invalid-slot rejection still requires native no-mutation regression testing.

## Lifecycle and boundaries

Do not construct a station component, write a detached DataTable row, or write its OptionalProperty cache. Use the existing RuneSchema-owned component. The native standalone/listen-host menu is expected to consume the updated row; the new binding/cache path still needs gameplay verification.

World journals use the real world GUID, never a character name. Clear catalog snapshots on travel and keep no persistent controller/pawn references. Startup catch-up is bounded; ready/pickup/learn events are coalesced after 500 ms. There is no per-frame full-object scan.

`services/trading.lua` and its atomic backend tests are a separate domain prototype, not the production native transaction path. Those tests are not native atomicity or deduplication evidence.

The server-side discovery union exists, but dynamic row/recipe transport and identity matching on remote co-op clients are not implemented. Multiplayer must not be advertised as supported until that work and host/client tests are complete.
