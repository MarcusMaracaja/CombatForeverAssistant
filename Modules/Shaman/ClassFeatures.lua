-- Combat Forever Assistant — Shaman module: class-specific helpers, spell families,
-- weapon enchant / totem / Maelstrom / aura tracking, and Shaman predicates.
-- Relies on Shared/Functions.lua and Core.lua for all generic checks (resources,
-- target, PvP, spec detection, castable engine, cooldowns).
local _, addon = ...

local Shaman = addon.modules.SHAMAN or {}
addon.modules.SHAMAN = Shaman
Shaman.classTag = "SHAMAN"
Shaman.addon = addon
Shaman.Compat = addon.Compat
Shaman.RotationPredicates = Shaman.RotationPredicates or {}
Shaman.RotationSpecs = Shaman.RotationSpecs or {}
Shaman.BuffBeliefs = Shaman.BuffBeliefs or {}
Shaman.FlameShockBelief = Shaman.FlameShockBelief or nil
Shaman.StormstrikeBelief = Shaman.StormstrikeBelief or nil

local LOCALE = GetLocale and GetLocale() or "enUS"
local PTBR = (LOCALE == "ptBR")
local function LBL(pt, en) return PTBR and pt or en end

-- ---------------------------------------------------------------------------
-- Shaman spell rank families (Vanilla / WoW Forever ranks).
-- Registered globally in Core so SpellKnown, HighestKnownSpellID, ResolveKnownID,
-- IsSpellOnCD and RunDeclaredRotation recognize every rank automatically.
-- ---------------------------------------------------------------------------
local SHAMAN_FAMILIES = {
    { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208, 25448, 25449, 49237, 49238 }, -- Lightning Bolt
    { 421, 930, 2860, 10605, 25439, 25442, 49270, 49271 },                                     -- Chain Lightning
    { 8050, 8052, 8053, 10447, 10448, 29228, 25457, 49232, 49233 },                            -- Flame Shock
    { 8042, 8044, 8045, 8046, 10412, 10413, 10414, 25454, 49230, 49231 },                      -- Earth Shock
    { 8056, 8058, 10472, 10473, 25464, 49235, 49236 },                                         -- Frost Shock
    { 1535, 8498, 8499, 11314, 11315, 25546, 25547, 61649, 61657 },                            -- Fire Nova
    { 3599, 6363, 6364, 6365, 10437, 10438, 25533, 58699, 58703, 58704 },                      -- Searing Totem
    { 8190, 10585, 10586, 10587, 25552, 58731, 58734 },                                        -- Magma Totem
    { 324, 325, 905, 945, 8134, 10431, 10432, 25469, 25472, 49280, 49281 },                    -- Lightning Shield
    { 52127, 24398, 33736, 52129, 52131, 52134, 52136, 52138, 57960 },                         -- Water Shield
    { 8024, 8027, 8030, 16339, 16341, 16342, 25489, 58785, 58789, 58790 },                     -- Flametongue Weapon
    { 8232, 8235, 10486, 16362, 25505, 58801, 58803, 58804 },                                  -- Windfury Weapon
    { 8017, 8018, 8019, 10399, 16314, 16315, 16316, 25485 },                                   -- Rockbiter Weapon
    { 8075, 8160, 8161, 10442, 25361, 25528, 57622, 58643 },                                   -- Strength of Earth Totem
    { 5675, 10495, 10496, 10497, 25570, 58771, 58773, 58774 },                                 -- Mana Spring Totem
    { 8512, 10613, 10614, 25585, 25587 },                                                      -- Windfury Totem
    { 8835, 10627, 25359 },                                                                    -- Grace of Air Totem
    { 370, 8012 },                                                                             -- Purge
    { 17364 },                                                                                 -- Stormstrike
    { 16166 },                                                                                 -- Lightning Mastery / Elemental Mastery
    { 425336 },                                                                                -- Rage of the Farseer
    { 30823 },                                                                                 -- Shamanistic Rage (if present)
}

if addon.Compat and type(addon.Compat.RegisterSpellFamilies) == "function" then
    addon.Compat.RegisterSpellFamilies(SHAMAN_FAMILIES)
end

-- Maelstrom Weapon aura IDs (Forever / SoD / WotLK variants) + localized name fallback
local MAELSTROM_AURA_IDS = {
    [408498] = true,
    [408505] = true,
    [53817]  = true,
    [51532]  = true,
}

-- Clearcasting (Elemental Focus) aura IDs
local CLEARCASTING_AURA_IDS = {
    [16246] = true,
}

-- Weapon enchant IDs from GetWeaponEnchantInfo() (verified with LibraryBuffs.lua)
local WEAPON_ENCHANT_IDS = {
    flametongue = { [3] = true, [4] = true, [5] = true, [523] = true, [1665] = true, [1666] = true, [2634] = true, [3779] = true, [3780] = true, [3781] = true },
    windfury    = { [283] = true, [284] = true, [525] = true, [1669] = true, [2636] = true, [3785] = true, [3786] = true, [3787] = true },
    rockbiter   = { [1] = true, [6] = true, [29] = true, [503] = true, [683] = true, [1663] = true, [1664] = true, [2632] = true },
}

local function now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, t = pcall(GetTime)
    return ok and addon.SafeNumber(t, 0) or 0
end

local function normalizeName(name)
    local s = addon.SafeString and addon.SafeString(name, nil)
        or (type(name) == "string" and not (addon.IsSecretValue and addon.IsSecretValue(name)) and name or nil)
    if not s then return nil end
    return (s:lower():gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Shaman.SameFamily(spellID, baseID)
    if type(spellID) ~= "number" or type(baseID) ~= "number" then return false end
    if spellID == baseID then return true end
    local fam = addon.Compat and addon.Compat.FamilyOf
    return fam ~= nil and fam[spellID] ~= nil and fam[spellID] == fam[baseID]
end

function Shaman.ResolveID(spellID)
    if type(spellID) ~= "number" then return nil end
    return (addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(spellID)) or nil
end

function Shaman.SpellName(spellID)
    local id = Shaman.ResolveID(spellID) or spellID
    return addon.SpellName and addon.SpellName(id) or (addon.Compat and addon.Compat.SpellName and addon.Compat.SpellName(id))
end

-- ---------------------------------------------------------------------------
-- Weapon Enchant detection (GetWeaponEnchantInfo — weapon imbues are NOT auras!)
-- ---------------------------------------------------------------------------
function Shaman.GetMainHandEnchantInfo()
    if type(GetWeaponEnchantInfo) ~= "function" then
        return false, 0, nil, false
    end
    local ok, hasMH, mhExp, _, mhID = pcall(GetWeaponEnchantInfo)
    if not ok then return false, 0, nil, false end
    local has = addon.SafeBoolean and addon.SafeBoolean(hasMH, nil)
    if has == nil then return false, 0, nil, false end
    local remSec = (addon.SafeNumber(mhExp, 0) or 0) / 1000
    local enchID = addon.SafeNumber(mhID, nil)
    return has == true, remSec, enchID, true
end

function Shaman.HasWeaponEnchant(kind)
    local hasMH, remSec, enchID, readable = Shaman.GetMainHandEnchantInfo()
    if readable then
        -- Refresh when missing or < 30s remaining out of combat
        if not hasMH or remSec <= 30 then
            local belief = Shaman.BuffBeliefs[kind]
            if type(belief) == "table" and (now() - (belief.appliedAt or 0)) < 2.5 then
                return true
            end
            return false
        end
        if enchID and WEAPON_ENCHANT_IDS[kind] then
            if WEAPON_ENCHANT_IDS[kind][enchID] then return true end
            -- Another imbue is active on MH; allow recommending the desired one if enchant IDs don't match
            -- unless the client uses a custom Forever enchant ID (not in any known table -> trust hasMH).
            local knownOther = false
            for otherKind, ids in pairs(WEAPON_ENCHANT_IDS) do
                if otherKind ~= kind and ids[enchID] then knownOther = true break end
            end
            return not knownOther
        end
        return true
    end
    -- Fallback to belief if GetWeaponEnchantInfo is unavailable/secret
    local belief = Shaman.BuffBeliefs[kind]
    return type(belief) == "table" and (belief.expires == nil or now() < belief.expires)
end

-- ---------------------------------------------------------------------------
-- Totem detection (GetTotemInfo slots 1=Fire, 2=Earth, 3=Water, 4=Air)
-- ---------------------------------------------------------------------------
function Shaman.GetActiveTotems()
    local result = {}
    if type(GetTotemInfo) ~= "function" then return result end
    for slot = 1, 4 do
        local ok, haveTotem, totemName, startTime, duration = pcall(GetTotemInfo, slot)
        if ok and not (addon.IsSecretValue and addon.IsSecretValue(haveTotem))
            and (haveTotem == true or haveTotem == 1) then
            local clean = normalizeName(totemName)
            local st = addon.SafeNumber(startTime, nil)
            local dur = addon.SafeNumber(duration, nil)
            local rem = (st and dur and dur > 0) and math.max(0, st + dur - now()) or nil
            result[slot] = {
                active = true,
                name = addon.SafeString and addon.SafeString(totemName, "") or "",
                cleanName = clean or "",
                remaining = rem,
            }
        end
    end
    return result
end

function Shaman.IsTotemSlotActive(slot, minRemaining)
    local totems = Shaman.GetActiveTotems()
    local info = totems[slot]
    if not info or not info.active then return false end
    if minRemaining and info.remaining ~= nil and info.remaining < minRemaining then
        return false
    end
    return true
end

function Shaman.IsTotemSpellActive(spellID, expectedSlot)
    local totems = Shaman.GetActiveTotems()
    local names = {}
    local fam = (addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[spellID]) or { spellID }
    for _, id in ipairs(fam) do
        local n = normalizeName(Shaman.SpellName(id))
        if n and n ~= "" then names[n] = true end
    end
    local function matchesSlot(slot)
        local info = totems[slot]
        if not info or not info.active then return false end
        if info.remaining ~= nil and info.remaining <= 1.5 then return false end
        if info.cleanName == "" then return true end
        for wanted in pairs(names) do
            if info.cleanName == wanted or info.cleanName:find(wanted, 1, true) then
                return true
            end
        end
        return false
    end
    if expectedSlot then
        if matchesSlot(expectedSlot) then return true end
    end
    for slot = 1, 4 do
        if matchesSlot(slot) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Buff / Debuff / Proc helpers (secret-safe + beliefs)
-- ---------------------------------------------------------------------------
function Shaman.IsBuffActive(spellID, beliefKey, auraFamily)
    local status
    if auraFamily and addon.BuffLib and addon.BuffLib.Status then
        local ok, res = pcall(addon.BuffLib.Status, addon.BuffLib, "player", auraFamily)
        if ok and type(res) == "table" then
            status = res
            if status.present then return true end
        end
    end
    local name = Shaman.SpellName(spellID)
    if name and addon.Compat and addon.Compat.CheckBuff and addon.Compat.CheckBuff(name, "player", false) then
        return true
    end
    if addon.HasBuff and addon.HasBuff("player", spellID) then
        return true
    end
    local belief = beliefKey and Shaman.BuffBeliefs[beliefKey] or nil
    if status and status.readable then
        if type(belief) == "table" and (now() - (belief.appliedAt or 0)) < 2.0 then
            return true
        end
        if beliefKey then Shaman.BuffBeliefs[beliefKey] = nil end
        return false
    end
    if type(belief) == "table" then
        return belief.expires == nil or now() < belief.expires
    end
    return false
end

function Shaman.HasAnyShieldActive()
    return Shaman.IsBuffActive(324, "lightning_shield", "LightningShield")
        or Shaman.IsBuffActive(52127, "water_shield", nil)
end

function Shaman.IsClearcastingActive()
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(aura) ~= "table" then break end
            local okID, sid = pcall(function() return aura.spellId or aura.spellID end)
            sid = okID and addon.SafeNumber(sid, nil) or nil
            if sid and CLEARCASTING_AURA_IDS[sid] then return true end
        end
    end
    local name = Shaman.SpellName(16246)
    return (name ~= nil and addon.HasBuff and addon.HasBuff("player", name)) or false
end

function Shaman.GetMaelstromStacks()
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(aura) ~= "table" then break end
            local okID, sid = pcall(function() return aura.spellId or aura.spellID end)
            sid = okID and addon.SafeNumber(sid, nil) or nil
            local okN, nm = pcall(function() return aura.name end)
            local clean = okN and normalizeName(nm) or nil
            local isMaelstrom = (sid and MAELSTROM_AURA_IDS[sid])
                or (clean and (clean:find("maelstrom", 1, true) ~= nil or clean:find("voragem", 1, true) ~= nil))
            if isMaelstrom then
                local okSt, st = pcall(function() return aura.applications end)
                local count = okSt and addon.SafeNumber(st, nil) or nil
                return count or 1
            end
        end
    end
    return 0
end

local function currentTargetGUID()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "target")
    return ok and (addon.SafeString and addon.SafeString(guid, nil)) or nil
end

function Shaman.IsFlameShockActive()
    local name = Shaman.SpellName(8050)
    if name and addon.Compat and addon.Compat.CheckDebuff and addon.Compat.CheckDebuff(name, "target", true) then
        return true
    end
    local guid = currentTargetGUID()
    local b = Shaman.FlameShockBelief
    return type(b) == "table" and guid ~= nil and b.guid == guid and now() < (b.expires or 0)
end

function Shaman.IsStormstrikeDebuffActive()
    local name = Shaman.SpellName(17364)
    if name and addon.Compat and addon.Compat.CheckDebuff and addon.Compat.CheckDebuff(name, "target", false) then
        return true
    end
    local guid = currentTargetGUID()
    local b = Shaman.StormstrikeBelief
    return type(b) == "table" and guid ~= nil and b.guid == guid and now() < (b.expires or 0)
end

function Shaman.IsTargetSlowed()
    local frostName = Shaman.SpellName(8056)
    if frostName and addon.HasDebuff and addon.HasDebuff("target", frostName) then return true end
    return false
end

function Shaman.RecordCast(spellID)
    spellID = addon.SafeNumber(spellID, nil)
    if not spellID then return end
    local t = now()
    local buffs = {
        { 324,    "lightning_shield",   nil },
        { 52127,  "water_shield",       nil },
        { 8024,   "flametongue",        300 },
        { 8232,   "windfury",           300 },
        { 8017,   "rockbiter",          300 },
        { 16166,  "lightning_mastery",  15  },
        { 425336, "rage_of_farseer",    25  },
        { 30823,  "shamanistic_rage",   15  },
    }
    for _, info in ipairs(buffs) do
        if Shaman.SameFamily(spellID, info[1]) then
            Shaman.BuffBeliefs[info[2]] = {
                expires = info[3] and (t + info[3]) or nil,
                appliedAt = t,
            }
        end
    end
    local guid = currentTargetGUID()
    if guid then
        if Shaman.SameFamily(spellID, 8050) then
            Shaman.FlameShockBelief = { guid = guid, expires = t + 12 }
        elseif spellID == 17364 then
            Shaman.StormstrikeBelief = { guid = guid, expires = t + 12 }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Shaman-specific rotation predicates (registered on Shaman.RotationPredicates)
-- ---------------------------------------------------------------------------
local P = Shaman.RotationPredicates

P["shaman_has_enemy"] = {
    label = LBL("Alvo inimigo atacável", "Attackable enemy target"),
    fn = function(env) return env.hasActiveEnemy == true end,
}

P["shaman_interrupt"] = {
    label = LBL("Alvo conjurando (interromper)", "Enemy casting (interrupt)"),
    fn = function(env) return env.hasActiveEnemy and env.targetInterruptible == true end,
}

P["shaman_lightning_mastery"] = {
    label = LBL("Maestria em Raios em combate", "Lightning Mastery in combat"),
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy
            and not Shaman.IsBuffActive(16166, "lightning_mastery")
    end,
}

P["shaman_rage_of_farseer"] = {
    label = LBL("Fúria do Clarividente (combate melee)", "Rage of the Farseer (melee combat)"),
    fn = function(env)
        return env.inCombat and env.hasActiveEnemy and env.isMelee
            and not Shaman.IsBuffActive(425336, "rage_of_farseer")
    end,
}

P["shaman_shamanistic_rage"] = {
    label = LBL("Fúria Xamânica (mana <= 50% em combate)", "Shamanistic Rage (mana <= 50% in combat)"),
    fn = function(env)
        local lowMana = addon.HasResourcePctAtMost(addon.PowerType.MANA, 50, "player")
        return env.inCombat and env.hasActiveEnemy and lowMana
            and not Shaman.IsBuffActive(30823, "shamanistic_rage")
    end,
}

P["shaman_stormstrike"] = {
    label = LBL("Ataque da Tempestade (melee)", "Stormstrike (melee)"),
    fn = function(env) return env.hasActiveEnemy and env.isMelee == true end,
}

P["shaman_maelstrom_st"] = {
    label = LBL("Arma da Voragem (5 cargas, alvo único)", "Maelstrom Weapon (5 stacks, single target)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isAoE and (env.maelstromStacks or 0) >= 5
    end,
}

P["shaman_maelstrom_aoe"] = {
    label = LBL("Arma da Voragem (5 cargas, área 2+)", "Maelstrom Weapon (5 stacks, AoE 2+)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and (env.maelstromStacks or 0) >= 5
    end,
}

P["shaman_flame_shock"] = {
    label = LBL("Choque Flamejante ausente (mana > 15%)", "Flame Shock missing (mana > 15%)"),
    fn = function(env)
        return env.hasActiveEnemy and (addon.HasManaPct(15)) and not env.flameShockActive
    end,
}

P["shaman_earth_shock_enh"] = {
    label = LBL("Choque Terreno (combate melee, Flame Shock ativo)", "Earth Shock (melee, Flame Shock active)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isMelee and (addon.HasManaPct(20))
            and (env.flameShockActive or env.stormstrikeActive)
    end,
}

P["shaman_earth_shock_moving"] = {
    label = LBL("Choque Terreno em movimento", "Earth Shock while moving"),
    fn = function(env)
        return env.hasActiveEnemy and env.isMoving and (addon.HasManaPct(20))
            and not env.targetInterruptible
    end,
}

P["shaman_frost_shock_pvp"] = {
    label = LBL("Choque Gélido (PvP, alvo sem lentidão)", "Frost Shock (PvP, target not slowed)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isPvP and (addon.HasManaPct(20))
            and not env.targetSlowed
    end,
}

P["shaman_magma_totem"] = {
    label = LBL("Totem de Magma (Área 2+, sem totem de fogo)", "Magma Totem (AoE 2+, no fire totem)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and (addon.HasManaPct(15))
            and not env.magmaTotemActive
    end,
}

P["shaman_searing_totem"] = {
    label = LBL("Totem Calcinante (alvo único, sem totem de fogo)", "Searing Totem (single target, no fire totem)"),
    fn = function(env)
        return env.hasActiveEnemy and not env.isAoE and (addon.HasManaPct(15))
            and not env.fireTotemActive
    end,
}

P["shaman_fire_nova"] = {
    label = LBL("Nova de Fogo (Área 2+ com totem de fogo ativo)", "Fire Nova (AoE 2+ with active fire totem)"),
    fn = function(env)
        return env.hasActiveEnemy and env.isAoE and (addon.HasManaPct(15))
            and env.fireTotemActive == true
    end,
}

P["shaman_chain_lightning_ele"] = {
    label = LBL("Cadeia de Raios (AoE, Clearcasting, Maestria ou mana >= 50%)", "Chain Lightning (AoE, Clearcasting, Mastery, or mana >= 50%)"),
    fn = function(env)
        if not env.hasActiveEnemy then return false end
        if env.isAoE and (addon.HasManaPct(15)) then return true end
        return env.clearcastingActive or env.lightningMasteryActive or (addon.HasManaPct(50))
    end,
}

P["shaman_not_melee"] = {
    label = LBL("Alvo fora do melee (filler à distância)", "Target outside melee (ranged filler)"),
    fn = function(env) return env.hasActiveEnemy and env.isMelee == false end,
}
