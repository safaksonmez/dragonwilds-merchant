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
local Content = require("merchant.data.native_content")
local old_content, old_count = Content.by_item, Content.product_count
local old_merge = Store.merge
local Sales = require("merchant.integrations.deferred_sales")
local old_ensure = Sales.ensure
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
    function dt:AddRow() error("Lua DataTable writes are forbidden") end
    function dt:FindRow(name) return rows[name] end
    registry[Native.table_path] = dt
    Content.by_item, Content.product_count = {}, 2
    local collection = {}
    for i = 1, 2 do
        local name = "RSRecipe_DWM_Buy_test"..i
        local path = "/Game/RuneSchema/DragonwildsMerchant/Recipes/"..name.."."..name
        local recipe = object(path,"RecipeData")
        recipe.PersistenceID = string_value(identities[i])
        recipe.ItemsConsumed = array({{ItemData=coin,Count=10}})
        recipe.ItemsCreated = array({{ItemData=items[i],Count=1}})
        registry[path] = recipe
        Content.by_item[Native.path(items[i])] = {path=path,id=identities[i],buy_price=10,sell_price=4}
        collection[#collection+1] = parameter(recipe)
    end
    rows[Native.row_name] = {bIsVendor=true,
        LabeledRecipes=array({{Collection=collection}}),
        SellableItems=array({{Currency=coin,CurrencyPerItem=4},{Currency=coin,CurrencyPerItem=4}})}
    Sales.ensure = function(_, actual, expected) return actual == expected end

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
    _G.StaticConstructObject = function() error("Lua recipe construction is forbidden") end
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
    Native.clear()
    for path in pairs(result.approved) do
        assert(not progress.RecipesUnlocked:Contains(registry[path]))
    end
    assert(progress.RecipesUnlocked:Contains(learned))
end)
for _, name in ipairs(globals) do _G[name] = previous[name] end
Store.merge = old_merge
Sales.ensure = old_ensure
Content.by_item, Content.product_count = old_content, old_count
assert(ok, problem)
print("PASS full Lua catalog flow: pickup + learned outputs, hidden-item gate, transient unlocks, read-only native row, reopen, revoke; forbidden Lua writes guarded")
