-- Combat Forever Assistant — Priest DPS module: main rotation hub.
-- Uses global helpers from Shared/Functions.lua and Core.lua:
--   - Spec detection via Core:RegisterSpecDetection / Core:DetectSpec (DISC / HOLY / SHAD)
--   - Character resources via addon.PopulateEnvResources / addon.HasManaPct
--   - Castability & cooldowns via addon.CheckCastable / Core:RunDeclaredRotation
--   - Rotation editor via addon.RotationEditor.Attach (SHAD / DISC / HOLY + Extra tab)
-- Focuses on DPS rotations (Shadow DPS, Discipline Smite DPS, Holy DPS fallback);
-- dedicated healer logic will be added in a future healer phase.
local _, addon = ...

local Priest = addon.modules.PRIEST
local L = addon.L

local EXTRA_KEYS = {
    fortitude         = true,
    inner_fire        = true,
    divine_spirit     = true,
    shadow_protection = true,
    fear_ward         = true,
}

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

local function playerHealthPct()
    local okC, cur = pcall(UnitHealth, "player")
    local okM, maxV = pcall(UnitHealthMax, "player")
    cur = okC and addon.SafeNumber(cur, nil) or nil
    maxV = okM and addon.SafeNumber(maxV, nil) or nil
    if cur and maxV and maxV > 0 then
        return math.max(0, math.min(100, (cur / maxV) * 100))
    end
    return nil
end

local function countActiveEnemies(hasEnemy)
    if type(addon.CountActiveEnemies) == "function" then
        return addon.CountActiveEnemies(hasEnemy)
    end
    return hasEnemy and 1 or 0
end

-- ---------------------------------------------------------------------------
-- Event tracker (beliefs, target changes, talent cache invalidation)
-- ---------------------------------------------------------------------------
local tracker = CreateFrame("Frame", "CombatForeverAssistantPriestTracker", UIParent)
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("PLAYER_TARGET_CHANGED")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(tracker.RegisterEvent, tracker, "TRAIT_CONFIG_UPDATED")

tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        wipe(Priest.BuffBeliefs)
        wipe(Priest.TargetBeliefs)
        if Priest.AllyBeliefs then wipe(Priest.AllyBeliefs) end
        addon:InvalidateSpecTalentCache("PRIEST")
    elseif event == "PLAYER_TARGET_CHANGED" then
        wipe(Priest.TargetBeliefs)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        addon:InvalidateSpecTalentCache("PRIEST")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            Priest.RecordCast(spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Spec detection (registered in Core's shared pipeline)
-- Classic Priest tree order: 1=Discipline, 2=Holy, 3=Shadow.
-- ---------------------------------------------------------------------------
addon:RegisterSpecDetection(Priest, {
    charDbKey       = "priestSpec",
    treeOrder       = { "DISC", "HOLY", "SHAD" },
    validSpecs      = { "SHAD", "DISC", "HOLY" },
    signatures      = {
        { spellID = 15473, spec = "SHAD", source = "Shadowform" },
        { spellID = 15407, spec = "SHAD", source = "Mind Flay" },
        { spellID = 15286, spec = "SHAD", source = "Vampiric Embrace" },
        { spellID = 47540, spec = "DISC", source = "Penance" },
        { spellID = 10060, spec = "DISC", source = "Power Infusion" },
        { spellID = 15237, spec = "HOLY", source = "Holy Nova" },
    },
    defaultSpec     = "SHAD",
    defaultTiebreak = "SHAD",
})

function Priest:DetectSpec()
    local specKey, source = addon:DetectSpec(self)
    -- If Shadowform is currently active, prefer SHAD unless explicitly overridden
    local override = addon.charDb and addon.charDb.priestSpec
    if not override and Priest.IsShadowformActive() then
        return "SHAD", "Shadowform"
    end
    return specKey, source
end

function Priest:SetSpecOverride(specKey)
    if specKey == "auto" then
        addon.charDb.priestSpec = nil
        addon:InvalidateSpecTalentCache("PRIEST")
        return true
    end
    if specKey ~= "SHAD" and specKey ~= "DISC" and specKey ~= "HOLY" then return false end
    addon.charDb.priestSpec = specKey
    return true
end

-- ---------------------------------------------------------------------------
-- Healer mode preference (per character): "auto" | "always" | "off"
--   "auto"   = Holy/Discipline automatically heals in party/raid (or friendly target)
--   "always" = Always run healer triage + portrait highlight (even solo or Shadow)
--   "off"    = DPS only
-- ---------------------------------------------------------------------------
function Priest:GetHealMode()
    local m = addon.charDb and addon.charDb.priestHealMode
    if m == "always" or m == "off" or m == "auto" then return m end
    return "auto"
end

function Priest:SetHealMode(mode)
    if mode ~= "auto" and mode ~= "always" and mode ~= "off" then return false end
    if addon.charDb then addon.charDb.priestHealMode = mode end
    return true
end

function Priest:IsHealerModeActive(specKey)
    local mode = self:GetHealMode()
    if mode == "off" then return false end
    if mode == "always" then return true end
    -- "auto": activate healer mode when Holy or Discipline AND in a group/raid
    -- (or when explicitly targeting a friendly ally)
    if specKey ~= "HOLY" and specKey ~= "DISC" then return false end
    if addon.Healer and addon.Healer.IsInGroup() then return true end
    if UnitExists("target") and addon.Healer and addon.Healer.IsUnitFriendlyPlayer("target")
        and not (addon.UnitIsSame and addon.UnitIsSame("target", "player")) then
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Extra buffs toggles (per character)
-- ---------------------------------------------------------------------------
function Priest:IsExtraSuggestionEnabled(key)
    if not EXTRA_KEYS[key] then return false end
    local settings = addon.charDb and addon.charDb.priestExtras
    if type(settings) == "table" and settings[key] ~= nil then
        return settings[key] ~= false
    end
    if key == "shadow_protection" or key == "fear_ward" then return false end
    return true
end

function Priest:SetExtraSuggestionEnabled(key, enabled)
    if not EXTRA_KEYS[key] or type(enabled) ~= "boolean" or not addon.charDb then return false end
    addon.charDb.priestExtras = addon.charDb.priestExtras or {}
    addon.charDb.priestExtras[key] = enabled
    return true
end

-- ---------------------------------------------------------------------------
-- BuildEnv (uses Shared/Functions.lua globals)
-- ---------------------------------------------------------------------------
function Priest:BuildEnv(specKey)
    specKey = specKey or self:DetectSpec()
    local hasEnemy = addon.UnitTargetExistsAndAttackable and addon.UnitTargetExistsAndAttackable() or false
    local distance = addon.TargetDistance and addon:TargetDistance("target") or nil
    local melee = (distance ~= nil and distance <= 10)
        or (addon.IsInMeleeRange and addon:IsInMeleeRange("target") == true) or false
    local inCombat = playerInCombat()
    local enemies = countActiveEnemies(hasEnemy)
    local castingTarget = hasEnemy
        and (addon.IsTargetInterruptibleCasting and addon.IsTargetInterruptibleCasting("target") or false) or false

    local env = {
        spec                  = specKey,
        hasActiveEnemy        = hasEnemy,
        inCombat              = inCombat,
        isPvP                 = addon.IsPvPEnvironment and addon.IsPvPEnvironment() or false,
        myHealth              = playerHealthPct(),
        targetDistance        = distance,
        isMelee               = melee,
        tooCloseForRanged     = melee,
        targetInterruptible   = castingTarget,
        targetCasting         = castingTarget,
        isMoving              = playerMoving(),
        isAoE                 = enemies >= 2,
        enemies               = enemies,
        hasWand               = Priest.HasWandEquipped(),
        shadowformActive      = Priest.IsShadowformActive(),
        pwShieldActive        = Priest.IsBuffActive(17, "pw_shield", "PowerWordShield"),
        weakenedSoul          = Priest.HasWeakenedSoul(),
        innerFocusActive      = Priest.IsBuffActive(14751, "inner_focus"),
        powerInfusionActive   = Priest.IsBuffActive(10060, "power_infusion", "PowerInfusion"),
        vampiricEmbraceActive = Priest.IsBuffActive(15286, "vampiric_embrace", "VampiricEmbrace"),
        swPainActive          = hasEnemy and Priest.IsTargetDebuffActive(589, "sw_pain") or false,
        devouringPlagueActive = hasEnemy and Priest.IsTargetDebuffActive(2944, "devouring_plague") or false,
        vampiricTouchActive   = hasEnemy and Priest.IsTargetDebuffActive(34914, "vampiric_touch") or false,
        holyFireActive        = hasEnemy and Priest.IsTargetDebuffActive(14914, "holy_fire") or false,
    }

    if type(addon.PopulateEnvResources) == "function" then
        addon.PopulateEnvResources(env, "player")
    end
    if env.manaPct == nil then env.manaPct = 100 end

    -- Populate Healer triage snapshot when Healer mode is active
    local healerActive = self:IsHealerModeActive(specKey)
    env.healerActive = healerActive
    env.inGroup = addon.Healer and addon.Healer.IsInGroup() or false
    if healerActive and addon.Healer and type(addon.Healer.ScanGroup) == "function" then
        local probeHealID = Priest.ResolveID(2061) or Priest.ResolveID(2060)
            or Priest.ResolveID(2054) or Priest.ResolveID(2050) or 2061
        local probeResID = Priest.ResolveID(2006) or 2006
        local hs = addon.Healer.ScanGroup({
            inCombat            = inCombat,
            healSpellID         = probeHealID,
            resSpellID          = probeResID,
            canDispelMagic      = Priest.ResolveID(527) ~= nil,
            canDispelDisease    = (Priest.ResolveID(552) ~= nil or Priest.ResolveID(528) ~= nil),
            canResurrect        = Priest.ResolveID(2006) ~= nil,
            healThreshold       = 93,
            proactiveTankShield = (Priest.ResolveID(17) ~= nil),
            tankNeedsShieldFn   = function(u)
                return not Priest.HasUnitBuff(u, 17, "pw_shield", "PowerWordShield")
                    and not Priest.HasUnitWeakenedSoul(u)
            end,
        })
        env.healState                = hs
        env.inGroup                  = hs.inGroup
        env.playerHasAggro           = hs.playerHasAggro
        env.injuredCount82           = hs.injuredCount82
        env.injuredCount72           = hs.injuredCount72
        env.criticalCount55          = hs.criticalCount55
        env.recommendedHealUnit      = hs.recommendedUnit
        env.recommendedHealReason    = hs.recommendedReason
        env.recommendedHealColor     = hs.recommendedColor
        env.recommendedHealOutOfRange = hs.recommendedOutOfRange
        env.healUnit                 = hs.activeUnit
        env.healHP                   = hs.activeHP
        env.healIsSelf               = hs.activeIsSelf
        env.healIsDead               = hs.activeIsDead
        env.healIsTank               = hs.activeIsTank
        env.healInRange              = hs.activeInRange
        env.healInResRange           = hs.activeInResRange
        env.healDispelMagic          = hs.activeDispelMagic
        env.healDispelDisease        = hs.activeDispelDisease
        if hs.activeUnit and not hs.activeIsDead then
            env.healTargetShield         = Priest.HasUnitBuff(hs.activeUnit, 17, "pw_shield", "PowerWordShield")
            env.healTargetWeakenedSoul   = Priest.HasUnitWeakenedSoul(hs.activeUnit)
            env.healTargetRenew          = Priest.HasUnitBuff(hs.activeUnit, 139, "renew", "Renew")
            env.healTargetPoM            = Priest.HasUnitBuff(hs.activeUnit, 33076, "prayer_mending")
            env.healTargetAbolishDisease = Priest.HasUnitBuff(hs.activeUnit, 552, "abolish_disease")
        end
    end
    return env
end

-- ---------------------------------------------------------------------------
-- Suggestion & TryFlash plumbing (matches Core:RunDeclaredRotation contract)
-- ---------------------------------------------------------------------------
Priest.TickFlashUsed = nil
Priest.PendingSuggestion = nil
Priest.SpellName = Priest.SpellName
Priest.CheckCastable = addon.CheckCastable

function Priest:Suggest(spellID, color, asAdditional)
    if self.TickFlashUsed then return false end
    self.TickFlashUsed = true
    local knownID = Priest.ResolveID(spellID) or spellID
    local suggestion = { spellID = knownID, color = color or "Damage" }
    if asAdditional and self.PendingSuggestion then
        self.PendingSuggestion.additional = self.PendingSuggestion.additional or {}
        table.insert(self.PendingSuggestion.additional, suggestion)
    else
        self.PendingSuggestion = suggestion
    end
    return true
end

function Priest:TryFlash(spellID, color, condition, nodeName, env, opts, asAdditional)
    if self.TickFlashUsed then return false end
    opts = opts or {}
    local knownID = Priest.ResolveID(spellID)
    if not knownID then
        addon:DebugPrint("Priest", tostring(nodeName or spellID), "BLOQUEADO: spell desconhecida")
        return false
    end
    local spellName = Priest.SpellName(knownID)
    if not spellName then
        addon:DebugPrint("Priest", tostring(nodeName or spellID), "BLOQUEADO: nome indisponível")
        return false
    end
    if addon.IsPressSuppressed and addon:IsPressSuppressed(spellName) then
        addon:DebugPrint("Priest", tostring(nodeName or spellID), "BLOQUEADO: botão pressionado agora")
        return false
    end
    if type(condition) == "function" then
        local ok, passed = pcall(condition, env)
        if not ok or not passed then return false end
    end

    local dbg = {}
    local targetUnit = (opts.unitKey and env and env[opts.unitKey])
        or opts.unit
        or (opts.noEnemy and "player" or "target")
    local castable = addon.CheckCastable({
        SpellID           = knownID,
        SpellName         = spellName,
        EnemyTargetNeeded = opts.noEnemy ~= true,
        Unit              = targetUnit,
        NoRangeCheck      = (opts.noRangeCheck == true or opts.noRange == true),
        NotIfActive       = opts.notIfActive == true,
        Debug             = dbg,
    })
    if not castable then
        addon:DebugPrint("Priest", tostring(nodeName or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    addon:DebugPrint("Priest", tostring(nodeName or spellID), "OK (sugere)")
    return self:Suggest(knownID, color or "Damage", asAdditional)
end

-- ---------------------------------------------------------------------------
-- Extra self/party buffs (Fortitude, Inner Fire, Divine Spirit, Shadow Prot, Fear Ward)
-- ---------------------------------------------------------------------------
local function canSuggestSelfSpell(spellID)
    local knownID = Priest.ResolveID(spellID)
    if not knownID then return nil end
    local name = Priest.SpellName(knownID)
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

local function nextExtraSuggestion(env)
    if Priest:IsExtraSuggestionEnabled("inner_fire")
        and not Priest.IsBuffActive(588, "inner_fire", "InnerFire") then
        local sug = canSuggestSelfSpell(588)
        if sug then return sug end
    end

    -- Avoid suggesting long raid buffs mid-combat if in Shadowform or busy;
    -- out of combat (or if missing) suggest Fortitude / Spirit / Shadow Prot / Fear Ward.
    if not env.inCombat then
        if Priest:IsExtraSuggestionEnabled("fortitude")
            and not Priest.IsBuffActive(1243, "fortitude", "Fortitude") then
            local sug = canSuggestSelfSpell(1243)
            if sug then return sug end
        end

        if Priest:IsExtraSuggestionEnabled("divine_spirit")
            and not Priest.IsBuffActive(14752, "divine_spirit", "DivineSpirit") then
            local sug = canSuggestSelfSpell(14752)
            if sug then return sug end
        end

        if Priest:IsExtraSuggestionEnabled("shadow_protection")
            and not Priest.IsBuffActive(976, "shadow_protection", "ShadowProtection") then
            local sug = canSuggestSelfSpell(976)
            if sug then return sug end
        end

        if Priest:IsExtraSuggestionEnabled("fear_ward")
            and not Priest.IsBuffActive(6346, "fear_ward", "FearWard") then
            local sug = canSuggestSelfSpell(6346)
            if sug then return sug end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Main tick entry point
-- ---------------------------------------------------------------------------
function Priest:GetSuggestion()
    if addon.db and addon.db.priestEnabled == false then return nil end
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then return nil end

    self.PendingSuggestion = nil
    self.TickFlashUsed = nil
    pcall(addon.HookActionButtonPress)

    if type(IsMounted) == "function" and IsMounted() then return nil end
    if addon.CastingOrChanneling and addon.CastingOrChanneling(nil, "player") then return nil end

    local specKey = self:DetectSpec()
    local env = self:BuildEnv(specKey)

    local unitHighlight = nil
    if env.healerActive then
        -- 1) Highlight the #1 ally's portrait / party / raid frame when anyone needs help
        if env.recommendedHealUnit then
            unitHighlight = {
                kind   = "unitframe",
                unit   = env.recommendedHealUnit,
                color  = env.recommendedHealColor or "Defensive",
                urgent = (env.recommendedHealReason == "emergency"),
            }
        end

        -- 2) Run the dedicated Priest HEAL rotation (self-saves work immediately;
        --    targeted heals/shields/dispels/resurrection fire once the healer has the
        --    needing ally targeted AND in range!)
        addon:RunDeclaredRotation(self, "HEAL", env)

        -- 3) Quiet downtime fallback: when everyone is healthy (no ally needs attention),
        --    mana >= 50%, and the healer targets an enemy, help with Smite DPS!
        if not self.PendingSuggestion and not unitHighlight and env.hasActiveEnemy
            and (addon.HasManaPct(50)) then
            local dpsSpec = (specKey == "SHAD") and "SHAD" or ((specKey == "DISC") and "DISC" or "HOLY")
            addon:RunDeclaredRotation(self, dpsSpec, env)
        end
    else
        addon:RunDeclaredRotation(self, specKey, env)
    end

    local extra = nextExtraSuggestion(env)
    local rotation = self.PendingSuggestion

    -- Low-priority racial when rotation has nothing else to recommend
    if not rotation and not unitHighlight and addon.SuggestRacial and addon:SuggestRacial(self, env) then
        rotation = self.PendingSuggestion
    end

    -- In Healer mode, active healing / ally portrait highlight ALWAYS takes priority over Extra buffs
    if env.healerActive and (rotation or unitHighlight) then
        local primary = rotation or unitHighlight
        if rotation and unitHighlight then
            primary.additional = primary.additional or {}
            table.insert(primary.additional, unitHighlight)
        end
        if extra and env.recommendedHealReason ~= "emergency" then
            primary.additional = primary.additional or {}
            table.insert(primary.additional, extra)
        end
        return primary
    end

    if extra then
        if rotation then extra.additional = { rotation } end
        return extra
    end
    return rotation
end

-- ---------------------------------------------------------------------------
-- /cfa status & /cfa debug / /cfa priest diagnostics
-- ---------------------------------------------------------------------------
function Priest:GetStatus()
    local specKey, source = self:DetectSpec()
    local title = self.RotationSpecs[specKey] and self.RotationSpecs[specKey].title or specKey
    local enabled = not (addon.db and addon.db.priestEnabled == false)
    local healTag = self:IsHealerModeActive(specKey) and " [HEALER ATIVO]" or (" [heal=" .. self:GetHealMode() .. "]")
    return string.format("Priest — %s (%s)%s — %s", tostring(title), tostring(source),
        healTag, enabled and "ativo" or "desativado")
end

function Priest:DebugRotation()
    local specKey, source = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    local activeSpec = env.healerActive and "HEAL" or specKey

    print(string.format("|cff44ddff[CFA dbg]|r ===== RELATÓRIO DA ROTAÇÃO (Priest %s) =====",
        env.healerActive and "HEALER" or "DPS"))
    print(string.format(
        "|cff44ddff[CFA dbg]|r spec=%s (%s) | healMode=%s active=%s | inGroup=%s | enemy=%s | combat=%s | moving=%s | hp=%s | mana=%s(ok=%s)",
        tostring(specKey), tostring(source), self:GetHealMode(), tostring(env.healerActive),
        tostring(env.inGroup), tostring(env.hasActiveEnemy), tostring(env.inCombat),
        tostring(env.isMoving),
        env.myHealth and string.format("%.0f%%", env.myHealth) or "nil",
        env.manaPct and string.format("%.1f%%", env.manaPct) or "nil", tostring(env.manaReadable)))
    if env.healerActive then
        print(string.format(
            "|cff44ddff[CFA dbg]|r HEAL: rec=%s(%s,oor=%s) | active=%s(hp=%s,dead=%s,rng=%s,resRng=%s,tank=%s) | inj82=%d inj72=%d crit55=%d | shld=%s ws=%s ren=%s pom=%s",
            tostring(env.recommendedHealUnit or "-"), tostring(env.recommendedHealReason or "-"),
            tostring(env.recommendedHealOutOfRange), tostring(env.healUnit or "clique_no_aliado"),
            env.healHP and string.format("%.0f%%", env.healHP) or "-", tostring(env.healIsDead),
            tostring(env.healInRange), tostring(env.healInResRange), tostring(env.healIsTank),
            env.injuredCount82 or 0, env.injuredCount72 or 0, env.criticalCount55 or 0,
            tostring(env.healTargetShield), tostring(env.healTargetWeakenedSoul),
            tostring(env.healTargetRenew), tostring(env.healTargetPoM)))
    else
        print(string.format(
            "|cff44ddff[CFA dbg]|r shadowform=%s | shield=%s | weakSoul=%s | wand=%s | SW:P=%s | DP=%s | VT=%s | HF=%s",
            tostring(env.shadowformActive), tostring(env.pwShieldActive), tostring(env.weakenedSoul),
            tostring(env.hasWand), tostring(env.swPainActive), tostring(env.devouringPlagueActive),
            tostring(env.vampiricTouchActive), tostring(env.holyFireActive)))
    end

    local nodes = (type(self.GetEffectiveNodes) == "function" and self:GetEffectiveNodes(activeSpec))
        or (self.RotationSpecs[activeSpec] and self.RotationSpecs[activeSpec].nodes) or {}
    for _, node in ipairs(nodes) do
        local enabled = node.enabled ~= false
        local condOK = enabled and addon.NodeConditionPass(self, env, node, true)
        local knownID = Priest.ResolveID(node.spellID)
        local locName = knownID and Priest.SpellName(knownID) or nil
        local dbg = {}
        local castOK = false
        if condOK and knownID and locName then
            local opts = node.opts or {}
            local unit = (opts.unitKey and env[opts.unitKey]) or opts.unit or (opts.noEnemy and "player" or "target")
            castOK = addon.CheckCastable({
                SpellID           = knownID,
                SpellName         = locName,
                EnemyTargetNeeded = opts.noEnemy ~= true,
                Unit              = unit,
                NoRangeCheck      = (opts.noRangeCheck == true or opts.noRange == true),
                NotIfActive       = opts.notIfActive == true,
                Debug             = dbg,
            }) and true or false
        elseif not knownID then
            dbg.reason = "spell desconhecida"
        elseif not locName then
            dbg.reason = "sem nome localizado"
        end
        print(string.format("|cff44ddff[CFA dbg]|r %-24s en=%-5s cond=%-5s id=%-6s cast=%-5s %s",
            tostring(node.id), tostring(enabled), tostring(condOK),
            tostring(knownID or node.spellID), tostring(castOK), tostring(dbg.reason or "")))
    end
end

-- ---------------------------------------------------------------------------
-- Attach shared Rotation Editor (SHAD / DISC / HOLY + Extra tab)
-- ---------------------------------------------------------------------------
local function attachPriestEditor()
    if type(addon.RotationEditor) ~= "table"
        or type(addon.RotationEditor.Attach) ~= "function" then
        return false
    end

    local EXTRAS = {
        { key = "fortitude",         labelKey = "priest_buff_fortitude",         fallback = "Power Word: Fortitude" },
        { key = "inner_fire",        labelKey = "priest_buff_inner_fire",        fallback = "Inner Fire" },
        { key = "divine_spirit",     labelKey = "priest_buff_divine_spirit",     fallback = "Divine Spirit" },
        { key = "shadow_protection", labelKey = "priest_buff_shadow_protection", fallback = "Shadow Protection" },
        { key = "fear_ward",         labelKey = "priest_buff_fear_ward",         fallback = "Fear Ward" },
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

    return addon.RotationEditor.Attach(Priest, {
        storageKey = "priestRotation",
        title      = (L and L["priest_tab"]) or "Priest",
        specOrder  = { "SHAD", "DISC", "HOLY", "HEAL" },
        extraTabs  = {
            {
                key    = "EXTRA",
                label  = "Extra",
                render = renderExtraTab,
                hint   = (L and L["priest_extra_hint"]) or "",
            },
        },
    })
end

attachPriestEditor()

addon:RegisterModule("PRIEST", Priest)
