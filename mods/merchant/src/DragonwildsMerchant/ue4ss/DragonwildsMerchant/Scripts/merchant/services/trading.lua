local V = require("merchant.domain.values")
local Trading = {}

-- Backend runs on the authority game thread and must atomically persist Coin,
-- inventory and request receipts, checking revision and deduplicating retries.
-- A sequential RemoveItem + wallet write is NOT a valid commit implementation.
function Trading.new(world, catalog, backend, config)
    local self, busy = {}, {}
    function self:execute(session, request)
        if type(session) ~= "table" or not V.token(session.player_id)
            or session.world_id ~= world:world_id() then return false, "invalid_session" end
        if type(request) ~= "table" or not V.token(request.id) or not V.token(request.item_id)
            or not V.integer(request.quantity, 1, config.max_trade_quantity)
            or (request.side ~= "buy" and request.side ~= "sell") then return false, "invalid_request" end
        if busy[session.player_id] then return false, "trade_busy" end
        if type(backend.commit_exchange) ~= "function" then return false, "atomic_backend_unavailable" end
        busy[session.player_id] = true
        local ok, accepted, result = pcall(function()
            if backend:authorize(session, request.merchant_id) ~= true then return false, "not_authorized" end
            local fingerprint = table.concat({request.side, request.item_id, tostring(request.quantity)}, "\0")
            local receipt = backend:receipt(session, request.id)
            if receipt then
                if receipt.fingerprint ~= fingerprint then return false, "request_id_conflict" end
                return true, V.copy(receipt)
            end
            local entry = catalog:get(request.item_id)
            if not entry then return false, "unknown_item" end
            if request.side == "buy" and not world:is_discovered(entry.id) then return false, "item_not_discovered" end
            local snapshot = backend:snapshot(session, entry.id)
            if type(snapshot) ~= "table" or not V.integer(snapshot.coins, 0, V.MAX_INTEGER)
                or not V.integer(snapshot.item_count, 0, V.MAX_INTEGER)
                or not V.integer(snapshot.revision, 0, V.MAX_INTEGER) then return false, "invalid_inventory_snapshot" end
            local price = request.side == "buy" and entry.buy_price or entry.sell_price
            if request.quantity > math.floor(V.MAX_INTEGER / price) then return false, "total_overflow" end
            local total = price * request.quantity
            if request.side == "buy" then
                if snapshot.coins < total then return false, "insufficient_coins" end
                if snapshot.item_count > V.MAX_INTEGER - request.quantity then return false, "inventory_overflow" end
                if backend:can_receive(session, entry.id, request.quantity) ~= true then return false, "inventory_full" end
            else
                if snapshot.item_count < request.quantity then return false, "insufficient_items" end
                if snapshot.coins > V.MAX_INTEGER - total then return false, "coin_overflow" end
                if backend:can_sell(session, entry.id, request.quantity) ~= true then return false, "item_not_sellable" end
            end
            local direction = request.side == "buy" and 1 or -1
            return backend:commit_exchange(session, {
                request_id = request.id, fingerprint = fingerprint, expected_revision = snapshot.revision,
                item_id = entry.id, quantity = request.quantity, side = request.side,
                item_delta = direction * request.quantity, coin_delta = -direction * total,
                currency = "Coin", unit_price = price,
            })
        end)
        busy[session.player_id] = nil
        if not ok then return false, "backend_error" end
        return accepted == true, result
    end
    return self
end

return Trading
