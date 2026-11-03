local Store = {}
local MAX_BYTES = 2097152

local function valid_id(id)
    return type(id) == "string" and #id == 22 and id:match("^[%w_-]+$") ~= nil
end

-- A data-only append journal. A truncated batch fails closed. Never evaluate
-- saved text as Lua, and never mix world discovery with character Coin balances.
function Store.decode(text)
    assert(#text <= MAX_BYTES, "discovery journal too large")
    local ids, batch, expected = {}, nil, nil
    if text == "" then return ids end
    assert(text:sub(-1) == "\n", "incomplete discovery journal")
    for line in text:gmatch("([^\n]*)\n") do
        if line:match("^B %d+$") then
            assert(not batch, "nested discovery batch")
            expected = tonumber(line:sub(3))
            assert(expected > 0 and expected <= 32768, "invalid discovery batch size")
            batch = {}
        elseif line:match("^E %d+$") then
            assert(batch and tonumber(line:sub(3)) == expected and #batch == expected,
                "incomplete discovery batch")
            for _, id in ipairs(batch) do ids[id] = true end
            batch, expected = nil, nil
        else
            assert(batch and valid_id(line) and #batch < expected, "invalid discovery record")
            batch[#batch + 1] = line
        end
    end
    assert(not batch, "uncommitted discovery batch")
    return ids
end

function Store.merge(root, world_id, new_ids)
    assert(type(world_id) == "string" and #world_id == 32 and world_id:match("^%x+$"), "invalid world id")
    local path = root .. "/Data/discovery-v1-" .. world_id .. ".txt"
    local file, problem = io.open(path, "a+b")
    assert(file, "discovery storage unavailable: " .. tostring(problem))
    local ok, result = pcall(function()
        assert(file:seek("end") <= MAX_BYTES, "discovery journal too large")
        assert(file:seek("set", 0))
        local ids = Store.decode(assert(file:read("*a")))
        local added = {}
        for id in pairs(new_ids) do
            assert(valid_id(id), "invalid discovery id")
            if not ids[id] then added[#added + 1] = id end
        end
        table.sort(added)
        if #added > 0 then
            local record = "B " .. #added .. "\n" .. table.concat(added, "\n") .. "\nE " .. #added .. "\n"
            assert(file:seek("end") + #record <= MAX_BYTES, "discovery journal full")
            assert(file:write(record)); assert(file:flush())
            assert(file:seek("set", 0))
            ids = Store.decode(assert(file:read("*a")))
            for _, id in ipairs(added) do assert(ids[id], "discovery readback failed") end
        end
        return ids
    end)
    local closed, close_error = file:close()
    assert(ok, result)
    assert(closed, close_error)
    return result
end

return Store
