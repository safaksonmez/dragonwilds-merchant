# Dragonwilds Merchant

**Version `0.2.0-dev.4` — experimental; gameplay regression testing is pending.**

The mod defines a fixed Coin Merchant in Bramblemead Valley, a marker on the M map, and an authored table/crates/barrel setup. It references the Wise Old Man model and idle animation. Coin has its own persistent ItemData identity, separate from Soul Fragments; its current appearance is inherited from the donor item.

The NPC's presence and Coin persistence have been observed in game. The newest catalog fix, completed transactions, stall presentation, and animation playback are not yet verified. Remote co-op client catalog synchronization is not supported.

## Catalog and economy

On the authority, the catalog combines native pickup history and the outputs of learned recipes across current world participants. It excludes undiscovered items and the merchant's own transient recipes from discovery. History is stored per world GUID in `Data/discovery-v1-*.txt`. Only registered, currently loaded ItemData assets are considered; unloaded content is not guaranteed.

Discovered quest/bound products can appear for purchase; quest and player-bound items cannot be sold. Coin cannot be traded for itself. Stock is unlimited. Buy price is `10 + max(0, PowerLevel) * 2` Coin; sell price is 40% of the buy price, rounded down, minimum 1 Coin. Maximum trade quantity is 999; authority interaction distance is 600 Unreal centimeters.

Purchases use native recipes and sales use the native sell operation. Lua does not maintain a second wallet or repeat the native inventory exchange. Native capacity, atomicity, failure, and duplicate-request behavior still require gameplay tests. The separate domain-service tests do not prove those native guarantees.

## Dependencies

- A compatible [Dragonwilds UE4SS distribution](https://www.nexusmods.com/runescapedragonwilds/mods/4). Local research used `3.0.1 Beta f6d5f942`.
- [RuneSchema 0.8.0.3](https://github.com/gh0sted5456-us/RuneSchema/releases/tag/0.8.0.3), installed separately.
- For Vortex: the [Dragonwilds game extension](https://www.nexusmods.com/site/mods/1273), with RuneSchema JSON package support. A clean Vortex installation has not been tested.

## Build the install archive

Run from the repository root with Python and PowerShell 7:

```powershell
python -m pip install --target mods/merchant/local/python -r mods/merchant/requirements-dev.txt
python mods/merchant/scripts/test.py
pwsh -NoProfile -File mods/merchant/scripts/package.ps1 -Force
```

The ZIP contains one root folder:

```text
DragonwildsMerchant/
  assets/10-coin.json
  npc/10-bramblemead-merchant.json
  npc/20-bramblemead-stall.json
  vendors/10-coin-store.json
  ue4ss/DragonwildsMerchant/
    Scripts/main.lua
    Scripts/merchant/...
    Data/README.txt
```

`src/DragonwildsMerchant` is the single runtime source. `mod.json` is repository metadata, not a loader manifest. Packaging verifies allowed paths, JSON, the required storefront contract, and ZIP entry SHA256 values. It does not prove native game behavior or Vortex compatibility.

## Install

Vortex: install the dependencies, add the generated ZIP using **Install From File**, confirm that it is identified as a **RuneSchema mod**, enable it, and deploy. Keep staging and the game on the same drive. The intended target is:

```text
RSDragonwilds/Binaries/Win64/ue4ss/Mods/RuneSchema/mods/DragonwildsMerchant/
```

Manual: with the game closed, copy the ZIP's `DragonwildsMerchant` folder into `ue4ss/Mods/RuneSchema/mods/`. Enable `DragonwildsMerchant : 1` in the RuneSchema load-order list. Do not also install a top-level `ue4ss/Mods/DragonwildsMerchant` copy; duplicate Lua package names are rejected. Back up and remove the old top-level Lua scaffold when upgrading from 0.1.

Start the game normally; PowerShell is not required to launch it. Look for `[DragonwildsMerchant] Native Coin shop hooks registered` and, after loading an authority world, `Catalog ready: ... discovered offers`. `Catalog blocked` reports why the catalog was rejected. The Xbox WinGDK layout and other storefronts have not been tested.

## Configure, update, and remove

Settings live in `ue4ss/DragonwildsMerchant/Scripts/merchant/config.lua`. Authored NPC/stall positions are in the parent `npc/*.json` files. Restart after changing runtime files or definitions.

Before updating, back up the config and `ue4ss/DragonwildsMerchant/Data/discovery-v1-*.txt` journals. Config changes are not merged automatically; compare your settings with the new defaults. Runtime journals are not included in the install ZIP. Move the matching discovery journal when moving a world to another host.

To remove: close the game, back up config/journals, then uninstall and deploy through Vortex or remove only the manually installed parent folder. Keep shared RuneSchema/UE4SS files and other mods. Coin is a custom asset and cannot resolve without this mod; retain the mod for saves containing Coin, or remove/spend the custom item first and keep a save backup.

## Development tools

```powershell
pwsh -NoProfile -File mods/merchant/scripts/deploy-local.ps1 -GameRoot '<game-root>'
```

The deployment tool requires the game to be closed, backs up the current add-on, preserves runtime journals, and verifies installed hashes. It does not control the game or modify shared loader settings.

The F8/F9 reflection probe and offline Coin grant tool are development utilities and never enter the install ZIP. The public runtime does not grant free Coin. See [design](docs/design.md), [compatibility](docs/compatibility.md), [testing](docs/testing.md), and [changelog](CHANGELOG.md).

No project license has been selected; no Nexus release has been published.
