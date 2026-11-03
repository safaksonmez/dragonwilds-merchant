local V = require("merchant.domain.values")
local Catalog = {}

-- Entries are populated from registered native ItemData.
function Catalog.new(entries)
    local by_id = {}
    for _, entry in ipairs(entries) do
        assert(V.token(entry.id) and not by_id[entry.id], "Invalid or duplicate item identity")
        assert(V.integer(entry.buy_price, 1, V.MAX_INTEGER), "Invalid buy price")
        assert(V.integer(entry.sell_price, 1, entry.buy_price), "Invalid sell price")
        by_id[entry.id] = V.copy(entry)
    end
    local self = {}
    function self:get(id) return V.copy(by_id[id]) end
    function self:visible(world)
        local result = {}
        for id, entry in pairs(by_id) do
            if world:is_discovered(id) then result[#result + 1] = V.copy(entry) end
        end
        table.sort(result, function(a, b) return a.id < b.id end)
        return result
    end
    return self
end

return Catalog
