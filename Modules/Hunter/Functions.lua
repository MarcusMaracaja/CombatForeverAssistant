-- Combat Forever Assistant — Hunter module: castable engine + aura beliefs.
local moduleName, module = ...

module.L = module.L
local L = module.L
local BuffLib = module.BuffLib

-- ---------------------------------------------------------------------------
-- Castable engine: given a table describing a spell to cast, answer "can I
-- cast this now?". Kept deliberately small: the rotation proves spells out by
-- checking conditions + range/CD before suggesting.
-- ---------------------------------------------------------------------------
module.Castable = module.Castable or {}

function module.SpellIDFromName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if module.Compat and module.Compat.SpellBookItem then
        for i = 1, 300 do
            local n, _ = module.Compat.SpellBookItem(i, "spell")
            if n == name then
                local ok, info = pcall(function()
                    if C_Spell and C_Spell.GetSpellInfo then
                        local o, i2 = pcall(C_Spell.GetSpellInfo, i)
                        return o and i2 and type(i2) == "table" and i2.spellID or nil
                    end
                end)
                return ok and info or nil
            end
            if n == nil then break end
        end
    end
    return nil
end

function module.SpellKnown(name)
    if module.Compat and module.Compat.SpellBookItem then
        for i = 1, 300 do
            local n, _ = module.Compat.SpellBookItem(i, "spell")
            if n == name then return true end
            if n == nil then break end
        end
        return false
    end
    return type(IsSpellKnown) == "function" and IsSpellKnown(name) or false
end

function module.IsOnCooldown(name, id)
    local known = id or module.SpellIDFromName(name)
    if known and C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, known)
        if ok and type(info) == "table" then
            local start = info.startTime
            local dur = info.duration
            if type(start) == "number" and type(dur) == "number"
                and start > 0 and duration > 0
                and (GetTime() - start) < dur then
                return true
            end
        end
    end
    return false
end

function module.CheckCastable(z)
    if type(z) ~= "table" then return false end
    local name = z.SpellName
    if type(name) ~= "string" or name == "" then return false end
    if z.EnemyTargetNeeded and not module.UnitTargetExistsAndAttackable() then return false end
    if z.TargetNotDead then
        if not UnitExists("target") then return false end
        local ok, dead = pcall(UnitIsDeadOrGhost, "target")
        if ok and dead then return false end
    end
    if not module.SpellKnown(name) then return false end
    if module.IsOnCooldown(name, z.SpellID) then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Aura helpers via BuffLib (aura IDs — UnitBuff reports auras in this client)
-- ---------------------------------------------------------------------------
function module.HasFamilyBuff(unit, family)
    if not BuffLib or not BuffLib.HasFamily then return false end
    return BuffLib:HasFamily(unit, family) and true or false
end

function module.HasFamilyDebuff(unit, family, onlyMine)
    if not BuffLib or not BuffLib.Has then return false end
    return BuffLib:Has(unit, family) and true or false
end

local function targetMana()
    if not UnitExists("target") then return 0 end
    local ok, t = pcall(UnitPowerType, "target")
    return ok and t or 0
end

function module.TargetUsesMana()
    return targetMana() == 0
end

function module.TargetIsMeleeClass()
    if not UnitExists("target") then return false end
    local _, cls = UnitClass("target")
    return cls == "WARRIOR" or cls == "ROGUE"
end

-- PvE silence/interrupt question: is the current enemy casting an
-- interruptible spell?
function module.IsTargetInterruptibleCasting(unit)
    unit = unit or "target"
    if type(UnitCastingInfo) ~= "function" then return false end
    local ok, name, _, _, _, _, canInterrupt = pcall(UnitCastingInfo, unit)
    if not ok or not name then return false end
    return canInterrupt and true or false
end

-- ---------------------------------------------------------------------------
-- Beliefs: track our own casts (UNIT_SPELLCAST_SUCCEEDED, filter "player")
-- instead of trusting UnitDebuff in combat (auras are secret there).
-- Slot counter increments on every PLAYER_TARGET_CHANGED — a new target
-- invalidates previous beliefs (GUID would be secret anyway).
-- ---------------------------------------------------------------------------
local markBeliefSlot = 0
module.MarkBelief = { slot = 0, active = false }
module.SerpentStingBelief = { slot = 0, applied = false, expires = 0 }
module.WingClipBelief = { slot = 0, applied = false, expires = 0 }
module.AspectBelief = nil
module.PET_IS_DEAD = false

-- Exposed so Scripts.lua can create the tracker frame (ordering: module load).
function module.OnTargetChanged()
    markBeliefSlot = markBeliefSlot + 1
    module.SerpentStingBelief.applied = false
    module.WingClipBelief.applied = false
end

function module.RegisterCast(castName)
    local base = (type(castName) == "string") and castName:lower():gsub("%s*%b()%s*$", "") or ""
    if base == "" then return end
    local function strip(id)
        local n = module.SpellName(id)
        if not n then return nil end
        return n:lower():gsub("%s*%b()%s*$", "")
    end
    if strip(1130) == base then
        module.MarkBelief.active = true
        module.MarkBelief.slot = markBeliefSlot
        return
    end
    if strip(1978) == base then
        module.SerpentStingBelief.applied = true
        module.SerpentStingBelief.slot = markBeliefSlot
        module.SerpentStingBelief.expires = GetTime() + 15
        return
    end
    if strip(2974) == base then
        module.WingClipBelief.applied = true
        module.WingClipBelief.slot = markBeliefSlot
        module.WingClipBelief.expires = GetTime() + 12
        return
    end
    if strip(3045) == base then -- Rapid Fire: pure self CD, no belief needed
        return
    end
    -- aspect tracking (auras are secret in combat)
    local ids = { 5118, 13159, 13161, 13163, 13165, 20043 }
    for _, id in ipairs(ids) do
        if strip(id) == base then
            module.AspectBelief = { active = true, name = base }
            return
        end
    end
end

function module.IsMarkedByUs()
    return module.MarkBelief.active and module.MarkBelief.slot == markBeliefSlot
end

function module.IsSerpentStingActive(unit)
    unit = unit or "target"
    if unit == "target" then
        local b = module.SerpentStingBelief
        if b.applied and b.slot == markBeliefSlot and GetTime() < b.expires then
            return true
        end
        b.applied = false
    end
    return module.HasFamilyBuff(unit, "SerpentSting")
end

local function stripAspectName(n)
    if type(n) ~= "string" then return "" end
    return n:lower():gsub("%s*%b()%s*$", "")
end

-- Debuff readable by name (out of combat / not secret). Returns false in
-- combat when auras are secret — callers use beliefs there.
function module.HasDebuff(unit, name)
    if type(UnitDebuff) ~= "function" then return false end
    if type(name) ~= "string" or name == "" then return false end
    local want = name:lower():gsub("%s*%b()%s*$", "")
    for i = 1, 40 do
        local ok, n = pcall(UnitDebuff, unit, i)
        if not ok or not n then return false end
        if _G.issecretvalue and issecretvalue(n) then break end
        if n == name then return true end
        if n:lower():gsub("%s*%b()%s*$", "") == want then return true end
    end
    return false
end

function module.IsWingClipActive(unit)
    unit = unit or "target"
    if unit == "target" then
        local b = module.WingClipBelief
        if b.applied and b.slot == markBeliefSlot and GetTime() < b.expires then
            return true
        end
        b.applied = false
        return module.HasDebuff(unit, "Wing Clip")
    end
    return module.HasDebuff(unit, "Wing Clip")
end

function module.IsClipped(unit)
    return module.IsWingClipActive(unit)
end

function module.IsAspectActive()
    -- out of combat, auras are readable; in combat, use our last cast belief
    if module.HasFamilyBuff("player", "AspectOfTheBeast")
        or module.HasFamilyBuff("player", "AspectOfTheCheetah")
        or module.HasFamilyBuff("player", "AspectOfTheHawk")
        or module.HasFamilyBuff("player", "AspectOfTheMonkey")
        or module.HasFamilyBuff("player", "AspectOfThePack")
        or module.HasFamilyBuff("player", "AspectOfTheWild") then
        return true
    end
    return module.AspectBelief and module.AspectBelief.active or false
end

function module.IsAspectOfHawkActive()
    return module.HasFamilyBuff("player", "AspectOfTheHawk")
        or (module.AspectBelief and module.AspectBelief.active
            and module.AspectBelief.name == stripAspectName(module.SpellName(13165)))
end

function module.IsAspectOfBeastActive()
    return module.HasFamilyBuff("player", "AspectOfTheBeast")
end
function module.IsAspectOfMonkeyActive()
    return module.HasFamilyBuff("player", "AspectOfTheMonkey")
end
function module.IsAspectOfCheetahActive()
    return module.HasFamilyBuff("player", "AspectOfTheCheetah")
end
function module.IsAspectOfPackActive()
    return module.HasFamilyBuff("player", "AspectOfThePack")
end
function module.IsAspectOfWildActive()
    return module.HasFamilyBuff("player", "AspectOfTheWild")
end

function module.IsMarked(unit)
    unit = unit or "target"
    return module.HasFamilyBuff(unit, "HuntersMark") or module.HasDebuff(unit, "Hunter's Mark")
end
