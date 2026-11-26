-- Combat Forever Assistant — Warrior module: Protection (Tank) rotation (declared data).
-- WoW Forever Protection priority (2026):
--   Defensive Stance -> Shield Wall (<= 25% HP) -> Last Stand (<= 30% HP) ->
--   Taunt (enemy attacking ally) -> Shield Bash / Concussion Blow (interrupt) ->
--   Bloodrage (low rage) -> Victory Rush (reactive) ->
--   Shield Block (off-GCD passthrough when tanking) -> Revenge (reactive highest threat/rage) ->
--   Shield Slam (on CD) -> Shockwave (AoE, if known) -> Thunder Clap (AoE or debuff missing) ->
--   Demoralizing Shout (debuff missing) -> Sunder Armor (< 5 stacks) ->
--   Devastate (filler if known) -> Cleave (AoE excess rage) -> Heroic Strike (excess rage).
local _, addon = ...

local Warrior = addon.modules.WARRIOR
Warrior.RotationSpecs = Warrior.RotationSpecs or {}

Warrior.RotationSpecs.PROT = {
    title = "Protection",
    nodes = {
        {
            id = "defensive_stance",
            spellID = 71,
            name = "Defensive Stance",
            color = "Utility",
            condition = "war_needs_defensive_stance",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "shield_wall",
            spellID = 871,
            name = "Shield Wall",
            color = "Defensive",
            condition = "war_shield_wall",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "last_stand",
            spellID = 12975,
            name = "Last Stand",
            color = "Defensive",
            condition = "war_last_stand",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "taunt",
            spellID = 355,
            name = "Taunt",
            color = "Utility",
            condition = "war_taunt",
        },
        {
            id = "shield_bash_prot",
            spellID = 72,
            name = "Shield Bash",
            color = "Interrupt",
            condition = "war_interrupt_shield_bash",
        },
        {
            id = "concussion_blow",
            spellID = 12809,
            name = "Concussion Blow",
            color = "Interrupt",
            condition = "war_interrupt_concussion",
        },
        {
            id = "bloodrage_prot",
            spellID = 2687,
            name = "Bloodrage",
            color = "Utility",
            condition = "war_bloodrage_low",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "victory_rush_prot",
            spellID = 34428,
            name = "Victory Rush",
            color = "Damage",
            condition = "war_victory_rush",
        },
        {
            id = "shield_block",
            spellID = 2565,
            name = "Shield Block",
            color = "Defensive",
            condition = "war_shield_block",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "revenge",
            spellID = 6572,
            name = "Revenge",
            color = "Damage",
            condition = "war_revenge",
        },
        {
            id = "shield_slam",
            spellID = 23922,
            name = "Shield Slam",
            color = "Damage",
            condition = "war_shield_slam",
        },
        {
            id = "shockwave",
            spellID = 46968,
            name = "Shockwave",
            color = "AoE",
            condition = "war_shockwave",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "thunder_clap",
            spellID = 6343,
            name = "Thunder Clap",
            color = "AoE",
            condition = "war_thunder_clap",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "demo_shout",
            spellID = 1160,
            name = "Demoralizing Shout",
            color = "Utility",
            condition = "war_demo_shout",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "sunder_armor",
            spellID = 7386,
            name = "Sunder Armor",
            color = "Damage",
            condition = "war_sunder_armor",
        },
        {
            id = "devastate",
            spellID = 20243,
            name = "Devastate",
            color = "Damage",
            condition = "war_devastate",
        },
        {
            id = "cleave_prot",
            spellID = 845,
            name = "Cleave",
            color = "AoE",
            condition = "war_cleave_dump",
            opts = { notIfActive = true },
        },
        {
            id = "heroic_strike_prot",
            spellID = 78,
            name = "Heroic Strike",
            color = "Damage",
            condition = "war_heroic_strike_dump",
            opts = { notIfActive = true },
        },
    },
}
