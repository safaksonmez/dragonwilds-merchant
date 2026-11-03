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

RuneSchema supplies registered Coin, placement, visuals/animation, map markers, and interaction. The Lua companion reads discovery, persists a per-world journal, builds `DWM_CoinMerchant_v1`, and creates transient buy recipes in categories of up to 100 products.

RuneSchema requires `Items: []` in the storefront record. The provider owns `DWM_CoinMerchant_bootstrap_v1`; Lua owns a different dynamic row and binds only its station before menu entry. Removing Items makes the store invalid and disables the merchant. Keeping the rows separate prevents provider refreshes from emptying the Lua-owned catalog.

Shop recipes enter `RecipesUnlockedThatShouldNotPersist` before `RecipesUnlocked`. The first is a persistence exclusion marker; the second controls visibility. Cleanup only targets the mod's exact transient recipe path/name pattern. Vanilla learned recipes remain untouched.

Coin balances belong to native inventory. Lua does not repeat consumption or output. Guards check authority, world, distance, quantity, server-owned recipe prices, balance, capacity, item ownership, protected items, and Coin overflow. Invalid purchases zero Count/BonusCount; invalid sales use the native invalid-slot sentinel. These rejection paths still need proof of zero mutation in game.

Pricing uses `base_price + max(0, PowerLevel) * price_per_power_level`. ItemData's signed int32 level is not restricted to the 0–100 range used by player-level gates. Negative values receive the base price as an explicit economy policy. Malformed metadata or an overflowing quote excludes that product with diagnostics; it must not blank other discovered products. Invalid global economy settings still block catalog generation.

## Lifecycle and boundaries

Do not construct a station component or write its OptionalProperty cache. Use the existing RuneSchema-owned component. The native standalone/listen-host menu is expected to consume the updated row; the new binding/cache path still needs gameplay verification.

World journals use the real world GUID, never a character name. Clear catalog snapshots on travel and keep no persistent controller/pawn references. Startup catch-up is bounded; ready/pickup/learn events are coalesced after 500 ms. There is no per-frame full-object scan.

`services/trading.lua` and its atomic backend tests are a separate domain prototype, not the production native transaction path. Those tests are not native atomicity or deduplication evidence.

The server-side discovery union exists, but dynamic row/recipe transport and identity matching on remote co-op clients are not implemented. Multiplayer must not be advertised as supported until that work and host/client tests are complete.
