local V = require("merchant.domain.values")
local Pricing = {}

-- Configurable initial economy; PowerLevel must come from native ItemData.
function Pricing.quote(power_level, config)
    if not V.integer(power_level, -V.MAX_INTEGER - 1, V.MAX_INTEGER) then return nil, "invalid_power_level" end
    if not V.integer(config.base_price, 1, V.MAX_INTEGER)
        or not V.integer(config.price_per_power_level, 0, 1000000)
        or not V.integer(config.sell_percent, 1, 100) then return nil, "invalid_economy" end
    -- Pricing policy: native negative levels use the base tier. ItemData is a
    -- signed int32; a player-level gate's 0..100 limit is not an item constraint.
    local tier = math.max(0, power_level)
    if config.price_per_power_level > 0
        and tier > math.floor((V.MAX_INTEGER - config.base_price) / config.price_per_power_level) then
        return nil, "price_overflow"
    end
    local buy = config.base_price + tier * config.price_per_power_level
    return {buy_price = buy, sell_price = math.max(1, math.floor(buy * config.sell_percent / 100))}
end

return Pricing
