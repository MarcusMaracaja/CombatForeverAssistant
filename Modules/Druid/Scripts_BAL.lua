-- Combat Forever Assistant — Druid module: rotação de Equilíbrio (Balance) — DADO.
--
-- Ordem e condições iguais às do modelo clean-room:
--   Moonkin Form -> Insect Swarm -> Moonfire -> Starfire -> Wrath
local addonName, addon = ...
local module = addon.Druid

module.RotationSpecs = module.RotationSpecs or {}

module.RotationSpecs.BAL = {
    title = "Balance",
    nodes = {
        { id = "moonkin_form",  spellID = 24858, name = "Moonkin Form", color = "Green",  condition = "not_moonkin", opts = { noEnemy = true } },
        { id = "insect_swarm",  spellID = 5570,  name = "Insect Swarm", color = "Pink",   condition = "insect_swarm_missing" },
        { id = "moonfire",      spellID = 8921,  name = "Moonfire",     color = "Pink",   condition = "moonfire_missing" },
        { id = "starfire",      spellID = 8950,  name = "Starfire",     color = "Yellow", condition = "always" },
        { id = "wrath",         spellID = 5176,  name = "Wrath",        color = "Yellow", condition = "always" },
    },
}
