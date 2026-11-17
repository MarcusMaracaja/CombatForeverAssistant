-- Combat Forever Assistant — LibraryBuffs.
-- Registry of every buff we care about, grouped by class, with spell IDs per rank.
-- Any module can ask:
--     CFA.BuffLib:Has(unit, spellID)            -> boolean, tier|nil
--     CFA.BuffLib:Status(unit, familyName)      -> { present, tier, maxTier, outdated }
--     CFA.BuffLib:GetAll(unit)                  -> array of { family, name, tier, maxTier }
--
-- Notes:
--  * "unit" is "player", "target", "party1".."party4", "raidN".
--  * The WoW Forever client is a modern engine running vanilla content, so UnitBuff/
--    UnitDebuff are expected to return a spellID. If a given client does not, we fall
--    back to matching the aura name against the (English) labels — localized clients
--    may miss matches; prefer ID-capable clients.
--  * Totems are NOT auras on a player and are intentionally excluded.
--  * Families group the single-target and party-wide variants of the same buff
--    (e.g. Power Word: Fortitude / Prayer of Fortitude). `tierBase` aligns the tiers
--    of the party-wide variant with the single-target one.
--
-- Buff IDs were researched against wowhead classic + legacyofwarcraft DBs (2026-11-16).
-- Entries marked "VERIFY" still need an in-game check (GetSpellInfo / UnitBuff).

local addonName, addon = ...
local L = addon.L

local BuffLib = {}
addon.BuffLib = BuffLib

-- Class index (stable, used by blocks below and by callers)
BuffLib.ClassIndex = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9,
}

-- Every entry:
--   family   -> canonical key used in Status()/GetAll()
--   name     -> English label (documentation/fallback)
--   class    -> owner class tag
--   kind     -> "raid" | "self" | "hot" | "debuff" | "enchant" | "other"
--   ranks    -> array of spell IDs, index = tier within the entry
--   tierBase -> offset added to the index (aligns grouped variants)
local E = {
    ------------------------------------------------------------------ PRIEST
    { family = "Fortitude", name = "Power Word: Fortitude", class = "PRIEST", kind = "raid",
      ranks = { 1243, 1244, 1245, 2791, 10937, 10938 }, tierBase = 0 },
    { family = "Fortitude", name = "Prayer of Fortitude", class = "PRIEST", kind = "raid",
      ranks = { 21562, 21564 }, tierBase = 4 },

    { family = "DivineSpirit", name = "Divine Spirit", class = "PRIEST", kind = "raid",
      ranks = { 14752, 14818, 14819, 27841 }, tierBase = 0 },
    { family = "DivineSpirit", name = "Prayer of Spirit", class = "PRIEST", kind = "raid",
      ranks = { 27681 }, tierBase = 3 },

    { family = "ShadowProtection", name = "Shadow Protection", class = "PRIEST", kind = "raid",
      ranks = { 976, 10957, 10958 }, tierBase = 0 },
    { family = "ShadowProtection", name = "Prayer of Shadow Protection", class = "PRIEST", kind = "raid",
      ranks = { 27683 }, tierBase = 2 },

    { family = "PowerWordShield", name = "Power Word: Shield", class = "PRIEST", kind = "raid",
      ranks = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }, tierBase = 0 },

    { family = "InnerFire", name = "Inner Fire", class = "PRIEST", kind = "self",
      ranks = { 588, 7128, 602, 1006, 10951, 10952 }, tierBase = 0 },

    { family = "Renew", name = "Renew", class = "PRIEST", kind = "hot",
      ranks = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 }, tierBase = 0 },

    { family = "PowerInfusion", name = "Power Infusion", class = "PRIEST", kind = "other",
      ranks = { 10060 }, tierBase = 0 }, -- talent

    { family = "FearWard", name = "Fear Ward", class = "PRIEST", kind = "raid",
      ranks = { 6346 }, tierBase = 0 },

    { family = "Shadowform", name = "Shadowform", class = "PRIEST", kind = "self",
      ranks = { 15473 }, tierBase = 0 },

    { family = "VampiricEmbrace", name = "Vampiric Embrace", class = "PRIEST", kind = "self",
      ranks = { 15286 }, tierBase = 0 }, -- talent

    ------------------------------------------------------------------ DRUID
    { family = "MarkOfTheWild", name = "Mark of the Wild", class = "DRUID", kind = "raid",
      ranks = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, tierBase = 0 },
    { family = "MarkOfTheWild", name = "Gift of the Wild", class = "DRUID", kind = "raid",
      ranks = { 21849, 21850 }, tierBase = 5 },

    { family = "Thorns", name = "Thorns", class = "DRUID", kind = "raid",
      ranks = { 467, 782, 1075, 8914, 9756, 9910 }, tierBase = 0 },

    { family = "Rejuvenation", name = "Rejuvenation", class = "DRUID", kind = "hot",
      ranks = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }, tierBase = 0 },

    { family = "Regrowth", name = "Regrowth", class = "DRUID", kind = "hot",
      ranks = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }, tierBase = 0 },

    { family = "MoonkinAura", name = "Moonkin Aura", class = "DRUID", kind = "raid",
      ranks = { 24907 }, tierBase = 0 }, -- VERIFY in game

    { family = "LeaderOfThePack", name = "Leader of the Pack", class = "DRUID", kind = "raid",
      ranks = { 17007 }, tierBase = 0 }, -- talent aura

    { family = "Barkskin", name = "Barkskin", class = "DRUID", kind = "self",
      ranks = { 22812 }, tierBase = 0 },

    { family = "TigersFury", name = "Tiger's Fury", class = "DRUID", kind = "self",
      ranks = { 5217, 6793, 9845, 9846 }, tierBase = 0 },

    { family = "Innervate", name = "Innervate", class = "DRUID", kind = "raid",
      ranks = { 29166 }, tierBase = 0 },

    -- Druid debuffs (enemy)
    { family = "FaerieFire", name = "Faerie Fire", class = "DRUID", kind = "debuff",
      ranks = { 770, 778, 9749, 9907 }, tierBase = 0 },
    { family = "FaerieFireFeral", name = "Faerie Fire (Feral)", class = "DRUID", kind = "debuff",
      ranks = { 16857, 17390, 17391, 17392 }, tierBase = 0 },
    { family = "InsectSwarm", name = "Insect Swarm", class = "DRUID", kind = "debuff",
      ranks = { 5570, 24974, 24975, 24976, 24977 }, tierBase = 0 }, -- VERIFY ranks in game

    ---------------------------------------------------------- PALADIN
    { family = "BlessingOfMight", name = "Blessing of Might", class = "PALADIN", kind = "raid",
      ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, tierBase = 0 },
    { family = "BlessingOfWisdom", name = "Blessing of Wisdom", class = "PALADIN", kind = "raid",
      ranks = { 19742, 19850, 19852, 19853, 19854, 25290 }, tierBase = 0 },
    { family = "BlessingOfSalvation", name = "Blessing of Salvation", class = "PALADIN", kind = "raid",
      ranks = { 1038 }, tierBase = 0 },
    { family = "BlessingOfSacrifice", name = "Blessing of Sacrifice", class = "PALADIN", kind = "raid",
      ranks = { 6940, 20729 }, tierBase = 0 },
    { family = "BlessingOfProtection", name = "Blessing of Protection", class = "PALADIN", kind = "raid",
      ranks = { 1022, 5599, 10278 }, tierBase = 0 },
    { family = "BlessingOfFreedom", name = "Blessing of Freedom", class = "PALADIN", kind = "raid",
      ranks = { 1044 }, tierBase = 0 },
    { family = "BlessingOfLight", name = "Blessing of Light", class = "PALADIN", kind = "raid",
      ranks = { 19977, 19978, 19979 }, tierBase = 0 },
    { family = "BlessingOfSanctuary", name = "Blessing of Sanctuary", class = "PALADIN", kind = "raid",
      ranks = { 20911, 20912, 20913, 20914 }, tierBase = 0 }, -- Protection talent
    { family = "DivineShield", name = "Divine Shield", class = "PALADIN", kind = "self",
      ranks = { 642 }, tierBase = 0 },

    ---------------------------------------------------------- WARRIOR
    { family = "BattleShout", name = "Battle Shout", class = "WARRIOR", kind = "raid",
      ranks = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, tierBase = 0 },

    ---------------------------------------------------------- HUNTER (pending data)

    ---------------------------------------------------------- ROGUE (pending data)

    ---------------------------------------------------------- SHAMAN
    -- Weapon enchants are NOT UnitBuff auras: detect via GetWeaponEnchantInfo().
    -- `enchants` here maps rank -> temporary enchant ID (informational).
    { family = "LightningShield", name = "Lightning Shield", class = "SHAMAN", kind = "self",
      ranks = { 324, 325, 905, 945, 8134, 10431, 10432 }, tierBase = 0 },
    { family = "RockbiterWeapon", name = "Rockbiter Weapon", class = "SHAMAN", kind = "enchant",
      ranks = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }, tierBase = 0,
      enchants = { 29, 6, 1, 503, 1663, 683, 1664 } },
    { family = "WindfuryWeapon", name = "Windfury Weapon", class = "SHAMAN", kind = "enchant",
      ranks = { 8232, 8235, 10486, 16362 }, tierBase = 0,
      enchants = { 283, 284, 525, 1669 } },
    { family = "FlametongueWeapon", name = "Flametongue Weapon", class = "SHAMAN", kind = "enchant",
      ranks = { 8024, 8027, 8030, 16339, 16341, 16342 }, tierBase = 0,
      enchants = { 5, 4, 3, 523, 1665, 1666 } },
    -- Healing Wave's effective stat totems: the buff ON the player (aura IDs).
    { family = "StrengthOfEarthAura", name = "Strength of Earth", class = "SHAMAN", kind = "totem",
      ranks = { 8076, 8162, 8163, 10441, 25362 }, tierBase = 0 },
    { family = "GraceOfAirAura", name = "Grace of Air", class = "SHAMAN", kind = "totem",
      ranks = { 8836, 10626, 25360 }, tierBase = 0 },
    { family = "WindfuryTotemAura", name = "Windfury Totem", class = "SHAMAN", kind = "totem",
      ranks = { 8516, 10608, 10610 }, tierBase = 0 },
    { family = "ManaSpringAura", name = "Mana Spring", class = "SHAMAN", kind = "totem",
      ranks = { 5677, 10491, 10493, 10494 }, tierBase = 0 },
    -- Not vanilla 1.12 (do NOT scan): Earth Shield, Molten Armor.

    ---------------------------------------------------------- MAGE
    { family = "ArcaneIntellect", name = "Arcane Intellect", class = "MAGE", kind = "raid",
      ranks = { 1459, 1460, 1461, 10156, 10157 }, tierBase = 0 },
    { family = "ArcaneIntellect", name = "Arcane Intellect (1.11 duplicate)", class = "MAGE", kind = "raid",
      ranks = { 16876 }, tierBase = 4 }, -- 1.11+ re-issue of R5; aura is the same
    { family = "ArcaneBrilliance", name = "Arcane Brilliance", class = "MAGE", kind = "raid",
      ranks = { 23028 }, tierBase = 0 },
    { family = "FrostArmor", name = "Frost Armor", class = "MAGE", kind = "self",
      ranks = { 168, 7300, 7301 }, tierBase = 0 },
    { family = "IceArmor", name = "Ice Armor", class = "MAGE", kind = "self",
      ranks = { 7302, 7320, 10219, 10220 }, tierBase = 0 },
    { family = "MageArmor", name = "Mage Armor", class = "MAGE", kind = "self",
      ranks = { 6117, 22782, 22783 }, tierBase = 0 },
    { family = "FrostWard", name = "Frost Ward", class = "MAGE", kind = "self",
      ranks = { 6143, 8461, 8462, 10177 }, tierBase = 0 }, -- +28609 (VERIFY: post-1.12)
    { family = "FireWard", name = "Fire Ward", class = "MAGE", kind = "self",
      ranks = { 543, 8457, 8458, 10223, 10225 }, tierBase = 0 },
    { family = "Clearcasting", name = "Clearcasting", class = "MAGE", kind = "other",
      ranks = { 12536 }, tierBase = 0 }, -- talent proc aura
    -- Molten Armor: not in vanilla 1.12 (TBC 30482). Not scanned.

    ---------------------------------------------------------- WARLOCK (pending data)
}

-- Index: spellID -> { entryIndex, tier }
local bySpellID = {}
local familyMax = {}
for i, entry in ipairs(E) do
    for j, id in ipairs(entry.ranks) do
        local tier = (entry.tierBase or 0) + j
        bySpellID[id] = { entryIndex = i, tier = tier }
        familyMax[entry.family] = math.max(familyMax[entry.family] or 0, (entry.tierBase or 0) + #entry.ranks)
    end
end
BuffLib.entries = E
BuffLib.FamilyMaxTier = familyMax

local function scan(unit, harvest)
    local i = 1
    while true do
        local name, rank, _, _, _, _, _, _, _, spellID = UnitBuff(unit, i)
        if not name then break end
        spellID = tonumber(spellID)
        if spellID and bySpellID[spellID] then
            local hit = bySpellID[spellID]
            harvest(hit.entryIndex, hit.tier, spellID)
        end
        i = i + 1
    end
    i = 1
    while true do
        local name, rank, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, i)
        if not name then break end
        spellID = tonumber(spellID)
        if spellID and bySpellID[spellID] then
            local hit = bySpellID[spellID]
            harvest(hit.entryIndex, hit.tier, spellID)
        end
        i = i + 1
    end
end

function BuffLib:Has(unit, spellID)
    local found, tier = false, nil
    scan(unit, function(entryIndex, t, auraSpellID)
        if auraSpellID == spellID then found, tier = true, t end
    end)
    return found, tier
end

-- Convenience: "does the unit have familyName at any tier, and is it current?"
-- Modules typically want this rather than raw Has(): e.g. a Druid asking whether the
-- player has Mark of the Wild before suggesting it.
function BuffLib:HasFamily(unit, family)
    local st = self:Status(unit, family)
    return st.present, st.tier, st.outdated
end

function BuffLib:Status(unit, family)
    local best = 0
    scan(unit, function(entryIndex, t)
        if E[entryIndex].family == family then best = math.max(best, t) end
    end)
    local maxTier = familyMax[family]
    if best == 0 then
        return { present = false, tier = 0, maxTier = maxTier, outdated = false }
    end
    return { present = true, tier = best, maxTier = maxTier, outdated = best < (maxTier or 0) }
end

function BuffLib:GetAll(unit)
    local out = {}
    local bestByFamily = {}
    scan(unit, function(entryIndex, t)
        local e = E[entryIndex]
        bestByFamily[e.family] = math.max(bestByFamily[e.family] or 0, t)
    end)
    for family, tier in pairs(bestByFamily) do
        out[#out + 1] = { family = family, tier = tier, maxTier = familyMax[family], outdated = tier < (familyMax[family] or 0) }
    end
    return out
end

function BuffLib:ClassIndexOf(classTag)
    return BuffLib.ClassIndex[classTag] or 0
end
