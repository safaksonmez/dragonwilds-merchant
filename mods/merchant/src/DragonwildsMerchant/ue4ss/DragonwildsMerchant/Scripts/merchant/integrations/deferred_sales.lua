-- RuneSchema's native raw reload runs on its engine tick after file closure.
-- Defer hard Coin references until /assets has registered the custom currency.
local Sales = {}
local requested = {}
local function destination(root) return root .. "/../../raw/90-dwm-runtime-sales.json" end

function Sales.prepare(root)
    local config = assert(io.open(root .. "/../../../../settings/settings.ini", "rb"), "RuneSchema settings unavailable")
    local settings = config:read("*a"); config:close()
    local section, enabled = nil, false
    for line in settings:gmatch("[^\r\n]+") do
        section = line:match("^%s*%[([^%]]+)%]") or section
        if section == "RuneSchema" then
            local value = line:match("^%s*enableAutoReload%s*=%s*(%w+)")
            if value then enabled = value:lower() == "true" end
        end
    end
    -- The Lua companion starts before native /raw processing. Clear only this
    -- mod-owned generated file so a previous session cannot reference Coin early.
    local file, problem = io.open(destination(root), "wb")
    assert(file, "cannot reset generated sales file: " .. tostring(problem))
    assert(file:write("{}\n")); assert(file:close())
    requested[root] = nil
    assert(enabled, "RuneSchema enableAutoReload=true is required for deferred Coin sales")
end

function Sales.ensure(root, actual_count, expected_count)
    if actual_count == expected_count then requested[root] = nil; return true end
    if not requested[root] then
        local source = assert(io.open(root .. "/Data/native-sales.json", "rb"), "native sales template unavailable")
        local payload = assert(source:read("*a")); source:close()
        assert(#payload > 0 and #payload <= 2097152, "invalid native sales template size")
        local file = assert(io.open(destination(root), "wb"), "generated sales file is not writable")
        assert(file:write(payload)); assert(file:flush()); assert(file:close())
        requested[root] = true
    end
    return false
end

return Sales
