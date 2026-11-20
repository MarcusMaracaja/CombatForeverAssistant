-- Combat Forever Assistant — Druid module: spec "SELF" (auto-buffs) — DADO.
--
-- Usada quando o Druid Feral está em forma de conjurador (sem rotação de
-- forma ativa). A cadeia é vazia de propósito: os auto-buffs (Marca da
-- Selva / Espinhos / Garras da Natureza) são UTILIDADE e rodam depois da
-- spec (ver Scripts.lua) — assim nunca bloqueiam a rotação de combate.
--
-- No modelo clean-room esses auto-buffs eram um prefixo comum "passthrough" (brilhavam
-- junto com a rotação, sem bloquear). No CFA a ordem é invertida de
-- propósito: primeiro o combate, depois a utilidade.
local addonName, addon = ...
local module = addon.Druid

module.RotationSpecs = module.RotationSpecs or {}

module.RotationSpecs.SELF = {
    title = "Self-buffs",
    nodes = {},
}
