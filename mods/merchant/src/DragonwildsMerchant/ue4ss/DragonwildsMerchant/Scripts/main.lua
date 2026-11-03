local config = require("merchant.config")
local game = require("merchant.integrations.dragonwilds")

local function log(message)
    print("[DragonwildsMerchant] " .. message .. "\n")
end

if not config.enabled then
    log("Lua catalog disabled in config; disable the RuneSchema parent to remove the merchant too.")
    return
end

local ready, reason = game.initialize(config, RuneSchemaUE4SS and RuneSchemaUE4SS.Current)
if not ready then
    log("Gameplay unavailable: " .. reason)
    return
end

log("DragonwildsMerchant 0.3.0-dev.1 loaded; in-game regression testing required.")
