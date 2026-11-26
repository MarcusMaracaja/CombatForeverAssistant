-- Combat Forever Assistant — Priest module: Shadow DPS rotation (declared data).
-- WoW Forever Shadow Priest priority (2026):
--   Shadowform -> Silence (interrupt) -> Power Word: Shield (defensive <= 60% HP) ->
--   Inner Focus (passthrough crit CD) -> Shadowfiend (low mana) ->
--   Vampiric Embrace (sustain CD) -> Shadow Word: Pain (maintain DoT) ->
--   Devouring Plague (baseline lvl 20, maintain DoT) -> Vampiric Touch (if known) ->
--   Mind Blast (on CD) -> Shadow Word: Death (baseline lvl 32, safe HP > 35%) ->
--   Mind Flay (standing filler) -> Smite (low-level filler before Mind Flay) ->
--   Shoot / Wand (low mana <= 12%).
local _, addon = ...

local Priest = addon.modules.PRIEST
Priest.RotationSpecs = Priest.RotationSpecs or {}

Priest.CommonNodes = {
    {
        id = "silence",
        spellID = 15487,
        name = "Silence",
        color = "Interrupt",
        condition = "priest_interrupt",
    },
    {
        id = "pw_shield_defensive",
        spellID = 17,
        name = "Power Word: Shield",
        color = "Defensive",
        condition = "priest_defensive_shield",
        opts = { noEnemy = true, noRangeCheck = true },
    },
}

Priest.RotationSpecs.SHAD = {
    title = "Shadow",
    nodes = addon:ConcatCommonNodes({
        {
            id = "shadowform",
            spellID = 15473,
            name = "Shadowform",
            color = "Utility",
            condition = "priest_needs_shadowform",
            opts = { noEnemy = true, noRangeCheck = true },
        },
    }, addon:ConcatCommonNodes(Priest.CommonNodes, {
        {
            id = "inner_focus",
            spellID = 14751,
            name = "Inner Focus",
            color = "Damage",
            condition = "priest_inner_focus",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "shadowfiend",
            spellID = 34433,
            name = "Shadowfiend",
            color = "Utility",
            condition = "priest_shadowfiend",
        },
        {
            id = "vampiric_embrace",
            spellID = 15286,
            name = "Vampiric Embrace",
            color = "Utility",
            condition = "priest_vampiric_embrace",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "sw_pain",
            spellID = 589,
            name = "Shadow Word: Pain",
            color = "Damage",
            condition = "priest_sw_pain_missing",
        },
        {
            id = "devouring_plague",
            spellID = 2944,
            name = "Devouring Plague",
            color = "Damage",
            condition = "priest_devouring_plague_missing",
        },
        {
            id = "vampiric_touch",
            spellID = 34914,
            name = "Vampiric Touch",
            color = "Damage",
            condition = "priest_vampiric_touch_missing",
        },
        {
            id = "mind_blast",
            spellID = 8092,
            name = "Mind Blast",
            color = "Damage",
            condition = "priest_mind_blast",
        },
        {
            id = "sw_death",
            spellID = 32379,
            name = "Shadow Word: Death",
            color = "Damage",
            condition = "priest_sw_death",
        },
        {
            id = "mind_flay",
            spellID = 15407,
            name = "Mind Flay",
            color = "Damage",
            condition = "priest_mind_flay",
        },
        {
            id = "smite_low_level",
            spellID = 585,
            name = "Smite",
            color = "Damage",
            condition = "priest_smite_low_level",
        },
        {
            id = "shoot_wand",
            spellID = 5019,
            name = "Shoot (Wand)",
            color = "Damage",
            condition = "priest_wand_filler",
        },
    })),
}
