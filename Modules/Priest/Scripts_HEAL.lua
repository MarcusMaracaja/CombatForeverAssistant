-- Combat Forever Assistant — Priest module: Group / Raid Healer rotation (declared data).
-- Expert Priest healing priority (covers both Holy and Discipline from level 1 to max level):
--   1) Resurrection (out of combat, dead ally in range)
--   2) Self-preservation: Fade (healer aggro in group) -> Desperate Prayer (self <= 40% HP)
--   3) Life-saving emergencies: Guardian Spirit (<= 30%) -> Pain Suppression (<= 35%) ->
--      Power Word: Shield (<= 45%, no Weakened Soul) -> Inner Focus / Power Infusion (passthrough) ->
--      Divine Hymn (3+ <= 55%) -> Penance (<= 55%) -> Flash Heal (<= 50%)
--   4) Smart AoE & Dual healing: Circle of Healing (3+ <= 82%) -> Prayer of Mending ->
--      Prayer of Healing (3+ <= 72%) -> Binding Heal (ally <= 75% & self <= 78%)
--   5) Proactive tank protection & Discipline throughput: Tank PW:S (<= 85%) -> Penance (<= 78%)
--   6) Cleanse debuffs (when nobody is critical): Dispel Magic -> Abolish/Cure Disease
--   7) Movement instants: PW: Shield -> Holy Nova (AoE) -> Renew
--   8) Mana-efficient single-target healing: Greater Heal (<= 75%) -> Heal / Lesser Heal (low level) ->
--      Flash Heal (<= 62% fallback) -> Renew (<= 92% HoT maintenance)
--   9) Mana recovery when group is stable: Hymn of Hope -> Shadowfiend
local _, addon = ...

local Priest = addon.modules.PRIEST
Priest.RotationSpecs = Priest.RotationSpecs or {}

Priest.RotationSpecs.HEAL = {
    title = "Healer (Grupo/Raide)",
    nodes = {
        {
            id = "heal_resurrection",
            spellID = 2006,
            name = "Resurrection",
            color = "Utility",
            condition = "priest_heal_resurrection",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_fade",
            spellID = 586,
            name = "Fade",
            color = "Utility",
            condition = "priest_heal_fade",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "heal_desperate_prayer",
            spellID = 19236,
            name = "Desperate Prayer",
            color = "Defensive",
            condition = "priest_heal_desperate_prayer",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "heal_guardian_spirit",
            spellID = 47788,
            name = "Guardian Spirit",
            color = "Defensive",
            condition = "priest_heal_guardian_spirit",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_pain_suppression",
            spellID = 33206,
            name = "Pain Suppression",
            color = "Defensive",
            condition = "priest_heal_pain_suppression",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_pw_shield_emergency",
            spellID = 17,
            name = "Power Word: Shield",
            color = "Defensive",
            condition = "priest_heal_shield_emergency",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_inner_focus",
            spellID = 14751,
            name = "Inner Focus",
            color = "Utility",
            condition = "priest_heal_inner_focus",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "heal_power_infusion",
            spellID = 10060,
            name = "Power Infusion",
            color = "Utility",
            condition = "priest_heal_power_infusion",
            opts = { noEnemy = true, noRangeCheck = true },
            passthrough = true,
        },
        {
            id = "heal_divine_hymn",
            spellID = 64843,
            name = "Divine Hymn",
            color = "AoE",
            condition = "priest_heal_divine_hymn",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "heal_penance_emergency",
            spellID = 47540,
            name = "Penance",
            color = "Defensive",
            condition = "priest_heal_penance_emergency",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_flash_emergency",
            spellID = 2061,
            name = "Flash Heal",
            color = "Defensive",
            condition = "priest_heal_flash_emergency",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_circle_of_healing",
            spellID = 34861,
            name = "Circle of Healing",
            color = "AoE",
            condition = "priest_heal_circle_of_healing",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_prayer_of_mending",
            spellID = 33076,
            name = "Prayer of Mending",
            color = "AoE",
            condition = "priest_heal_prayer_of_mending",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_prayer_of_healing",
            spellID = 596,
            name = "Prayer of Healing",
            color = "AoE",
            condition = "priest_heal_prayer_of_healing",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_binding_heal",
            spellID = 32546,
            name = "Binding Heal",
            color = "Defensive",
            condition = "priest_heal_binding_heal",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_pw_shield_tank",
            spellID = 17,
            name = "Power Word: Shield (Tank)",
            color = "Defensive",
            condition = "priest_heal_shield_tank",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_penance",
            spellID = 47540,
            name = "Penance",
            color = "Defensive",
            condition = "priest_heal_penance",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_dispel_magic",
            spellID = 527,
            name = "Dispel Magic",
            color = "Utility",
            condition = "priest_heal_dispel_magic",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_abolish_disease",
            spellID = 552,
            name = "Abolish Disease",
            color = "Utility",
            condition = "priest_heal_abolish_disease",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_cure_disease",
            spellID = 528,
            name = "Cure Disease",
            color = "Utility",
            condition = "priest_heal_cure_disease",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_pw_shield_moving",
            spellID = 17,
            name = "Power Word: Shield",
            color = "Defensive",
            condition = "priest_heal_shield_moving",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_holy_nova_moving",
            spellID = 15237,
            name = "Holy Nova",
            color = "AoE",
            condition = "priest_heal_holy_nova_moving",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "heal_greater_heal",
            spellID = 2060,
            name = "Greater Heal",
            color = "Defensive",
            condition = "priest_heal_greater_heal",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_mid",
            spellID = 2054,
            name = "Heal",
            color = "Defensive",
            condition = "priest_heal_mid",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_lesser",
            spellID = 2050,
            name = "Lesser Heal",
            color = "Defensive",
            condition = "priest_heal_lesser",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_flash_fast",
            spellID = 2061,
            name = "Flash Heal",
            color = "Defensive",
            condition = "priest_heal_flash_fast",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_renew",
            spellID = 139,
            name = "Renew",
            color = "Defensive",
            condition = "priest_heal_renew",
            opts = { noEnemy = true, unitKey = "healUnit" },
        },
        {
            id = "heal_hymn_of_hope",
            spellID = 64901,
            name = "Hymn of Hope",
            color = "Utility",
            condition = "priest_heal_hymn_of_hope",
            opts = { noEnemy = true, noRangeCheck = true },
        },
        {
            id = "heal_shadowfiend",
            spellID = 34433,
            name = "Shadowfiend",
            color = "Utility",
            condition = "priest_heal_shadowfiend",
        },
    },
}
