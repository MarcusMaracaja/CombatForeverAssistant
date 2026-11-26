-- Combat Forever Assistant — Shaman module: Elemental rotation + Restoration DPS fallback.
-- WoW Forever Elemental identity (Nov/2026):
--   Earth Shock (interrupt) -> Lightning Mastery (burst CD) -> Flame Shock (maintain) ->
--   Fire Totem (Magma AoE / Searing ST) -> Fire Nova (AoE pulse from active Fire Totem) ->
--   Chain Lightning (AoE / Clearcasting / Mastery / high mana) -> Earth Shock (moving) ->
--   Lightning Bolt (primary single-target filler).
-- Restoration healing patterns will be implemented in a dedicated healer phase;
-- until then, REST uses the clean caster DPS fallback (without Lightning Mastery).
local _, addon = ...

local Shaman = addon.modules.SHAMAN
Shaman.RotationSpecs = Shaman.RotationSpecs or {}

Shaman.CommonNodes = {
    {
        id = "earth_shock_interrupt",
        spellID = 8042,
        name = "Earth Shock",
        color = "Interrupt",
        condition = "shaman_interrupt",
    },
}

local function buildCasterNodes(includeMastery)
    local nodes = {}
    if includeMastery then
        nodes[#nodes + 1] = {
            id = "lightning_mastery",
            spellID = 16166,
            name = "Lightning Mastery",
            color = "Damage",
            condition = "shaman_lightning_mastery",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        }
    end
    nodes[#nodes + 1] = {
        id = "magma_totem",
        spellID = 8190,
        name = "Magma Totem",
        color = "AoE",
        condition = "shaman_magma_totem",
        opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "searing_totem",
        spellID = 3599,
        name = "Searing Totem",
        color = "Damage",
        condition = "shaman_searing_totem",
        opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "flame_shock",
        spellID = 8050,
        name = "Flame Shock",
        color = "Damage",
        condition = "shaman_flame_shock",
    }
    nodes[#nodes + 1] = {
        id = "fire_nova",
        spellID = 1535,
        name = "Fire Nova",
        color = "AoE",
        condition = "shaman_fire_nova",
        opts = { noEnemy = true, noRangeCheck = true },
    }
    nodes[#nodes + 1] = {
        id = "chain_lightning",
        spellID = 421,
        name = "Chain Lightning",
        color = "AoE",
        condition = "shaman_chain_lightning_ele",
    }
    nodes[#nodes + 1] = {
        id = "earth_shock_moving",
        spellID = 8042,
        name = "Earth Shock (Moving)",
        color = "Damage",
        condition = "shaman_earth_shock_moving",
    }
    nodes[#nodes + 1] = {
        id = "lightning_bolt",
        spellID = 403,
        name = "Lightning Bolt",
        color = "Damage",
        condition = "shaman_has_enemy",
    }
    return nodes
end

Shaman.RotationSpecs.ELE = {
    title = "Elemental",
    nodes = addon:ConcatCommonNodes(Shaman.CommonNodes, buildCasterNodes(true)),
}

Shaman.RotationSpecs.REST = {
    title = "Restoration (DPS fallback)",
    nodes = addon:ConcatCommonNodes(Shaman.CommonNodes, buildCasterNodes(false)),
}
