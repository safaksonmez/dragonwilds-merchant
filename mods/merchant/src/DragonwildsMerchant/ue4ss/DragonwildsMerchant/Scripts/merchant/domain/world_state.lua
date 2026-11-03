local V = require("merchant.domain.values")
local WorldState = {}

-- Save commits one world-scoped snapshot atomically before changes become visible.
function WorldState.new(world_id, saved, save)
    assert(V.token(world_id), "A stable world identity is required")
    assert(type(save) == "function", "Durable storage is required")
    local state = saved and V.copy(saved) or {
        schema = 1, world_id = world_id, revision = 0, discoveries = {}, placements = {},
    }
    assert(state.schema == 1 and state.world_id == world_id, "Wrong world or state schema")
    assert(V.integer(state.revision, 0, V.MAX_INTEGER), "Invalid state revision")
    assert(type(state.discoveries) == "table" and type(state.placements) == "table", "Invalid world state")
    for id, discovered in pairs(state.discoveries) do
        assert(V.token(id) and discovered == true, "Invalid discovery record")
    end
    for region, point in pairs(state.placements) do
        assert(V.token(region) and V.point(point), "Invalid placement record")
    end
    local self, busy = {}, false
    local function commit(next_state)
        if busy then return false, "state_busy" end
        if state.revision == V.MAX_INTEGER then return false, "revision_exhausted" end
        busy = true
        next_state.revision = state.revision + 1
        local ok, accepted = pcall(save, V.copy(next_state), state.revision)
        busy = false
        if not ok or accepted ~= true then return false, "state_save_failed" end
        state = next_state
        return true
    end
    function self:snapshot() return V.copy(state) end
    function self:world_id() return world_id end
    function self:is_discovered(item_id) return state.discoveries[item_id] == true end
    function self:merge_discoveries(item_ids)
        if type(item_ids) ~= "table" then return false, "invalid_discoveries" end
        local next_state, changed = V.copy(state), false
        for _, id in ipairs(item_ids) do
            if not V.token(id) then return false, "invalid_item_id" end
            if not next_state.discoveries[id] then next_state.discoveries[id], changed = true, true end
        end
        if not changed then return true end
        return commit(next_state)
    end
    function self:placement(region) return V.copy(state.placements[region]) end
    function self:reserve_placement(region, point)
        if not V.token(region) or not V.point(point) then return false, "invalid_placement" end
        if state.placements[region] then return true, self:placement(region) end
        local next_state = V.copy(state)
        next_state.placements[region] = V.copy(point)
        local ok, reason = commit(next_state)
        if not ok then return false, reason end
        return true, self:placement(region)
    end
    return self
end

return WorldState
