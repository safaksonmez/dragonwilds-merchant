# Dragonwilds Merchant

An experimental **Coin merchant mod for RuneScape: Dragonwilds**, built with RuneSchema and a UE4SS Lua companion. The intended distribution channel is Nexus Mods, with a Vortex-compatible installation archive.

**Current version: `0.3.0-dev.2`. This is a development prototype, not a verified gameplay release.** The merchant has appeared in game and the separate Coin item persists across reloads. The latest dynamic catalog fix is awaiting in-game verification. Buying, selling, transaction failure behavior, animations, and stall presentation still require testing. Remote co-op client catalog synchronization is not implemented.

## Intended behavior

- One fixed merchant in **Bramblemead Valley**, with a map marker; more regions can be added later.
- A separate inventory currency named **Coin**.
- A catalog restricted to items already picked up or unlocked through learned recipes.
- Discovery history shared across the authority's world participants and stored per world GUID.
- Native-authored recipes and merchant rows, with Lua discovery gates and authority checks.
- A verified 572-item native roster, currently priced at 10 Coin to buy / 4 Coin to sell.
- A neutral NPC using existing game assets, an idle animation, and a small stall setup.

## Get started

See the [merchant README](mods/merchant/README.md) for dependencies, installation, configuration, updates, and removal. [Compatibility](mods/merchant/docs/compatibility.md) distinguishes verified game observations from source research; [testing](mods/merchant/docs/testing.md) lists the outstanding gameplay checks.

```powershell
python -m pip install --target mods/merchant/local/python -r mods/merchant/requirements-dev.txt
python mods/merchant/scripts/test.py
pwsh -NoProfile -File mods/merchant/scripts/package.ps1 -Force
```

The install archive is generated at `mods/merchant/dist/DragonwildsMerchant-0.3.0-dev.2.zip`, with a SHA256 file. The GitHub source download is **not** a Vortex install archive.

## Repository layout

```text
mods/merchant/
  src/DragonwildsMerchant/   # Single source of truth for installable files
  docs/                     # Design, compatibility, and test records
  scripts/                  # Local validation, packaging, and deployment tools
  tests/                    # Lua domain and integration-contract regressions
  tools/                    # Development-only reflection probe
```

Local dependencies, game files, extracted assets, dumps, saves, machine-specific paths, and generated ZIPs are excluded from version control. Loader binaries are installed separately. See [AGENTS.md](AGENTS.md) for contributor instructions and [the changelog](mods/merchant/CHANGELOG.md) for development history.

## Credits and licensing

This is an independent community project, not affiliated with Jagex. RuneScape: Dragonwilds assets are referenced by path and are not redistributed. [RuneSchema](https://github.com/gh0sted5456-us/RuneSchema), [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), and the [Dragonwilds Vortex extension](https://www.nexusmods.com/site/mods/1273) are separate projects with their own terms.

A project license has not been selected. Public source availability does not grant an additional redistribution license. No Nexus release has been published.
