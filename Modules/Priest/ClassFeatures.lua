-- Combat Forever Assistant — Priest module: class-specific helpers, spell families,
-- aura / DoT / Weakened Soul tracking, and Priest DPS predicates.
-- Relies on Shared/Functions.lua and Core.lua for all generic checks (resources,
-- target, PvP, spec detection, castable engine, cooldowns).
local _, addon = ...

local Priest = addon.modules.PRIEST or {}
addon.modules.PRIEST = Priest
Priest.classTag = "PRIEST"
Priest.addon = addon
Priest.Compat = addon.Compat
Priest.RotationPredicates = Priest.RotationPredicates or {}
Priest.RotationSpecs = Priest.RotationSpecs or {}
Priest.BuffBeliefs = Priest.BuffBeliefs or {}
Priest.TargetBeliefs = Priest.TargetBeliefs or {}
Priest.AllyBeliefs = Priest.AllyBeliefs or {}

local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end

-- ---------------------------------------------------------------------------
-- Priest spell rank families (Vanilla / WoW Forever ranks).
-- Registered globally in Core so SpellKnown, HighestKnownSpellID, ResolveKnownID,
-- IsSpellOnCD and RunDeclaredRotation recognize every rank automatically.
-- ---------------------------------------------------------------------------
local PRIEST_FAMILIES = {
    { 589, 594, 970, 992, 2767, 10892, 10893, 10894, 25367, 25368, 48124, 48125 },   -- Shadow Word: Pain
    { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947, 25372, 25375, 48126, 48127 }, -- Mind Blast
    { 15407, 17311, 17312, 17313, 17314, 18807, 25387, 48155, 48156 },               -- Mind Flay
    { 2944, 19276, 19277, 19278, 19279, 19280, 25467, 48299, 48300 },                -- Devouring Plague
    { 32379, 32996, 48157, 48158 },                                                  -- Shadow Word: Death
    { 34914, 34916, 34917, 48159, 48160 },                                           -- Vampiric Touch
    { 585, 591, 598, 984, 1004, 6060, 10933, 10934, 25363, 25364, 48122, 48123 },    -- Smite
    { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261, 25384, 48134, 48135 }, -- Holy Fire
    { 15237, 15430, 15431, 27799, 27800, 27801, 25331, 48077, 48078 },               -- Holy Nova
    { 47540, 53005, 53006, 53007 },                                                  -- Penance
    { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 25217, 25218, 48065, 48066 }, -- Power Word: Shield
    { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315, 25221, 25222, 48067, 48068 }, -- Renew
    { 2050, 2052, 2053 },                                                            -- Lesser Heal
    { 2054, 2055, 6063, 6064 },                                                      -- Heal
    { 2060, 10963, 10964, 10965, 25314, 25210, 25213, 48062, 48063 },                -- Greater Heal
    { 2061, 9472, 9473, 9474, 10915, 10916, 10917, 25233, 25235, 48070, 48071 },     -- Flash Heal
    { 32546, 48119, 48120 },                                                         -- Binding Heal
    { 596, 996, 10960, 10961, 25316, 25308, 48072 },                                 -- Prayer of Healing
    { 33076, 48112, 48113 },                                                         -- Prayer of Mending
    { 34861, 34863, 34864, 34865, 34866, 48088, 48089 },                             -- Circle of Healing
    { 19236, 19238, 19240, 19241, 19242, 19243, 25437, 48173 },                      -- Desperate Prayer
    { 33206 },                                                                       -- Pain Suppression
    { 47788 },                                                                       -- Guardian Spirit
    { 64843 },                                                                       -- Divine Hymn
    { 64901 },                                                                       -- Hymn of Hope
    { 586 },                                                                         -- Fade
    { 527, 988 },                                                                    -- Dispel Magic
    { 552 },                                                                         -- Abolish Disease
    { 528 },                                                                         -- Cure Disease
    { 2006, 2010, 10880, 10881, 20770, 25435, 48171 },                               -- Resurrection
    { 1243, 1244, 1245, 2791, 10937, 10938, 25389, 48161 },                          -- Power Word: Fortitude
    { 21562, 21564, 25392, 48162 },                                                  -- Prayer of Fortitude
    { 588, 7128, 602, 1006, 10951, 10952, 25431, 48168 },                            -- Inner Fire
    { 14752, 14818, 14819, 27841, 25312, 48073 },                                    -- Divine Spirit
    { 27681, 32999, 48074 },                                                         -- Prayer of Spirit
    { 976, 10957, 10958, 25433, 48169 },                                             -- Shadow Protection
    { 27683, 39374, 48170 },                                                         -- Prayer of Shadow Protection
    { 15473 },                                                                       -- Shadowform
    { 15286 },                                                                       -- Vampiric Embrace
    { 15487 },                                                                       -- Silence
    { 14751 },                                                                       -- Inner Focus
    { 10060 },                                                                       -- Power Infusion
    { 34433 },                                                                       -- Shadowfiend
    { 6346 },                                                                        -- Fear Ward
    { 5019 },                                                                        -- Shoot (Wand)
}

if addon.Compat and type(addon.Compat.RegisterSpellFamilies) == "function" then
    addon.Compat.RegisterSpellFamilies(PRIEST_FAMILIES)
end

local DOT_DURATIONS = {
    [589]   = { key = "sw_pain",          duration = 18 },
    [2944]  = { key = "devouring_plague", duration = 24 },
    [34914] = { key = "vampiric_touch",   duration = 15 },
    [14914] = { key = "holy_fire",        duration = 10 },
}

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, t = pcall(GetTime)
    return ok and addon.SafeNumber(t, 0) or 0
end

local function currentTargetGUID()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "target")
    return ok and (addon.SafeString and addon.SafeString(guid, nil)) or nil
end

function Priest.SameFamily(spellID, baseID)
    if type(spellID) ~= "number" or type(baseID) ~= "number" then return false end
    if spellID == baseID then return true end
    local fam = addon.Compat and addon.Compat.FamilyOf
    return fam ~= nil and fam[spellID] ~= nil and fam[spellID] == fam[baseID]
end

function Priest.ResolveID(spellID)
    if type(spellID) ~= "number" then return nil end
    return (addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(spellID)) or nil
end

function Priest.SpellName(spellID)
    local id = Priest.ResolveID(spellID) or spellID
    return addon.SpellName and addon.SpellName(id)
        or (addon.Compat and addon.Compat.SpellName and addon.Compat.SpellName(id))
end

-- ---------------------------------------------------------------------------
-- Buff / Debuff helpers (secret-safe + beliefs)
-- ---------------------------------------------------------------------------
function Priest.IsBuffActive(spellID, beliefKey, auraFamily)
    local status
    if auraFamily and addon.BuffLib and addon.BuffLib.Status then
        local ok, res = pcall(addon.BuffLib.Status, addon.BuffLib, "player", auraFamily)
        if ok and type(res) == "table" then
            status = res
            if status.present then return true end
        end
    end
    local name = Priest.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckBuff and addon.Compat.CheckBuff(name, "player", false) then
        return true
    end
    if addon.HasBuff and addon.HasBuff("player", spellID) then
        return true
    end
    local belief = beliefKey and Priest.BuffBeliefs[beliefKey] or nil
    if status and status.readable then
        if type(belief) == "table" and (now() - (belief.appliedAt or 0)) < 2.0 then
            return true
        end
        if beliefKey then Priest.BuffBeliefs[beliefKey] = nil end
        return false
    end
    if type(belief) == "table" then
        return belief.expires == nil or now() < belief.expires
    end
    return false
end

function Priest.IsTargetDebuffActive(spellID, beliefKey)
    local name = Priest.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckDebuff and addon.Compat.CheckDebuff(name, "target", true) then
        return true
    end
    local guid = currentTargetGUID()
    local b = beliefKey and Priest.TargetBeliefs[beliefKey] or nil
    if type(b) == "table" and guid ~= nil and b.guid == guid and now() < (b.expires or 0) then
        return true
    end
    if b and (not guid or b.guid ~= guid or now() >= (b.expires or 0)) then
        Priest.TargetBeliefs[beliefKey] = nil
    end
    return false
end

function Priest.IsShadowformActive()
    -- Shapeshift form check (Shadowform is a stance on modern clients)
    if type(GetShapeshiftForm) == "function" then
        local ok, idx = pcall(GetShapeshiftForm)
        local n = ok and addon.SafeNumber(idx, nil) or nil
        if n ~= nil and n > 0 then return true end
    end
    return Priest.IsBuffActive(15473, "shadowform", "Shadowform")
end

local function unitGUIDSafe(unit)
    if not unit or type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    return ok and (addon.SafeString and addon.SafeString(guid, nil)) or nil
end

function Priest.HasUnitBuff(unit, spellID, beliefKey, auraFamily)
    unit = unit or "player"
    local status
    if auraFamily and addon.BuffLib and addon.BuffLib.Status then
        local ok, res = pcall(addon.BuffLib.Status, addon.BuffLib, unit, auraFamily)
        if ok and type(res) == "table" then
            status = res
            if status.present then return true end
        end
    end
    local name = Priest.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckBuff and addon.Compat.CheckBuff(name, unit, false) then
        return true
    end
    if addon.HasBuff and addon.HasBuff(unit, spellID) then
        return true
    end
    local guid = unitGUIDSafe(unit)
    local byGuid = guid and Priest.AllyBeliefs[guid] or nil
    local belief = byGuid and beliefKey and byGuid[beliefKey] or nil
    if status and status.readable then
        if type(belief) == "table" and (now() - (belief.appliedAt or 0)) < 2.0 then
            return true
        end
        if byGuid and beliefKey then byGuid[beliefKey] = nil end
        return false
    end
    if type(belief) == "table" then
        return belief.expires == nil or now() < belief.expires
    end
    return false
end

function Priest.HasUnitWeakenedSoul(unit)
    unit = unit or "player"
    if addon.HasDebuff and addon.HasDebuff(unit, 6788) then return true end
    local wsName = addon.SpellName and addon.SpellName(6788)
    if wsName and addon.Compat and addon.Compat.CheckDebuff and addon.Compat.CheckDebuff(wsName, unit, false) then
        return true
    end
    if addon.UnitIsSame and addon.UnitIsSame(unit, "player") then
        local b = Priest.BuffBeliefs.weakened_soul
        if type(b) == "table" and now() < (b.expires or 0) then return true end
    end
    local guid = unitGUIDSafe(unit)
    local byGuid = guid and Priest.AllyBeliefs[guid] or nil
    local ab = byGuid and byGuid.weakened_soul or nil
    return type(ab) == "table" and now() < (ab.expires or 0)
end

function Priest.HasWeakenedSoul()
    return Priest.HasUnitWeakenedSoul("player")
end

function Priest.HasWandEquipped()
    if type(GetInventoryItemID) ~= "function" then return false end
    local ok, itemID = pcall(GetInventoryItemID, "player", 18) -- RangedSlot = 18
    return ok and type(itemID) == "number" and itemID > 0
end

function Priest.RecordCast(spellID)
    spellID = addon.SafeNumber(spellID, nil)
    if not spellID then return end
    local t = now()
    local buffs = {
        { 1243,  "fortitude",         1800 },
        { 21562, "fortitude",         3600 },
        { 588,   "inner_fire",        600  },
        { 14752, "divine_spirit",     1800 },
        { 27681, "divine_spirit",     3600 },
        { 976,   "shadow_protection", 600  },
        { 27683, "shadow_protection", 1200 },
        { 6346,  "fear_ward",         180  },
        { 15473, "shadowform",        nil  },
        { 15286, "vampiric_embrace",  30   },
        { 14751, "inner_focus",       15   },
        { 10060, "power_infusion",    15   },
        { 17,    "pw_shield",         30   },
    }
    local allyUnit = (UnitExists("target") and addon.Healer and addon.Healer.IsUnitFriendlyPlayer("target")
        and not (addon.UnitIsSame and addon.UnitIsSame("target", "player")))
        and "target" or "player"
    for _, info in ipairs(buffs) do
        if Priest.SameFamily(spellID, info[1]) then
            if info[1] ~= 17 or allyUnit == "player" then
                Priest.BuffBeliefs[info[2]] = {
                    expires = info[3] and (t + info[3]) or nil,
                    appliedAt = t,
                }
                if info[1] == 17 then
                    Priest.BuffBeliefs.weakened_soul = { expires = t + 15, appliedAt = t }
                end
            end
        end
    end

    local allyGuid = unitGUIDSafe(allyUnit)
    if allyGuid then
        local allyBuffs = {
            { 17,    "pw_shield",       30, true },
            { 139,   "renew",           15, false },
            { 33076, "prayer_mending",  30, false },
            { 552,   "abolish_disease", 20, false },
            { 33206, "pain_supp",       8,  false },
            { 47788, "guardian_spirit", 10, false },
        }
        for _, info in ipairs(allyBuffs) do
            if Priest.SameFamily(spellID, info[1]) then
                Priest.AllyBeliefs[allyGuid] = Priest.AllyBeliefs[allyGuid] or {}
                Priest.AllyBeliefs[allyGuid][info[2]] = { expires = t + info[3], appliedAt = t }
                if info[4] then
                    Priest.AllyBeliefs[allyGuid].weakened_soul = { expires = t + 15, appliedAt = t }
                end
            end
        end
    end

    local guid = currentTargetGUID()
    if guid then
        for baseID, info in pairs(DOT_DURATIONS) do
            if Priest.SameFamily(spellID, baseID) then
                Priest.TargetBeliefs[info.key] = {
                    guid = guid,
                    expires = t + info.duration,
                }
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Priest-specific rotation predicates (registered on Priest.RotationPredicates)
-- ---------------------------------------------------------------------------
local P = Priest.RotationPredicates

P["priest_has_enemy"] = {
    label = LBL("Alvo inimigo atacável", "Attackable enemy target"),
    fn = function(env) return env.hasActiveEnemy == true end,
}

P["priest_needs_shadowform"] = {
    label = LBL("Forma de Sombra ausente", "Shadowform missing"),
    fn = function(env) return env.hasActiveEnemy and not env.shadowformActive end,
}

P["priest_interrupt"] = {
    label = LBL("Alvo conjurando (Silêncio)", "Enemy casting (Silence)"),
    fn = function(env) return env.hasActiveEnemy and env.targetInterruptible == true end,
}

P["priest_defensive_shield"] = {
    label = LBL("Vida <= 60% em combate (sem Alma Enfraquecida)", "Health <= 60% in combat (no Weakened Soul)"),
    fn = function(env)
        return env.inCombat and env.myHealth ~= nil and env.myHealth <= 60
            and not env.pwShieldActive and not env.weakenedSoul
    end,
}

P["priest_inner_focus"] = {
    label = LBL("Foco Interior pronto em combate", "Inner Focus ready in combat"),
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy and not env.innerFocusActive
    end,
}

P["priest_power_infusion"] = {
    label = LBL("Infusão de Poder em combate", "Power Infusion in combat"),
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy and not env.powerInfusionActive
    end,
}

P["priest_vampiric_embrace"] = {
    label = LBL("Abraço Vampírico ausente em combate", "Vampiric Embrace missing in combat"),
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy and not env.vampiricEmbraceActive
    end,
}

P["priest_shadowfiend"] = {
    label = LBL("Demônio das Sombras (mana <= 65% em combate)", "Shadowfiend (mana <= 65% in combat)"),
    fn = function(env)
        local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 65, "player")
        return env.inCombat and env.hasActiveEnemy and lowMana
    end,
}

P["priest_sw_pain_missing"] = {
    label = LBL("Palavra Sombria: Dor ausente", "Shadow Word: Pain missing"),
    fn = function(env)
        return env.hasActiveEnemy and not env.swPainActive
    end,
}

P["priest_devouring_plague_missing"] = {
    label = LBL("Praga Devoradora ausente (mana > 15%)", "Devouring Plague missing (mana > 15%)"),
    fn = function(env)
        return env.hasActiveEnemy and (addon.HasManaPct(15)) and not env.devouringPlagueActive
    end,
}

P["priest_vampiric_touch_missing"] = {
    label = LBL("Toque Vampírico ausente (parado)", "Vampiric Touch missing (standing still)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and not env.vampiricTouchActive
    end,
}

P["priest_mind_blast"] = {
    label = LBL("Impacto Mental pronto (parado)", "Mind Blast ready (standing still)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and (addon.HasManaPct(12))
    end,
}

P["priest_sw_death"] = {
    label = LBL("Palavra Sombria: Morte (vida > 35%)", "Shadow Word: Death (health > 35%)"),
    fn = function(env)
        local safeHP = (env.myHealth == nil or env.myHealth > 35)
        return env.hasActiveEnemy and safeHP and (addon.HasManaPct(12))
    end,
}

P["priest_mind_flay"] = {
    label = LBL("Açoite Mental (filler parado)", "Mind Flay (standing filler)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and (addon.HasManaPct(10))
    end,
}

P["priest_holy_fire_missing"] = {
    label = LBL("Fogo Sagrado ausente (parado)", "Holy Fire missing (standing still)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and (addon.HasManaPct(15))
            and not env.holyFireActive
    end,
}

P["priest_penance"] = {
    label = LBL("Penitência pronta (parado)", "Penance ready (standing still)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and (addon.HasManaPct(12))
    end,
}

P["priest_holy_nova_aoe"] = {
    label = LBL("Nova Sagrada (Área 2+ em alcance curto)", "Holy Nova (AoE 2+ close range)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and env.isMelee
            and (addon.HasManaPct(25))
    end,
}

P["priest_smite"] = {
    label = LBL("Punição / Smite (filler parado)", "Smite (standing filler)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and (addon.HasManaPct(10))
    end,
}

P["priest_smite_low_level"] = {
    label = LBL("Punição (nível baixo, fora de Forma de Sombra)", "Smite (low level, outside Shadowform)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving and not env.shadowformActive
            and not Priest.ResolveID(15407) and (addon.HasManaPct(10))
    end,
}

P["priest_wand_filler"] = {
    label = LBL("Varinha (mana baixa <= 12%)", "Wand Shoot (low mana <= 12%)"),
    fn = function(env)
        local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 12, "player")
        return env.hasActiveEnemy and env.hasWand and lowMana and not addon.AutoShoot
    end,
}

-- ---------------------------------------------------------------------------
-- Priest HEALER predicates (Group / Raid triage, range-verified)
-- ---------------------------------------------------------------------------
local function healTargetAliveInRange(env)
    return env.healUnit ~= nil and not env.healIsDead and env.healInRange == true and env.healHP ~= nil
end

P["priest_heal_resurrection"] = {
    label = LBL("Reviver aliado morto (fora de combate, parado, em alcance)", "Resurrect dead ally (out of combat, standing, in range)"),
    fn = function(env)
        return not env.inCombat and not env.isMoving
            and env.healUnit ~= nil and env.healIsDead == true and env.healInResRange == true
    end,
}

P["priest_heal_fade"] = {
    label = LBL("Desvanecer (aggro no curandeiro em grupo)", "Fade (healer has aggro in group)"),
    fn = function(env)
        return env.inCombat and env.inGroup == true and env.playerHasAggro == true
    end,
}

P["priest_heal_desperate_prayer"] = {
    label = LBL("Prece Desesperada (emergência própria <= 40% vida)", "Desperate Prayer (self emergency <= 40% HP)"),
    fn = function(env)
        return env.inCombat and env.myHealth ~= nil and env.myHealth <= 40
    end,
}

P["priest_heal_guardian_spirit"] = {
    label = LBL("Espírito Guardião (aliado crítico <= 30% em combate)", "Guardian Spirit (critical ally <= 30% in combat)"),
    fn = function(env)
        return env.inCombat and healTargetAliveInRange(env) and env.healHP <= 30
    end,
}

P["priest_heal_pain_suppression"] = {
    label = LBL("Supressão de Dor (aliado crítico <= 35% em combate)", "Pain Suppression (critical ally <= 35% in combat)"),
    fn = function(env)
        return env.inCombat and healTargetAliveInRange(env) and env.healHP <= 35
    end,
}

P["priest_heal_shield_emergency"] = {
    label = LBL("Escudo de emergência (<= 45% vida em combate, sem Alma Enfraquecida)", "Emergency PW: Shield (<= 45% HP in combat, no Weakened Soul)"),
    fn = function(env)
        return env.inCombat and healTargetAliveInRange(env) and env.healHP <= 45
            and not env.healTargetShield and not env.healTargetWeakenedSoul
    end,
}

P["priest_heal_inner_focus"] = {
    label = LBL("Foco Interior (cura pesada <= 50% ou grupo ferido 3+)", "Inner Focus (heavy heal <= 50% or 3+ injured)"),
    fn = function(env)
        return env.inCombat and not env.innerFocusActive and (
            (healTargetAliveInRange(env) and env.healHP <= 50)
            or (env.injuredCount72 or 0) >= 3
        )
    end,
}

P["priest_heal_power_infusion"] = {
    label = LBL("Infusão de Poder (pressão de cura em combate)", "Power Infusion (heavy healing pressure in combat)"),
    fn = function(env)
        return env.inCombat and not env.powerInfusionActive and (
            (healTargetAliveInRange(env) and env.healHP <= 50)
            or (env.criticalCount55 or 0) >= 2
            or (env.injuredCount72 or 0) >= 3
        )
    end,
}

P["priest_heal_divine_hymn"] = {
    label = LBL("Hino Divino (emergência em grupo: 3+ <= 55% vida, parado)", "Divine Hymn (group emergency: 3+ <= 55% HP, standing)"),
    fn = function(env)
        return env.inCombat and not env.isMoving and (env.criticalCount55 or 0) >= 3
    end,
}

P["priest_heal_penance_emergency"] = {
    label = LBL("Penitência urgente (<= 55% vida, parado)", "Urgent Penance (<= 55% HP, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving and env.healHP <= 55
    end,
}

P["priest_heal_flash_emergency"] = {
    label = LBL("Cura Célere / Flash Heal urgente (<= 50% vida, parado)", "Emergency Flash Heal (<= 50% HP, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving and env.healHP <= 50
    end,
}

P["priest_heal_circle_of_healing"] = {
    label = LBL("Círculo de Cura (AoE instantânea: 3+ <= 82% vida)", "Circle of Healing (instant AoE: 3+ <= 82% HP)"),
    fn = function(env)
        return healTargetAliveInRange(env) and (env.injuredCount82 or 0) >= 3
    end,
}

P["priest_heal_prayer_of_mending"] = {
    label = LBL("Prece da Recomposição (em combate: tanque ou 2+ feridos)", "Prayer of Mending (in combat: tank or 2+ injured)"),
    fn = function(env)
        return env.inCombat and healTargetAliveInRange(env)
            and not env.healTargetPoM
            and ((env.injuredCount82 or 0) >= 2 or (env.healIsTank and env.healHP <= 88) or env.healHP <= 78)
    end,
}

P["priest_heal_prayer_of_healing"] = {
    label = LBL("Prece de Cura (AoE em grupo: 3+ <= 72% vida, parado)", "Prayer of Healing (group AoE: 3+ <= 72% HP, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving
            and (env.injuredCount72 or 0) >= 3 and (addon.HasManaPct(20))
    end,
}

P["priest_heal_binding_heal"] = {
    label = LBL("Cura Vinculada (aliado <= 75% E curandeiro <= 78%, parado)", "Binding Heal (ally <= 75% AND healer <= 78%, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving and not env.healIsSelf
            and env.healHP <= 75 and env.myHealth ~= nil and env.myHealth <= 78
    end,
}

P["priest_heal_shield_tank"] = {
    label = LBL("Escudo preventivo no Tanque (em combate <= 85%, sem Alma Enfraquecida)", "Proactive Tank PW: Shield (in combat <= 85%, no Weakened Soul)"),
    fn = function(env)
        return env.inCombat and healTargetAliveInRange(env)
            and env.healIsTank == true and env.healHP <= 85
            and not env.healTargetShield and not env.healTargetWeakenedSoul
    end,
}

P["priest_heal_penance"] = {
    label = LBL("Penitência eficiente (<= 78% vida, parado)", "Efficient Penance (<= 78% HP, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving and env.healHP <= 78
    end,
}

P["priest_heal_dispel_magic"] = {
    label = LBL("Dissipar Magia (debuff mágico no aliado, sem emergência crítica)", "Dispel Magic (Magic debuff on ally, no critical HP)"),
    fn = function(env)
        return healTargetAliveInRange(env) and env.healDispelMagic == true and env.healHP > 45
    end,
}

P["priest_heal_abolish_disease"] = {
    label = LBL("Abolir Doença (debuff de doença no aliado, sem buff ativo)", "Abolish Disease (Disease debuff on ally, buff missing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and env.healDispelDisease == true
            and env.healHP > 45 and not env.healTargetAbolishDisease
    end,
}

P["priest_heal_cure_disease"] = {
    label = LBL("Curar Doença (fallback se Abolir Doença não conhecido)", "Cure Disease (fallback when Abolish Disease unknown)"),
    fn = function(env)
        return healTargetAliveInRange(env) and env.healDispelDisease == true
            and env.healHP > 45 and not Priest.ResolveID(552)
    end,
}

P["priest_heal_shield_moving"] = {
    label = LBL("Escudo em movimento (<= 75% vida, sem Alma Enfraquecida)", "PW: Shield while moving (<= 75% HP, no Weakened Soul)"),
    fn = function(env)
        return env.isMoving and healTargetAliveInRange(env) and env.healHP <= 75
            and not env.healTargetShield and not env.healTargetWeakenedSoul
    end,
}

P["priest_heal_holy_nova_moving"] = {
    label = LBL("Nova Sagrada em movimento (3+ aliados <= 82% vida)", "Holy Nova while moving (3+ allies <= 82% HP)"),
    fn = function(env)
        return env.isMoving and (env.injuredCount82 or 0) >= 3 and (addon.HasManaPct(25))
    end,
}

P["priest_heal_greater_heal"] = {
    label = LBL("Cura Maior (cura eficiente para dano moderado/alto <= 75%, parado)", "Greater Heal (efficient heavy heal <= 75%, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving and env.healHP <= 75
    end,
}

P["priest_heal_mid"] = {
    label = LBL("Cura (fallback eficiente antes de Cura Maior, <= 78%, parado)", "Heal (mid-level efficient fallback <= 78%, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving
            and not Priest.ResolveID(2060) and env.healHP <= 78
    end,
}

P["priest_heal_lesser"] = {
    label = LBL("Cura Menor (nível baixo antes de Cura/Cura Maior, <= 82%, parado)", "Lesser Heal (low-level fallback <= 82%, standing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving
            and not Priest.ResolveID(2054) and not Priest.ResolveID(2060) and env.healHP <= 82
    end,
}

P["priest_heal_flash_fast"] = {
    label = LBL("Cura Célere / Flash Heal (dano moderado <= 62% se Cura Maior indisponível)", "Flash Heal (moderate <= 62% fallback)"),
    fn = function(env)
        return healTargetAliveInRange(env) and not env.isMoving and env.healHP <= 62
    end,
}

P["priest_heal_renew"] = {
    label = LBL("Renovar (HoT instantânea <= 92% vida sem Renovar ativo)", "Renew (instant HoT <= 92% HP when missing)"),
    fn = function(env)
        return healTargetAliveInRange(env) and env.healHP <= 92 and not env.healTargetRenew
    end,
}

P["priest_heal_hymn_of_hope"] = {
    label = LBL("Hino de Esperança (recuperar mana <= 40%, grupo estável)", "Hymn of Hope (mana <= 40%, group stable)"),
    fn = function(env)
        local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 40, "player")
        return env.inCombat and not env.isMoving and lowMana and (env.criticalCount55 or 0) == 0
            and (env.healHP == nil or env.healHP > 65)
    end,
}

P["priest_heal_shadowfiend"] = {
    label = LBL("Demônio das Sombras (mana <= 60% com inimigo na mira, grupo estável)", "Shadowfiend (mana <= 60% with enemy target, group stable)"),
    fn = function(env)
        local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 60, "player")
        return env.inCombat and env.hasActiveEnemy and lowMana and (env.criticalCount55 or 0) == 0
    end,
}
