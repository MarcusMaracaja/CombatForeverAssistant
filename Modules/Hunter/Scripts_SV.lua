-- Combat Forever Assistant — Hunter module: Survival rotation (declared data).
-- Order: shared melee/dead-zone prefix, then the Forever SV chain:
--   Deterrence -> Scatter Shot -> Rapid Fire -> Viper/Scorpid (PvP) ->
--   Multi-Shot/Aimed -> Serpent -> Arcane -> Volley.
-- Chute de Moa (Strider Kick, 1317257): talento de Survival, nível 30.
-- Dano de arma corpo a corpo (100%), cooldown 8s, +30% velocidade 3s.
local moduleName, module = ...

local Hunter = module
Hunter.RotationModuleName = "CombatForeverAssistant"
Hunter.RotationSpecs = Hunter.RotationSpecs or {}

-- A ordem é intencional: Contra-ataque é reativo e só entra quando a API o
-- considera utilizável; Mangusto e Raptor exigem melee real. Armadilhas mantêm
-- seus gates de alvo/cast/AoE/distância, sem exigir alvo hostil no gate global.
Hunter.HunterMeleeNodes = {
    { id = "disengage",       spellID = 781,   name = "Disengage",       color = "Defensive", condition = "dead_zone_not_melee" },
    { id = "strider_kick",    spellID = 1317257, name = "Chute de Moa",  color = "Damage",    condition = "melee_only",    opts = { noRange = true }, passthrough = true },
    { id = "counterattack",   spellID = 19306, name = "Counterattack",   color = "Damage",     condition = "melee_or_close", opts = { noRange = true, notIfActive = true } },
    { id = "mongoose_bite",   spellID = 1495,  name = "Mongoose Bite",   color = "Damage",     condition = "melee_only",     opts = { noRange = true } },
    { id = "raptor_strike",   spellID = 2973,  name = "Raptor Strike",   color = "Damage",     condition = "melee_only",     opts = { noRange = true, notIfActive = true } },
    { id = "wing_clip",       spellID = 2974,  name = "Wing Clip",       color = "Interrupt",  condition = "pvp_not_clipped_melee" },
    { id = "freezing_trap",   spellID = 1499,  name = "Freezing Trap",   color = "Interrupt", condition = "melee_enemy_interruptible", opts = { noEnemy = true } },
    { id = "explosive_trap",  spellID = 13813, name = "Explosive Trap",  color = "AoE",        condition = "within_8_aoe",             opts = { noEnemy = true } },
    { id = "immolation_trap", spellID = 13795, name = "Immolation Trap", color = "AoE",        condition = "trap_melee_or_close", opts = { noEnemy = true } },
}

Hunter.RotationSpecs.SV = {
    title = "Survival",
    nodes = module:ConcatCommonNodes(Hunter.HunterMeleeNodes, {
        { id = "deterrence",    spellID = 19263, name = "Deterrence",    color = "Defensive", condition = "pvp_hp30" },
        { id = "scatter_shot",  spellID = 19503, name = "Scatter Shot",  color = "Interrupt", condition = "enemy_interruptible_not_cc" },
        { id = "rapid_fire",    spellID = 3045,  name = "Rapid Fire",    color = "Damage",    condition = "enemy_in_combat_not_too_close", passthrough = true },
        { id = "viper_sting",   spellID = 3034,  name = "Viper Sting",   color = "Utility",   condition = "viper_pvp_mana" },
        { id = "scorpid_sting", spellID = 3043,  name = "Scorpid Sting", color = "Utility",   condition = "scorpid_pvp_melee" },
        { id = "multi_shot",    spellID = 2643,  name = "Multi-Shot",    color = "AoE",       condition = "aoe_not_too_close" },
        { id = "aimed_shot",    spellID = 19434, name = "Aimed Shot",    color = "Damage",    condition = "not_aoe_not_too_close" },
        { id = "serpent_sting", spellID = 1978,  name = "Serpent Sting", color = "Damage",    condition = "no_serpent_pve" },
        { id = "arcane_shot",   spellID = 3044,  name = "Arcane Shot",   color = "Damage",    condition = "not_too_close_ranged" },
        { id = "volley",        spellID = 1510,  name = "Volley",        color = "AoE",       condition = "aoe_not_pvp_mana15" },
    }),
}
