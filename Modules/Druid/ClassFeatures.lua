-- Combat Forever Assistant — Druid module: class-specific mechanics.
-- Shapeshift form detection (CAT / BEAR / MOONKIN / HUMANOID), slot-based
-- combat debuff beliefs, buff beliefs, and Druid-specific rotation predicates.
-- Consumes shared utilities from Core.lua and Shared\Functions.lua.
local _, addon = ...

local Druid = addon.modules.DRUID or {}
addon.modules.DRUID = Druid
Druid.classTag = "DRUID"
Druid.addon = addon
Druid.Compat = addon.Compat
Druid.L = addon.L

-- Shared delegates expected by Core (e.g. SuggestRacial)
Druid.SpellName = addon.SpellName
Druid.CheckCastable = addon.CheckCastable

-- Register Forever Druid spell rank families into Core's global Compat layer
if addon.Compat and type(addon.Compat.RegisterSpellFamilies) == "function" then
    addon.Compat.RegisterSpellFamilies({
        { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990 },         -- Mark of the Wild
        { 21849, 21850, 26991 },                                     -- Gift of the Wild
        { 467, 782, 1075, 8914, 9756, 9910, 26992 },                 -- Thorns
        { 770, 778, 9749, 9907, 26993 },                             -- Faerie Fire
        { 16857, 17390, 17391, 17392, 27011 },                       -- Faerie Fire (Feral)
        { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912, 26984 },   -- Wrath
        { 2912, 8949, 8950, 8951, 9875, 9876, 25298, 26986 },        -- Starfire
        { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835, 26987, 26988 }, -- Moonfire
        { 5570, 24974, 24975, 24976, 24977 },                        -- Insect Swarm
        { 16914, 17401, 17402 },                                     -- Hurricane
        { 5221, 6800, 8992, 9829, 9830, 27001 },                     -- Shred
        { 1082, 3029, 5201, 9849, 9850, 27000 },                     -- Claw
        { 1822, 1823, 1824, 9904, 27003 },                           -- Rake
        { 1079, 9492, 9493, 9752, 9894, 9896, 27008 },               -- Rip
        { 22568, 22827, 22828, 22829, 31018 },                       -- Ferocious Bite
        { 5217, 6793, 9845, 9846 },                                  -- Tiger's Fury
        { 33876, 33982, 33983 },                                     -- Mangle (Cat)
        { 33878, 33986, 33987 },                                     -- Mangle (Bear)
        { 6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996 },         -- Maul
        { 779, 780, 769, 9754, 9908 },                               -- Swipe (Bear)
        { 99, 1735, 9490, 9747, 9898, 26998 },                       -- Demoralizing Roar
        { 5211, 6798, 8983 },                                        -- Bash
        { 5487, 9634 },                                              -- Bear / Dire Bear Form
        { 768 },                                                     -- Cat Form
        { 1066 },                                                    -- Aquatic Form
        { 24858, 24907 },                                            -- Moonkin Form
        { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, 26980 }, -- Regrowth
        { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, 26981 }, -- Rejuvenation
        { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297, 26978, 26979 }, -- Healing Touch
        { 22842, 22895, 22896 },                                     -- Frenzied Regeneration
    })
end

-- ---------------------------------------------------------------------------
-- Form detection (secret-safe, preserves last valid form if unreadable)
-- ---------------------------------------------------------------------------
local lastKnownForm = "HUMANOID"

local FORM_BY_SPELL_ID = {
    [768]   = "CAT",
    [1066]  = "AQUATIC",
    [5487]  = "BEAR",
    [9634]  = "BEAR",
    [24858] = "MOONKIN",
    [24907] = "MOONKIN",
}

local FORM_BY_SHAPESHIFT_ID = {
    [1]  = "CAT",
    [4]  = "AQUATIC",
    [5]  = "BEAR",
    [8]  = "BEAR",
    [31] = "MOONKIN",
}

function Druid.ActiveForm()
    -- 1) UnitPowerType is cheap and readable in combat: 3 = Energy (Cat), 1 = Rage (Bear)
    if type(UnitPowerType) == "function" then
        local ok, pt = pcall(UnitPowerType, "player")
        local powerType = ok and addon.SafeNumber(pt, nil) or nil
        if powerType == 3 then
            lastKnownForm = "CAT"
            return "CAT"
        elseif powerType == 1 then
            lastKnownForm = "BEAR"
            return "BEAR"
        end
    end

    -- 2) Shapeshift API (distinguishes Aquatic / Moonkin / Humanoid when powerType == 0)
    if type(GetShapeshiftFormID) == "function" then
        local ok, fid = pcall(GetShapeshiftFormID)
        local formID = ok and addon.SafeNumber(fid, nil) or nil
        if formID ~= nil then
            if formID == 0 then
                lastKnownForm = "HUMANOID"
                return "HUMANOID"
            end
            local mapped = FORM_BY_SHAPESHIFT_ID[formID] or FORM_BY_SPELL_ID[formID]
            if mapped then
                lastKnownForm = mapped
                return mapped
            end
            lastKnownForm = "OTHER"
            return "OTHER"
        end
    end

    if type(GetShapeshiftForm) == "function" then
        local ok, idx = pcall(GetShapeshiftForm)
        local index = ok and addon.SafeNumber(idx, nil) or nil
        if index ~= nil then
            if index == 0 then
                lastKnownForm = "HUMANOID"
                return "HUMANOID"
            end
            if type(GetShapeshiftFormInfo) == "function" then
                local okInfo, icon, isActive, _, spellID = pcall(GetShapeshiftFormInfo, index)
                if okInfo then
                    if type(icon) == "table" then spellID = icon.spellID or icon.spellId end
                    spellID = addon.SafeNumber(spellID, nil)
                    if spellID and FORM_BY_SPELL_ID[spellID] then
                        lastKnownForm = FORM_BY_SPELL_ID[spellID]
                        return lastKnownForm
                    end
                    if isActive == false then
                        lastKnownForm = "HUMANOID"
                        return "HUMANOID"
                    end
                end
            end
        end
    end

    -- 3) Aura fallback (works out of combat)
    if addon.HasBuff("player", 1066) then
        lastKnownForm = "AQUATIC"
        return "AQUATIC"
    end
    if addon.HasBuff("player", 24858) or addon.HasBuff("player", 24907) then
        lastKnownForm = "MOONKIN"
        return "MOONKIN"
    end
    if addon.HasBuff("player", 768) then
        lastKnownForm = "CAT"
        return "CAT"
    end
    if addon.HasBuff("player", 5487) or addon.HasBuff("player", 9634) then
        lastKnownForm = "BEAR"
        return "BEAR"
    end

    -- 4) If powerType == 0 and no form aura detected, player is in Humanoid form
    if type(UnitPowerType) == "function" then
        local ok, pt = pcall(UnitPowerType, "player")
        if ok and addon.SafeNumber(pt, nil) == 0 then
            lastKnownForm = "HUMANOID"
            return "HUMANOID"
        end
    end

    return lastKnownForm
end

-- ---------------------------------------------------------------------------
-- Beliefs: slot-based target debuffs (GUID is secret in dungeons/raids)
-- and player buff beliefs (auras are secret in combat).
-- ---------------------------------------------------------------------------
local targetBeliefSlot = 0
Druid.buffBeliefs = {}
Druid.targetBeliefs = {}

local DOT_INFO = {
    [1079]  = { key = "rip", duration = 12 },
    [1822]  = { key = "rake", duration = 9 },
    [5570]  = { key = "insect_swarm", duration = 12 },
    [8921]  = { key = "moonfire", duration = 12 },
    [99]    = { key = "demoralizing_roar", duration = 30 },
    [16857] = { key = "faerie_fire_feral", duration = 40 },
    [770]   = { key = "faerie_fire", duration = 40 },
    [33876] = { key = "mangle_cat", duration = 12 },
    [33878] = { key = "mangle_bear", duration = 12 },
}

local function sameFamily(spellID, baseID)
    if spellID == baseID then return true end
    local fam = addon.Compat and addon.Compat.FamilyOf
    return fam and fam[spellID] ~= nil and fam[spellID] == fam[baseID]
end

function Druid.OnTargetChanged()
    targetBeliefSlot = targetBeliefSlot + 1
    wipe(Druid.targetBeliefs)
end

function Druid.ClearAllBeliefs()
    wipe(Druid.buffBeliefs)
    wipe(Druid.targetBeliefs)
end

function Druid.RegisterCast(spellID)
    local id = addon.SafeNumber(spellID, nil)
    if not id then return end
    local now = addon.SafeNumber(GetTime(), 0) or 0

    if sameFamily(id, 1126) or sameFamily(id, 21849) then
        Druid.buffBeliefs.mark_of_the_wild = { expires = now + 1800 }
        return
    elseif sameFamily(id, 467) then
        Druid.buffBeliefs.thorns = { expires = now + 600 }
        return
    elseif sameFamily(id, 5217) then
        Druid.buffBeliefs.tiger_fury = { expires = now + 6 }
        return
    elseif id == 22812 then
        Druid.buffBeliefs.barkskin = { expires = now + 12 }
        return
    end

    for baseID, info in pairs(DOT_INFO) do
        if sameFamily(id, baseID) then
            Druid.targetBeliefs[info.key] = {
                slot = targetBeliefSlot,
                expires = now + info.duration,
            }
            return
        end
    end
end

function Druid.IsTargetDebuffActive(spellID, key, requirePlayer)
    local belief = Druid.targetBeliefs[key]
    local now = addon.SafeNumber(GetTime(), 0) or 0
    if type(belief) == "table" and belief.slot == targetBeliefSlot and now < belief.expires then
        return true
    end
    if belief then Druid.targetBeliefs[key] = nil end

    local name = addon.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckDebuff
        and addon.Compat.CheckDebuff(name, "target", requirePlayer) then
        return true
    end
    return addon.HasDebuff("target", spellID)
end

function Druid.IsPlayerBuffActive(spellID, key, familyName)
    local status
    if familyName and addon.BuffLib and addon.BuffLib.Status then
        local ok, result = pcall(addon.BuffLib.Status, addon.BuffLib, "player", familyName)
        if ok and type(result) == "table" then
            status = result
            if status.present then return true end
        end
    end

    if addon.HasBuff("player", spellID) then return true end
    local name = addon.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckBuff
        and addon.Compat.CheckBuff(name, "player") then
        return true
    end

    local belief = Druid.buffBeliefs[key]
    if status and status.readable then
        Druid.buffBeliefs[key] = nil
        return false
    end
    local now = addon.SafeNumber(GetTime(), 0) or 0
    return type(belief) == "table" and now < belief.expires or false
end

-- ---------------------------------------------------------------------------
-- Druid-specific predicates (inherits generic predicates from Shared).
-- ---------------------------------------------------------------------------
local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end

Druid.RotationPredicates = setmetatable(Druid.RotationPredicates or {}, {
    __index = addon.RotationPredicates,
})
local P = Druid.RotationPredicates

-- Shared Druid helpers
P["innervate_low_mana"] = {
    label = LBL("Mana baixa (<= 20%)", "Low mana (<= 20%)"),
    fn = function(env) return env.hasMana and (env.manaPct or 100) <= 20 end,
}

-- Balance predicates
P["needs_moonkin_form"] = {
    label = LBL("Sem Forma de Luniscante", "Moonkin Form missing"),
    fn = function(env) return env.hasActiveEnemy and env.form ~= "MOONKIN" end,
}
P["bal_enemy"] = {
    label = LBL("Equilíbrio com alvo inimigo", "Balance with enemy target"),
    fn = function(env) return env.hasActiveEnemy and (env.form == "HUMANOID" or env.form == "MOONKIN") end,
}
P["bal_needs_faerie_fire"] = {
    label = LBL("Sem Fogo Feérico", "Faerie Fire missing"),
    fn = function(env) return P["bal_enemy"].fn(env) and not env.targetDebuffFaerieFire end,
}
P["bal_needs_insect_swarm"] = {
    label = LBL("Sem Enxame de Insetos", "Insect Swarm missing"),
    fn = function(env) return P["bal_enemy"].fn(env) and not env.targetDebuffInsectSwarm end,
}
P["bal_needs_moonfire"] = {
    label = LBL("Sem Fogo Lunar", "Moonfire missing"),
    fn = function(env) return P["bal_enemy"].fn(env) and not env.targetDebuffMoonfire end,
}
P["bal_aoe"] = {
    label = LBL("Equilíbrio AoE (3+)", "Balance AoE (3+)"),
    fn = function(env) return P["bal_enemy"].fn(env) and env.isAoE end,
}

-- Feral: Bear Form (Tank) predicates — active ONLY when player is in Bear Form
local function inBearEnemy(env) return env.form == "BEAR" and env.hasActiveEnemy end

P["bear_frenzied_regen"] = {
    label = LBL("Urso: vida <= 50% e raiva >= 10", "Bear: HP <= 50% and rage >= 10"),
    fn = function(env)
        return env.form == "BEAR" and env.inCombat
            and env.myHP ~= nil and env.myHP <= 50
            and (env.rage == nil or env.rage >= 10)
    end,
}
P["bear_low_health"] = {
    label = LBL("Urso: vida <= 40%", "Bear: HP <= 40%"),
    fn = function(env)
        return env.form == "BEAR" and env.inCombat
            and env.myHP ~= nil and env.myHP <= 40 and not env.barkskinActive
    end,
}
P["bear_needs_enrage"] = {
    label = LBL("Urso: raiva baixa (< 20)", "Bear: low rage (< 20)"),
    fn = function(env)
        return inBearEnemy(env) and env.inCombat and (env.rage == nil or env.rage < 20)
    end,
}
P["bear_needs_taunt"] = {
    label = LBL("Urso: perdeu aggro (alvo atacando aliado)", "Bear: lost aggro (target attacking ally)"),
    fn = function(env)
        return inBearEnemy(env) and env.inCombat and env.lostAggro == true
    end,
}
P["bear_needs_bash"] = {
    label = LBL("Urso: alvo conjurando (interromper)", "Bear: target casting (interrupt)"),
    fn = function(env)
        return inBearEnemy(env) and env.inCombat and env.targetInterruptible and env.isMelee ~= false
    end,
}
P["bear_needs_faerie_fire"] = {
    label = LBL("Urso: sem Fogo Feérico (Feral)", "Bear: Feral Faerie Fire missing"),
    fn = function(env) return inBearEnemy(env) and not env.targetDebuffFaerieFireFeral end,
}
P["bear_needs_demo"] = {
    label = LBL("Urso: sem Rugido Desmoralizante", "Bear: Demoralizing Roar missing"),
    fn = function(env) return inBearEnemy(env) and not env.targetDebuffDemoralizingRoar end,
}
P["bear_needs_mangle"] = {
    label = LBL("Urso: sem Destroçar", "Bear: Mangle missing"),
    fn = function(env) return inBearEnemy(env) and not env.targetDebuffMangleBear end,
}
P["bear_aoe"] = {
    label = LBL("Urso: múltiplos inimigos (AoE)", "Bear: multiple enemies (AoE)"),
    fn = function(env) return inBearEnemy(env) and env.isAoE end,
}
P["bear_maul"] = {
    label = LBL("Urso: Malho (raiva >= 15)", "Bear: Maul (rage >= 15)"),
    fn = function(env) return inBearEnemy(env) and (env.rage == nil or env.rage >= 15) end,
}

-- Feral: Cat Form (Melee DPS) predicates — active ONLY when player is in Cat Form
local function inCatEnemy(env) return env.form == "CAT" and env.hasActiveEnemy end

P["cat_low_health"] = {
    label = LBL("Gato: vida <= 40%", "Cat: HP <= 40%"),
    fn = function(env)
        return env.form == "CAT" and env.inCombat
            and env.myHP ~= nil and env.myHP <= 40 and not env.barkskinActive
    end,
}
P["cat_tigers_fury"] = {
    label = LBL("Gato: energia <= 40 e Fúria do Tigre", "Cat: energy <= 40 and Tiger's Fury"),
    fn = function(env)
        return inCatEnemy(env) and (env.energy == nil or env.energy <= 40) and not env.tigerFuryActive
    end,
}
P["cat_needs_faerie_fire"] = {
    label = LBL("Gato: sem Fogo Feérico (Feral)", "Cat: Feral Faerie Fire missing"),
    fn = function(env) return inCatEnemy(env) and not env.targetDebuffFaerieFireFeral end,
}
P["cat_needs_mangle"] = {
    label = LBL("Gato: sem Destroçar", "Cat: Mangle missing"),
    fn = function(env)
        return inCatEnemy(env) and (env.combo or 0) < 5 and not env.targetDebuffMangleCat
    end,
}
P["cat_needs_rake"] = {
    label = LBL("Gato: sem Estraçalhar (Rake)", "Cat: Rake missing"),
    fn = function(env)
        return inCatEnemy(env) and (env.combo or 0) < 5 and not env.targetDebuffRake
    end,
}
P["cat_needs_rip"] = {
    label = LBL("Gato: 5 pontos de combo, sem Rasgar (Rip)", "Cat: 5 combo points, Rip missing"),
    fn = function(env)
        return inCatEnemy(env) and (env.combo or 0) >= 5
            and not env.targetDebuffRip
            and (not env.targetHP or env.targetHP > 20)
    end,
}
P["cat_can_bite"] = {
    label = LBL("Gato: Mordida Feroz (5 CP ou execução)", "Cat: Ferocious Bite (5 CP or execute)"),
    fn = function(env)
        if not inCatEnemy(env) then return false end
        local cp = env.combo or 0
        if env.energy ~= nil and env.energy < 35 then return false end
        if cp >= 5 and env.targetDebuffRip then return true end
        if env.targetHP and env.targetHP <= 30 and cp >= 3 then return true end
        return false
    end,
}
P["cat_builder"] = {
    label = LBL("Gato: gerar pontos de combo (< 5 CP)", "Cat: build combo points (< 5 CP)"),
    fn = function(env)
        return inCatEnemy(env) and (env.combo or 0) < 5
    end,
}

-- Restoration predicates
P["heal_swiftmend"] = {
    label = LBL("Cura urgente (<= 45%) com HoT ativo", "Urgent heal (<= 45%) with HoT active"),
    fn = function(env) return env.healHealth ~= nil and env.healHealth <= 45 and env.hasHoT end,
}
P["heal_regrowth"] = {
    label = LBL("Vida do alvo <= 60%", "Target health <= 60%"),
    fn = function(env) return env.healHealth ~= nil and env.healHealth <= 60 end,
}
P["heal_touch"] = {
    label = LBL("Vida do alvo <= 70%", "Target health <= 70%"),
    fn = function(env) return env.healHealth ~= nil and env.healHealth <= 70 end,
}
P["heal_rejuvenation"] = {
    label = LBL("Vida <= 90% e sem Rejuvenescer", "Health <= 90% and Rejuvenation missing"),
    fn = function(env)
        if env.healHealth == nil or env.healHealth > 90 then return false end
        local name = addon.SpellName(774)
        return not (name and addon.Compat and addon.Compat.CheckBuff
            and addon.Compat.CheckBuff(name, env.healUnit))
    end,
}
