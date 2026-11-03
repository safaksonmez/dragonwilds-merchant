-- Contract regression for the complete Lua catalog path. Uses the documented
-- TSet(element) vs TArray(index, element) signatures; not a native game test.
local Native = require("merchant.integrations.native_shop")
local Store = require("merchant.integrations.discovery_store")
local config = require("merchant.config")
local identities = {"abcdefghijklmnopqrstuv", "ABCDEFGHIJKLMNOPQRSTUV", "0123456789012345678901"}

local function parameter(value) return {get = function() return value end} end
local function string_value(value) return {ToString = function() return value end} end
local function object(path, class)
    return {
        IsValid = function() return true end,
        GetFullName = function() return (class or "ItemData") .. " " .. path end,
    }
end
local function array(values)
    local a = values or {}
    function a:ForEach(callback)
        for index, value in ipairs(self) do
            if callback(index, parameter(value)) == true then return end
        end
    end
    return a
end
local function set(values)
    local entries = values or {}
    return {
        ForEach = function(_, callback)
            for _, value in ipairs(entries) do if callback(parameter(value)) == true then return end end
        end,
        Add = function(_, value)
            for _, existing in ipairs(entries) do if existing == value then return end end
            entries[#entries + 1] = value
        end,
        Contains = function(_, value)
            for _, existing in ipairs(entries) do if existing == value then return true end end
            return false
        end,
        Remove = function(_, value)
            for index = #entries, 1, -1 do if entries[index] == value then table.remove(entries, index) end end
        end,
    }
end

local globals = {"StaticFindObject", "LoadAsset", "FindAllOf", "StaticConstructObject", "FText", "FName"}
local previous = {}; for _, name in ipairs(globals) do previous[name] = _G[name] end
local old_merge = Store.merge
local ok, problem = pcall(function()
    local registry, rows, items = {}, {}, {}
    for i, name in ipairs({"PickedUp", "Learned", "Hidden"}) do
        local item = object("/Game/Gameplay/Test/"..name.."."..name)
        item.PersistenceID, item.Name = string_value(identities[i]), string_value(name)
        item.PowerLevel, item.MaxStackSize = ({-1, 150, 0})[i], 99
        item.IsQuestItem, item.IsBoundToPlayer = function() return false end, function() return false end
        items[i] = item; registry[Native.path(item)] = item
    end
    local coin = object(Native.coin_path)
    coin.PersistenceID = string_value("o-67GWCBTUeTPasJ-o_1Sw")
    registry[Native.coin_path] = coin
    local dt = object(Native.table_path, "DataTable")
    function dt:AddRow(name, row) rows[name] = row end
    function dt:FindRow(name) return rows[name] end
    registry[Native.table_path] = dt
    registry["/Script/Dominion.RecipeData"] = object("/Script/Dominion.RecipeData", "Class")
    registry["/Engine/Transient"] = object("/Engine/Transient", "Package")
    local system = object("/Script/Engine.Default__KismetSystemLibrary", "KismetSystemLibrary")
    function system:Conv_ObjectToSoftObjectReference(value) return parameter(value) end
    registry["/Script/Engine.Default__KismetSystemLibrary"] = system

    local learned = object("/Game/Gameplay/Test/LearnedRecipe.LearnedRecipe", "RecipeData")
    learned.ItemsCreated = array({{ItemData=items[2], Count=1}})
    -- Previously opened shop offers must never discover an otherwise hidden item.
    local old_shop = object("/Engine/Transient.DWM_Buy_1234", "RecipeData")
    old_shop.ItemsCreated = array({{ItemData=items[3], Count=1}})
    local progress = object("/Test.Progress", "ProgressComponent")
    progress.RecipesUnlocked = set({learned, old_shop})
    progress.RecipesUnlockedThatShouldNotPersist = set({old_shop})
    function progress:HasPickedUpItem(item) return item == items[1] end
    local world = object("/Game/Maps/Test.Test", "World")
    world.GameState = object("/Game/Maps/Test.Test:State", "GameState")
    world.GameState.WorldInfo = {WorldId={A=1,B=2,C=3,D=4}}
    local controller = object("/Test.Controller", "DominionPlayerController")
    controller.Pawn = object("/Test.Pawn", "Pawn")
    function controller.Pawn:GetWorld() return world end
    function controller:HasAuthority() return true end
    function controller:GetProgressComponent() return progress end

    _G.StaticFindObject = function(path) return registry[path] end
    _G.LoadAsset = function(path) error("unexpected asset load: "..path) end
    _G.FindAllOf = function(class)
        if class == "ItemData" then return items end
        assert(class == "DominionPlayerController"); return {controller}
    end
    _G.StaticConstructObject = function(_, _, name)
        local recipe = object("/Engine/Transient."..name, "RecipeData")
        -- Unreal FString property assignments are read back as FString userdata.
        recipe = setmetatable(recipe, {__newindex=function(self, key, value)
            if key == "PersistenceID" or key == "InternalName" then value = string_value(value) end
            rawset(self, key, value)
        end})
        registry[Native.path(recipe)] = recipe
        return recipe
    end
    _G.FText, _G.FName = string_value, function(value) return value end
    Store.merge = function(_, world_id, discovered)
        assert(world_id == "00000001000000020000000300000004")
        assert(discovered[identities[1]] and discovered[identities[2]])
        assert(not discovered[identities[3]], "shop recipes must not unlock hidden outputs")
        return discovered
    end

    local result = Native.refresh("unused-test-root", controller, config)
    assert(result.entries == 2 and result.sellable == 2)
    local row = assert(rows[Native.row_name])
    assert(#row.LabeledRecipes == 1 and #row.LabeledRecipes[1].Collection == 2)
    assert(#row.SellableItems == 2)
    local count = 0
    for path, entry in pairs(result.approved) do
        count = count + 1
        local recipe = registry[path]
        assert(progress.RecipesUnlocked:Contains(recipe))
        assert(progress.RecipesUnlockedThatShouldNotPersist:Contains(recipe))
        assert(recipe.ItemsConsumed[1].ItemData == coin and recipe.ItemsConsumed[1].Count == entry.buy_price)
        assert(recipe.ItemsCreated[1].Count == 1)
        assert(entry.id ~= identities[3])
    end
    assert(count == 2 and progress.RecipesUnlocked:Contains(learned))
    assert(not progress.RecipesUnlocked:Contains(old_shop))
    -- Opening again must reuse owned recipes without duplicating offers.
    assert(Native.refresh("unused-test-root", controller, config).entries == 2)
end)
for _, name in ipairs(globals) do _G[name] = previous[name] end
Store.merge = old_merge
assert(ok, problem)
print("PASS full Lua catalog flow: pickup + learned outputs, hidden-item gate, transient unlocks, native row, reopen")
