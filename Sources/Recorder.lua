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
    
    local function get_wave_prefix()
        local success, current_wave = pcall(function() return replicated_storage.StateReplicators.GameStateReplicator:GetAttribute("Wave") end)
        if success and current_wave > last_wave then
            last_wave = current_wave
            return "\n-- [ Wave " .. current_wave .. " ] --\n"
        end
        return ""
    end

    local function record_action(command_str)
        if not Globals.record_strat then return end
        if appendfile then
            appendfile("Strat.txt", get_wave_prefix() .. command_str .. "\n")
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

    -- Serializes a value into a Lua literal string, indented at the given depth.
    local function serialize_config_value(v, depth)
        depth = depth or 0
        local indent = string.rep("    ", depth)
        local inner  = string.rep("    ", depth + 1)
        local t = type(v)

        if t == "string" then
            return string.format("%q", v)
        elseif t == "number" then
            return num_to_str(v)
        elseif t == "boolean" then
            return tostring(v)
        elseif t == "table" then
            -- Check if it's an array
            local is_arr, max_idx = is_array(v)
            local parts = {}
            if is_arr then
                for i = 1, max_idx do
                    table.insert(parts, inner .. serialize_config_value(v[i], depth + 1))
                end
            else
                local keys = {}
                for k in pairs(v) do table.insert(keys, k) end
                table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                for _, k in ipairs(keys) do
                    local key_str = (type(k) == "string" and k:match("^[_%a][_%w]*$"))
                        and k
                        or ("[" .. string.format("%q", tostring(k)) .. "]")
                    table.insert(parts, inner .. key_str .. " = " .. serialize_config_value(v[k], depth + 1))
                end
            end
            if #parts == 0 then
                return "{}"
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
        return "nil"
    end

    -- Builds the Config = { ... } block from a flat key->value table,
    -- with each top-level field on its own indented line.
    local function build_config_block(cfg)
        local lines = {}
        -- Fixed ordering for the well-known keys, then any extras
        local ordered_keys = { "Map", "Mode", "Loadout", "Modifiers" }
        local seen = {}
        for _, k in ipairs(ordered_keys) do
            if cfg[k] ~= nil then
                seen[k] = true
                table.insert(lines, "    " .. k .. " = " .. serialize_config_value(cfg[k], 1))
            end
        end
        -- Append any extra map keys not in the fixed list
        local extra_keys = {}
        for k in pairs(cfg) do
            if not seen[k] then table.insert(extra_keys, k) end
        end
        table.sort(extra_keys)
        for _, k in ipairs(extra_keys) do
            local key_str = (type(k) == "string" and k:match("^[_%a][_%w]*$"))
                and k
                or ("[" .. string.format("%q", tostring(k)) .. "]")
            table.insert(lines, "    " .. key_str .. " = " .. serialize_config_value(cfg[k], 1))
        end
        return "local Config = {\n" .. table.concat(lines, ",\n") .. "\n}\n"
    end

    local RecorderTab = Window:Tab({Title = "Recorder", Icon = "camera"}) do
        Recorder = RecorderTab:CreateLogger({
            Title = "RECORDER:",
            Size = UDim2.new(0, 330, 0, 230)
        })

        RecorderTab:Button({
            Title = "START",
            Desc = "",
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

                Recorder:Log("Recorder started")

                -- ── Gather game metadata ──────────────────────────────────────────

                local current_mode      = "Unknown"
                local current_map       = "Unknown"
                local skip_game_info    = false
                local raw_mod_table     = {}   -- { [ModName] = true, ... }

                local state_folder = replicated_storage:FindFirstChild("State")
                if state_folder then
                    current_mode = state_folder.Difficulty.Value
                    current_map  = state_folder.Map.Value
                    local mode_obj = state_folder:FindFirstChild("Mode")
                    if mode_obj then
                        if mode_obj.Value == "Hardcore" then
                            current_mode = (current_mode == "Hard") and "Voidcore" or "Hardcore"
                        elseif mode_obj.Value == "DuckEvent" then
                            if current_mode == "Easy" then
                                current_mode = "DuckyEasy"
                            elseif current_mode == "Hard" then
                                current_mode = "DuckyHard"
                            end
                        end
                    end
                    if current_mode == "Trial" or (mode_obj and (mode_obj.Value == "Special" or mode_obj.Value == "DuckEvent")) then
                        skip_game_info = true
                    end
                end

                local tower1, tower2, tower3, tower4, tower5 = "None", "None", "None", "None", "None"
                local state_replicators = replicated_storage:FindFirstChild("StateReplicators")

                -- Extra map attributes we want to forward to the loader
                local extra_map_data = {}

                if state_replicators then
                    -- Player loadout
                    for _, folder in ipairs(state_replicators:GetChildren()) do
                        if folder.Name == "PlayerReplicator"
                            and folder:GetAttribute("UserId") == local_player.UserId
                        then
                            local equipped = folder:GetAttribute("EquippedTowers")
                            if type(equipped) == "string" then
                                local cleaned = equipped:match("%[.*%]")
                                local ok, tbl = pcall(function()
                                    return http_service:JSONDecode(cleaned)
                                end)
                                if ok and type(tbl) == "table" then
                                    tower1 = tbl[1] or "None"
                                    tower2 = tbl[2] or "None"
                                    tower3 = tbl[3] or "None"
                                    tower4 = tbl[4] or "None"
                                    tower5 = tbl[5] or "None"
                                end
                            end
                        end

                        -- Active modifiers (kept as a real table now)
                        if folder.Name == "ModifierReplicator" then
                            local raw_votes = folder:GetAttribute("Votes")
                            if type(raw_votes) == "string" then
                                local cleaned = raw_votes:match("{.*}")
                                local ok, tbl = pcall(function()
                                    return http_service:JSONDecode(cleaned)
                                end)
                                if ok and type(tbl) == "table" then
                                    for mod_name, _ in pairs(tbl) do
                                        raw_mod_table[mod_name] = true
                                    end
                                end
                            end
                        end
                    end

                    -- Extra attributes from GameStateReplicator
                    local gsr = state_replicators:FindFirstChild("GameStateReplicator")
                    if gsr then
                        -- Extend this list with any attribute names the game exposes
                        local wanted_attrs = {
                            "MaxWaves",
                            "TotalEnemies",
                            "EnemyMultiplier",
                            "HealthMultiplier",
                            "SpeedMultiplier",
                            "RewardMultiplier",
                            "MapSeed",
                            "PlayerCount",
                            "TimeLimit",
                            "Difficulty",
                            "SubMode",
                            "Event",
                        }
                        for _, attr in ipairs(wanted_attrs) do
                            local val = gsr:GetAttribute(attr)
                            if val ~= nil then
                                extra_map_data[attr] = val
                            end
                        end
                    end

                    -- Extra attributes from the State folder itself
                    if state_folder then
                        local wanted_state = {
                            "Creator",
                            "Version",
                            "Genre",
                            "Layout",
                        }
                        for _, attr in ipairs(wanted_state) do
                            local obj = state_folder:FindFirstChild(attr)
                            if obj and obj.Value ~= nil then
                                extra_map_data[attr] = obj.Value
                            end
                        end
                    end
                end

                -- Log summary to the UI
                Recorder:Log("Mode: " .. current_mode)
                Recorder:Log("Map:  " .. current_map)
                Recorder:Log("Towers: " .. tower1 .. ", " .. tower2)
                Recorder:Log(tower3 .. ", " .. tower4 .. ", " .. tower5)

                local mod_names = {}
                for k in pairs(raw_mod_table) do table.insert(mod_names, k) end
                if #mod_names > 0 then
                    Recorder:Log("Mods: " .. table.concat(mod_names, ", "))
                end
                for k, v in pairs(extra_map_data) do
                    Recorder:Log(k .. ": " .. tostring(v))
                end

                sync_existing_towers()
                last_wave = 0
                Globals.record_strat = true

                -- ── Write the header file ─────────────────────────────────────────

                if writefile then
                    -- Build a unified Config table for the loader.
                    -- Add more fields here in the future – the loader receives
                    -- everything from a single TDS:Init(Config) call.
                    local cfg = {
                        Map      = current_map,
                        Mode     = current_mode,
                        Loadout  = { tower1, tower2, tower3, tower4, tower5 },
                        Modifiers = raw_mod_table,
                    }

                    -- Merge extra map attributes in (skip GameInfo fields for
                    -- Trial / Special / DuckEvent modes if needed)
                    if not skip_game_info then
                        for k, v in pairs(extra_map_data) do
                            cfg[k] = v
                        end
                    end

                    local config_block = build_config_block(cfg)

                    local header = table.concat({
                        'local TDS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()',
                        "",
                        config_block,
                        "TDS:Init(Config)",
                        "",
                        "",
                    }, "\n")

                    writefile("Strat.txt", header)
                end

                Window:Notify({
                    Title = "ADS",
                    Desc = "Recorder has started, you may place down your towers now.",
                    Time = 3,
                    Type = "normal"
                })
            end
        })

        RecorderTab:Button({
            Title = "STOP",
            Desc = "",
            Callback = function()
                Globals.record_strat = false
                if has_hook then
                    Recorder:Clear()
                    Recorder:Log("Strategy saved, you may find it in \nyour workspace folder called 'Strat.txt'")
                    Window:Notify({
                        Title = "ADS",
                        Desc = "Recording has been saved! Check your workspace folder for Strat.txt",
                        Time = 3,
                        Type = "normal"
                    })
                end
            end
        })

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
                Recorder:Log("Placed " .. tower_name .. " (Index: " .. my_index .. ")")
            end)

            towers_folder.ChildRemoved:Connect(function(tower)
                if not Globals.record_strat then return end
                
                local my_index = spawned_towers[tower]
                if my_index then
                    record_action(string.format('TDS:Sell(%d)', my_index))
                    Recorder:Log("Sold Tower " .. my_index)
                    spawned_towers[tower] = nil
                end
            end)
        end
    end
end
