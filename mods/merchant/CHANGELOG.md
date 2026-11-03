# Changelog

## 0.3.0-dev.2 — 2026-11-03

- Fix raw startup ordering: create the native row without hard Coin references; defer native SellableItems patching until the currency clone exists.
- Use RuneSchema's supported, game-thread file reload with a mod-owned generated patch, startup reset, bounded acknowledgement retries, and currency/price readback. This requires the documented shared `enableAutoReload=true` setting; no shared config enters the ZIP.
- Explicitly disable Repair/Ascension on the native component as well as the row.
- Add deferred-file lifecycle tests, startup dependency checks, and package checks preventing early hard Coin references. Native gameplay verification remains pending.
- Follow-up validation: native reload completed, 333 discovered offers survived reopening, and the tester confirmed a purchase. Exact transaction deltas and selling remain unverified.

## 0.3.0-dev.1 — 2026-11-03

- Replace Lua DataTable writes and runtime recipe construction with RuneSchema-authored `/raw` and `/recipes` content. The installed Lua binding left AddRow(table) fields empty; direct detached-row mutation crashed UE4SS during diagnosis. That diagnostic is disabled.
- Generate 572 native buy recipes and matching sell records from verified build-248854 ItemData references. Only asset paths/definitions ship, never cooked game content or discovery histories.
- Bind the native row through RuneSchema VendorProperties. Lua now reads the row/recipe fields, validates identities/amounts, and grants or revokes only discovered shop availability.
- Use fixed prototype prices of 10 Coin buy / 4 Coin sell; regeneration is required to change native prices. Unlisted items and mismatched prices fail closed.
- Add generated-content consistency checks and prohibit Lua AddRow/StaticConstructObject calls in runtime validation. Native recipe/row loading and gameplay still require an in-game regression pass.

## 0.2.0-dev.4 — 2026-11-03

- Fix one discovered item outside the assumed 0–100 PowerLevel range aborting the entire merchant catalog with `invalid_power_level`.
- Accept signed native int32 levels for pricing, use the base tier below zero, and check price overflow before scaling. Reject malformed or overflowing products individually without inventing fallback prices; invalid economy settings still block the catalog.
- Log excluded product paths, raw level values, and reasons, with a bounded per-refresh diagnostic count.
- Add signed-level, malformed-value, overflow, and partial-catalog regressions; exercise negative and above-100 levels through the full Lua catalog flow. 33 local checks plus the flow regression pass. Gameplay verification remains pending.

## 0.2.0-dev.3 — 2026-11-03

- Fix catalog generation aborting with `attempt to index a number value (local 'output')`: RecipeData.ItemsCreated uses the TArray `(index, element)` callback signature, unlike TSet's single-element callback.
- Add a full Lua catalog-flow regression covering pickup history, learned outputs, hidden-item filtering, transient unlock sets, native row generation, and reopening. The existing 28 checks and new flow regression pass; native gameplay verification remains pending.

## 0.2.0-dev.2 — 2026-11-03

- Restore the mandatory `Items: []` storefront field so RuneSchema resolves the NPC's store reference.
- Separate the provider-owned empty bootstrap row from the dynamic Lua catalog row and bind the owned station before menu entry.
- Replace unsupported UE4SS `GetPathName()` calls with an adapter based on documented `GetFullName()` output.
- Validate required storefront fields during packaging and add adapter regressions, bringing the local suite to 28 checks. The NPC appeared in the subsequent game test; catalog iteration still failed and was addressed in dev.3.

## 0.2.0-dev.1 — 2026-11-03

- Migrate from a Lua scaffold to a RuneSchema add-on with a nested Lua companion.
- Register a separate persistent Coin item; no automatic free currency in the public runtime.
- Define the fixed Bramblemead Valley NPC/map marker, idle animation, and table/crates/barrel setup.
- Add world-scoped discovery journals, pickup/learned-recipe discovery, and protection against self-unlocking shop outputs.
- Add native buying/selling integration and authority, distance, quantity, balance, capacity, and protected-item checks.
- Add ZIP hash verification, backed-up local deployment, and 26 domain tests.
- Native gameplay regression, remote client catalog synchronization, and Vortex validation remain incomplete.

## 0.1.0-dev.1 — 2026-11-03

- Add the UE4SS Lua scaffold, domain modules, initial packaging, and development documentation.
