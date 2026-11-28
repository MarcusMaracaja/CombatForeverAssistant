-- Combat Forever Assistant — Hunter module: main rotation hub.
-- Isolated inside addon.modules.HUNTER. Builds env, delegates spec detection
-- to Core, runs the declared spec rotation, manages Aspects/Pet/Mark/Concussive,
-- and attaches the shared rotation editor with Hunter's Extra tab.
local _, addon = ...

local Hunter = addon.modules.HUNTER
local L = addon.L

-- ---------------------------------------------------------------------------
-- Tracking frame (beliefs & pet death tracking)
-- ---------------------------------------------------------------------------
local trackerFrame = CreateFrame("Frame", "CombatForeverAssistantHunterTracker", UIParent)
trackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
trackerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
trackerFrame:RegisterEvent("UNIT_PET")
trackerFrame:RegisterEvent("UNIT_DIED")
trackerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

trackerFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        Hunter.OnTargetChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- NOTE: addon.charDb.aspectBelief is intentionally kept (persistent
        -- per character); aspects don't expire on /reload, only on death or recast.
        Hunter.AspectBelief = nil
        Hunter.MarkBelief = { slot = 0, active = false }
        Hunter.SerpentStingBelief = { slot = 0, applied = false, expires = 0 }
        Hunter.WingClipBelief = { slot = 0, applied = false, expires = 0 }
        Hunter.PET_IS_DEAD = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        Hunter.PET_IS_DEAD = false
    elseif event == "UNIT_PET" then
        local unit = ...
        if type(unit) == "string" and addon.UnitIsSame(unit, "player") then
            local ok2, exists = pcall(UnitExists, "pet")
            local ok3, dead = pcall(UnitIsDeadOrGhost, "pet")
            Hunter.PET_IS_DEAD = ok2 and exists and ok3 and dead or false
        end
    elseif event == "UNIT_DIED" then
        local unit = ...
        if type(unit) == "string" then
            if addon.UnitIsSame(unit, "pet") then
                Hunter.PET_IS_DEAD = true
            end
            if addon.UnitIsSame(unit, "player") and addon.charDb then
                addon.charDb.aspectBelief = nil
                Hunter.AspectBelief = nil
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if type(spellID) == "number" and not (_G.issecretvalue and issecretvalue(spellID))
            and addon.Compat and addon.Compat.SpellInfoByID then
            local name = addon.Compat.SpellInfoByID(spellID)
            if type(name) ~= "string" or (_G.issecretvalue and issecretvalue(name)) then
                name = nil
            end
            pcall(Hunter.RegisterCast, name, spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Env helpers
-- ---------------------------------------------------------------------------
local function countEnemiesInCombat(hasEnemy)
    if type(addon.CountActiveEnemies) == "function" then
        return addon.CountActiveEnemies(hasEnemy)
    end
    return hasEnemy and 1 or 0
end

local function safePct(cur, max)
    local c = addon.SafeNumber(cur, nil)
    local m = addon.SafeNumber(max, nil)
    if c and m and m > 0 then
        return math.floor(((c / m) * 100) + 0.5)
    end
    return 100
end

local function safePower(unit, ptype)
    if type(UnitPower) ~= "function" then return 0 end
    local ok, v = pcall(UnitPower, unit, ptype)
    if ok then return addon.SafeNumber(v, 0) or 0 end
    return 0
end

local function isCastingSomething(unit)
    if type(UnitCastingInfo) == "function" then
        local ok, n = pcall(UnitCastingInfo, unit)
        if ok and n then
            if _G.issecretvalue and issecretvalue(n) then return false end
            return true
        end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, n = pcall(UnitChannelInfo, unit)
        if ok and n then
            if _G.issecretvalue and issecretvalue(n) then return false end
            return true
        end
    end
    return false
end

local function combatOf(unit)
    if type(UnitAffectingCombat) ~= "function" then return false end
    local ok, v = pcall(UnitAffectingCombat, unit)
    if not ok then return true end
    if _G.issecretvalue and issecretvalue(v) then return true end
    return v and true or false
end

local function groupCount(fn)
    if type(fn) ~= "function" then return 0 end
    local ok, n = pcall(fn)
    if ok and tonumber(n) then return tonumber(n) end
    return 0
end

local function isGroupInCombat()
    if combatOf("player") then return true end
    for i = 1, groupCount(GetNumPartyMembers) do
        if combatOf("party" .. i) then return true end
    end
    for i = 1, groupCount(GetNumRaidMembers) do
        if combatOf("raid" .. i) then return true end
    end
    return false
end

function Hunter:BuildEnv()
    local env = {}
    env.myHP = safePct(UnitHealth and UnitHealth("player"), UnitHealthMax and UnitHealthMax("player"))
    if type(addon.PopulateEnvResources) == "function" then
        addon.PopulateEnvResources(env, "player")
    end
    -- Fallback numérico para compatibilidade (manaReadable/resources.mana.readable preserva o estado real)
    if env.manaPct == nil then
        env.manaPct = safePct(UnitPower and UnitPower("player"), UnitPowerMax and UnitPowerMax("player"))
    else
        env.manaPct = math.floor(env.manaPct + 0.5)
    end
    env.targetCasting = addon.IsTargetInterruptibleCasting and addon.IsTargetInterruptibleCasting("target")
        or isCastingSomething("target")
    env.hasActiveEnemy = addon.UnitTargetExistsAndAttackable()
    env.isPvP = addon.IsPvPEnvironment()
    env.isMelee = false
    env.tooCloseForRanged = false
    env.isDeadZone = false
    env.isRangedConfirmed = false
    env.targetDistance = nil

    -- Zona morta do Hunter: melee <= 5 yd; ranged inviável <= 10 yd; dead zone = 5 < d <= 10 yd.
    if UnitExists("target") then
        local dist = addon:TargetDistance("target")
        if dist then
            env.targetDistance = dist
            env.isMelee = dist <= 5
            env.tooCloseForRanged = dist <= 10
            env.isDeadZone = (dist > 5 and dist <= 10)
            env.isRangedConfirmed = dist > 10
        else
            local melee = addon:IsInMeleeRange("target")
            local deadZone = addon:IsInDeadZoneRange("target")
            if melee == true then
                env.targetDistance = 5
                env.isMelee = true
                env.tooCloseForRanged = true
                env.isDeadZone = false
            elseif deadZone == true then
                env.targetDistance = 8
                env.isMelee = false
                env.tooCloseForRanged = true
                env.isDeadZone = true
            elseif melee == false then
                env.targetDistance = 35
                env.isMelee = false
                env.tooCloseForRanged = false
                env.isDeadZone = false
                env.isRangedConfirmed = true
            else
                env.targetDistance = 100
                env.isMelee = false
                env.tooCloseForRanged = false
                env.isDeadZone = false
            end
        end
    else
        env.targetDistance = 100
        env.tooCloseForRanged = false
        env.isMelee = false
        env.isDeadZone = false
    end

    env.petAlive = (type(UnitExists) == "function" and UnitExists("pet")
        and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("pet"))) and true or false
    env.inCombat = combatOf("player")
    env.isAoE = countEnemiesInCombat(env.hasActiveEnemy) >= 2
    return env
end

-- ---------------------------------------------------------------------------
-- Spec detection: registered in Core's shared pipeline (isolated from addon).
-- ---------------------------------------------------------------------------
addon:RegisterSpecDetection(Hunter, {
    charDbKey       = "hunterSpec",
    treeOrder       = { "SV", "MM", "BM" },
    validSpecs      = { "SV", "MM", "BM" },
    signatures      = {
        { spellID = 19574,   spec = "BM", source = "Bestial Wrath" },
        { spellID = 19306,   spec = "SV", source = "Counterattack" },
        { spellID = 1310786, spec = "MM", source = "Sniper Shot" },
    },
    defaultSpec     = "SV",
    defaultTiebreak = "SV",
})

function Hunter:DetectSpec()
    return addon:DetectSpec(self)
end

-- ---------------------------------------------------------------------------
-- Aspects (global Hunter management, Extra tab toggles)
-- ---------------------------------------------------------------------------
local function aspectCastable(id)
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID
        and addon.Compat.HighestKnownSpellID(id) or id
    local spellName = addon.SpellName(knownID)
    if not spellName then return nil, nil, "sem nome" end
    local dbg = {}
    local ok = addon.CheckCastable({
        SpellName = spellName,
        SpellID = knownID,
        EnemyTargetNeeded = false,
        NoRangeCheck = true,
        Debug = dbg,
    })
    return ok, knownID, dbg.reason
end

local function suggestAspect(id, color, label)
    local ok, knownID, reason = aspectCastable(id)
    addon:DebugPrint("aspecto", label, "castable=", tostring(ok), "motivo=", tostring(reason))
    if not ok then return nil end
    return { spellID = knownID, color = color }
end

local ASPECT_SUGGESTIONS = {
    Cheetah = true,
    Pack = true,
    Monkey = true,
    Beast = true,
    Hawk = true,
}

function Hunter:IsAspectSuggestionEnabled(key)
    if not ASPECT_SUGGESTIONS[key] then return false end
    local settings = addon.charDb and addon.charDb.hunterAspectSuggestions
    return type(settings) ~= "table" or settings[key] ~= false
end

function Hunter:SetAspectSuggestionEnabled(key, enabled)
    if not ASPECT_SUGGESTIONS[key] or not addon.charDb then return false end
    addon.charDb.hunterAspectSuggestions = addon.charDb.hunterAspectSuggestions or {}
    local settings = addon.charDb.hunterAspectSuggestions
    if enabled then
        settings[key] = nil
        if not next(settings) then addon.charDb.hunterAspectSuggestions = nil end
    else
        settings[key] = false
    end
    return true
end

function Hunter:ManageAspects(env)
    -- Out of combat: Cheetah solo / Pack in group (never in PvP/arena)
    if not isGroupInCombat() then
        if not addon.IsPvPEnvironment(env) then
            local numParty = groupCount(GetNumPartyMembers)
            local numRaid = groupCount(GetNumRaidMembers)
            if numParty > 0 or numRaid > 1 then
                if self:IsAspectSuggestionEnabled("Pack") and not Hunter.IsAspectOfPackActive() then
                    return suggestAspect(13159, "Utility", "Pack")
                end
            else
                if self:IsAspectSuggestionEnabled("Cheetah") and not Hunter.IsAspectOfCheetahActive() then
                    return suggestAspect(5118, "Utility", "Cheetah")
                end
            end
        end
        return nil
    end
    -- In combat:
    -- 1) Perto/melee com alvo inimigo -> Macaco (sendo atacado) ou Fera (não sendo atacado)
    local beingFocused = env.hasActiveEnemy and addon.UnitIsSame("targettarget", "player") or false
    if env.hasActiveEnemy and env.tooCloseForRanged then
        if beingFocused then
            if self:IsAspectSuggestionEnabled("Monkey") and not Hunter.IsAspectOfMonkeyActive() then
                return suggestAspect(13163, "Utility", "Monkey")
            end
        else
            if self:IsAspectSuggestionEnabled("Beast") and not Hunter.IsAspectOfBeastActive() then
                return suggestAspect(13161, "Utility", "Beast")
            end
        end
        return nil
    end

    local dangerousAspect = Hunter.IsAspectOfCheetahActive() or Hunter.IsAspectOfPackActive()

    -- 2) Em combate + tenho alvo + alvo está longe -> Aspecto do Falcão/Águia
    if env.hasActiveEnemy and not env.tooCloseForRanged then
        if self:IsAspectSuggestionEnabled("Hawk") and not Hunter.IsAspectOfHawkActive() then
            return suggestAspect(13165, "Utility", "Hawk")
        end
        return nil
    end

    -- 3) Em combate sem alvo inimigo:
    --    fica no aspecto atual se já estiver em um aspecto seguro de combate;
    --    se estiver sem aspecto ou em Guepardo/Matilha, muda para Macaco (atacado) ou Fera (não atacado).
    if dangerousAspect or not Hunter.IsAspectActive() then
        if beingFocused then
            if self:IsAspectSuggestionEnabled("Monkey") and not Hunter.IsAspectOfMonkeyActive() then
                return suggestAspect(13163, "Utility", "Monkey")
            end
        else
            if self:IsAspectSuggestionEnabled("Beast") and not Hunter.IsAspectOfBeastActive() then
                return suggestAspect(13161, "Utility", "Beast")
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Per-character rotation overrides (preserves legacy charDb.hunterRotation &
-- charDb.hunterOrder schema so existing saved Hunter customizations survive).
-- ---------------------------------------------------------------------------
local function deepCopyNode(n)
    local out = {}
    for k, v in pairs(n) do
        if k == "filter" and type(v) == "table" then
            local f = {}
            for fk, fv in pairs(v) do f[fk] = fv end
            out.filter = f
        else
            out[k] = v
        end
    end
    return out
end

local function rotationOverrides(specKey)
    return addon.charDb and addon.charDb.hunterRotation and addon.charDb.hunterRotation[specKey] or nil
end

local function rotationOrder(specKey)
    return addon.charDb and addon.charDb.hunterOrder and addon.charDb.hunterOrder[specKey] or nil
end

function Hunter:GetNodeOrder(specKey)
    local order = rotationOrder(specKey)
    if type(order) == "table" then return order end
    local spec = self.RotationSpecs and self.RotationSpecs[specKey]
    if not spec then return nil end
    local out = {}
    for _, n in ipairs(spec.nodes) do out[#out + 1] = n.id end
    return out
end

function Hunter:SetNodeOrder(specKey, order)
    if not addon.charDb then return end
    addon.charDb.hunterOrder = addon.charDb.hunterOrder or {}
    addon.charDb.hunterOrder[specKey] = order
end

function Hunter:MoveNode(specKey, nodeId, delta)
    local unpackFn = table.unpack or unpack
    local order = self:GetNodeOrder(specKey)
    if not order then return false end
    order = unpackFn and { unpackFn(order) } or { unpack(order) }
    local idx
    for i, id in ipairs(order) do if id == nodeId then idx = i break end end
    if not idx then return false end
    local j = idx + delta
    if j < 1 or j > #order then return false end
    order[idx], order[j] = order[j], order[idx]
    self:SetNodeOrder(specKey, order)
    return true
end

function Hunter:GetEffectiveNodes(specKey)
    local spec = self.RotationSpecs and self.RotationSpecs[specKey]
    if not spec then return nil end
    local ov = rotationOverrides(specKey)
    local out = {}
    local defaultIndex = {}
    for i, base in ipairs(spec.nodes) do
        defaultIndex[base.id] = i
        local o = ov and ov[base.id]
        if o then
            local n = deepCopyNode(base)
            if o.enabled ~= nil then n.enabled = o.enabled end
            if o.condition ~= nil then n.condition = o.condition end
            if o.filter ~= nil then
                if type(o.filter) == "table" and next(o.filter) then
                    n.filter = o.filter
                else
                    n.filter = nil
                end
            end
            out[#out + 1] = n
        else
            out[#out + 1] = base
        end
    end
    local custom = rotationOrder(specKey)
    if type(custom) == "table" and #custom > 0 then
        local pos = {}
        for i, id in ipairs(custom) do pos[id] = i end
        table.sort(out, function(a, b)
            local pa, pb = pos[a.id], pos[b.id]
            if pa and pb then return pa < pb end
            if pa then return true end
            if pb then return false end
            return (defaultIndex[a.id] or 0) < (defaultIndex[b.id] or 0)
        end)
    end
    return out
end

function Hunter:SetNodeOverride(specKey, nodeId, key, value)
    local charDb = addon.charDb
    if not charDb then return end
    charDb.hunterRotation = charDb.hunterRotation or {}
    charDb.hunterRotation[specKey] = charDb.hunterRotation[specKey] or {}
    local ov = charDb.hunterRotation[specKey][nodeId]
    if value == nil then
        if ov then
            ov[key] = nil
            if not next(ov) then charDb.hunterRotation[specKey][nodeId] = nil end
            if not next(charDb.hunterRotation[specKey]) then charDb.hunterRotation[specKey] = nil end
        end
        return
    end
    if not ov then ov = {}; charDb.hunterRotation[specKey][nodeId] = ov end
    ov[key] = value
end

function Hunter:ResetRotationOverrides(specKey)
    if addon.charDb then
        if addon.charDb.hunterRotation then addon.charDb.hunterRotation[specKey] = nil end
        if addon.charDb.hunterOrder then addon.charDb.hunterOrder[specKey] = nil end
    end
end

function Hunter.GetRotationDisabled(specKey)
    local ov = rotationOverrides(specKey)
    if not ov then return nil end
    local m = {}
    for id, o in pairs(ov) do
        if o.enabled == false then m[id] = true end
    end
    return m
end

-- ---------------------------------------------------------------------------
-- Suggestion plumbing
-- ---------------------------------------------------------------------------
Hunter.TickFlashUsed = nil
Hunter.PendingSuggestion = nil
Hunter.PendingAspectSuggestion = nil

function Hunter:Suggest(spellID, color, asAdditional)
    if self.TickFlashUsed then return false end
    self.TickFlashUsed = true
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID
        and addon.Compat.HighestKnownSpellID(spellID) or spellID
    local suggestion = { spellID = knownID or spellID, color = color or "Utility" }
    if asAdditional and self.PendingSuggestion then
        self.PendingSuggestion.additional = self.PendingSuggestion.additional or {}
        table.insert(self.PendingSuggestion.additional, suggestion)
    else
        local aspect = self.PendingAspectSuggestion
        if aspect and aspect.spellID ~= suggestion.spellID then
            aspect.additional = { suggestion }
            self.PendingSuggestion = aspect
        else
            self.PendingSuggestion = suggestion
        end
    end
    return true
end

function Hunter:TryFlash(spellID, color, condition, name, env, opts, asAdditional)
    if self.TickFlashUsed then return false end
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID
        and addon.Compat.HighestKnownSpellID(spellID) or spellID
    local spellName = addon.SpellName(knownID or spellID)
    if not spellName then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: nome da spell não resolvido")
        return false
    end
    if knownID == 3045 and Hunter.IsRapidFireSuppressed() then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: Rapid Fire ativo/em cooldown")
        return false
    end
    if addon:IsPressSuppressed(spellName) then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: botão pressionado agora")
        return false
    end
    if type(condition) == "function" then
        local ok, res = pcall(condition, env)
        if not ok or not res then
            addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: condição")
            return false
        end
    end
    local dbg = {}
    local castable = addon.CheckCastable({
        SpellName = spellName,
        SpellID = knownID or spellID,
        EnemyTargetNeeded = not (opts and opts.noEnemy),
        NoRangeCheck = (opts and opts.noRange) and true or nil,
        NotIfActive = (opts and opts.notIfActive) and true or nil,
        Debug = dbg,
    })
    self.LastCastDebug = dbg
    if not castable then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    addon:DebugPrint("tryflash", tostring(name or spellID), "OK (sugere)")
    return self:Suggest(knownID or spellID, color, asAdditional)
end

function Hunter:GetSuggestion()
    local _, myClass = UnitClass("player")
    if myClass ~= "HUNTER" then return nil end
    if addon.db and addon.db.hunterEnabled == false then return nil end
    self.TickFlashUsed = nil
    self.PendingSuggestion = nil
    self.PendingAspectSuggestion = nil
    pcall(addon.HookActionButtonPress)
    if IsMounted and IsMounted() then
        addon:DebugPrint("GetSuggestion: montado — nada sugerido")
        return nil
    end
    if isCastingSomething("player") then
        addon:DebugPrint("GetSuggestion: conjurando/canalizando — nada sugerido")
        return nil
    end

    local env = self:BuildEnv()
    addon:DebugPrint(string.format(
        "env enemy=%s combate=%s melee=%s longe=%s dist=%s aoe=%s pvp=%s hp=%s mana=%s pet=%s autoShot=%s",
        tostring(env.hasActiveEnemy), tostring(env.inCombat), tostring(env.isMelee),
        tostring(env.tooCloseForRanged), tostring(env.targetDistance), tostring(env.isAoE),
        tostring(env.isPvP), tostring(env.myHP), tostring(env.manaPct),
        tostring(env.petAlive), tostring(addon.AutoShoot)))

    -- Aspect is a parallel hint; keep evaluating the combat rotation this tick.
    self.PendingAspectSuggestion = self:ManageAspects(env)

    -- Hunter's Mark
    if env.hasActiveEnemy and not Hunter.IsMarkedByUs() and not Hunter.IsMarked("target") then
        if self:TryFlash(1130, "Utility", function() return true end, "Hunter's Mark", env) then
            return self.PendingSuggestion
        end
    end

    -- Concussive Shot (PvP control / PvE aggro)
    if env.hasActiveEnemy and not env.isMelee and not Hunter.IsClipped("target") then
        local beingFocused = addon.UnitIsSame("targettarget", "player")
        if env.isPvP or (env.inCombat and (beingFocused or not UnitExists("targettarget"))) then
            if self:TryFlash(5116, "Interrupt", function() return true end, "Concussive Shot", env) then
                return self.PendingSuggestion
            end
        end
    end

    -- Run the spec rotation (declared data) via Core pipeline.
    local specKey = self:DetectSpec()
    if specKey then
        addon:RunDeclaredRotation(self, specKey, env)
        if self.PendingSuggestion then return self.PendingSuggestion end
    end

    -- Pet management (utilidade): depois da rotação da spec para nunca bloquear combate.
    if env.petAlive then
        local mending = addon.HasFamilyBuff("pet", "MendPet")
        local petHP = 100
        if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
            petHP = safePct(UnitHealth("pet"), UnitHealthMax("pet"))
        end
        if petHP < 70 and not mending then
            if self:TryFlash(136, "Utility", function() return true end, "Mend Pet", env,
                { noEnemy = true, noRange = true, notIfActive = true }) then
                return self.PendingSuggestion
            end
        end
    else
        if not Hunter.PET_IS_DEAD then
            if self:TryFlash(883, "Utility", function() return true end, "Call Pet", env,
                { noEnemy = true, noRange = true }) then
                return self.PendingSuggestion
            end
        else
            if self:TryFlash(34497, "Utility", function() return true end, "Revive Pet", env,
                { noEnemy = true, noRange = true }) then
                return self.PendingSuggestion
            end
        end
    end

    -- Racial (baixa prioridade: só dispara quando nada mais foi sugerido no tick).
    if addon.SuggestRacial and addon:SuggestRacial(self, env) then
        return self.PendingSuggestion
    end

    -- Auto Shot (filler) — só se não estiver em auto-repetição.
    if env.hasActiveEnemy and not env.isMelee and not addon.AutoShoot
        and not addon:IsPressSuppressed(addon.SpellName(75)) then
        if self:Suggest(75, "Damage") then return self.PendingSuggestion end
    end
    return self.PendingSuggestion or self.PendingAspectSuggestion
end

-- ---------------------------------------------------------------------------
-- /cfa debug — relatório pontual da rotação no estado atual (por nó).
-- ---------------------------------------------------------------------------
function Hunter:DebugRotation()
    local specKey = self:DetectSpec()
    local env = self:BuildEnv()
    print("|cff44ddff[CFA dbg]|r ===== RELATÓRIO DA ROTAÇÃO (Hunter) =====")
    print(string.format(
        "|cff44ddff[CFA dbg]|r spec=%s | inimigo=%s | combate=%s | melee=%s | longe=%s | dist=%s | aoe=%s | pvp=%s | hp=%s | mana=%s | pet=%s | autoShot=%s",
        tostring(specKey), tostring(env.hasActiveEnemy), tostring(env.inCombat), tostring(env.isMelee),
        tostring(env.tooCloseForRanged), tostring(env.targetDistance), tostring(env.isAoE),
        tostring(env.isPvP), tostring(env.myHP), tostring(env.manaPct),
        tostring(env.petAlive), tostring(addon.AutoShoot)))
    print(string.format("|cff44ddff[CFA dbg]|r aspectos: guepardo=%s matilha=%s falcão=%s besta=%s macaco=%s",
        tostring(Hunter.IsAspectOfCheetahActive()), tostring(Hunter.IsAspectOfPackActive()),
        tostring(Hunter.IsAspectOfHawkActive()), tostring(Hunter.IsAspectOfBeastActive()),
        tostring(Hunter.IsAspectOfMonkeyActive())))
    print("|cff44ddff[CFA dbg]|r --- nós da spec ---")
    local nodes = self:GetEffectiveNodes(specKey) or {}
    for _, node in ipairs(nodes) do
        local condOK = node.enabled ~= false and addon.NodeConditionPass(self, env, node)
        local knownID = (addon.Compat and addon.Compat.HighestKnownSpellID
            and addon.Compat.HighestKnownSpellID(node.spellID)) or node.spellID
        local name = addon.SpellName(knownID)
        local dbg = {}
        local cast = false
        if condOK and name then
            local opts = node.opts
            cast = addon.CheckCastable({
                SpellName = name,
                SpellID = knownID,
                EnemyTargetNeeded = not (opts and opts.noEnemy),
                NoRangeCheck = (opts and opts.noRange) and true or nil,
                NotIfActive = (opts and opts.notIfActive) and true or nil,
                Debug = dbg,
            }) and true or false
        end
        print(string.format("|cff44ddff[CFA dbg]|r %-16s cond=%-5s known=%-5s cast=%-5s %s",
            tostring(node.id), tostring(condOK),
            tostring(addon.Compat.SpellKnown(knownID)), tostring(cast), tostring(dbg.reason or "")))
    end
end

-- ---------------------------------------------------------------------------
-- /cfa status helper
-- ---------------------------------------------------------------------------
function Hunter:GetStatus()
    local spec, source = self:DetectSpec()
    local enabled = not (addon.db and addon.db.hunterEnabled == false)
    local PT = (GetLocale and GetLocale() == "ptBR")
    if PT then
        return string.format("Hunter — spec %s (%s) — %s", tostring(spec), tostring(source),
            enabled and "ligado" or "desligado")
    end
    return string.format("Hunter — spec %s (%s) — %s", tostring(spec), tostring(source),
        enabled and "enabled" or "disabled")
end

-- ---------------------------------------------------------------------------
-- Rotation editor: attach the shared editor with Hunter's specs + Extra tab.
-- ---------------------------------------------------------------------------
local function attachHunterEditor()
    if type(addon.RotationEditor) ~= "table"
        or type(addon.RotationEditor.Attach) ~= "function" then
        return false
    end

    local function Loc(key, fallback)
        if L and L[key] then return L[key] end
        return fallback or key
    end

    local ASPECTS = {
        { key = "Cheetah", labelKey = "extra_aspect_cheetah", fallback = "Aspect of the Cheetah" },
        { key = "Pack",    labelKey = "extra_aspect_pack",    fallback = "Aspect of the Pack" },
        { key = "Monkey",  labelKey = "extra_aspect_monkey",  fallback = "Aspect of the Monkey" },
        { key = "Beast",   labelKey = "extra_aspect_beast",   fallback = "Aspect of the Beast" },
        { key = "Hawk",    labelKey = "extra_aspect_hawk",    fallback = "Aspect of the Hawk" },
    }

    local function renderAspectsTab(scrollChild, mod, rows)
        local y = -4
        for _, aspect in ipairs(ASPECTS) do
            local aspectKey, labelKey, fallback = aspect.key, aspect.labelKey, aspect.fallback
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(30)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)

            local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            check:SetChecked(mod:IsAspectSuggestionEnabled(aspectKey))
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", check, "RIGHT", 4, 0)
            label:SetText(Loc(labelKey, fallback))
            check:SetScript("OnClick", function(self)
                mod:SetAspectSuggestionEnabled(aspectKey, self:GetChecked() and true or false)
            end)
            rows[#rows + 1] = row
            y = y - 34
        end
        scrollChild:SetHeight(math.max(-y, 1))
    end

    return addon.RotationEditor.Attach(Hunter, {
        storageKey = "hunterRotation",
        title = Loc("rotation_editor_title_hunter", "Rotation editor — Hunter"),
        specOrder = { "BM", "MM", "SV" },
        extraTabs = {
            {
                key = "EXTRA",
                label = Loc("rotation_editor_extra", "Extra"),
                render = renderAspectsTab,
                hint = Loc("extra_hint", "Aspectos são independentes da rotação. Marque os que deseja receber; as condições de uso são automáticas."),
            },
        },
    })
end

attachHunterEditor()

-- ---------------------------------------------------------------------------
-- Register isolated module with the core
-- ---------------------------------------------------------------------------
addon:RegisterModule("HUNTER", Hunter)
