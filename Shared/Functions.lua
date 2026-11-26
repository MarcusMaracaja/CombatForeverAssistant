-- Combat Forever Assistant — Shared utility functions (generic layer).
-- Exposed on the global addon namespace so ANY class module (Hunter, Shaman,
-- Druid, future classes) can consume them without duplicating code or
-- depending on another class folder.
--
-- Load order: after Core.lua, before Shared\Predicates.lua and class modules.
local _, addon = ...

-- ---------------------------------------------------------------------------
-- Safe number, boolean & string guards (WoW Forever degrades reads to secrets).
-- ---------------------------------------------------------------------------
function addon.IsSecretValue(v)
    if v == nil then return false end
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, v)
    return ok and secret == true
end

function addon.SafeNumber(v, fallback)
    if type(v) ~= "number" then return fallback end
    if addon.IsSecretValue(v) then return fallback end
    if v ~= v or v == math.huge or v == -math.huge then return fallback end
    return v
end

function addon.SafeBoolean(v, fallback)
    if type(v) ~= "boolean" then return fallback end
    if addon.IsSecretValue(v) then return fallback end
    return v
end

function addon.SafeString(v, fallback)
    if type(v) ~= "string" then return fallback end
    if addon.IsSecretValue(v) then return fallback end
    return v
end

function addon.StripRank(name)
    if type(name) ~= "string" then return nil end
    return (name:gsub("%s*%(.-%)%s*$", ""))
end

local function normalizeSpellName(n)
    if type(n) ~= "string" then return "" end
    return n:lower():gsub("%s*%b()%s*$", "")
end

-- ---------------------------------------------------------------------------
-- Spell helpers
-- ---------------------------------------------------------------------------
function addon.SpellName(id)
    if not id then return nil end
    local name
    if addon.Compat and addon.Compat.SpellInfoByID then
        name = addon.Compat.SpellInfoByID(id)
    end
    if not name and type(GetSpellInfo) == "function" then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then name = n end
    end
    if type(name) ~= "string" or (_G.issecretvalue and issecretvalue(name)) then
        return nil
    end
    return addon.StripRank(name)
end

function addon.SpellIDFromName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if addon.Compat and addon.Compat.SpellIDFromName then
        return addon.Compat.SpellIDFromName(name)
    end
    return nil
end

function addon.SpellKnown(nameOrID)
    if type(nameOrID) == "number" and addon.Compat and addon.Compat.SpellKnown then
        return addon.Compat.SpellKnown(nameOrID)
    end
    if addon.Compat and addon.Compat.SpellBookItem then
        for i = 1, 300 do
            local n = addon.Compat.SpellBookItem(i, "spell")
            if n == nameOrID then return true end
            if n == nil then break end
        end
    end
    return false
end

function addon.IsOnCooldown(name, id)
    local known = id or addon.SpellIDFromName(name)
    if not known then return false end
    return addon:IsSpellOnCooldown(known)
end

-- ---------------------------------------------------------------------------
-- Castable engine wrapper (delegates to Core:CheckIfSpellCastable with ":").
-- ---------------------------------------------------------------------------
function addon.CheckCastable(z)
    if type(z) ~= "table" then return false end
    z.Unit = z.Unit or "target"
    return addon:CheckIfSpellCastable(z)
end

-- ---------------------------------------------------------------------------
-- Target & environment helpers (generic, secret-safe, fail-open where needed).
-- ---------------------------------------------------------------------------
function addon.UnitTargetExistsAndAttackable()
    if not UnitExists("target") then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if ok and dead then return false end
    local ok2, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok2 then return true end -- fail-open: never starve rotation on unreadable probe
    if _G.issecretvalue and issecretvalue(canAttack) then return true end
    return canAttack and true or false
end

function addon.IsPvPTarget()
    if not (type(UnitIsPlayer) == "function" and UnitIsPlayer("target")) then return false end
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok or (_G.issecretvalue and issecretvalue(canAttack)) then return false end
    return canAttack and true or false
end

function addon.IsPvPInstance()
    if type(GetInstanceInfo) == "function" then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        if ok and (instanceType == "pvp" or instanceType == "arena") then return true end
    end
    return false
end

function addon.IsPvPEnvironment(env)
    if env and env.isPvP then return true end
    return addon.IsPvPTarget() or addon.IsPvPInstance()
end

function addon.UnitIsSame(unit, other)
    if type(UnitIsUnit) ~= "function" then return false end
    local ok, same = pcall(UnitIsUnit, unit, other)
    if not ok or (_G.issecretvalue and issecretvalue(same)) then return false end
    return same == true
end

function addon.TargetUsesMana()
    if not UnitExists("target") then return false end
    local ok, t = pcall(UnitPowerType, "target")
    return ok and t == 0 or false
end

function addon.TargetIsMeleeClass()
    if not UnitExists("target") then return false end
    local _, cls = UnitClass("target")
    return cls == "WARRIOR" or cls == "ROGUE"
end

function addon.IsTargetInterruptibleCasting(unit)
    unit = unit or "target"
    if type(UnitCastingInfo) ~= "function" then return false end
    local ok, name, _, _, _, _, canInterrupt = pcall(UnitCastingInfo, unit)
    if not ok or not name then return false end
    if _G.issecretvalue and issecretvalue(canInterrupt) then return false end
    return canInterrupt and true or false
end

-- ---------------------------------------------------------------------------
-- Aura / buff helpers (generic, C_UnitAuras-first, secret-safe).
-- ---------------------------------------------------------------------------
function addon.HasFamilyBuff(unit, family)
    if not addon.BuffLib or not addon.BuffLib.HasFamily then return false end
    return addon.BuffLib:HasFamily(unit, family) and true or false
end

function addon.HasFamilyDebuff(unit, family)
    if not addon.BuffLib or not addon.BuffLib.Has then return false end
    return addon.BuffLib:Has(unit, family) and true or false
end

local function scanAura(unit, spellIDOrName, filter)
    if not UnitExists(unit) then return false end
    local wantName
    if type(spellIDOrName) == "number" then
        wantName = addon.SpellName(spellIDOrName)
    elseif type(spellIDOrName) == "string" then
        wantName = spellIDOrName
    end
    local wantClean = wantName and normalizeSpellName(wantName) or nil

    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or not data or type(data) ~= "table" then break end
            local okId, sId = pcall(function()
                return tonumber(data.spellId or data.spellID or data.auraSpellId or data.auraSpellID)
            end)
            if okId and sId and type(spellIDOrName) == "number" and sId == spellIDOrName then
                return true
            end
            if wantClean and wantClean ~= "" and type(data.name) == "string"
                and not (_G.issecretvalue and issecretvalue(data.name))
                and normalizeSpellName(data.name) == wantClean then
                return true
            end
        end
    end
    return false
end

function addon.HasBuff(unit, spellIDOrName)
    return scanAura(unit or "player", spellIDOrName, "HELPFUL")
end

function addon.HasDebuff(unit, spellIDOrName)
    return scanAura(unit or "target", spellIDOrName, "HARMFUL")
end

-- ---------------------------------------------------------------------------
-- Current spell / casting helpers (generic).
-- ---------------------------------------------------------------------------
function addon.IsCurrentSpell(spellName)
    if addon.Compat and addon.Compat.IsCurrentSpell then
        return addon.Compat.IsCurrentSpell(spellName)
    end
    if type(IsCurrentSpell) == "function" then
        local ok, c = pcall(IsCurrentSpell, spellName)
        if ok then return not not c end
    end
    return false
end

function addon.CastingOrChanneling(baseName, unit)
    unit = unit or "player"
    if addon.Compat and addon.Compat.CastingOrChanneling then
        return addon.Compat.CastingOrChanneling(baseName, unit)
    end
    if type(UnitCastingInfo) == "function" then
        local ok, name = pcall(UnitCastingInfo, unit)
        if ok and type(name) == "string" and name ~= "" then return true end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, name = pcall(UnitChannelInfo, unit)
        if ok and type(name) == "string" and name ~= "" then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Global Character Resources (Mana, Rage, Focus, Energy, Combo Points, etc.)
-- Centralized here in Shared/Functions.lua so every class module (Druid,
-- Hunter, Shaman, Warrior, Rogue, Paladin, future classes), Equipment and
-- Core filter axes share one secret-safe, WoW Forever-compatible layer.
-- ---------------------------------------------------------------------------
local EPT = (type(_G.Enum) == "table" and type(_G.Enum.PowerType) == "table") and _G.Enum.PowerType or {}

addon.PowerType = {
    MANA         = EPT.Mana        or 0,
    RAGE         = EPT.Rage        or 1,
    FOCUS        = EPT.Focus       or 2,
    ENERGY       = EPT.Energy      or 3,
    COMBO_POINTS = EPT.ComboPoints or 4,
    RUNES        = EPT.Runes       or 5,
    RUNIC_POWER  = EPT.RunicPower  or 6,
    SOUL_SHARDS  = EPT.SoulShards  or 7,
    LUNAR_POWER  = EPT.LunarPower  or 8,
    HOLY_POWER   = EPT.HolyPower   or 9,
    MAELSTROM    = EPT.Maelstrom   or 11,
    INSANITY     = EPT.Insanity    or 13,
    FURY         = EPT.Fury        or 17,
    PAIN         = EPT.Pain        or 18,
}

local POWER_ALIASES = {
    mana         = addon.PowerType.MANA,
    rage         = addon.PowerType.RAGE,
    raiva        = addon.PowerType.RAGE,
    focus        = addon.PowerType.FOCUS,
    foco         = addon.PowerType.FOCUS,
    energy       = addon.PowerType.ENERGY,
    energia      = addon.PowerType.ENERGY,
    combo        = addon.PowerType.COMBO_POINTS,
    combopoints  = addon.PowerType.COMBO_POINTS,
    combo_points = addon.PowerType.COMBO_POINTS,
    runes        = addon.PowerType.RUNES,
    runic        = addon.PowerType.RUNIC_POWER,
    runicpower   = addon.PowerType.RUNIC_POWER,
    runic_power  = addon.PowerType.RUNIC_POWER,
    soulshards   = addon.PowerType.SOUL_SHARDS,
    soul_shards  = addon.PowerType.SOUL_SHARDS,
    lunarpower   = addon.PowerType.LUNAR_POWER,
    lunar_power  = addon.PowerType.LUNAR_POWER,
    holypower    = addon.PowerType.HOLY_POWER,
    holy_power   = addon.PowerType.HOLY_POWER,
    maelstrom    = addon.PowerType.MAELSTROM,
    insanity     = addon.PowerType.INSANITY,
    fury         = addon.PowerType.FURY,
    pain         = addon.PowerType.PAIN,
}

local POWER_NAMES = {}
for k, v in pairs(addon.PowerType) do
    if POWER_NAMES[v] == nil then POWER_NAMES[v] = k end
end

function addon.ResolvePowerType(powerType)
    if type(powerType) == "number" then return powerType end
    if type(powerType) == "string" then
        return POWER_ALIASES[powerType:lower():gsub("%s+", "")]
    end
    return nil
end

function addon.GetPowerType(unit)
    unit = unit or "player"
    if type(UnitPowerType) ~= "function" then return nil, nil, false, false end
    local ok, pType, pToken = pcall(UnitPowerType, unit)
    if not ok then return nil, nil, false, false end
    local typeSecret = addon.IsSecretValue(pType)
    local tokenSecret = addon.IsSecretValue(pToken)
    local safeType = addon.SafeNumber(pType, nil)
    local safeToken = addon.SafeString(pToken, nil)
    return safeType, safeToken, safeType ~= nil, (typeSecret or tokenSecret)
end

-- Safe raw reader for UnitPower / UnitPowerMax / GetComboPoints.
-- Returns: current, max, pct, readable, isSecret
function addon.GetResource(powerType, unit)
    unit = unit or "player"
    local pType = addon.ResolvePowerType(powerType)
    if pType == nil then
        pType = addon.GetPowerType(unit)
        if pType == nil then return nil, nil, nil, false, false end
    end

    local cur, maxVal
    local anySecret = false

    if type(UnitPower) == "function" then
        local okC, rawC = pcall(UnitPower, unit, pType)
        if okC then
            if addon.IsSecretValue(rawC) then
                anySecret = true
            else
                cur = addon.SafeNumber(rawC, nil)
            end
        end
    end

    if type(UnitPowerMax) == "function" then
        local okM, rawM = pcall(UnitPowerMax, unit, pType)
        if okM then
            if addon.IsSecretValue(rawM) then
                anySecret = true
            else
                maxVal = addon.SafeNumber(rawM, nil)
            end
        end
    end

    -- Combo points: some Classic/Forever builds still expose target combo points
    -- via GetComboPoints("player", "target") even when UnitPower(player, 4) is 0/nil.
    if pType == addon.PowerType.COMBO_POINTS and type(GetComboPoints) == "function" then
        local needFallback = (cur == nil) or (cur == 0 and unit == "player")
        if needFallback then
            local okCP, rawCP = pcall(GetComboPoints, unit, "target")
            if okCP then
                if addon.IsSecretValue(rawCP) then
                    anySecret = true
                else
                    local cp = addon.SafeNumber(rawCP, nil)
                    if cp ~= nil and (cur == nil or cp > cur) then cur = cp end
                end
            end
            if cur == nil then
                local okCP2, rawCP2 = pcall(GetComboPoints, unit)
                if okCP2 then
                    if addon.IsSecretValue(rawCP2) then
                        anySecret = true
                    else
                        local cp2 = addon.SafeNumber(rawCP2, nil)
                        if cp2 ~= nil then cur = cp2 end
                    end
                end
            end
        end
        if maxVal == nil or maxVal <= 0 then maxVal = 5 end
    end

    -- Defensive scaling guard: if a build ever returns Rage on a 0..1000 scale,
    -- normalize it back to the standard 0..100 scale.
    if pType == addon.PowerType.RAGE and maxVal ~= nil and maxVal >= 900 then
        if cur ~= nil then cur = cur / 10 end
        maxVal = maxVal / 10
    end

    local readable = (cur ~= nil)
    local pct = nil
    if cur ~= nil and maxVal ~= nil and maxVal > 0 then
        pct = math.max(0, math.min(100, (cur / maxVal) * 100))
    end
    return cur, maxVal, pct, readable, anySecret
end

-- Reads spell power cost via C_Spell.GetSpellPowerCost / GetSpellPowerCost.
-- Returns table { cost, minCost, powerType, name, readable, isSecret } or nil.
function addon.GetSpellPowerCost(spellID)
    if type(spellID) ~= "number" then return nil end
    local id = (addon.Compat and addon.Compat.ResolveKnownID and addon.Compat.ResolveKnownID(spellID)) or spellID
    local costs
    if C_Spell and type(C_Spell.GetSpellPowerCost) == "function" then
        local ok, result = pcall(C_Spell.GetSpellPowerCost, id)
        if ok and type(result) == "table" then costs = result end
    end
    if not costs and type(GetSpellPowerCost) == "function" then
        local ok, result = pcall(GetSpellPowerCost, id)
        if ok and type(result) == "table" then costs = result end
    end
    if type(costs) ~= "table" or #costs == 0 then return nil end

    local activeType = addon.GetPowerType("player")
    local chosen
    for _, entry in ipairs(costs) do
        if type(entry) == "table" then
            local pType = addon.SafeNumber(entry.type, nil)
            if not chosen then chosen = entry end
            if activeType ~= nil and pType == activeType then
                chosen = entry
                break
            end
        end
    end
    if type(chosen) ~= "table" then return nil end

    local rawCost, rawMin, rawType, rawName
    pcall(function()
        rawCost = chosen.cost
        rawMin  = chosen.minCost
        rawType = chosen.type
        rawName = chosen.name
    end)

    local secret = addon.IsSecretValue(rawCost) or addon.IsSecretValue(rawMin) or addon.IsSecretValue(rawType)
    local cost = addon.SafeNumber(rawCost, nil)
    local minCost = addon.SafeNumber(rawMin, nil)
    local pType = addon.SafeNumber(rawType, nil)
    local pName = addon.SafeString(rawName, nil)
    local effectiveCost = (minCost and minCost > 0) and minCost or cost

    return {
        cost = cost,
        minCost = minCost,
        effectiveCost = effectiveCost,
        powerType = pType,
        name = pName or (pType and POWER_NAMES[pType]) or nil,
        readable = (effectiveCost ~= nil and pType ~= nil),
        isSecret = secret,
    }
end

-- Secret-safe wrapper for C_ActionBar.IsUsableAction / IsUsableAction.
-- Returns: isUsable, notEnoughPower, readable, isSecret, slot
function addon.CheckActionUsable(spellID)
    if type(spellID) ~= "number" or type(addon.FindActionSlot) ~= "function" then
        return nil, nil, false, false, nil
    end
    local knownID = (addon.Compat and addon.Compat.ResolveKnownID and addon.Compat.ResolveKnownID(spellID)) or spellID
    local slot = addon:FindActionSlot(knownID) or (knownID ~= spellID and addon:FindActionSlot(spellID) or nil)
    if not slot then return nil, nil, false, false, nil end

    local fn = (C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" and C_ActionBar.IsUsableAction)
        or (type(IsUsableAction) == "function" and IsUsableAction)
        or nil
    if not fn then return nil, nil, false, false, slot end

    local ok, rawUsable, rawNoPower = pcall(fn, slot)
    if not ok then return nil, nil, false, false, slot end
    local secret = addon.IsSecretValue(rawUsable) or addon.IsSecretValue(rawNoPower)
    local usable = addon.SafeBoolean(rawUsable, nil)
    local noPower = addon.SafeBoolean(rawNoPower, nil)
    local readable = (usable ~= nil or noPower ~= nil)
    return usable, noPower, readable, secret, slot
end

-- Authoritative resource-sufficiency check for a spell on WoW Forever.
-- Order:
--   1) C_Spell.IsSpellUsable (secret-safe)
--   2) C_ActionBar.IsUsableAction on the spell's action slot (secret-safe)
--   3) C_Spell.GetSpellPowerCost vs UnitPower (secret-safe)
--   4) Legacy IsUsableSpell (secret-safe)
--   5) Fail-open (true) when all APIs return secret/unreadable values so the
--      rotation is never starved during combat.
-- Returns: hasEnough (bool), source (string), details (table)
function addon.HasEnoughPowerForSpell(spellID, unit)
    unit = unit or "player"
    local details = { spellID = spellID }
    if type(spellID) ~= "number" then return true, "no_spell_id", details end

    local knownID = (addon.Compat and addon.Compat.ResolveKnownID and addon.Compat.ResolveKnownID(spellID)) or spellID
    details.knownID = knownID

    -- 1) C_Spell.IsSpellUsable
    if C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        local ok, rawUsable, rawNoPower = pcall(C_Spell.IsSpellUsable, knownID)
        if ok then
            details.spellUsableSecret = addon.IsSecretValue(rawUsable) or addon.IsSecretValue(rawNoPower)
            local usable = addon.SafeBoolean(rawUsable, nil)
            local noPower = addon.SafeBoolean(rawNoPower, nil)
            details.spellUsable = usable
            details.spellNotEnoughPower = noPower
            if noPower == true then
                return false, "C_Spell.IsSpellUsable(notEnoughPower)", details
            end
            if usable == true and noPower == false then
                return true, "C_Spell.IsSpellUsable(ok)", details
            end
        end
    end

    -- 2) Action bar slot usability
    local aUsable, aNoPower, aReadable, aSecret, slot = addon.CheckActionUsable(knownID)
    details.actionSlot = slot
    details.actionUsable = aUsable
    details.actionNotEnoughPower = aNoPower
    details.actionSecret = aSecret
    if aReadable then
        if aNoPower == true then
            return false, "IsUsableAction(notEnoughPower)", details
        end
        if aUsable == true and aNoPower == false then
            return true, "IsUsableAction(ok)", details
        end
    end

    -- 3) Direct power cost comparison via UnitPower
    local costInfo = addon.GetSpellPowerCost(knownID)
    details.costInfo = costInfo
    if costInfo and costInfo.readable and costInfo.effectiveCost then
        local cur, maxVal, _, readable, isSecret = addon.GetResource(costInfo.powerType, unit)
        details.resourceCurrent = cur
        details.resourceMax = maxVal
        details.resourceReadable = readable
        details.resourceSecret = isSecret
        if readable then
            local okPower = cur >= costInfo.effectiveCost
            return okPower, string.format("UnitPower(%s=%s>=%s)", tostring(costInfo.name or costInfo.powerType),
                tostring(cur), tostring(costInfo.effectiveCost)), details
        end
    end

    -- 4) Legacy IsUsableSpell
    if type(IsUsableSpell) == "function" then
        local name = addon.SpellName and addon.SpellName(knownID)
        if name then
            local ok, rawUsable, rawNoPower = pcall(IsUsableSpell, name)
            if ok then
                local usable = addon.SafeBoolean(rawUsable, nil)
                local noPower = addon.SafeBoolean(rawNoPower, nil)
                if noPower == true then return false, "IsUsableSpell(notEnoughPower)", details end
                if usable == true and noPower == false then return true, "IsUsableSpell(ok)", details end
            end
        end
    end

    -- 5) Fail-open when all resource probes are secret/unreadable
    return true, "unreadable_fail_open", details
end

-- Threshold checks (secret-safe, configurable fail-open/fail-closed).
-- For minimum resource checks ("do I have at least X rage/energy/mana?"),
-- failOpen defaults to true so secret values never starve the rotation.
function addon.HasResourceAtLeast(powerType, minAmount, unit, opts)
    opts = opts or {}
    local cur, _, _, readable, isSecret = addon.GetResource(powerType, unit)
    if readable then
        return cur >= (minAmount or 0), cur, true, "unit_power"
    end
    if opts.spellID then
        local okSpell, src = addon.HasEnoughPowerForSpell(opts.spellID, unit)
        return okSpell, nil, false, src
    end
    local failOpen = (opts.failOpen ~= false)
    return failOpen, nil, false, isSecret and "secret_fallback" or "unreadable_fallback"
end

-- For maximum resource checks ("am I low on rage/energy/mana?"),
-- failOpen defaults to false so recovery cooldowns aren't spammed blindly.
function addon.HasResourceAtMost(powerType, maxAmount, unit, opts)
    opts = opts or {}
    local cur, _, _, readable, isSecret = addon.GetResource(powerType, unit)
    if readable then
        return cur <= (maxAmount or 0), cur, true, "unit_power"
    end
    local failOpen = (opts.failOpen == true)
    return failOpen, nil, false, isSecret and "secret_fallback" or "unreadable_fallback"
end

function addon.HasResourcePctAtLeast(powerType, minPct, unit, opts)
    opts = opts or {}
    local _, _, pct, readable, isSecret = addon.GetResource(powerType, unit)
    if readable and pct ~= nil then
        return pct >= (minPct or 0), pct, true, "unit_power_pct"
    end
    local failOpen = (opts.failOpen ~= false)
    return failOpen, nil, false, isSecret and "secret_fallback" or "unreadable_fallback"
end

function addon.HasResourcePctAtMost(powerType, maxPct, unit, opts)
    opts = opts or {}
    local _, _, pct, readable, isSecret = addon.GetResource(powerType, unit)
    if readable and pct ~= nil then
        return pct <= (maxPct or 0), pct, true, "unit_power_pct"
    end
    local failOpen = (opts.failOpen == true)
    return failOpen, nil, false, isSecret and "secret_fallback" or "unreadable_fallback"
end

-- Convenience accessors usable by any class module.
function addon.GetMana(unit)        return addon.GetResource(addon.PowerType.MANA, unit) end
function addon.GetRage(unit)        return addon.GetResource(addon.PowerType.RAGE, unit) end
function addon.GetFocus(unit)       return addon.GetResource(addon.PowerType.FOCUS, unit) end
function addon.GetEnergy(unit)      return addon.GetResource(addon.PowerType.ENERGY, unit) end
function addon.GetComboPoints(unit) return addon.GetResource(addon.PowerType.COMBO_POINTS, unit) end
function addon.GetRunicPower(unit)  return addon.GetResource(addon.PowerType.RUNIC_POWER, unit) end

function addon.GetManaPct(unit)
    local _, _, pct, readable, isSecret = addon.GetResource(addon.PowerType.MANA, unit)
    return pct, readable, isSecret
end

function addon.HasRage(minAmount, spellID, opts)
    local o = type(opts) == "table" and opts or {}
    if spellID and not o.spellID then o.spellID = spellID end
    return addon.HasResourceAtLeast(addon.PowerType.RAGE, minAmount, "player", o)
end

function addon.HasEnergy(minAmount, spellID, opts)
    local o = type(opts) == "table" and opts or {}
    if spellID and not o.spellID then o.spellID = spellID end
    return addon.HasResourceAtLeast(addon.PowerType.ENERGY, minAmount, "player", o)
end

function addon.HasFocus(minAmount, spellID, opts)
    local o = type(opts) == "table" and opts or {}
    if spellID and not o.spellID then o.spellID = spellID end
    return addon.HasResourceAtLeast(addon.PowerType.FOCUS, minAmount, "player", o)
end

function addon.HasManaPct(minPct, opts)
    return addon.HasResourcePctAtLeast(addon.PowerType.MANA, minPct, "player", opts)
end

function addon.HasComboPoints(minAmount, opts)
    local o = type(opts) == "table" and opts or { failOpen = false }
    if o.failOpen == nil then o.failOpen = false end
    return addon.HasResourceAtLeast(addon.PowerType.COMBO_POINTS, minAmount, "player", o)
end

-- Populates standard resource fields on any module's `env` table.
function addon.PopulateEnvResources(env, unit)
    env = env or {}
    unit = unit or "player"

    local pType, pToken, pTypeReadable, pTypeSecret = addon.GetPowerType(unit)
    local mana, manaMax, manaPct, manaReadable, manaSecret = addon.GetMana(unit)
    local rage, rageMax, ragePct, rageReadable, rageSecret = addon.GetRage(unit)
    local focus, focusMax, focusPct, focusReadable, focusSecret = addon.GetFocus(unit)
    local energy, energyMax, energyPct, energyReadable, energySecret = addon.GetEnergy(unit)
    local combo, comboMax, comboPct, comboReadable, comboSecret = addon.GetComboPoints(unit)
    local runic, runicMax, runicPct, runicReadable, runicSecret = addon.GetRunicPower(unit)

    env.powerType      = pType
    env.powerToken     = pToken
    env.mana           = mana
    env.manaMax        = manaMax
    env.manaPct        = manaPct
    env.manaReadable   = manaReadable
    env.hasMana        = (manaMax ~= nil and manaMax > 0) or (pType == addon.PowerType.MANA)

    env.rage           = rage
    env.rageMax        = rageMax
    env.rageReadable   = rageReadable

    env.focus          = focus
    env.focusMax       = focusMax
    env.focusReadable  = focusReadable

    env.energy         = energy
    env.energyMax      = energyMax
    env.energyReadable = energyReadable

    env.combo          = combo
    env.comboPoints    = combo
    env.comboMax       = comboMax
    env.comboReadable  = comboReadable

    env.runicPower     = runic
    env.runicPowerMax  = runicMax

    env.resources = {
        powerType  = { value = pType, token = pToken, readable = pTypeReadable, isSecret = pTypeSecret },
        mana       = { current = mana,   max = manaMax,   pct = manaPct,   readable = manaReadable,   isSecret = manaSecret },
        rage       = { current = rage,   max = rageMax,   pct = ragePct,   readable = rageReadable,   isSecret = rageSecret },
        focus      = { current = focus,  max = focusMax,  pct = focusPct,  readable = focusReadable,  isSecret = focusSecret },
        energy     = { current = energy, max = energyMax, pct = energyPct, readable = energyReadable, isSecret = energySecret },
        combo      = { current = combo,  max = comboMax,  pct = comboPct,  readable = comboReadable,  isSecret = comboSecret },
        runicPower = { current = runic,  max = runicMax,  pct = runicPct,  readable = runicReadable,  isSecret = runicSecret },
    }
    return env
end

-- Diagnostic chat dump for /cfa res [spellID] (and /cfa maul).
function addon.DebugDumpResources(spellID)
    local function P(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("|cff44ddff[CFA res]|r " .. table.concat(parts, " "))
    end

    local _, cls = UnitClass("player")
    local combat = false
    if type(UnitAffectingCombat) == "function" then
        local ok, v = pcall(UnitAffectingCombat, "player")
        if ok and not addon.IsSecretValue(v) then combat = v == true end
    end
    local pType, pToken, pReadable, pSecret = addon.GetPowerType("player")
    P("===== DIAGNÓSTICO DE RECURSOS =====")
    P("class=", cls, "combat=", combat, "powerType=", pType, "token=", pToken,
        "readable=", pReadable, "secret=", pSecret)

    local list = {
        { "MANA",         addon.PowerType.MANA },
        { "RAGE",         addon.PowerType.RAGE },
        { "FOCUS",        addon.PowerType.FOCUS },
        { "ENERGY",       addon.PowerType.ENERGY },
        { "COMBO_POINTS", addon.PowerType.COMBO_POINTS },
        { "RUNIC_POWER",  addon.PowerType.RUNIC_POWER },
    }
    for _, entry in ipairs(list) do
        local cur, maxVal, pct, readable, isSecret = addon.GetResource(entry[2], "player")
        local pctStr = pct and string.format("%.1f%%", pct) or "nil"
        P(string.format("  %-12s cur=%-6s max=%-6s pct=%-7s readable=%-5s secret=%s",
            entry[1], tostring(cur), tostring(maxVal), pctStr, tostring(readable), tostring(isSecret)))
    end

    if type(GetShapeshiftFormID) == "function" or type(GetShapeshiftForm) == "function" then
        local okID, rawFID = pcall(GetShapeshiftFormID or function() return nil end)
        local okIdx, rawIdx = pcall(GetShapeshiftForm or function() return nil end)
        local fid = okID and addon.SafeNumber(rawFID, nil) or nil
        local fidx = okIdx and addon.SafeNumber(rawIdx, nil) or nil
        local activeMod = addon.activeModule
        local specKey, specSrc
        if activeMod and type(activeMod.DetectSpec) == "function" then
            local okS, sk, ss = pcall(activeMod.DetectSpec, activeMod)
            if okS then specKey, specSrc = sk, ss end
        end
        P("shapeshift: GetShapeshiftFormID=", fid, "GetShapeshiftForm=", fidx,
            "spec=", specKey, "source=", specSrc)
    end

    -- Default probe spell for Druid: Maul (6807)
    if not spellID and cls == "DRUID" then spellID = 6807 end
    if type(spellID) == "number" then
        local knownID = (addon.Compat and addon.Compat.ResolveKnownID and addon.Compat.ResolveKnownID(spellID)) or spellID
        local name = addon.SpellName and addon.SpellName(knownID)
        local known = addon.Compat and addon.Compat.SpellKnown and addon.Compat.SpellKnown(spellID)
        P("--- Spell probe:", spellID, "-> knownID=", knownID, "name=", name, "known=", known, "---")

        local costInfo = addon.GetSpellPowerCost(knownID)
        if costInfo then
            P("  GetSpellPowerCost: cost=", costInfo.cost, "minCost=", costInfo.minCost,
                "effective=", costInfo.effectiveCost, "powerType=", costInfo.powerType,
                "name=", costInfo.name, "readable=", costInfo.readable, "secret=", costInfo.isSecret)
        else
            P("  GetSpellPowerCost: nil")
        end

        local hasPower, powerSrc, powerDbg = addon.HasEnoughPowerForSpell(knownID, "player")
        P("  HasEnoughPowerForSpell:", hasPower, "source=", powerSrc,
            "spellUsable=", powerDbg.spellUsable, "spellNoPower=", powerDbg.spellNotEnoughPower,
            "spellSecret=", powerDbg.spellUsableSecret,
            "slot=", powerDbg.actionSlot, "actUsable=", powerDbg.actionUsable,
            "actNoPower=", powerDbg.actionNotEnoughPower, "actSecret=", powerDbg.actionSecret)

        local onCD = addon.IsSpellOnCD and addon:IsSpellOnCD(knownID)
        local inRange = addon.IsSpellInRangeEx and addon:IsSpellInRangeEx(knownID, "target")
        local isCurrent = name and addon.IsCurrentSpell and addon.IsCurrentSpell(name)
        P("  onCD=", onCD, "inRange(target)=", inRange, "isCurrent=", isCurrent)

        if name and addon.CheckIfSpellCastable then
            local dbg = {}
            local castOK = addon:CheckIfSpellCastable({
                SpellID = knownID,
                SpellName = name,
                EnemyTargetNeeded = true,
                Unit = "target",
                NotIfActive = (spellID == 6807),
                Debug = dbg,
            })
            P("  CheckIfSpellCastable:", castOK, "reason=", dbg.reason or "OK")
        end

        if cls == "DRUID" and addon.modules and addon.modules.DRUID then
            local mod = addon.modules.DRUID
            if type(mod.BuildEnv) == "function" and type(mod.DetectSpec) == "function" then
                local sk = mod:DetectSpec()
                local env = mod:BuildEnv(sk)
                local pred = mod.RotationPredicates and mod.RotationPredicates.bear_maul
                local predOK = pred and pred.fn and select(2, pcall(pred.fn, env))
                P("  Druid env: spec=", env.spec, "form=", env.form, "enemy=", env.hasActiveEnemy,
                    "feral_bear_enemy=", env.feral_bear_enemy, "rage=", env.rage,
                    "rageReadable=", env.rageReadable, "bear_maul=", predOK)
            end
        end
    end
    P("===== FIM DIAGNÓSTICO =====")
end
