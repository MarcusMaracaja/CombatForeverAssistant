-- Combat Forever Assistant — Warrior module: Fury rotation (declared data).
-- WoW Forever Fury priority (2026):
--   Berserker Stance (or Battle < lvl 30) -> Charge / Intercept -> Interrupt (Pummel) ->
--   Bloodrage (low rage) -> Death Wish (burst CD) -> Victory Rush (baseline lvl 20) ->
--   Execute (<= 20% HP) -> Bloodthirst (on CD) -> Whirlwind (on CD) ->
--   Overpower (if in Battle Stance) -> Hamstring (PvP) ->
--   Cleave (AoE rage dump) -> Heroic Strike (rage dump / low-level filler).
local _, addon = ...

local Warrior = addon.modules.WARRIOR
Warrior.RotationSpecs = Warrior.RotationSpecs or {}

Warrior.RotationSpecs.FURY = {
    title = "Fury",
    nodes = {
        {
            id = "charge_fury",
            spellID = 100,
            name = "Charge",
            color = "Utility",
            condition = "war_charge",
        },
        {
            id = "berserker_stance",
            spellID = 2458,
            name = "Berserker Stance",
            color = "Utility",
            condition = "war_needs_berserker_stance",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "battle_stance_fury_low",
            spellID = 2457,
            name = "Battle Stance",
            color = "Utility",
            condition = "war_needs_battle_fallback",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "intercept_fury",
            spellID = 20252,
            name = "Intercept",
            color = "Utility",
            condition = "war_intercept",
        },
        {
            id = "pummel_fury",
            spellID = 6552,
            name = "Pummel",
            color = "Interrupt",
            condition = "war_interrupt_pummel",
        },
        {
            id = "shield_bash_fury",
            spellID = 72,
            name = "Shield Bash",
            color = "Interrupt",
            condition = "war_interrupt_shield_bash",
        },
        {
            id = "bloodrage_fury",
            spellID = 2687,
            name = "Bloodrage",
            color = "Utility",
            condition = "war_bloodrage_low",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "death_wish",
            spellID = 12292,
            name = "Death Wish",
            color = "Damage",
            condition = "war_death_wish",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "victory_rush_fury",
            spellID = 34428,
            name = "Victory Rush",
            color = "Damage",
            condition = "war_victory_rush",
        },
        {
            id = "execute_fury",
            spellID = 5308,
            name = "Execute",
            color = "Damage",
            condition = "war_execute",
        },
        {
            id = "bloodthirst",
            spellID = 23881,
            name = "Bloodthirst",
            color = "Damage",
            condition = "war_bloodthirst",
        },
        {
            id = "whirlwind",
            spellID = 1680,
            name = "Whirlwind",
            color = "AoE",
            condition = "war_whirlwind",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "overpower_fury",
            spellID = 7384,
            name = "Overpower",
            color = "Damage",
            condition = "war_overpower",
        },
        {
            id = "hamstring_fury",
            spellID = 1715,
            name = "Hamstring",
            color = "Interrupt",
            condition = "war_hamstring_pvp",
        },
        {
            id = "cleave_fury",
            spellID = 845,
            name = "Cleave",
            color = "AoE",
            condition = "war_cleave_dump",
            opts = { notIfActive = true },
        },
        {
            id = "heroic_strike_fury",
            spellID = 78,
            name = "Heroic Strike",
            color = "Damage",
            condition = "war_heroic_strike_dump",
            opts = { notIfActive = true },
        },
    },
}
