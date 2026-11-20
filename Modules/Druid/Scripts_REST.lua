-- Combat Forever Assistant — Druid module: rotação de Restauração — DADO.
--
-- Ordem e condições iguais às do modelo clean-room:
--   Frenzied Regeneration -> Cat Form (só quando está em Urso)
--
-- Observação: a spec de Restauração do modelo clean-room é enxuta (auto-cura + troca de
-- forma). O mesmo aqui — a paridade de comportamento é a regra.
local addonName, addon = ...
local module = addon.Druid

module.RotationSpecs = module.RotationSpecs or {}

module.RotationSpecs.REST = {
    title = "Restoration",
    nodes = {
        { id = "frenzied_regeneration", spellID = 22842, name = "Frenzied Regeneration", color = "Green", condition = "my_hp35", opts = { noEnemy = true } },
        { id = "cat_form",              spellID = 768,   name = "Cat Form",              color = "Green", condition = "bear_form", opts = { noEnemy = true } },
    },
}
