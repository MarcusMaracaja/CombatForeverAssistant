-- Combat Forever Assistant — Hunter module: class-specific mechanics.
-- Aspects, Hunter's Mark, stings, Wing Clip, Rapid Fire, combat cast beliefs,
-- and Hunter-only rotation predicates. Isolated inside addon.modules.HUNTER.
local _, addon = ...

local Hunter = addon.modules.HUNTER or {}
addon.modules.HUNTER = Hunter
Hunter.classTag = "HUNTER"
Hunter.addon = addon
Hunter.Compat = addon.Compat
Hunter.L = addon.L

-- Shared delegates expected by Core (e.g. SuggestRacial) and rotation nodes
Hunter.SpellName = addon.SpellName
Hunter.CheckCastable = addon.CheckCastable

-- ---------------------------------------------------------------------------
-- Beliefs: track our own casts (UNIT_SPELLCAST_SUCCEEDED, filter "player")
-- instead of trusting UnitDebuff in combat (auras are secret there).
-- Slot counter increments on every PLAYER_TARGET_CHANGED — a new target
-- invalidates previous beliefs (GUID would be secret anyway).
-- ---------------------------------------------------------------------------
local markBeliefSlot = 0
-- Keep Rapid Fire suppressed through its standard cooldown if client data is missing or stale.
local RAPID_FIRE_COOLDOWN = 300
Hunter.MarkBelief = { slot = 0, active = false }
Hunter.SerpentStingBelief = { slot = 0, applied = false, expires = 0 }
Hunter.WingClipBelief = { slot = 0, applied = false, expires = 0 }
Hunter.AspectBelief = nil
Hunter.RapidFireBelief = nil
Hunter.PET_IS_DEAD = false

local function stripAspectName(n)
    if type(n) ~= "string" then return "" end
    return n:lower():gsub("%s*%b()%s*$", "")
end

local function matchesAspectBelief(belief, id, base)
    if type(belief) ~= "table" then return false end
    return belief.id == id or (base ~= "" and stripAspectName(belief.name) == base)
end

-- Exposed so Scripts.lua can drive beliefs from the tracker frame.
function Hunter.OnTargetChanged()
    markBeliefSlot = markBeliefSlot + 1
    Hunter.SerpentStingBelief.applied = false
    Hunter.WingClipBelief.applied = false
end

function Hunter.RegisterCast(castName, castID)
    if type(castName) ~= "string" or castName == ""
        or (_G.issecretvalue and issecretvalue(castName)) then
        castName = nil
    end
    if type(castID) ~= "number" or (_G.issecretvalue and issecretvalue(castID)) then
        castID = nil
    end
    if not castName and not castID then return end
    local base = castName and stripAspectName(castName) or nil
    local function strip(id)
        local n = addon.SpellName(id)
        if not n then return nil end
        return stripAspectName(n)
    end
    if base and strip(1130) == base then
        Hunter.MarkBelief.active = true
        Hunter.MarkBelief.slot = markBeliefSlot
        return
    end
    if base and strip(1978) == base then
        Hunter.SerpentStingBelief.applied = true
        Hunter.SerpentStingBelief.slot = markBeliefSlot
        Hunter.SerpentStingBelief.expires = GetTime() + 15
        return
    end
    if base and strip(2974) == base then
        Hunter.WingClipBelief.applied = true
        Hunter.WingClipBelief.slot = markBeliefSlot
        Hunter.WingClipBelief.expires = GetTime() + 12
        return
    end
    if (base and strip(3045) == base) or castID == 3045 then
        local castAt = GetTime()
        Hunter.RapidFireBelief = { expires = castAt + RAPID_FIRE_COOLDOWN }
        return
    end
    -- Aspect tracking (auras are secret in combat). Persisted per character:
    -- aspects don't expire on their own, so the belief can outlive /reload.
    local ids = { 5118, 13159, 13161, 13163, 13165, 20043 }
    for _, id in ipairs(ids) do
        local knownID = addon.Compat and addon.Compat.HighestKnownSpellID
            and addon.Compat.HighestKnownSpellID(id)
        local family = addon.Compat and addon.Compat.FamilyOf
        local sameFamily = castID and family and family[castID] ~= nil
            and family[castID] == family[id]
        local idMatch = castID and (castID == id or (knownID and castID == knownID) or sameFamily)
        if (base and strip(id) == base) or idMatch then
            local aspectName = strip(id) or base or ""
            Hunter.AspectBelief = { active = true, name = aspectName, id = id, time = GetTime() }
            if addon.charDb then
                addon.charDb.aspectBelief = { id = id, name = aspectName, time = GetTime() }
            end
            return
        end
    end
end

function Hunter.IsRapidFireSuppressed()
    local belief = Hunter.RapidFireBelief
    if not belief then
        local name = addon.SpellName(3045)
        return name ~= nil and addon.Compat.CheckBuff(name, "player") or false
    end

    local now = GetTime()
    local onCooldown, remaining = addon:IsSpellOnCooldown(3045)
    if onCooldown then
        belief.expires = now + remaining
        return true
    end
    local name = addon.SpellName(3045)
    if name and addon.Compat.CheckBuff(name, "player") then return true end
    if now < belief.expires then return true end

    Hunter.RapidFireBelief = nil
    return false
end

function Hunter.IsMarkedByUs()
    return Hunter.MarkBelief.active and Hunter.MarkBelief.slot == markBeliefSlot
end

function Hunter.IsSerpentStingActive(unit)
    unit = unit or "target"
    if unit == "target" then
        local b = Hunter.SerpentStingBelief
        if b.applied and b.slot == markBeliefSlot and GetTime() < b.expires then
            return true
        end
        b.applied = false
    end
    return addon.HasFamilyBuff(unit, "SerpentSting")
end

-- Aura API readable? (outside combat yes; in combat the whole payload is secret)
function Hunter.AspectAuraReadable()
    local BuffLib = addon.BuffLib
    if not BuffLib or not BuffLib.Status then return false end
    local st = BuffLib:Status("player", "AspectOfTheHawk")
    return st and st.readable and true or false
end

-- Aspect semantics (git proven logic):
--  1) live aura on player (localized name / spellID via C_UnitAuras + BuffLib);
--  2) when aura API is readable (out of combat), reconcile/clear stale beliefs
--     so manually cancelled aspects are detected immediately;
--  3) in combat (secret auras), trust session belief and persisted charDb belief.
local function aspectActive(family, id)
    local name = addon.SpellName(id)
    local base = stripAspectName(name)
    if addon.HasBuff("player", id) then return true end
    if addon.HasFamilyBuff("player", family) then return true end
    local b = Hunter.AspectBelief
    local cb = addon.charDb and addon.charDb.aspectBelief
    local matchesBelief = (b and b.active and matchesAspectBelief(b, id, base))
        or matchesAspectBelief(cb, id, base)
    if Hunter.AspectAuraReadable() then
        if matchesBelief then
            Hunter.AspectBelief = nil
            if addon.charDb then addon.charDb.aspectBelief = nil end
        end
        return false
    end
    if b and b.active and matchesAspectBelief(b, id, base) then return true end
    if matchesAspectBelief(cb, id, base) then return true end
    return false
end

function Hunter.IsWingClipActive(unit)
    unit = unit or "target"
    if unit == "target" then
        local b = Hunter.WingClipBelief
        if b.applied and b.slot == markBeliefSlot and GetTime() < b.expires then
            return true
        end
        b.applied = false
        return addon.HasDebuff(unit, 2974) or addon.HasDebuff(unit, "Wing Clip")
    end
    return addon.HasDebuff(unit, 2974) or addon.HasDebuff(unit, "Wing Clip")
end

function Hunter.IsClipped(unit)
    return Hunter.IsWingClipActive(unit)
end

function Hunter.IsAspectIDActive(id, family)
    return aspectActive(family or "Generic", id)
end

function Hunter.IsAspectOfCheetahActive() return Hunter.IsAspectIDActive(5118, "AspectOfTheCheetah") end
function Hunter.IsAspectOfPackActive()    return Hunter.IsAspectIDActive(13159, "AspectOfThePack") end
function Hunter.IsAspectOfHawkActive()    return Hunter.IsAspectIDActive(13165, "AspectOfTheHawk") end
function Hunter.IsAspectOfMonkeyActive()  return Hunter.IsAspectIDActive(13163, "AspectOfTheMonkey") end
function Hunter.IsAspectOfBeastActive()   return Hunter.IsAspectIDActive(13161, "AspectOfTheBeast") end
function Hunter.IsAspectOfWildActive()    return Hunter.IsAspectIDActive(20043, "AspectOfTheWild") end

function Hunter.IsAspectActive()
    return Hunter.IsAspectOfHawkActive()
        or Hunter.IsAspectOfCheetahActive()
        or Hunter.IsAspectOfMonkeyActive()
        or Hunter.IsAspectOfBeastActive()
        or Hunter.IsAspectOfPackActive()
        or Hunter.IsAspectOfWildActive()
end

function Hunter.IsMarked(unit)
    unit = unit or "target"
    return addon.HasFamilyBuff(unit, "HuntersMark")
        or addon.HasDebuff(unit, 1130)
        or addon.HasDebuff(unit, "Hunter's Mark")
end

-- ---------------------------------------------------------------------------
-- Revive Pet — só sugere quando o pet está morto (com ou sem corpo).
-- ---------------------------------------------------------------------------
Hunter.Castable = Hunter.Castable or {}
Hunter.Castable["Revive Pet"] = function()
    if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then return false end
    if not UnitExists("pet") and not Hunter.PET_IS_DEAD then return false end
    return addon.CheckCastable({
        SpellName = addon.SpellName(34497),
        SpellID = 34497,
        EnemyTargetNeeded = false,
    })
end

-- ---------------------------------------------------------------------------
-- Predicados específicos do Hunter (herda predicados genéricos de Shared).
-- ---------------------------------------------------------------------------
local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end
local function hasActiveEnemy(env) return env.hasActiveEnemy and true or false end

Hunter.RotationPredicates = setmetatable(Hunter.RotationPredicates or {}, {
    __index = addon.RotationPredicates,
})
local P = Hunter.RotationPredicates

P["pet_interruptible"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        if not env.petAlive then return false end
        return addon.IsTargetInterruptibleCasting("target") or false
    end,
    label = LBL("Pet viva, alvo conjurando", "Pet alive, target casting"),
}
P["pvp_target_mana"] = {
    fn = function(env)
        if not (env.isPvP and hasActiveEnemy(env)) then return false end
        return type(UnitPowerType) == "function" and UnitPowerType("target") == 0 or false
    end,
    label = LBL("PvP, alvo usa mana", "PvP, mana target"),
}
P["pvp_target_melee_class"] = {
    fn = function(env)
        if not (env.isPvP and hasActiveEnemy(env)) then return false end
        local _, cls = UnitClass("target")
        return (cls == "WARRIOR" or cls == "ROGUE") and true or false
    end,
    label = LBL("PvP, alvo corpo a corpo", "PvP, melee target"),
}
P["viper_pvp_mana"] = {
    fn = function(env)
        if not P["pvp_target_mana"].fn(env) then return false end
        return not addon.HasFamilyBuff("target", "ViperSting")
    end,
    label = LBL("PvP mana, sem Viper Sting", "PvP mana, no Viper Sting"),
}
P["scorpid_pvp_melee"] = {
    fn = function(env)
        if not P["pvp_target_melee_class"].fn(env) then return false end
        return not addon.HasFamilyBuff("target", "ScorpidSting")
    end,
    label = LBL("PvP melee, sem Scorpid Sting", "PvP melee, no Scorpid Sting"),
}
P["no_serpent_pve"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.isMelee and not env.isPvP) then return false end
        return not Hunter.IsSerpentStingActive("target")
    end,
    label = LBL("PvE, sem Serpent Sting", "PvE, no Serpent Sting"),
}
P["no_serpent_mm"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.isMelee) then return false end
        return not Hunter.IsSerpentStingActive("target")
    end,
    label = LBL("Sem Serpent Sting", "No Serpent Sting"),
}
P["no_any_sting"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        if Hunter.IsSerpentStingActive("target") then return false end
        if addon.HasFamilyBuff("target", "ViperSting") then return false end
        if addon.HasFamilyBuff("target", "ScorpidSting") then return false end
        return true
    end,
    label = LBL("Sem nenhuma Sting", "No Sting active"),
}
P["trap_melee_or_close"] = {
    fn = function(env)
        if not hasActiveEnemy(env) then return false end
        return env.isMelee or env.tooCloseForRanged
    end,
    label = LBL("Trap curta distância", "Trap close range"),
}
P["pvp_not_clipped_melee"] = {
    fn = function(env)
        if not (env.tooCloseForRanged or env.isMelee) then return false end
        if not env.isPvP then return false end
        return not Hunter.IsClipped("target")
    end,
    label = LBL("PvP melee, sem Wing Clip", "PvP melee, no Wing Clip"),
}
P["melee_enemy_interruptible"] = {
    fn = function(env)
        if not (env.isMelee and hasActiveEnemy(env)) then return false end
        return addon.IsTargetInterruptibleCasting("target") or false
    end,
    label = LBL("Melee, alvo conjurando", "Melee, target casting"),
}
P["pvp_hp30"] = {
    fn = function(env)
        if not env.isPvP then return false end
        local hp = env.myHP or 100
        if hp >= 30 then return false end
        return not addon.HasFamilyBuff("player", "Deterrence")
    end,
    label = LBL("PvP, HP < 30%", "PvP, HP < 30%"),
}
