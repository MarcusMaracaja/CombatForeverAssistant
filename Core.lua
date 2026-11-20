-- Combat Forever Assistant — Core.
-- Owns SavedVariables, the suggestion pipeline and the action-bar button map.
-- Modules register with CFA:RegisterModule and implement :GetSuggestion().

local addonName, addon = ...
_G[addonName] = addon

CFA = addon
local L = addon.L

-- Defaults (filled lazily so old settings survive schema changes).
local defaults = {
    visualMode = "circle",      -- "circle" | "border" | "flame" | "lightning" | "zoom"
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

-- ---------------------------------------------------------------------------
-- Modo de diagnóstico (/cfa debug on) — prints detalhados do pipeline.
-- Desligado por padrão (zero impacto em produção).
-- ---------------------------------------------------------------------------
addon.debugMode = false

function addon:DebugPrint(...)
    if not self.debugMode then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print("|cff44ddff[CFA dbg]|r " .. table.concat(parts, " "))
end

-- Relatório pontual das APIs usadas pela rotação (sem depender de estado).
function addon:DebugProbe()
    local function P(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("|cff44ddff[CFA probe]|r " .. table.concat(parts, " "))
    end
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    P("class=", class, "race=", race, "target=", tostring(UnitExists("target")))
    P("UnitAffectingCombat existe:", tostring(type(UnitAffectingCombat) == "function"),
        "InCombatLockdown existe:", tostring(type(InCombatLockdown) == "function"))
    if type(UnitAffectingCombat) == "function" then
        local ok, v = pcall(UnitAffectingCombat, "player")
        P("UnitAffectingCombat(player)=", tostring(v), "ok=", tostring(ok))
    end
    if type(InCombatLockdown) == "function" then
        local ok, v = pcall(InCombatLockdown)
        P("InCombatLockdown()=", tostring(v), "ok=", tostring(ok))
    end
    local okCA, canAttack = pcall(UnitCanAttack, "player", "target")
    P("UnitCanAttack(player,target)=", tostring(canAttack), "ok=", tostring(okCA))
    if type(UnitDistanceSquared) == "function" then
        local okD, sq, checked = pcall(UnitDistanceSquared, "target")
        P("UnitDistanceSquared=", tostring(sq), "checked=", tostring(checked), "ok=", tostring(okD))
    end
    P("C_Spell.IsSpellInRange existe:", tostring(C_Spell and type(C_Spell.IsSpellInRange) == "function"))
    P("C_Spell.IsSpellUsable existe:", tostring(C_Spell and type(C_Spell.IsSpellUsable) == "function"))
    P("C_Spell.GetSpellCooldown existe:", tostring(C_Spell and type(C_Spell.GetSpellCooldown) == "function"))
    P("C_SpellBook.IsSpellKnownOrInSpellBook existe:",
        tostring(C_SpellBook and type(C_SpellBook.IsSpellKnownOrInSpellBook) == "function"))
    for _, id in ipairs({ 75, 5118, 13165, 1978, 3044, 2643, 19434 }) do
        local name = self.Compat.SpellInfoByID(id)
        local known = self.Compat.SpellKnown(id)
        local cd, dur = self.Compat.SpellCooldown(id)
        P("spell", id, "nome=", tostring(name), "known=", tostring(known),
            "cd=", tostring(cd), "dur=", tostring(dur))
    end
    local aok, aura = pcall(function()
        return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
    end)
    P("aura#1 ok=", tostring(aok), "nome=", tostring(aura and aura.name), "spellId=", tostring(aura and aura.spellId))
end

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
    -- caches de "spell conhecida" são invalidados quando o spellbook muda
    if (event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN")
        and addon.Compat and addon.Compat.InvalidateSpellCaches then
        addon.Compat.InvalidateSpellCaches()
    end
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
    elseif event == "START_AUTOREPEAT_SPELL" then
        addon.AutoShoot = true
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        addon.AutoShoot = nil
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("START_AUTOREPEAT_SPELL")
frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")

local lastEquipmentErrorPrint = 0
local function updateSuggestionDisplay(suggestion, module)
    local suggestions = {}
    if type(suggestion) == "table" then
        suggestions[#suggestions + 1] = suggestion
        if type(suggestion.additional) == "table" then
            for _, extra in ipairs(suggestion.additional) do
                suggestions[#suggestions + 1] = extra
            end
        end
    end
    if addon.Equipment and type(addon.Equipment.GetSuggestions) == "function" then
        local ok, extras = pcall(addon.Equipment.GetSuggestions, module)
        if ok and type(extras) == "table" then
            for _, extra in ipairs(extras) do suggestions[#suggestions + 1] = extra end
        elseif not ok then
            local now = GetTime()
            addon.lastError = tostring(extras)
            if now - lastEquipmentErrorPrint > 10 then
                lastEquipmentErrorPrint = now
                print("[CFA] Equipment recommendation error: " .. tostring(extras))
            end
        else
            local now = GetTime()
            addon.lastError = "Equipment.GetSuggestions must return a table"
            if now - lastEquipmentErrorPrint > 10 then
                lastEquipmentErrorPrint = now
                print("[CFA] Equipment recommendation error: expected a table of suggestions")
            end
        end
    end
    if addon.Visuals then
        if #suggestions > 0 and addon.Visuals.ShowMany then
            addon.Visuals.ShowMany(suggestions)
        elseif suggestion and suggestion.spellID then
            addon.Visuals.Show(suggestion.spellID, suggestion.color or "Utility")
        else
            addon.Visuals.Hide()
        end
    end
    if addon.KeyButton then
        if suggestion and suggestion.spellID and addon.db.keyButton then
            addon.KeyButton.ShowFor(suggestion.spellID)
        elseif addon.db.keyButton and addon.db.keyButtonAlways then
            addon.KeyButton.ShowPlaceholder()
        else
            addon.KeyButton.Hide()
        end
    end
end

frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end
    elapsed = 0
    if not playerCanRun() then return end
    if not addon.welcomeSent then
        addon.welcomeSent = true
        pcall(addon.PrintWelcome, addon)
    end
    local mod = addon.activeModule
    -- Test-flash (icon click in the editor / /cfa test) wins over the rotation
    if addon.Visuals and addon.Visuals.flashSpell and GetTime() < (addon.Visuals.flashUntil or 0) then
        addon.Visuals.Show(addon.Visuals.flashSpell, addon.Visuals.flashColor or "Utility")
        return
    elseif addon.Visuals then
        -- flash expired: make sure nothing stays lit
        addon.Visuals.flashSpell, addon.Visuals.flashUntil = nil, nil
        if addon.Visuals.Hide then addon.Visuals.Hide() end
        if addon.KeyButton then
            if addon.db.keyButtonAlways then addon.KeyButton.ShowPlaceholder() else addon.KeyButton.Hide() end
        end
    end
    if not mod or not mod.GetSuggestion then
        updateSuggestionDisplay(nil, mod)
        return
    end
    local ok, suggestion = pcall(mod.GetSuggestion, mod)
    if addon.debugMode then
        if not ok then
            addon:DebugPrint("ERRO em GetSuggestion:", tostring(suggestion))
        elseif suggestion then
            addon:DebugPrint("tick -> SUGESTÃO:", tostring(suggestion.spellID), tostring(suggestion.color))
        else
            addon:DebugPrint("tick -> nada sugerido")
        end
    end
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
    updateSuggestionDisplay(suggestion, mod)
end)

-- ---------------------------------------------------------------------------
-- Compat layer (modern engine: globals may have moved into C_Spell / C_SpellBook)
-- ---------------------------------------------------------------------------
addon.Compat = {}
addon.Compat.SpellNameToID = {}

-- ---------------------------------------------------------------------------
-- Spell rank families (data facts: rank IDs of vanilla spells).
-- "Known" = any rank of the family known — the client only knows the CURRENT
-- rank, so a rank-1 ID on a rotation node must still count as known.
-- (Hunter entries verified against the Forever tuning data, 2026-11.)
-- ---------------------------------------------------------------------------
local FAMILIES = {
    { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }, -- Arcane Shot
    { 19434, 20900, 20901, 20902, 20903, 20904 },               -- Aimed Shot
    { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }, -- Serpent Sting
    { 1130, 14323, 14324, 14325, 1213268 },                     -- Hunter's Mark
    { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 },  -- Raptor Strike
    { 1495, 14269, 14270, 14271 },                              -- Mongoose Bite
    { 2974, 1310180, 14267, 14268 },                            -- Wing Clip
    { 13165, 14318, 14319, 14320, 14321, 14322, 25296 },        -- Aspect of the Hawk
    { 13161, 1299445, 1299446, 1299447 },                       -- Aspect of the Beast
    { 13795, 14302, 14303, 14304, 14305 },                      -- Immolation Trap
    { 13813, 14310, 14311, 14312 },                             -- Explosive Trap
    { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }, -- Lightning Bolt
    { 421, 930, 2860, 10605 },                                  -- Chain Lightning
    { 8050, 8052, 8053, 10447, 10448, 29228 },                  -- Flame Shock
    { 8042, 8044, 8045, 8046, 10412, 10413, 10414 },            -- Earth Shock
    { 1535, 8498, 8499, 11314, 11315 },                         -- Fire Nova
    { 3599, 6363, 6364, 6365, 10437, 10438 },                   -- Searing Totem
    { 8190, 10585, 10586, 10587 },                              -- Magma Totem
    { 324, 325, 905, 945, 8134, 10431, 10432 },                 -- Lightning Shield
    { 8024, 8027, 8030, 16339, 16341, 16342 },                  -- Flametongue Weapon
    { 8232, 8235, 10486, 16362 },                               -- Windfury Weapon
    { 8075, 8160, 8161, 10442, 25361 },                         -- Strength of Earth Totem
    { 5675, 10495, 10496, 10497 },                              -- Mana Spring Totem
    { 17364 },                                                   -- Stormstrike
    { 16166 },                                                   -- Lightning Mastery
    { 425336 },                                                  -- Rage of the Farseer
}
local familyOf = {}
for _, fam in ipairs(FAMILIES) do
    for _, id in ipairs(fam) do familyOf[id] = fam end
end
addon.Compat.FamilyOf = familyOf

-- direct "known" check by ID (client exposes C_SpellBook.IsSpellKnown[OrInSpellBook])
local _knownIDCache = {}
function addon.Compat.IsSpellKnownID(id)
    if type(id) ~= "number" then return false end
    if _knownIDCache[id] == true then return true end
    local function probe(fn)
        local ok, known = pcall(fn, id)
        if not ok then return nil end
        if known == true then return true end
        if known == false then return false end
        return nil
    end
    local sawFalse = false
    if C_SpellBook and type(C_SpellBook.IsSpellKnownOrInSpellBook) == "function" then
        local r = probe(C_SpellBook.IsSpellKnownOrInSpellBook)
        if r == true then _knownIDCache[id] = true return true end
        if r == false then sawFalse = true end
    end
    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        local r = probe(C_SpellBook.IsSpellKnown)
        if r == true then _knownIDCache[id] = true return true end
    end
    if sawFalse then return false end
    -- Sem resposta confiável: fail-open. NUNCA cachear "false": no login o
    -- spellbook pode ainda não estar pronto (cache envenenado = rotação morta).
    return true
end

-- "does the player know this spell?" (any rank of its family)
function addon.Compat.SpellKnown(id)
    if type(id) ~= "number" then return false end
    local fam = familyOf[id]
    if fam then
        for i = #fam, 1, -1 do
            if addon.Compat.IsSpellKnownID(fam[i]) then return true end
        end
        return false
    end
    return addon.Compat.IsSpellKnownID(id)
end

-- Highest known rank of the family; nil when nothing in the family is known.
local _highestKnownCache = {}
function addon.Compat.HighestKnownSpellID(id)
    if type(id) ~= "number" then return nil end
    if _highestKnownCache[id] then return _highestKnownCache[id] end
    local fam = familyOf[id]
    if fam then
        for i = #fam, 1, -1 do
            if addon.Compat.IsSpellKnownID(fam[i]) then
                _highestKnownCache[id] = fam[i]
                return fam[i]
            end
        end
        return nil
    end
    -- no family: direct check on the exact ID
    if addon.Compat.IsSpellKnownID(id) then
        _highestKnownCache[id] = id
        return id
    end
    return nil
end

-- Resolve qualquer rank para o rank conhecido da família (CD/alcance).
-- Como o SFF: se a família não tiver rank conhecido, devolve o próprio ID.
function addon.Compat.ResolveKnownID(id)
    if type(id) ~= "number" then return id end
    if familyOf[id] then
        return addon.Compat.HighestKnownSpellID(id) or id
    end
    return id
end

-- Invalida os caches de "conhecido" (o spellbook pode carregar depois do login;
-- um "false" cacheado deixa a rotação morta para sempre).
function addon.Compat.InvalidateSpellCaches()
    wipe(_knownIDCache)
    wipe(_highestKnownCache)
end

function addon.Compat.SpellInfoByID(id)
    -- Nunca indexar tabelas com valor secreto/nil (o cliente mascara dados).
    local safeKey = type(id) == "number" and not (_G.issecretvalue and issecretvalue(id))
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then
            -- `subName` carries "Rank N" on retail-style APIs when present
            local name = info.name
            local rank = info.subName or info.rank
            if type(name) == "string" and not (_G.issecretvalue and issecretvalue(name)) then
                if safeKey then addon.Compat.SpellNameToID[name] = id end
                return name, rank
            end
        end
    end
    if GetSpellInfo then
        local ok, name, rank = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" and not (_G.issecretvalue and issecretvalue(name)) then
            if safeKey then addon.Compat.SpellNameToID[name] = id end
            return name, rank
        end
    end
    return nil
end

function addon.Compat.SpellName(id)
    if type(id) ~= "number" then return id end
    local name = addon.Compat.SpellInfoByID(id)
    if name then return name end
    return tostring(id)
end

function addon.Compat.SpellIDFromName(name)
    if type(name) ~= "string" then return nil end
    -- busca por nome no cache nome->ID (preenchido por SpellInfoByID/SpellName)
    for id, nm in pairs(addon.Compat.SpellNameToID or {}) do
        if type(nm) == "string" and nm:lower() == name:lower() then return id end
    end
    -- varredura do spellbook como fallback
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        for i = 1, 300 do
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, "spell")
            if ok and info and info.name then
                local base = info.name:gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if base:lower() == name:lower() then
                    local id = addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(info.id) or info.id
                    return id
                end
            end
        end
    end
    return nil
end

-- Cooldown de um spellID pelo cliente Forever (C_Spell.GetSpellCooldown).
-- Retorna (timeLeft, duration). Usa issecretvalue como fail-safe.
-- CheckBuff / CheckDebuff — leitura de auras via C_UnitAuras (moderna) com
-- fallback para UnitBuff/UnitDebuff. mine=true exige sourceUnit == "player".
-- Em combate auras podem ser secret → retornam false (fail-safe).
local function CheckAura(filter, defaultUnit, SpellName, unit, mine)
    unit = unit or defaultUnit
    if not UnitExists(unit) then return false end
    local wanted = {}
    local function AddWanted(w)
        if type(w) == "number" then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(w)
            w = info and info.name or tostring(w)
        end
        if type(w) == "string" and w ~= "" then wanted[#wanted + 1] = w end
    end
    if type(SpellName) == "table" then
        for _, w in ipairs(SpellName) do AddWanted(w) end
    else
        AddWanted(SpellName)
    end
    if #wanted == 0 then return false end
    local wantClean = {}
    for _, w in ipairs(wanted) do wantClean[w:lower()] = true end
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or not data or type(data) ~= "table" then break end
            local name = data.name
            if _G.issecretvalue and issecretvalue(name) then break end
            if name and wantClean[name:lower()] then
                if not mine then return true end
                local source = data.sourceUnit
                if source == nil or _G.issecretvalue and issecretvalue(source) then return false end
                local okU, same = pcall(UnitIsUnit, source, "player")
                if okU and same then return true end
                local okP, sameP = pcall(UnitIsUnit, source, "pet")
                if okP and sameP then return true end
            end
        end
    elseif type(UnitBuff) == "function" or type(UnitDebuff) == "function" then
        local iter = (filter == "HELPFUL") and UnitBuff or UnitDebuff
        if type(iter) == "function" then
            for i = 1, 40 do
                local ok, n = pcall(iter, unit, i)
                if not ok or not n then break end
                if _G.issecretvalue and issecretvalue(n) then break end
                if wantClean[n:lower()] then return true end
            end
        end
    end
    return false
end

function addon.Compat.CheckBuff(SpellName, unit, mine)
    return CheckAura("HELPFUL", "player", SpellName, unit, mine)
end

function addon.Compat.CheckDebuff(SpellName, unit, mine)
    return CheckAura("HARMFUL", "target", SpellName, unit, mine)
end

local function cooldownField(info, primary, fallback)
    local ok, value = pcall(function()
        local result = info[primary]
        if result == nil and fallback then result = info[fallback] end
        return result
    end)
    if not ok then return nil end
    return addon.SafeNumber(value, nil)
end

local function cooldownFromInfo(info)
    if type(info) ~= "table" then return 0, 0, false end
    local start = cooldownField(info, "startTime", "cooldownStartTime")
    local duration = cooldownField(info, "duration", "cooldownDuration")
    local remaining = cooldownField(info, "timeUntilEndOfStartRecovery")
    local okActive, isActive = pcall(function() return info.isActive == true end)
    if not okActive then isActive = false end
    local timeLeft
    if start ~= nil and duration ~= nil then
        local now = addon.SafeNumber(GetTime(), 0) or 0
        timeLeft = math.max(0, start + duration - now)
    end
    if timeLeft == nil then
        if remaining and remaining > 0 then return remaining, duration or 0, true end
        return 0, 0, false
    end
    timeLeft = math.max(timeLeft or 0, remaining or 0)
    if timeLeft > 0 then
        return timeLeft, duration or 0, true
    end
    if isActive and duration and duration > 0 then
        return duration, duration, true
    end
    return 0, duration or 0, true
end

function addon.Compat.SpellCooldown(spellID)
    if type(spellID) ~= "number" then return 0, 0, false end
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok then
            local cooldown, duration, readable = cooldownFromInfo(info)
            if readable then return cooldown, duration, true end
        end
    end
    if type(GetSpellCooldown) == "function" then
        local ok, start, duration = pcall(GetSpellCooldown, spellID)
        if ok then return cooldownFromInfo({ startTime = start, duration = duration }) end
    end
    return 0, 0, false
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

function addon.NodeConditionPass(module, env, node, strict)
    if type(node) ~= "table" or not addon.NodeFilterPass(env, node.filter) then return false end
    local condition = node.condition
    if not condition or condition == "" then return true end
    local predicates = type(module) == "table" and module.RotationPredicates or nil
    local predicate = type(predicates) == "table" and predicates[condition] or nil
    if type(predicate) ~= "table" or type(predicate.fn) ~= "function" then
        return not strict
    end
    local ok, result = pcall(predicate.fn, env)
    return ok and result and true or false
end

-- ---------------------------------------------------------------------------
-- Global racial system — every class module can ask "should I use my racial?"
-- Data: raceToken -> { spellID, condition, color, classes = { ... } }
--   condition:
--     "always"          — sugere sempre (se souber o feitiço)
--     "combat"          — sugere só em combate (ex: Berserking, Blood Fury)
--     "out_of_combat"   — sugere só fora de combate (ex: Shadowmeld)
--     "interrupt"       — sugere se o alvo está castando (ex: War Stomp)
--     "cc_break"        — sugere em combate com inimigo (CC break: Will to Survive, Escape Artist, Will of the Forsaken)
-- Racial NUNCA trava a rotação normal: módulos chamam como baixa prioridade
-- (apenas dispara quando nada mais foi sugerido neste tick).
-- IDs confirmados no WoW Forever (wowhead.com/forever, 2026-11-19).
-- ---------------------------------------------------------------------------
addon.RacialData = {
    Human = {
        spellID = 1259718, condition = "cc_break", color = "Utility",
        classes = { WARRIOR = true, PALADIN = true, ROGUE = true, MAGE = true, WARLOCK = true, PRIEST = true, HUNTER = true },
    }, -- Will to Survive (remove stuns)
    Dwarf = {
        spellID = 20594, condition = "combat", color = "Utility",
        classes = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, MAGE = true, PRIEST = true, WARLOCK = true, SHAMAN = true },
    }, -- Stoneform (bleed/poison/disease immunity + 10% menos dano físico)
    NightElf = {
        spellID = 20580, condition = "out_of_combat", color = "Utility",
        classes = { WARRIOR = true, ROGUE = true, HUNTER = true, DRUID = true, PRIEST = true },
    }, -- Shadowmeld (stealth parado, drop de threat)
    Gnome = {
        spellID = 20589, condition = "cc_break", color = "Utility",
        classes = { WARRIOR = true, ROGUE = true, MAGE = true, WARLOCK = true, PRIEST = true },
    }, -- Escape Artist (remove roots/snares + 3s imunidade)
    Orc = {
        spellID = 20572, condition = "combat", color = "Damage",
        classes = { WARRIOR = true, HUNTER = true, ROGUE = true, MAGE = true, WARLOCK = true, SHAMAN = true },
    }, -- Blood Fury (+10% AP/SP por 15s)
    Scourge = {
        spellID = 7744, condition = "cc_break", color = "Utility",
        classes = { WARRIOR = true, ROGUE = true, MAGE = true, PRIEST = true, WARLOCK = true, PALADIN = true },
    }, -- Will of the Forsaken (remove charm/fear/sleep) — alias de Undead
    Undead = {
        spellID = 7744, condition = "cc_break", color = "Utility",
        classes = { WARRIOR = true, ROGUE = true, MAGE = true, PRIEST = true, WARLOCK = true, PALADIN = true },
    }, -- Will of the Forsaken (remove charm/fear/sleep)
    Tauren = {
        spellID = 20549, condition = "interrupt", color = "Aqua",
        classes = { WARRIOR = true, HUNTER = true, SHAMAN = true, DRUID = true },
    }, -- War Stomp (stun 2s, até 5 inimigos a 8 yd)
    Troll = {
        spellID = 20554, condition = "combat", color = "Damage",
        classes = { WARRIOR = true, HUNTER = true, ROGUE = true, MAGE = true, PRIEST = true, SHAMAN = true, WARLOCK = true },
    }, -- Berserking (+10% cast/attack speed por 15s)
    HighOrderSkyborne = {
        spellID = nil, condition = "always", color = "Utility",
        classes = { DRUID = true, HUNTER = true, MAGE = true, ROGUE = true, WARRIOR = true },
    }, -- Sem racial ativa documentada no Forever
    WindshaperSkyborne = {
        spellID = 1259416, condition = "out_of_combat", color = "Utility",
        classes = { DRUID = true, HUNTER = true, ROGUE = true, SHAMAN = true, WARRIOR = true },
    }, -- Walk on Air (planar 10s)
}
-- map nomes localizados do UnitRace para o token canônico da tabela RacialData
addon.RacialTokenAliases = {
    ["scourge"] = "Scourge",
    ["undead"]  = "Undead",
    ["morto-vivo"] = "Scourge",
    ["mortovivo"] = "Scourge",
    ["humano"] = "Human",
    ["anão"] = "Dwarf", ["anao"] = "Dwarf",
    ["elfo noturno"] = "NightElf",
    ["gnomo"] = "Gnome",
    ["orc"] = "Orc",
    ["tauren"] = "Tauren",
    ["troll"] = "Troll",
    ["high order skyborne"] = "HighOrderSkyborne",
    ["windshaper skyborne"] = "WindshaperSkyborne",
}

-- Retorna o spellID da racial da raça (ou nil se não houver racial ativa).
function addon:GetRacialSpellID(raceToken)
    if type(raceToken) ~= "string" then return nil end
    local data = self.RacialData[raceToken]
    if not data then return nil end
    return data.spellID
end

-- Retorna true se a racial desta raça deve ser sugerida agora, dadas as condições.
-- `env` é a tabela de contexto da rotação (pode ser nil -> condição não depende dela).
function addon:ShouldUseRacial(raceToken, env)
    if type(raceToken) ~= "string" then return false end
    local data = self.RacialData[raceToken]
    if not data then return false end
    -- se a raça não tem racial ativa (spellID nil), nunca sugere
    if not data.spellID then return false end
    local cond = data.condition or "always"
    if cond == "always" then return true end
    if cond == "combat" then
        return env and env.inCombat == true or false
    end
    if cond == "out_of_combat" then
        return env and env.inCombat ~= true or false
    end
    if cond == "interrupt" then
        return env and env.targetCasting == true or false
    end
    if cond == "cc_break" then
        -- só faz sentido em combate com inimigo presente (o player decide se está CC'd)
        return env and env.inCombat == true and env.hasActiveEnemy == true or false
    end
    return false
end

-- Tenta sugerir a racial do player como baixa prioridade (não bloqueante).
-- Retorna true se uma sugestão de racial foi definida; false caso contrário.
-- Chamar DEPOIS da rotação normal para nunca bloquear dano/utilidade.
function addon:SuggestRacial(module, env)
    local _, raceToken = UnitRace("player")
    if not raceToken then return false end
    -- resolve aliases localizados para o token canônico
    local lower = raceToken:lower()
    raceToken = self.RacialTokenAliases[lower] or raceToken
    if not self:ShouldUseRacial(raceToken, env) then return false end
    local spellID = self:GetRacialSpellID(raceToken)
    if not spellID then return false end
    local color = self.RacialData[raceToken].color or "Utility"
    local knownID = self.Compat and self.Compat.HighestKnownSpellID and self.Compat.HighestKnownSpellID(spellID) or spellID
    if module.TickFlashUsed then return false end
    -- verifica castabilidade antes de sugerir (raciais são self-target)
    local spellName = module.SpellName and module.SpellName(knownID)
    if not spellName then return false end
    local z = {
        SpellName = spellName,
        SpellID = knownID,
        EnemyTargetNeeded = false,
    }
    -- module.CheckCastable é função com ponto (sem self implícito): chamar com "."
    if module.CheckCastable and not module.CheckCastable(z) then return false end
    return module:Suggest(knownID, color)
end

-- ---------------------------------------------------------------------------
-- FindActionSlot — busca por slot na barra de ação de uma spell (por ID ou
-- nome-base). Baseado no SFF (SpellFlashForever.lua). Com cache, suporte a
-- macros, ataque automático e match por nome-base (insensível a rank/locale).
-- ---------------------------------------------------------------------------
local ACTION_SLOT_CACHE = {}
local ACTION_SLOT_CACHE_FRAME = CreateFrame("Frame")
ACTION_SLOT_CACHE_FRAME:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ACTION_SLOT_CACHE_FRAME:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
ACTION_SLOT_CACHE_FRAME:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
ACTION_SLOT_CACHE_FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
ACTION_SLOT_CACHE_FRAME:SetScript("OnEvent", function() wipe(ACTION_SLOT_CACHE) end)

local BAR_NAMES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button",
}

local function stripRank(name)
    if type(name) ~= "string" then return "" end
    return (name:gsub("%s*%b()%s*$", "")):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeName(name)
    return stripRank(name):lower()
end

local function toActionID(id)
    if type(id) == "number" then return id end
    if type(id) == "string" then return tonumber(id) end
    return nil
end

local function spellNameFromID(id)
    if type(id) ~= "number" then return nil end
    if addon.Compat and addon.Compat.SpellInfoByID then
        local ok, info = pcall(addon.Compat.SpellInfoByID, id)
        if ok and info and type(info) == "string" then return info end
        if ok and type(info) == "table" and info.name then return info.name end
    end
    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and name then return name end
    end
    return nil
end

local function findAttackActionSlot()
    if C_ActionBar and type(C_ActionBar.IsAttackAction) == "function" then
        for i = 1, 180 do
            local ok, isAttack = pcall(C_ActionBar.IsAttackAction, i)
            if ok and isAttack == true then return i end
        end
    end
    if type(GetActionInfo) == "function" then
        for i = 1, 180 do
            local ok, actionType = pcall(GetActionInfo, i)
            if ok and actionType == "attack" then return i end
        end
    end
    return nil
end

local function findActionButtonByID(spellID)
    if not spellID or type(spellID) ~= "number" then return nil end
    -- Ataque automático (6603): ação especial, não é slot "spell" comum.
    if spellID == 6603 then
        local attackSlot = findAttackActionSlot()
        if attackSlot then return attackSlot end
    end
    local targetName = normalizeName(spellNameFromID(spellID))
    -- 1) ID exato
    for i = 1, 180 do
        local ok, actionType, id = pcall(GetActionInfo, i)
        if ok and actionType == "spell" and toActionID(id) == spellID then return i end
    end
    -- 2) Nome-base normalizado (outro rank da mesma spell)
    if targetName ~= "" then
        for i = 1, 180 do
            local ok, actionType, id = pcall(GetActionInfo, i)
            if ok and actionType == "spell" then
                local name = spellNameFromID(toActionID(id) or id)
                if normalizeName(name) == targetName then return i end
            end
        end
    end
    -- 3) Macros
    for i = 1, 180 do
        local ok, actionType, id = pcall(GetActionInfo, i)
        if ok and actionType == "macro" then
            local macroIndex = toActionID(id)
            local macroName = GetActionText and GetActionText(i)
            if targetName ~= "" and type(macroName) == "string"
                and normalizeName(macroName) == targetName then return i end
            if macroIndex then
                local ok2, spellName2 = pcall(function()
                    if C_Spell and C_Spell.GetSpellInfo then
                        local o, info = pcall(C_Spell.GetSpellInfo, macroIndex)
                        return o and info and info.name or nil
                    end
                end)
                if ok2 and spellName2 and normalizeName(spellName2) == targetName then return i end
            end
        end
    end
    return nil
end

function addon:FindActionSlot(spellID)
    if type(spellID) ~= "number" then return nil end
    local cached = ACTION_SLOT_CACHE[spellID]
    if cached ~= nil then return cached or nil end
    local slot = findActionButtonByID(spellID)
    ACTION_SLOT_CACHE[spellID] = slot or false
    return slot
end

-- ---------------------------------------------------------------------------
-- ActionCooldown — cooldown pelo slot da barra de ação (resposta do cliente).
-- Robusto: independe de rank/nome; usa C_ActionBar.GetActionCooldown.
-- ---------------------------------------------------------------------------
function addon:ActionCooldown(slot)
    if not slot then return 0, 0, false end
    if C_ActionBar and type(C_ActionBar.GetActionCooldown) == "function" then
        local ok, info = pcall(C_ActionBar.GetActionCooldown, slot)
        if ok then
            local cooldown, duration, readable = cooldownFromInfo(info)
            if readable then return cooldown, duration, true end
        end
    end
    if type(GetActionCooldown) == "function" then
        local ok, start, duration = pcall(GetActionCooldown, slot)
        if ok then return cooldownFromInfo({ startTime = start, duration = duration }) end
    end
    return 0, 0, false
end

-- ---------------------------------------------------------------------------
-- IsSpellInRangeEx — alcance estrito (true/false/nil). Nil = desconhecido,
-- nunca interpretado como "em alcance" (evita o bug de todo alvo parecer
-- melee quando a API é secreta).
-- ---------------------------------------------------------------------------
function addon:IsSpellInRangeEx(spellName, unit)
    unit = unit or "target"
    local spellID
    if type(spellName) == "number" then
        spellID = spellName
    else
        spellID = addon.SafeNumber(function() return addon.Compat.SpellIDFromName and addon.Compat.SpellIDFromName(spellName) end, nil)
    end
    local base = stripRank(tostring(spellName))

    local function byID(id)
        if not id or not C_Spell or type(C_Spell.IsSpellInRange) ~= "function" then return nil end
        local ok, result = pcall(C_Spell.IsSpellInRange, id, unit)
        if not ok then return nil end
        if _G.issecretvalue and issecretvalue(result) then return nil end
        if result == true or result == 1 then return true end
        if result == false or result == 0 then return false end
        return nil
    end

    local function byName(name)
        if type(name) ~= "string" or name == "" then return nil end
        if not C_Spell or type(C_Spell.IsSpellInRange) ~= "function" then return nil end
        local ok, result = pcall(C_Spell.IsSpellInRange, name, unit)
        if not ok then return nil end
        if _G.issecretvalue and issecretvalue(result) then return nil end
        if result == true or result == 1 then return true end
        if result == false or result == 0 then return false end
        return nil
    end

    local answer
    if spellID then
        answer = byID(spellID)
        if answer == nil then answer = byName(base) end
    else
        answer = byName(base)
    end
    if answer ~= nil then return answer end

    -- API global legada (1/0/nil)
    if type(IsSpellInRange) == "function" and base and base ~= "" then
        local ok, result = pcall(IsSpellInRange, base, unit)
        if ok then
            if _G.issecretvalue and issecretvalue(result) then return nil end
            if result == true or result == 1 then return true end
            if result == false or result == 0 then return false end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- ActionSlotRange / TargetDistance / IsInMeleeRange — portados do SFF
-- (SharedFunctions.lua). Sem chute: nil = desconhecido.
-- ---------------------------------------------------------------------------
function addon:ActionSlotRange(slot, unit)
    if not slot then return nil end
    local fn = (C_ActionBar and C_ActionBar.IsActionInRange) or _G.IsActionInRange
    if type(fn) ~= "function" then return nil end
    local function answer(v)
        if v == nil then return nil end
        if _G.issecretvalue and issecretvalue(v) then return nil end
        if v == true or v == 1 then return true end
        if v == false or v == 0 then return false end
        return nil
    end
    local ok, result = pcall(fn, slot, unit or "target")
    if ok then
        local a = answer(result)
        if a ~= nil then return a end
    end
    ok, result = pcall(fn, slot)
    if ok then return answer(result) end
    return nil
end

function addon:TargetDistance(unit)
    unit = unit or "target"
    if type(UnitDistanceSquared) ~= "function" then return nil end
    if not UnitExists(unit) then return nil end
    local ok, squared, checked = pcall(UnitDistanceSquared, unit)
    if not ok or checked ~= true then return nil end
    if type(squared) ~= "number" then return nil end
    if _G.issecretvalue and issecretvalue(squared) then return nil end
    if squared < 0 then return nil end
    return math.sqrt(squared)
end

-- true = melee, false = ranged, nil = desconhecido
function addon:IsInMeleeRange(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    local attackSlot = self:FindActionSlot(6603)
    local attackRange = self:ActionSlotRange(attackSlot, unit)
    if attackRange ~= nil then return attackRange end
    local known = (self.Compat and self.Compat.HighestKnownSpellID and self.Compat.HighestKnownSpellID(2974)) or 2974
    local r = self:IsSpellInRangeEx(known, unit)
    if r == true then return true end
    local autoSlot = self:FindActionSlot(75)
    local autoRange = self:ActionSlotRange(autoSlot, unit)
    if autoRange == true then return false end
    if autoRange == false then return true end
    if not (type(InCombatLockdown) == "function" and InCombatLockdown())
        and type(CheckInteractDistance) == "function" then
        local ok, can = pcall(CheckInteractDistance, unit, 3)
        if ok and not (_G.issecretvalue and issecretvalue(can)) then
            return can and true or false
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Zona morta do Hunter (5-10 yd): o corpo a corpo (5 yd) não alcança e as
-- habilidades de longo alcance não funcionam — é o caso do Disengage.
--   true  = zona morta
--   false = fora da zona morta
--   nil   = desconhecido (sem leitura de distância/alcance)
-- Sem distância medida: usa a sondagem do slot "Atacar" (≤5 yd) contra a
-- sondagem do Corte de Asa (≤10 yd): ataque fora + corte dentro = zona morta.
-- ---------------------------------------------------------------------------
function addon:IsInDeadZoneRange(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    local dist = self:TargetDistance(unit)
    if dist then return (dist > 5 and dist <= 10) and true or false end
    local attackSlot = self:FindActionSlot(6603)
    local attackRange = self:ActionSlotRange(attackSlot, unit)
    if attackRange == true then return false end
    local known = (self.Compat and self.Compat.HighestKnownSpellID and self.Compat.HighestKnownSpellID(2974)) or 2974
    local r = self:IsSpellInRangeEx(known, unit)
    if r == true then return true end
    if attackRange == false then return false end
    return nil
end

-- ---------------------------------------------------------------------------
-- Flashable — spell conhecida e utilizável (o "piscar" ainda passa por
-- CheckIfSpellCastable no próprio módulo).
-- ---------------------------------------------------------------------------
function addon:Flashable(spellName)
    if not spellName then return false end
    local known
    if type(spellName) == "number" then
        known = addon.Compat and addon.Compat.SpellKnown and addon.Compat.SpellKnown(spellName)
    else
        known = addon.Compat and addon.Compat.SpellKnown and addon.Compat.SpellKnown(spellName)
    end
    if known == false then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- CheckIfSpellCastable — coração do sistema de castabilidade (portado do SFF).
-- Verifica: spell conhecido, cooldown (spellID + slot da barra como reforço),
-- GCD, alcance, auras (buff/debuff/myBuff/myDebuff), EnemyTargetNeeded,
-- TargetThatUsesManaNeeded, NotIfActive, EvenIfNotUsable.
-- ---------------------------------------------------------------------------
function addon:CheckIfSpellCastable(z)
    if type(z) ~= "table" then return false end

    -- z.Debug = tabela: recebe o motivo da recusa (usado pelo /cfa debug).
    local dbg = z.Debug
    local function fail(reason)
        if type(dbg) == "table" then dbg.reason = reason end
        if addon.debugMode then
            addon:DebugPrint("castable: RECUSADO", tostring(z.SpellName), tostring(z.SpellID), "-", tostring(reason))
        end
        return false
    end

    local spellID = z.SpellID
    local spellName = z.SpellName
    if type(spellID) == "number" then
        spellName = spellName or spellNameFromID(spellID)
    elseif type(spellName) == "number" then
        spellID = spellName
        spellName = spellNameFromID(spellID)
    end
    if not spellName or spellName == "" then return fail("sem nome de spell") end

    local baseName = stripRank(spellName)
    local knownID = addon.Compat and addon.Compat.ResolveKnownID and addon.Compat.ResolveKnownID(spellID) or spellID

    -- "Conhecida": o SFF NÃO bloqueia a rotação por ID (o ID do nó pode ser um
    -- rank que o jogador não tem mais no livro). Aqui: só bloqueia se o ID e o
    -- NOME forem simultaneamente desconhecidos (fail-open, igual ao SFF).
    if spellID then
        local known = addon.Compat and addon.Compat.SpellKnown and addon.Compat.SpellKnown(spellID)
        if known == false then
            local byName = addon.Compat and addon.Compat.HasSpell and addon.Compat.HasSpell(spellName)
            if not byName then return fail("spell desconhecida (id=" .. tostring(spellID) .. ")") end
        end
    else
        local has = addon.Compat and addon.Compat.HasSpell and addon.Compat.HasSpell(spellName)
        if not has then return fail("spell desconhecida (" .. tostring(spellName) .. ")") end
    end

    z.Unit = z.Unit or "target"

    if z.EnemyTargetNeeded then
        local enemy = addon.Enemy and addon:Enemy(z.Unit)
        if enemy == false then return fail("sem alvo inimigo") end
    end

    local isUsable, notEnoughPower = true, false
    if addon.Compat and addon.Compat.UsableSpell then
        isUsable, notEnoughPower = addon.Compat.UsableSpell(baseName, knownID)
    elseif type(IsUsableSpell) == "function" then
        local ok, a, b = pcall(IsUsableSpell, spellName)
        if ok then isUsable = not not a; notEnoughPower = not not b end
    end

    local cooldown = 0
    local duration = 0
    local checkedCooldownIDs = {}
    local function readSpellCooldown(id)
        if type(id) ~= "number" or checkedCooldownIDs[id] then return end
        checkedCooldownIDs[id] = true
        if addon.Compat and addon.Compat.SpellCooldown then
            local cd, dur, readable = addon.Compat.SpellCooldown(id)
            if readable then
                if (cd or 0) > cooldown then
                    cooldown, duration = cd, dur or 0
                end
            end
        end
    end
    local cdID = knownID or spellID
    readSpellCooldown(cdID)
    local spellFamily = cdID and addon.Compat and addon.Compat.FamilyOf
        and addon.Compat.FamilyOf[cdID]
    if spellFamily then
        for _, familyID in ipairs(spellFamily) do readSpellCooldown(familyID) end
    end
    local actionSlot = nil
    if knownID and addon.FindActionSlot then
        actionSlot = addon:FindActionSlot(knownID)
    end
    if actionSlot and addon.ActionCooldown then
        local sc, sd, readable = addon:ActionCooldown(actionSlot)
        if readable then
            if (sc or 0) > cooldown then
                cooldown, duration = sc, sd or duration
            end
        end
    end
    local Aura = z.Debuff or z.Buff or z.MyDebuff or z.MyBuff

    -- Alcance: nil (desconhecido/segreto) não bloqueia — igual ao SFF (SpellInRange retorna 1 quando nil)
    local rangeOk = true
    if not z.NoRangeCheck then
        local hasRange = true
        if addon.Compat and addon.Compat.SpellHasRange then
            hasRange = addon.Compat.SpellHasRange(baseName)
        end
        if hasRange then
            local r = addon:IsSpellInRangeEx(baseName, z.Unit)
            rangeOk = (r ~= false)
            if not rangeOk then return fail("fora de alcance") end
        end
    end

    local cooldownOk = cooldown <= 0.05
    if not cooldownOk then
        return fail(string.format("em cooldown (%.1fs de %.1fs)",
            tonumber(cooldown) or 0, tonumber(duration) or 0))
    end

    local notIfActiveOk = true
    if not z.NotIfActive and not Aura then
        -- sem NotIfActive e sem aura: passa
    else
        local current = false
        if addon.Compat and addon.Compat.IsCurrentSpell then
            current = addon.Compat.IsCurrentSpell(baseName)
        elseif type(IsCurrentSpell) == "function" then
            local ok, c = pcall(IsCurrentSpell, spellName)
            if ok then current = not not c end
        end
        local casting = false
        if addon.Compat and addon.Compat.CastingOrChanneling then
            casting = addon.Compat.CastingOrChanneling(baseName, "player")
        end
        if not z.NotIfActive and not Aura then
            notIfActiveOk = true
        else
            notIfActiveOk = (not current and not casting) or (not Aura and (casting or 0) <= lag)
        end
    end

    local enemyOk = true
    if z.EnemyTargetNeeded then
        local e = addon.Enemy and addon:Enemy(z.Unit)
        enemyOk = (e ~= false)
    end

    local manaTargetOk = true
    if z.TargetThatUsesManaNeeded then
        if type(UnitPowerType) == "function" then
            local okPT, pType = pcall(UnitPowerType, z.Unit)
            manaTargetOk = (okPT and pType == 0) or false
        else
            manaTargetOk = true
        end
    end

    local debuffSlotOk = true
    if z.DebuffSlotNeeded then
        debuffSlotOk = true -- nunca bloqueia por "slots de debuff cheios"
    end

    local debuffOk = true
    if z.Debuff then
        local check = addon.Compat and addon.Compat.CheckDebuff
        if check then
            local buffUnit = z.BuffUnit or z.Unit or "target"
            local mine = (z.MyDebuff == z.Debuff) and true or nil
            local okD, up = pcall(check, z.Debuff, buffUnit, mine)
            debuffOk = (okD and up == true) or false
        end
    end

    local buffOk = true
    if z.Buff then
        local check = addon.Compat and addon.Compat.CheckBuff
        if check then
            local buffUnit = z.BuffUnit or z.Unit or "target"
            local mine = (z.MyBuff == z.Buff) and true or nil
            local okB, up = pcall(check, z.Buff, buffUnit, mine)
            buffOk = (okB and up == true) or false
        end
    end

    local myDebuffOk = true
    if z.MyDebuff then
        local check = addon.Compat and addon.Compat.CheckDebuff
        if check then
            local buffUnit = z.BuffUnit or z.Unit or "target"
            local okD, up = pcall(check, z.MyDebuff, buffUnit, true)
            myDebuffOk = (okD and up == true) or false
        end
    end

    local myBuffOk = true
    if z.MyBuff then
        local check = addon.Compat and addon.Compat.CheckBuff
        if check then
            local buffUnit = z.BuffUnit or z.Unit or "target"
            local okB, up = pcall(check, z.MyBuff, buffUnit, true)
            myBuffOk = (okB and up == true) or false
        end
    end

    if not (z.EvenIfNotUsable or isUsable) then return fail("spell não utilizável agora") end
    if notEnoughPower then return fail("sem mana/poder") end
    if not notIfActiveOk then return fail("já está conjurando/canalizando") end
    if not enemyOk then return fail("alvo não é inimigo") end
    if not manaTargetOk then return fail("alvo não usa mana") end
    if not debuffSlotOk then return fail("sem espaço de debuff") end
    if not debuffOk then return fail("debuff já aplicado") end
    if not buffOk then return fail("buff já ativo") end
    if not myDebuffOk then return fail("meu debuff já aplicado") end
    if not myBuffOk then return fail("meu buff já ativo") end

    if addon.debugMode then
        addon:DebugPrint("castable: OK", tostring(spellName), tostring(spellID))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Enemy wrapper (fail-open): se a leitura de UnitCanAttack for secreta/ilegível,
-- trata como atacável para não travar a rotação.
-- ---------------------------------------------------------------------------
function addon:Enemy(unit)
    unit = unit or "target"
    local okE, exists = pcall(UnitExists, unit)
    if not okE or not exists then return false end
    local ok, canAttack = pcall(UnitCanAttack, "player", unit)
    if not ok or (_G.issecretvalue and issecretvalue(canAttack)) then canAttack = true end
    if not canAttack then return false end
    local ok2, dead = pcall(UnitIsDeadOrGhost, unit)
    if ok2 and dead then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- SafeNumber — leitura segura de números secretos (taint do cliente Forever).
-- ---------------------------------------------------------------------------
function addon.SafeNumber(v, fallback)
    if type(v) ~= "number" then return fallback end
    if _G.issecretvalue and issecretvalue(v) then return fallback end
    return v
end

-- ---------------------------------------------------------------------------
-- Compat: funções de suporte que o CheckIfSpellCastable precisa e que o SFF
-- expõe em SpellFlashAddon. Todas usam pcall + issecretvalue como fail-safe.
-- ---------------------------------------------------------------------------
function addon.Compat.HasSpell(spellName)
    local name = addon.Compat.SpellName and addon.Compat.SpellName(spellName) or spellName
    if type(name) ~= "string" or name == "" then return false end
    local spellID = addon.Compat.SpellIDFromName and addon.Compat.SpellIDFromName(name)
    if spellID then
        local known = addon.Compat.SpellKnown and addon.Compat.SpellKnown(spellID)
        if known == true then return true end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellName)
        if ok and info ~= nil then return true end
    end
    if type(GetSpellInfo) == "function" then
        local ok, result = pcall(GetSpellInfo, name)
        if ok and result ~= nil then return true end
    end
    return true -- fail-open: deixar recomendar (cliente-friendly)
end

function addon.Compat.UsableSpell(spellName, knownID)
    local id = (type(knownID) == "number" and knownID)
        or (type(spellName) == "number" and spellName)
        or (addon.Compat.SpellIDFromName and addon.Compat.SpellIDFromName(spellName)) or nil
    if id and C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        local ok, isUsable, notEnoughPower = pcall(C_Spell.IsSpellUsable, id)
        if ok and isUsable == true then
            return true, notEnoughPower == true
        end
        if ok and isUsable == false then
            return false, notEnoughPower == true
        end
    end
    -- O fallback legado só é usado se a API moderna estiver ausente,
    -- lançar erro ou não retornar um booleano.
    if type(IsUsableSpell) == "function" then
        local ok, a, b = pcall(IsUsableSpell, spellName)
        if ok and a ~= nil then return a and true or false, not not b end
    end
    return true, false
end

function addon.Compat.IsCurrentSpell(spellName)
    local name = addon.Compat.SpellName and addon.Compat.SpellName(spellName) or spellName
    if not name then return false end
    if type(IsCurrentSpell) == "function" then
        local ok, c = pcall(IsCurrentSpell, name)
        if ok then return not not c end
    end
    return false
end

function addon.Compat.GetCasting(spellName, unit)
    unit = unit or "player"
    if type(UnitCastingInfo) == "function" then
        local ok, _, _, _, _, startMS, endMS = pcall(UnitCastingInfo, unit)
        if ok and endMS and startMS then
            local remaining = (endMS - (GetTime and GetTime() * 1000 or 0)) / 1000
            if remaining > 0 then return remaining end
            return 0
        end
    end
    return nil
end

function addon.Compat.CastingOrChanneling(spellName, unit)
    unit = unit or "player"
    local name = addon.Compat.SpellName and addon.Compat.SpellName(spellName) or spellName
    local remaining = nil
    if type(UnitCastingInfo) == "function" then
        local okCast, _, _, _, _, startMS, endMS = pcall(UnitCastingInfo, unit)
        if okCast and endMS and startMS then
            remaining = (endMS - (GetTime and GetTime() * 1000 or 0)) / 1000
            if remaining > 0 then return remaining end
        end
    end
    if type(UnitChannelInfo) == "function" then
        local okChan, _, _, _, _, endMS = pcall(UnitChannelInfo, unit)
        if okChan and endMS then
            remaining = (endMS - (GetTime and GetTime() * 1000 or 0)) / 1000
            if remaining > 0 then return remaining end
        end
    end
    return nil
end

function addon.Compat.SpellHasRange(spellName)
    local id = type(spellName) == "number" and spellName or addon.Compat.SpellIDFromName and addon.Compat.SpellIDFromName(spellName)
    if not id then
        if type(spellName) == "string" and spellName:match("^%d+$") then return false end
        return true -- desconhecido: assume que tem alcance
    end
    if not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then return true end
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if not ok or not info then return true end
    return (info.maxRange or 0) > 0
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
    for _, node in ipairs(nodes) do
        if node.enabled ~= false and not (disabled and disabled[node.id]) then
            local pass = addon.NodeConditionPass(module, env, node)
            if pass then
                if addon.debugMode then
                    addon:DebugPrint("nó", tostring(node.id), "cond=" .. tostring(node.condition),
                        "condOK=true", "enabled=ok")
                end
                local knownID = addon.Compat.HighestKnownSpellID(node.spellID) or node.spellID
                if module:TryFlash(knownID, node.color, function() return true end, node.name, env, node.opts) then
                    if addon.debugMode then
                        addon:DebugPrint("   -> SUGERIDO", tostring(node.id), tostring(knownID))
                    end
                    if not node.passthrough then return true end
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
    -- show the key button too while the test-flash is on
    if addon.KeyButton and addon.db.keyButton then
        addon.KeyButton.ShowFor(known)
    end
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
    local _, className = UnitClass("player")
    local mod = addon.activeModule
    local spec, source
    if mod and type(mod.DetectSpec) == "function" then
        local ok, s, src = pcall(mod.DetectSpec, mod)
        if ok then spec, source = s, src end
    end

    local tag = "|cff33ff99[CFA]|r "
    if className == "HUNTER" or (mod and mod.classTag == "HUNTER") then
        local blessKey = spec and ("bless_" .. spec:lower()) or "bless_low"
        local bless = addon.L[blessKey] or addon.L["bless_sv"]
        print(tag .. bless)
        local specName = addon.L["spec_" .. (spec and spec:lower() or "sv")] or spec or "Survival"
        print(tag .. "|cFFCCCCCCspec:|r " .. tostring(source or "auto") .. " (" .. tostring(specName) .. ")")
    else
        local classLoc = UnitClass("player")
        print(string.format(addon.L["welcome_loaded"], tostring(classLoc)))
        if spec then
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
    elseif msg == "debug" or msg == "debug on" then
        addon.debugMode = (msg == "debug on") and true or not addon.debugMode
        print("|cff44ddff[CFA]|r modo debug: " .. (addon.debugMode and "LIGADO" or "DESLIGADO"))
        if addon.debugMode and addon.activeModule and addon.activeModule.DebugRotation then
            addon.activeModule.DebugRotation()
        end
    elseif msg == "debug off" then
        addon.debugMode = false
        print("|cff44ddff[CFA]|r modo debug: DESLIGADO")
    elseif msg == "probe" then
        addon:DebugProbe()
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
