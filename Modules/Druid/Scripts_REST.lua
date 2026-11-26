-- Combat Forever Assistant — Druid module: Restoration rotation (declared data).
-- Heals player or selected friendly target using Forever (1.60.1) spells.
local _, addon = ...

local Druid = addon.modules.DRUID
Druid.RotationSpecs = Druid.RotationSpecs or {}

Druid.RotationSpecs.REST = {
    title = "Restoration",
    nodes = {
        { id = "innervate",     spellID = 29166, name = "Innervate",     color = "Utility",
            condition = "innervate_low_mana", opts = { noEnemy = true, noRange = true } },
        { id = "swiftmend",     spellID = 18562, name = "Swiftmend",     color = "Defensive",
            condition = "heal_swiftmend",     opts = { noEnemy = true, noRange = true, unitKey = "healUnit" } },
        { id = "regrowth",      spellID = 8936,  name = "Regrowth",      color = "Defensive",
            condition = "heal_regrowth",      opts = { noEnemy = true, unitKey = "healUnit" } },
        { id = "healing_touch", spellID = 5185,  name = "Healing Touch", color = "Defensive",
            condition = "heal_touch",         opts = { noEnemy = true, unitKey = "healUnit" } },
        { id = "rejuvenation",  spellID = 774,   name = "Rejuvenation",  color = "Defensive",
            condition = "heal_rejuvenation",  opts = { noEnemy = true, unitKey = "healUnit" } },
    },
}
