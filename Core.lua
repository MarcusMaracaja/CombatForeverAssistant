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
    local ok, suggestion = pcall(mod.GetSuggestion, mod)
    if not ok then return end
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
    local nodes = spec.nodes
    if type(nodes) ~= "table" then return false end
    local disabled = (type(module.GetRotationDisabled) == "function" and module.GetRotationDisabled(specKey)) or nil
    local preds = type(module.RotationPredicates) == "table" and module.RotationPredicates or {}
    for _, node in ipairs(nodes) do
        if node.enabled ~= false and not (disabled and disabled[node.id]) then
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
    return false
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
