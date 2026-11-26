-- Combat Forever Assistant — Shaman module: Enhancement rotation (declared data).
-- WoW Forever Enhancement priority:
--   Earth Shock (interrupt) -> Rage of the Farseer / Shamanistic Rage (CDs) ->
--   Maelstrom Weapon 5 stacks (Chain Lightning AoE / Lightning Bolt ST) ->
--   Stormstrike (on CD in melee) -> Fire Totem (Magma AoE / Searing ST) ->
--   Fire Nova (AoE with active Fire Totem) -> Flame Shock (maintain DoT) ->
--   Frost Shock (PvP slow) -> Earth Shock (melee shock filler with SS/FS up) ->
--   Lightning Bolt (ranged filler when outside melee).
local _, addon = ...

local Shaman = addon.modules.SHAMAN
Shaman.RotationSpecs = Shaman.RotationSpecs or {}

Shaman.RotationSpecs.ENH = {
    title = "Enhancement",
    nodes = addon:ConcatCommonNodes(Shaman.CommonNodes, {
        {
            id = "rage_of_farseer",
            spellID = 425336,
            name = "Rage of the Farseer",
            color = "Damage",
            condition = "shaman_rage_of_farseer",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "shamanistic_rage",
            spellID = 30823,
            name = "Shamanistic Rage",
            color = "Utility",
            condition = "shaman_shamanistic_rage",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "chain_lightning_maelstrom",
            spellID = 421,
            name = "Chain Lightning (Maelstrom)",
            color = "AoE",
            condition = "shaman_maelstrom_aoe",
        },
        {
            id = "lightning_bolt_maelstrom",
            spellID = 403,
            name = "Lightning Bolt (Maelstrom)",
            color = "Damage",
            condition = "shaman_maelstrom_st",
        },
        {
            id = "stormstrike",
            spellID = 17364,
            name = "Stormstrike",
            color = "Damage",
            condition = "shaman_stormstrike",
        },
        {
            id = "magma_totem_enh",
            spellID = 8190,
            name = "Magma Totem",
            color = "AoE",
            condition = "shaman_magma_totem",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "fire_nova_enh",
            spellID = 1535,
            name = "Fire Nova",
            color = "AoE",
            condition = "shaman_fire_nova",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "searing_totem_enh",
            spellID = 3599,
            name = "Searing Totem",
            color = "Damage",
            condition = "shaman_searing_totem",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "flame_shock_enh",
            spellID = 8050,
            name = "Flame Shock",
            color = "Damage",
            condition = "shaman_flame_shock",
        },
        {
            id = "frost_shock_pvp",
            spellID = 8056,
            name = "Frost Shock",
            color = "Interrupt",
            condition = "shaman_frost_shock_pvp",
        },
        {
            id = "earth_shock_enh",
            spellID = 8042,
            name = "Earth Shock",
            color = "Damage",
            condition = "shaman_earth_shock_enh",
        },
        {
            id = "lightning_bolt_ranged",
            spellID = 403,
            name = "Lightning Bolt (Ranged)",
            color = "Damage",
            condition = "shaman_not_melee",
        },
    }),
}
