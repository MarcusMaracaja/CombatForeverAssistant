-- Combat Forever Assistant — LibraryBuffs.
-- Registry of buffs/debuffs per class, with spell IDs per rank.
-- Any module can ask:
--     CFA.BuffLib:Has(unit, spellID)            -> boolean, tier|nil   (exact rank present?)
--     CFA.BuffLib:HasFamily(unit, familyName)   -> boolean, tier, outdated
--     CFA.BuffLib:Status(unit, familyName)      -> { present, tier, maxTier, outdated }
--     CFA.BuffLib:GetAll(unit)                  -> array of { family, tier, maxTier, outdated }
--     CFA.BuffLib:ClassIndexOf(classTag)        -> stable numeric index
--
-- ⚠️ Critical vanilla fact: `UnitBuff`/`UnitDebuff` do NOT exist on WoW Forever.
-- Auras are read via `C_UnitAuras.GetAuraDataByIndex` and the numeric ID reported
-- is the **aura** spell ID (dbc cat 0), NOT necessarily the cast ID. Entries may
-- carry two lists:
--   auras = { ... }   -> scanned first when present (verified on wowhead classic tooltips)
--   ranks = { ... }   -> cast spell IDs; used as fallback scan list when auras are absent
-- Localized clients still return the same numeric IDs; name matching is never required.
-- In combat the aura payload may be *secret*; unreadable entries are skipped
-- (fail-safe: "not present") rather than crash.
--
-- Totems are NOT auras on the totem's owner. The buff the player RECEIVES from a totem
-- uses its own aura IDs (e.g. Strength of Earth aura 8076), and those are what we scan.
-- Weapon enchants are NOT auras: detect via GetWeaponEnchantInfo() (see `enchants`).
--
-- Families group single-target and party-wide variants of the same buff; `tierBase`
-- aligns their power tiers.
--
-- Sources (2026-11-16): wowhead classic (tooltip API + embedded JSON rank lists),
-- classicdb.ch, warcraft.wiki.gg; Priest/Druid additionally cross-checked on
-- legacyofwarcraft.com. Entries marked "VERIFY" still need an in-game check.

local addonName, addon = ...
local BuffLib = {}
addon.BuffLib = BuffLib

BuffLib.ClassIndex = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9,
}

local E = {
    ------------------------------------------------------------------ PRIEST
    { family = "Fortitude", name = "Power Word: Fortitude", class = "PRIEST", kind = "raid",
      ranks = { 1243, 1244, 1245, 2791, 10937, 10938 }, tierBase = 0 }, -- aura IDs VERIFY
    { family = "Fortitude", name = "Prayer of Fortitude", class = "PRIEST", kind = "raid",
      ranks = { 21562, 21564 }, tierBase = 4 }, -- aura IDs VERIFY

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
      ranks = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, tierBase = 0 }, -- aura IDs VERIFY
    { family = "MarkOfTheWild", name = "Gift of the Wild", class = "DRUID", kind = "raid",
      ranks = { 21849, 21850 }, tierBase = 5 },

    { family = "Thorns", name = "Thorns", class = "DRUID", kind = "raid",
      ranks = { 467, 782, 1075, 8914, 9756, 9910 }, tierBase = 0 },

    { family = "Rejuvenation", name = "Rejuvenation", class = "DRUID", kind = "hot",
      ranks = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }, tierBase = 0 },

    { family = "Regrowth", name = "Regrowth", class = "DRUID", kind = "hot",
      ranks = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }, tierBase = 0 },

    { family = "MoonkinAura", name = "Moonkin Aura", class = "DRUID", kind = "raid",
      ranks = { 24907 }, tierBase = 0 }, -- VERIFY in game (may be the shapeshift aura)

    { family = "LeaderOfThePack", name = "Leader of the Pack", class = "DRUID", kind = "raid",
      ranks = { 17007 }, tierBase = 0 }, -- talent aura

    { family = "Barkskin", name = "Barkskin", class = "DRUID", kind = "self",
      ranks = { 22812 }, tierBase = 0 },

    { family = "TigersFury", name = "Tiger's Fury", class = "DRUID", kind = "self",
      ranks = { 5217, 6793, 9845, 9846 }, tierBase = 0 },

    { family = "Innervate", name = "Innervate", class = "DRUID", kind = "raid",
      ranks = { 29166 }, tierBase = 0 },

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
      ranks = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, tierBase = 0 }, -- aura IDs VERIFY

    ---------------------------------------------------------- HUNTER
    { family = "AspectOfTheBeast", name = "Aspect of the Beast", class = "HUNTER", kind = "self",
      ranks = { 13161 }, auras = { 13162 }, tierBase = 0 },
    { family = "AspectOfTheCheetah", name = "Aspect of the Cheetah", class = "HUNTER", kind = "self",
      ranks = { 5118 }, auras = { 5131 }, tierBase = 0 },
    { family = "AspectOfTheMonkey", name = "Aspect of the Monkey", class = "HUNTER", kind = "self",
      ranks = { 13163 }, auras = { 13164 }, tierBase = 0 },
    { family = "AspectOfThePack", name = "Aspect of the Pack", class = "HUNTER", kind = "raid",
      ranks = { 13159 }, auras = { 13160 }, tierBase = 0 },
    { family = "AspectOfTheHawk", name = "Aspect of the Hawk", class = "HUNTER", kind = "self",
      ranks = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 },
      auras = { 6385, 14374, 14375, 14376, 14377, 14378, 25406 }, tierBase = 0 },
    { family = "AspectOfTheWild", name = "Aspect of the Wild", class = "HUNTER", kind = "raid",
      ranks = { 20043, 20190 }, auras = { 20044, 20191 }, tierBase = 0 },
    { family = "TrueshotAura", name = "Trueshot Aura", class = "HUNTER", kind = "raid",
      ranks = { 19506, 20905, 20906 }, auras = { 19506, 1563, 20938 }, tierBase = 0 }, -- R1 VERIFY
    { family = "ExposeWeakness", name = "Expose Weakness", class = "HUNTER", kind = "raid",
      auras = { 23577 }, tierBase = 0 }, -- talent aura
    { family = "BestialWrath", name = "Bestial Wrath", class = "HUNTER", kind = "other",
      ranks = { 19574 }, tierBase = 0 }, -- aura ID VERIFY (pet buff)
    -- Hunter target debuffs
    { family = "HuntersMark", name = "Hunter's Mark", class = "HUNTER", kind = "debuff",
      ranks = { 1130, 14323, 14324, 14325 }, auras = { 5298, 14431, 14432, 14434 }, tierBase = 0 },
    { family = "SerpentSting", name = "Serpent Sting", class = "HUNTER", kind = "debuff",
      ranks = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }, tierBase = 0 }, -- aura IDs VERIFY
    { family = "ScorpidSting", name = "Scorpid Sting", class = "HUNTER", kind = "debuff",
      ranks = { 3043, 14275, 14276, 14277 }, tierBase = 0 }, -- aura IDs VERIFY

    ---------------------------------------------------------- ROGUE
    { family = "SliceAndDice", name = "Slice and Dice", class = "ROGUE", kind = "self",
      ranks = { 5171, 6774 }, auras = { 5175, 6775 }, tierBase = 0 },
    { family = "Evasion", name = "Evasion", class = "ROGUE", kind = "self",
      ranks = { 5277 }, tierBase = 0 }, -- aura 4086 or 5278? VERIFY
    { family = "BladeFlurry", name = "Blade Flurry", class = "ROGUE", kind = "self",
      ranks = { 13877 }, tierBase = 0 }, -- aura 22482? VERIFY (talent)
    { family = "AdrenalineRush", name = "Adrenaline Rush", class = "ROGUE", kind = "self",
      ranks = { 13750 }, tierBase = 0 }, -- aura 28753? VERIFY (talent)
    { family = "ColdBlood", name = "Cold Blood", class = "ROGUE", kind = "self",
      ranks = { 14177 }, tierBase = 0 }, -- aura ID probably = cast ID? VERIFY (talent)
    -- Rogue target debuffs
    { family = "ExposeArmor", name = "Expose Armor", class = "ROGUE", kind = "debuff",
      ranks = { 8647, 8649, 8650, 11197, 11198 }, auras = { 8648, 8651, 8652, 11199, 11200 }, tierBase = 0 },
    { family = "Rupture", name = "Rupture", class = "ROGUE", kind = "debuff",
      ranks = { 1943, 8639, 8640, 11273, 11274, 11275 }, auras = { 6736, 8641, 8642, 11276, 11277, 11278 }, tierBase = 0 },
    { family = "Garrote", name = "Garrote", class = "ROGUE", kind = "debuff",
      ranks = { 703, 8631, 8632, 8633, 11289, 11290 }, auras = { 6737, 8634, 8635, 8636, 11291, 11292 }, tierBase = 0 },
    { family = "KidneyShot", name = "Kidney Shot", class = "ROGUE", kind = "debuff",
      ranks = { 408, 8643 }, auras = { 6735, 8644 }, tierBase = 0 },

    ---------------------------------------------------------- SHAMAN
    -- Weapon enchants are NOT UnitBuff auras: detect via GetWeaponEnchantInfo().
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
    -- The buff ON the player (aura IDs from the totem)
    { family = "StrengthOfEarthAura", name = "Strength of Earth", class = "SHAMAN", kind = "totem",
      auras = { 8076, 8162, 8163, 10441, 25362 }, tierBase = 0 },
    { family = "GraceOfAirAura", name = "Grace of Air", class = "SHAMAN", kind = "totem",
      auras = { 8836, 10626, 25360 }, tierBase = 0 },
    { family = "WindfuryTotemAura", name = "Windfury Totem", class = "SHAMAN", kind = "totem",
      auras = { 8516, 10608, 10610 }, tierBase = 0 },
    { family = "ManaSpringAura", name = "Mana Spring", class = "SHAMAN", kind = "totem",
      auras = { 5677, 10491, 10493, 10494 }, tierBase = 0 },
    -- Not vanilla 1.12 (do NOT scan): Earth Shield, Molten Armor.

    ---------------------------------------------------------- MAGE
    { family = "ArcaneIntellect", name = "Arcane Intellect", class = "MAGE", kind = "raid",
      ranks = { 1459, 1460, 1461, 10156, 10157 }, tierBase = 0 }, -- aura IDs VERIFY
    { family = "ArcaneIntellect", name = "Arcane Intellect (1.11 duplicate)", class = "MAGE", kind = "raid",
      ranks = { 16876 }, tierBase = 4 }, -- 1.11+ re-issue of R5; aura is the same
    { family = "ArcaneBrilliance", name = "Arcane Brilliance", class = "MAGE", kind = "raid",
      ranks = { 23028 }, tierBase = 0 }, -- aura IDs VERIFY
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

    ---------------------------------------------------------- WARLOCK
    { family = "DemonSkin", name = "Demon Skin", class = "WARLOCK", kind = "self",
      ranks = { 687, 696 }, tierBase = 0 }, -- aura 1383 (rank mapping VERIFY)
    { family = "DemonArmor", name = "Demon Armor", class = "WARLOCK", kind = "self",
      ranks = { 706, 1086, 11733, 11734, 11735 }, auras = { 1384, 1404, 11736, 11737, 11738 }, tierBase = 0 },
    { family = "BloodPact", name = "Blood Pact", class = "WARLOCK", kind = "raid",
      auras = { 7871, 7872, 7873, 11768, 11769 }, tierBase = 0 }, -- imp buff aura
    { family = "SoulLink", name = "Soul Link", class = "WARLOCK", kind = "self",
      ranks = { 19028 }, tierBase = 0 }, -- aura 25228? VERIFY (talent)
    { family = "AmplifyCurse", name = "Amplify Curse", class = "WARLOCK", kind = "other",
      ranks = { 18288 }, tierBase = 0 }, -- talent buff
    -- Warlock target debuffs
    { family = "Corruption", name = "Corruption", class = "WARLOCK", kind = "debuff",
      ranks = { 172, 6222, 6223, 7648, 11671, 11672, 25311 },
      auras = { 6221, 6224, 6225, 7649, 11673, 11674, 25419 }, tierBase = 0 },
    { family = "CurseOfAgony", name = "Curse of Agony", class = "WARLOCK", kind = "debuff",
      ranks = { 980, 1014, 6217, 11711, 11712, 11713 },
      auras = { 1296, 1297, 6218, 11714, 11715, 11716 }, tierBase = 0 },
    { family = "CurseOfDoom", name = "Curse of Doom", class = "WARLOCK", kind = "debuff",
      ranks = { 603 }, auras = { 18753 }, tierBase = 0 },
    { family = "CurseOfTheElements", name = "Curse of the Elements", class = "WARLOCK", kind = "debuff",
      ranks = { 1490, 11721, 11722 }, auras = { 7666, 11723, 11724 }, tierBase = 0 },
    { family = "CurseOfWeakness", name = "Curse of Weakness", class = "WARLOCK", kind = "debuff",
      ranks = { 702, 1108, 6205, 7646, 11707, 11708 }, auras = { 1393, 1394, 6206, 7647, 11709, 11710 }, tierBase = 0 },
    { family = "CurseOfRecklessness", name = "Curse of Recklessness", class = "WARLOCK", kind = "debuff",
      ranks = { 704, 7658, 7659, 11717 }, auras = { 7650, 7660, 7661, 11718 }, tierBase = 0 },
    { family = "CurseOfShadow", name = "Curse of Shadow", class = "WARLOCK", kind = "debuff",
      ranks = { 17862, 17937 }, auras = { 17865, 17938 }, tierBase = 0 },
    { family = "CurseOfTongues", name = "Curse of Tongues", class = "WARLOCK", kind = "debuff",
      ranks = { 1714, 11719 }, auras = { 5736, 11720 }, tierBase = 0 },
    { family = "Banish", name = "Banish", class = "WARLOCK", kind = "debuff",
      ranks = { 710, 18647 }, auras = { 7664, 18648 }, tierBase = 0 },
    -- Expose Armor ids noted for Rogue in Rogue block; keep entries class-scoped.
}

-- Index: aura spellID -> { entryIndex, tier } (both auras and ranks indexed; names indexed as fallback)
local bySpellID = {}
local byName = {}
local familyMax = {}
for i, entry in ipairs(E) do
    local tierCount = math.max(#(entry.ranks or {}), #(entry.auras or {}))
    for j, id in ipairs(entry.auras or {}) do
        bySpellID[id] = { entryIndex = i, tier = (entry.tierBase or 0) + j }
    end
    for j, id in ipairs(entry.ranks or {}) do
        if not bySpellID[id] then
            bySpellID[id] = { entryIndex = i, tier = (entry.tierBase or 0) + j }
        end
        local n = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        n = (type(n) == "table" and n.name) or n
        if not n and GetSpellInfo then n = GetSpellInfo(id) end
        if type(n) == "string" and n ~= "" then
            byName[n:lower():gsub("%s*%b()%s*$", "")] = { entryIndex = i, tier = (entry.tierBase or 0) + j }
        end
    end
    if entry.name then
        byName[entry.name:lower():gsub("%s*%b()%s*$", "")] = { entryIndex = i, tier = 1 }
    end
    if tierCount > 0 then
        familyMax[entry.family] = math.max(familyMax[entry.family] or 0, (entry.tierBase or 0) + tierCount)
    end
end
BuffLib.entries = E
BuffLib.FamilyMaxTier = familyMax

-- WoW Forever (modern engine): UnitBuff/UnitDebuff do NOT exist — auras come
-- from C_UnitAuras.GetAuraDataByIndex(unit, i, filter). In combat the aura
-- payload may be *secret*; we skip unreadable entries (fail-safe: "unknown").
-- Anything we cannot read simply leaves BuffLib answering "not present".
local AURA_FILTERS = { "HELPFUL", "HARMFUL" }

local function auraSpellID(aura)
    if type(aura) ~= "table" then return nil end
    local id = aura.spellId or aura.spellID or aura.auraSpellId or aura.auraSpellID
    if id == nil then return nil end
    if _G.issecretvalue and issecretvalue(id) then return nil end
    return tonumber(id)
end

-- pcall-wrapped aura walk; returns (list, readable)
local function auraWalk(unit, filter)
    local out = {}
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then
        return out, false
    end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok then return out, false end
        if aura == nil then return out, true end -- full sweep
        if type(aura) ~= "table" then return out, false end
        out[#out + 1] = aura
    end
    return out, true
end

local function scan(unit, harvest)
    local readable = true
    for _, filter in ipairs(AURA_FILTERS) do
        local list, ok = auraWalk(unit, filter)
        if not ok then readable = false end
        for _, aura in ipairs(list) do
            local spellID = auraSpellID(aura)
            if spellID and bySpellID[spellID] then
                local hit = bySpellID[spellID]
                harvest(hit.entryIndex, hit.tier, spellID)
            elseif type(aura.name) == "string" and not (_G.issecretvalue and issecretvalue(aura.name)) then
                local clean = aura.name:lower():gsub("%s*%b()%s*$", "")
                local hit = byName[clean]
                if hit then
                    harvest(hit.entryIndex, hit.tier, spellID or 0)
                end
            end
        end
    end
    return readable
end

function BuffLib:Has(unit, spellID)
    local found, tier = false, nil
    scan(unit, function(_, t, auraSpellID)
        if auraSpellID == spellID then found, tier = true, t end
    end)
    return found, tier
end

-- "does the unit have familyName at any tier, and is it current?"
function BuffLib:HasFamily(unit, family)
    local st = self:Status(unit, family)
    return st.present, st.tier, st.outdated, st.readable
end

function BuffLib:Status(unit, family)
    local best = 0
    local readable = scan(unit, function(entryIndex, t)
        if E[entryIndex].family == family then best = math.max(best, t) end
    end)
    local maxTier = familyMax[family]
    if best == 0 then
        return { present = false, tier = 0, maxTier = maxTier, outdated = false, readable = readable }
    end
    return { present = true, tier = best, maxTier = maxTier, outdated = best < (maxTier or 0), readable = readable }
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
