local Shop = {}

local labels = {
    en = {merchant = "Coin Merchant", items = "Items "},
    tr = {merchant = "Coin Tuccari", items = "Esyalar "},
}

function Shop.labels(locale)
    local selected = labels[locale] or labels.en
    return {merchant = selected.merchant, items = selected.items}
end

return Shop
