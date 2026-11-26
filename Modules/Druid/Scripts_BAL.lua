-- Combat Forever Assistant — Druid module: Balance rotation (declared data).
-- Forever (1.60.1) spells only — no WotLK spells.
local _, addon = ...

local Druid = addon.modules.DRUID
Druid.RotationSpecs = Druid.RotationSpecs or {}

Druid.RotationSpecs.BAL = {
    title = "Balance",
    nodes = {
        { id = "moonkin_form", spellID = 24858, name = "Moonkin Form", color = "Utility",
            condition = "needs_moonkin_form", opts = { noEnemy = true, noRange = true } },
        { id = "innervate",    spellID = 29166, name = "Innervate",    color = "Utility",
            condition = "innervate_low_mana", opts = { noEnemy = true, noRange = true } },
        { id = "faerie_fire",  spellID = 770,   name = "Faerie Fire",  color = "Utility",
            condition = "bal_needs_faerie_fire" },
        { id = "insect_swarm", spellID = 5570,  name = "Insect Swarm", color = "Damage",
            condition = "bal_needs_insect_swarm" },
        { id = "moonfire",     spellID = 8921,  name = "Moonfire",     color = "Damage",
            condition = "bal_needs_moonfire" },
        { id = "hurricane",    spellID = 16914, name = "Hurricane",    color = "AoE",
            condition = "bal_aoe" },
        { id = "starfire",     spellID = 2912,  name = "Starfire",     color = "Damage",
            condition = "bal_enemy" },
        { id = "wrath",        spellID = 5176,  name = "Wrath",        color = "Damage",
            condition = "bal_enemy" },
    },
}
