local Native = require("merchant.integrations.native_shop")
local Dragonwilds = {}
local started, queued, generation = false, false, 0
local hooks, snapshot = {}, nil

local function log(message) print("[DragonwildsMerchant] " .. message .. "\n") end

function Dragonwilds.initialize(config, context)
    if started then return true end
    if not context or not context.Root or context.Owner ~= "DragonwildsMerchant" then
        return false, "RuneSchema Lua companion context is missing; install the complete parent add-on."
    end
    local root = context.Root
    local function refresh(controller)
        local ok, result = pcall(Native.refresh, root, controller, config)
        if ok then
            snapshot = result
            log("Catalog ready: " .. result.entries .. " discovered offers, " .. result.sellable
                .. " sellable items, " .. result.rejected .. " rejected products; world=" .. result.world_id)
        else
            snapshot = nil
            pcall(Native.clear)
            log("Catalog blocked: " .. tostring(result))
        end
        return ok
    end
    local function warmup()
        for _, controller in ipairs(Native.controllers()) do
            if controller:IsLocalController() then refresh(controller); return end
        end
        local controllers = Native.controllers()
        if controllers[1] then refresh(controllers[1]) end
    end
    local function queue()
        if queued then return end
        queued = true
        local current = generation
        ExecuteWithDelay(500, function()
            if current ~= generation then return end
            ExecuteInGameThread(function()
                if current ~= generation then return end
                queued = false
                local ok, problem = pcall(warmup)
                if not ok then log("Warmup deferred: " .. tostring(problem)) end
            end)
        end)
    end
    local function hook(path, pre, post)
        assert(StaticFindObject(path):IsValid(), "required function unavailable: " .. path)
        local a, b = RegisterHook(path, pre, post)
        assert(a and b, "failed to register hook: " .. path)
        hooks[#hooks + 1] = {path, a, b}
    end
    local function craft_guard(context_param, station_param, recipe_param, count_param, bonus_param, xp_param, bonus_xp_param, inventories_param)
        local station, recipe = station_param:get(), recipe_param:get()
        if not Native.is_merchant(station) and not Native.own_recipe(recipe) then return end
        local ok, problem = pcall(function()
            local controller = context_param:get():GetOwner()
            Native.check_buy(controller, station, recipe, count_param:get(), snapshot, config)
            inventories_param:set({controller:GetInventory()})
        end)
        -- No shop request may award bonus output or crafting XP.
        bonus_param:set(0); xp_param:set(0); bonus_xp_param:set(0)
        if not ok then
            count_param:set(0)
            log("Purchase refused: " .. tostring(problem))
        end
    end
    local function sell_guard(context_param, inventory_param, slot_param, station_param)
        local station = station_param:get()
        if not Native.is_merchant(station) then return end
        local ok, problem = pcall(function()
            Native.check_sell(context_param:get():GetOwner(), inventory_param:get(), slot_param:get(), station, snapshot, config)
        end)
        if not ok then
            slot_param:set(-1) -- Native invalid-slot sentinel, never remove or credit anything from Lua.
            log("Sale refused: " .. tostring(problem))
        end
    end
    local ok, problem = pcall(function()
        hook("/Script/Dominion.DominionPlayerController:Client_ToggleCraftingMenu", function(controller_param, station_param)
            local station = station_param:get()
            if not Native.is_merchant(station) then return end
            local ready = refresh(controller_param:get())
            if ready then
                local ok, problem = pcall(Native.bind, station)
                if not ok then
                    ready = false; snapshot = nil; pcall(Native.clear)
                    log("Merchant binding blocked: " .. tostring(problem))
                end
            end
            if not ready then
                -- Only our station is affected. Do not touch OptionalProperty.
                station.CachedLabeledRecipes, station.ValidRecipes = {}, {}
            end
        end)
        hook("/Script/Dominion.InventoryController:CraftRecipe", craft_guard)
        hook("/Script/Dominion.InventoryController:Server_CraftRecipe", craft_guard)
        hook("/Script/Dominion.InventoryController:Server_SellItemFromInventory", sell_guard)
        hook("/Script/Dominion.DominionPlayerController:BP_OnPlayerControllerReady", function() end, queue)
        hook("/Script/Dominion.ProgressComponent:Client_OnItemFirstPickup", function() end, queue)
        hook("/Script/Dominion.ProgressComponent:Client_HandleItemPickupsLoadedFromPersistence", function() end, queue)
        hook("/Script/Dominion.ProgressComponent:UnlockRecipes", function() end, queue)
        RegisterInitGameStatePostHook(function()
            generation, queued, snapshot = generation + 1, false, nil
            pcall(Native.clear)
            queue()
        end)
    end)
    if not ok then
        for _, entry in ipairs(hooks) do pcall(UnregisterHook, entry[1], entry[2], entry[3]) end
        hooks = {}
        return false, tostring(problem)
    end
    started = true
    -- A bounded startup catch-up covers a companion loaded after player-ready.
    for _, delay in ipairs({1000, 5000, 15000}) do
        ExecuteWithDelay(delay, function() if not snapshot then queue() end end)
    end
    log("Native Coin shop hooks registered. Waiting for an authority world/player.")
    return true
end

return Dragonwilds
