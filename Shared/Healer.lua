-- Combat Forever Assistant — Shared Healer Triage & Group Scanning Engine.
-- Global layer reusable by ANY healer class (Priest, Druid, Shaman, Paladin).
-- Responsibilities:
--   1) Detect solo / party / raid membership safely (WoW Forever secret-safe)
--   2) Scan ally health, dead status, tank role, range and dispellable debuffs
--   3) Pick the #1 ally who needs attention (recommendedUnit) so Visuals can
--      outline their portrait / party / raid frame
--   4) Determine the active heal target (activeUnit): only recommends targeted
--      healing spells once the healer has a needing ally targeted (or self when
--      self needs healing) AND that ally is within spell range.
-- Never targets, clicks or casts automatically — strictly visual assistance.
local _, addon = ...

local Healer = {}
addon.Healer = Healer

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function safeNum(v, fallback)
    if type(addon.SafeNumber) == "function" then return addon.SafeNumber(v, fallback) end
    if type(v) ~= "number" or (addon.IsSecretValue and addon.IsSecretValue(v)) then return fallback end
    return v
end

local function safeBool(v, fallback)
    if type(addon.SafeBoolean) == "function" then return addon.SafeBoolean(v, fallback) end
    if type(v) ~= "boolean" or (addon.IsSecretValue and addon.IsSecretValue(v)) then return fallback end
    return v
end

local function safeStr(v, fallback)
    if type(addon.SafeString) == "function" then return addon.SafeString(v, fallback) end
    if type(v) ~= "string" or (addon.IsSecretValue and addon.IsSecretValue(v)) then return fallback end
    return v
end

-- ---------------------------------------------------------------------------
-- Group detection & unit enumeration
-- ---------------------------------------------------------------------------
function Healer.IsInRaid()
    if type(IsInRaid) == "function" then
        local ok, v = safeCall(IsInRaid)
        if ok and safeBool(v, false) then return true end
    end
    return false
end

function Healer.IsInGroup()
    if Healer.IsInRaid() then return true end
    if type(IsInGroup) == "function" then
        local ok, v = safeCall(IsInGroup)
        if ok and safeBool(v, false) then return true end
    end
    if type(GetNumGroupMembers) == "function" then
        local ok, n = safeCall(GetNumGroupMembers)
        if ok and (safeNum(n, 0) or 0) > 1 then return true end
    end
    if type(GetNumSubgroupMembers) == "function" then
        local ok, n = safeCall(GetNumSubgroupMembers)
        if ok and (safeNum(n, 0) or 0) > 0 then return true end
    end
    return false
end

function Healer.GetGroupUnits()
    local units = {}
    if Healer.IsInRaid() then
        local count = 40
        if type(GetNumGroupMembers) == "function" then
            local ok, n = safeCall(GetNumGroupMembers)
            n = ok and safeNum(n, 0) or 0
            if n > 0 then count = math.min(40, n) end
        end
        local sawPlayer = false
        for i = 1, count do
            local u = "raid" .. i
            local okE, exists = safeCall(UnitExists, u)
            if okE and exists then
                if addon.UnitIsSame and addon.UnitIsSame(u, "player") then
                    units[#units + 1] = "player"
                    sawPlayer = true
                else
                    units[#units + 1] = u
                end
            end
        end
        if not sawPlayer then
            table.insert(units, 1, "player")
        end
        return units
    end

    units[1] = "player"
    if Healer.IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            local okE, exists = safeCall(UnitExists, u)
            if okE and exists then
                units[#units + 1] = u
            end
        end
    end
    return units
end

-- ---------------------------------------------------------------------------
-- Per-unit state readers (HP%, dead, connected, friendly, role, range, dispels)
-- ---------------------------------------------------------------------------
function Healer.IsUnitConnected(unit)
    if not unit then return false end
    local okE, exists = safeCall(UnitExists, unit)
    if not okE or not exists then return false end
    if type(UnitIsConnected) == "function" then
        local okC, conn = safeCall(UnitIsConnected, unit)
        local b = okC and safeBool(conn, nil)
        if b == false then return false end
    end
    return true
end

function Healer.IsUnitDead(unit)
    if not unit then return false end
    if type(UnitIsDeadOrGhost) == "function" then
        local ok, d = safeCall(UnitIsDeadOrGhost, unit)
        local b = ok and safeBool(d, nil)
        if b ~= nil then return b end
    end
    if type(UnitIsDead) == "function" then
        local ok, d = safeCall(UnitIsDead, unit)
        local b = ok and safeBool(d, nil)
        if b ~= nil then return b end
    end
    return false
end

function Healer.IsUnitFriendlyPlayer(unit)
    if not unit then return false end
    local okE, exists = safeCall(UnitExists, unit)
    if not okE or not exists then return false end
    if addon.UnitIsSame and addon.UnitIsSame(unit, "player") then return true end
    if type(UnitCanAttack) == "function" then
        local okA, canAtk = safeCall(UnitCanAttack, "player", unit)
        if okA and safeBool(canAtk, false) == true then return false end
    end
    if type(UnitIsFriend) == "function" then
        local okF, isF = safeCall(UnitIsFriend, "player", unit)
        local b = okF and safeBool(isF, nil)
        if b == false then return false end
    end
    if type(UnitCanAssist) == "function" then
        local okAs, canAs = safeCall(UnitCanAssist, "player", unit)
        local b = okAs and safeBool(canAs, nil)
        if b == false then return false end
    end
    return true
end

function Healer.GetUnitHealthPct(unit)
    if not unit then return nil, false end
    local cur, maxV
    local okC, rawC = safeCall(UnitHealth, unit)
    local okM, rawM = safeCall(UnitHealthMax, unit)
    cur = okC and safeNum(rawC, nil) or nil
    maxV = okM and safeNum(rawM, nil) or nil
    if cur ~= nil and maxV ~= nil and maxV > 0 then
        return math.max(0, math.min(100, (cur / maxV) * 100)), true
    end
    -- Modern Midnight/Forever fallback if UnitHealthPercent is exposed
    if type(UnitHealthPercent) == "function" then
        local okP, rawP = safeCall(UnitHealthPercent, unit)
        local p = okP and safeNum(rawP, nil) or nil
        if p ~= nil then
            if p <= 1.0 and p >= 0 then p = p * 100 end
            return math.max(0, math.min(100, p)), true
        end
    end
    return nil, false
end

function Healer.GetUnitRole(unit)
    if not unit then return "NONE" end
    if type(GetPartyAssignment) == "function" then
        local okMT, mt = safeCall(GetPartyAssignment, "MAINTANK", unit)
        if okMT and safeBool(mt, false) == true then return "TANK" end
    end
    if type(UnitGroupRolesAssigned) == "function" then
        local okR, role = safeCall(UnitGroupRolesAssigned, unit)
        role = okR and safeStr(role, nil) or nil
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
            return role
        end
    end
    return "NONE"
end

-- Secret-safe range check for friendly healing/resurrection spells.
-- Returns: inRange (bool), source (string)
function Healer.IsUnitInRange(unit, spellID, maxYards)
    if not unit then return false, "no_unit" end
    local okE, exists = safeCall(UnitExists, unit)
    if not okE or not exists then return false, "not_exists" end
    if addon.UnitIsSame and addon.UnitIsSame(unit, "player") then
        return true, "self"
    end

    maxYards = maxYards or 40

    -- 1) Exact spell range check (most accurate when spell is known)
    if spellID then
        local knownID = (addon.Compat and addon.Compat.ResolveKnownID and addon.Compat.ResolveKnownID(spellID)) or spellID
        if C_Spell and type(C_Spell.IsSpellInRange) == "function" then
            local ok, res = safeCall(C_Spell.IsSpellInRange, knownID, unit)
            if ok and res ~= nil and not (addon.IsSecretValue and addon.IsSecretValue(res)) then
                if res == true or res == 1 then return true, "C_Spell.IsSpellInRange" end
                if res == false or res == 0 then return false, "C_Spell.IsSpellInRange" end
            end
        end
        local spellName = addon.SpellName and addon.SpellName(knownID)
        if spellName and type(IsSpellInRange) == "function" then
            local ok, res = safeCall(IsSpellInRange, spellName, unit)
            if ok and res ~= nil and not (addon.IsSecretValue and addon.IsSecretValue(res)) then
                if res == 1 or res == true then return true, "IsSpellInRange" end
                if res == 0 or res == false then return false, "IsSpellInRange" end
            end
        end
    end

    -- 2) Exact distance squared (works on party/raid in open world & many instances)
    if type(UnitDistanceSquared) == "function" then
        local ok, distSq, checked = safeCall(UnitDistanceSquared, unit)
        if ok and safeBool(checked, false) == true then
            local sq = safeNum(distSq, nil)
            if sq ~= nil and sq >= 0 then
                return (sq <= (maxYards * maxYards)), "UnitDistanceSquared"
            end
        end
    end

    -- 3) UnitInRange (~40y for party/raid members)
    if type(UnitInRange) == "function" then
        local ok, inRange, checked = safeCall(UnitInRange, unit)
        if ok then
            local chk = safeBool(checked, true)
            local ir = safeBool(inRange, nil)
            if chk ~= false and ir ~= nil then
                return ir, "UnitInRange"
            end
        end
    end

    -- 4) Visibility fallback: if not visible at all, definitely out of range
    if type(UnitIsVisible) == "function" then
        local ok, vis = safeCall(UnitIsVisible, unit)
        if ok and safeBool(vis, true) == false then
            return false, "UnitIsVisible"
        end
    end

    -- Fail-open if client masks distance/range
    return true, "fail_open"
end

function Healer.ScanUnitDispellable(unit)
    local out = { magic = false, disease = false, poison = false, curse = false }
    if not unit or not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then
        return out
    end
    for i = 1, 40 do
        local ok, aura = safeCall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        if not ok or type(aura) ~= "table" then break end
        local okD, dType = pcall(function() return aura.dispelName end)
        dType = okD and safeStr(dType, nil) or nil
        if dType == "Magic" then out.magic = true
        elseif dType == "Disease" then out.disease = true
        elseif dType == "Poison" then out.poison = true
        elseif dType == "Curse" then out.curse = true
        end
    end
    return out
end

function Healer.PlayerHasAggro()
    if type(UnitThreatSituation) == "function" then
        local ok, status = safeCall(UnitThreatSituation, "player")
        local n = ok and safeNum(status, nil) or nil
        if n ~= nil and n >= 2 then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Group Triage Scanner
-- opts = {
--   inCombat = bool,
--   healSpellID = number (e.g. 2061 Flash Heal, for 40y range probe),
--   resSpellID = number (e.g. 2006 Resurrection, for 30y range probe),
--   canDispelMagic = bool,
--   canDispelDisease = bool,
--   canDispelPoison = bool,
--   canDispelCurse = bool,
--   canResurrect = bool,
--   healThreshold = number (default 93),
--   proactiveTankShield = bool (default false; e.g. Priest in combat on tank <= 95%),
--   tankNeedsShieldFn = function(unit) -> bool,
-- }
-- ---------------------------------------------------------------------------
function Healer.ScanGroup(opts)
    opts = opts or {}
    local inCombat = opts.inCombat == true
    local healSpellID = opts.healSpellID
    local resSpellID = opts.resSpellID
    local healThreshold = opts.healThreshold or 93
    local inGroup = Healer.IsInGroup()
    local isRaid = Healer.IsInRaid()
    local groupUnits = Healer.GetGroupUnits()

    local records = {}
    local injuredCount82 = 0
    local injuredCount72 = 0
    local criticalCount55 = 0
    local deadCount = 0
    local hpSum, hpCount = 0, 0
    local tankUnit, tankHP = nil, nil
    local hasExplicitTank = false

    for _, unit in ipairs(groupUnits) do
        if Healer.IsUnitConnected(unit) then
            local isSelf = addon.UnitIsSame and addon.UnitIsSame(unit, "player") or (unit == "player")
            local dead = Healer.IsUnitDead(unit)
            local hp, hpOK = Healer.GetUnitHealthPct(unit)
            if dead then hp = 0 end
            local role = Healer.GetUnitRole(unit)
            if role == "TANK" then hasExplicitTank = true end

            local inRange, rangeSrc = Healer.IsUnitInRange(unit, healSpellID, 40)
            local inResRange = dead and Healer.IsUnitInRange(unit, resSpellID or healSpellID, 30) or inRange
            local disp = (not dead and inRange) and Healer.ScanUnitDispellable(unit)
                or { magic = false, disease = false, poison = false, curse = false }

            local _, cls = UnitClass(unit)
            local name = safeStr(UnitName(unit), unit)

            local rec = {
                unit = unit,
                name = name,
                class = cls,
                isSelf = isSelf,
                dead = dead,
                hp = hp,
                hpReadable = hpOK,
                role = role,
                inRange = inRange,
                inResRange = inResRange,
                rangeSrc = rangeSrc,
                dispel = disp,
            }
            records[#records + 1] = rec

            if dead then
                deadCount = deadCount + 1
            elseif inRange and hp ~= nil then
                hpSum = hpSum + hp
                hpCount = hpCount + 1
                if hp <= 82 then injuredCount82 = injuredCount82 + 1 end
                if hp <= 72 then injuredCount72 = injuredCount72 + 1 end
                if hp <= 55 then criticalCount55 = criticalCount55 + 1 end
            end
        end
    end

    -- Fallback tank detection in classic 5-man when Blizzard role wasn't set:
    -- pick the Warrior (or Bear Druid / Paladin) with highest max HP in the party.
    if not hasExplicitTank and inGroup and #records >= 2 then
        local bestTankRec, bestMaxHP = nil, 0
        for _, rec in ipairs(records) do
            if not rec.isSelf and not rec.dead
                and (rec.class == "WARRIOR" or rec.class == "PALADIN" or rec.class == "DRUID") then
                local okM, mhp = safeCall(UnitHealthMax, rec.unit)
                mhp = okM and safeNum(mhp, 0) or 0
                if mhp > bestMaxHP then
                    bestMaxHP = mhp
                    bestTankRec = rec
                end
            end
        end
        if bestTankRec then
            bestTankRec.role = "TANK"
        end
    end

    for _, rec in ipairs(records) do
        if rec.role == "TANK" and not rec.dead then
            tankUnit = rec.unit
            tankHP = rec.hp
            break
        end
    end

    -- Score each member to find #1 recommendedUnit
    local bestRec, bestScore, bestReason = nil, -99999, nil
    for _, rec in ipairs(records) do
        local score = nil
        local reason = nil

        if rec.dead then
            -- Resurrect ONLY out of combat
            if not inCombat and opts.canResurrect ~= false and not rec.isSelf then
                score = rec.inResRange and 45 or -500
                reason = "resurrect"
            end
        elseif rec.hp ~= nil and rec.hp < healThreshold then
            score = 100 - rec.hp
            if rec.hp <= 35 then
                score = score + 60
                reason = "emergency"
            else
                reason = "heal"
            end
            if rec.role == "TANK" then score = score + 18 end
            if rec.isSelf and rec.hp <= 45 then score = score + 22 end
            if not rec.inRange then score = score - 1000 end
        elseif inCombat and opts.proactiveTankShield and rec.role == "TANK" and rec.inRange
            and type(opts.tankNeedsShieldFn) == "function" and opts.tankNeedsShieldFn(rec.unit) then
            score = 8
            reason = "tank_shield"
        end

        -- Dispellable debuffs (lower urgency than critical healing, higher than minor chip damage)
        if not rec.dead and rec.inRange then
            local wantMagic = opts.canDispelMagic and rec.dispel.magic
            local wantDisease = opts.canDispelDisease and rec.dispel.disease
            local wantPoison = opts.canDispelPoison and rec.dispel.poison
            local wantCurse = opts.canDispelCurse and rec.dispel.curse
            if wantMagic or wantDisease or wantPoison or wantCurse then
                local dispelScore = 22 + (rec.role == "TANK" and 6 or 0)
                if score == nil or dispelScore > score then
                    score = dispelScore
                    if wantMagic then reason = "dispel_magic"
                    elseif wantDisease then reason = "dispel_disease"
                    elseif wantPoison then reason = "dispel_poison"
                    else reason = "dispel_curse" end
                end
            end
        end

        if score ~= nil and score > bestScore then
            bestScore = score
            bestRec = rec
            bestReason = reason
        end
    end

    -- Also allow healing a friendly non-group target (e.g. open-world ally / NPC)
    -- if nobody in our group needs attention.
    if not bestRec and Healer.IsUnitFriendlyPlayer("target")
        and not (addon.UnitIsSame and addon.UnitIsSame("target", "player")) then
        local dead = Healer.IsUnitDead("target")
        local hp = Healer.GetUnitHealthPct("target")
        local inRange = Healer.IsUnitInRange("target", healSpellID, 40)
        if dead and not inCombat and opts.canResurrect ~= false then
            bestRec = {
                unit = "target", name = safeStr(UnitName("target"), "target"),
                isSelf = false, dead = true, hp = 0, role = "NONE",
                inRange = inRange, inResRange = Healer.IsUnitInRange("target", resSpellID or healSpellID, 30),
                dispel = { magic = false, disease = false, poison = false, curse = false },
            }
            bestReason = "resurrect"
        elseif not dead and hp ~= nil and hp < healThreshold then
            bestRec = {
                unit = "target", name = safeStr(UnitName("target"), "target"),
                isSelf = false, dead = false, hp = hp, role = "NONE",
                inRange = inRange, inResRange = inRange,
                dispel = Healer.ScanUnitDispellable("target"),
            }
            bestReason = (hp <= 35) and "emergency" or "heal"
        end
    end

    -- Color coding for unit-frame highlight
    local recOutOfRange = false
    local recColor = "Defensive"
    if bestRec then
        recOutOfRange = (bestReason == "resurrect") and (not bestRec.inResRange) or (not bestRec.inRange)
        if recOutOfRange then
            recColor = "Interrupt" -- Yellow: ally needs attention, move closer!
        elseif bestReason == "emergency" then
            recColor = "Damage"    -- Red: critical danger (<= 35% HP)!
        elseif bestReason == "resurrect" or (bestReason and bestReason:sub(1, 6) == "dispel") then
            recColor = "Utility"   -- Cyan: Resurrection or Dispel
        else
            recColor = "Defensive" -- Green: Standard heal / shield
        end
    end

    -- Determine activeUnit (who the healer's spell cast will actually land on RIGHT NOW!)
    local activeUnit, activeRec = nil, nil
    local hasFriendlyTarget = UnitExists("target") and Healer.IsUnitFriendlyPlayer("target")

    if hasFriendlyTarget then
        -- Check if player's current target is in our group records
        local tgtRec
        for _, rec in ipairs(records) do
            if addon.UnitIsSame and addon.UnitIsSame("target", rec.unit) then
                tgtRec = rec
                break
            end
        end
        if not tgtRec and bestRec and bestRec.unit == "target" then
            tgtRec = bestRec
        end
        if tgtRec then
            -- Use player's selected friendly target if it actually needs healing/shield/dispel/res
            local needsAction = (tgtRec.dead and not inCombat)
                or (not tgtRec.dead and tgtRec.hp ~= nil and tgtRec.hp < healThreshold)
                or (not tgtRec.dead and ((opts.canDispelMagic and tgtRec.dispel.magic)
                    or (opts.canDispelDisease and tgtRec.dispel.disease)
                    or (opts.canDispelPoison and tgtRec.dispel.poison)
                    or (opts.canDispelCurse and tgtRec.dispel.curse)))
                or (bestRec and tgtRec.unit == bestRec.unit)
            if needsAction then
                activeUnit = "target"
                activeRec = tgtRec
            end
        end
    elseif bestRec and bestRec.isSelf then
        -- No friendly target (targeting enemy or nobody) and YOU need healing: WoW auto-self-casts!
        activeUnit = "player"
        activeRec = bestRec
    end

    return {
        inGroup               = inGroup,
        isRaid                = isRaid,
        groupSize             = #records,
        units                 = records,
        injuredCount82        = injuredCount82,
        injuredCount72        = injuredCount72,
        criticalCount55       = criticalCount55,
        deadCount             = deadCount,
        avgGroupHP            = (hpCount > 0) and (hpSum / hpCount) or 100,
        tankUnit              = tankUnit,
        tankHP                = tankHP,
        -- Who should have their party/raid portrait highlighted
        recommendedUnit       = bestRec and bestRec.unit or nil,
        recommendedName       = bestRec and bestRec.name or nil,
        recommendedHP         = bestRec and bestRec.hp or nil,
        recommendedReason     = bestReason,
        recommendedOutOfRange = recOutOfRange,
        recommendedColor      = recColor,
        -- Who will receive the heal spell right now (nil if healer must click recommendedUnit first)
        activeUnit            = activeUnit,
        activeName            = activeRec and activeRec.name or nil,
        activeHP              = activeRec and activeRec.hp or nil,
        activeIsSelf          = activeRec and activeRec.isSelf or false,
        activeIsDead          = activeRec and activeRec.dead or false,
        activeIsTank          = activeRec and (activeRec.role == "TANK") or false,
        activeInRange         = activeRec and activeRec.inRange or false,
        activeInResRange      = activeRec and activeRec.inResRange or false,
        activeDispelMagic     = activeRec and activeRec.dispel and activeRec.dispel.magic or false,
        activeDispelDisease   = activeRec and activeRec.dispel and activeRec.dispel.disease or false,
        activeDispelPoison    = activeRec and activeRec.dispel and activeRec.dispel.poison or false,
        activeDispelCurse     = activeRec and activeRec.dispel and activeRec.dispel.curse or false,
        playerHasAggro        = Healer.PlayerHasAggro(),
    }
end

-- ---------------------------------------------------------------------------
-- Chat diagnostic command: /cfa heal
-- ---------------------------------------------------------------------------
function Healer.DebugDump(opts)
    local function P(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("|cff44ddff[CFA heal]|r " .. table.concat(parts, " "))
    end

    local inCombat = (type(UnitAffectingCombat) == "function" and safeBool(UnitAffectingCombat("player"), false)) or false
    local hs = Healer.ScanGroup(opts or {
        inCombat = inCombat,
        healSpellID = 2061,
        resSpellID = 2006,
        canDispelMagic = true,
        canDispelDisease = true,
        canResurrect = true,
    })

    P("===== DIAGNÓSTICO HEALER / GRUPO =====")
    P(string.format("inGroup=%s isRaid=%s size=%d combat=%s aggro=%s avgHP=%.1f%% inj82=%d inj72=%d crit55=%d dead=%d",
        tostring(hs.inGroup), tostring(hs.isRaid), hs.groupSize, tostring(inCombat),
        tostring(hs.playerHasAggro), hs.avgGroupHP or 100, hs.injuredCount82, hs.injuredCount72,
        hs.criticalCount55, hs.deadCount))
    P(string.format("RECOMENDADO: unit=%s (%s) hp=%s motivo=%s outOfRange=%s cor=%s",
        tostring(hs.recommendedUnit or "nenhum"), tostring(hs.recommendedName or "-"),
        hs.recommendedHP and string.format("%.0f%%", hs.recommendedHP) or "-",
        tostring(hs.recommendedReason or "-"), tostring(hs.recommendedOutOfRange), tostring(hs.recommendedColor)))
    P(string.format("ALVO ATIVO P/ CURA: unit=%s (%s) hp=%s dead=%s inRange=%s resRange=%s magic=%s disease=%s",
        tostring(hs.activeUnit or "nenhum (clique no aliado destacado!)"), tostring(hs.activeName or "-"),
        hs.activeHP and string.format("%.0f%%", hs.activeHP) or "-",
        tostring(hs.activeIsDead), tostring(hs.activeInRange), tostring(hs.activeInResRange),
        tostring(hs.activeDispelMagic), tostring(hs.activeDispelDisease)))

    for _, rec in ipairs(hs.units) do
        local frames = (addon.Visuals and addon.Visuals.FindUnitFrames and addon.Visuals.FindUnitFrames(rec.unit)) or {}
        local fNames = {}
        for _, f in ipairs(frames) do
            fNames[#fNames + 1] = tostring(f.name or "frame") .. (f.portrait and "(portrait)" or "(card)")
        end
        local dFlags = {}
        if rec.dispel.magic then dFlags[#dFlags + 1] = "M" end
        if rec.dispel.disease then dFlags[#dFlags + 1] = "D" end
        if rec.dispel.poison then dFlags[#dFlags + 1] = "P" end
        if rec.dispel.curse then dFlags[#dFlags + 1] = "C" end
        P(string.format("  %-7s %-14s role=%-6s hp=%-5s(ok=%s) dead=%-5s range=%-5s(%s) disp=%s ui=[%s]",
            rec.unit, tostring(rec.name):sub(1, 14), rec.role,
            rec.hp and string.format("%.0f%%", rec.hp) or "nil", tostring(rec.hpReadable),
            tostring(rec.dead), tostring(rec.inRange), tostring(rec.rangeSrc),
            (#dFlags > 0) and table.concat(dFlags, ",") or "-",
            (#fNames > 0) and table.concat(fNames, ",") or "NENHUM"))
    end
    P("===== FIM DIAGNÓSTICO HEALER =====")
end
