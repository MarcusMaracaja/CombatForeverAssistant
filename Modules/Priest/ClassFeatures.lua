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

function Priest.HasWeakenedSoul()
    -- Weakened Soul debuff ID 6788 prevents re-applying Power Word: Shield
    if addon.HasDebuff and addon.HasDebuff("player", 6788) then return true end
    local wsName = addon.SpellName and addon.SpellName(6788)
    if wsName and addon.Compat and addon.Compat.CheckDebuff and addon.Compat.CheckDebuff(wsName, "player", false) then
        return true
    end
    local b = Priest.BuffBeliefs.weakened_soul
    return type(b) == "table" and now() < (b.expires or 0)
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
    for _, info in ipairs(buffs) do
        if Priest.SameFamily(spellID, info[1]) then
            Priest.BuffBeliefs[info[2]] = {
                expires = info[3] and (t + info[3]) or nil,
                appliedAt = t,
            }
            if info[1] == 17 then
                Priest.BuffBeliefs.weakened_soul = { expires = t + 15, appliedAt = t }
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
