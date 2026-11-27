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
    optionsWidth = 520,
    optionsHeight = 420,
    assistSmartTabEnabled = true,
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
    if type(addon.DebugDumpResources) == "function" then
        addon.DebugDumpResources()
    end
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
local playerUnavailable = false

local function playerCanRun()
    return UnitExists("player") and not UnitIsDeadOrGhost("player")
end

local function clearPlayerSuggestions()
    if addon.Visuals then
        addon.Visuals.flashSpell = nil
        addon.Visuals.flashUntil = nil
        addon.Visuals.flashColor = nil
        if type(addon.Visuals.Hide) == "function" then addon.Visuals.Hide() end
    end
    if addon.KeyButton then addon.KeyButton.Hide() end
end

-- ---------------------------------------------------------------------------
-- Press suppression (global — qualquer classe pode usar).
-- Quando o jogador aperta o botão da skill piscando, para de piscar
-- imediatamente em vez de esperar o cast aterrissar.
-- ---------------------------------------------------------------------------
addon.PressSuppress = {}

function addon.OnSpinPressed(button)
    if not button or not button.GetAttribute then return end
    local action = button:GetAttribute("action")
    if not action then return end
    local actionType, id = GetActionInfo(tonumber(action) or action)
    if actionType == "spell" and id then
        local name = addon.Compat and addon.Compat.SpellName and addon.Compat.SpellName(id)
        if name then
            addon.PressSuppress[name] = GetTime() + 0.6
        end
    end
end

function addon:IsPressSuppressed(spellName)
    if not spellName or spellName == "" then return false end
    local untilTime = addon.PressSuppress[spellName]
    return not not (untilTime and GetTime() < untilTime)
end

function addon.HookActionButtonPress()
    if addon.HooksDone then return end
    addon.HooksDone = true
    addon._hookedButtons = {}
    local function hookPrefix(prefix)
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn and not btn.cfaPressHooked then
                btn.cfaPressHooked = true
                hooksecurefunc(btn, "Click", function(self)
                    pcall(addon.OnSpinPressed, self)
                end)
            end
        end
    end
    if type(SecureActionButton_OnClick) == "function" then
        hooksecurefunc("SecureActionButton_OnClick", function(self)
            pcall(addon.OnSpinPressed, self)
        end)
        return
    end
    local prefixes = { "ActionButton", "MultiBarRightButton", "MultiBarLeftButton",
        "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "PetActionButton", "StanceButton", "PossessButton" }
    for _, p in ipairs(prefixes) do hookPrefix(p) end
end

frame:SetScript("OnEvent", function(_, event, arg1, ...)
    -- caches de "spell conhecida" são invalidados quando o spellbook muda
    if (event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN")
        and addon.Compat and addon.Compat.InvalidateSpellCaches then
        addon.Compat.InvalidateSpellCaches()
    end
    if event == "SPELLS_CHANGED" then
        addon:InvalidateSpecTalentCache()
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
        addon:InvalidateSpecTalentCache()
    elseif event == "PLAYER_DEAD" then
        playerUnavailable = true
        clearPlayerSuggestions()
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
frame:RegisterEvent("PLAYER_DEAD")
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
    if addon.Consumables and type(addon.Consumables.GetSuggestions) == "function" then
        local ok, extras = pcall(addon.Consumables.GetSuggestions)
        if ok and type(extras) == "table" then
            for _, extra in ipairs(extras) do suggestions[#suggestions + 1] = extra end
        elseif not ok then
            local now = GetTime()
            addon.lastError = tostring(extras)
            if now - lastEquipmentErrorPrint > 10 then
                lastEquipmentErrorPrint = now
                print("[CFA] Consumables recommendation error: " .. tostring(extras))
            end
        end
    end
    local readySuggestions = {}
    local keySuggestion
    for _, candidate in ipairs(suggestions) do
        local onCooldown = false
        if type(candidate) == "table" and candidate.kind ~= "item"
            and type(candidate.spellID) == "number" then
            local remaining, duration
            onCooldown, remaining, duration = addon:IsSpellOnCooldown(candidate.spellID)
            if onCooldown then
                addon:DebugPrint("Sugestão removida por cooldown", candidate.spellID,
                    string.format("(%.1fs de %.1fs)", remaining, duration))
            elseif not keySuggestion then
                keySuggestion = candidate
            end
        end
        if not onCooldown then readySuggestions[#readySuggestions + 1] = candidate end
    end
    suggestions = readySuggestions

    if addon.Visuals then
        if #suggestions > 0 and addon.Visuals.ShowMany then
            addon.Visuals.ShowMany(suggestions)
        elseif keySuggestion then
            addon.Visuals.Show(keySuggestion.spellID, keySuggestion.color or "Utility")
        else
            addon.Visuals.Hide()
        end
    end
    if addon.KeyButton then
        local keyShown = false
        if addon.db.keyButton then
            for _, candidate in ipairs(suggestions) do
                if type(candidate) == "table" and candidate.kind ~= "item"
                    and type(candidate.spellID) == "number"
                    and addon.KeyButton.ShowFor(candidate.spellID, true) then
                    keyShown = true
                    break
                end
            end
            if not keyShown and addon.db.keyButtonAlways then
                addon.KeyButton.ShowPlaceholder()
            elseif not keyShown then
                addon.KeyButton.Hide()
            end
        else
            addon.KeyButton.Hide()
        end
    end
end

frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end
    elapsed = 0
    if not playerCanRun() then
        if not playerUnavailable then clearPlayerSuggestions() end
        playerUnavailable = true
        return
    end
    playerUnavailable = false
    if not addon.welcomeSent then
        addon.welcomeSent = true
        pcall(addon.PrintWelcome, addon)
    end
    local mod = addon.activeModule
    -- Test-flash (icon click in the editor / /cfa test) wins over the rotation
    if addon.Visuals and addon.Visuals.flashSpell and GetTime() < (addon.Visuals.flashUntil or 0) then
        addon.Visuals.Show(addon.Visuals.flashSpell, addon.Visuals.flashColor or "Utility")
        return
    elseif addon.Visuals and addon.Visuals.flashSpell then
        -- flash just expired: clear it once without wiping regular highlights every tick
        addon.Visuals.flashSpell, addon.Visuals.flashUntil = nil, nil
        if addon.Visuals.Hide then addon.Visuals.Hide() end
        if addon.KeyButton then
            if addon.db.keyButtonAlways then addon.KeyButton.ShowPlaceholder() else addon.KeyButton.Hide() end
        end
    end
    -- Enquanto o jogador estiver comendo ou bebendo fora de combate, suprime a
    -- rotação de classe (para não interromper com aspectos/buffs/skills), mas
    -- mantém o pipeline de Consumables para permitir comer E beber ao mesmo tempo.
    if addon.Consumables and type(addon.Consumables.IsEatingOrDrinking) == "function" then
        local okED, eatingOrDrinking = pcall(addon.Consumables.IsEatingOrDrinking)
        if okED and eatingOrDrinking then
            updateSuggestionDisplay(nil, mod)
            return
        end
    end
    if not mod or not mod.GetSuggestion then
        updateSuggestionDisplay(nil, mod)
        return
    end
    local now = GetTime()
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
        local now2 = GetTime()
        if now2 - lastErrorPrint > 10 then
            lastErrorPrint = now2
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

function addon.Compat.RegisterSpellFamilies(families)
    if type(families) ~= "table" then return end
    for _, fam in ipairs(families) do
        if type(fam) == "table" and #fam > 0 then
            FAMILIES[#FAMILIES + 1] = fam
            for _, id in ipairs(fam) do
                if type(id) == "number" then familyOf[id] = fam end
            end
        end
    end
end

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
    -- busca por nome no cache nome->ID (preenchido por SpellInfoByID/SpellName: [name] = id)
    local cache = addon.Compat.SpellNameToID or {}
    if type(cache[name]) == "number" then return cache[name] end
    local lower = name:lower()
    for k, v in pairs(cache) do
        if type(k) == "string" and type(v) == "number" and k:lower() == lower then return v end
        if type(v) == "string" and type(k) == "number" and v:lower() == lower then return k end
    end
    -- varredura do spellbook como fallback
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        for i = 1, 300 do
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, "spell")
            if ok and info and info.name then
                local base = info.name:gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if base:lower() == lower then
                    local id = addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(info.id) or info.id
                    return id
                end
            end
        end
    end
    return nil
end

-- Cooldown de um spellID pelo cliente Forever (C_Spell.GetSpellCooldown).
-- Retorna (timeLeft, duration); campos secretos são desconhecidos, não cooldown infinito.
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
    local secret = value ~= nil and _G.issecretvalue and issecretvalue(value) or false
    return addon.SafeNumber(value, nil), secret
end

local function cooldownFromInfo(info)
    if type(info) ~= "table" then return 0, 0, false end
    local start, startSecret = cooldownField(info, "startTime", "cooldownStartTime")
    local duration, durationSecret = cooldownField(info, "duration", "cooldownDuration")
    local okActive, activeValue = pcall(function() return info.isActive end)
    local activeSecret = okActive and activeValue ~= nil
        and _G.issecretvalue and issecretvalue(activeValue) or false
    local isActive = okActive and not activeSecret and activeValue == true
    local timeLeft
    if start ~= nil and duration ~= nil then
        local now = addon.SafeNumber(GetTime(), 0) or 0
        timeLeft = math.max(0, start + duration - now)
    end
    if timeLeft == nil then
        if isActive and duration and duration > 0 then
            if duration <= 1.5 then return 0, duration, true end
            return duration, duration, true
        end
        if startSecret or durationSecret or activeSecret then
            return 0, duration or 0, false
        end
        return 0, 0, false
    end
    if timeLeft > 0 then
        return timeLeft, duration or 0, true
    end
    if isActive and duration and duration > 0 then
        return duration, duration, true
    end
    return 0, duration or 0, true
end

local function cooldownFromDurationAPI(getter, actionID)
    local ok, durationObject = pcall(getter, actionID, true)
    if not ok then return 0, 0, false, false end
    if durationObject == nil then return 0, 0, true, true end

    local okMethod, getRemaining = pcall(function()
        return durationObject.GetRemainingDuration
    end)
    if not okMethod or type(getRemaining) ~= "function" then return 0, 0, false, false end

    local okRemaining, remaining = pcall(getRemaining, durationObject)
    if not okRemaining or (_G.issecretvalue and issecretvalue(remaining)) then
        return 0, 0, false, false
    end
    remaining = addon.SafeNumber(remaining, nil)
    if remaining == nil then return 0, 0, false, false end

    local duration = remaining
    local okTotalMethod, getTotal = pcall(function()
        return durationObject.GetTotalDuration
    end)
    if okTotalMethod and type(getTotal) == "function" then
        local okTotal, total = pcall(getTotal, durationObject)
        if okTotal and not (_G.issecretvalue and issecretvalue(total)) then
            duration = addon.SafeNumber(total, remaining) or remaining
        end
    end
    return math.max(0, remaining), math.max(0, duration), true, true
end

function addon.Compat.SpellCooldown(spellID)
    if type(spellID) ~= "number" then return 0, 0, false end
    if C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function" then
        local remaining, duration, readable, ignoresGCD =
            cooldownFromDurationAPI(C_Spell.GetSpellCooldownDuration, spellID)
        if readable then return remaining, duration, true, ignoresGCD end
    end
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok then
            local cooldown, duration, readable = cooldownFromInfo(info)
            if readable then return cooldown, duration, true, false end
        end
    end
    if type(GetSpellCooldown) == "function" then
        local ok, start, duration = pcall(GetSpellCooldown, spellID)
        if ok then
            local remaining, total, readable = cooldownFromInfo({ startTime = start, duration = duration })
            return remaining, total, readable, false
        end
    end
    return 0, 0, false, false
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
        if v == 1 then
            if type(addon.HasManaPct) == "function" then return (addon.HasManaPct(15)) end
            return (env.manaPct or 100) > 15
        end
        if v == 2 then
            if type(addon.HasManaPct) == "function" then return (addon.HasManaPct(40)) end
            return (env.manaPct or 100) > 40
        end
        if v == 3 then
            if type(addon.HasManaPct) == "function" then return (addon.HasManaPct(50)) end
            return (env.manaPct or 100) > 50
        end
        if v == 4 then
            if type(addon.HasRage) == "function" then return (addon.HasRage(40)) end
            return (env.rage == nil or env.rage >= 40)
        end
        if v == 5 then
            if type(addon.HasEnergy) == "function" then return (addon.HasEnergy(40)) end
            return (env.energy == nil or env.energy >= 40)
        end
        if v == 6 then
            if type(addon.HasComboPoints) == "function" then return (addon.HasComboPoints(5)) end
            return ((env.combo or env.comboPoints or 0) >= 5)
        end
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
    local predicate = (type(predicates) == "table" and predicates[condition])
        or (type(addon.RotationPredicates) == "table" and addon.RotationPredicates[condition])
        or nil
    if type(predicate) ~= "table" or type(predicate.fn) ~= "function" then
        return not strict
    end
    local ok, result = pcall(predicate.fn, env)
    return ok and result and true or false
end

-- ---------------------------------------------------------------------------
-- Global spec detection infrastructure (shared by all classes).
--
-- Pipeline (em ordem de prioridade):
--   1) Override salvo por personagem (charDb[config.charDbKey])
--   2) Leitura de pontos de talento via C_ClassTalents / C_Traits
--      (mapeamento ordinal de treeIDs, pois nomes de árvores podem ser
--      vazios/genéricos no cliente Forever), com cache e proteção pcall.
--   3) Fallback por IsSpellKnown de spells assinatura (config.signatures)
--   4) defaultSpec / defaultTiebreak
--
-- Cada módulo de classe chama addon:RegisterSpecDetection(module, config)
-- uma vez no carregamento, informando apenas seus dados específicos
-- (chaves de spec, ordem das árvores, spells assinatura, chave de override).
-- ---------------------------------------------------------------------------
addon.SpecDetectionConfigs = {}
local _talentCache = {}

local function specCacheKey(classTag)
    return classTag or "unknown"
end

function addon:RegisterSpecDetection(module, config)
    if type(module) ~= "table" or type(config) ~= "table" then return false end
    if type(config.charDbKey) ~= "string" then return false end
    if type(config.treeOrder) ~= "table" or #config.treeOrder == 0 then return false end
    if type(config.validSpecs) ~= "table" then config.validSpecs = {} end
    if type(config.signatures) ~= "table" then config.signatures = {} end
    if type(config.defaultSpec) ~= "string" then config.defaultSpec = config.validSpecs[1] end
    if type(config.defaultTiebreak) ~= "string" then config.defaultTiebreak = config.defaultSpec end

    local classTag = module.classTag or moduleName or "unknown"
    self.SpecDetectionConfigs[classTag] = config
    module._specConfig = config
    return true
end

function addon:GetSpecConfig(module)
    if type(module) ~= "table" then return nil end
    local classTag = module.classTag or moduleName or "unknown"
    return self.SpecDetectionConfigs[classTag]
end

-- Invalida o cache de talentos de uma classe (ou de todas, se classTag for nil).
function addon:InvalidateSpecTalentCache(classTag)
    if classTag then
        _talentCache[specCacheKey(classTag)] = nil
    else
        wipe(_talentCache)
    end
end

local function readTalentPointsOrdinal(config)
    if not (C_ClassTalents and C_Traits) then return false end
    local okCfg, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not okCfg or not cfg then return false end
    if _G.issecretvalue and issecretvalue(cfg) then return false end

    local okInfo, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return false end

    local counts = {}
    for idx, treeID in ipairs(info.treeIDs) do
        local specKey = config.treeOrder[idx]
        if specKey then
            local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
            local total = 0
            if type(nodes) == "table" then
                for _, nodeID in ipairs(nodes) do
                    local okNI, ni = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
                    if okNI and type(ni) == "table" then
                        total = total + (addon.SafeNumber(ni.currentRank)
                            or addon.SafeNumber(ni.ranksPurchased)
                            or addon.SafeNumber(ni.activeRank) or 0)
                    end
                end
            end
            counts[specKey] = total
        end
    end
    return counts
end

function addon:DetectSpec(module)
    if type(module) ~= "table" then return nil, "no module" end
    local config = self:GetSpecConfig(module)
    if not config then return nil, "no spec config" end

    -- 1) Override salvo por personagem
    local charDb = module.charDb or addon.charDb
    if type(charDb) == "table" then
        local override = charDb[config.charDbKey]
        for _, valid in ipairs(config.validSpecs) do
            if override == valid then return override, "override" end
        end
    end

    -- 2) Leitura de talentos via C_ClassTalents / C_Traits (ordinal, cacheada 1x por sessão/SPELLS_CHANGED)
    local cacheKey = specCacheKey(module.classTag or "unknown")
    local cached = _talentCache[cacheKey]
    if cached == nil then
        cached = readTalentPointsOrdinal(config) or false
        _talentCache[cacheKey] = cached
    end
    if type(cached) == "table" then
        local selected, best, hasPoints, tied = config.defaultSpec, -1, false, false
        for _, specKey in ipairs(config.treeOrder) do
            local points = tonumber(cached[specKey]) or 0
            if points > 0 then hasPoints = true end
            if points > best then
                selected, best, tied = specKey, points, false
            elseif points == best then
                tied = true
            end
        end
        if hasPoints then
            if tied and config.defaultTiebreak and (tonumber(cached[config.defaultTiebreak]) or 0) == best then
                selected = config.defaultTiebreak
            end
            local parts = {}
            for _, s in ipairs(config.treeOrder) do
                parts[#parts + 1] = s .. "=" .. tostring(tonumber(cached[s]) or 0)
            end
            return selected, "C_Traits " .. table.concat(parts, " ")
        end
    end

    -- 3) Fallback por IsSpellKnown de spells assinatura
    if type(IsSpellKnown) == "function" then
        for _, sig in ipairs(config.signatures) do
            if type(sig.spellID) == "number" and IsSpellKnown(sig.spellID) then
                return sig.spec, sig.source or "talent signature"
            end
        end
    end

    -- 4) Fallback padrão
    return config.defaultSpec, "default"
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
ACTION_SLOT_CACHE_FRAME:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
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
    if not slot then return 0, 0, false, false end
    if C_ActionBar and type(C_ActionBar.GetActionCooldownDuration) == "function" then
        local remaining, duration, readable, ignoresGCD =
            cooldownFromDurationAPI(C_ActionBar.GetActionCooldownDuration, slot)
        if readable then return remaining, duration, true, ignoresGCD end
    end
    if C_ActionBar and type(C_ActionBar.GetActionCooldown) == "function" then
        local ok, info = pcall(C_ActionBar.GetActionCooldown, slot)
        if ok then
            local cooldown, duration, readable = cooldownFromInfo(info)
            if readable then return cooldown, duration, true, false end
        end
    end
    if type(GetActionCooldown) == "function" then
        local ok, start, duration = pcall(GetActionCooldown, slot)
        if ok then
            local remaining, total, readable = cooldownFromInfo({ startTime = start, duration = duration })
            return remaining, total, readable, false
        end
    end
    return 0, 0, false, false
end

function addon:IsSpellOnCooldown(spellID)
    if type(spellID) ~= "number" then return false, 0, 0, false end

    local knownID = addon.Compat and addon.Compat.ResolveKnownID
        and addon.Compat.ResolveKnownID(spellID) or spellID
    local ids, seenIDs = {}, {}
    local function addID(id)
        if type(id) == "number" and not seenIDs[id] then
            seenIDs[id] = true
            ids[#ids + 1] = id
        end
    end
    addID(knownID)
    addID(spellID)
    local families = addon.Compat and addon.Compat.FamilyOf
    local family = families and (families[knownID] or families[spellID])
    if family then
        for _, id in ipairs(family) do addID(id) end
    end

    local cooldown, duration, readable, onCooldown = 0, 0, false, false
    local function considerCooldown(remaining, cooldownDuration, isReadable, ignoresGCD)
        if not isReadable then return end
        readable = true
        cooldownDuration = cooldownDuration or 0
        if remaining <= 0.05 or (not ignoresGCD and cooldownDuration <= 1.5 and remaining <= 1.5) then return end
        onCooldown = true
        if remaining > cooldown then
            cooldown, duration = remaining, cooldownDuration
        end
    end
    for _, id in ipairs(ids) do
        local remaining, spellDuration, spellReadable, ignoresGCD = addon.Compat.SpellCooldown(id)
        considerCooldown(remaining, spellDuration, spellReadable, ignoresGCD)
    end

    local seenSlots = {}
    for _, id in ipairs({ knownID, spellID }) do
        local slot = addon:FindActionSlot(id)
        if slot and not seenSlots[slot] then
            seenSlots[slot] = true
            local remaining, actionDuration, actionReadable, ignoresGCD = addon:ActionCooldown(slot)
            considerCooldown(remaining, actionDuration, actionReadable, ignoresGCD)
        end
    end

    return onCooldown, cooldown, duration, readable
end

-- ---------------------------------------------------------------------------
-- IsSpellOnCD — função booleana pura: verdadeira se a spell estiver em cooldown.
-- Não depende do campo "readable" (valores secretos no cliente Forever fazem
-- o IsSpellOnCooldown retornar false durante o combate). Usar esta função em
-- todos os gates de recomendação para nunca sugerir skill em cooldown.
-- ---------------------------------------------------------------------------
function addon:IsSpellOnCD(spellID)
    if type(spellID) ~= "number" then return false end
    local knownID = addon.Compat and addon.Compat.ResolveKnownID
        and addon.Compat.ResolveKnownID(spellID) or spellID
    local ids = {knownID, spellID}
    local families = addon.Compat and addon.Compat.FamilyOf
    local family = families and (families[knownID] or families[spellID])
    if family then
        for _, id in ipairs(family) do
            table.insert(ids, id)
        end
    end
    local now = addon.SafeNumber(GetTime(), 0)
    for _, id in ipairs(ids) do
        -- C_Spell.GetSpellCooldownDuration (objeto com GetRemainingDuration)
        if C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function" then
            local ok, obj = pcall(C_Spell.GetSpellCooldownDuration, id, true)
            if ok and obj and type(obj.GetRemainingDuration) == "function" then
                local ok2, remaining = pcall(obj.GetRemainingDuration, obj)
                remaining = addon.SafeNumber(remaining, nil)
                if ok2 and type(remaining) == "number" and remaining > 0.5 then
                    return true
                end
            end
        end
        -- C_Spell.GetSpellCooldown (tabela startTime/duration/isActive)
        if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
            local ok, info = pcall(C_Spell.GetSpellCooldown, id)
            if ok and type(info) == "table" then
                local start = addon.SafeNumber(info.startTime or info.cooldownStartTime or 0, 0)
                local dur = addon.SafeNumber(info.duration or info.cooldownDuration or 0, 0)
                local active = info.isActive
                -- Se o cliente reporta isActive=true, a spell está em cooldown
                -- mesmo que startTime/duration sejam secretos no Forever.
                if active == true then
                    return true
                end
                if type(start) == "number" and type(dur) == "number" and dur > 1.5 then
                    local timeLeft = start + dur - now
                    if timeLeft > 0.5 then return true end
                end
            end
        end
        -- GetSpellCooldown legado (start, duration)
        if type(GetSpellCooldown) == "function" then
            local ok, start, duration = pcall(GetSpellCooldown, id)
            start = addon.SafeNumber(start, 0)
            duration = addon.SafeNumber(duration, 0)
            if ok and type(start) == "number" and type(duration) == "number"
               and duration > 1.5 then
                local timeLeft = start + duration - now
                if timeLeft > 0.5 then return true end
            end
        end
    end
    return false
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
        local resolved = addon.Compat and addon.Compat.SpellIDFromName and addon.Compat.SpellIDFromName(spellName)
        spellID = addon.SafeNumber(resolved, nil)
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

    local onCooldown, cooldown, duration = addon:IsSpellOnCooldown(knownID or spellID)
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

    -- Usa a função booleana IsSpellOnCD, que não depende de "readable"
    -- (valores secretos no cliente Forever fazem IsSpellOnCooldown retornar
    -- false durante o combate, deixando skills em cooldown serem recomendadas).
    if addon:IsSpellOnCD(knownID or spellID) then
        return fail("em cooldown")
    end

    local notIfActiveOk = true
    local lag = 0.2
    if not z.NotIfActive and not Aura then
        -- sem NotIfActive e sem aura: passa
    else
        local current = false
        if addon.Compat and addon.Compat.IsCurrentSpell then
            current = addon.Compat.IsCurrentSpell(knownID or baseName)
        elseif type(IsCurrentSpell) == "function" then
            local ok, c = pcall(IsCurrentSpell, spellName)
            if ok and not (_G.issecretvalue and issecretvalue(c)) then current = not not c end
        end
        local casting = nil
        if addon.Compat and addon.Compat.CastingOrChanneling then
            casting = addon.Compat.CastingOrChanneling(baseName, "player")
        end
        if current then
            notIfActiveOk = false
        elseif casting then
            local rem = addon.SafeNumber(casting, nil)
            notIfActiveOk = (not Aura and rem ~= nil and rem <= lag)
        else
            notIfActiveOk = true
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

    if notEnoughPower then return fail("sem mana/poder") end
    if not (z.EvenIfNotUsable or isUsable) then return fail("spell não utilizável agora") end
    if not notIfActiveOk then return fail("já está ativa/conjurando") end
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

    local function safeBool(v)
        if type(addon.SafeBoolean) == "function" then return addon.SafeBoolean(v, nil) end
        if type(v) ~= "boolean" then return nil end
        if _G.issecretvalue and issecretvalue(v) then return nil end
        return v
    end

    if id and C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        local ok, rawUsable, rawNoPower = pcall(C_Spell.IsSpellUsable, id)
        if ok then
            local usable = safeBool(rawUsable)
            local noPower = safeBool(rawNoPower)
            if noPower == true then
                return false, true
            end
            if usable ~= nil then
                return usable, (noPower == true)
            end
        end
    end

    -- Fallback pelo slot na barra de ação (secret-safe)
    if id and type(addon.CheckActionUsable) == "function" then
        local aUsable, aNoPower, aReadable = addon.CheckActionUsable(id)
        if aReadable then
            if aNoPower == true then return false, true end
            if aUsable ~= nil then return aUsable, (aNoPower == true) end
        end
    end

    -- Fallback por custo da spell vs UnitPower via camada global de recursos
    if id and type(addon.GetSpellPowerCost) == "function" and type(addon.GetResource) == "function" then
        local costInfo = addon.GetSpellPowerCost(id)
        if costInfo and costInfo.readable and costInfo.effectiveCost then
            local cur, _, _, readable = addon.GetResource(costInfo.powerType, "player")
            if readable then
                local enough = cur >= costInfo.effectiveCost
                return enough, (not enough)
            end
        end
    end

    -- Fallback legado (secret-safe)
    if type(IsUsableSpell) == "function" then
        local ok, rawUsable, rawNoPower = pcall(IsUsableSpell, spellName)
        if ok then
            local usable = safeBool(rawUsable)
            local noPower = safeBool(rawNoPower)
            if noPower == true then return false, true end
            if usable ~= nil then return usable, (noPower == true) end
        end
    end
    return true, false
end

function addon.Compat.IsCurrentSpell(spellName)
    local id = type(spellName) == "number" and spellName
        or (addon.Compat.SpellIDFromName and addon.Compat.SpellIDFromName(spellName))
    if id and C_Spell and type(C_Spell.IsCurrentSpell) == "function" then
        local ok, c = pcall(C_Spell.IsCurrentSpell, id)
        if ok then
            local b = type(addon.SafeBoolean) == "function" and addon.SafeBoolean(c, nil)
                or (type(c) == "boolean" and not (_G.issecretvalue and issecretvalue(c)) and c or nil)
            if b ~= nil then return b end
        end
    end
    local name = addon.Compat.SpellName and addon.Compat.SpellName(spellName) or spellName
    if not name then return false end
    if type(IsCurrentSpell) == "function" then
        local ok, c = pcall(IsCurrentSpell, name)
        if ok and not (_G.issecretvalue and issecretvalue(c)) then return not not c end
    end
    return false
end

function addon.Compat.GetCasting(spellName, unit)
    unit = unit or "player"
    if type(UnitCastingInfo) == "function" then
        local ok, _, _, _, startMS, endMS = pcall(UnitCastingInfo, unit)
        startMS = ok and addon.SafeNumber(startMS, nil) or nil
        endMS = ok and addon.SafeNumber(endMS, nil) or nil
        if endMS and startMS then
            local remaining = (endMS - (GetTime and GetTime() * 1000 or 0)) / 1000
            if remaining > 0 then return remaining end
            return 0
        end
    end
    return nil
end

function addon.Compat.CastingOrChanneling(spellName, unit)
    unit = unit or "player"
    local remaining = nil
    if type(UnitCastingInfo) == "function" then
        local okCast, _, _, _, startMS, endMS = pcall(UnitCastingInfo, unit)
        startMS = okCast and addon.SafeNumber(startMS, nil) or nil
        endMS = okCast and addon.SafeNumber(endMS, nil) or nil
        if endMS and startMS then
            remaining = (endMS - (GetTime and GetTime() * 1000 or 0)) / 1000
            if remaining > 0 then return remaining end
        end
    end
    if type(UnitChannelInfo) == "function" then
        local okChan, _, _, _, _, endMS = pcall(UnitChannelInfo, unit)
        endMS = okChan and addon.SafeNumber(endMS, nil) or nil
        if endMS then
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
    local disabled = (type(module.GetRotationDisabled) == "function" and module:GetRotationDisabled(specKey)) or nil

    for _, node in ipairs(nodes) do
        if node.enabled ~= false and not (disabled and disabled[node.id]) then
            local pass = addon.NodeConditionPass(module, env, node)
            if pass then
                if addon.debugMode then
                    addon:DebugPrint("nó", tostring(node.id), "cond=" .. tostring(node.condition),
                        "condOK=true", "enabled=ok")
                end
                local knownID = addon.Compat.HighestKnownSpellID(node.spellID) or node.spellID
                if module:TryFlash(knownID, node.color, function() return true end, node.name, env, node.opts, node.passthrough) then
                    if addon.debugMode then
                        addon:DebugPrint("   -> SUGERIDO", tostring(node.id), tostring(knownID))
                    end
                    if not node.passthrough then return true end
                    -- Nós com passthrough (ex: Chute de Moa) não travam
                    -- as próximas habilidades na mesma rotação deste tick.
                    module.TickFlashUsed = nil
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
            addon.activeModule:DebugRotation()
        end
    elseif msg == "debug off" then
        addon.debugMode = false
        print("|cff44ddff[CFA]|r modo debug: DESLIGADO")
    elseif msg == "probe" then
        addon:DebugProbe()
    elseif msg == "res" or msg == "resources" or msg == "maul" or msg:match("^res%s+%d+$") then
        local idStr = msg:match("^res%s+(%d+)$")
        local spellID = idStr and tonumber(idStr) or (msg == "maul" and 6807 or nil)
        if type(addon.DebugDumpResources) == "function" then
            addon.DebugDumpResources(spellID)
        else
            print("|cff44ddff[CFA]|r DebugDumpResources indisponível.")
        end
    elseif msg == "items" or msg == "food" or msg == "consumables" or msg == "potions" then
        if addon.Consumables and type(addon.Consumables.DebugDump) == "function" then
            addon.Consumables.DebugDump()
        else
            print("|cff44ddff[CFA]|r Consumables.DebugDump indisponível.")
        end
    elseif msg == "shaman" then
        local mod = addon.modules and addon.modules.SHAMAN
        if mod and type(mod.DebugRotation) == "function" then
            mod:DebugRotation()
        else
            print("|cff44ddff[CFA]|r Módulo Shaman indisponível.")
        end
    elseif msg == "priest" then
        local mod = addon.modules and addon.modules.PRIEST
        if mod and type(mod.DebugRotation) == "function" then
            mod:DebugRotation()
        else
            print("|cff44ddff[CFA]|r Módulo Priest indisponível.")
        end
    elseif msg == "warrior" then
        local mod = addon.modules and addon.modules.WARRIOR
        if mod and type(mod.DebugRotation) == "function" then
            mod:DebugRotation()
        else
            print("|cff44ddff[CFA]|r Módulo Warrior indisponível.")
        end
    elseif msg == "key" then
        addon.db.keyButton = not addon.db.keyButton
        print(addon.db.keyButton and L["key_button_shown"] or L["key_button_hidden"])
    elseif msg == "minimap" then
        addon.db.minimapHidden = not addon.db.minimapHidden
        if addon.Minimap then addon.Minimap.Refresh() end
        print(addon.db.minimapHidden and L["minimap_hidden"] or L["minimap_shown"])
    elseif msg == "cd" then
        local id = 1317257
        local n = nil
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local ok, info = pcall(C_Spell.GetSpellInfo, id)
            if ok and type(info) == "table" then n = info.name end
        end
        print("|cff44ddff[CFA cd]|r Chute de Moa (1317257):")
        print("  Nome:", tostring(n))
        if C_Spell and C_Spell.GetSpellCooldownDuration then
            local ok, obj = pcall(C_Spell.GetSpellCooldownDuration, id, true)
            print("  GetSpellCooldownDuration ok=", tostring(ok), "tipo=", type(obj))
            if obj and obj.GetRemainingDuration then
                local ok2, rem = pcall(obj.GetRemainingDuration, obj)
                print("  Remaining=", tostring(rem))
            end
        end
        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, info = pcall(C_Spell.GetSpellCooldown, id)
            print("  GetSpellCooldown ok=", tostring(ok))
            if ok and type(info) == "table" then
                print("  startTime=", tostring(info.startTime), "duration=", tostring(info.duration), "isActive=", tostring(info.isActive))
            end
        end
        if IsSpellKnown then
            print("  IsSpellKnown=", tostring(IsSpellKnown(id)))
        end
        if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
            local ok2, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id)
            print("  IsSpellKnownOrInSpellBook=", tostring(known))
        end
        if CFA and CFA.IsSpellOnCooldown then
            local onCd, rem, dur, readable = CFA:IsSpellOnCooldown(id)
            print("  CFA:IsSpellOnCooldown -> onCd=", tostring(onCd), "remaining=", tostring(rem), "duration=", tostring(dur), "readable=", tostring(readable))
        end
        print("|cff44ddff[CFA cd]|r fim")
    else
        print(L["slash_help"])
    end
end
