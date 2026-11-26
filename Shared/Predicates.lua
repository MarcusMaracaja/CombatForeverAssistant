-- Combat Forever Assistant — Shared rotation predicates (generic layer).
-- Predicates here are reusable by ANY class module (Hunter, Shaman, Druid,
-- future classes). Class-specific predicates (Wing Clip, Stings, Deterrence,
-- Totems, Shapeshift, etc.) stay inside Modules/<Class>/.
--
-- Each predicate is a table: { fn = function(env) return boolean end, label = "..." }
local _, addon = ...

addon.RotationPredicates = addon.RotationPredicates or {}
local P = addon.RotationPredicates

local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end

local function hasActiveEnemy(env) return env.hasActiveEnemy and true or false end

-- ---------------------------------------------------------------------------
-- Generic predicates
-- ---------------------------------------------------------------------------
P["always"] = {
    fn = function() return true end,
    label = LBL("Sempre", "Always"),
}

P["is_aoe"] = {
    fn = function(env) return env.isAoE and true or false end,
    label = LBL("Área (2+)", "AoE (2+)"),
}

P["melee_only"] = {
    fn = function(env) return hasActiveEnemy(env) and env.isMelee and true or false end,
    label = LBL("Melee real", "Actual melee range"),
}

P["melee_or_close"] = {
    fn = function(env) return env.tooCloseForRanged or env.isMelee end,
    label = LBL("Melee/perto", "Melee/close"),
}

P["not_too_close_ranged"] = {
    fn = function(env) return not env.tooCloseForRanged end,
    label = LBL("Fora do melee", "Outside melee"),
}

P["aoe_not_too_close"] = {
    fn = function(env) return env.isAoE and not env.tooCloseForRanged end,
    label = LBL("AoE fora do melee", "AoE outside melee"),
}

P["aoe_not_pvp_mana15"] = {
    fn = function(env)
        local hasMana = type(addon.HasManaPct) == "function" and (addon.HasManaPct(15)) or ((env.manaPct or 100) > 15)
        return env.isAoE and not env.isPvP and hasMana
    end,
    label = LBL("AoE PvE (mana > 15%)", "AoE PvE (mana > 15%)"),
}

P["not_aoe_not_too_close"] = {
    fn = function(env) return hasActiveEnemy(env) and not env.tooCloseForRanged and not env.isAoE end,
    label = LBL("Alvo único ranged", "Single target ranged"),
}

P["enemy_in_combat_not_too_close"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        return type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") and true or false
    end,
    label = LBL("Inimigo em combate (ranged)", "Enemy in combat (ranged)"),
}

P["enemy_interruptible_not_cc"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        return addon.IsTargetInterruptibleCasting and addon.IsTargetInterruptibleCasting("target") or false
    end,
    label = LBL("Alvo conjurando (ranged)", "Target casting (ranged)"),
}

P["within_8_aoe"] = {
    fn = function(env) return env.targetDistance and env.targetDistance <= 8 and env.hasActiveEnemy and env.isAoE end,
    label = LBL("Área a 8 yd", "AoE within 8 yd"),
}

P["within_8_st"] = {
    fn = function(env) return env.targetDistance and env.targetDistance <= 8 and env.hasActiveEnemy and not env.isAoE end,
    label = LBL("Alvo único a 8 yd", "Single target within 8 yd"),
}

P["dead_zone_not_melee"] = {
    -- Zona morta (5-10 yd): corpo a corpo não alcança e alcance longo não funciona.
    fn = function(env)
        if env.isDeadZone ~= nil then return env.isDeadZone and true or false end
        return env.tooCloseForRanged and not env.isMelee and true or false
    end,
    label = LBL("Zona morta", "Dead zone"),
}
