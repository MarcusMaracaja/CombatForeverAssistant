-- Combat Forever Assistant — Hunter module: Marksmanship rotation (declared data).
-- Order: shared melee/dead-zone prefix, then the Forever MM chain:
--   Scatter Shot -> Rapid Fire / Sniper Shot -> Aimed (single target) ->
--   Multi-Shot / Volley (AoE) -> Stings -> Arcane Shot.
local _, addon = ...

local Hunter = addon.modules.HUNTER
Hunter.RotationSpecs = Hunter.RotationSpecs or {}

Hunter.RotationSpecs.MM = {
    title = "Marksmanship",
    nodes = addon:ConcatCommonNodes(Hunter.HunterMeleeNodes, {
        { id = "scatter_shot",   spellID = 19503,   name = "Scatter Shot",   color = "Interrupt", condition = "enemy_interruptible_not_cc" },
        { id = "rapid_fire",     spellID = 3045,    name = "Rapid Fire",     color = "Damage",    condition = "enemy_in_combat_not_too_close", passthrough = true },
        { id = "sniper_shot",    spellID = 1310786, name = "Sniper Shot",    color = "Damage",    condition = "enemy_in_combat_not_too_close", passthrough = true },
        { id = "aimed_shot",     spellID = 19434,   name = "Aimed Shot",     color = "Damage",    condition = "not_aoe_not_too_close" },
        { id = "multi_shot",     spellID = 2643,    name = "Multi-Shot",     color = "AoE",       condition = "is_aoe" },
        { id = "volley",         spellID = 1510,    name = "Volley",         color = "AoE",       condition = "aoe_not_pvp_mana15" },
        { id = "viper_sting",    spellID = 3034,    name = "Viper Sting",    color = "Utility",   condition = "viper_pvp_mana" },
        { id = "scorpid_sting",  spellID = 3043,    name = "Scorpid Sting",  color = "Utility",   condition = "scorpid_pvp_melee" },
        { id = "serpent_sting",  spellID = 1978,    name = "Serpent Sting",  color = "Damage",    condition = "no_serpent_mm" },
        { id = "arcane_shot",    spellID = 3044,    name = "Arcane Shot",    color = "Damage",    condition = "not_too_close_ranged" },
    }),
}
