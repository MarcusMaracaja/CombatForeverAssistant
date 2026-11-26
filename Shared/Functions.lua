-- Combat Forever Assistant — Shared utility functions (generic layer).
-- Exposed on the global addon namespace so ANY class module (Hunter, Shaman,
-- Druid, future classes) can consume them without duplicating code or
-- depending on another class folder.
--
-- Load order: after Core.lua, before Shared\Predicates.lua and class modules.
local _, addon = ...

-- ---------------------------------------------------------------------------
-- Safe number & string guards (WoW Forever degrades reads to secret values).
-- ---------------------------------------------------------------------------
function addon.SafeNumber(v, fallback)
    if type(v) ~= "number" then return fallback end
    if _G.issecretvalue and issecretvalue(v) then return fallback end
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
