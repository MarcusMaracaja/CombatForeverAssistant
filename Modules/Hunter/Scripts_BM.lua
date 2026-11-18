-- Combat Forever Assistant — Hunter module: Beast Mastery rotation (declared data).
-- Order: shared melee/dead-zone prefix, then the Forever BM chain:
--   Intimidation -> Scatter Shot -> Bestial Wrath / Rapid Fire -> Stings ->
--   Multi-Shot -> Aimed (single target) -> Arcane -> Volley.
local moduleName, module = ...

local Hunter = module
Hunter.RotationSpecs = Hunter.RotationSpecs or {}

Hunter.RotationSpecs.BM = {
    title = "Beast Mastery",
    nodes = module:ConcatCommonNodes(Hunter.HunterMeleeNodes, {
        { id = "intimidation",  spellID = 19577, name = "Intimidation",  color = "Interrupt", condition = "pet_interruptible" },
        { id = "scatter_shot",  spellID = 19503, name = "Scatter Shot",  color = "Interrupt", condition = "enemy_interruptible_not_cc" },
        { id = "bestial_wrath", spellID = 19574, name = "Bestial Wrath", color = "Damage",    condition = "enemy_in_combat_not_too_close", passthrough = true },
        { id = "rapid_fire",    spellID = 3045,  name = "Rapid Fire",    color = "Damage",    condition = "enemy_in_combat_not_too_close", passthrough = true },
        { id = "viper_sting",   spellID = 3034,  name = "Viper Sting",   color = "Utility",   condition = "viper_pvp_mana" },
        { id = "scorpid_sting", spellID = 3043,  name = "Scorpid Sting", color = "Utility",   condition = "scorpid_pvp_melee" },
        { id = "serpent_sting", spellID = 1978,  name = "Serpent Sting", color = "Damage",    condition = "no_any_sting" },
        { id = "multi_shot",    spellID = 2643,  name = "Multi-Shot",    color = "AoE",       condition = "is_aoe" },
        { id = "aimed_shot",    spellID = 19434, name = "Aimed Shot",    color = "Damage",    condition = "not_aoe_not_too_close" },
        { id = "arcane_shot",   spellID = 3044,  name = "Arcane Shot",   color = "Damage",    condition = "not_too_close_ranged" },
        { id = "volley",        spellID = 1510,  name = "Volley",        color = "AoE",       condition = "aoe_not_pvp_mana15" },
    }),
}
