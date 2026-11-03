local Identity = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- Stable 128-bit identifier, never used for authorization. Ownership is checked
-- against the full, reversible object name as well as the native recipe fields.
function Identity.recipe(item_id)
    local a, b = 0xcbf29ce484222325, 0x6c62272e07bb0142
    local text = "DragonwildsMerchant:buy:v1:" .. item_id
    for i = 1, #text do
        a = (a ~ text:byte(i)) * 0x100000001b3
        b = (b ~ text:byte(i)) * 0xc2b2ae3d27d4eb4f
    end
    local encoded, buffer, bits = {}, 0, 0
    for i = 0, 15 do
        local n = i < 8 and a or b
        buffer = (buffer << 8) | ((n >> ((i % 8) * 8)) & 255)
        bits = bits + 8
        while bits >= 6 do
            bits = bits - 6
            local index = (buffer >> bits) & 63
            encoded[#encoded + 1] = alphabet:sub(index + 1, index + 1)
        end
    end
    if bits > 0 then
        local index = (buffer << (6 - bits)) & 63
        encoded[#encoded + 1] = alphabet:sub(index + 1, index + 1)
    end
    local hex = item_id:gsub(".", function(c) return string.format("%02x", c:byte()) end)
    return "DWM_Buy_" .. hex, table.concat(encoded)
end

return Identity
