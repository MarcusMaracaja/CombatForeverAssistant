-- Combat Forever Assistant — Priest module: Discipline Smite DPS + Holy DPS fallback.
-- WoW Forever Discipline Smite DPS priority (2026):
--   Power Infusion / Inner Focus (CDs) -> Holy Fire (enables Power in Light) ->
--   Shadow Word: Pain (maintain DoT / Power in Light) -> Devouring Plague ->
--   Penance (core Discipline offensive channel) -> Holy Nova (AoE close range) ->
--   Shadow Word: Death (instant / execute, HP > 35%) -> Mind Blast (if no Penance) ->
--   Smite (primary Holy filler) -> Shoot / Wand (low mana <= 12%).
-- Dedicated healer patterns for Discipline / Holy will be built in a future healer phase.
local _, addon = ...

local Priest = addon.modules.PRIEST
Priest.RotationSpecs = Priest.RotationSpecs or {}

local function buildHolyCasterNodes(isDiscipline)
    local nodes = {}
    if isDiscipline then
        nodes[#nodes + 1] = {
            id = "power_infusion",
            spellID = 10060,
            name = "Power Infusion",
            color = "Damage",
            condition = "priest_power_infusion",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        }
    end
    nodes[#nodes + 1] = {
        id = "inner_focus_holy",
        spellID = 14751,
        name = "Inner Focus",
        color = "Damage",
        condition = "priest_inner_focus",
        opts = { noEnemy = true, noRangeCheck = true },
        passthrough = true,
    }
    nodes[#nodes + 1] = {
        id = "shadowfiend_holy",
        spellID = 34433,
        name = "Shadowfiend",
        color = "Utility",
        condition = "priest_shadowfiend",
    }
    nodes[#nodes + 1] = {
        id = "holy_fire",
        spellID = 14914,
        name = "Holy Fire",
        color = "Damage",
        condition = "priest_holy_fire_missing",
    }
    nodes[#nodes + 1] = {
        id = "sw_pain_holy",
        spellID = 589,
        name = "Shadow Word: Pain",
        color = "Damage",
        condition = "priest_sw_pain_missing",
    }
    nodes[#nodes + 1] = {
        id = "devouring_plague_holy",
        spellID = 2944,
        name = "Devouring Plague",
        color = "Damage",
        condition = "priest_devouring_plague_missing",
    }
    if isDiscipline then
        nodes[#nodes + 1] = {
            id = "penance",
            spellID = 47540,
            name = "Penance",
            color = "Damage",
            condition = "priest_penance",
        }
    end
    nodes[#nodes + 1] = {
        id = "holy_nova",
        spellID = 15237,
        name = "Holy Nova",
        color = "AoE",
        condition = "priest_holy_nova_aoe",
        opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "sw_death_holy",
        spellID = 32379,
        name = "Shadow Word: Death",
        color = "Damage",
        condition = "priest_sw_death",
    }
    nodes[#nodes + 1] = {
        id = "smite",
        spellID = 585,
        name = "Smite",
        color = "Damage",
        condition = "priest_smite",
    }
    nodes[#nodes + 1] = {
        id = "shoot_wand_holy",
        spellID = 5019,
        name = "Shoot (Wand)",
        color = "Damage",
        condition = "priest_wand_filler",
    }
    return nodes
end

Priest.RotationSpecs.DISC = {
    title = "Discipline (Smite DPS)",
    nodes = addon:ConcatCommonNodes(Priest.CommonNodes, buildHolyCasterNodes(true)),
}

Priest.RotationSpecs.HOLY = {
    title = "Holy (DPS fallback)",
    nodes = addon:ConcatCommonNodes(Priest.CommonNodes, buildHolyCasterNodes(false)),
}
