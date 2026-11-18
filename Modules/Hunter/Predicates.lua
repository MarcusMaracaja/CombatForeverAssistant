-- Combat Forever Assistant — Hunter module: declarative rotation predicates.
-- Each predicate answers "should this node flash?" from (env). Names are
-- referenced from Scripts_SV/BM/MM.lua as strings.
local moduleName, module = ...

local L = module.L
module.RotationPredicates = module.RotationPredicates or {}
local P = module.RotationPredicates

local function hasActiveEnemy(env) return env.hasActiveEnemy and true or false end

P["always"] = { fn = function(env) return true end }

P["is_aoe"] = { fn = function(env) return env.isAoE and true or false end }

P["not_too_close_ranged"] = {
    fn = function(env) return not env.tooCloseForRanged end,
}
P["aoe_not_too_close"] = {
    fn = function(env) return env.isAoE and not env.tooCloseForRanged end,
}
P["aoe_not_pvp_mana15"] = {
    fn = function(env) return env.isAoE and not env.isPvP and (env.manaPct or 100) > 15 end,
}
P["not_aoe_not_too_close"] = {
    fn = function(env) return hasActiveEnemy(env) and not env.tooCloseForRanged and not env.isAoE end,
}
P["enemy_in_combat_not_too_close"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        return type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") and true or false
    end,
}
P["enemy_interruptible_not_cc"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        return module.IsTargetInterruptibleCasting and module.IsTargetInterruptibleCasting("target") or false
    end,
}
P["pet_interruptible"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        if not env.petAlive then return false end
        return module.IsTargetInterruptibleCasting and module.IsTargetInterruptibleCasting("target") or false
    end,
}
P["pvp_target_mana"] = {
    fn = function(env)
        if not (env.isPvP and hasActiveEnemy(env)) then return false end
        return type(UnitPowerType) == "function" and UnitPowerType("target") == 0 or false
    end,
}
P["pvp_target_melee_class"] = {
    fn = function(env)
        if not (env.isPvP and hasActiveEnemy(env)) then return false end
        local _, cls = UnitClass("target")
        return (cls == "WARRIOR" or cls == "ROGUE") and true or false
    end,
}
P["viper_pvp_mana"] = {
    fn = function(env)
        if not P["pvp_target_mana"].fn(env) then return false end
        return not module.HasFamilyBuff("target", "ViperSting")
    end,
}
P["scorpid_pvp_melee"] = {
    fn = function(env)
        if not P["pvp_target_melee_class"].fn(env) then return false end
        return not module.HasFamilyBuff("target", "ScorpidSting")
    end,
}
P["no_serpent_pve"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.isMelee and not env.isPvP) then return false end
        return not module.IsSerpentStingActive("target")
    end,
}
P["no_serpent_mm"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.isMelee) then return false end
        return not module.IsSerpentStingActive("target")
    end,
}
P["no_any_sting"] = {
    fn = function(env)
        if not (hasActiveEnemy(env) and not env.tooCloseForRanged) then return false end
        if module.IsSerpentStingActive("target") then return false end
        if module.HasFamilyBuff("target", "ViperSting") then return false end
        if module.HasFamilyBuff("target", "ScorpidSting") then return false end
        return true
    end,
}
P["melee_or_close"] = {
    fn = function(env) return env.tooCloseForRanged or env.isMelee end,
}
P["dead_zone_not_melee"] = {
    fn = function(env) return env.tooCloseForRanged and not env.isMelee end,
}
P["pvp_not_clipped_melee"] = {
    fn = function(env)
        if not (env.tooCloseForRanged or env.isMelee) then return false end
        if not env.isPvP then return false end
        return not module.IsClipped("target")
    end,
}
P["melee_enemy_interruptible"] = {
    fn = function(env)
        if not (env.isMelee and hasActiveEnemy(env)) then return false end
        return module.IsTargetInterruptibleCasting and module.IsTargetInterruptibleCasting("target") or false
    end,
}
P["within_8_aoe"] = {
    fn = function(env) return env.targetDistance and env.targetDistance <= 8 and env.hasActiveEnemy and env.isAoE end,
}
P["within_8_st"] = {
    fn = function(env) return env.targetDistance and env.targetDistance <= 8 and env.hasActiveEnemy and not env.isAoE end,
}
P["pvp_hp30"] = {
    fn = function(env)
        if not env.isPvP then return false end
        local hp = env.myHP or 100
        if hp >= 30 then return false end
        return not module.HasFamilyBuff("player", "Deterrence")
    end,
}
