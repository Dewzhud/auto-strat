local Globals = getgenv()

return function(ctx)
    if not ctx or not ctx.Window then
        return
    end

    local Window = ctx.Window
    local replicated_storage = ctx.ReplicatedStorage or game:GetService("ReplicatedStorage")
    local http_service = ctx.HttpService or game:GetService("HttpService")
    local game_state = ctx.GameState or "UNKNOWN"
    local workspace_ref = ctx.workspace or workspace

    local players_service = game:GetService("Players")
    local local_player = ctx.LocalPlayer or players_service.LocalPlayer or players_service.PlayerAdded:Wait()

    Globals.record_strat = Globals.record_strat or false

    local spawned_towers = {}
    local tower_count = 0
    local last_wave = 0
    local Recorder
    local has_hook = type(hookmetamethod) == "function"
    
    -- ============================================
    -- MULTI-MAP VARIABLES
    -- ============================================
    local current_map = "Unknown"
    local map_actions = {}
    local is_recording_map = false
    local current_map_started = false
    local map_headers = {}
    local current_towers = {"None", "None", "None", "None", "None"}
    local current_modifiers = ""
    local current_mode = "Unknown"
    local skip_game_info = false
    
    -- ============================================
    -- GET CURRENT MAP NAME
    -- ============================================
    local function GetCurrentMapName()
        local state_folder = replicated_storage:FindFirstChild("State")
        if state_folder then
            local map = state_folder:GetAttribute("Map")
            if map and map ~= "" and map ~= "Unknown" then
                return map
            end
        end
        
        local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
        if state_replicators then
            local game_state = state_replicators:FindFirstChild("GameStateReplicator")
            if game_state then
                local map = game_state:GetAttribute("Map")
                if map and map ~= "" then
                    return map
                end
            end
        end
        return "Unknown"
    end
    
    -- ============================================
    -- GET CURRENT MODE
    -- ============================================
    local function GetCurrentMode()
        local state_folder = replicated_storage:FindFirstChild("State")
        if not state_folder then
            return "Unknown"
        end
        
        local mode = state_folder.Difficulty.Value or "Unknown"
        local mode_obj = state_folder:FindFirstChild("Mode")
        
        if mode_obj then
            if mode_obj.Value == "Hardcore" then
                if mode == "Hard" then
                    return "Voidcore"
                else
                    return "Hardcore"
                end
            elseif mode_obj.Value == "DuckEvent" then
                if mode == "Easy" then
                    return "DuckyEasy"
                elseif mode == "Hard" then
                    return "DuckyHard"
                end
            elseif mode_obj.Value == "Special" or mode_obj.Value == "DuckEvent" then
                skip_game_info = true
            end
        end
        
        if mode == "Trial" then
            skip_game_info = true
        end
        
        return mode
    end
    
    -- ============================================
    -- GET EQUIPPED TOWERS
    -- ============================================
    local function GetEquippedTowers()
        local towers = {"None", "None", "None", "None", "None"}
        local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
        
        if state_replicators then
            for _, folder in ipairs(state_replicators:GetChildren()) do
                if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == local_player.UserId then
                    local equipped = folder:GetAttribute("EquippedTowers")
                    if type(equipped) == "string" then
                        local cleaned_json = equipped:match("%[.*%]") 
                        
                        local success, tower_table = pcall(function()
                            return http_service:JSONDecode(cleaned_json)
                        end)
                        
                        if success and type(tower_table) == "table" then
                            towers[1] = tower_table[1] or "None"
                            towers[2] = tower_table[2] or "None"
                            towers[3] = tower_table[3] or "None"
                            towers[4] = tower_table[4] or "None"
                            towers[5] = tower_table[5] or "None"
                        end
                    end
                end
            end
        end
        return towers
    end
    
    -- ============================================
    -- GET MODIFIERS
    -- ============================================
    local function GetModifiers()
        local mods = {}
        local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
        
        if state_replicators then
            for _, folder in ipairs(state_replicators:GetChildren()) do
                if folder.Name == "ModifierReplicator" then
                    local raw_votes = folder:GetAttribute("Votes")
                    if type(raw_votes) == "string" then
                        local cleaned_json = raw_votes:match("{.*}") 
                        
                        local success, mod_table = pcall(function()
                            return http_service:JSONDecode(cleaned_json)
                        end)
                        
                        if success and type(mod_table) == "table" then
                            for mod_name, _ in pairs(mod_table) do
                                table.insert(mods, mod_name .. " = true")
                            end
                        end
                    end
                end
            end
        end
        return table.concat(mods, ", ")
    end
    
    -- ============================================
    -- GET WAVE PREFIX
    -- ============================================
    local function get_wave_prefix()
        local success, current_wave = pcall(function() 
            return replicated_storage.StateReplicators.GameStateReplicator:GetAttribute("Wave") 
        end)
        if success and current_wave and current_wave > last_wave then
            last_wave = current_wave
            return "\n-- [ Wave " .. current_wave .. " ] --\n"
        end
        return ""
    end

    -- ============================================
    -- RECORD ACTION WITH MAP CONTEXT
    -- ============================================
    local function record_action(command_str)
        if not Globals.record_strat then return end
        
        -- Record to current map's actions
        if current_map ~= "Unknown" then
            if not map_actions[current_map] then
                map_actions[current_map] = {}
            end
            table.insert(map_actions[current_map], get_wave_prefix() .. command_str)
        end
        
        -- Also append to Strat.txt for compatibility
        if appendfile then
            appendfile("Strat.txt", get_wave_prefix() .. command_str .. "\n")
        end
    end

    -- ============================================
    -- SAVE MULTI-MAP STRATEGY
    -- ============================================
    local function SaveMultiMapStrategy()
        if not writefile then
            if Recorder then
                Recorder:Log("⚠️ writefile not available, cannot save multi-map strategy")
            end
            return
        end
        
        local content = "local TDS = loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
        content = content .. "-- ============================================\n"
        content = content .. "-- MULTI-MAP STRATEGY FILE\n"
        content = content .. "-- Generated at: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
        content = content .. "-- Maps recorded: " .. table.concat(table.keys(map_actions), ", ") .. "\n"
        content = content .. "-- ============================================\n\n"
        
        content = content .. "-- Map-specific actions\n\n"
        content = content .. "local MapActions = {\n"
        
        local has_actions = false
        for map_name, actions in pairs(map_actions) do
            if #actions > 0 then
                has_actions = true
                content = content .. string.format('    ["%s"] = {\n', map_name)
                for _, action in ipairs(actions) do
                    content = content .. "        " .. action .. ",\n"
                end
                content = content .. "    },\n"
            end
        end
        
        content = content .. "}\n\n"
        
        if has_actions then
            content = content .. [=[
-- ============================================
-- AUTO-EXECUTION LOGIC
-- ============================================
local function ExecuteCurrentMapStrategy()
    print("=== Executing Multi-Map Strategy ===")
    local stateReplicators = game:GetService("ReplicatedStorage"):FindFirstChild("StateReplicators")
    if not stateReplicators then 
        print("No StateReplicators found")
        return 
    end
    
    local gameState = stateReplicators:FindFirstChild("GameStateReplicator")
    if not gameState then 
        print("No GameStateReplicator found")
        return 
    end
    
    local currentMap = gameState:GetAttribute("Map") or "Unknown"
    print("Current map detected: " .. currentMap)
    local actions = MapActions[currentMap]
    
    if actions and #actions > 0 then
        print("Executing strategy for map: " .. currentMap .. " (" .. #actions .. " actions)")
        for i, action in ipairs(actions) do
            print("  [" .. i .. "] " .. action)
            local func = loadstring("return " .. action)()
            if func then
                pcall(func)
            end
        end
        print("Strategy execution complete for: " .. currentMap)
    else
        print("No strategy found for map: " .. currentMap)
        if next(MapActions) then
            print("Available maps: " .. table.concat(table.keys(MapActions), ", "))
        end
    end
end

-- Execute when game starts or map changes
local function SetupMapListener()
    local stateReplicators = game:GetService("ReplicatedStorage"):FindFirstChild("StateReplicators")
    if not stateReplicators then 
        print("No StateReplicators found")
        return 
    end
    
    local gameState = stateReplicators:FindFirstChild("GameStateReplicator")
    if gameState then
        gameState:GetAttributeChangedSignal("Map"):Connect(function()
            print("Map changed, executing strategy...")
            ExecuteCurrentMapStrategy()
        end)
        task.wait(2)
        print("Initial map execution...")
        ExecuteCurrentMapStrategy()
    else
        print("GameStateReplicator not found")
    end
end

print("Setting up multi-map strategy listener...")
task.spawn(SetupMapListener)
]=]
            
            writefile("Strat_MultiMap.lua", content)
            
            if Recorder then
                Recorder:Log("✅ Multi-map strategy saved to Strat_MultiMap.lua")
                Recorder:Log("📊 Maps recorded: " .. table.concat(table.keys(map_actions), ", "))
            end
            if Window then
                Window:Notify({
                    Title = "✅ Multi-Map Strategy Saved",
                    Desc = "Saved " .. #map_actions .. " map(s) to Strat_MultiMap.lua",
                    Time = 5,
                    Type = "normal"
                })
            end
        else
            if Recorder then
                Recorder:Log("⚠️ No actions recorded yet!")
            end
        end
    end

    -- ============================================
    -- GET MAP HEADER
    -- ============================================
    local function GetMapHeader()
        local towers = GetEquippedTowers()
        local mode = GetCurrentMode()
        local modifiers = GetModifiers()
        
        local header = string.format([[
-- ============================================
-- MAP: %s
-- Mode: %s
-- Towers: %s, %s, %s, %s, %s
-- Modifiers: %s
-- ============================================

]], current_map, mode, towers[1], towers[2], towers[3], towers[4], towers[5], modifiers)
        
        return header
    end

    -- ============================================
    -- START NEW MAP RECORDING
    -- ============================================
    local function StartNewMapRecording()
        local new_map = GetCurrentMapName()
        if new_map == "Unknown" then
            return
        end
        
        if new_map ~= current_map then
            current_map = new_map
            current_map_started = false
            
            -- Get fresh data for the new map
            current_towers = GetEquippedTowers()
            current_mode = GetCurrentMode()
            current_modifiers = GetModifiers()
            
            if Recorder then
                Recorder:Log("📝 New map detected: " .. current_map)
                Recorder:Log("  Mode: " .. current_mode)
                Recorder:Log("  Towers: " .. table.concat(current_towers, ", "))
            end
        end
        
        if not current_map_started then
            current_map_started = true
            
            -- Initialize map actions
            if not map_actions[current_map] then
                map_actions[current_map] = {}
            end
            
            -- Add map header to actions
            local header = GetMapHeader()
            table.insert(map_actions[current_map], header)
            
            -- Also append to Strat.txt
            if appendfile then
                appendfile("Strat.txt", header)
            end
            
            if Recorder then
                Recorder:Log("✅ Recording started for map: " .. current_map)
            end
            if Window then
                Window:Notify({
                    Title = "🎯 Map Detected",
                    Desc = "Recording for: " .. current_map,
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    end

    local function log_line(message)
        if Recorder and Recorder.Log then
            Recorder:Log(message)
        end
    end

    local function resolve_tower_index(tower)
        if typeof(tower) ~= "Instance" then
            return nil
        end

        if spawned_towers[tower] then
            return spawned_towers[tower]
        end

        local current = tower.Parent
        while current do
            if spawned_towers[current] then
                return spawned_towers[current]
            end
            current = current.Parent
        end

        return nil
    end

    local function sync_existing_towers()
        if game_state ~= "GAME" then
            return
        end

        local towers_folder = workspace_ref:FindFirstChild("Towers")
        if not towers_folder then
            return
        end

        table.clear(spawned_towers)
        tower_count = 0

        for _, tower in ipairs(towers_folder:GetChildren()) do
            local replicator = tower:FindFirstChild("TowerReplicator")
            if replicator and replicator:GetAttribute("OwnerId") == local_player.UserId then
                tower_count += 1
                spawned_towers[tower] = tower_count
            end
        end
    end

    local function num_to_str(n)
        if type(n) ~= "number" then
            return tostring(n)
        end
        if n == math.huge then
            return "math.huge"
        end
        if n == -math.huge then
            return "-math.huge"
        end
        if n ~= n then
            return "0/0"
        end
        return tostring(n)
    end

    local serialize_value
    local serialize_value_raw
    local serialize_table
    local serialize_table_raw

    local function format_key(key)
        if type(key) == "string" and key:match("^[_%a][_%w]*$") then
            return key
        end
        if type(key) == "number" then
            return "[" .. num_to_str(key) .. "]"
        end
        return "[" .. serialize_value(key) .. "]"
    end

    local function is_array(tbl)
        local max_idx = 0
        for k, _ in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                return false, 0
            end
            if k > max_idx then
                max_idx = k
            end
        end
        return true, max_idx
    end

    serialize_value = function(v, depth)
        depth = depth or 0
        if depth > 4 then
            return "nil"
        end

        local t = typeof(v)
        if t == "string" then
            return string.format("%q", v)
        elseif t == "number" then
            return num_to_str(v)
        elseif t == "boolean" then
            return tostring(v)
        elseif t == "Vector3" then
            return string.format(
                "Vector3.new(%s, %s, %s)",
                num_to_str(v.X),
                num_to_str(v.Y),
                num_to_str(v.Z)
            )
        elseif t == "CFrame" then
            local comps = {v:GetComponents()}
            local parts = {}
            for i = 1, #comps do
                parts[i] = num_to_str(comps[i])
            end
            return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
        elseif t == "Instance" then
            local idx = resolve_tower_index(v)
            if idx then
                return tostring(idx)
            end
            return "nil"
        elseif t == "table" then
            return serialize_table(v, depth + 1)
        end

        return "nil"
    end

    serialize_value_raw = function(v, depth)
        depth = depth or 0
        if depth > 4 then
            return "nil"
        end

        local t = typeof(v)
        if t == "string" then
            return string.format("%q", v)
        elseif t == "number" then
            return num_to_str(v)
        elseif t == "boolean" then
            return tostring(v)
        elseif t == "Vector3" then
            return string.format(
                "Vector3.new(%s, %s, %s)",
                num_to_str(v.X),
                num_to_str(v.Y),
                num_to_str(v.Z)
            )
        elseif t == "CFrame" then
            local comps = {v:GetComponents()}
            local parts = {}
            for i = 1, #comps do
                parts[i] = num_to_str(comps[i])
            end
            return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
        elseif t == "Instance" then
            local full = v:GetFullName()
            if type(full) == "string" and full ~= "" then
                local parts = string.split(full, ".")
                local expr = 'game:GetService("' .. parts[1] .. '")'
                for i = 2, #parts do
                    local part = parts[i]
                    if part:match("^[_%a][_%w]*$") then
                        expr = expr .. "." .. part
                    else
                        expr = expr .. "[" .. string.format("%q", part) .. "]"
                    end
                end
                return expr
            end
            return "nil"
        elseif t == "table" then
            return serialize_table_raw(v, depth + 1)
        end

        return "nil"
    end

    serialize_table = function(tbl, depth)
        local is_arr, max_idx = is_array(tbl)
        local parts = {}

        if is_arr then
            for i = 1, max_idx do
                parts[i] = serialize_value(tbl[i], depth)
            end
        else
            local keys = {}
            for k, _ in pairs(tbl) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, k in ipairs(keys) do
                table.insert(parts, format_key(k) .. " = " .. serialize_value(tbl[k], depth))
            end
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    serialize_table_raw = function(tbl, depth)
        local is_arr, max_idx = is_array(tbl)
        local parts = {}

        if is_arr then
            for i = 1, max_idx do
                parts[i] = serialize_value_raw(tbl[i], depth)
            end
        else
            local keys = {}
            for k, _ in pairs(tbl) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, k in ipairs(keys) do
                local key_str
                if type(k) == "string" and k:match("^[_%a][_%w]*$") then
                    key_str = k
                elseif type(k) == "number" then
                    key_str = "[" .. num_to_str(k) .. "]"
                else
                    key_str = "[" .. serialize_value_raw(k, depth) .. "]"
                end
                table.insert(parts, key_str .. " = " .. serialize_value_raw(tbl[k], depth))
            end
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    local function build_remote_call(remote, method, args)
        if typeof(remote) ~= "Instance" then
            return nil
        end

        local full = remote:GetFullName()
        if type(full) ~= "string" or full == "" then
            return nil
        end

        local parts = string.split(full, ".")
        local expr = 'game:GetService("' .. parts[1] .. '")'
        for i = 2, #parts do
            local part = parts[i]
            if part:match("^[_%a][_%w]*$") then
                expr = expr .. "." .. part
            else
                expr = expr .. "[" .. string.format("%q", part) .. "]"
            end
        end

        local arg_parts = {}
        for i = 1, #args do
            arg_parts[i] = serialize_value_raw(args[i])
        end

        return expr .. ":" .. method .. "(" .. table.concat(arg_parts, ", ") .. ")"
    end

    local function is_consumable_call(remote, args)
        local first = args[1]
        if type(first) == "string" then
            local lower = first:lower()
            if lower:find("consum") then
                return true
            end
            if lower:find("item") and type(args[2]) == "string" and tostring(args[2]):lower():find("use") then
                return true
            end
        end

        if typeof(remote) == "Instance" then
            local full = remote:GetFullName()
            if type(full) == "string" then
                local lower = full:lower()
                if lower:find("consum") then
                    return true
                end
                if lower:find("item") and lower:find("use") then
                    return true
                end
            end
        end

        return false
    end

    local function any_string_contains(args, token)
        for i = 1, #args do
            local v = args[i]
            if type(v) == "string" then
                local lower = v:lower()
                if lower:find(token, 1, true) then
                    return true
                end
            end
        end
        return false
    end

    local function collect_non_keyword_strings(args)
        local keywords = {
            troops = true,
            troop = true,
            option = true,
            options = true,
            target = true,
            ability = true,
            abilities = true,
            activate = true,
            set = true,
            voting = true,
            skip = true,
            inventory = true,
            equip = true,
            unequip = true,
            tower = true
        }

        local list = {}
        for i = 1, #args do
            local v = args[i]
            if type(v) == "string" then
                local lower = v:lower()
                if not keywords[lower] then
                    table.insert(list, v)
                end
            end
        end
        return list
    end

    local function find_payload(args)
        for i = 1, #args do
            local v = args[i]
            if type(v) == "table" then
                if v.Troop or v.troop or v.Tower or v.tower then
                    return v
                end
            end
        end
        return nil
    end

    local function find_tower_arg(args)
        for i = 1, #args do
            local v = args[i]
            if typeof(v) == "Instance" then
                local idx = resolve_tower_index(v)
                if idx then
                    return v
                end
            end
        end
        return nil
    end

    local function record_line(line, message)
        record_action(line)
        if message then
            log_line(message)
        end
    end

    Globals.__tds_record_equip = function(tower_name)
        if type(tower_name) ~= "string" then
            return
        end
        local cmd = string.format("TDS:Equip(%s)", string.format("%q", tower_name))
        record_line(cmd, "Equipped: " .. tower_name)
    end

    Globals.__tds_record_unequip = function(tower_name)
        if type(tower_name) ~= "string" then
            return
        end
        local cmd = string.format("TDS:Unequip(%s)", string.format("%q", tower_name))
        record_line(cmd, "Unequipped: " .. tower_name)
    end

    local function handle_namecall(remote, method, args, results)
        if not Globals.record_strat then
            return
        end

        if method ~= "InvokeServer" and method ~= "FireServer" then
            return
        end

        local handled = false

        local a1 = args[1]
        local a2 = args[2]
        local a3 = args[3]
        local a4 = args[4]
        local a5 = args[5]

        if a1 == "Troops" and a2 == "Abilities" and a3 == "Activate" then
            if type(a4) == "table" and type(a4.Name) == "string" then
                local abilityName = a4.Name
                if abilityName == "Call Of Arms" or abilityName == "Support Caravan" or abilityName == "Drop The Beat" or abilityName == "Raise The Dead" then
                    return
                end
            end
            
            if not results or results[1] ~= true then
                return
            end
            
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local name = a4.Name
                if idx and type(name) == "string" then
                    local data = a4.Data
                    local cmd
                    if data == nil or (type(data) == "table" and next(data) == nil) then
                        cmd = string.format("TDS:Ability(%d, %s)", idx, string.format("%q", name))
                    else
                        cmd = string.format(
                            "TDS:Ability(%d, %s, %s)",
                            idx,
                            string.format("%q", name),
                            serialize_value(data)
                        )
                    end

                    record_line(cmd, "Ability: " .. name .. " (Index: " .. idx .. ")")
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "Target" and a3 == "Set" then
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local target_type = a4.Target
                if idx and type(target_type) == "string" then
                    local cmd = string.format("TDS:SetTarget(%d, %s)", idx, string.format("%q", target_type))
                    record_line(cmd, "Target: " .. idx .. " -> " .. target_type)
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "Upgrade" and a3 == "Set" then
            if type(a4) == "table" then
                local tower = a4.Troop
                local my_index = resolve_tower_index(tower)
                local path = a4.Path or 1

                if my_index and tower and results and results[1] == true then
                    local replicator = tower:FindFirstChild("TowerReplicator")
                    local tower_name = replicator and replicator:GetAttribute("Name") or tower.Name

                    local cmd = (path > 1) and string.format("TDS:Upgrade(%d, %d)", my_index, path) or string.format("TDS:Upgrade(%d)", my_index)
            
                    record_line(cmd, "Upgraded " .. tower_name .. " (Index: " .. my_index .. ")")
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "Option" and a3 == "Set" then
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local opt_name = a4.Name or a4.Option or a4.Key or a4.Track
                local opt_val = a4.Value or a4.Val
                if idx and type(opt_name) == "string" then
                    local cmd = string.format(
                        "TDS:SetOption(%d, %s, %s)",
                        idx,
                        string.format("%q", opt_name),
                        serialize_value(opt_val)
                    )
                    record_line(cmd, "Option: " .. idx .. " " .. opt_name .. " = " .. tostring(opt_val))
                    handled = true
                    return
                end
            end
        end

        if a1 == "Troops" and a2 == "TowerServerEvent" and a3 == "ToggleSelectedTower" then
            local idx = resolve_tower_index(a4)
            local target_idx = resolve_tower_index(a5)
            if idx and target_idx then
                local cmd = string.format("TDS:MedicSelect(%d, %d)", idx, target_idx)
                record_line(cmd, "Medic: " .. idx .. " -> " .. target_idx)
                handled = true
                return
            end
        end

        if a1 == "Voting" and a2 == "Skip" then
            local current_wave = 0
            current_wave = replicated_storage.StateReplicators.GameStateReplicator:GetAttribute("Wave") or 0
            if current_wave == 0 then
                record_line("TDS:Ready()", "Readied up for the match")
            else
                record_line("TDS:VoteSkip(" .. current_wave .. ")", "Voted to skip wave " .. current_wave)
            end
            handled = true
            return
        end

        if a1 == "Inventory" and a2 == "Equip" and a3 == "tower" then
            if type(args[4]) == "string" then
                local tower_name = args[4]
                local cmd = string.format("TDS:Equip(%s)", string.format("%q", tower_name))
                record_line(cmd, "Equipped: " .. tower_name)
            end
            handled = true
            return
        end

        if a1 == "Inventory" and a2 == "Unequip" and a3 == "tower" then
            if type(args[4]) == "string" then
                local tower_name = args[4]
                local cmd = string.format("TDS:Unequip(%s)", string.format("%q", tower_name))
                record_line(cmd, "Unequipped: " .. tower_name)
            end
            handled = true
            return
        end

        if is_consumable_call(remote, args) then
            local raw_call = build_remote_call(remote, method, args)
            if raw_call then
                record_line(raw_call, "Consumable used")
            end
            handled = true
            return
        end

        if handled then
            return
        end

        if a1 ~= "Troops" then
            return
        end

        local payload = find_payload(args)
        local tower_obj = payload and (payload.Troop or payload.troop or payload.Tower or payload.tower) or find_tower_arg(args)
        local idx = resolve_tower_index(tower_obj)
        if not idx then
            return
        end

        local strings = collect_non_keyword_strings(args)
        local has_option = any_string_contains(args, "option") or any_string_contains(args, "track")
        local has_ability = any_string_contains(args, "abil")
        local has_target = any_string_contains(args, "target")

        if has_option then
            local opt_name = payload and (payload.Name or payload.Option or payload.Key or payload.Track)
            local opt_val = payload and (payload.Value or payload.Val)

            if not opt_name and #strings >= 1 then
                opt_name = strings[1]
            end
            if opt_val == nil and #strings >= 2 then
                opt_val = strings[2]
            end
            if not opt_name and any_string_contains(args, "track") then
                opt_name = "Track"
            end

            if opt_name then
                local cmd = string.format(
                    "TDS:SetOption(%d, %s, %s)",
                    idx,
                    string.format("%q", opt_name),
                    serialize_value(opt_val)
                )
                record_line(cmd, "Option: " .. idx .. " " .. opt_name .. " = " .. tostring(opt_val))
            end
            return
        end

        if has_target then
            local target_type = payload and payload.Target or (#strings >= 1 and strings[1] or nil)
            if target_type then
                local cmd = string.format("TDS:SetTarget(%d, %s)", idx, string.format("%q", target_type))
                record_line(cmd, "Target: " .. idx .. " -> " .. tostring(target_type))
            end
            return
        end

        if has_ability then
            local name = payload and payload.Name or (#strings >= 1 and strings[1] or nil)
            if name then
                local data = payload and payload.Data or nil
                local cmd
                if data == nil or (type(data) == "table" and next(data) == nil) then
                    cmd = string.format("TDS:Ability(%d, %s)", idx, string.format("%q", name))
                else
                    cmd = string.format(
                        "TDS:Ability(%d, %s, %s)",
                        idx,
                        string.format("%q", name),
                        serialize_value(data)
                    )
                end
                record_line(cmd, "Ability: " .. name .. " (Index: " .. idx .. ")")
            end
            return
        end
    end

    local RecorderTab = Window:Tab({Title = "Recorder", Icon = "camera"}) do
        Recorder = RecorderTab:CreateLogger({
            Title = "RECORDER:",
            Size = UDim2.new(0, 330, 0, 230)
        })

        RecorderTab:Button({
            Title = "START RECORDING",
            Desc = "Start recording for the current map",
            Callback = function()
                Recorder:Clear()

                if not has_hook then
                    Recorder:Log("\nYour executor is not supported for recording and is \nonly meant for replaying strats.")
                    return
                end

                if has_hook then
                    Globals.__tds_recorder_handler = function(remote, method, args, results)
                        handle_namecall(remote, method, args, results)
                    end

                    if not Globals.__tds_recorder_hooked then
                        Globals.__tds_recorder_hooked = true
                        local original
                        original = hookmetamethod(game, "__namecall", function(self, ...)
                            local method = getnamecallmethod and getnamecallmethod() or nil
                            local args = {...}
                            local results = table.pack(original(self, ...))
                            local handler = Globals.__tds_recorder_handler
                            if handler and method then
                                task.spawn(function()
                                    local set_id = setthreadidentity or setidentity or setthreadcontext
                                    if set_id then set_id(7) end
                                    pcall(handler, self, method, args, results)
                                end)
                            end
                            return table.unpack(results, 1, results.n)
                        end)
                    end
                end

                Recorder:Log("✅ Recorder started - Multi-Map Mode")
                Recorder:Log("📝 Recording will auto-detect maps")
                
                -- Get current map info
                current_map = GetCurrentMapName()
                current_mode = GetCurrentMode()
                current_towers = GetEquippedTowers()
                current_modifiers = GetModifiers()
                
                if current_map ~= "Unknown" then
                    Recorder:Log("🎯 Current map: " .. current_map)
                    Recorder:Log("  Mode: " .. current_mode)
                    Recorder:Log("  Towers: " .. table.concat(current_towers, ", "))
                    
                    -- Start recording for current map
                    StartNewMapRecording()
                else
                    Recorder:Log("⏳ Waiting for map detection...")
                end
                
                -- Setup map change detection
                local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
                if state_replicators then
                    local game_state_replicator = state_replicators:FindFirstChild("GameStateReplicator")
                    if game_state_replicator then
                        game_state_replicator:GetAttributeChangedSignal("Map"):Connect(function()
                            local new_map = game_state_replicator:GetAttribute("Map")
                            if new_map and new_map ~= "" and new_map ~= current_map then
                                Recorder:Log("🔄 Map changed to: " .. new_map)
                                current_map = new_map
                                StartNewMapRecording()
                            end
                        end)
                    end
                end

                sync_existing_towers()
                last_wave = 0
                Globals.record_strat = true

                Window:Notify({
                    Title = "🎥 Recorder Started",
                    Desc = "Recording for map: " .. current_map,
                    Time = 3,
                    Type = "normal"
                })
            end
        })

        RecorderTab:Button({
            Title = "STOP & SAVE",
            Desc = "Stop recording and save multi-map strategy",
            Callback = function()
                Globals.record_strat = false
                
                if #map_actions > 0 then
                    SaveMultiMapStrategy()
                    Recorder:Clear()
                    Recorder:Log("✅ Recording stopped and saved!")
                    Recorder:Log("📊 Maps recorded: " .. table.concat(table.keys(map_actions), ", "))
                    Recorder:Log("📁 Saved as: Strat_MultiMap.lua")
                    Recorder:Log("📄 Also saved individual Strat.txt")
                    
                    Window:Notify({
                        Title = "✅ Strategy Saved",
                        Desc = "Multi-map strategy saved to Strat_MultiMap.lua",
                        Time = 3,
                        Type = "normal"
                    })
                else
                    Recorder:Log("⚠️ No actions recorded!")
                    Window:Notify({
                        Title = "⚠️ No Actions",
                        Desc = "No actions recorded. Play a match first!",
                        Time = 3,
                        Type = "error"
                    })
                end
            end
        })

        RecorderTab:Button({
            Title = "SAVE CURRENT MAP ONLY",
            Desc = "Save only the current map's strategy",
            Callback = function()
                if not current_map or current_map == "Unknown" then
                    Recorder:Log("⚠️ No map detected!")
                    Window:Notify({
                        Title = "⚠️ No Map",
                        Desc = "Join a match first!",
                        Time = 3,
                        Type = "error"
                    })
                    return
                end
                
                if not map_actions[current_map] or #map_actions[current_map] == 0 then
                    Recorder:Log("⚠️ No actions for map: " .. current_map)
                    Window:Notify({
                        Title = "⚠️ No Actions",
                        Desc = "No actions recorded for " .. current_map,
                        Time = 3,
                        Type = "error"
                    })
                    return
                end
                
                if writefile then
                    local content = "local TDS = loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    content = content .. GetMapHeader()
                    content = content .. "\n-- Actions\n"
                    
                    for _, action in ipairs(map_actions[current_map]) do
                        if not action:match("^--") then
                            content = content .. action .. "\n"
                        end
                    end
                    
                    writefile("Strat_" .. current_map .. ".lua", content)
                    Recorder:Log("✅ Saved strategy for: " .. current_map)
                    Window:Notify({
                        Title = "✅ Saved",
                        Desc = "Saved strategy for: " .. current_map,
                        Time = 3,
                        Type = "normal"
                    })
                end
            end
        })

        RecorderTab:Button({
            Title = "CLEAR ALL RECORDINGS",
            Desc = "Clear all recorded map actions",
            Callback = function()
                table.clear(map_actions)
                table.clear(spawned_towers)
                tower_count = 0
                current_map_started = false
                Recorder:Clear()
                Recorder:Log("🗑️ All recordings cleared!")
                Window:Notify({
                    Title = "🗑️ Cleared",
                    Desc = "All recorded actions cleared",
                    Time = 3,
                    Type = "normal"
                })
            end
        })

        -- ============================================
        -- TOWER PLACEMENT TRACKING
        -- ============================================
        if game_state == "GAME" then
            local towers_folder = workspace_ref:WaitForChild("Towers", 5)

            towers_folder.ChildAdded:Connect(function(tower)
                if not Globals.record_strat then return end
                
                local replicator = tower:WaitForChild("TowerReplicator", 5)
                if not replicator then return end

                local owner_id = replicator:GetAttribute("OwnerId")
                if owner_id and owner_id ~= local_player.UserId then return end

                if replicator:GetAttribute("Hologram") == true then return end

                tower_count = tower_count + 1
                local my_index = tower_count
                spawned_towers[tower] = my_index

                local tower_name = replicator:GetAttribute("Name") or tower.Name
                local raw_pos = replicator:GetAttribute("Position")
                
                local pos_x, pos_y, pos_z
                if typeof(raw_pos) == "Vector3" then
                    pos_x, pos_y, pos_z = raw_pos.X, raw_pos.Y, raw_pos.Z
                else
                    local p = tower:GetPivot().Position
                    pos_x, pos_y, pos_z = p.X, p.Y, p.Z
                end
                
                local command
                if Globals.StackEnabled then
                    command = 'TDS:Place("' .. tower_name .. '", ' .. tostring(pos_x) .. ', ' .. tostring(pos_y) .. ', ' .. tostring(pos_z) .. ', true)'
                else
                    command = 'TDS:Place("' .. tower_name .. '", ' .. tostring(pos_x) .. ', ' .. tostring(pos_y) .. ', ' .. tostring(pos_z) .. ')'
                end
                record_action(command)
                Recorder:Log("📌 Placed " .. tower_name .. " (Index: " .. my_index .. ") on " .. current_map)

            end)

            towers_folder.ChildRemoved:Connect(function(tower)
                if not Globals.record_strat then return end
                
                local my_index = spawned_towers[tower]
                if my_index then
                    record_action(string.format('TDS:Sell(%d)', my_index))
                    Recorder:Log("💀 Sold Tower " .. my_index)
                    
                    spawned_towers[tower] = nil
                end
            end)
        end
        
        -- ============================================
        -- STATUS DISPLAY
        -- ============================================
        RecorderTab:Section({Title = "Status"})
        
        local MapLabel = RecorderTab:Label({Title = "Current Map: " .. current_map, Desc = ""})
        local MapCountLabel = RecorderTab:Label({Title = "Maps Recorded: 0", Desc = ""})
        local ActionsLabel = RecorderTab:Label({Title = "Total Actions: 0", Desc = ""})
        
        -- Update status periodically
        task.spawn(function()
            while true do
                task.wait(2)
                if MapLabel then
                    MapLabel:SetTitle("Current Map: " .. current_map)
                end
                if MapCountLabel then
                    local count = 0
                    for _ in pairs(map_actions) do count = count + 1 end
                    MapCountLabel:SetTitle("Maps Recorded: " .. count)
                end
                if ActionsLabel then
                    local total = 0
                    for _, actions in pairs(map_actions) do
                        total = total + #actions
                    end
                    ActionsLabel:SetTitle("Total Actions: " .. total)
                end
            end
        end)
    end
end
