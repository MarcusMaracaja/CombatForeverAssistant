-- Combat Forever Assistant — Druid module: rotação de Gato (Cat Form) — DADO.
--
-- Ordem e condições iguais às da referência clean-room:
--   Pounce -> Rip -> Ferocious Bite -> Rake -> Shred -> Claw
--
-- Diferença em relação ao modelo clean-room: os auto-buffs (Marca da Selva / Espinhos /
-- Garras da Natureza) NÃO entram na cadeia do Gato. No modelo clean-room eles eram um
-- prefixo "passthrough" (brilhavam junto, sem bloquear); no CFA as
-- utilidades rodam DEPOIS da spec (ver Scripts.lua), então nunca bloqueiam
-- a rotação de combate — e no Gato/Urso eles nem se aplicam.
local addonName, addon = ...
local module = addon.Druid

module.RotationSpecs = module.RotationSpecs or {}

module.RotationSpecs.CAT = {
    title = "Cat Form",
    nodes = {
        { id = "pounce",         spellID = 9005,  name = "Pounce",         color = "Yellow", condition = "pounce_condition" },
        { id = "rip",            spellID = 1079,  name = "Rip",            color = "Yellow", condition = "combo5" },
        { id = "ferocious_bite", spellID = 22568, name = "Ferocious Bite", color = "Orange", condition = "combo5" },
        { id = "rake",           spellID = 1822,  name = "Rake",           color = "Pink",   condition = "energy40" },
        { id = "shred",          spellID = 5221,  name = "Shred",          color = "Yellow", condition = "behind" },
        { id = "claw",           spellID = 1082,  name = "Claw",           color = "White",  condition = "always" },
    },
}
