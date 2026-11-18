-- Combat Forever Assistant — Core.
-- Owns SavedVariables, the suggestion pipeline and the action-bar button map.
-- Modules register with CFA:RegisterModule and implement :GetSuggestion().

local addonName, addon = ...
_G[addonName] = addon

CFA = addon
local L = addon.L

-- Defaults (filled lazily so old settings survive schema changes).
local defaults = {
    visualMode = "circle",      -- "circle" | "border"
    borderWidth = 12,           -- px used by border mode
    keyButton = true,
    keyButtonLocked = false,
    keyButtonAlways = false,
    keySize = 46,
    keyFont = "Fonts\\FRIZQT__.TTF",
    keyBgColor = { 0.05, 0.05, 0.05 },
    keyBgAlpha = 0.72,
    keyTextColor = { 1.0, 0.9, 0.3 },
    warnOutdated = true,
    RotationEditor = {},
}

local function initDB()
    if type(CombatForeverAssistantDB) ~= "table" then
        CombatForeverAssistantDB = {}
    end
    if type(CombatForeverAssistantCharDB) ~= "table" then
        CombatForeverAssistantCharDB = {}
    end
    addon.db = CombatForeverAssistantDB
    addon.charDb = CombatForeverAssistantCharDB

    for k, v in pairs(defaults) do
        if addon.db[k] == nil then
            addon.db[k] = v
        end
    end
end

-- Initialize fallback tables at load time so other files don't fail before ADDON_LOADED
initDB()

addon.modules = {}
addon.activeModule = nil

function addon:RegisterModule(classTag, module)
    module.classTag = classTag
    self.modules[classTag] = module
    if module.OnRegister then pcall(module.OnRegister, module) end
end

function addon:GetModuleForPlayer()
    local _, class = UnitClass("player")
    return self.modules[class]
end

-- ---------------------------------------------------------------------------
-- Event frame
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "CombatForeverAssistantCore", UIParent)
local TICK = 0.2
local elapsed = 0
local lastErrorPrint = 0

local function playerCanRun()
    return UnitExists("player") and not UnitIsDeadOrGhost("player")
end

frame:SetScript("OnEvent", function(_, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        initDB()
        addon.activeModule = addon:GetModuleForPlayer()
        if addon.activeModule and addon.activeModule.OnEnable then
            pcall(addon.activeModule.OnEnable, addon.activeModule)
        end
        if addon.db.warnOutdated then
            pcall(addon.CheckOutdatedRanks, addon)
        end
        if addon.Minimap then addon.Minimap.Refresh() end
        pcall(addon.PrintWelcome, addon)
    elseif event == "PLAYER_ENTERING_WORLD" then
        if addon.Visuals then addon.Visuals.RefreshMap() end
    elseif event == "SPELLS_CHANGED" or event == "UPDATE_BINDINGS"
        or event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        if addon.Visuals then addon.Visuals.RefreshMap() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- entering combat: nothing special yet
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end
    elapsed = 0
    if not playerCanRun() then return end
    local mod = addon.activeModule
    if not mod or not mod.GetSuggestion then return end
    -- Test-flash (icon click in the editor / /cfa test) wins over the rotation
    if addon.Visuals and addon.Visuals.flashSpell and GetTime() < (addon.Visuals.flashUntil or 0) then
        addon.Visuals.Show(addon.Visuals.flashSpell, addon.Visuals.flashColor or "Utility")
        return
    elseif addon.Visuals then
        addon.Visuals.flashSpell, addon.Visuals.flashUntil = nil, nil
    end
    local ok, suggestion = pcall(mod.GetSuggestion, mod)
    if not ok then
        -- Never fail silently: surface the first error and throttle repeats.
        addon.lastError = tostring(suggestion)
        local now = GetTime()
        if now - lastErrorPrint > 10 then
            lastErrorPrint = now
            print(string.format(L["rotation_error"] or "[CFA] Rotation error: %s", tostring(suggestion)))
        end
        return
    end
    if addon.Visuals then
        if suggestion then
            addon.Visuals.Show(suggestion.spellID, suggestion.color or "Utility")
        else
            addon.Visuals.Hide()
        end
    end
    if addon.KeyButton then
        if suggestion and addon.db.keyButton then
            addon.KeyButton.ShowFor(suggestion.spellID)
        elseif addon.db.keyButton and addon.db.keyButtonAlways then
            addon.KeyButton.ShowPlaceholder()
        else
            addon.KeyButton.Hide()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Compat layer (modern engine: globals may have moved into C_Spell / C_SpellBook)
-- ---------------------------------------------------------------------------
addon.Compat = {}

function addon.Compat.SpellInfoByID(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then
            -- `subName` carries "Rank N" on retail-style APIs when present
            return info.name, info.subName or info.rank
        end
    end
    if GetSpellInfo then
        local ok, name, rank = pcall(GetSpellInfo, id)
        if ok then return name, rank end
    end
    return nil
end

function addon.Compat.SpellBookItem(i, bookType)
    bookType = bookType or BOOKTYPE_SPELL or "spell"
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bookType)
        if ok and type(info) == "table" then
            return info.name, info.subName or info.rank
        end
    end
    if GetSpellBookItemName then
        local ok, name, rank = pcall(GetSpellBookItemName, i, bookType)
        if ok then return name, rank end
    end
    return nil
end

-- Highest rank the player actually knows for a spellID (same base name).
-- Cached per id for the session.
local _highestKnownCache = {}
function addon.Compat.HighestKnownSpellID(id)
    if not id then return nil end
    if _highestKnownCache[id] then return _highestKnownCache[id] end
    local base = nil
    if addon.Compat.SpellInfoByID then
        local name = addon.Compat.SpellInfoByID(id)
        if name then base = name:gsub("%s*%b()%s*$", "") end
    end
    if not base then
        _highestKnownCache[id] = id
        return id
    end
    local bestID, bestRank = id, 0
    for i = 1, 300 do
        local name, rank = addon.Compat.SpellBookItem(i, "spell")
        if name == nil then break end
        local nBase = name:gsub("%s*%b()%s*$", "")
        if nBase == base then
            local entryID = nil
            if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, "spell")
                if ok and type(info) == "table" then entryID = info.identifier or info.spellID end
            end
            if not entryID and type(GetSpellLink) == "function" then
                local ok, link = pcall(GetSpellLink, i, "spell")
                if ok and type(link) == "string" then
                    entryID = tonumber(link:match("spell:(%d+)"))
                end
            end
            local rankNum = tonumber((tostring(rank or ""):match("%d+"))) or 0
            if entryID and (rankNum > bestRank or (rankNum == bestRank and not entryID)) then
                bestID, bestRank = entryID, rankNum
            end
        end
    end
    _highestKnownCache[id] = bestID
    return bestID
end

-- ---------------------------------------------------------------------------
-- Outdated-rank warning (chat, at login) — best effort; silently no-ops if the
-- client exposes no rank info.
-- ---------------------------------------------------------------------------
local SPELLBOOK_RANKS = {}
local function parseRank(rankStr)
    if not rankStr then return 0 end
    local n = tostring(rankStr):match("(%d+)")
    return tonumber(n) or 0
end

local function spellbookMaxRank(baseName)
    if SPELLBOOK_RANKS[baseName] then return SPELLBOOK_RANKS[baseName] end
    local maxRank = 0
    for i = 1, 300 do
        local name, rank = addon.Compat.SpellBookItem(i, "spell")
        if not name then break end
        if name == baseName then
            maxRank = math.max(maxRank, parseRank(rank))
        end
    end
    SPELLBOOK_RANKS[baseName] = maxRank
    return maxRank
end

function addon:CheckOutdatedRanks()
    for k in pairs(SPELLBOOK_RANKS) do SPELLBOOK_RANKS[k] = nil end
    pcall(function()
        for slot = 1, 120 do
            local actionType, id = GetActionInfo(slot)
            if actionType == "spell" and id then
                local name, rank = addon.Compat.SpellInfoByID(id)
                if name then
                    local best = spellbookMaxRank(name)
                    local have = parseRank(rank)
                    if best > 0 and have > 0 and have < best then
                        print(string.format(L["outdated_warning"], name, have, best))
                    end
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Fine-grained filters — 6 cascade axes, each node may restrict under which
-- conditions it fires. 0 = "any/both" (always passes).
-- ---------------------------------------------------------------------------
addon.FilterAxes = {
    { key = "combat",   labelKey = "rot_axis_combat",
      options = { { 1, "axis_in_combat" }, { 2, "axis_out_combat" } } },
    { key = "env",      labelKey = "rot_axis_env",
      options = { { 1, "PvE" }, { 2, "PvP" } } },  -- literal PvE/PvP labels
    { key = "target",   labelKey = "rot_axis_target",
      options = { { 1, "axis_attackable" }, { 2, "axis_casting" }, { 3, "axis_no_attack" } } },
    { key = "range",    labelKey = "rot_axis_range",
      options = { { 1, "axis_ranged" }, { 2, "axis_melee" }, { 3, "axis_dead_zone" } } },
    { key = "resource", labelKey = "rot_axis_resource",
      options = { { 1, "axis_mana15" }, { 2, "axis_mana40" }, { 3, "axis_mana50" },
                  { 4, "axis_rage40" }, { 5, "axis_energy40" }, { 6, "axis_combo5" } } },
    { key = "aoe",      labelKey = "rot_axis_aoe",
      options = { { 1, "axis_aoe_2" }, { 2, "axis_single" } } },
}

local FILTER_EVALS = {
    combat   = function(env, v)
        if v == 1 then return env.inCombat and true or false end
        if v == 2 then return not env.inCombat and true or false end
        return true
    end,
    env      = function(env, v)
        if v == 1 then return not env.isPvP and true or false end
        if v == 2 then return env.isPvP and true or false end
        return true
    end,
    target   = function(env, v)
        if v == 1 then return env.hasActiveEnemy and true or false end
        if v == 2 then return env.targetCasting and true or false end
        if v == 3 then return not env.hasActiveEnemy and true or false end
        return true
    end,
    range    = function(env, v)
        local tooClose = env.tooCloseForRanged == true
        local melee = env.isMelee == true
        if v == 1 then return not tooClose and not melee and true or false end
        if v == 2 then return (tooClose or melee) and true or false end
        if v == 3 then return (tooClose and not melee) and true or false end
        return true
    end,
    resource = function(env, v)
        if v == 1 then return (env.manaPct or 0) > 15 end
        if v == 2 then return (env.manaPct or 0) > 40 end
        if v == 3 then return (env.manaPct or 0) > 50 end
        if v == 4 then return (env.rage or 0) >= 40 end
        if v == 5 then return (env.energy or 0) >= 40 end
        if v == 6 then return (env.combo or 0) >= 5 end
        return true
    end,
    aoe      = function(env, v)
        if v == 1 then return env.isAoE and true or false end
        if v == 2 then return not env.isAoE and true or false end
        return true
    end,
}

function addon.NodeFilterPass(env, filter)
    if type(filter) ~= "table" then return true end
    for _, axis in ipairs(addon.FilterAxes) do
        local v = tonumber(filter[axis.key]) or 0
        if v ~= 0 then
            local fn = FILTER_EVALS[axis.key]
            if fn and not fn(env, v) then return false end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Declarative rotation engine (used by class modules)
-- ---------------------------------------------------------------------------
function addon:ConcatCommonNodes(common, nodes)
    local out = {}
    for _, n in ipairs(common or {}) do out[#out + 1] = n end
    for _, n in ipairs(nodes or {}) do out[#out + 1] = n end
    return out
end

function addon:RunDeclaredRotation(module, specKey, env)
    if type(module) ~= "table" then return false end
    local specs = module.RotationSpecs
    if type(specs) ~= "table" then return false end
    local spec = specs[specKey]
    if not spec then return false end
    -- Modules may merge per-character overrides (enabled/condition/filter)
    local nodes = (type(module.GetEffectiveNodes) == "function" and module:GetEffectiveNodes(specKey)) or spec.nodes
    if type(nodes) ~= "table" then return false end
    local disabled = (type(module.GetRotationDisabled) == "function" and module.GetRotationDisabled(specKey)) or nil
    local preds = type(module.RotationPredicates) == "table" and module.RotationPredicates or {}
    for _, node in ipairs(nodes) do
        if node.enabled ~= false and not (disabled and disabled[node.id]) then
            if addon.NodeFilterPass(env, node.filter) then
                local pass = true
                local cond = node.condition
                if cond and cond ~= "" then
                    local p = preds[cond]
                    if type(p) == "table" and type(p.fn) == "function" then
                        local ok, r = pcall(p.fn, env)
                        pass = ok and r and true or false
                    else
                        pass = true
                    end
                end
                if pass then
                    local knownID = addon.Compat.HighestKnownSpellID(node.spellID) or node.spellID
                    if module:TryFlash(knownID, node.color, function() return true end, node.name, env) then
                        if not node.passthrough then return true end
                    end
                end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Flash test: highlights the buttons bound to a spell for a short time
-- (used by the rotation editor's icon click; global, all classes).
-- ---------------------------------------------------------------------------
function addon:FlashSpell(spellID, color, duration)
    if not spellID then return false end
    duration = duration or 1.5
    local known = spellID
    if addon.Compat and addon.Compat.HighestKnownSpellID then
        known = addon.Compat.HighestKnownSpellID(spellID) or spellID
    end
    local function baseName(n)
        return n and n:gsub("%s*%b()%s*$", ""):lower() or nil
    end
    local want = baseName(addon.Compat.SpellInfoByID(known)) or tostring(known)
    local found = false
    if addon.Visuals and addon.Visuals.FindButtons then
        for _, btn in ipairs(addon.Visuals.FindButtons(known)) do found = true break end
    end
    if not found then
        print(addon.L["rot_not_on_bar"])
        return false
    end
    addon.Visuals.flashSpell = known
    addon.Visuals.flashUntil = GetTime() + duration
    addon.Visuals.flashColor = color or "Utility"
    return true
end

-- ---------------------------------------------------------------------------
-- Welcome message (login): class, spec and race greeting
-- ---------------------------------------------------------------------------
local RACE_GREETING_KEYS = {
    Human = "race_human", Dwarf = "race_dwarf", NightElf = "race_nightelf",
    Gnome = "race_gnome", Orc = "race_orc", Scourge = "race_undead", Undead = "race_undead",
    Tauren = "race_tauren", Troll = "race_troll",
    HighOrderSkyborne = "race_highorder", WindshaperSkyborne = "race_windshaper",
}
local RACE_NAME_ALIASES = {
    ["humano"] = "Human", ["anão"] = "Dwarf", ["anao"] = "Dwarf", ["dwarf"] = "Dwarf",
    ["elfo noturno"] = "NightElf", ["nightelf"] = "NightElf", ["gnomo"] = "Gnome",
    ["orc"] = "Orc", ["morto-vivo"] = "Scourge", ["mortovivo"] = "Scourge", ["undead"] = "Undead",
    ["tauren"] = "Tauren", ["troll"] = "Troll", ["skyborne"] = "HighOrderSkyborne",
}
local function normalizeRaceName(s)
    if type(s) ~= "string" then return nil end
    s = s:lower()
    local ok, stripped = pcall(function() return s:gsub("[áàâãä]", "a"):gsub("[éèêë]", "e"):gsub("[íìîï]", "i"):gsub("[óòôõö]", "o"):gsub("[úùûü]", "u"):gsub("[ç]", "c") end)
    if ok then s = stripped end
    return (s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

function addon:GetRaceGreeting()
    if type(UnitRace) ~= "function" then return nil end
    local name, token = UnitRace("player")
    local key = RACE_GREETING_KEYS[token]
    if not key then
        local alias = RACE_NAME_ALIASES[normalizeRaceName(name)]
        key = alias and RACE_GREETING_KEYS[alias] or nil
    end
    return key and addon.L[key] or nil
end

function addon:PrintWelcome()
    local className = UnitClass("player")
    print(string.format(addon.L["welcome_loaded"], tostring(className)))
    local mod = addon.activeModule
    if mod and type(mod.DetectSpec) == "function" then
        local ok, spec, source = pcall(mod.DetectSpec, mod)
        if ok and spec then
            local specName = addon.L["spec_" .. spec:lower()] or spec
            print(string.format(addon.L["welcome_spec"], tostring(specName), tostring(source or "?")))
        end
    end
    local greet = addon:GetRaceGreeting()
    if greet then print(string.format(addon.L["welcome_race"], greet)) end
end

SLASH_COMBATFOREVERASSISTANT1 = "/cfa"
SlashCmdList["COMBATFOREVERASSISTANT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        if addon.Options then addon.Options.Toggle() end
    elseif msg == "status" then
        if addon.activeModule and addon.activeModule.GetStatus then
            print(string.format(L["status_module"], tostring(addon.activeModule:GetStatus())))
        else
            print(L["status_no_module"])
        end
        if addon.lastError then
            print(string.format(L["rotation_error"], addon.lastError))
        end
    elseif msg == "key" then
        addon.db.keyButton = not addon.db.keyButton
        print(addon.db.keyButton and L["key_button_shown"] or L["key_button_hidden"])
    elseif msg == "minimap" then
        addon.db.minimapHidden = not addon.db.minimapHidden
        if addon.Minimap then addon.Minimap.Refresh() end
        print(addon.db.minimapHidden and L["minimap_hidden"] or L["minimap_shown"])
    else
        print(L["slash_help"])
    end
end
