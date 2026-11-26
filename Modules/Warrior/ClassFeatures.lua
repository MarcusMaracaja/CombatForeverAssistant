-- Combat Forever Assistant — Warrior module: class-specific helpers, spell families,
-- stance / shield / Sunder Armor / DoT tracking, and Warrior predicates for Arms,
-- Fury and Protection. Uses Shared/Functions.lua for all Rage & generic checks.
local _, addon = ...

local Warrior = addon.modules.WARRIOR or {}
addon.modules.WARRIOR = Warrior
Warrior.classTag = "WARRIOR"
Warrior.addon = addon
Warrior.Compat = addon.Compat
Warrior.RotationPredicates = Warrior.RotationPredicates or {}
Warrior.RotationSpecs = Warrior.RotationSpecs or {}
Warrior.BuffBeliefs = Warrior.BuffBeliefs or {}
Warrior.TargetBeliefs = Warrior.TargetBeliefs or {}

local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end

-- ---------------------------------------------------------------------------
-- Warrior spell rank families (Vanilla / WoW Forever ranks).
-- Registered globally in Core so SpellKnown, HighestKnownSpellID, ResolveKnownID,
-- IsSpellOnCD and RunDeclaredRotation recognize every rank automatically.
-- ---------------------------------------------------------------------------
local WARRIOR_FAMILIES = {
    { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286, 29707, 30324, 47449, 47450 }, -- Heroic Strike
    { 845, 7369, 11608, 11609, 20569, 25231, 47519, 47520 },                               -- Cleave
    { 772, 6546, 6547, 6548, 11572, 11573, 11574, 25208, 46845, 47465 },                   -- Rend
    { 7384, 7887, 11584, 11585 },                                                          -- Overpower
    { 12294, 21551, 21552, 21553, 25248, 30330, 47485, 47486 },                            -- Mortal Strike
    { 23881, 23892, 23893, 23894, 25251, 30335 },                                          -- Bloodthirst
    { 5308, 20658, 20660, 20661, 20662, 25234, 25236, 47470, 47471 },                      -- Execute
    { 1464, 8820, 11604, 11605, 25241, 25242, 47474, 47475 },                              -- Slam
    { 6572, 6574, 7379, 11600, 11601, 25288, 25269, 30357, 57823 },                        -- Revenge
    { 23922, 23923, 23924, 23925, 25258, 30356, 47487, 47488 },                            -- Shield Slam
    { 20243, 30016, 30022, 47497, 47498 },                                                 -- Devastate
    { 7386, 7405, 8380, 11596, 11597, 25225, 47467 },                                      -- Sunder Armor
    { 6343, 8198, 8204, 8205, 11580, 11581, 25264, 47501, 47502 },                         -- Thunder Clap
    { 1160, 6190, 11554, 11555, 11556, 25202, 25203, 47437 },                              -- Demoralizing Shout
    { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 2048, 47436 },                         -- Battle Shout
    { 469, 47439, 47440 },                                                                 -- Commanding Shout
    { 1715, 7372, 7373, 25212 },                                                           -- Hamstring
    { 6552, 6554 },                                                                        -- Pummel
    { 72, 1671, 1672 },                                                                    -- Shield Bash
    { 100, 6178, 11578 },                                                                  -- Charge
    { 20252, 20616, 20617 },                                                               -- Intercept
    { 1680 },                                                                              -- Whirlwind
    { 34428 },                                                                             -- Victory Rush (baseline lvl 20 Forever)
    { 12328 },                                                                             -- Sweeping Strikes
    { 12292 },                                                                             -- Death Wish
    { 2565 },                                                                              -- Shield Block
    { 355 },                                                                               -- Taunt
    { 2687 },                                                                              -- Bloodrage
    { 18499 },                                                                             -- Berserker Rage
    { 12975 },                                                                             -- Last Stand
    { 871 },                                                                               -- Shield Wall
    { 12809 },                                                                             -- Concussion Blow
    { 46968 },                                                                             -- Shockwave
    { 46924 },                                                                             -- Bladestorm
    { 2457 },                                                                              -- Battle Stance
    { 71 },                                                                                -- Defensive Stance
    { 2458 },                                                                              -- Berserker Stance
}

if addon.Compat and type(addon.Compat.RegisterSpellFamilies) == "function" then
    addon.Compat.RegisterSpellFamilies(WARRIOR_FAMILIES)
end

local STANCE_FORM_IDS = {
    [17] = "BATTLE",
    [18] = "DEFENSIVE",
    [19] = "BERSERKER",
}

local STANCE_SPELL_IDS = {
    [2457] = "BATTLE",
    [71]   = "DEFENSIVE",
    [2458] = "BERSERKER",
}

local DOT_INFO = {
    [772]  = { key = "rend",         duration = 15 },
    [1160] = { key = "demo_shout",   duration = 30 },
    [6343] = { key = "thunder_clap", duration = 20 },
    [1715] = { key = "hamstring",    duration = 15 },
    [7386] = { key = "sunder_armor", duration = 30, stacks = true },
    [20243]= { key = "sunder_armor", duration = 30, stacks = true }, -- Devastate refreshes/stacks Sunder
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

function Warrior.SameFamily(spellID, baseID)
    if type(spellID) ~= "number" or type(baseID) ~= "number" then return false end
    if spellID == baseID then return true end
    local fam = addon.Compat and addon.Compat.FamilyOf
    return fam ~= nil and fam[spellID] ~= nil and fam[spellID] == fam[baseID]
end

function Warrior.ResolveID(spellID)
    if type(spellID) ~= "number" then return nil end
    return (addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(spellID)) or nil
end

function Warrior.SpellName(spellID)
    local id = Warrior.ResolveID(spellID) or spellID
    return addon.SpellName and addon.SpellName(id)
        or (addon.Compat and addon.Compat.SpellName and addon.Compat.SpellName(id))
end

-- ---------------------------------------------------------------------------
-- Stance & Shield detection
-- ---------------------------------------------------------------------------
function Warrior.GetActiveStance()
    if type(GetShapeshiftFormID) == "function" then
        local ok, rawID = pcall(GetShapeshiftFormID)
        local formID = ok and addon.SafeNumber(rawID, nil) or nil
        if formID and STANCE_FORM_IDS[formID] then
            return STANCE_FORM_IDS[formID]
        end
    end

    if type(GetShapeshiftForm) == "function" then
        local ok, rawIdx = pcall(GetShapeshiftForm)
        local idx = ok and addon.SafeNumber(rawIdx, nil) or nil
        if idx and idx > 0 then
            if type(GetShapeshiftFormInfo) == "function" then
                local okI, icon, _, _, spellID = pcall(GetShapeshiftFormInfo, idx)
                if okI then
                    if type(icon) == "table" then spellID = icon.spellID or icon.spellId end
                    spellID = addon.SafeNumber(spellID, nil)
                    if spellID and STANCE_SPELL_IDS[spellID] then
                        return STANCE_SPELL_IDS[spellID]
                    end
                end
            end
            if idx == 1 then return "BATTLE" end
            if idx == 2 then return "DEFENSIVE" end
            if idx == 3 then return "BERSERKER" end
        end
    end

    for spellID, stance in pairs(STANCE_SPELL_IDS) do
        local name = Warrior.SpellName(spellID)
        if name and addon.Compat and addon.Compat.CheckBuff and addon.Compat.CheckBuff(name, "player") then
            return stance
        end
    end
    return "UNKNOWN"
end

function Warrior.HasShieldEquipped()
    if type(GetInventoryItemID) ~= "function" then return false end
    local ok, itemID = pcall(GetInventoryItemID, "player", 17) -- SecondaryHandSlot = 17
    if not ok or type(itemID) ~= "number" or itemID <= 0 then return false end
    local getter = (C_Item and type(C_Item.GetItemInfoInstant) == "function" and C_Item.GetItemInfoInstant)
        or (type(GetItemInfoInstant) == "function" and GetItemInfoInstant)
    if getter then
        local okI, _, _, _, equipLoc = pcall(getter, itemID)
        if okI and equipLoc == "INVTYPE_SHIELD" then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Buff / Debuff / Sunder Stacks helpers (secret-safe + beliefs)
-- ---------------------------------------------------------------------------
function Warrior.IsBuffActive(spellID, beliefKey, auraFamily)
    local status
    if auraFamily and addon.BuffLib and addon.BuffLib.Status then
        local ok, res = pcall(addon.BuffLib.Status, addon.BuffLib, "player", auraFamily)
        if ok and type(res) == "table" then
            status = res
            if status.present then return true end
        end
    end
    local name = Warrior.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckBuff and addon.Compat.CheckBuff(name, "player", false) then
        return true
    end
    if addon.HasBuff and addon.HasBuff("player", spellID) then
        return true
    end
    local belief = beliefKey and Warrior.BuffBeliefs[beliefKey] or nil
    if status and status.readable then
        if type(belief) == "table" and (now() - (belief.appliedAt or 0)) < 2.0 then
            return true
        end
        if beliefKey then Warrior.BuffBeliefs[beliefKey] = nil end
        return false
    end
    if type(belief) == "table" then
        return belief.expires == nil or now() < belief.expires
    end
    return false
end

function Warrior.IsTargetDebuffActive(spellID, beliefKey, requirePlayer)
    local name = Warrior.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckDebuff and addon.Compat.CheckDebuff(name, "target", requirePlayer) then
        return true
    end
    local guid = currentTargetGUID()
    local b = beliefKey and Warrior.TargetBeliefs[beliefKey] or nil
    if type(b) == "table" and guid ~= nil and b.guid == guid and now() < (b.expires or 0) then
        return true
    end
    if b and (not guid or b.guid ~= guid or now() >= (b.expires or 0)) then
        Warrior.TargetBeliefs[beliefKey] = nil
    end
    return false
end

function Warrior.GetSunderStacks()
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        local fam = addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[7386]
        local expectedName = Warrior.SpellName(7386)
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
            if not ok or type(aura) ~= "table" then break end
            local okID, aid = pcall(function() return aura.spellId or aura.spellID end)
            aid = okID and addon.SafeNumber(aid, nil) or nil
            local okN, nm = pcall(function() return aura.name end)
            nm = okN and addon.SafeString and addon.SafeString(nm, nil) or nil
            local matches = (nm and expectedName and nm == expectedName)
                or (aid and (aid == 7386 or (fam and addon.Compat.FamilyOf[aid] == fam)))
            if matches then
                local okS, st = pcall(function() return aura.applications end)
                local count = okS and addon.SafeNumber(st, nil) or nil
                if count ~= nil then return math.max(1, count) end
                local b = Warrior.TargetBeliefs.sunder_armor
                return (type(b) == "table" and b.stacks) or 1
            end
        end
    end
    local guid = currentTargetGUID()
    local b = Warrior.TargetBeliefs.sunder_armor
    if type(b) == "table" and guid ~= nil and b.guid == guid and now() < (b.expires or 0) then
        return b.stacks or 1
    end
    return 0
end

function Warrior.RecordCast(spellID)
    spellID = addon.SafeNumber(spellID, nil)
    if not spellID then return end
    local t = now()
    local buffs = {
        { 6673,  "battle_shout",     120 },
        { 469,   "commanding_shout", 120 },
        { 2565,  "shield_block",     5   },
        { 12292, "death_wish",       30  },
        { 12328, "sweeping_strikes", 20  },
        { 18499, "berserker_rage",   10  },
        { 12975, "last_stand",       20  },
        { 871,   "shield_wall",      10  },
    }
    for _, info in ipairs(buffs) do
        if Warrior.SameFamily(spellID, info[1]) then
            Warrior.BuffBeliefs[info[2]] = { expires = t + info[3], appliedAt = t }
        end
    end

    local guid = currentTargetGUID()
    if guid then
        for baseID, info in pairs(DOT_INFO) do
            if Warrior.SameFamily(spellID, baseID) then
                local prev = Warrior.TargetBeliefs[info.key]
                local stacks = 1
                if info.stacks and type(prev) == "table" and prev.guid == guid and t < (prev.expires or 0) then
                    stacks = math.min(5, (prev.stacks or 0) + 1)
                end
                Warrior.TargetBeliefs[info.key] = {
                    guid = guid,
                    expires = t + info.duration,
                    stacks = stacks,
                }
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Warrior-specific rotation predicates (uses global addon.HasRage / HasResourceAtMost!)
-- ---------------------------------------------------------------------------
local P = Warrior.RotationPredicates

P["war_needs_battle_stance"] = {
    label = LBL("Fora de Postura de Batalha", "Battle Stance missing"),
    fn = function(env) return env.hasActiveEnemy and env.stance ~= "BATTLE" end,
}

P["war_needs_defensive_stance"] = {
    label = LBL("Fora de Postura de Defesa", "Defensive Stance missing"),
    fn = function(env) return env.hasActiveEnemy and env.stance ~= "DEFENSIVE" end,
}

P["war_needs_berserker_stance"] = {
    label = LBL("Fora de Postura de Berserker", "Berserker Stance missing"),
    fn = function(env)
        return env.hasActiveEnemy and env.stance ~= "BERSERKER"
    end,
}

P["war_needs_battle_fallback"] = {
    label = LBL("Postura de Batalha (antes de Berserker)", "Battle Stance (before Berserker)"),
    fn = function(env)
        return env.hasActiveEnemy and not Warrior.ResolveID(2458) and env.stance ~= "BATTLE"
    end,
}

P["war_charge"] = {
    label = LBL("Investida (fora de combate, longe do melee)", "Charge (out of combat, outside melee)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.inCombat and env.stance == "BATTLE"
            and env.isMelee == false
    end,
}

P["war_intercept"] = {
    label = LBL("Interceptar (em combate, longe do melee)", "Intercept (in combat, outside melee)"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and env.stance == "BERSERKER"
            and env.isMelee == false and (addon.HasRage(10, 20252))
    end,
}

P["war_interrupt_pummel"] = {
    label = LBL("Alvo conjurando (Murro)", "Enemy casting (Pummel)"),
    fn = function(env)
        return env.hasActiveEnemy and env.targetInterruptible
            and env.stance == "BERSERKER" and (addon.HasRage(10, 6552))
    end,
}

P["war_interrupt_shield_bash"] = {
    label = LBL("Alvo conjurando (Escudada, com escudo)", "Enemy casting (Shield Bash, with shield)"),
    fn = function(env)
        return env.hasActiveEnemy and env.targetInterruptible and env.hasShield
            and env.stance ~= "BERSERKER" and (addon.HasRage(10, 72))
    end,
}

P["war_interrupt_concussion"] = {
    label = LBL("Alvo conjurando (Golpe de Concussão)", "Enemy casting (Concussion Blow)"),
    fn = function(env)
        return env.hasActiveEnemy and env.targetInterruptible and (addon.HasRage(15, 12809))
    end,
}

P["war_victory_rush"] = {
    label = LBL("Ímpeto da Vitória pronto (após abate)", "Victory Rush ready (after kill)"),
    fn = function(env) return env.hasActiveEnemy and env.isMelee ~= false end,
}

P["war_execute"] = {
    label = LBL("Executar (alvo <= 20% vida)", "Execute (target <= 20% health)"),
    fn = function(env)
        return env.hasActiveEnemy and env.stance ~= "DEFENSIVE"
            and env.targetHealth ~= nil and env.targetHealth <= 20
            and (addon.HasRage(15, Warrior.ResolveID(5308) or 5308))
    end,
}

P["war_overpower"] = {
    label = LBL("Subjugar pronto (Postura de Batalha)", "Overpower ready (Battle Stance)"),
    fn = function(env)
        return env.hasActiveEnemy and env.stance == "BATTLE"
            and (addon.HasRage(5, Warrior.ResolveID(7384) or 7384))
    end,
}

P["war_mortal_strike"] = {
    label = LBL("Golpe Mortal pronto (30+ raiva)", "Mortal Strike ready (30+ rage)"),
    fn = function(env)
        return env.hasActiveEnemy and (addon.HasRage(30, Warrior.ResolveID(12294) or 12294))
    end,
}

P["war_bloodthirst"] = {
    label = LBL("Sede de Sangue pronta (30+ raiva)", "Bloodthirst ready (30+ rage)"),
    fn = function(env)
        return env.hasActiveEnemy and (addon.HasRage(30, Warrior.ResolveID(23881) or 23881))
    end,
}

P["war_whirlwind"] = {
    label = LBL("Redemoinho pronto (Postura de Berserker)", "Whirlwind ready (Berserker Stance)"),
    fn = function(env)
        return env.hasActiveEnemy and env.stance == "BERSERKER" and env.isMelee ~= false
            and (addon.HasRage(25, 1680))
    end,
}

P["war_sweeping_strikes"] = {
    label = LBL("Golpes Amplos (Área 2+ em combate)", "Sweeping Strikes (AoE 2+ in combat)"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and env.isAoE
            and not env.sweepingStrikesActive and (addon.HasRage(30, 12328))
    end,
}

P["war_bladestorm"] = {
    label = LBL("Tornado de Lâminas (Área 2+)", "Bladestorm (AoE 2+)"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and env.isAoE and env.isMelee ~= false
            and (addon.HasRage(25, 46924))
    end,
}

P["war_death_wish"] = {
    label = LBL("Desejo de Morte em combate", "Death Wish in combat"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and not env.deathWishActive
            and (addon.HasRage(10, 12292))
    end,
}

P["war_rend"] = {
    label = LBL("Dilacerar ausente (alvo > 25% vida)", "Rend missing (target > 25% health)"),
    fn = function(env)
        return env.hasActiveEnemy and env.stance ~= "BERSERKER"
            and not env.rendActive
            and (env.targetHealth == nil or env.targetHealth > 25)
            and (addon.HasRage(10, Warrior.ResolveID(772) or 772))
    end,
}

P["war_slam"] = {
    label = LBL("Batida (parado, 15+ raiva)", "Slam (standing still, 15+ rage)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isMoving
            and (addon.HasRage(15, Warrior.ResolveID(1464) or 1464))
    end,
}

P["war_hamstring_pvp"] = {
    label = LBL("Cortar Tendão (PvP, alvo sem slow)", "Hamstring (PvP, target not slowed)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isPvP and env.stance ~= "DEFENSIVE"
            and not env.hamstringActive and (addon.HasRage(10, Warrior.ResolveID(1715) or 1715))
    end,
}

P["war_cleave_dump"] = {
    label = LBL("Cleave (Área 2+, excesso de raiva)", "Cleave (AoE 2+, excess rage)"),
    fn = function(env)
        if not (env.hasActiveEnemy and env.isAoE) then return false end
        local minRage = env.spec == "PROT" and 45 or 40
        return (addon.HasRage(minRage, Warrior.ResolveID(845) or 845))
    end,
}

P["war_heroic_strike_dump"] = {
    label = LBL("Golpe Heroico (gasto de raiva / filler)", "Heroic Strike (rage dump / low-level filler)"),
    fn = function(env)
        if not env.hasActiveEnemy or env.isAoE then return false end
        local hsID = Warrior.ResolveID(78) or 78
        -- At low levels before Mortal Strike / Bloodthirst / Shield Slam / Devastate,
        -- Heroic Strike is the main rage spender (15 rage); otherwise dump excess rage (>= 45).
        local hasCoreSpender = (env.spec == "ARMS" and Warrior.ResolveID(12294) ~= nil)
            or (env.spec == "FURY" and Warrior.ResolveID(23881) ~= nil)
            or (env.spec == "PROT" and (Warrior.ResolveID(23922) ~= nil or Warrior.ResolveID(20243) ~= nil))
        local minRage = hasCoreSpender and 45 or 15
        return (addon.HasRage(minRage, hsID))
    end,
}

-- Protection / Tank predicates
P["war_shield_wall"] = {
    label = LBL("Muralha de Escudos (vida <= 25%, com escudo)", "Shield Wall (health <= 25%, with shield)"),
    fn = function(env)
        return env.inCombat and env.hasShield and env.stance == "DEFENSIVE"
            and env.myHealth ~= nil and env.myHealth <= 25
    end,
}

P["war_last_stand"] = {
    label = LBL("Último Recurso (vida <= 30%)", "Last Stand (health <= 30%)"),
    fn = function(env)
        return env.inCombat and env.myHealth ~= nil and env.myHealth <= 30
    end,
}

P["war_taunt"] = {
    label = LBL("Provocar (alvo atacando aliado)", "Taunt (target attacking an ally)"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and env.stance == "DEFENSIVE"
            and env.hasTargetTarget and not env.targetTargetIsPlayer
    end,
}

P["war_bloodrage_low"] = {
    label = LBL("Fúria Sanguinária (raiva < 25 em combate)", "Bloodrage (rage < 25 in combat)"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat
            and (addon.HasResourceAtMost(addon.PowerType.RAGE, 24, "player"))
    end,
}

P["war_shield_block"] = {
    label = LBL("Bloqueio com Escudo (alvo te atacando, 10+ raiva)", "Shield Block (being attacked, 10+ rage)"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and env.hasShield
            and env.stance == "DEFENSIVE" and not env.shieldBlockActive
            and (not env.hasTargetTarget or env.targetTargetIsPlayer)
            and (addon.HasRage(10, 2565))
    end,
}

P["war_revenge"] = {
    label = LBL("Revanche pronta (Postura de Defesa)", "Revenge ready (Defensive Stance)"),
    fn = function(env)
        return env.hasActiveEnemy and env.stance == "DEFENSIVE"
            and (addon.HasRage(5, Warrior.ResolveID(6572) or 6572))
    end,
}

P["war_shield_slam"] = {
    label = LBL("Escudada Poderosa (com escudo, 20+ raiva)", "Shield Slam (with shield, 20+ rage)"),
    fn = function(env)
        return env.hasActiveEnemy and env.hasShield
            and (addon.HasRage(20, Warrior.ResolveID(23922) or 23922))
    end,
}

P["war_shockwave"] = {
    label = LBL("Onda de Choque (Área 2+)", "Shockwave (AoE 2+)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and env.isMelee ~= false
            and (addon.HasRage(15, 46968))
    end,
}

P["war_thunder_clap"] = {
    label = LBL("Trovoada (Área 2+ ou debuff ausente)", "Thunder Clap (AoE 2+ or debuff missing)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isMelee ~= false
            and (env.isAoE or not env.thunderClapActive)
            and (addon.HasRage(20, Warrior.ResolveID(6343) or 6343))
    end,
}

P["war_demo_shout"] = {
    label = LBL("Brado Desmoralizador ausente em combate", "Demoralizing Shout missing in combat"),
    fn = function(env)
        return env.hasActiveEnemy and env.inCombat and env.isMelee ~= false
            and not env.demoShoutActive
            and (addon.HasRage(10, Warrior.ResolveID(1160) or 1160))
    end,
}

P["war_sunder_armor"] = {
    label = LBL("Fender Armadura (< 5 cargas)", "Sunder Armor (< 5 stacks)"),
    fn = function(env)
        return env.hasActiveEnemy and (env.sunderStacks or 0) < 5
            and (addon.HasRage(15, Warrior.ResolveID(7386) or 7386))
    end,
}

P["war_devastate"] = {
    label = LBL("Devastar (com escudo, 15+ raiva)", "Devastate (with shield, 15+ rage)"),
    fn = function(env)
        return env.hasActiveEnemy and env.hasShield
            and (addon.HasRage(15, Warrior.ResolveID(20243) or 20243))
    end,
}
