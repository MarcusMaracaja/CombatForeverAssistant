-- Combat Forever Assistant — Shaman module: main rotation hub (rebuilt cleanly).
-- Uses global helpers from Shared/Functions.lua and Core.lua:
--   - Spec detection via Core:RegisterSpecDetection / Core:DetectSpec
--   - Character resources via addon.PopulateEnvResources / addon.HasManaPct
--   - Castability & cooldowns via addon.CheckCastable / Core:RunDeclaredRotation
--   - Rotation editor via addon.RotationEditor.Attach (ELE / ENH / REST + Extra tab)
--   - Weapon imbues detected via GetWeaponEnchantInfo() (not auras!)
-- Focuses on DPS rotations (Elemental, Enhancement, Restoration DPS fallback);
-- dedicated healer logic will be added in a future healer phase.
local _, addon = ...

local Shaman = addon.modules.SHAMAN
local L = addon.L

local EXTRA_KEYS = {
    lightning_shield   = true,
    water_shield       = true,
    flametongue_weapon = true,
    windfury_weapon    = true,
    strength_of_earth  = true,
    air_totem          = true,
    mana_spring        = true,
}

local combatStartedAt

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, t = pcall(GetTime)
    return ok and addon.SafeNumber(t, 0) or 0
end

local function playerInCombat()
    if type(UnitAffectingCombat) == "function" then
        local ok, v = pcall(UnitAffectingCombat, "player")
        local b = ok and addon.SafeBoolean and addon.SafeBoolean(v, nil)
        if b ~= nil then return b end
    end
    if type(InCombatLockdown) == "function" then
        local ok, v = pcall(InCombatLockdown)
        local b = ok and addon.SafeBoolean and addon.SafeBoolean(v, nil)
        if b ~= nil then return b end
    end
    return false
end

local function playerMoving()
    if type(GetUnitSpeed) == "function" then
        local ok, s = pcall(GetUnitSpeed, "player")
        local speed = ok and addon.SafeNumber(s, nil) or nil
        if speed ~= nil then return speed > 0 end
    end
    if type(IsPlayerMoving) == "function" then
        local ok, m = pcall(IsPlayerMoving)
        local b = ok and addon.SafeBoolean and addon.SafeBoolean(m, nil)
        if b ~= nil then return b end
    end
    return false
end

local function countActiveEnemies(hasEnemy)
    if type(addon.CountActiveEnemies) == "function" then
        return addon.CountActiveEnemies(hasEnemy)
    end
    return hasEnemy and 1 or 0
end

local function resolveMeleeRange(distance)
    if distance ~= nil then return distance <= 5 end
    if type(addon.IsInMeleeRange) == "function" then
        local r = addon:IsInMeleeRange("target")
        if r ~= nil then return r end
    end
    local ssID = Shaman.ResolveID(17364) or 17364
    if type(addon.IsSpellInRangeEx) == "function" then
        return addon:IsSpellInRangeEx(ssID, "target")
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Event tracker (beliefs, combat timer, target changes)
-- ---------------------------------------------------------------------------
local tracker = CreateFrame("Frame", "CombatForeverAssistantShamanTracker", UIParent)
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("PLAYER_TARGET_CHANGED")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(tracker.RegisterEvent, tracker, "TRAIT_CONFIG_UPDATED")

tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        wipe(Shaman.BuffBeliefs)
        Shaman.FlameShockBelief = nil
        Shaman.StormstrikeBelief = nil
        combatStartedAt = nil
        addon:InvalidateSpecTalentCache("SHAMAN")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Shaman.FlameShockBelief = nil
        Shaman.StormstrikeBelief = nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStartedAt = now()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatStartedAt = nil
    elseif event == "TRAIT_CONFIG_UPDATED" then
        addon:InvalidateSpecTalentCache("SHAMAN")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            Shaman.RecordCast(spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Spec detection (registered in Core's shared pipeline)
-- ---------------------------------------------------------------------------
addon:RegisterSpecDetection(Shaman, {
    charDbKey       = "shamanSpec",
    treeOrder       = { "ELE", "ENH", "REST" },
    validSpecs      = { "ELE", "ENH", "REST" },
    signatures      = {
        { spellID = 17364,  spec = "ENH",  source = "Stormstrike" },
        { spellID = 425336, spec = "ENH",  source = "Rage of the Farseer" },
        { spellID = 30823,  spec = "ENH",  source = "Shamanistic Rage" },
        { spellID = 16166,  spec = "ELE",  source = "Lightning Mastery" },
        { spellID = 16188,  spec = "REST", source = "Nature's Swiftness" },
    },
    defaultSpec     = "ELE",
    defaultTiebreak = "ELE",
})

function Shaman:DetectSpec()
    return addon:DetectSpec(self)
end

function Shaman:SetSpecOverride(specKey)
    if specKey == "auto" then
        addon.charDb.shamanSpec = nil
        addon:InvalidateSpecTalentCache("SHAMAN")
        return true
    end
    if specKey ~= "ELE" and specKey ~= "ENH" and specKey ~= "REST" then return false end
    addon.charDb.shamanSpec = specKey
    return true
end

-- ---------------------------------------------------------------------------
-- Extra buffs & totems toggles (per character)
-- ---------------------------------------------------------------------------
function Shaman:IsExtraSuggestionEnabled(key)
    if not EXTRA_KEYS[key] then return false end
    local settings = addon.charDb and addon.charDb.shamanExtras
    if type(settings) == "table" and settings[key] ~= nil then
        return settings[key] ~= false
    end
    -- Water Shield defaults off unless enabled, so Lightning Shield doesn't fight it
    if key == "water_shield" then return false end
    return true
end

function Shaman:SetExtraSuggestionEnabled(key, enabled)
    if not EXTRA_KEYS[key] or type(enabled) ~= "boolean" or not addon.charDb then return false end
    addon.charDb.shamanExtras = addon.charDb.shamanExtras or {}
    addon.charDb.shamanExtras[key] = enabled
    return true
end

-- ---------------------------------------------------------------------------
-- BuildEnv (uses Shared/Functions.lua globals)
-- ---------------------------------------------------------------------------
function Shaman:BuildEnv(specKey)
    specKey = specKey or self:DetectSpec()
    local hasEnemy = addon.UnitTargetExistsAndAttackable and addon.UnitTargetExistsAndAttackable() or false
    local distance = addon.TargetDistance and addon:TargetDistance("target") or nil
    local melee = resolveMeleeRange(distance)
    local inCombat = playerInCombat()
    local timeInCombat = (inCombat and combatStartedAt) and math.max(0, now() - combatStartedAt) or 0
    local enemies = countActiveEnemies(hasEnemy)

    local env = {
        spec                  = specKey,
        hasActiveEnemy        = hasEnemy,
        inCombat              = inCombat,
        isPvP                 = addon.IsPvPEnvironment and addon.IsPvPEnvironment() or false,
        isMelee               = melee,
        tooCloseForRanged     = (melee == true),
        targetDistance        = distance,
        targetInterruptible   = hasEnemy and (addon.IsTargetInterruptibleCasting and addon.IsTargetInterruptibleCasting("target") or false) or false,
        targetCasting         = hasEnemy and (addon.IsTargetInterruptibleCasting and addon.IsTargetInterruptibleCasting("target") or false) or false,
        isMoving              = playerMoving(),
        isAoE                 = enemies >= 2,
        enemies               = enemies,
        combatTime            = timeInCombat,
        maelstromStacks       = Shaman.GetMaelstromStacks(),
        clearcastingActive    = Shaman.IsClearcastingActive(),
        lightningMasteryActive = Shaman.IsBuffActive(16166, "lightning_mastery"),
        flameShockActive      = hasEnemy and Shaman.IsFlameShockActive() or false,
        stormstrikeActive     = hasEnemy and Shaman.IsStormstrikeDebuffActive() or false,
        targetSlowed          = hasEnemy and Shaman.IsTargetSlowed() or false,
        searingTotemActive    = Shaman.IsTotemSpellActive(3599, 1),
        magmaTotemActive      = Shaman.IsTotemSpellActive(8190, 1),
        fireTotemActive       = Shaman.IsTotemSlotActive(1, 1.5),
    }

    if type(addon.PopulateEnvResources) == "function" then
        addon.PopulateEnvResources(env, "player")
    end
    if env.manaPct == nil then env.manaPct = 100 end
    return env
end

-- ---------------------------------------------------------------------------
-- Suggestion & TryFlash plumbing (matches Core:RunDeclaredRotation contract)
-- ---------------------------------------------------------------------------
Shaman.TickFlashUsed = nil
Shaman.PendingSuggestion = nil
Shaman.SpellName = Shaman.SpellName
Shaman.CheckCastable = addon.CheckCastable

function Shaman:Suggest(spellID, color, asAdditional)
    if self.TickFlashUsed then return false end
    self.TickFlashUsed = true
    local knownID = Shaman.ResolveID(spellID) or spellID
    local suggestion = { spellID = knownID, color = color or "Damage" }
    if asAdditional and self.PendingSuggestion then
        self.PendingSuggestion.additional = self.PendingSuggestion.additional or {}
        table.insert(self.PendingSuggestion.additional, suggestion)
    else
        self.PendingSuggestion = suggestion
    end
    return true
end

function Shaman:TryFlash(spellID, color, condition, nodeName, env, opts, asAdditional)
    if self.TickFlashUsed then return false end
    opts = opts or {}
    local knownID = Shaman.ResolveID(spellID)
    if not knownID then
        addon:DebugPrint("Shaman", tostring(nodeName or spellID), "BLOQUEADO: spell desconhecida")
        return false
    end
    local spellName = Shaman.SpellName(knownID)
    if not spellName then
        addon:DebugPrint("Shaman", tostring(nodeName or spellID), "BLOQUEADO: nome indisponível")
        return false
    end
    if addon.IsPressSuppressed and addon:IsPressSuppressed(spellName) then
        addon:DebugPrint("Shaman", tostring(nodeName or spellID), "BLOQUEADO: botão pressionado agora")
        return false
    end
    if type(condition) == "function" then
        local ok, passed = pcall(condition, env)
        if not ok or not passed then return false end
    end

    local dbg = {}
    local castable = addon.CheckCastable({
        SpellID           = knownID,
        SpellName         = spellName,
        EnemyTargetNeeded = opts.noEnemy ~= true,
        Unit              = opts.unit or (opts.noEnemy and "player" or "target"),
        NoRangeCheck      = (opts.noRangeCheck == true or opts.noRange == true),
        NotIfActive       = opts.notIfActive == true,
        Debug             = dbg,
    })
    if not castable then
        addon:DebugPrint("Shaman", tostring(nodeName or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    addon:DebugPrint("Shaman", tostring(nodeName or spellID), "OK (sugere)")
    return self:Suggest(knownID, color or "Damage", asAdditional)
end

-- ---------------------------------------------------------------------------
-- Extra buffs & totems suggestions (weapon imbue via GetWeaponEnchantInfo!)
-- ---------------------------------------------------------------------------
local function canSuggestSelfSpell(spellID)
    local knownID = Shaman.ResolveID(spellID)
    if not knownID then return nil end
    local name = Shaman.SpellName(knownID)
    if not name then return nil end
    if addon.IsPressSuppressed and addon:IsPressSuppressed(name) then return nil end
    if addon.CheckCastable({
        SpellID           = knownID,
        SpellName         = name,
        EnemyTargetNeeded = false,
        Unit              = "player",
        NoRangeCheck      = true,
    }) then
        return { spellID = knownID, color = "Utility" }
    end
    return nil
end

local function nextExtraSuggestion(env, specKey)
    -- 1) Shield: Water Shield (if enabled & known, or low mana) vs Lightning Shield
    if not Shaman.HasAnyShieldActive() then
        local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 45, "player")
        if Shaman:IsExtraSuggestionEnabled("water_shield")
            and (lowMana or not Shaman:IsExtraSuggestionEnabled("lightning_shield")) then
            local sug = canSuggestSelfSpell(52127)
            if sug then return sug end
        end
        if Shaman:IsExtraSuggestionEnabled("lightning_shield") then
            local sug = canSuggestSelfSpell(324)
            if sug then return sug end
        end
        if Shaman:IsExtraSuggestionEnabled("water_shield") then
            local sug = canSuggestSelfSpell(52127)
            if sug then return sug end
        end
    end

    -- 2) Weapon imbue (GetWeaponEnchantInfo — ENH: Windfury -> Rockbiter; ELE/REST: Flametongue -> Rockbiter)
    if specKey == "ENH" then
        if Shaman:IsExtraSuggestionEnabled("windfury_weapon") then
            if Shaman.ResolveID(8232) then
                if not Shaman.HasWeaponEnchant("windfury") then
                    local sug = canSuggestSelfSpell(8232)
                    if sug then return sug end
                end
            elseif Shaman.ResolveID(8017) and not Shaman.HasWeaponEnchant("rockbiter") then
                local sug = canSuggestSelfSpell(8017)
                if sug then return sug end
            end
        end
    else
        if Shaman:IsExtraSuggestionEnabled("flametongue_weapon") then
            if Shaman.ResolveID(8024) then
                if not Shaman.HasWeaponEnchant("flametongue") then
                    local sug = canSuggestSelfSpell(8024)
                    if sug then return sug end
                end
            elseif Shaman.ResolveID(8017) and not Shaman.HasWeaponEnchant("rockbiter") then
                local sug = canSuggestSelfSpell(8017)
                if sug then return sug end
            end
        end
    end

    -- 3) Earth Totem: Strength of Earth (slot 2)
    if Shaman:IsExtraSuggestionEnabled("strength_of_earth")
        and not Shaman.IsBuffActive(8075, "strength_of_earth", "StrengthOfEarthAura")
        and not Shaman.IsTotemSlotActive(2, 2) then
        local sug = canSuggestSelfSpell(8075)
        if sug then return sug end
    end

    -- 4) Air Totem: Windfury Totem (ENH) / Grace of Air (fallback) (slot 4)
    if Shaman:IsExtraSuggestionEnabled("air_totem")
        and specKey == "ENH"
        and not Shaman.IsTotemSlotActive(4, 2) then
        if not Shaman.IsBuffActive(8512, "windfury_totem", "WindfuryTotemAura") then
            local sug = canSuggestSelfSpell(8512)
            if sug then return sug end
        end
        if not Shaman.IsBuffActive(8835, "grace_of_air", "GraceOfAirAura") then
            local sug = canSuggestSelfSpell(8835)
            if sug then return sug end
        end
    end

    -- 5) Water Totem: Mana Spring (pre-combat / low mana / long fight) (slot 3)
    local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 49, "player")
    if Shaman:IsExtraSuggestionEnabled("mana_spring")
        and (not env.inCombat or lowMana or env.combatTime >= 60)
        and not Shaman.IsBuffActive(5675, "mana_spring", "ManaSpringAura")
        and not Shaman.IsTotemSlotActive(3, 2) then
        local sug = canSuggestSelfSpell(5675)
        if sug then return sug end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Main tick entry point
-- ---------------------------------------------------------------------------
function Shaman:GetSuggestion()
    if addon.db and addon.db.shamanEnabled == false then return nil end
    local _, playerClass = UnitClass("player")
    if playerClass ~= "SHAMAN" then return nil end

    self.PendingSuggestion = nil
    self.TickFlashUsed = nil
    pcall(addon.HookActionButtonPress)

    if type(IsMounted) == "function" and IsMounted() then return nil end
    if addon.CastingOrChanneling and addon.CastingOrChanneling(nil, "player") then return nil end

    local specKey = self:DetectSpec()
    local env = self:BuildEnv(specKey)

    addon:RunDeclaredRotation(self, specKey, env)

    local extra = nextExtraSuggestion(env, specKey)
    local rotation = self.PendingSuggestion

    -- Low-priority racial when rotation has nothing else to recommend
    if not rotation and addon.SuggestRacial and addon:SuggestRacial(self, env) then
        rotation = self.PendingSuggestion
    end

    if extra then
        if rotation then extra.additional = { rotation } end
        return extra
    end
    return rotation
end

-- ---------------------------------------------------------------------------
-- /cfa status & /cfa debug / /cfa shaman diagnostics
-- ---------------------------------------------------------------------------
function Shaman:GetStatus()
    local specKey, source = self:DetectSpec()
    local title = self.RotationSpecs[specKey] and self.RotationSpecs[specKey].title or specKey
    local enabled = not (addon.db and addon.db.shamanEnabled == false)
    return string.format("Shaman — %s (%s) — %s", tostring(title), tostring(source),
        enabled and "ativo" or "desativado")
end

function Shaman:DebugRotation()
    local specKey, source = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    local hasMH, mhRem, mhID, mhReadable = Shaman.GetMainHandEnchantInfo()
    local totems = Shaman.GetActiveTotems()
    local function totemStr(slot)
        local t = totems[slot]
        if not t or not t.active then return "off" end
        return string.format("%s(%.0fs)", t.name ~= "" and t.name or "on", t.remaining or 0)
    end

    print("|cff44ddff[CFA dbg]|r ===== RELATÓRIO DA ROTAÇÃO (Shaman) =====")
    print(string.format(
        "|cff44ddff[CFA dbg]|r spec=%s (%s) | enemy=%s | combat=%s | melee=%s | moving=%s | AoE=%s(%d) | pvp=%s",
        tostring(specKey), tostring(source), tostring(env.hasActiveEnemy), tostring(env.inCombat),
        tostring(env.isMelee), tostring(env.isMoving), tostring(env.isAoE), env.enemies or 0, tostring(env.isPvP)))
    print(string.format(
        "|cff44ddff[CFA dbg]|r mana=%s (ok=%s) | maelstrom=%d | clearcast=%s | flameShock=%s | stormstrike=%s",
        env.manaPct and string.format("%.1f%%", env.manaPct) or "nil", tostring(env.manaReadable),
        env.maelstromStacks or 0, tostring(env.clearcastingActive),
        tostring(env.flameShockActive), tostring(env.stormstrikeActive)))
    print(string.format(
        "|cff44ddff[CFA dbg]|r armaMH: has=%s id=%s rem=%.0fs (ok=%s) | shield=%s | totens: F=%s E=%s W=%s A=%s",
        tostring(hasMH), tostring(mhID), mhRem or 0, tostring(mhReadable),
        tostring(Shaman.HasAnyShieldActive()),
        totemStr(1), totemStr(2), totemStr(3), totemStr(4)))

    local nodes = (type(self.GetEffectiveNodes) == "function" and self:GetEffectiveNodes(specKey))
        or (self.RotationSpecs[specKey] and self.RotationSpecs[specKey].nodes) or {}
    for _, node in ipairs(nodes) do
        local enabled = node.enabled ~= false
        local condOK = enabled and addon.NodeConditionPass(self, env, node, true)
        local knownID = Shaman.ResolveID(node.spellID)
        local locName = knownID and Shaman.SpellName(knownID) or nil
        local dbg = {}
        local castOK = false
        if condOK and knownID and locName then
            local opts = node.opts or {}
            castOK = addon.CheckCastable({
                SpellID           = knownID,
                SpellName         = locName,
                EnemyTargetNeeded = opts.noEnemy ~= true,
                Unit              = opts.unit or (opts.noEnemy and "player" or "target"),
                NoRangeCheck      = (opts.noRangeCheck == true or opts.noRange == true),
                NotIfActive       = opts.notIfActive == true,
                Debug             = dbg,
            }) and true or false
        elseif not knownID then
            dbg.reason = "spell desconhecida"
        elseif not locName then
            dbg.reason = "sem nome localizado"
        end
        print(string.format("|cff44ddff[CFA dbg]|r %-26s en=%-5s cond=%-5s id=%-7s cast=%-5s %s",
            tostring(node.id), tostring(enabled), tostring(condOK),
            tostring(knownID or node.spellID), tostring(castOK), tostring(dbg.reason or "")))
    end
end

-- ---------------------------------------------------------------------------
-- Attach shared Rotation Editor (ELE / ENH / REST + Extra tab)
-- ---------------------------------------------------------------------------
local function attachShamanEditor()
    if type(addon.RotationEditor) ~= "table"
        or type(addon.RotationEditor.Attach) ~= "function" then
        return false
    end

    local EXTRAS = {
        { key = "lightning_shield",   labelKey = "shaman_buff_lightning_shield", fallback = "Lightning Shield" },
        { key = "water_shield",       labelKey = "shaman_buff_water_shield",     fallback = "Water Shield" },
        { key = "flametongue_weapon", labelKey = "shaman_buff_flametongue",      fallback = "Flametongue Weapon (Elemental/Rest)" },
        { key = "windfury_weapon",    labelKey = "shaman_buff_windfury",         fallback = "Windfury Weapon (Enhancement)" },
        { key = "strength_of_earth",  labelKey = "shaman_buff_strength",         fallback = "Strength of Earth Totem" },
        { key = "air_totem",          labelKey = "shaman_buff_air_totem",        fallback = "Windfury / Grace of Air Totem (Enhancement)" },
        { key = "mana_spring",        labelKey = "shaman_buff_mana_spring",      fallback = "Mana Spring Totem" },
    }

    local function renderExtraTab(scrollChild, mod, rows)
        local y = -4
        for _, item in ipairs(EXTRAS) do
            local key, labelKey, fallback = item.key, item.labelKey, item.fallback
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(30)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)

            local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            check:SetChecked(mod:IsExtraSuggestionEnabled(key))
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", check, "RIGHT", 4, 0)
            label:SetText((L and L[labelKey]) or fallback)
            check:SetScript("OnClick", function(self)
                mod:SetExtraSuggestionEnabled(key, self:GetChecked() and true or false)
            end)
            rows[#rows + 1] = row
            y = y - 34
        end
        scrollChild:SetHeight(math.max(-y, 1))
    end

    return addon.RotationEditor.Attach(Shaman, {
        storageKey = "shamanRotation",
        title      = (L and L["shaman_tab"]) or "Shaman",
        specOrder  = { "ELE", "ENH", "REST" },
        extraTabs  = {
            {
                key    = "EXTRA",
                label  = "Extra",
                render = renderExtraTab,
                hint   = (L and L["shaman_extra_hint"]) or "",
            },
        },
    })
end

attachShamanEditor()

addon:RegisterModule("SHAMAN", Shaman)
