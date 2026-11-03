local Values = {}
Values.MAX_INTEGER = 2147483647

function Values.integer(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value % 1 == 0
end

function Values.token(value)
    return type(value) == "string" and #value > 0 and #value <= 1024
        and not value:find("[%z\1-\31]")
end

function Values.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = Values.copy(entry) end
    return result
end

function Values.point(value)
    if type(value) ~= "table" then return false end
    for _, axis in ipairs({"x", "y", "z"}) do
        local n = value[axis]
        if type(n) ~= "number" or n ~= n or math.abs(n) > 100000000 then return false end
    end
    return true
end

return Values
