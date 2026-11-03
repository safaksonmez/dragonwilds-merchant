local V = require("merchant.domain.values")
local Pricing = {}

-- Configurable initial economy; PowerLevel must come from native ItemData.
function Pricing.quote(power_level, config)
    if not V.integer(power_level, 0, 100) then return nil, "invalid_power_level" end
    if not V.integer(config.base_price, 1, V.MAX_INTEGER)
        or not V.integer(config.price_per_power_level, 0, 1000000)
        or not V.integer(config.sell_percent, 1, 100) then return nil, "invalid_economy" end
    local buy = config.base_price + power_level * config.price_per_power_level
    if buy > V.MAX_INTEGER then return nil, "price_overflow" end
    return {buy_price = buy, sell_price = math.max(1, math.floor(buy * config.sell_percent / 100))}
end

return Pricing
