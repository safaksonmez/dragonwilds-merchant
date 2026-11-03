-- Development-only, read-only reflection probe. Never include in the mod ZIP.
local function dump()
    ExecuteInGameThread(function()
        print("[DragonwildsMerchantProbe] Dumping reflected objects; no gameplay mutations.\n")
        DumpAllObjects()
        print("[DragonwildsMerchantProbe] Object dump completed.\n")
    end)
end

RegisterKeyBind(Key.F8, dump)
RegisterKeyBind(Key.F9, function()
    ExecuteInGameThread(function()
        local ok, config = pcall(require, "probe_config")
        if not ok then
            print("[DragonwildsMerchantProbe] Local probe config unavailable.\n")
            return
        end
        local chunk, problem = loadfile(config.command_file)
        if not chunk then
            print("[DragonwildsMerchantProbe] " .. tostring(problem) .. "\n")
            return
        end
        local success, result = pcall(chunk)
        print("[DragonwildsMerchantProbe] Command: " .. tostring(success) .. " " .. tostring(result) .. "\n")
    end)
end)
print("[DragonwildsMerchantProbe] Ready. F8 dumps objects; F9 runs the local development command. No automatic dump.\n")
