return {
    enabled = true,
    currency = "Coin",
    discovery_scope = "world",
    regions = { bramblemead_valley = true },
    max_trade_quantity = 999,
    max_trade_distance = 600, -- Unreal centimeters; checked again by the authority.
    -- NPC/prop authored locations live in the parent npc/*.json files.
    locale = "en",
    economy = { base_price = 10, price_per_power_level = 2, sell_percent = 40 },
}
