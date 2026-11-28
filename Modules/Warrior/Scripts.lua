-- Combat Forever Assistant — Warrior module: main rotation hub (Arms / Fury / Protection).
-- Uses global helpers from Shared/Functions.lua and Core.lua:
--   - Spec detection via Core:RegisterSpecDetection / Core:DetectSpec (ARMS / FURY / PROT)
--   - Rage & resources via addon.PopulateEnvResources / addon.HasRage / addon.HasResourceAtMost
--   - Castability & cooldowns via addon.CheckCastable / Core:RunDeclaredRotation
--   - Rotation editor via addon.RotationEditor.Attach (ARMS / FURY / PROT + Extra tab)
local _, addon = ...

local Warrior = addon.modules.WARRIOR
local L = addon.L

local EXTRA_KEYS = {
    battle_shout     = true,
    commanding_shout = true,
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

local function unitHealthPct(unit)
    if type(UnitExists) == "function" then
        local okE, ex = pcall(UnitExists, unit)
        if not okE or not ex then return nil end
    end
    local okC, cur = pcall(UnitHealth, unit)
    local okM, maxV = pcall(UnitHealthMax, unit)
    cur = okC and addon.SafeNumber(cur, nil) or nil
    maxV = okM and addon.SafeNumber(maxV, nil) or nil
    if cur and maxV and maxV > 0 then
        return math.max(0, math.min(100, (cur / maxV) * 100))
    end
    return nil
end

local function countActiveEnemies(hasEnemy)
    if type(addon.CountActiveEnemies) == "function" then
        return addon.CountActiveEnemies(hasEnemy, { meleeOnly = true })
    end
    return hasEnemy and 1 or 0
end

local function resolveMeleeRange(distance)
    if distance ~= nil then return distance <= 5 end
    if type(addon.IsInMeleeRange) == "function" then
        local r = addon:IsInMeleeRange("target")
        if r ~= nil then return r end
    end
    local hsID = Warrior.ResolveID(78) or 78
    if type(addon.IsSpellInRangeEx) == "function" then
        return addon:IsSpellInRangeEx(hsID, "target")
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Event tracker (beliefs, target changes, talent cache invalidation)
-- ---------------------------------------------------------------------------
local tracker = CreateFrame("Frame", "CombatForeverAssistantWarriorTracker", UIParent)
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("PLAYER_TARGET_CHANGED")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(tracker.RegisterEvent, tracker, "TRAIT_CONFIG_UPDATED")

tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        wipe(Warrior.BuffBeliefs)
        wipe(Warrior.TargetBeliefs)
        addon:InvalidateSpecTalentCache("WARRIOR")
    elseif event == "PLAYER_TARGET_CHANGED" then
        wipe(Warrior.TargetBeliefs)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        addon:InvalidateSpecTalentCache("WARRIOR")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            Warrior.RecordCast(spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Spec detection (registered in Core's shared pipeline)
-- Classic Warrior tree order: 1=Arms, 2=Fury, 3=Protection.
-- ---------------------------------------------------------------------------
addon:RegisterSpecDetection(Warrior, {
    charDbKey       = "warriorSpec",
    treeOrder       = { "ARMS", "FURY", "PROT" },
    validSpecs      = { "ARMS", "FURY", "PROT" },
    signatures      = {
        { spellID = 12294, spec = "ARMS", source = "Mortal Strike" },
        { spellID = 12328, spec = "ARMS", source = "Sweeping Strikes" },
        { spellID = 46924, spec = "ARMS", source = "Bladestorm" },
        { spellID = 23881, spec = "FURY", source = "Bloodthirst" },
        { spellID = 12292, spec = "FURY", source = "Death Wish" },
        { spellID = 23922, spec = "PROT", source = "Shield Slam" },
        { spellID = 20243, spec = "PROT", source = "Devastate" },
        { spellID = 12809, spec = "PROT", source = "Concussion Blow" },
        { spellID = 12975, spec = "PROT", source = "Last Stand" },
    },
    defaultSpec     = "ARMS",
    defaultTiebreak = "ARMS",
})

function Warrior:DetectSpec()
    return addon:DetectSpec(self)
end

function Warrior:SetSpecOverride(specKey)
    if specKey == "auto" then
        addon.charDb.warriorSpec = nil
        addon:InvalidateSpecTalentCache("WARRIOR")
        return true
    end
    if specKey ~= "ARMS" and specKey ~= "FURY" and specKey ~= "PROT" then return false end
    addon.charDb.warriorSpec = specKey
    return true
end

-- ---------------------------------------------------------------------------
-- Extra buffs toggles (Battle Shout / Commanding Shout)
-- ---------------------------------------------------------------------------
function Warrior:IsExtraSuggestionEnabled(key)
    if not EXTRA_KEYS[key] then return false end
    local settings = addon.charDb and addon.charDb.warriorExtras
    if type(settings) == "table" and settings[key] ~= nil then
        return settings[key] ~= false
    end
    if key == "commanding_shout" then return false end
    return true
end

function Warrior:SetExtraSuggestionEnabled(key, enabled)
    if not EXTRA_KEYS[key] or type(enabled) ~= "boolean" or not addon.charDb then return false end
    addon.charDb.warriorExtras = addon.charDb.warriorExtras or {}
    addon.charDb.warriorExtras[key] = enabled
    return true
end

-- ---------------------------------------------------------------------------
-- BuildEnv (uses Shared/Functions.lua globals)
-- ---------------------------------------------------------------------------
function Warrior:BuildEnv(specKey)
    specKey = specKey or self:DetectSpec()
    local hasEnemy = addon.UnitTargetExistsAndAttackable and addon.UnitTargetExistsAndAttackable() or false
    local distance = addon.TargetDistance and addon:TargetDistance("target") or nil
    local melee = resolveMeleeRange(distance)
    local inCombat = playerInCombat()
    local enemies = countActiveEnemies(hasEnemy)
    local castingTarget = hasEnemy
        and (addon.IsTargetInterruptibleCasting and addon.IsTargetInterruptibleCasting("target") or false) or false

    local hasTargetTarget = false
    if type(UnitExists) == "function" then
        local ok, ex = pcall(UnitExists, "targettarget")
        hasTargetTarget = ok and not (addon.IsSecretValue and addon.IsSecretValue(ex)) and ex == true
    end
    local targetTargetIsPlayer = hasTargetTarget and (addon.UnitIsSame and addon.UnitIsSame("targettarget", "player")) or false
    local lostAggro = hasEnemy and (addon.PlayerLostAggro and addon.PlayerLostAggro("target") or false) or false

    local env = {
        spec                  = specKey,
        stance                = Warrior.GetActiveStance(),
        hasShield             = Warrior.HasShieldEquipped(),
        hasActiveEnemy        = hasEnemy,
        inCombat              = inCombat,
        isPvP                 = addon.IsPvPEnvironment and addon.IsPvPEnvironment() or false,
        myHealth              = unitHealthPct("player"),
        targetHealth          = hasEnemy and unitHealthPct("target") or nil,
        targetDistance        = distance,
        isMelee               = melee,
        tooCloseForRanged     = (melee == true),
        targetInterruptible   = castingTarget,
        targetCasting         = castingTarget,
        isMoving              = playerMoving(),
        isAoE                 = enemies >= 2,
        enemies               = enemies,
        lostAggro             = lostAggro,
        hasTargetTarget       = hasTargetTarget,
        targetTargetIsPlayer  = targetTargetIsPlayer,
        battleShoutActive     = Warrior.IsBuffActive(6673, "battle_shout", "BattleShout"),
        commandingShoutActive = Warrior.IsBuffActive(469, "commanding_shout"),
        shieldBlockActive     = Warrior.IsBuffActive(2565, "shield_block"),
        deathWishActive       = Warrior.IsBuffActive(12292, "death_wish"),
        sweepingStrikesActive = Warrior.IsBuffActive(12328, "sweeping_strikes"),
        rendActive            = hasEnemy and Warrior.IsTargetDebuffActive(772, "rend", true) or false,
        demoShoutActive       = hasEnemy and Warrior.IsTargetDebuffActive(1160, "demo_shout", false) or false,
        thunderClapActive     = hasEnemy and Warrior.IsTargetDebuffActive(6343, "thunder_clap", false) or false,
        hamstringActive       = hasEnemy and Warrior.IsTargetDebuffActive(1715, "hamstring", false) or false,
        sunderStacks          = hasEnemy and Warrior.GetSunderStacks() or 0,
    }

    if type(addon.PopulateEnvResources) == "function" then
        addon.PopulateEnvResources(env, "player")
    end
    return env
end

-- ---------------------------------------------------------------------------
-- Suggestion & TryFlash plumbing (matches Core:RunDeclaredRotation contract)
-- ---------------------------------------------------------------------------
Warrior.TickFlashUsed = nil
Warrior.PendingSuggestion = nil
Warrior.SpellName = Warrior.SpellName
Warrior.CheckCastable = addon.CheckCastable

function Warrior:Suggest(spellID, color, asAdditional)
    if self.TickFlashUsed then return false end
    self.TickFlashUsed = true
    local knownID = Warrior.ResolveID(spellID) or spellID
    local suggestion = { spellID = knownID, color = color or "Damage" }
    if asAdditional and self.PendingSuggestion then
        self.PendingSuggestion.additional = self.PendingSuggestion.additional or {}
        table.insert(self.PendingSuggestion.additional, suggestion)
    else
        self.PendingSuggestion = suggestion
    end
    return true
end

function Warrior:TryFlash(spellID, color, condition, nodeName, env, opts, asAdditional)
    if self.TickFlashUsed then return false end
    opts = opts or {}
    local knownID = Warrior.ResolveID(spellID)
    if not knownID then
        addon:DebugPrint("Warrior", tostring(nodeName or spellID), "BLOQUEADO: spell desconhecida")
        return false
    end
    local spellName = Warrior.SpellName(knownID)
    if not spellName then
        addon:DebugPrint("Warrior", tostring(nodeName or spellID), "BLOQUEADO: nome indisponível")
        return false
    end
    if addon.IsPressSuppressed and addon:IsPressSuppressed(spellName) then
        addon:DebugPrint("Warrior", tostring(nodeName or spellID), "BLOQUEADO: botão pressionado agora")
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
        addon:DebugPrint("Warrior", tostring(nodeName or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    addon:DebugPrint("Warrior", tostring(nodeName or spellID), "OK (sugere)")
    return self:Suggest(knownID, color or "Damage", asAdditional)
end

-- ---------------------------------------------------------------------------
-- Extra buffs (Battle Shout / Commanding Shout — require 10 rage!)
-- ---------------------------------------------------------------------------
local function canSuggestShout(spellID)
    local knownID = Warrior.ResolveID(spellID)
    if not knownID then return nil end
    if not addon.HasRage(10, knownID) then return nil end
    local name = Warrior.SpellName(knownID)
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
    -- Shouts only replace each other; suggest when missing and player has >= 10 rage.
    if env.battleShoutActive or env.commandingShoutActive then return nil end
    if Warrior:IsExtraSuggestionEnabled("commanding_shout") and env.spec == "PROT" then
        local sug = canSuggestShout(469)
        if sug then return sug end
    end
    if Warrior:IsExtraSuggestionEnabled("battle_shout") then
        local sug = canSuggestShout(6673)
        if sug then return sug end
    end
    if Warrior:IsExtraSuggestionEnabled("commanding_shout") then
        local sug = canSuggestShout(469)
        if sug then return sug end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Main tick entry point
-- ---------------------------------------------------------------------------
function Warrior:GetSuggestion()
    if addon.db and addon.db.warriorEnabled == false then return nil end
    local _, playerClass = UnitClass("player")
    if playerClass ~= "WARRIOR" then return nil end

    self.PendingSuggestion = nil
    self.TickFlashUsed = nil
    pcall(addon.HookActionButtonPress)

    if type(IsMounted) == "function" and IsMounted() then return nil end
    if addon.CastingOrChanneling and addon.CastingOrChanneling(nil, "player") then return nil end

    local specKey = self:DetectSpec()
    local env = self:BuildEnv(specKey)

    addon:RunDeclaredRotation(self, specKey, env)

    local extra = nextExtraSuggestion(env)
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
-- /cfa status & /cfa debug / /cfa warrior diagnostics
-- ---------------------------------------------------------------------------
function Warrior:GetStatus()
    local specKey, source = self:DetectSpec()
    local title = self.RotationSpecs[specKey] and self.RotationSpecs[specKey].title or specKey
    local enabled = not (addon.db and addon.db.warriorEnabled == false)
    return string.format("Warrior — %s (%s) — %s", tostring(title), tostring(source),
        enabled and "ativo" or "desativado")
end

function Warrior:DebugRotation()
    local specKey, source = self:DetectSpec()
    local env = self:BuildEnv(specKey)

    print("|cff44ddff[CFA dbg]|r ===== RELATÓRIO DA ROTAÇÃO (Warrior) =====")
    print(string.format(
        "|cff44ddff[CFA dbg]|r spec=%s (%s) | stance=%s | shield=%s | enemy=%s | combat=%s | melee=%s | AoE=%s(%d)",
        tostring(specKey), tostring(source), tostring(env.stance), tostring(env.hasShield),
        tostring(env.hasActiveEnemy), tostring(env.inCombat), tostring(env.isMelee),
        tostring(env.isAoE), env.enemies or 0))
    print(string.format(
        "|cff44ddff[CFA dbg]|r rage=%s(ok=%s) | hp=%s | tgtHP=%s | bShout=%s | sBlock=%s | rend=%s | demo=%s | tc=%s | sunder=%d",
        tostring(env.rage), tostring(env.rageReadable),
        env.myHealth and string.format("%.0f%%", env.myHealth) or "nil",
        env.targetHealth and string.format("%.0f%%", env.targetHealth) or "nil",
        tostring(env.battleShoutActive), tostring(env.shieldBlockActive),
        tostring(env.rendActive), tostring(env.demoShoutActive),
        tostring(env.thunderClapActive), env.sunderStacks or 0))

    local nodes = (type(self.GetEffectiveNodes) == "function" and self:GetEffectiveNodes(specKey))
        or (self.RotationSpecs[specKey] and self.RotationSpecs[specKey].nodes) or {}
    for _, node in ipairs(nodes) do
        local enabled = node.enabled ~= false
        local condOK = enabled and addon.NodeConditionPass(self, env, node, true)
        local knownID = Warrior.ResolveID(node.spellID)
        local locName = knownID and Warrior.SpellName(knownID) or nil
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
        print(string.format("|cff44ddff[CFA dbg]|r %-24s en=%-5s cond=%-5s id=%-6s cast=%-5s %s",
            tostring(node.id), tostring(enabled), tostring(condOK),
            tostring(knownID or node.spellID), tostring(castOK), tostring(dbg.reason or "")))
    end
end

-- ---------------------------------------------------------------------------
-- Attach shared Rotation Editor (ARMS / FURY / PROT + Extra tab)
-- ---------------------------------------------------------------------------
local function attachWarriorEditor()
    if type(addon.RotationEditor) ~= "table"
        or type(addon.RotationEditor.Attach) ~= "function" then
        return false
    end

    local EXTRAS = {
        { key = "battle_shout",     labelKey = "warrior_buff_battle_shout",     fallback = "Battle Shout" },
        { key = "commanding_shout", labelKey = "warrior_buff_commanding_shout", fallback = "Commanding Shout" },
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

    return addon.RotationEditor.Attach(Warrior, {
        storageKey = "warriorRotation",
        title      = (L and L["warrior_tab"]) or "Warrior",
        specOrder  = { "ARMS", "FURY", "PROT" },
        extraTabs  = {
            {
                key    = "EXTRA",
                label  = "Extra",
                render = renderExtraTab,
                hint   = (L and L["warrior_extra_hint"]) or "",
            },
        },
    })
end

attachWarriorEditor()

addon:RegisterModule("WARRIOR", Warrior)
