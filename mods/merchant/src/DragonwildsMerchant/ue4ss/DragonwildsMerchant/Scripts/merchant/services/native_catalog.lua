local Pricing = require("merchant.services.pricing")
local Catalog = {}

-- Only native discovery facts may enter this list. No inventory mutation here.
function Catalog.build(facts, discovered, economy)
    local baseline, config_error = Pricing.quote(0, economy)
    assert(baseline, config_error)
    local entries, seen, rejected = {}, {}, {}
    for _, fact in ipairs(facts) do
        if discovered[fact.id] and not seen[fact.id] then
            local quote, reason = Pricing.quote(fact.power_level, economy)
            seen[fact.id] = true
            if quote then
                entries[#entries + 1] = {
                    id = fact.id, name = fact.name, path = fact.path,
                    buy_price = quote.buy_price, sell_price = quote.sell_price,
                    sellable = fact.sellable == true,
                }
            else
                -- Reject the unsafe product, not every other discovered item.
                rejected[#rejected + 1] = {id = fact.id, path = fact.path, reason = reason,
                    power_level = tostring(fact.power_level)}
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return entries, rejected
end

return Catalog
