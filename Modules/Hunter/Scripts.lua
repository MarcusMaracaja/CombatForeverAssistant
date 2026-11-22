-- Combat Forever Assistant â€” Hunter module: hub.
-- Builds the env, detects the spec, decides the suggestion and registers
-- the module with the core. The core pipeline (OnUpdate -> GetSuggestion)
-- takes it from here and flashes the button.
local moduleName, module = ...
local addon = _G.CFA

local L = module.L

-- ---------------------------------------------------------------------------
-- Tracking frame (aliases created at load so later files can use them)
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
        module.OnTargetChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- NOTE: aspect belief is intentionally kept (persistent per character);
        -- aspects don't expire on /reload, only on death or when recast.
        module.AspectBelief = nil
        module.MarkBelief = { slot = 0, active = false }
        module.SerpentStingBelief = { slot = 0, applied = false, expires = 0 }
        module.WingClipBelief = { slot = 0, applied = false, expires = 0 }
        module.PET_IS_DEAD = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        module.PET_IS_DEAD = false
    elseif event == "UNIT_PET" then
        local unit = ...
        if type(unit) == "string" then
            local ok, same = pcall(UnitIsUnit, unit, "player")
            if ok and same then
                local ok2, exists = pcall(UnitExists, "pet")
                local ok3, dead = pcall(UnitIsDeadOrGhost, "pet")
                module.PET_IS_DEAD = ok2 and exists and ok3 and dead or false
            end
        end
    elseif event == "UNIT_DIED" then
        local unit = ...
        if type(unit) == "string" then
            local ok, same = pcall(UnitIsUnit, unit, "pet")
            if ok and same then
                module.PET_IS_DEAD = true
            end
            -- the player's aspect is lost on death; drop the persistent belief
            local ok2, sameP = pcall(UnitIsUnit, unit, "player")
            if ok2 and sameP and module.charDb then
                module.charDb.aspectBelief = nil
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if type(spellID) == "number" and not (_G.issecretvalue and issecretvalue(spellID))
            and module.Compat and module.Compat.SpellInfoByID then
            local name = module.Compat.SpellInfoByID(spellID)
            if type(name) ~= "string" or (_G.issecretvalue and issecretvalue(name)) then
                name = nil
            end
            pcall(module.RegisterCast, name, spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Press suppress: when you press the button for the blinking spell, stop
-- blinking it immediately instead of waiting for the cast to land.
-- ---------------------------------------------------------------------------
module.PressSuppress = {}

function module.OnSpinPressed(button)
    if not button or not button.GetAttribute then return end
    local action = button:GetAttribute("action")
    if not action then return end
    local actionType, id = GetActionInfo(tonumber(action) or action)
    if actionType == "spell" and id then
        local name = module.Compat and module.Compat.SpellInfoByID and module.Compat.SpellInfoByID(id)
        if name then
            module.PressSuppress[name] = GetTime() + 0.6
        end
    end
end

function module.IsPressSuppressed(spellName)
    if not spellName or spellName == "" then return false end
    local untilTime = module.PressSuppress[spellName]
    return not not (untilTime and GetTime() < untilTime)
end

module.HooksDone = false
function module.HookActionButtonPress()
    if module.HooksDone then return end
    module.HooksDone = true
    module._hookedButtons = {}
    local function hookPrefix(prefix)
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn and not btn.cfaPressHooked then
                btn.cfaPressHooked = true
                hooksecurefunc(btn, "Click", function(self)
                    pcall(module.OnSpinPressed, self)
                end)
            end
        end
    end
    if type(SecureActionButton_OnClick) == "function" then
        hooksecurefunc("SecureActionButton_OnClick", function(self)
            pcall(module.OnSpinPressed, self)
        end)
        return
    end
    local prefixes = { "ActionButton", "MultiBarRightButton", "MultiBarLeftButton",
        "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "PetActionButton", "StanceButton", "PossessButton" }
    for _, p in ipairs(prefixes) do hookPrefix(p) end
end

-- ---------------------------------------------------------------------------
-- Env + AoE detection
-- ---------------------------------------------------------------------------
local function countEnemiesInCombat()
    if _G.MaxDps and type(_G.MaxDps.SmartAoe) == "function" then
        local ok, n = pcall(_G.MaxDps.SmartAoe)
        if ok and type(n) == "number" then return module.SafeNumber(n, 0) or 0 end
    end
    -- Fallback: no AoE detector available. Zero is safe (AoE nodes simply
    -- won't suggest); the player can still fire them from the rotation.
    return 0
end

local function safePct(cur, max)
    local c = module.SafeNumber(cur, nil)
    local m = module.SafeNumber(max, nil)
    if c and m and m > 0 then
        return math.floor(((c / m) * 100) + 0.5)
    end
    return 100
end

local function safePower(unit, ptype)
    if type(UnitPower) ~= "function" then return 0 end
    local ok, v = pcall(UnitPower, unit, ptype)
    if ok then
        return module.SafeNumber(v, 0) or 0
    end
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

-- Melee probe: the slot of "Attack" on the action bars (engine reports range)
local function findAttackSlot()
    if C_ActionBar and C_ActionBar.IsAttackAction then
        for slot = 1, 120 do
            local ok, r = pcall(C_ActionBar.IsAttackAction, slot)
            if ok and r then return slot end
        end
        return nil
    end
    if type(GetActionInfo) == "function" then
        for slot = 1, 120 do
            local actionType, id = GetActionInfo(slot)
            if actionType == "spell" and id then
                local name = module.SpellName(id)
                if name and (name == "Attack" or name == "Atacar" or name == "Ataque") then
                    return slot
                end
            end
        end
    end
    return nil
end

local function attackSlotInRange()
    local slot = findAttackSlot()
    if not slot then return nil end
    if C_ActionBar and C_ActionBar.IsActionInRange then
        local ok, r = pcall(C_ActionBar.IsActionInRange, slot)
        if not ok then return nil end
        if r == 1 then return true end
        if r == 0 then return false end
        return nil
    end
    return nil
end

local function spellProbe(id)
    local name = module.SpellName(id)
    if not name or type(IsSpellInRange) ~= "function" then return nil end
    local ok, r = pcall(IsSpellInRange, name, "target")
    if ok and r == 1 then return true end
    if ok and r == 0 then return false end
    return nil
end

function module:BuildEnv()
    local env = {}
    env.myHP = safePct(UnitHealth and UnitHealth("player"), UnitHealthMax and UnitHealthMax("player"))
    env.manaPct = safePct(UnitPower and UnitPower("player"), UnitPowerMax and UnitPowerMax("player"))
    env.rage = safePower("player", 1)
    env.energy = safePower("player", 3)
    env.combo = safePower("player", 4)
    env.targetCasting = isCastingSomething("target")
    env.hasActiveEnemy = module.UnitTargetExistsAndAttackable()
    env.isPvP = module.IsPvPTarget()
    env.isMelee = false
    env.tooCloseForRanged = false
    env.isDeadZone = false
    env.targetDistance = nil
    -- Distância: UnitDistanceSquared (medida) -> sondagem de slot (SFF) -> chute seguro.
    --
    -- Zona morta do Hunter (WotLK): corpo a corpo precisa de 5 yd e as
    -- habilidades de longo alcance não funcionam entre 5 e 10 yd.
    --   - isMelee           = dentro do alcance corpo a corpo (<= 5 yd)
    --   - tooCloseForRanged = alcance longo inviável (<= 10 yd)
    --   - isDeadZone        = 5 < distancia <= 10 (é o caso do Disengage)
    -- Antes, isMelee e tooCloseForRanged eram sempre iguais (dist <= 10), o que
    -- tornava a condição "dead_zone_not_melee" (Disengage) impossível.
    if UnitExists("target") then
        local dist = addon:TargetDistance("target")
        if dist then
            env.targetDistance = dist
            env.isMelee = dist <= 5
            env.tooCloseForRanged = dist <= 10
            env.isDeadZone = (dist > 5 and dist <= 10)
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
    env.petAlive = (type(UnitExists) == "function" and UnitExists("pet") and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("pet"))) and true or false
    env.inCombat = combatOf("player")
    env.isAoE = countEnemiesInCombat() >= 2
    return env
end

-- ---------------------------------------------------------------------------
-- Spec detection: override -> C_Traits points (SV wins ties) -> signature spells
-- Tree NAMES are "(sem nome)" on this client, so we map by POSITION:
-- Hunter treeIDs (stable WotLK order) are { SV, MM, BM }.
-- ---------------------------------------------------------------------------
local TREE_ORDER_HUNTER = { "SV", "MM", "BM" }

local _talentCountCache = nil
local function talentTreePointsByOrdinal()
    if _talentCountCache then return _talentCountCache end
    _talentCountCache = false
    if not (C_ClassTalents and C_Traits) then return false end
    local okCfg, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not okCfg or not cfg then return false end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return false end
    local counts = {}
    for idx, treeID in ipairs(info.treeIDs) do
        local specKey = TREE_ORDER_HUNTER[idx]
        if specKey then
            local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
            local total = 0
            if type(nodes) == "table" then
                for _, nodeID in ipairs(nodes) do
                    local okNI, ni = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
                    if okNI and type(ni) == "table" then
                        total = total + (tonumber(ni.currentRank) or tonumber(ni.ranksPurchased) or tonumber(ni.activeRank) or 0)
                    end
                end
            end
            counts[specKey] = total
        end
    end
    _talentCountCache = { counts = counts }
    return _talentCountCache
end

function module:DetectSpec()
    local override = module.charDb and module.charDb.hunterSpec or nil
    if override == "BM" or override == "MM" or override == "SV" then
        return override, "override"
    end
    local cache = talentTreePointsByOrdinal()
    local c = cache and cache.counts or nil
    local pointsBM = c and tonumber(c.BM) or 0
    local pointsMM = c and tonumber(c.MM) or 0
    local pointsSV = c and tonumber(c.SV) or 0
    local detail = string.format("C_Traits F=%d M=%d S=%d", pointsBM, pointsMM, pointsSV)
    if pointsBM > pointsMM and pointsBM > pointsSV then return "BM", detail end
    if pointsMM > pointsBM and pointsMM > pointsSV then return "MM", detail end
    if pointsBM > 0 or pointsMM > 0 or pointsSV > 0 then return "SV", detail end
    if type(IsSpellKnown) == "function" then
        if IsSpellKnown(19574) then return "BM", "Bestial Wrath" end
        if IsSpellKnown(19306) then return "SV", "Counterattack" end
        if IsSpellKnown(1310786) then return "MM", "Sniper Shot" end
    end
    return "SV", "default"
end

-- ---------------------------------------------------------------------------
-- Aspects (global management)
-- ---------------------------------------------------------------------------
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

local function isPvPEnvironment(env)
    if env and env.isPvP then return true end
    if type(GetInstanceInfo) == "function" then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        if ok and (instanceType == "pvp" or instanceType == "arena") then return true end
    end
    return false
end

local function unitIsSame(unit, other)
    if type(UnitIsUnit) ~= "function" then return false end
    local ok, same = pcall(UnitIsUnit, unit, other)
    if not ok or (_G.issecretvalue and issecretvalue(same)) then return false end
    return same == true
end

-- ---------------------------------------------------------------------------
-- Aspects (global management): manter a sugestão elegível até o aspecto ser
-- ativado. O loop de rotação roda a cada 0,2 s; ticks não são tentativas do jogador.
-- ---------------------------------------------------------------------------

local function aspectCastable(id)
    local knownID = module.Compat and module.Compat.HighestKnownSpellID and module.Compat.HighestKnownSpellID(id) or id
    local spellName = module.SpellName(knownID)
    if not spellName then return nil, nil, "sem nome" end
    local dbg = {}
    local ok = module.CheckCastable({
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

function module:IsAspectSuggestionEnabled(key)
    if not ASPECT_SUGGESTIONS[key] then return false end
    local settings = module.charDb and module.charDb.hunterAspectSuggestions
    return type(settings) ~= "table" or settings[key] ~= false
end

function module:SetAspectSuggestionEnabled(key, enabled)
    if not ASPECT_SUGGESTIONS[key] or not module.charDb then return false end
    module.charDb.hunterAspectSuggestions = module.charDb.hunterAspectSuggestions or {}
    local settings = module.charDb.hunterAspectSuggestions
    if enabled then
        settings[key] = nil
        if not next(settings) then module.charDb.hunterAspectSuggestions = nil end
    else
        settings[key] = false
    end
    return true
end

function module:ManageAspects(env)
    -- Out of combat: Cheetah solo / Pack in group
    if not isGroupInCombat() then
        if not isPvPEnvironment(env) then
            local numParty = groupCount(GetNumPartyMembers)
            local numRaid = groupCount(GetNumRaidMembers)
            if numParty > 0 or numRaid > 1 then
                if module:IsAspectSuggestionEnabled("Pack") and not module.IsAspectOfPackActive() then
                    return suggestAspect(13159, "Utility", "Pack")
                end
            else
                if module:IsAspectSuggestionEnabled("Cheetah") and not module.IsAspectOfCheetahActive() then
                    return suggestAspect(5118, "Utility", "Cheetah")
                end
            end
        end
        return nil
    end
    -- In combat, melee: Beast/Monkey; ranged: Hawk (damage aspect)
    if env.tooCloseForRanged then
        local beingFocused = unitIsSame("targettarget", "player")
        if beingFocused then
            if module:IsAspectSuggestionEnabled("Monkey") and not module.IsAspectOfMonkeyActive() then
                return suggestAspect(13163, "Utility", "Monkey")
            end
        else
            if module:IsAspectSuggestionEnabled("Beast") and not module.IsAspectOfBeastActive() then
                return suggestAspect(13161, "Utility", "Beast")
            end
        end
        return nil
    end
    local dangerousAspect = module.IsAspectOfCheetahActive() or module.IsAspectOfPackActive()
    if not env.tooCloseForRanged and (env.manaPct > 70 or not module.IsAspectActive() or dangerousAspect) then
        if module:IsAspectSuggestionEnabled("Hawk") and not module.IsAspectOfHawkActive() then
            return suggestAspect(13165, "Utility", "Hawk")
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Per-character rotation overrides (enabled / condition / filter).
-- charDb.hunterRotation[specKey][nodeId] = { enabled=bool?, condition=string?,
-- filter={axis=value}? } — merged over the declared defaults on every call.
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
    return module.charDb and module.charDb.hunterRotation and module.charDb.hunterRotation[specKey] or nil
end

local function rotationOrder(specKey)
    return module.charDb and module.charDb.hunterOrder and module.charDb.hunterOrder[specKey] or nil
end

function module:GetNodeOrder(specKey)
    local order = rotationOrder(specKey)
    if type(order) == "table" then return order end
    local spec = module.RotationSpecs and module.RotationSpecs[specKey]
    if not spec then return nil end
    local out = {}
    for _, n in ipairs(spec.nodes) do out[#out + 1] = n.id end
    return out
end

function module:SetNodeOrder(specKey, order)
    if not module.charDb then return end
    module.charDb.hunterOrder = module.charDb.hunterOrder or {}
    module.charDb.hunterOrder[specKey] = order
end

function module:MoveNode(specKey, nodeId, delta)
    local unpackFn = table.unpack or unpack
    local order = module:GetNodeOrder(specKey)
    if not order then return false end
    order = unpackFn and { unpackFn(order) } or { unpack(order) }
    local idx
    for i, id in ipairs(order) do if id == nodeId then idx = i break end end
    if not idx then return false end
    local j = idx + delta
    if j < 1 or j > #order then return false end
    order[idx], order[j] = order[j], order[idx]
    module:SetNodeOrder(specKey, order)
    return true
end

function module:GetEffectiveNodes(specKey)
    local spec = module.RotationSpecs and module.RotationSpecs[specKey]
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
    -- per-character custom order (^/v buttons in the editor) wins over the
    -- declared default; nodes not in the custom list keep default position.
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

function module:SetNodeOverride(specKey, nodeId, key, value)
    local charDb = module.charDb
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

function module:ResetRotationOverrides(specKey)
    if module.charDb then
        if module.charDb.hunterRotation then module.charDb.hunterRotation[specKey] = nil end
        if module.charDb.hunterOrder then module.charDb.hunterOrder[specKey] = nil end
    end
end

function module.GetRotationDisabled(specKey)
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
module.TickFlashUsed = nil
module.PendingSuggestion = nil
module.PendingAspectSuggestion = nil

function module:Suggest(spellID, color, asAdditional)
    if module.TickFlashUsed then return false end
    module.TickFlashUsed = true
    local knownID = module.Compat and module.Compat.HighestKnownSpellID and module.Compat.HighestKnownSpellID(spellID) or spellID
    local suggestion = { spellID = knownID or spellID, color = color or "Utility" }
    if asAdditional and module.PendingSuggestion then
        -- Adiciona como sugestão adicional (ex: Chute de Moa junto com dano principal)
        module.PendingSuggestion.additional = module.PendingSuggestion.additional or {}
        table.insert(module.PendingSuggestion.additional, suggestion)
    else
        local aspect = module.PendingAspectSuggestion
        if aspect and aspect.spellID ~= suggestion.spellID then
            aspect.additional = { suggestion }
            module.PendingSuggestion = aspect
        else
            module.PendingSuggestion = suggestion
        end
    end
    return true
end

function module:TryFlash(spellID, color, condition, name, env, opts, asAdditional)
    if module.TickFlashUsed then return false end
    local knownID = module.Compat and module.Compat.HighestKnownSpellID and module.Compat.HighestKnownSpellID(spellID) or spellID
    local spellName = module.SpellName(knownID or spellID)
    if not spellName then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: nome da spell não resolvido")
        return false
    end
    if knownID == 3045 and module.IsRapidFireSuppressed() then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: Rapid Fire ativo/em cooldown")
        return false
    end
    if module.IsPressSuppressed(spellName) then
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
    local castable = module.CheckCastable({
        SpellName = spellName,
        SpellID = knownID or spellID,
        EnemyTargetNeeded = not (opts and opts.noEnemy),
        NoRangeCheck = (opts and opts.noRange) and true or nil,
        NotIfActive = (opts and opts.notIfActive) and true or nil,
        Debug = dbg,
    })
    module.LastCastDebug = dbg
    if not castable then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    addon:DebugPrint("tryflash", tostring(name or spellID), "OK (sugere)")
    return module:Suggest(knownID or spellID, color, asAdditional)
end

function module:GetSuggestion()
    local _, myClass = UnitClass("player")
    if myClass ~= "HUNTER" then return nil end
    if module.db and module.db.hunterEnabled == false then return nil end
    module.TickFlashUsed = nil
    module.PendingSuggestion = nil
    module.PendingAspectSuggestion = nil
    pcall(module.HookActionButtonPress)
    if IsMounted and IsMounted() then
        addon:DebugPrint("GetSuggestion: montado — nada sugerido")
        return nil
    end
    if isCastingSomething("player") then
        addon:DebugPrint("GetSuggestion: conjurando/canalizando — nada sugerido")
        return nil
    end

    local env = module:BuildEnv()
    addon:DebugPrint(string.format(
        "env enemy=%s combate=%s melee=%s longe=%s dist=%s aoe=%s hp=%s mana=%s pet=%s autoShot=%s",
        tostring(env.hasActiveEnemy), tostring(env.inCombat), tostring(env.isMelee),
        tostring(env.tooCloseForRanged), tostring(env.targetDistance), tostring(env.isAoE),
        tostring(env.myHP), tostring(env.manaPct), tostring(env.petAlive), tostring(addon.AutoShoot)))

    -- Aspect is a parallel hint; keep evaluating the combat rotation this tick.
    module.PendingAspectSuggestion = self:ManageAspects(env)

    -- Hunter's Mark
    if env.hasActiveEnemy and not module.IsMarkedByUs() and not module.IsMarked("target") then
        if module:TryFlash(1130, "Utility", function() return true end, "Hunter's Mark", env) then
            return module.PendingSuggestion
        end
    end

    -- Concussive Shot (PvP control / PvE aggro)
    if env.hasActiveEnemy and not env.isMelee and not module.IsClipped("target") then
        local beingFocused = unitIsSame("targettarget", "player")
        if env.isPvP or (env.inCombat and (beingFocused or not UnitExists("targettarget"))) then
            if module:TryFlash(5116, "Interrupt", function() return true end, "Concussive Shot", env) then
                return module.PendingSuggestion
            end
        end
    end

    -- Run the spec rotation (declared data)
    local specKey = self:DetectSpec()
    if specKey and module.RunDeclaredRotation then
        module:RunDeclaredRotation(module, specKey, env)
        if module.PendingSuggestion then return module.PendingSuggestion end
    end

    -- Pet management (utilidade): vem DEPOIS da rotação da spec, para nunca
    -- bloquear as habilidades de combate (o SFF documenta o mesmo: "Curar/
    -- Chamar Pet piscam JUNTO com a rotação (não bloqueiam)").
    if env.petAlive then
        local mending = module.HasFamilyBuff("pet", "MendPet")
        local petHP = 100
        if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
            petHP = safePct(UnitHealth("pet"), UnitHealthMax("pet"))
        end
        if petHP < 70 and not mending then
            if module:TryFlash(136, "Utility", function() return true end, "Mend Pet", env,
                { noEnemy = true, noRange = true, notIfActive = true }) then
                return module.PendingSuggestion
            end
        end
    else
        if not module.PET_IS_DEAD then
            if module:TryFlash(883, "Utility", function() return true end, "Call Pet", env,
                { noEnemy = true, noRange = true }) then
                return module.PendingSuggestion
            end
        else
            -- Pet está morto: tenta Revive Pet (se não estiver castando já)
            if module:TryFlash(34497, "Utility", function() return true end, "Revive Pet", env,
                { noEnemy = true, noRange = true }) then
                return module.PendingSuggestion
            end
        end
    end

    -- Racial (low priority: only fires when nothing else was suggested this tick,
    -- so it never blocks the normal rotation).
    local core = _G.CFA
    if core and core.SuggestRacial and core:SuggestRacial(module, env) then return module.PendingSuggestion end

    -- Auto Shot (filler) — só se não estiver em auto-repetição (started by client)
    if env.hasActiveEnemy and not env.isMelee and not addon.AutoShoot
        and not module:IsPressSuppressed(module.SpellName(75)) then
        if module:Suggest(75, "Damage") then return module.PendingSuggestion end
    end
    return module.PendingSuggestion or module.PendingAspectSuggestion
end

-- ---------------------------------------------------------------------------
-- /cfa debug — relatório pontual da rotação no estado atual (por nó).
-- ---------------------------------------------------------------------------
function module.DebugRotation()
    local specKey = module:DetectSpec()
    local env = module:BuildEnv()
    print("|cff44ddff[CFA dbg]|r ===== RELATÓRIO DA ROTAÇÃO =====")
    print(string.format("|cff44ddff[CFA dbg]|r spec=%s | inimigo=%s | combate=%s | melee=%s | longe=%s | dist=%s | aoe=%s | hp=%s | mana=%s | pet=%s | autoShot=%s",
        tostring(specKey), tostring(env.hasActiveEnemy), tostring(env.inCombat), tostring(env.isMelee),
        tostring(env.tooCloseForRanged), tostring(env.targetDistance), tostring(env.isAoE),
        tostring(env.myHP), tostring(env.manaPct), tostring(env.petAlive), tostring(addon.AutoShoot)))
    print(string.format("|cff44ddff[CFA dbg]|r aspectos: guepardo=%s matilha=%s falcão=%s besta=%s macaco=%s",
        tostring(module.IsAspectOfCheetahActive()), tostring(module.IsAspectOfPackActive()),
        tostring(module.IsAspectOfHawkActive()), tostring(module.IsAspectOfBeastActive()),
        tostring(module.IsAspectOfMonkeyActive())))
    print("|cff44ddff[CFA dbg]|r --- nós da spec ---")
    local nodes = module:GetEffectiveNodes(specKey) or {}
    local preds = module.RotationPredicates or {}
    for _, node in ipairs(nodes) do
        local condOK = true
        if node.enabled == false then
            condOK = false
        elseif node.condition and node.condition ~= "" then
            local p = preds[node.condition]
            if type(p) == "table" and type(p.fn) == "function" then
                local ok, r = pcall(p.fn, env)
                condOK = ok and r and true or false
            end
        end
        local name = module.SpellName(node.spellID)
        local knownID = (module.Compat and module.Compat.HighestKnownSpellID
            and module.Compat.HighestKnownSpellID(node.spellID)) or node.spellID
        local dbg = {}
        local cast = false
        if condOK and name then
            cast = module.CheckCastable({
                SpellName = name, SpellID = knownID,
                EnemyTargetNeeded = true, Debug = dbg,
            }) and true or false
        end
        print(string.format("|cff44ddff[CFA dbg]|r %-16s cond=%-5s known=%-5s cast=%-5s %s",
            tostring(node.id), tostring(condOK),
            tostring(module.Compat.SpellKnown(knownID)), tostring(cast), tostring(dbg.reason or "")))
    end
end

-- ---------------------------------------------------------------------------
-- /cfa status helper
-- ---------------------------------------------------------------------------
function module:GetStatus()
    local spec, source = self:DetectSpec()
    local enabled = not (module.db and module.db.hunterEnabled == false)
    local PT = (GetLocale and GetLocale() == "ptBR")
    if PT then
        return string.format("Hunter — spec %s (%s) — %s", tostring(spec), tostring(source),
            enabled and "ligado" or "desligado")
    end
    return string.format("Hunter — spec %s (%s) — %s", tostring(spec), tostring(source),
        enabled and "enabled" or "disabled")
end

-- ---------------------------------------------------------------------------
-- Register with the core
-- ---------------------------------------------------------------------------
module:RegisterModule("HUNTER", module)
