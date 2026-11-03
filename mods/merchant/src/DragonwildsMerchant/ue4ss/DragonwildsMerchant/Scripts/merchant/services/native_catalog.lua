local Pricing = require("merchant.services.pricing")
local Catalog = {}

-- Only native discovery facts may enter this list. No inventory mutation here.
function Catalog.build(facts, discovered, economy)
    local entries, seen = {}, {}
    for _, fact in ipairs(facts) do
        if discovered[fact.id] and not seen[fact.id] then
            local quote, reason = Pricing.quote(fact.power_level, economy)
            assert(quote, reason)
            seen[fact.id] = true
            entries[#entries + 1] = {
                id = fact.id, name = fact.name, path = fact.path,
                buy_price = quote.buy_price, sell_price = quote.sell_price,
                sellable = fact.sellable == true,
            }
        end
    end
    table.sort(entries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return entries
end

return Catalog
