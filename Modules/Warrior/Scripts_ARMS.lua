-- Combat Forever Assistant — Warrior module: Arms rotation (declared data).
-- WoW Forever Arms priority (2026):
--   Battle Stance -> Charge (out of combat) -> Interrupt (Pummel/Shield Bash) ->
--   Bloodrage (low rage) -> Victory Rush (baseline lvl 20 reactive) ->
--   Execute (<= 20% HP) -> Sweeping Strikes (AoE) -> Bladestorm (AoE, if known) ->
--   Overpower (reactive) -> Mortal Strike (on CD) -> Rend (maintain > 25% HP) ->
--   Hamstring (PvP) -> Slam (standing filler) -> Cleave (AoE rage dump) ->
--   Heroic Strike (rage dump / low-level filler).
local _, addon = ...

local Warrior = addon.modules.WARRIOR
Warrior.RotationSpecs = Warrior.RotationSpecs or {}

Warrior.RotationSpecs.ARMS = {
    title = "Arms",
    nodes = {
        {
            id = "battle_stance",
            spellID = 2457,
            name = "Battle Stance",
            color = "Utility",
            condition = "war_needs_battle_stance",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "charge_arms",
            spellID = 100,
            name = "Charge",
            color = "Utility",
            condition = "war_charge",
        },
        {
            id = "pummel_arms",
            spellID = 6552,
            name = "Pummel",
            color = "Interrupt",
            condition = "war_interrupt_pummel",
        },
        {
            id = "shield_bash_arms",
            spellID = 72,
            name = "Shield Bash",
            color = "Interrupt",
            condition = "war_interrupt_shield_bash",
        },
        {
            id = "bloodrage_arms",
            spellID = 2687,
            name = "Bloodrage",
            color = "Utility",
            condition = "war_bloodrage_low",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "victory_rush_arms",
            spellID = 34428,
            name = "Victory Rush",
            color = "Damage",
            condition = "war_victory_rush",
        },
        {
            id = "execute_arms",
            spellID = 5308,
            name = "Execute",
            color = "Damage",
            condition = "war_execute",
        },
        {
            id = "sweeping_strikes",
            spellID = 12328,
            name = "Sweeping Strikes",
            color = "AoE",
            condition = "war_sweeping_strikes",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "bladestorm",
            spellID = 46924,
            name = "Bladestorm",
            color = "AoE",
            condition = "war_bladestorm",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "overpower_arms",
            spellID = 7384,
            name = "Overpower",
            color = "Damage",
            condition = "war_overpower",
        },
        {
            id = "mortal_strike",
            spellID = 12294,
            name = "Mortal Strike",
            color = "Damage",
            condition = "war_mortal_strike",
        },
        {
            id = "rend_arms",
            spellID = 772,
            name = "Rend",
            color = "Damage",
            condition = "war_rend",
        },
        {
            id = "hamstring_arms",
            spellID = 1715,
            name = "Hamstring",
            color = "Interrupt",
            condition = "war_hamstring_pvp",
        },
        {
            id = "slam_arms",
            spellID = 1464,
            name = "Slam",
            color = "Damage",
            condition = "war_slam",
        },
        {
            id = "cleave_arms",
            spellID = 845,
            name = "Cleave",
            color = "AoE",
            condition = "war_cleave_dump",
            opts = { notIfActive = true },
        },
        {
            id = "heroic_strike_arms",
            spellID = 78,
            name = "Heroic Strike",
            color = "Damage",
            condition = "war_heroic_strike_dump",
            opts = { notIfActive = true },
        },
    },
}
