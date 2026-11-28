-- Combat Forever Assistant — Druid module: main rotation hub.
-- Isolated inside addon.modules.DRUID. Uses Core + Shared utilities globally:
--   * Global spec detection with Forever's real tree order: { "FER", "BAL", "REST" }
--   * Single Feral spec that adapts dynamically to Bear (Tank) or Cat (Melee DPS)
--   * Extra buff suggestions (Mark of the Wild / Thorns) via BuffLib + cast beliefs
--   * Shared rotation editor with BAL / FER / REST + Extra tabs
local _, addon = ...

local Druid = addon.modules.DRUID
local L = addon.L

local EXTRA_KEYS = { mark = true, thorns = true, aquatic = true }
local lastLandForm = nil
local preAquaticForm = nil
local restoreAfterWaterUntil = 0
local wasInAquaticForm = false

-- ---------------------------------------------------------------------------
-- Event tracker (beliefs & talent cache invalidation)
-- ---------------------------------------------------------------------------
local tracker = CreateFrame("Frame", "CombatForeverAssistantDruidTracker", UIParent)
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_TARGET_CHANGED")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(tracker.RegisterEvent, tracker, "TRAIT_CONFIG_UPDATED")

tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        Druid.OnTargetChanged()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        Druid.ClearAllBeliefs()
        preAquaticForm = nil
        wasInAquaticForm = false
        restoreAfterWaterUntil = 0
        addon:InvalidateSpecTalentCache("DRUID")
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then
        addon:InvalidateSpecTalentCache("DRUID")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            local sid = addon.SafeNumber(spellID, nil)
            if sid == 1066 then
                wasInAquaticForm = true
            elseif sid == 5487 or sid == 9634 or sid == 768 or sid == 24858 or sid == 24907 then
                -- Player manually shifted into a land form: restore is complete
                wasInAquaticForm = false
                preAquaticForm = nil
                restoreAfterWaterUntil = 0
            end
            pcall(Druid.RegisterCast, spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Global spec detection registration
-- Forever C_Traits treeIDs order for Druid is { "FER", "BAL", "REST" }
-- (verified in-game: Combate Feral = index 1).
-- ---------------------------------------------------------------------------
addon:RegisterSpecDetection(Druid, {
    charDbKey       = "druidSpec",
    treeOrder       = { "FER", "BAL", "REST" },
    validSpecs      = { "FER", "BAL", "REST" },
    signatures      = {
        { spellID = 24858, spec = "BAL",  source = "Moonkin Form" },
        { spellID = 18562, spec = "REST", source = "Swiftmend" },
        { spellID = 16979, spec = "FER",  source = "Feral Charge" },
        { spellID = 33876, spec = "FER",  source = "Mangle (Cat)" },
        { spellID = 33878, spec = "FER",  source = "Mangle (Bear)" },
    },
    defaultSpec     = "FER",
    defaultTiebreak = "FER",
})

function Druid:DetectSpec()
    return addon:DetectSpec(self)
end

function Druid:SetSpecOverride(specKey)
    if not addon.charDb then return false end
    if specKey == "auto" then
        addon.charDb.druidSpec = nil
        addon:InvalidateSpecTalentCache("DRUID")
        return true
    end
    if specKey ~= "BAL" and specKey ~= "FER" and specKey ~= "REST" then return false end
    addon.charDb.druidSpec = specKey
    return true
end

function Druid:IsExtraSuggestionEnabled(key)
    if not EXTRA_KEYS[key] then return false end
    local settings = addon.charDb and addon.charDb.druidExtras
    return type(settings) ~= "table" or settings[key] ~= false
end

function Druid:SetExtraSuggestionEnabled(key, enabled)
    if not EXTRA_KEYS[key] or type(enabled) ~= "boolean" or not addon.charDb then return false end
    if type(addon.charDb.druidExtras) ~= "table" then addon.charDb.druidExtras = {} end
    local settings = addon.charDb.druidExtras
    if enabled then
        settings[key] = nil
        if not next(settings) then addon.charDb.druidExtras = nil end
    else
        settings[key] = false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Env helpers (secret-safe, using global Shared helpers)
-- ---------------------------------------------------------------------------
local function readNum(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and addon.SafeNumber(v, nil) or nil
end

local function healthPct(unit)
    local cur = readNum(UnitHealth, unit)
    local max = readNum(UnitHealthMax, unit)
    if not cur or not max or max <= 0 then return nil end
    return math.max(0, math.min(100, math.floor((cur / max) * 100 + 0.5)))
end

local function powerPct(unit, powerType)
    local cur = readNum(UnitPower, unit, powerType)
    local max = readNum(UnitPowerMax, unit, powerType)
    if not cur or not max or max <= 0 then return nil end
    return math.max(0, math.min(100, math.floor((cur / max) * 100 + 0.5)))
end

local function inCombat(unit)
    if type(UnitAffectingCombat) == "function" then
        local ok, v = pcall(UnitAffectingCombat, unit or "player")
        if ok and not (_G.issecretvalue and issecretvalue(v)) then return v == true end
    end
    if type(InCombatLockdown) == "function" then
        local ok, v = pcall(InCombatLockdown)
        if ok and not (_G.issecretvalue and issecretvalue(v)) then return v == true end
    end
    return false
end

local function playerIsFriendlyTarget()
    if not UnitExists("target") or type(UnitIsFriend) ~= "function" then return false end
    local ok, friendly = pcall(UnitIsFriend, "player", "target")
    return ok and not (_G.issecretvalue and issecretvalue(friendly)) and friendly == true
end

local function chooseHealTarget()
    local selfHP = healthPct("player")
    local targetHP
    if playerIsFriendlyTarget() then targetHP = healthPct("target") end
    if targetHP and targetHP < 95 and (not selfHP or targetHP < selfHP) then
        return "target", targetHP
    end
    if selfHP and selfHP < 95 then return "player", selfHP end
    if targetHP and targetHP < 95 then return "target", targetHP end
    return "player", selfHP
end

local function countEnemies(hasEnemy, isMeleeForm)
    if type(addon.CountActiveEnemies) == "function" then
        return addon.CountActiveEnemies(hasEnemy, isMeleeForm and { meleeOnly = true } or nil)
    end
    return hasEnemy and 1 or 0
end

function Druid:BuildEnv(specKey)
    local hasEnemy = addon.UnitTargetExistsAndAttackable()
    local form = Druid.ActiveForm()
    local isCat = form == "CAT"
    local isBear = form == "BEAR"
    local isCaster = not isCat and not isBear

    local healUnit, healHealth = "player", nil
    local hasHoT = false
    if specKey == "REST" then
        healUnit, healHealth = chooseHealTarget()
        local rejuvName = addon.SpellName(774)
        local regrowthName = addon.SpellName(8936)
        if healUnit and addon.Compat and addon.Compat.CheckBuff then
            hasHoT = (rejuvName and addon.Compat.CheckBuff(rejuvName, healUnit))
                or (regrowthName and addon.Compat.CheckBuff(regrowthName, healUnit))
                or false
        end
    end

    local enemies = hasEnemy and countEnemies(hasEnemy, isBear or isCat) or 0
    local combo = 0
    if isCat and hasEnemy then
        combo = readNum(GetComboPoints, "player", "target")
        if combo == nil then combo = readNum(GetComboPoints, "player") end
        if combo == nil then combo = readNum(UnitPower, "player", 4) end
        combo = combo or 0
    end

    local inMelee = hasEnemy and (addon:IsInMeleeRange("target") == true) or false
    local targetCast = hasEnemy and addon.IsTargetInterruptibleCasting("target") or false
    local lostAggro = hasEnemy and (addon.PlayerLostAggro and addon.PlayerLostAggro("target") or false) or false

    local env = {
        spec = specKey,
        form = form,
        myHP = healthPct("player"),
        targetHP = hasEnemy and healthPct("target") or nil,
        manaPct = powerPct("player", 0),
        hasMana = (readNum(UnitPowerMax, "player", 0) or 0) > 0,
        rage = isBear and readNum(UnitPower, "player", 1) or nil,
        energy = isCat and readNum(UnitPower, "player", 3) or nil,
        combo = isCat and (combo or 0) or 0,
        hasActiveEnemy = hasEnemy,
        inCombat = inCombat("player"),
        isPvP = addon.IsPvPEnvironment(),
        targetDistance = hasEnemy and addon:TargetDistance("target") or nil,
        isMelee = inMelee,
        tooCloseForRanged = inMelee,
        enemyCount = enemies,
        isAoE = enemies >= 2,
        targetCasting = targetCast,
        targetInterruptible = targetCast,
        lostAggro = lostAggro,
        hasTargetTarget = hasEnemy and UnitExists("targettarget") and true or false,
        targetTargetIsPlayer = hasEnemy and UnitExists("targettarget") and addon.UnitIsSame("targettarget", "player") or
            false,
        healUnit = healUnit,
        healHealth = healHealth,
        emergencyHealing = specKey == "REST" and healHealth ~= nil and healHealth <= 35,
        hasHoT = hasHoT,

        -- Debuffs (API + slot belief) — only scan debuffs relevant to current form
        targetDebuffRake = hasEnemy and isCat and Druid.IsTargetDebuffActive(1822, "rake", true) or false,
        targetDebuffRip = hasEnemy and isCat and Druid.IsTargetDebuffActive(1079, "rip", true) or false,
        targetDebuffMoonfire = hasEnemy and isCaster and Druid.IsTargetDebuffActive(8921, "moonfire", true) or false,
        targetDebuffInsectSwarm = hasEnemy and isCaster and Druid.IsTargetDebuffActive(5570, "insect_swarm", true) or
            false,
        targetDebuffFaerieFire = hasEnemy and isCaster and Druid.IsTargetDebuffActive(770, "faerie_fire", false) or false,
        targetDebuffFaerieFireFeral = hasEnemy and (isCat or isBear) and
            Druid.IsTargetDebuffActive(16857, "faerie_fire_feral", false) or false,
        targetDebuffMangleCat = hasEnemy and isCat and Druid.IsTargetDebuffActive(33876, "mangle_cat", false) or false,
        targetDebuffMangleBear = hasEnemy and isBear and Druid.IsTargetDebuffActive(33878, "mangle_bear", false) or false,
        targetDebuffDemoralizingRoar = hasEnemy and isBear and Druid.IsTargetDebuffActive(99, "demoralizing_roar", false) or
            false,

        -- Player combat buffs
        tigerFuryActive = isCat and Druid.IsPlayerBuffActive(5217, "tiger_fury", "TigersFury") or false,
        barkskinActive = Druid.IsPlayerBuffActive(22812, "barkskin", "Barkskin"),
    }
    return env
end

-- ---------------------------------------------------------------------------
-- Suggestion plumbing (uses global Compat.HighestKnownSpellID + CheckCastable)
-- ---------------------------------------------------------------------------
Druid.TickFlashUsed = nil
Druid.PendingSuggestion = nil

function Druid:Suggest(spellID, color, asAdditional)
    if self.TickFlashUsed then return false end
    self.TickFlashUsed = true
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID
        and addon.Compat.HighestKnownSpellID(spellID) or spellID
    local suggestion = { spellID = knownID or spellID, color = color or "Utility" }
    if asAdditional and self.PendingSuggestion then
        self.PendingSuggestion.additional = self.PendingSuggestion.additional or {}
        table.insert(self.PendingSuggestion.additional, suggestion)
    else
        self.PendingSuggestion = suggestion
    end
    return true
end

function Druid:TryFlash(spellID, color, condition, name, env, opts, asAdditional)
    if self.TickFlashUsed then return false end
    opts = opts or {}
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID
        and addon.Compat.HighestKnownSpellID(spellID)
    if not knownID then return false end
    local localizedName = addon.SpellName(knownID)
    if not localizedName then return false end
    if addon:IsPressSuppressed(localizedName) then return false end
    if type(condition) == "function" then
        local ok, passed = pcall(condition, env)
        if not ok or not passed then return false end
    end

    local unit = opts.unit
    if opts.unitKey and type(env) == "table" then unit = env[opts.unitKey] end
    local dbg = {}
    local castable = addon.CheckCastable({
        SpellID = knownID,
        SpellName = localizedName,
        EnemyTargetNeeded = opts.noEnemy ~= true,
        Unit = unit or (opts.noEnemy and "player" or "target"),
        NoRangeCheck = (opts.noRange or opts.noRangeCheck) and true or nil,
        NotIfActive = opts.notIfActive and true or nil,
        Debug = dbg,
    })
    if not castable then
        addon:DebugPrint("Druid", tostring(name or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    return self:Suggest(knownID, color or "Damage", asAdditional)
end

-- ---------------------------------------------------------------------------
-- Automatic Aquatic Form (out of combat while swimming) + return to previous
-- land form upon leaving the water.
-- ---------------------------------------------------------------------------
local function playerIsSwimming()
    if type(IsSwimming) == "function" then
        local ok, v = pcall(IsSwimming)
        if ok and addon.SafeBoolean(v, false) == true then return true end
    end
    return false
end

local function formRestoreSpellID(formKey)
    if formKey == "BEAR" then
        return (addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(5487)) or 5487
    elseif formKey == "CAT" then
        return 768
    elseif formKey == "MOONKIN" then
        return 24858
    end
    -- HUMANOID / nil: clicking Aquatic Form (1066) again cancels Aquatic Form
    return 1066
end

local function aquaticFormSuggestion(env)
    if not Druid:IsExtraSuggestionEnabled("aquatic") then return nil end
    local swimming = playerIsSwimming()
    local form = env.form
    local now = (type(GetTime) == "function" and addon.SafeNumber(GetTime(), 0)) or 0

    if form == "AQUATIC" then
        wasInAquaticForm = true
        if preAquaticForm == nil then
            preAquaticForm = lastLandForm
        end
    end

    -- Swimming out of combat: suggest Aquatic Form (1066) and remember previous land form
    if swimming then
        restoreAfterWaterUntil = 0
        if env.inCombat then return nil end
        if form == "AQUATIC" then return nil end
        local aquaticID = addon.Compat and addon.Compat.HighestKnownSpellID
            and addon.Compat.HighestKnownSpellID(1066)
        if not aquaticID then return nil end
        local name = addon.SpellName(aquaticID)
        if name and addon.CheckCastable({
                SpellID = aquaticID, SpellName = name, EnemyTargetNeeded = false,
                Unit = "player", NoRangeCheck = true,
            }) then
            if preAquaticForm == nil then
                preAquaticForm = lastLandForm or form
            end
            return { spellID = aquaticID, color = "Utility" }
        end
        return nil
    end

    -- On land: if we were in Aquatic Form (WoW auto-cancels Aquatic Form to HUMANOID on land!),
    -- keep suggesting the previous land form (Bear / Cat / Moonkin) until restored or 15s pass.
    if wasInAquaticForm then
        if not preAquaticForm or preAquaticForm == "HUMANOID" then
            if form == "AQUATIC" and not env.inCombat then
                local name = addon.SpellName(1066)
                if name and addon.CheckCastable({
                        SpellID = 1066, SpellName = name, EnemyTargetNeeded = false,
                        Unit = "player", NoRangeCheck = true,
                    }) then
                    return { spellID = 1066, color = "Utility" }
                end
            end
            wasInAquaticForm = false
            preAquaticForm = nil
            restoreAfterWaterUntil = 0
        elseif form == preAquaticForm then
            -- Already back in the previous form!
            wasInAquaticForm = false
            preAquaticForm = nil
            restoreAfterWaterUntil = 0
            lastLandForm = form
            return nil
        else
            if restoreAfterWaterUntil == 0 then
                restoreAfterWaterUntil = now + 15
            end
            if now < restoreAfterWaterUntil then
                if env.inCombat then return nil end
                local restoreID = formRestoreSpellID(preAquaticForm)
                local knownID = (addon.Compat and addon.Compat.HighestKnownSpellID
                    and addon.Compat.HighestKnownSpellID(restoreID)) or restoreID
                local name = knownID and addon.SpellName(knownID)
                if knownID and name and addon.CheckCastable({
                        SpellID = knownID, SpellName = name, EnemyTargetNeeded = false,
                        Unit = "player", NoRangeCheck = true,
                    }) then
                    return { spellID = knownID, color = "Utility" }
                end
                return nil
            else
                -- Timed out (player chose to stay in Humanoid): clear restore state
                wasInAquaticForm = false
                preAquaticForm = nil
                restoreAfterWaterUntil = 0
            end
        end
    end

    -- Normal land tracking: remember the player's current land form
    if form == "BEAR" or form == "CAT" or form == "MOONKIN" or form == "HUMANOID" then
        lastLandForm = form
    end
    preAquaticForm = nil
    return nil
end

-- ---------------------------------------------------------------------------
-- Extra buff suggestions (Mark of the Wild / Thorns) — never forces dropping
-- Bear/Cat form while in combat.
-- ---------------------------------------------------------------------------
local function nextExtraSuggestion(env)
    local aquatic = aquaticFormSuggestion(env)
    if aquatic then return aquatic end
    if env.inCombat and (env.form == "CAT" or env.form == "BEAR") then
        return nil
    end
    if Druid:IsExtraSuggestionEnabled("mark")
        and not Druid.IsPlayerBuffActive(1126, "mark_of_the_wild", "MarkOfTheWild") then
        local id = addon.Compat and addon.Compat.HighestKnownSpellID(1126)
        local name = id and addon.SpellName(id)
        if id and name and addon.CheckCastable({
                SpellID = id, SpellName = name, EnemyTargetNeeded = false,
                Unit = "player", NoRangeCheck = true,
            }) then
            return { spellID = id, color = "Utility" }
        end
    end
    if Druid:IsExtraSuggestionEnabled("thorns")
        and not Druid.IsPlayerBuffActive(467, "thorns", "Thorns") then
        local id = addon.Compat and addon.Compat.HighestKnownSpellID(467)
        local name = id and addon.SpellName(id)
        if id and name and addon.CheckCastable({
                SpellID = id, SpellName = name, EnemyTargetNeeded = false,
                Unit = "player", NoRangeCheck = true,
            }) then
            return { spellID = id, color = "Utility" }
        end
    end
    return nil
end

function Druid:GetSuggestion()
    if addon.db and addon.db.druidEnabled == false then return nil end
    local _, playerClass = UnitClass("player")
    if playerClass ~= "DRUID" then return nil end
    pcall(addon.HookActionButtonPress)
    if type(IsMounted) == "function" and IsMounted() then return nil end
    if addon.CastingOrChanneling(nil, "player") then return nil end

    self.PendingSuggestion = nil
    self.TickFlashUsed = nil

    local specKey = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    addon:RunDeclaredRotation(self, specKey, env)

    local extra = nextExtraSuggestion(env)
    local rotation = self.PendingSuggestion
    if extra then
        if rotation and env.emergencyHealing then
            rotation.additional = { extra }
            return rotation
        end
        if rotation then extra.additional = { rotation } end
        return extra
    end
    if rotation then return rotation end

    if addon.SuggestRacial and addon:SuggestRacial(self, env) then
        return self.PendingSuggestion
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- /cfa status & /cfa debug
-- ---------------------------------------------------------------------------
function Druid:GetStatus()
    local specKey, source = self:DetectSpec()
    local form = Druid.ActiveForm()
    local title = self.RotationSpecs[specKey] and self.RotationSpecs[specKey].title or specKey
    return string.format("Druid — %s (%s) [forma: %s]", tostring(title), tostring(source), tostring(form))
end

function Druid:DebugRotation()
    local specKey, source = self:DetectSpec()
    local env = self:BuildEnv(specKey)
    print(string.format(
        "|cff44ddff[CFA dbg]|r Druid spec=%s (%s) | forma=%s | inimigo=%s | combate=%s | mana=%s | energia=%s | raiva=%s | cp=%s | enemies=%s aoe=%s | lostAggro=%s | castInt=%s",
        tostring(specKey), tostring(source), tostring(env.form), tostring(env.hasActiveEnemy),
        tostring(env.inCombat), tostring(env.manaPct), tostring(env.energy),
        tostring(env.rage), tostring(env.combo), tostring(env.enemyCount), tostring(env.isAoE),
        tostring(env.lostAggro), tostring(env.targetInterruptible)))
    local nodes = self:GetEffectiveNodes(specKey) or {}
    for _, node in ipairs(nodes) do
        local condOK = node.enabled ~= false and addon.NodeConditionPass(self, env, node, true)
        local knownID = addon.Compat and addon.Compat.HighestKnownSpellID(node.spellID)
        print(string.format("|cff44ddff[CFA dbg]|r %-22s cond=%-5s known=%s",
            tostring(node.id), tostring(condOK), tostring(knownID ~= nil)))
    end
end

-- ---------------------------------------------------------------------------
-- Attach shared rotation editor (3 specs: Balance, Feral, Restoration + Extra)
-- ---------------------------------------------------------------------------
if addon.RotationEditor and addon.RotationEditor.Attach then
    local EXTRAS = {
        { key = "mark",    labelKey = "druid_extra_mark",    fallback = "Mark of the Wild" },
        { key = "thorns",  labelKey = "druid_extra_thorns",  fallback = "Thorns" },
        { key = "aquatic", labelKey = "druid_extra_aquatic", fallback = "Aquatic Form (swimming)" },
    }
    local function renderExtraTab(scrollChild, mod, rows)
        local y = -4
        for _, entry in ipairs(EXTRAS) do
            local extraKey, labelKey, fallback = entry.key, entry.labelKey, entry.fallback
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(30)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)

            local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            check:SetChecked(mod:IsExtraSuggestionEnabled(extraKey))
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", check, "RIGHT", 4, 0)
            label:SetText((L and L[labelKey]) or fallback)
            check:SetScript("OnClick", function(self)
                mod:SetExtraSuggestionEnabled(extraKey, self:GetChecked() and true or false)
            end)
            rows[#rows + 1] = row
            y = y - 34
        end
        scrollChild:SetHeight(math.max(-y, 1))
    end

    addon.RotationEditor.Attach(Druid, {
        title = (L and L["druid_tab"]) or "Druid",
        storageKey = "druidRotation",
        specOrder = { "BAL", "FER", "REST" },
        extraTabs = {
            {
                key = "EXTRA",
                label = (L and L["rotation_editor_extra"]) or "Extra",
                render = renderExtraTab,
                hint = (L and L["druid_extra_hint"]) or "",
            },
        },
    })
end

addon:RegisterModule("DRUID", Druid)
