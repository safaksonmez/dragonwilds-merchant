local Catalog = require("merchant.services.native_catalog")
local Content = require("merchant.data.native_content")
local Store = require("merchant.integrations.discovery_store")
local V = require("merchant.domain.values")
local Native = {}

Native.coin_path = "/Game/RuneSchema/DragonwildsMerchant/Items/dwm_coin.dwm_coin"
Native.table_path = "/Game/Gameplay/World/Vendors/DT_VendorDataTable.DT_VendorDataTable"
Native.row_name = "DWM_CoinMerchant_v1"
Native.bootstrap_row_name = "DWM_CoinMerchant_bootstrap_v1"

function Native.valid(object)
    return object ~= nil and object:IsValid()
end

function Native.path(object)
    -- GetPathName is not exposed by this UE4SS build. GetFullName is the
    -- documented binding and returns "Class /Package.Object:Subobject".
    local path = object:GetFullName():match("^%S+ (.+)$")
    assert(path, "unexpected UObject full-name format")
    return path
end

local function text(value) return value:ToString() end
local function asset(path)
    local object = StaticFindObject(path)
    if not Native.valid(object) then object = LoadAsset(path) end
    assert(Native.valid(object), "asset unavailable: " .. path)
    return object
end

function Native.world_id(controller)
    assert(Native.valid(controller) and Native.valid(controller.Pawn), "player not ready")
    local world = controller.Pawn:GetWorld()
    assert(Native.valid(world) and Native.valid(world.GameState), "world not ready")
    local guid = world.GameState.WorldInfo.WorldId
    local id = string.format("%08x%08x%08x%08x", guid.A & 0xffffffff, guid.B & 0xffffffff,
        guid.C & 0xffffffff, guid.D & 0xffffffff)
    assert(id ~= string.rep("0", 32), "world has no stable persistence id")
    return id
end

function Native.controllers(world_id)
    local result = {}
    for _, controller in ipairs(FindAllOf("DominionPlayerController") or {}) do
        local ok, id = pcall(Native.world_id, controller)
        if ok and controller:HasAuthority() and (not world_id or id == world_id) then
            result[#result + 1] = controller
        end
    end
    return result
end

local function own_recipe(recipe)
    if not Native.valid(recipe) then return false end
    local path = Native.path(recipe)
    return path:match("^/Game/RuneSchema/DragonwildsMerchant/Recipes/RSRecipe_DWM_Buy_") ~= nil
        or path:match("^/Engine/Transient%.DWM_Buy_%x+$") ~= nil
end

function Native.is_merchant(station)
    if not Native.valid(station) then return false end
    local handle = station.CraftingDataRowHandle
    local name = text(handle.RowName)
    return (name == Native.row_name or name == Native.bootstrap_row_name) and Native.valid(handle.DataTable)
        and Native.path(handle.DataTable) == Native.table_path
end

function Native.bind(station)
    -- RuneSchema VendorProperties binds this handle natively. Never write a
    -- detached UScriptStruct or rebuild a DataTable through this Lua binding.
    assert(Native.is_merchant(station), "not an owned merchant station")
    assert(text(station.CraftingDataRowHandle.RowName) == Native.row_name,
        "RuneSchema native merchant row binding is not ready")
end

local function check_distance(controller, station, limit)
    local owner = station:GetOwner()
    assert(Native.valid(owner) and Native.valid(controller.Pawn), "merchant or pawn unavailable")
    assert(Native.path(owner:GetWorld()) == Native.path(controller.Pawn:GetWorld()), "different worlds")
    local a, b = owner:K2_GetActorLocation(), controller.Pawn:K2_GetActorLocation()
    local distance = (a.X - b.X)^2 + (a.Y - b.Y)^2 + (a.Z - b.Z)^2
    assert(distance <= limit^2, "merchant out of range")
end

local function read_items()
    local facts, objects, duplicates = {}, {}, {}
    for _, item in ipairs(FindAllOf("ItemData") or {}) do
        if Native.valid(item) then
            local path = Native.path(item)
            if path ~= Native.coin_path and (path:match("^/Game/Gameplay/") or path:match("^/Game/RuneSchema/")) then
                local id, name = text(item.PersistenceID), text(item.Name)
                if #id == 22 and id:match("^[%w_-]+$") and name ~= "" and item.MaxStackSize > 0 then
                    if objects[id] and Native.path(objects[id]) ~= path then duplicates[id] = true end
                    objects[id] = item
                    facts[#facts + 1] = {id = id, name = name, path = path, power_level = item.PowerLevel,
                        sellable = not item:IsQuestItem() and not item:IsBoundToPlayer()}
                end
            end
        end
    end
    assert(next(duplicates) == nil, "conflicting native item persistence ids; refusing catalog")
    assert(#facts > 0 and #facts <= 32768, "native item registry unavailable or exceeds bound")
    return facts, objects
end

local function discoveries(controllers, facts, objects)
    local found = {}
    for _, controller in ipairs(controllers) do
        local progress = controller:GetProgressComponent()
        assert(Native.valid(progress), "player progress unavailable")
        for _, fact in ipairs(facts) do
            if progress:HasPickedUpItem(objects[fact.id]) then found[fact.id] = true end
        end
        -- Existing learned recipes count as unlocked content. Our temporary
        -- store offers must never recursively unlock their own outputs.
        progress.RecipesUnlocked:ForEach(function(parameter)
            local recipe = parameter:get()
            if Native.valid(recipe) and not own_recipe(recipe) then
                -- TArray provides (index, element); TSet above provides only
                -- (element). Treating the first TArray argument as an item
                -- aborts the entire catalog even when pickup history is valid.
                recipe.ItemsCreated:ForEach(function(_, output)
                    local item = output:get().ItemData
                    if Native.valid(item) then
                        local id = text(item.PersistenceID)
                        if objects[id] and Native.path(objects[id]) == Native.path(item) then found[id] = true end
                    end
                end)
            end
        end)
    end
    return found
end

local function remove_own_unlocks(progress)
    local remove = {}
    progress.RecipesUnlocked:ForEach(function(parameter)
        local recipe = parameter:get()
        if own_recipe(recipe) then remove[#remove + 1] = recipe end
    end)
    for _, recipe in ipairs(remove) do
        progress.RecipesUnlocked:Remove(recipe)
        progress.RecipesUnlockedThatShouldNotPersist:Remove(recipe)
    end
end

function Native.clear()
    -- Fail closed by revoking only our shop availability. The static native row
    -- is never mutated from Lua; ordinary learned recipes remain untouched.
    for _, controller in ipairs(Native.controllers()) do
        local progress = controller:GetProgressComponent()
        if Native.valid(progress) then remove_own_unlocks(progress) end
    end
end

local function verify_recipe(recipe, entry)
    assert(#recipe.ItemsConsumed == 1 and #recipe.ItemsCreated == 1, "native recipe item amounts missing")
    assert(Native.path(recipe.ItemsConsumed[1].ItemData) == Native.coin_path
        and recipe.ItemsConsumed[1].Count == entry.buy_price
        and Native.path(recipe.ItemsCreated[1].ItemData) == entry.path
        and recipe.ItemsCreated[1].Count == 1, "native recipe did not retain its authored price/output")
end

function Native.refresh(root, controller, config)
    assert(controller:HasAuthority(), "authority required; client stock synchronization is not yet supported")
    local world_id = Native.world_id(controller)
    local dt, coin = asset(Native.table_path), asset(Native.coin_path)
    assert(text(coin.PersistenceID) == "o-67GWCBTUeTPasJ-o_1Sw", "Coin identity mismatch")
    local facts, objects = read_items()
    local discovered = Store.merge(root, world_id, discoveries(Native.controllers(world_id), facts, objects))
    local entries, rejected = Catalog.build(facts, discovered, config.economy)
    local row = dt:FindRow(Native.row_name)
    assert(row and row.bIsVendor and #row.SellableItems == Content.product_count,
        "RuneSchema native merchant row is missing or incomplete")
    local count = 0
    row.LabeledRecipes:ForEach(function(_, group) count = count + #group:get().Collection end)
    assert(count == Content.product_count, "RuneSchema native merchant categories are incomplete")
    local progress = controller:GetProgressComponent()
    remove_own_unlocks(progress)
    local approved, total, sellable = {}, 0, 0
    for _, entry in ipairs(entries) do
        local definition = Content.by_item[entry.path]
        if definition then
            assert(entry.buy_price == definition.buy_price and entry.sell_price == definition.sell_price,
                "economy settings differ from native content; regenerate recipes/row before changing prices")
            local recipe = asset(definition.path)
            assert(own_recipe(recipe) and text(recipe.PersistenceID) == definition.id, "native recipe identity mismatch")
            verify_recipe(recipe, entry)
            -- The persistence exclusion marker must be in place before visible
            -- availability. Native recipe assets and row data are read-only here.
            progress.RecipesUnlockedThatShouldNotPersist:Add(recipe)
            progress.RecipesUnlocked:Add(recipe)
            assert(progress.RecipesUnlocked:Contains(recipe)
                and progress.RecipesUnlockedThatShouldNotPersist:Contains(recipe), "native unlock readback failed")
            approved[Native.path(recipe)] = entry
            total = total + 1
            if entry.sellable then sellable = sellable + 1 end
        else
            rejected[#rejected + 1] = {path=entry.path, reason="not_in_verified_native_roster"}
        end
    end
    for index = 1, math.min(5, #rejected) do
        local entry = rejected[index]
        print("[DragonwildsMerchant] Product excluded: " .. entry.path .. "; " .. entry.reason .. "\n")
    end
    return {world_id=world_id, approved=approved, entries=total, sellable=sellable, rejected=#rejected}
end

-- Native inventory code remains the sole owner of consumption/output, capacity
-- and balance checks. This guard never performs a second exchange in Lua.
function Native.check_buy(controller, station, recipe, quantity, snapshot, config)
    assert(Native.valid(controller) and controller:HasAuthority(), "authority required")
    assert(Native.is_merchant(station), "merchant station required")
    check_distance(controller, station, config.max_trade_distance)
    assert(snapshot and snapshot.world_id == Native.world_id(controller), "stale world catalog")
    assert(Native.valid(recipe), "recipe missing")
    local entry = snapshot.approved[Native.path(recipe)]
    assert(entry, "recipe not in discovered catalog")
    assert(V.integer(quantity, 1, config.max_trade_quantity), "invalid trade quantity")
    assert(entry.buy_price * quantity <= V.MAX_INTEGER, "price overflow")
    local inventory = controller:GetInventory()
    local coin, item = asset(Native.coin_path), asset(entry.path)
    assert(inventory:GetNumItemsByData(coin) >= entry.buy_price * quantity, "insufficient Coin")
    assert(inventory:CanAddItemByData(item, quantity), "inventory full")
    -- Read server-owned native recipe fields; never accept a supplied price.
    assert(#recipe.ItemsConsumed == 1 and #recipe.ItemsCreated == 1, "unexpected recipe shape")
    assert(Native.path(recipe.ItemsConsumed[1].ItemData) == Native.coin_path
        and recipe.ItemsConsumed[1].Count == entry.buy_price
        and Native.path(recipe.ItemsCreated[1].ItemData) == entry.path
        and recipe.ItemsCreated[1].Count == 1, "recipe was modified")
    return true
end

function Native.check_sell(controller, inventory, slot_index, station, snapshot, config)
    assert(Native.valid(controller) and controller:HasAuthority(), "authority required")
    assert(Native.is_merchant(station), "merchant station required")
    check_distance(controller, station, config.max_trade_distance)
    assert(snapshot and snapshot.world_id == Native.world_id(controller), "stale world catalog")
    assert(V.integer(slot_index, 0, 100000), "invalid inventory slot")
    assert(Native.valid(inventory) and Native.path(inventory) == Native.path(controller:GetInventory()),
        "player inventory required")
    local item = inventory:GetItemFromSlot(slot_index)
    assert(Native.valid(item) and Native.valid(item.ItemData), "item unavailable")
    local data, found = item.ItemData, nil
    for _, entry in pairs(snapshot.approved) do
        if entry.path == Native.path(data) then found = entry; break end
    end
    assert(found and found.sellable and not data:IsBoundToPlayer() and not data:IsQuestItem(), "item cannot be sold")
    local count = item.Count
    assert(V.integer(count, 1, V.MAX_INTEGER), "invalid item count")
    local balance = inventory:GetNumItemsByData(asset(Native.coin_path))
    assert(count <= math.floor((V.MAX_INTEGER - balance) / found.sell_price), "Coin overflow")
    assert(inventory:CanAddItemByData(asset(Native.coin_path), count * found.sell_price), "no room for Coin")
    return true
end

Native.own_recipe = own_recipe
return Native
