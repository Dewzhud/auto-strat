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

    -- ─────────────────────────────────────────────
    --  MULTI-PATTERN STORAGE / EXPORT
    --  Keeps recording separate from file output.
    --  Existing recorder/event logic can therefore
    --  record into Pattern_N and export later.
    -- ─────────────────────────────────────────────
    Globals.TDSPatterns = Globals.TDSPatterns or {}
    local Patterns = Globals.TDSPatterns
    local CurrentPattern = nil
    local CurrentPatternName = nil

    local function sanitize_pattern_name(name)
        name = tostring(name or ""):gsub("[\\/:*?<>|%%"]", "_")
        name = name:gsub("%s+", "_")
        name = name:gsub("^_+", ""):gsub("_+$", "")
        if name == "" then name = "Pattern" end
        return name
    end

    local function ensure_pattern_folder()
        if not makefolder then return true end
        if isfolder and isfolder("Patterns") then return true end
        pcall(function() makefolder("Patterns") end)
        return not isfolder or isfolder("Patterns")
    end

    local function unique_pattern_name(base)
        base = sanitize_pattern_name(base)
        local name = base
        local n = 2
        while Patterns[name] do
            name = base .. "_" .. n
            n += 1
        end
        return name
    end

    local function get_pattern_count()
        local n = 0
        for _ in pairs(Patterns) do n += 1 end
        return n
    end

    local function create_pattern(name, header, resolved_mode, map_value, towers)
        local safe = unique_pattern_name(name or ("Pattern_" .. (get_pattern_count() + 1)))
        local pattern = {
            Name = safe,
            Header = header or "",
            Actions = {},
            Mode = resolved_mode or "Unknown",
            Map = map_value or "Unknown",
            Towers = towers or {"None", "None", "None", "None", "None"},
            Created = os.time(),
        }
        Patterns[safe] = pattern
        CurrentPatternName = safe
        CurrentPattern = pattern
        return pattern
    end

    local function sorted_patterns()
        local list = {}
        for _, pattern in pairs(Patterns) do
            table.insert(list, pattern)
        end
        table.sort(list, function(a, b) return tostring(a.Name):lower() < tostring(b.Name):lower() end)
        return list
    end

    local function build_pattern_output(pattern)
        if not pattern then return "" end
        local body = table.concat(pattern.Actions or {}, "\n")
        if body ~= "" then body = body .. "\n" end
        return (pattern.Header or "") .. body
    end

    local function export_pattern(pattern, filename)
        if not pattern or not writefile then return false end
        ensure_pattern_folder()
        filename = sanitize_pattern_name(filename or pattern.Name)
        pcall(function()
            writefile("Patterns/" .. filename .. ".lua", build_pattern_output(pattern))
        end)
        return true
    end

    local function export_all_patterns()
        if not writefile then return false end
        local list = sorted_patterns()
        if #list == 0 then return false end

        ensure_pattern_folder()

        local combined = "-- ========================================\n"
            .. "-- TDS RECORDER - ALL PATTERNS\n"
            .. "-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
            .. "-- ========================================\n\n"

        for _, pattern in ipairs(list) do
            combined ..= "-- ========================================\n"
            combined ..= "-- PATTERN: " .. pattern.Name .. "\n"
            combined ..= "-- ========================================\n\n"
            combined ..= build_pattern_output(pattern)
            combined ..= "\n"
        end

        pcall(function()
            writefile("All_Patterns.lua", combined)
        end)
        return true
    end

    local function export_current_pattern()
        if not CurrentPattern then return false end
        return export_pattern(CurrentPattern)
    end

    local spawned_towers = {}
    local tower_count = 0
    local last_wave = 0
    local Recorder
    local has_hook = type(hookmetamethod) == "function"

    -- ─────────────────────────────────────────────
    --  UNIVERSAL MODE RESOLVER
    --  Handles every known mode/difficulty combo
    --  and always emits TDS:GameInfo when relevant.
    -- ─────────────────────────────────────────────
    local DIFFICULTY_MAP = {
        Easy   = "Easy",
        Normal = "Normal",
        Hard   = "Hard",
        Insane = "Insane",
        Trial  = "Trial",
    }

    local MODE_OVERRIDE = {
        -- mode_value -> function(difficulty) -> resolved_mode_string
        Hardcore = function(diff)
            if diff == "Hard" then return "Voidcore" end
            return "Hardcore"
        end,
        DuckEvent = function(diff)
            if diff == "Easy"   then return "DuckyEasy"   end
            if diff == "Hard"   then return "DuckyHard"   end
            if diff == "Normal" then return "DuckyNormal" end
            return "Ducky"
        end,
        Special = function(diff)
            return "Special_" .. (diff or "Unknown")
        end,
        Endless = function(diff)
            return "Endless"
        end,
        Challenge = function(diff)
            return "Challenge"
        end,
        Event = function(diff)
            return "Event_" .. (diff or "Unknown")
        end,
    }

    -- Modes that carry extra semantic weight → always include TDS:GameInfo
    local ALWAYS_GAME_INFO = {
        Trial     = true,
        Special   = true,
        DuckEvent = true,
        Challenge = true,
        Event     = true,
    }

    local function resolve_mode(difficulty, mode_value, map_value)
        difficulty  = difficulty or "Unknown"
        mode_value  = mode_value  or ""
        map_value   = map_value   or "Unknown"

        local resolver = MODE_OVERRIDE[mode_value]
        local resolved_mode
        if resolver then
            resolved_mode = resolver(difficulty)
        else
            resolved_mode = DIFFICULTY_MAP[difficulty] or difficulty
        end

        -- Always emit TDS:GameInfo if the mode itself needs it OR if there
        -- is a non-trivial mode value set (catches future unknown modes too).
        local always = ALWAYS_GAME_INFO[mode_value] or (mode_value ~= "" and MODE_OVERRIDE[mode_value] == nil)
        return resolved_mode, always
    end

    -- ─────────────────────────────────────────────
    --  MODIFIER RESOLVER (handles any modifier set)
    -- ─────────────────────────────────────────────
    local function resolve_modifiers(state_replicators)
        local mods = {}
        if not state_replicators then return "{}", {} end

        for _, folder in ipairs(state_replicators:GetChildren()) do
            if folder.Name == "ModifierReplicator" then
                -- Try Votes attribute first (live game)
                local raw_votes = folder:GetAttribute("Votes")
                if type(raw_votes) == "string" then
                    local cleaned = raw_votes:match("{.*}")
                    if cleaned then
                        local ok, mod_table = pcall(function()
                            return http_service:JSONDecode(cleaned)
                        end)
                        if ok and type(mod_table) == "table" then
                            for name, val in pairs(mod_table) do
                                if val then
                                    table.insert(mods, { name = name, val = val })
                                end
                            end
                        end
                    end
                end

                -- Also check Active attribute (some game versions)
                local raw_active = folder:GetAttribute("Active")
                if type(raw_active) == "string" then
                    local cleaned = raw_active:match("{.*}")
                    if cleaned then
                        local ok, mod_table = pcall(function()
                            return http_service:JSONDecode(cleaned)
                        end)
                        if ok and type(mod_table) == "table" then
                            for name, val in pairs(mod_table) do
                                if val and not (function()
                                    for _, m in ipairs(mods) do
                                        if m.name == name then return true end
                                    end
                                end)() then
                                    table.insert(mods, { name = name, val = val })
                                end
                            end
                        end
                    end
                end

                -- Direct children as BoolValues (fallback)
                for _, child in ipairs(folder:GetChildren()) do
                    if child:IsA("BoolValue") and child.Value then
                        local already = false
                        for _, m in ipairs(mods) do
                            if m.name == child.Name then already = true; break end
                        end
                        if not already then
                            table.insert(mods, { name = child.Name, val = true })
                        end
                    end
                end
            end
        end

        -- Build table string and raw list
        local parts = {}
        local names  = {}
        for _, m in ipairs(mods) do
            if type(m.val) == "boolean" then
                table.insert(parts, m.name .. " = true")
            else
                table.insert(parts, m.name .. " = " .. tostring(m.val))
            end
            table.insert(names, m.name)
        end
        return "{" .. table.concat(parts, ", ") .. "}", names
    end

    -- ─────────────────────────────────────────────
    --  LOADOUT RESOLVER (5-slot, all sources)
    -- ─────────────────────────────────────────────
    local function resolve_loadout(state_replicators)
        local towers = { "None", "None", "None", "None", "None" }
        if not state_replicators then return towers end

        for _, folder in ipairs(state_replicators:GetChildren()) do
            if folder.Name == "PlayerReplicator"
                and folder:GetAttribute("UserId") == local_player.UserId then

                -- Primary: EquippedTowers attribute (JSON array)
                local equipped = folder:GetAttribute("EquippedTowers")
                if type(equipped) == "string" then
                    local cleaned = equipped:match("%[.*%]")
                    if cleaned then
                        local ok, t = pcall(function()
                            return http_service:JSONDecode(cleaned)
                        end)
                        if ok and type(t) == "table" then
                            for i = 1, 5 do
                                towers[i] = t[i] or "None"
                            end
                            break
                        end
                    end
                end

                -- Fallback: individual attributes Tower1 … Tower5
                local found = false
                for i = 1, 5 do
                    local v = folder:GetAttribute("Tower" .. i)
                    if type(v) == "string" then
                        towers[i] = v
                        found = true
                    end
                end
                if found then break end

                -- Fallback: children named "Slot1" … "Slot5"
                for i = 1, 5 do
                    local child = folder:FindFirstChild("Slot" .. i)
                    if child and type(child.Value) == "string" then
                        towers[i] = child.Value
                    end
                end
            end
        end
        return towers
    end

    -- ─────────────────────────────────────────────
    --  WAVE PREFIX
    -- ─────────────────────────────────────────────
    local function get_wave_prefix()
        local ok, w = pcall(function()
            return replicated_storage.StateReplicators
                .GameStateReplicator:GetAttribute("Wave")
        end)
        if ok and type(w) == "number" and w > last_wave then
            last_wave = w
            return "\n-- [ Wave " .. w .. " ] --\n"
        end
        return ""
    end

    local function record_action(command_str)
        if not Globals.record_strat then return end
        if not CurrentPattern then return end

        local wave_prefix = get_wave_prefix()
        if wave_prefix ~= "" then
            table.insert(CurrentPattern.Actions, wave_prefix:gsub("^\n", ""):gsub("\n$", ""))
        end
        table.insert(CurrentPattern.Actions, command_str)
    end

    local function log_line(message)
        if Recorder and Recorder.Log then
            Recorder:Log(message)
        end
    end

    local function record_line(line, message)
        record_action(line)
        if message then log_line(message) end
    end

    -- ─────────────────────────────────────────────
    --  TOWER INDEX HELPERS
    -- ─────────────────────────────────────────────
    local function resolve_tower_index(tower)
        if typeof(tower) ~= "Instance" then return nil end
        if spawned_towers[tower] then return spawned_towers[tower] end
        local current = tower.Parent
        while current do
            if spawned_towers[current] then return spawned_towers[current] end
            current = current.Parent
        end
        return nil
    end

    local function sync_existing_towers()
        if game_state ~= "GAME" then return end
        local towers_folder = workspace_ref:FindFirstChild("Towers")
        if not towers_folder then return end
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

    -- ─────────────────────────────────────────────
    --  SERIALIZERS
    -- ─────────────────────────────────────────────
    local function num_to_str(n)
        if type(n) ~= "number" then return tostring(n) end
        if n ==  math.huge then return  "math.huge" end
        if n == -math.huge then return "-math.huge" end
        if n ~= n           then return "0/0"       end
        return tostring(n)
    end

    local serialize_value, serialize_value_raw
    local serialize_table, serialize_table_raw

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
        for k in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                return false, 0
            end
            if k > max_idx then max_idx = k end
        end
        return true, max_idx
    end

    local function make_instance_expr(v)
        local full = v:GetFullName()
        if type(full) ~= "string" or full == "" then return "nil" end
        local parts = string.split(full, ".")
        local expr = 'game:GetService("' .. parts[1] .. '")'
        for i = 2, #parts do
            local p = parts[i]
            expr = expr .. (p:match("^[_%a][_%w]*$") and ("." .. p)
                                                       or ("[" .. string.format("%q", p) .. "]"))
        end
        return expr
    end

    serialize_value = function(v, depth)
        depth = depth or 0
        if depth > 4 then return "nil" end
        local t = typeof(v)
        if t == "string"  then return string.format("%q", v) end
        if t == "number"  then return num_to_str(v) end
        if t == "boolean" then return tostring(v) end
        if t == "Vector3" then
            return string.format("Vector3.new(%s, %s, %s)",
                num_to_str(v.X), num_to_str(v.Y), num_to_str(v.Z))
        end
        if t == "CFrame" then
            local comps = {v:GetComponents()}
            local parts = {}
            for i = 1, #comps do parts[i] = num_to_str(comps[i]) end
            return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
        end
        if t == "Instance" then
            local idx = resolve_tower_index(v)
            return idx and tostring(idx) or "nil"
        end
        if t == "table" then return serialize_table(v, depth + 1) end
        return "nil"
    end

    serialize_value_raw = function(v, depth)
        depth = depth or 0
        if depth > 4 then return "nil" end
        local t = typeof(v)
        if t == "string"  then return string.format("%q", v) end
        if t == "number"  then return num_to_str(v) end
        if t == "boolean" then return tostring(v) end
        if t == "Vector3" then
            return string.format("Vector3.new(%s, %s, %s)",
                num_to_str(v.X), num_to_str(v.Y), num_to_str(v.Z))
        end
        if t == "CFrame" then
            local comps = {v:GetComponents()}
            local parts = {}
            for i = 1, #comps do parts[i] = num_to_str(comps[i]) end
            return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
        end
        if t == "Instance" then return make_instance_expr(v) end
        if t == "table"    then return serialize_table_raw(v, depth + 1) end
        return "nil"
    end

    local function sorted_keys(tbl)
        local keys = {}
        for k in pairs(tbl) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys
    end

    serialize_table = function(tbl, depth)
        local is_arr, max_idx = is_array(tbl)
        local parts = {}
        if is_arr then
            for i = 1, max_idx do parts[i] = serialize_value(tbl[i], depth) end
        else
            for _, k in ipairs(sorted_keys(tbl)) do
                table.insert(parts, format_key(k) .. " = " .. serialize_value(tbl[k], depth))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end

    serialize_table_raw = function(tbl, depth)
        local is_arr, max_idx = is_array(tbl)
        local parts = {}
        if is_arr then
            for i = 1, max_idx do parts[i] = serialize_value_raw(tbl[i], depth) end
        else
            for _, k in ipairs(sorted_keys(tbl)) do
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

    -- ─────────────────────────────────────────────
    --  REMOTE CALL BUILDER
    -- ─────────────────────────────────────────────
    local function build_remote_call(remote, method, args)
        if typeof(remote) ~= "Instance" then return nil end
        local expr = make_instance_expr(remote)
        if expr == "nil" then return nil end
        local arg_parts = {}
        for i = 1, #args do arg_parts[i] = serialize_value_raw(args[i]) end
        return expr .. ":" .. method .. "(" .. table.concat(arg_parts, ", ") .. ")"
    end

    -- ─────────────────────────────────────────────
    --  NAMECALL FILTER HELPERS
    -- ─────────────────────────────────────────────
    local function is_consumable_call(remote, args)
        local function check_str(s)
            s = s:lower()
            if s:find("consum") then return true end
            if s:find("item") then return true end
        end
        local a1 = args[1]
        if type(a1) == "string" and check_str(a1) then return true end
        if typeof(remote) == "Instance" then
            local full = remote:GetFullName()
            if type(full) == "string" and check_str(full) then return true end
        end
        return false
    end

    local function any_string_contains(args, token)
        for i = 1, #args do
            if type(args[i]) == "string" and args[i]:lower():find(token, 1, true) then
                return true
            end
        end
        return false
    end

    local KEYWORD_SET = {
        troops=1, troop=1, option=1, options=1, target=1,
        ability=1, abilities=1, activate=1, set=1,
        voting=1, skip=1, inventory=1, equip=1, unequip=1, tower=1,
    }

    local function collect_non_keyword_strings(args)
        local list = {}
        for i = 1, #args do
            local v = args[i]
            if type(v) == "string" and not KEYWORD_SET[v:lower()] then
                table.insert(list, v)
            end
        end
        return list
    end

    local function find_payload(args)
        for i = 1, #args do
            local v = args[i]
            if type(v) == "table" and (v.Troop or v.troop or v.Tower or v.tower) then
                return v
            end
        end
        return nil
    end

    local function find_tower_arg(args)
        for i = 1, #args do
            if typeof(args[i]) == "Instance" and resolve_tower_index(args[i]) then
                return args[i]
            end
        end
        return nil
    end

    -- ─────────────────────────────────────────────
    --  GLOBAL HOOKS EXPOSED TO OTHER MODULES
    -- ─────────────────────────────────────────────
    Globals.__tds_record_equip = function(tower_name)
        if type(tower_name) ~= "string" then return end
        record_line(
            string.format("TDS:Equip(%s)", string.format("%q", tower_name)),
            "Equipped: " .. tower_name
        )
    end

    Globals.__tds_record_unequip = function(tower_name)
        if type(tower_name) ~= "string" then return end
        record_line(
            string.format("TDS:Unequip(%s)", string.format("%q", tower_name)),
            "Unequipped: " .. tower_name
        )
    end

    -- ─────────────────────────────────────────────
    --  NAMECALL HANDLER
    -- ─────────────────────────────────────────────
    local SKIP_ABILITIES = {
        ["Call Of Arms"]   = true,
        ["Support Caravan"]= true,
        ["Drop The Beat"]  = true,
        ["Raise The Dead"] = true,
    }

    local function handle_namecall(remote, method, args, results)
        if not Globals.record_strat then return end
        if method ~= "InvokeServer" and method ~= "FireServer" then return end

        local a1, a2, a3, a4, a5 = args[1], args[2], args[3], args[4], args[5]

        -- Abilities
        if a1 == "Troops" and a2 == "Abilities" and a3 == "Activate" then
            if type(a4) == "table" and type(a4.Name) == "string"
                and SKIP_ABILITIES[a4.Name] then return end
            if not results or results[1] ~= true then return end
            if type(a4) == "table" then
                local idx  = resolve_tower_index(a4.Troop)
                local name = a4.Name
                if idx and type(name) == "string" then
                    local data = a4.Data
                    local cmd
                    if data == nil or (type(data) == "table" and next(data) == nil) then
                        cmd = string.format("TDS:Ability(%d, %s)", idx, string.format("%q", name))
                    else
                        cmd = string.format("TDS:Ability(%d, %s, %s)", idx,
                            string.format("%q", name), serialize_value(data))
                    end
                    record_line(cmd, "Ability: " .. name .. " (Index: " .. idx .. ")")
                end
            end
            return
        end

        -- Target
        if a1 == "Troops" and a2 == "Target" and a3 == "Set" then
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local tgt = a4.Target
                if idx and type(tgt) == "string" then
                    record_line(
                        string.format("TDS:SetTarget(%d, %s)", idx, string.format("%q", tgt)),
                        "Target: " .. idx .. " -> " .. tgt
                    )
                end
            end
            return
        end

        -- Upgrade
        if a1 == "Troops" and a2 == "Upgrade" and a3 == "Set" then
            if type(a4) == "table" then
                local tower = a4.Troop
                local idx   = resolve_tower_index(tower)
                local path  = a4.Path or 1
                if idx and tower and results and results[1] == true then
                    local rep   = tower:FindFirstChild("TowerReplicator")
                    local name  = rep and rep:GetAttribute("Name") or tower.Name
                    local cmd   = path > 1
                        and string.format("TDS:Upgrade(%d, %d)", idx, path)
                        or  string.format("TDS:Upgrade(%d)", idx)
                    record_line(cmd, "Upgraded " .. name .. " (Index: " .. idx .. ")")
                end
            end
            return
        end

        -- Option
        if a1 == "Troops" and a2 == "Option" and a3 == "Set" then
            if type(a4) == "table" then
                local idx = resolve_tower_index(a4.Troop)
                local opt = a4.Name or a4.Option or a4.Key or a4.Track
                local val = a4.Value or a4.Val
                if idx and type(opt) == "string" then
                    record_line(
                        string.format("TDS:SetOption(%d, %s, %s)", idx,
                            string.format("%q", opt), serialize_value(val)),
                        "Option: " .. idx .. " " .. opt .. " = " .. tostring(val)
                    )
                end
            end
            return
        end

        -- Medic select
        if a1 == "Troops" and a2 == "TowerServerEvent" and a3 == "ToggleSelectedTower" then
            local idx  = resolve_tower_index(a4)
            local tidx = resolve_tower_index(a5)
            if idx and tidx then
                record_line(
                    string.format("TDS:MedicSelect(%d, %d)", idx, tidx),
                    "Medic: " .. idx .. " -> " .. tidx
                )
            end
            return
        end

        -- Vote / Ready
        if a1 == "Voting" and a2 == "Skip" then
            local ok, w = pcall(function()
                return replicated_storage.StateReplicators
                    .GameStateReplicator:GetAttribute("Wave")
            end)
            local current_wave = ok and w or 0
            if current_wave == 0 then
                record_line("TDS:Ready()", "Readied up for the match")
            else
                record_line(
                    "TDS:VoteSkip(" .. current_wave .. ")",
                    "Voted to skip wave " .. current_wave
                )
            end
            return
        end

        -- Equip / Unequip
        if a1 == "Inventory" and a2 == "Equip" and a3 == "tower" then
            if type(a4) == "string" then
                record_line(
                    string.format("TDS:Equip(%s)", string.format("%q", a4)),
                    "Equipped: " .. a4
                )
            end
            return
        end

        if a1 == "Inventory" and a2 == "Unequip" and a3 == "tower" then
            if type(a4) == "string" then
                record_line(
                    string.format("TDS:Unequip(%s)", string.format("%q", a4)),
                    "Unequipped: " .. a4
                )
            end
            return
        end

        -- Consumables
        if is_consumable_call(remote, args) then
            local raw = build_remote_call(remote, method, args)
            if raw then record_line(raw, "Consumable used") end
            return
        end

        -- Generic Troops fallback
        if a1 ~= "Troops" then return end

        local payload   = find_payload(args)
        local tower_obj = payload and (payload.Troop or payload.troop or payload.Tower or payload.tower)
                          or find_tower_arg(args)
        local idx = resolve_tower_index(tower_obj)
        if not idx then return end

        local strings    = collect_non_keyword_strings(args)
        local has_option = any_string_contains(args, "option") or any_string_contains(args, "track")
        local has_ability= any_string_contains(args, "abil")
        local has_target = any_string_contains(args, "target")

        if has_option then
            local opt = payload and (payload.Name or payload.Option or payload.Key or payload.Track)
                        or (#strings >= 1 and strings[1] or nil)
            local val = payload and (payload.Value or payload.Val)
                        or (#strings >= 2 and strings[2] or nil)
            if not opt and any_string_contains(args, "track") then opt = "Track" end
            if opt then
                record_line(
                    string.format("TDS:SetOption(%d, %s, %s)", idx,
                        string.format("%q", opt), serialize_value(val)),
                    "Option: " .. idx .. " " .. opt .. " = " .. tostring(val)
                )
            end
            return
        end

        if has_target then
            local tgt = (payload and payload.Target) or (#strings >= 1 and strings[1])
            if tgt then
                record_line(
                    string.format("TDS:SetTarget(%d, %s)", idx, string.format("%q", tgt)),
                    "Target: " .. idx .. " -> " .. tostring(tgt)
                )
            end
            return
        end

        if has_ability then
            local name = (payload and payload.Name) or (#strings >= 1 and strings[1])
            if name then
                local data = payload and payload.Data
                local cmd
                if data == nil or (type(data) == "table" and next(data) == nil) then
                    cmd = string.format("TDS:Ability(%d, %s)", idx, string.format("%q", name))
                else
                    cmd = string.format("TDS:Ability(%d, %s, %s)", idx,
                        string.format("%q", name), serialize_value(data))
                end
                record_line(cmd, "Ability: " .. name .. " (Index: " .. idx .. ")")
            end
            return
        end
    end

    -- ─────────────────────────────────────────────
    --  HEADER BUILDER  (universal: all modes/maps)
    -- ─────────────────────────────────────────────
    local function build_header()
        -- ── 1. difficulty + mode ──────────────────
        local difficulty   = "Unknown"
        local mode_value   = ""
        local map_value    = "Unknown"
        local round_type   = ""  -- extra tag e.g. "Fallen", "Hardcore" sub-type

        local state_folder = replicated_storage:FindFirstChild("State")
        if state_folder then
            local diff_obj = state_folder:FindFirstChild("Difficulty")
            if diff_obj then
                difficulty = diff_obj.Value or difficulty
            end

            local map_obj = state_folder:FindFirstChild("Map")
            if map_obj then
                map_value = map_obj.Value or map_value
            end

            local mode_obj = state_folder:FindFirstChild("Mode")
            if mode_obj then
                mode_value = mode_obj.Value or ""
            end

            -- Also check RoundType / SubMode for extra detail
            local rt = state_folder:FindFirstChild("RoundType") or state_folder:FindFirstChild("SubMode")
            if rt then round_type = rt.Value or "" end
        end

        -- Fallback: read from GameStateReplicator attributes
        if difficulty == "Unknown" then
            local ok, v = pcall(function()
                return replicated_storage.StateReplicators
                    .GameStateReplicator:GetAttribute("Difficulty")
            end)
            if ok and v then difficulty = tostring(v) end
        end
        if map_value == "Unknown" then
            local ok, v = pcall(function()
                return replicated_storage.StateReplicators
                    .GameStateReplicator:GetAttribute("Map")
            end)
            if ok and v then map_value = tostring(v) end
        end
        if mode_value == "" then
            local ok, v = pcall(function()
                return replicated_storage.StateReplicators
                    .GameStateReplicator:GetAttribute("Mode")
            end)
            if ok and v then mode_value = tostring(v) end
        end

        local resolved_mode, need_game_info = resolve_mode(difficulty, mode_value, map_value)

        -- ── 2. modifiers ─────────────────────────
        local state_replicators = replicated_storage:FindFirstChild("StateReplicators")
        local mod_str, mod_names = resolve_modifiers(state_replicators)
        local has_mods = (#mod_names > 0)

        -- ── 3. loadout ────────────────────────────
        local towers = resolve_loadout(state_replicators)

        -- ── 4. game info line ─────────────────────
        -- Always emit TDS:GameInfo when:
        --   • mode requires it (Trial, Special, DuckEvent, etc.)
        --   • there are active modifiers
        --   • round_type carries extra info
        local game_info_line = ""
        if need_game_info or has_mods or round_type ~= "" then
            local gi_mod = has_mods and mod_str or "{}"
            if round_type ~= "" then
                game_info_line = string.format(
                    '\nTDS:GameInfo("%s", %s, "%s")',
                    map_value, gi_mod, round_type
                )
            else
                game_info_line = string.format(
                    '\nTDS:GameInfo("%s", %s)',
                    map_value, gi_mod
                )
            end
        end

        -- ── 5. assemble ───────────────────────────
        return string.format([[
local TDS = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()

TDS:Loadout("%s", "%s", "%s", "%s", "%s")
TDS:Mode("%s")%s

]],
            towers[1], towers[2], towers[3], towers[4], towers[5],
            resolved_mode,
            game_info_line
        ), resolved_mode, map_value, towers
    end

    -- ─────────────────────────────────────────────
    --  UI TAB
    -- ─────────────────────────────────────────────
    local RecorderTab = Window:Tab({ Title = "Recorder", Icon = "camera" })
    do
        Recorder = RecorderTab:CreateLogger({
            Title = "RECORDER:",
            Size  = UDim2.new(0, 330, 0, 230),
        })

        RecorderTab:Button({
            Title    = "START",
            Desc     = "",
            Callback = function()
                Recorder:Clear()

                if not has_hook then
                    Recorder:Log(
                        "\nYour executor is not supported for recording.\n"
                        .. "It is only usable for replaying strats."
                    )
                    return
                end

                -- Install hook once
                Globals.__tds_recorder_handler = function(remote, method, args, results)
                    handle_namecall(remote, method, args, results)
                end

                if not Globals.__tds_recorder_hooked then
                    Globals.__tds_recorder_hooked = true
                    local original
                    original = hookmetamethod(game, "__namecall", function(self, ...)
                        local method  = getnamecallmethod and getnamecallmethod() or nil
                        local args    = { ... }
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

                -- Build header (universal)
                local header, resolved_mode, map_value, towers = build_header()

                -- Start a NEW independent pattern.
                local requested_name = CurrentPatternName
                if not requested_name or Patterns[requested_name] then
                    requested_name = "Pattern_" .. (get_pattern_count() + 1)
                end
                local pattern = create_pattern(requested_name, header, resolved_mode, map_value, towers)

                Recorder:Log("Recorder started")
                Recorder:Log("Pattern: " .. pattern.Name)
                Recorder:Log("Mode: " .. resolved_mode)
                Recorder:Log("Map:  " .. map_value)
                Recorder:Log("T1/2: " .. towers[1] .. ", " .. towers[2])
                Recorder:Log("T3/4: " .. towers[3] .. ", " .. towers[4])
                Recorder:Log("T5:   " .. towers[5])

                sync_existing_towers()
                last_wave = 0
                Globals.record_strat = true

                Window:Notify({
                    Title = "RECORDER",
                    Desc  = "Recording " .. pattern.Name .. ". Place your towers now.",
                    Time  = 3,
                    Type  = "normal",
                })
            end,
        })

        RecorderTab:Button({
            Title    = "STOP",
            Desc     = "",
            Callback = function()
                Globals.record_strat = false
                if has_hook then
                    Recorder:Clear()

                    if CurrentPattern then
                        export_pattern(CurrentPattern)

                        -- Backward-compatible single-file output.
                        if writefile then
                            pcall(function()
                                writefile("Strat.txt", build_pattern_output(CurrentPattern))
                            end)
                        end

                        Recorder:Log("Pattern saved: Patterns/" .. CurrentPattern.Name .. ".lua")
                        Recorder:Log("Actions: " .. tostring(#CurrentPattern.Actions))
                    else
                        Recorder:Log("No active pattern.")
                    end

                    Window:Notify({
                        Title = "RECORDER",
                        Desc  = CurrentPattern
                            and ("Saved " .. CurrentPattern.Name .. " to Patterns/")
                            or "No active pattern to save.",
                        Time  = 3,
                        Type  = "normal",
                    })
                end
            end,
        })

        RecorderTab:Button({
            Title = "NEW PATTERN",
            Desc = "Select a new name before starting the next recording.",
            Callback = function()
                local next_name = "Pattern_" .. (get_pattern_count() + 1)
                CurrentPatternName = unique_pattern_name(next_name)
                Recorder:Log("Next pattern: " .. CurrentPatternName)
                Window:Notify({
                    Title = "RECORDER",
                    Desc = "Next recording will use " .. CurrentPatternName,
                    Time = 3,
                    Type = "normal",
                })
            end,
        })

        RecorderTab:Button({
            Title = "EXPORT CURRENT",
            Desc = "Export the selected/current pattern as its own Lua file.",
            Callback = function()
                if export_current_pattern() then
                    Recorder:Log("Exported: Patterns/" .. CurrentPattern.Name .. ".lua")
                    Window:Notify({
                        Title = "RECORDER",
                        Desc = "Exported " .. CurrentPattern.Name,
                        Time = 3,
                        Type = "normal",
                    })
                else
                    Recorder:Log("No pattern available to export.")
                end
            end,
        })

        RecorderTab:Button({
            Title = "EXPORT ALL PATTERNS",
            Desc = "Export every recorded pattern into All_Patterns.lua.",
            Callback = function()
                if export_all_patterns() then
                    Recorder:Log("Exported all patterns to All_Patterns.lua")
                    Window:Notify({
                        Title = "RECORDER",
                        Desc = "All patterns exported.",
                        Time = 3,
                        Type = "normal",
                    })
                else
                    Recorder:Log("No patterns available to export.")
                end
            end,
        })

        RecorderTab:Button({
            Title = "LIST PATTERNS",
            Desc = "Show all recorded patterns in the recorder log.",
            Callback = function()
                Recorder:Clear()
                local list = sorted_patterns()
                if #list == 0 then
                    Recorder:Log("No recorded patterns.")
                    return
                end

                Recorder:Log("Recorded patterns: " .. tostring(#list))
                for i, pattern in ipairs(list) do
                    local selected = CurrentPattern == pattern and " [CURRENT]" or ""
                    Recorder:Log(
                        string.format(
                            "%d. %s%s | %d actions | %s | %s",
                            i,
                            pattern.Name,
                            selected,
                            #(pattern.Actions or {}),
                            tostring(pattern.Mode),
                            tostring(pattern.Map)
                        )
                    )
                end
            end,
        })

        -- Tower placement / removal listeners (only in GAME state)
        if game_state == "GAME" then
            local towers_folder = workspace_ref:WaitForChild("Towers", 5)

            if towers_folder then
                towers_folder.ChildAdded:Connect(function(tower)
                    if not Globals.record_strat then return end

                    local replicator = tower:WaitForChild("TowerReplicator", 5)
                    if not replicator then return end
                    if replicator:GetAttribute("OwnerId") ~= local_player.UserId then return end
                    if replicator:GetAttribute("Hologram") == true then return end

                    tower_count += 1
                    local my_index = tower_count
                    spawned_towers[tower] = my_index

                    local tower_name = replicator:GetAttribute("Name") or tower.Name
                    local raw_pos    = replicator:GetAttribute("Position")
                    local px, py, pz

                    if typeof(raw_pos) == "Vector3" then
                        px, py, pz = raw_pos.X, raw_pos.Y, raw_pos.Z
                    else
                        local p = tower:GetPivot().Position
                        px, py, pz = p.X, p.Y, p.Z
                    end

                    local stack_flag = Globals.StackEnabled and ", true" or ""
                    local cmd = string.format(
                        'TDS:Place("%s", %s, %s, %s%s)',
                        tower_name,
                        num_to_str(px), num_to_str(py), num_to_str(pz),
                        stack_flag
                    )
                    record_action(cmd)
                    Recorder:Log("Placed " .. tower_name .. " (Index: " .. my_index .. ")")
                end)

                towers_folder.ChildRemoved:Connect(function(tower)
                    if not Globals.record_strat then return end
                    local my_index = spawned_towers[tower]
                    if my_index then
                        record_action(string.format("TDS:Sell(%d)", my_index))
                        Recorder:Log("Sold Tower " .. my_index)
                        spawned_towers[tower] = nil
                    end
                end)
            end
        end
    end
end
