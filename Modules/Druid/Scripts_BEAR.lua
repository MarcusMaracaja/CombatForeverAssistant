-- Combat Forever Assistant — Druid module: rotação de Urso (Bear Form) — DADO.
--
-- Ordem e condições iguais às do modelo clean-room:
--   Bash -> Frenzied Regeneration -> Maul -> Swipe -> Lacerate -> Growl
--
-- O Rugido Demoralizador (Roar) entra no COMEÇO da cadeia de Urso, como no
-- modelo clean-room, mas como nó "passthrough": é uma utilidade e NÃO pode bloquear a
-- rotação de combate (no Core, um nó passthrough fica como fallback e a
-- habilidade de combate seguinte tem prioridade).
local addonName, addon = ...
local module = addon.Druid

module.RotationSpecs = module.RotationSpecs or {}

module.RotationSpecs.BEAR = {
    title = "Bear Form",
    nodes = {
        { id = "demoralizing_roar", spellID = 99,    name = "Demoralizing Roar", color = "Green", condition = "demoralizing_roar_missing", passthrough = true },
        { id = "bash",               spellID = 5211,  name = "Bash",               color = "Aqua",   condition = "target_interruptible" },
        { id = "frenzied_regeneration", spellID = 22842, name = "Frenzied Regeneration", color = "Green", condition = "my_hp35", passthrough = true, opts = { noEnemy = true } },
        { id = "maul",               spellID = 6807,  name = "Maul",               color = "Yellow", condition = "always" },
        { id = "swipe",              spellID = 779,   name = "Swipe (Bear)",       color = "Purple", condition = "aoe_and_enemy" },
        { id = "lacerate",           spellID = 54802, name = "Lacerate",           color = "Pink",   condition = "has_enemy" },
        { id = "growl",              spellID = 6795,  name = "Growl",              color = "Yellow", condition = "has_enemy" },
    },
}
