-- Combat Forever Assistant — Druid module: Feral rotation (declared data).
-- ONE unified Feral spec: adapts dynamically to the player's current form!
--   * Bear / Dire Bear Form -> Tank priority (defensives, Enrage, Growl, Bash,
--     Faerie Fire Feral, Demoralizing Roar, Mangle Bear, Swipe AoE, Maul).
--   * Cat Form              -> Melee DPS priority (Barkskin, Tiger's Fury,
--     Faerie Fire Feral, Mangle Cat, Rake, Rip, Ferocious Bite, Claw/Shred).
--   * Humanoid Form         -> Never forces a form; player chooses their form.
local _, addon = ...

local Druid = addon.modules.DRUID
Druid.RotationSpecs = Druid.RotationSpecs or {}

Druid.RotationSpecs.FER = {
    title = "Feral",
    nodes = {
        -- === BEAR FORM (TANK) ===
        { id = "frenzied_regeneration", spellID = 22842, name = "Frenzied Regeneration", color = "Defensive",
            condition = "bear_frenzied_regen", opts = { noEnemy = true, noRange = true } },
        { id = "barkskin_bear",         spellID = 22812, name = "Barkskin",              color = "Defensive",
            condition = "bear_low_health",     opts = { noEnemy = true, noRange = true } },
        { id = "enrage",                spellID = 5229,  name = "Enrage",                color = "Utility",
            condition = "bear_needs_enrage",   opts = { noEnemy = true, noRange = true } },
        { id = "growl",                 spellID = 6795,  name = "Growl",                 color = "Utility",
            condition = "bear_needs_taunt" },
        { id = "bash",                  spellID = 5211,  name = "Bash",                  color = "Interrupt",
            condition = "bear_needs_bash",     opts = { noRange = true } },
        { id = "feral_faerie_fire_bear", spellID = 16857, name = "Faerie Fire (Feral)",  color = "Utility",
            condition = "bear_needs_faerie_fire" },
        { id = "demoralizing_roar",     spellID = 99,    name = "Demoralizing Roar",     color = "Utility",
            condition = "bear_needs_demo",     opts = { noRange = true } },
        { id = "mangle_bear",           spellID = 33878, name = "Mangle (Bear)",         color = "Damage",
            condition = "bear_needs_mangle",   opts = { noRange = true } },
        { id = "swipe_bear",            spellID = 779,   name = "Swipe (Bear)",          color = "AoE",
            condition = "bear_aoe",            opts = { noRange = true } },
        { id = "maul",                  spellID = 6807,  name = "Maul",                  color = "Damage",
            condition = "bear_maul",           opts = { noRange = true } },

        -- === CAT FORM (MELEE DPS) ===
        { id = "barkskin_cat",          spellID = 22812, name = "Barkskin",              color = "Defensive",
            condition = "cat_low_health",      opts = { noEnemy = true, noRange = true } },
        { id = "tigers_fury",           spellID = 5217,  name = "Tiger's Fury",          color = "Damage",
            condition = "cat_tigers_fury",     opts = { noEnemy = true, noRange = true } },
        { id = "feral_faerie_fire_cat", spellID = 16857, name = "Faerie Fire (Feral)",   color = "Utility",
            condition = "cat_needs_faerie_fire" },
        { id = "mangle_cat",            spellID = 33876, name = "Mangle (Cat)",          color = "Damage",
            condition = "cat_needs_mangle",    opts = { noRange = true } },
        { id = "rake",                  spellID = 1822,  name = "Rake",                  color = "Damage",
            condition = "cat_needs_rake",      opts = { noRange = true } },
        { id = "rip",                   spellID = 1079,  name = "Rip",                   color = "Damage",
            condition = "cat_needs_rip",       opts = { noRange = true } },
        { id = "ferocious_bite",        spellID = 22568, name = "Ferocious Bite",        color = "Damage",
            condition = "cat_can_bite",        opts = { noRange = true } },
        { id = "claw",                  spellID = 1082,  name = "Claw",                  color = "Damage",
            condition = "cat_builder",         opts = { noRange = true } },
        { id = "shred",                 spellID = 5221,  name = "Shred",                 color = "Damage",
            condition = "cat_builder",         opts = { noRange = true } },
    },
}
