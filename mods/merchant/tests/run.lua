local State = require("merchant.domain.world_state")
local Catalog = require("merchant.data.catalog")
local Trading = require("merchant.services.trading")
local Pricing = require("merchant.services.pricing")
local V = require("merchant.domain.values")
local config = require("merchant.config")
local passed = 0

local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, fn)
    local ok, problem = pcall(fn)
    assert(ok, name .. ": " .. tostring(problem))
    passed = passed + 1
    print("PASS " .. name)
end

local function world(id)
    local persisted
    local function save(snapshot) persisted = V.copy(snapshot); return true end
    local state = State.new(id or "test-world", nil, save)
    return state, function() return State.new(id or "test-world", persisted, save) end
end
local function fixture()
    local state = world()
    local catalog = Catalog.new({
        {id = "test:wood", buy_price = 10, sell_price = 4},
        {id = "test:locked", buy_price = 30, sell_price = 12},
    })
    assert(state:merge_discoveries({"test:wood"}))
    local backend = {coins = 100, count = 5, revision = 0, receipts = {}, calls = 0, allowed = true}
    function backend:authorize(session, merchant) return self.allowed and merchant == "test-merchant" end
    function backend:receipt(_, id) return self.receipts[id] end
    function backend:snapshot() return {coins = self.coins, item_count = self.count, revision = self.revision} end
    function backend:can_receive() return not self.full end
    function backend:can_sell() return not self.protected end
    function backend:commit_exchange(_, plan)
        self.calls = self.calls + 1
        if self.fail then return false, "commit_rejected" end
        if self.stale then return false, "stale_inventory" end
        assert(plan.expected_revision == self.revision)
        local receipt = {fingerprint = plan.fingerprint, currency = plan.currency, total = math.abs(plan.coin_delta)}
        -- One atomic operation in this test double, not proof of native atomicity.
        self.coins, self.count, self.revision = self.coins + plan.coin_delta, self.count + plan.item_delta, self.revision + 1
        self.receipts[plan.request_id] = receipt
        return true, receipt
    end
    local session = {world_id = "test-world", player_id = "test-player"}
    local request = {id = "test-request", item_id = "test:wood", side = "buy", quantity = 2, merchant_id = "test-merchant"}
    return Trading.new(state, catalog, backend, config), backend, session, request, state, catalog
end

test("undiscovered items are absent from catalog", function()
    local _, _, _, _, state, catalog = fixture()
    local visible = catalog:visible(state)
    equal(#visible, 1); equal(visible[1].id, "test:wood")
end)
test("any participant discovery becomes world-wide and survives reload", function()
    local state, reload = world()
    assert(state:merge_discoveries({"test:alice-item"}))
    assert(state:merge_discoveries({"test:bob-item"}))
    local restored = reload()
    equal(restored:is_discovered("test:alice-item"), true)
    equal(restored:is_discovered("test:bob-item"), true)
end)
test("discoveries never leak between worlds", function()
    local a, b = world("world-a"), world("world-b")
    assert(a:merge_discoveries({"test:wood"})); equal(b:is_discovered("test:wood"), false)
    equal(pcall(State.new, "world-b", a:snapshot(), function() return true end), false)
end)
test("failed persistence does not unlock anything", function()
    local state = State.new("world", nil, function() return false end)
    equal(state:merge_discoveries({"test:wood"}), false)
    equal(state:is_discovered("test:wood"), false)
end)
test("catalog and state snapshots cannot mutate internal data", function()
    local _, _, _, _, state, catalog = fixture()
    state:snapshot().discoveries["test:locked"] = true
    catalog:get("test:wood").buy_price = 0
    equal(state:is_discovered("test:locked"), false); equal(catalog:get("test:wood").buy_price, 10)
end)
test("buy exchanges correct Coin and item amounts", function()
    local trade, backend, session, request = fixture()
    local ok, receipt = trade:execute(session, request)
    equal(ok, true); equal(receipt.currency, "Coin"); equal(backend.coins, 80); equal(backend.count, 7)
end)
test("sell earns Coin and consumes owned items", function()
    local trade, backend, session, request = fixture(); request.side = "sell"
    equal(trade:execute(session, request), true); equal(backend.coins, 108); equal(backend.count, 3)
end)
test("forged prices and balances are ignored", function()
    local trade, backend, session, request = fixture()
    request.price, request.coins = 0, 999999
    equal(trade:execute(session, request), true); equal(backend.coins, 80)
end)
test("hidden item cannot be bought by sending its ID directly", function()
    local trade, backend, session, request = fixture(); request.item_id = "test:locked"
    local ok, reason = trade:execute(session, request)
    equal(ok, false); equal(reason, "item_not_discovered"); equal(backend.calls, 0)
end)
test("zero negative fractional NaN infinite and oversized quantities are rejected", function()
    for _, n in ipairs({0, -1, 0.5, 0/0, math.huge, 1000}) do
        local trade, backend, session, request = fixture(); request.quantity = n
        equal(trade:execute(session, request), false); equal(backend.calls, 0)
    end
end)
test("insufficient funds and full inventory do not consume Coin", function()
    local trade, backend, session, request = fixture(); backend.coins = 1
    equal(trade:execute(session, request), false); equal(backend.count, 5)
    backend.coins, backend.full = 100, true
    equal(trade:execute(session, request), false); equal(backend.coins, 100); equal(backend.calls, 0)
end)
test("cannot sell absent or protected items", function()
    local trade, backend, session, request = fixture(); request.side = "sell"; request.quantity = 6
    equal(trade:execute(session, request), false)
    request.quantity, backend.protected = 1, true
    equal(trade:execute(session, request), false); equal(backend.coins, 100); equal(backend.calls, 0)
end)
test("same request retry and reconstructed service cannot duplicate purchases", function()
    local trade, backend, session, request, state, catalog = fixture()
    equal(trade:execute(session, request), true); equal(trade:execute(session, request), true)
    local restarted = Trading.new(state, catalog, backend, config)
    equal(restarted:execute(session, request), true); equal(backend.calls, 1); equal(backend.count, 7)
end)
test("reusing a receipt ID for another quantity is rejected", function()
    local trade, backend, session, request = fixture()
    equal(trade:execute(session, request), true); request.quantity = 3
    local ok, reason = trade:execute(session, request)
    equal(ok, false); equal(reason, "request_id_conflict"); equal(backend.calls, 1)
end)
test("failed commit and stale revision have no partial effects", function()
    for _, flag in ipairs({"fail", "stale"}) do
        local trade, backend, session, request = fixture(); backend[flag] = true
        equal(trade:execute(session, request), false); equal(backend.coins, 100); equal(backend.count, 5)
    end
end)
test("backend exception releases transaction lock", function()
    local trade, backend, session, request = fixture()
    local snapshot = backend.snapshot; backend.snapshot = function() error("test failure") end
    local ok, reason = trade:execute(session, request)
    equal(ok, false); equal(reason, "backend_error")
    backend.snapshot = snapshot; equal(trade:execute(session, request), true)
end)
test("reentrant trade is blocked", function()
    local trade, backend, session, request = fixture()
    local snapshot = backend.snapshot
    function backend:snapshot(...)
        local ok, reason = trade:execute(session, request)
        equal(ok, false); equal(reason, "trade_busy")
        return snapshot(self, ...)
    end
    equal(trade:execute(session, request), true); equal(backend.calls, 1)
end)
test("wrong world or out-of-range merchant is rejected", function()
    local trade, backend, session, request = fixture(); session.world_id = "other-world"
    equal(trade:execute(session, request), false)
    session.world_id, backend.allowed = "test-world", false
    equal(trade:execute(session, request), false); equal(backend.calls, 0)
end)
test("Coin overflow is rejected before sale", function()
    local trade, backend, session, request = fixture(); request.side = "sell"; backend.coins = V.MAX_INTEGER
    local ok, reason = trade:execute(session, request)
    equal(ok, false); equal(reason, "coin_overflow"); equal(backend.calls, 0)
end)
test("unimplemented atomic backend cannot mutate inventory", function()
    local trade, backend, session, request = fixture(); backend.commit_exchange = nil
    local ok, reason = trade:execute(session, request)
    equal(ok, false); equal(reason, "atomic_backend_unavailable"); equal(backend.coins, 100)
end)
test("economy quotes never permit buy-sell profit", function()
    for level = 0, 100 do
        local quote = assert(Pricing.quote(level, config.economy))
        assert(quote.sell_price > 0 and quote.sell_price <= quote.buy_price)
    end
end)

local NativeCatalog = require("merchant.services.native_catalog")
local Store = require("merchant.integrations.discovery_store")
local Identity = require("merchant.domain.identity")
local first_id = "abcdefghijklmnopqrstuv"
local second_id = "ABCDEFGHIJKLMNOPQRSTUV"

test("native catalog keeps undiscovered items hidden and sorts deterministically", function()
    local entries = NativeCatalog.build({
        {id=first_id,name="Wood",path="/test/wood",power_level=0,sellable=true},
        {id=second_id,name="Armor",path="/test/armor",power_level=10,sellable=false},
    }, {[first_id]=true}, config.economy)
    equal(#entries, 1); equal(entries[1].id, first_id)
    equal(entries[1].buy_price,10); equal(entries[1].sell_price,4)
    equal(entries[1].sellable,true)
end)

test("protected items can be discovered without becoming sellable", function()
    local entries = NativeCatalog.build({
        {id=second_id,name="Quest",path="/test/quest",power_level=0,sellable=false},
    }, {[second_id]=true}, config.economy)
    equal(#entries,1); equal(entries[1].sellable,false)
end)

test("discovery journal joins committed batches only", function()
    local ids = Store.decode("B 1\n"..first_id.."\nE 1\nB 1\n"..second_id.."\nE 1\n")
    equal(ids[first_id],true); equal(ids[second_id],true)
    equal(next(Store.decode("")),nil)
end)

test("incomplete corrupted or executable discovery data fails closed", function()
    for _, data in ipairs({"B 1\n"..first_id.."\n", "B 2\n"..first_id.."\nE 2\n", "return {}\n", "B 1\n../../save\nE 1\n"}) do
        equal(pcall(Store.decode,data),false)
    end
end)

test("recipe names do not collide and persistence ids remain stable", function()
    local name, id = Identity.recipe(first_id)
    local again, same = Identity.recipe(first_id)
    local other, different = Identity.recipe(second_id)
    equal(name,again); equal(id,same); equal(#id,22)
    assert(id:match("^[%w_-]+$")); assert(name~=other); assert(id~=different)
end)

local Native = require("merchant.integrations.native_shop")
test("signed native levels use base pricing below zero and scale above 100", function()
    for _, level in ipairs({-1, -2147483648, 0}) do
        local quote = assert(Pricing.quote(level, config.economy))
        equal(quote.buy_price,10); equal(quote.sell_price,4)
    end
    equal(assert(Pricing.quote(150, config.economy)).buy_price,310)
end)

test("malformed levels and integer price overflow remain rejected", function()
    for _, level in ipairs({false, "1", 0.5, 0/0, math.huge, -math.huge, 2147483648, -2147483649}) do
        local quote, reason = Pricing.quote(level, config.economy)
        equal(quote,nil); equal(reason,"invalid_power_level")
    end
    local quote, reason = Pricing.quote(V.MAX_INTEGER, config.economy)
    equal(quote,nil); equal(reason,"price_overflow")
end)

test("one unpriceable discovered item cannot blank the whole merchant", function()
    local entries, rejected = NativeCatalog.build({
        {id=first_id,name="Resource",path="/test/resource",power_level=-1,sellable=true},
        {id=second_id,name="Malformed",path="/test/malformed",power_level="bad",sellable=true},
        {id="hidden",name="Hidden",path="/test/hidden",power_level=-1,sellable=true},
    }, {[first_id]=true,[second_id]=true}, config.economy)
    equal(#entries,1); equal(entries[1].id,first_id)
    equal(#rejected,1); equal(rejected[1].id,second_id); equal(rejected[1].reason,"invalid_power_level")
end)

test("overflowing product is excluded without unsafe fallback prices", function()
    local entries, rejected = NativeCatalog.build({
        {id=first_id,name="TooExpensive",path="/test/overflow",power_level=V.MAX_INTEGER,sellable=true},
        {id=second_id,name="Resource",path="/test/resource",power_level=0,sellable=true},
    }, {[first_id]=true,[second_id]=true}, config.economy)
    equal(#entries,1); equal(entries[1].id,second_id)
    equal(#rejected,1); equal(rejected[1].reason,"price_overflow")
end)

test("invalid economy blocks catalog instead of inventing prices", function()
    equal(pcall(NativeCatalog.build, {}, {}, {base_price=0,price_per_power_level=2,sell_percent=40}), false)
end)

test("UObject path adapter uses supported full-name binding and retains subobjects", function()
    local object = {GetFullName = function() return "RecipeData /Engine/Transient.DWM_Test:Child" end}
    equal(Native.path(object), "/Engine/Transient.DWM_Test:Child")
    equal(pcall(Native.path, {GetFullName=function() return "invalid" end}), false)
end)

test("merchant matches bootstrap and dynamic rows but rejects unrelated tables", function()
    local function object(name)
        return {IsValid=function() return true end, GetFullName=function() return "DataTable "..name end}
    end
    local station = object("station")
    local row = Native.bootstrap_row_name
    station.CraftingDataRowHandle = {
        RowName={ToString=function() return row end}, DataTable=object(Native.table_path),
    }
    equal(Native.is_merchant(station),true)
    row = Native.row_name; equal(Native.is_merchant(station),true)
    row = "VanillaStore"; equal(Native.is_merchant(station),false)
    row = Native.bootstrap_row_name
    station.CraftingDataRowHandle.DataTable=object("/test/other")
    equal(Native.is_merchant(station),false)
end)

print(tostring(passed) .. " local tests passed (native game adapters are not mocked as verified).")
return passed
