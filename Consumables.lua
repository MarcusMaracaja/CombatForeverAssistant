-- Combat Forever Assistant — Food, Potions & Items module.
-- Independent from class rotation modules: scans bags and action bars for:
--   1) Best Food (HP) and Drink/Water (Mana, mana classes only) out of combat while standing still
--   2) Best Combat Healing Potion (HP) and Mana Potion (Mana, mana classes only) during combat
--   3) Long-duration (5+ min) bonus potions, elixirs, flasks and scrolls missing from player buffs
--   4) User-configured situational item rules ([+] button): water breath, engineering bombs,
--      or triggering an item right after casting a chosen ability.
-- Highlights items on open bags, on action bars, or both simultaneously.

local addonName, addon = ...
local L = addon.L

local Consumables = {}
addon.Consumables = Consumables

local ORANGE = { 1.0, 0.55, 0.10 }
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ---------------------------------------------------------------------------
-- Safe API helpers (WoW Forever secret-safe)
-- ---------------------------------------------------------------------------
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function isSecret(v)
    if type(addon.IsSecretValue) == "function" then return addon.IsSecretValue(v) end
    if v == nil or type(_G.issecretvalue) ~= "function" then return false end
    local ok, s = pcall(_G.issecretvalue, v)
    return ok and s == true
end

local function safeNum(v, fallback)
    if type(addon.SafeNumber) == "function" then return addon.SafeNumber(v, fallback) end
    if type(v) ~= "number" or isSecret(v) or v ~= v or v == math.huge or v == -math.huge then
        return fallback
    end
    return v
end

local function safeStr(v)
    if type(v) ~= "string" or isSecret(v) or v == "" then return nil end
    return v
end

local function safeBool(v)
    if type(v) ~= "boolean" or isSecret(v) then return nil end
    return v
end

local function now()
    local ok, t = safeCall(GetTime)
    return ok and safeNum(t, 0) or 0
end

local PT_FOLD_MAP = {
    ["\195\128"] = "a", ["\195\129"] = "a", ["\195\130"] = "a", ["\195\131"] = "a", ["\195\132"] = "a",
    ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\163"] = "a", ["\195\164"] = "a",
    ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e",
    ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
    ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i",
    ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
    ["\195\146"] = "o", ["\195\147"] = "o", ["\195\148"] = "o", ["\195\149"] = "o", ["\195\150"] = "o",
    ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\181"] = "o", ["\195\182"] = "o",
    ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u", ["\195\156"] = "u",
    ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u", ["\195\188"] = "u",
    ["\195\135"] = "c", ["\195\167"] = "c",
    ["\195\145"] = "n", ["\195\177"] = "n",
}

-- Lua's :lower() does not fold UTF-8 accented capitals (Á, É, Ç, etc.); fold to ASCII first.
local function foldPT(s)
    if type(s) ~= "string" or s == "" then return "" end
    return (s:gsub("\195[\128-\191]", PT_FOLD_MAP)):lower()
end

local function normalizeText(s)
    s = safeStr(s)
    if not s then return "" end
    return (foldPT(s):gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function loc(key, fallback)
    return (L and L[key]) or fallback or key
end

-- ---------------------------------------------------------------------------
-- Player state helpers (mana class, HP/Mana, combat, moving, eating/drinking,
-- underwater breath)
-- ---------------------------------------------------------------------------
local MANA_CLASSES = {
    MAGE = true, PRIEST = true, WARLOCK = true, PALADIN = true,
    SHAMAN = true, DRUID = true, HUNTER = true,
}

function Consumables.PlayerHasMana()
    if type(addon.GetMana) == "function" then
        local _, maxMana = addon.GetMana("player")
        if maxMana and maxMana > 0 then return true end
    end
    local _, cls = UnitClass("player")
    return cls ~= nil and MANA_CLASSES[cls] == true
end

local function playerLevel()
    local ok, lvl = safeCall(UnitLevel, "player")
    return ok and safeNum(lvl, 60) or 60
end

local function playerInCombat()
    if type(UnitAffectingCombat) == "function" then
        local ok, v = safeCall(UnitAffectingCombat, "player")
        local b = ok and safeBool(v)
        if b ~= nil then return b end
    end
    if type(InCombatLockdown) == "function" then
        local ok, v = safeCall(InCombatLockdown)
        local b = ok and safeBool(v)
        if b ~= nil then return b end
    end
    return false
end

local function playerIsMoving()
    if type(GetUnitSpeed) == "function" then
        local ok, speed = safeCall(GetUnitSpeed, "player")
        local s = ok and safeNum(speed, nil) or nil
        if s ~= nil then return s > 0 end
    end
    if type(IsPlayerMoving) == "function" then
        local ok, moving = safeCall(IsPlayerMoving)
        local b = ok and safeBool(moving)
        if b ~= nil then return b end
    end
    return false
end

local function playerIsMounted()
    if type(IsMounted) == "function" then
        local ok, m = safeCall(IsMounted)
        local b = ok and safeBool(m)
        if b == true then return true end
    end
    return false
end

local function playerHealthPct()
    local okC, cur = safeCall(UnitHealth, "player")
    local okM, maxV = safeCall(UnitHealthMax, "player")
    cur = okC and safeNum(cur, nil) or nil
    maxV = okM and safeNum(maxV, nil) or nil
    if cur and maxV and maxV > 0 then
        return math.max(0, math.min(100, (cur / maxV) * 100))
    end
    return nil
end

local function playerManaPct()
    if type(addon.GetManaPct) == "function" then
        local pct, readable = addon.GetManaPct("player")
        if readable and pct ~= nil then return pct end
    end
    return nil
end

local function playerUnderwaterAndBreath()
    local swimming = false
    if type(IsSwimming) == "function" then
        local ok, v = safeCall(IsSwimming)
        if ok and safeBool(v) == true then swimming = true end
    end
    if not swimming and type(IsSubmerged) == "function" then
        local ok, v = safeCall(IsSubmerged)
        if ok and safeBool(v) == true then swimming = true end
    end

    local breathPct = nil
    if type(GetMirrorTimerInfo) == "function" then
        for i = 1, 3 do
            local ok, timerType, value, maxValue = safeCall(GetMirrorTimerInfo, i)
            if ok and safeStr(timerType) == "BREATH" then
                swimming = true
                local cur = safeNum(value, nil)
                local maxV = safeNum(maxValue, nil)
                if type(GetMirrorTimerProgress) == "function" then
                    local okP, prog = safeCall(GetMirrorTimerProgress, "BREATH")
                    local p = okP and safeNum(prog, nil) or nil
                    if p ~= nil then cur = p end
                end
                if cur and maxV and maxV > 0 then
                    breathPct = math.max(0, math.min(100, (cur / maxV) * 100))
                end
                break
            end
        end
    end
    return swimming, breathPct
end

-- ---------------------------------------------------------------------------
-- Food & Drink detection (known aura IDs + localized names + scanned item spells + beliefs)
-- ---------------------------------------------------------------------------
local FOOD_AURA_IDS = {
    [433] = true, [434] = true, [435] = true, [1127] = true, [1129] = true, [1131] = true,
    [2639] = true, [5004] = true, [5005] = true, [5006] = true, [5007] = true,
    [10256] = true, [10257] = true, [18229] = true, [18230] = true, [18231] = true,
    [18232] = true, [18233] = true, [18234] = true, [22731] = true, [24800] = true,
    [25660] = true, [25700] = true, [25886] = true, [26026] = true, [26402] = true,
    [29073] = true, [33261] = true, [33263] = true, [33265] = true, [33268] = true,
    [35272] = true, [43180] = true, [45548] = true, [45619] = true,
}

local DRINK_AURA_IDS = {
    [430] = true, [431] = true, [432] = true, [1133] = true, [1135] = true, [1137] = true,
    [10250] = true, [22734] = true, [24355] = true, [25696] = true, [26261] = true,
    [26473] = true, [27089] = true, [29007] = true, [30024] = true, [34291] = true,
    [43182] = true, [43183] = true, [45279] = true, [57073] = true,
}

local HYBRID_FOOD_DRINK_IDS = {
    [25990] = true, [43180] = true, [43182] = true, [43183] = true, [45548] = true,
}

-- Dynamically discovered spellIDs from scanned food/drink items in bags
local knownFoodSpellIDs = {}
local knownDrinkSpellIDs = {}

-- Beliefs populated on UNIT_SPELLCAST_SUCCEEDED / SENT so glow stops immediately
local POST_COMBAT_WINDOW = 20 -- seconds after leaving combat when HP/Mana are secret (nil)
local state = {
    eatingBeliefUntil = 0,
    drinkingBeliefUntil = 0,
    postCombatFoodUntil = 0,
    postCombatDrinkUntil = 0,
    usedItemUntil = {},      -- [itemID] = timestamp
    usedCategoryUntil = {},  -- [category] = timestamp
    lastCastByID = {},       -- [spellID] = timestamp
    lastCastByName = {},     -- [normalizedName] = timestamp
    lastCastSummary = nil,
}

local function nameLooksLikeFood(foldedName)
    if type(foldedName) ~= "string" or foldedName == "" then return false end
    if foldedName:find("well fed", 1, true) or foldedName:find("bem alimentad", 1, true) then
        return false
    end
    return foldedName == "food" or foldedName == "comida" or foldedName == "comer"
        or foldedName == "eating" or foldedName == "comendo"
        or foldedName:find("food", 1, true) ~= nil
        or foldedName:find("comida", 1, true) ~= nil
        or foldedName:find("comer", 1, true) ~= nil
        or foldedName:find("comendo", 1, true) ~= nil
        or foldedName:find("refeic", 1, true) ~= nil
        or foldedName:find("aliment", 1, true) ~= nil
end

local function nameLooksLikeDrink(foldedName)
    if type(foldedName) ~= "string" or foldedName == "" then return false end
    -- Intentionally does NOT match generic "agua" to avoid false positives on
    -- buffs like "Escudo de Agua" (Water Shield) or "Andar sobre a Agua" (Water Walking).
    return foldedName == "drink" or foldedName == "bebida" or foldedName == "beber"
        or foldedName == "drinking" or foldedName == "bebendo"
        or foldedName:find("drink", 1, true) ~= nil
        or foldedName:find("bebida", 1, true) ~= nil
        or foldedName:find("beber", 1, true) ~= nil
        or foldedName:find("bebendo", 1, true) ~= nil
        or foldedName:find("refresco", 1, true) ~= nil
        or foldedName:find("refreshment", 1, true) ~= nil
end

local auraCacheByID, auraCacheByName, auraCacheReadable
local auraCacheTime = 0

local function invalidateAuraCache()
    auraCacheByID = nil
    auraCacheByName = nil
    auraCacheTime = 0
end

local function collectPlayerAuras()
    local t = now()
    if auraCacheByID and (t - auraCacheTime) < 1.0 then
        return auraCacheByID, auraCacheByName, auraCacheReadable
    end
    local byID, byName = {}, {}
    local readable = false
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 60 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(aura) ~= "table" then break end
            readable = true
            local sid = safeNum(aura.spellId or aura.spellID, nil)
            if sid then byID[sid] = true end
            local nm = safeStr(aura.name)
            if nm then byName[normalizeText(nm)] = true end
        end
    elseif type(UnitBuff) == "function" then
        for i = 1, 60 do
            local ok, nm, _, _, _, _, _, _, _, _, sid = pcall(UnitBuff, "player", i)
            if not ok or not nm then break end
            readable = true
            sid = safeNum(sid, nil)
            if sid then byID[sid] = true end
            nm = safeStr(nm)
            if nm then byName[normalizeText(nm)] = true end
        end
    end
    auraCacheByID = byID
    auraCacheByName = byName
    auraCacheReadable = readable
    auraCacheTime = t
    return byID, byName, readable
end

local function checkEatingDrinking(aurasByID, aurasByName)
    local t = now()
    local eating = (t < state.eatingBeliefUntil)
    local drinking = (t < state.drinkingBeliefUntil)

    for sid in pairs(aurasByID) do
        if FOOD_AURA_IDS[sid] or HYBRID_FOOD_DRINK_IDS[sid] or knownFoodSpellIDs[sid] then
            eating = true
        end
        if DRINK_AURA_IDS[sid] or HYBRID_FOOD_DRINK_IDS[sid] or knownDrinkSpellIDs[sid] then
            drinking = true
        end
    end
    for nm in pairs(aurasByName) do
        -- Ignore "Well Fed" / "Bem Alimentado(a)" for active eating check
        local isWellFed = nm:find("well fed", 1, true) or nm:find("bem alimentad", 1, true)
        if not isWellFed then
            if nameLooksLikeFood(nm) then eating = true end
            if nameLooksLikeDrink(nm) then drinking = true end
        end
    end
    return eating, drinking
end

function Consumables.IsEatingOrDrinking()
    local okC, inComb = safeCall(UnitAffectingCombat, "player")
    if okC and not isSecret(inComb) and inComb == true then return false end
    local okL, locked = safeCall(InCombatLockdown)
    if okL and not isSecret(locked) and locked == true then return false end
    local aurasByID, aurasByName = collectPlayerAuras()
    local eating, drinking = checkEatingDrinking(aurasByID, aurasByName)
    return (eating or drinking) and true or false
end

-- ---------------------------------------------------------------------------
-- Curated item-ID catalogs with explicit tier & restore values so known Classic /
-- TBC / WotLK / WoW Forever consumables are always recognized immediately (even
-- before tooltips load or when sellPrice == 0, such as Conjured food/water).
-- Custom WoW Forever items not in these tables are also detected dynamically
-- via UTF-8-safe tooltip inspection below.
-- ---------------------------------------------------------------------------
local KNOWN_FOODS = {
    -- Tier 10 (lvl 1, ~61 HP)
    [117]   = { tier = 10, restore = 61 },   -- Tough Jerky
    [787]   = { tier = 10, restore = 61 },   -- Slitherskin Mackerel
    [2070]  = { tier = 10, restore = 61 },   -- Darnassian Bleu
    [4536]  = { tier = 10, restore = 61 },   -- Shiny Red Apple
    [4540]  = { tier = 10, restore = 61 },   -- Tough Hunk of Bread
    [4604]  = { tier = 10, restore = 61 },   -- Forest Mushroom Cap
    [5349]  = { tier = 10, restore = 61 },   -- Conjured Muffin
    [2679]  = { tier = 12, restore = 61 },   -- Charred Wolf Meat
    [2680]  = { tier = 12, restore = 61 },   -- Spiced Wolf Meat
    [2681]  = { tier = 12, restore = 61 },   -- Roasted Boar Meat
    [6888]  = { tier = 12, restore = 61 },   -- Herb Baked Egg
    [12224] = { tier = 12, restore = 61 },   -- Crispy Bat Wing
    [17197] = { tier = 12, restore = 61 },   -- Gingerbread Cookie
    -- Tier 20 (lvl 5, ~243 HP)
    [414]   = { tier = 20, restore = 243 },  -- Dalaran Sharp
    [1113]  = { tier = 20, restore = 243 },  -- Conjured Bread
    [2287]  = { tier = 20, restore = 243 },  -- Haunch of Meat
    [4537]  = { tier = 20, restore = 243 },  -- Tel'Abim Banana
    [4541]  = { tier = 20, restore = 243 },  -- Freshly Baked Bread
    [4592]  = { tier = 20, restore = 243 },  -- Longjaw Mud Snapper
    [4605]  = { tier = 20, restore = 243 },  -- Red-speckled Mushroom
    [2684]  = { tier = 22, restore = 243 },  -- Coyote Steak
    [2687]  = { tier = 22, restore = 243 },  -- Dry Pork Ribs
    [3220]  = { tier = 22, restore = 243 },  -- Blood Sausage
    [5472]  = { tier = 22, restore = 243 },  -- Kaldorei Spider Kabob
    [5474]  = { tier = 22, restore = 243 },  -- Roasted Kodo Meat
    [5525]  = { tier = 22, restore = 243 },  -- Boiled Clams
    [6290]  = { tier = 22, restore = 243 },  -- Brilliant Smallfish
    -- Tier 30 (lvl 15, ~552 HP)
    [422]   = { tier = 30, restore = 552 },  -- Dwarven Mild
    [1114]  = { tier = 30, restore = 552 },  -- Conjured Rye
    [3770]  = { tier = 30, restore = 552 },  -- Mutton Chop
    [4538]  = { tier = 30, restore = 552 },  -- Snapvine Watermelon
    [4542]  = { tier = 30, restore = 552 },  -- Moist Cornbread
    [4593]  = { tier = 30, restore = 552 },  -- Bristle Whisker Catfish
    [4606]  = { tier = 30, restore = 552 },  -- Spongy Morel
    [1082]  = { tier = 32, restore = 552 },  -- Redridge Goulash
    [2685]  = { tier = 32, restore = 552 },  -- Succulent Pork Ribs
    [3662]  = { tier = 32, restore = 552 },  -- Crocolisk Steak
    [3726]  = { tier = 32, restore = 552 },  -- Big Bear Steak
    [5477]  = { tier = 32, restore = 552 },  -- Strider Stew
    [5526]  = { tier = 32, restore = 552 },  -- Clam Chowder
    -- Tier 40 (lvl 25, ~874 HP)
    [1487]  = { tier = 40, restore = 874 },  -- Conjured Pumpernickel
    [1707]  = { tier = 40, restore = 874 },  -- Stormwind Brie
    [3771]  = { tier = 40, restore = 874 },  -- Wild Hog Shank
    [4539]  = { tier = 40, restore = 874 },  -- Goldenbark Apple
    [4544]  = { tier = 40, restore = 874 },  -- Mulgore Spice Bread
    [4594]  = { tier = 40, restore = 874 },  -- Rockscale Cod
    [4607]  = { tier = 40, restore = 874 },  -- Delicious Cave Mold
    [3727]  = { tier = 42, restore = 874 },  -- Hot Lion Chops
    [3728]  = { tier = 42, restore = 874 },  -- Tasty Lion Steak
    [4457]  = { tier = 42, restore = 874 },  -- Barbecued Buzzard Wing
    [12209] = { tier = 42, restore = 874 },  -- Lean Wolf Steak
    [12210] = { tier = 42, restore = 874 },  -- Roast Raptor
    [12213] = { tier = 42, restore = 874 },  -- Carrion Surprise
    [13851] = { tier = 42, restore = 874 },  -- Hot Wolf Ribs
    -- Tier 50 (lvl 35, ~1392 HP)
    [3927]  = { tier = 50, restore = 1392 }, -- Fine Aged Cheddar
    [4599]  = { tier = 50, restore = 1392 }, -- Cured Ham Steak
    [4601]  = { tier = 50, restore = 1392 }, -- Soft Banana Bread
    [4602]  = { tier = 50, restore = 1392 }, -- Moon Harvest Pumpkin
    [4608]  = { tier = 50, restore = 1392 }, -- Raw Black Truffle
    [8075]  = { tier = 50, restore = 1392 }, -- Conjured Sourdough
    [8950]  = { tier = 50, restore = 1392 }, -- Homemade Cherry Pie
    [8952]  = { tier = 50, restore = 1392 }, -- Roasted Quail
    [8957]  = { tier = 50, restore = 1392 }, -- Spinefin Halibut
    [12215] = { tier = 52, restore = 1392 }, -- Heavy Kodo Stew
    [12216] = { tier = 52, restore = 1392 }, -- Spider Sausage
    [12218] = { tier = 52, restore = 1392 }, -- Monster Omelet
    [13928] = { tier = 52, restore = 1392 }, -- Grilled Squid
    [13931] = { tier = 52, restore = 1392 }, -- Nightfin Soup
    -- Tier 60 (lvl 45-55, ~2148-2550 HP)
    [8076]  = { tier = 60, restore = 2148 }, -- Conjured Sweet Roll
    [8932]  = { tier = 60, restore = 2148 }, -- Alterac Swiss
    [8948]  = { tier = 60, restore = 2148 }, -- Dried King Bolete
    [8953]  = { tier = 60, restore = 2148 }, -- Deep Fried Plantains
    [13724] = { tier = 62, restore = 2148 }, -- Enriched Manna Biscuit (Food + Drink)
    [16169] = { tier = 60, restore = 2148 }, -- Wild Ricecake
    [18254] = { tier = 62, restore = 2148 }, -- Runn Tum Tuber Surprise
    [19301] = { tier = 65, restore = 2148 }, -- Alterac Manna Biscuit (Food + Drink)
    [20452] = { tier = 65, restore = 2550 }, -- Smoked Desert Dumplings
    [21023] = { tier = 65, restore = 2550 }, -- Dirge's Kickin' Chimaerok Chops
    [22895] = { tier = 68, restore = 3180 }, -- Conjured Cinnamon Roll
    -- Tier 70-80 (TBC / WotLK / Forever high-level)
    [27854] = { tier = 70, restore = 4320 }, -- Smoked Talbuk Venison
    [27855] = { tier = 70, restore = 4320 }, -- Mag'har Grainbread
    [27856] = { tier = 70, restore = 4320 }, -- Skethyl Berries
    [27857] = { tier = 70, restore = 4320 }, -- Garadar Sharp
    [27858] = { tier = 70, restore = 4320 }, -- Sunspring Carp
    [27859] = { tier = 70, restore = 4320 }, -- Zangar Caps
    [22019] = { tier = 72, restore = 7500 }, -- Conjured Croissant
    [33443] = { tier = 75, restore = 7500 }, -- Sour Goat Cheese
    [33449] = { tier = 78, restore = 15000 }, -- Crusty Flatbread
    [33451] = { tier = 78, restore = 15000 }, -- Fillet of Icefin
    [33454] = { tier = 80, restore = 22500 }, -- Salted Venison
    [35950] = { tier = 80, restore = 22500 }, -- Sweet Potato Bread
    [43518] = { tier = 82, restore = 22500 }, -- Conjured Mana Pie (Food + Drink)
    [43523] = { tier = 85, restore = 22500 }, -- Conjured Mana Strudel (Food + Drink)
}

local KNOWN_DRINKS = {
    -- Tier 10 (lvl 1, ~151 Mana)
    [159]   = { tier = 10, restore = 151 },  -- Refreshing Spring Water
    [5350]  = { tier = 12, restore = 151 },  -- Conjured Water
    -- Tier 20 (lvl 5, ~436 Mana)
    [1179]  = { tier = 20, restore = 436 },  -- Ice Cold Milk
    [2288]  = { tier = 22, restore = 436 },  -- Conjured Fresh Water
    -- Tier 30 (lvl 15, ~835 Mana)
    [1205]  = { tier = 30, restore = 835 },  -- Melon Juice
    [2136]  = { tier = 32, restore = 835 },  -- Conjured Purified Water
    [9451]  = { tier = 31, restore = 835 },  -- Bubbling Water
    -- Tier 40 (lvl 25, ~1344 Mana)
    [1708]  = { tier = 40, restore = 1344 }, -- Sweet Nectar
    [3772]  = { tier = 42, restore = 1344 }, -- Conjured Spring Water
    [10841] = { tier = 41, restore = 1344 }, -- Goldthorn Tea
    -- Tier 50 (lvl 35, ~1992 Mana)
    [1645]  = { tier = 50, restore = 1992 }, -- Moonberry Juice
    [8077]  = { tier = 52, restore = 1992 }, -- Conjured Mineral Water
    [19299] = { tier = 51, restore = 1992 }, -- Fizzy Faire Drink
    -- Tier 60 (lvl 45-55, ~2934-4410 Mana)
    [8766]  = { tier = 60, restore = 2934 }, -- Morning Glory Dew
    [8078]  = { tier = 61, restore = 2934 }, -- Conjured Sparkling Water
    [13724] = { tier = 62, restore = 2934 }, -- Enriched Manna Biscuit (Food + Drink)
    [18300] = { tier = 63, restore = 3500 }, -- Hyjal Nectar
    [19301] = { tier = 64, restore = 4410 }, -- Alterac Manna Biscuit (Food + Drink)
    [8079]  = { tier = 68, restore = 4200 }, -- Conjured Crystal Water
    -- Tier 70-85 (TBC / WotLK / Forever high-level)
    [27860] = { tier = 70, restore = 7200 }, -- Purified Draenic Water
    [28399] = { tier = 70, restore = 7200 }, -- Filtered Draenic Water
    [22018] = { tier = 72, restore = 7200 }, -- Conjured Glacier Water
    [30703] = { tier = 74, restore = 7200 }, -- Conjured Mountain Spring Water
    [33444] = { tier = 76, restore = 11340 }, -- Pungent Seal Whey
    [33445] = { tier = 80, restore = 19920 }, -- Honeymint Tea
    [43518] = { tier = 82, restore = 19920 }, -- Conjured Mana Pie (Food + Drink)
    [43523] = { tier = 85, restore = 19920 }, -- Conjured Mana Strudel (Food + Drink)
}

local KNOWN_HEAL_POTIONS = {
    -- Instant Healing Potions
    [118]   = { tier = 10, restore = 80 },   -- Minor Healing Potion
    [4596]  = { tier = 15, restore = 160 },  -- Discolored Healing Potion
    [858]   = { tier = 20, restore = 160 },  -- Lesser Healing Potion
    [929]   = { tier = 30, restore = 320 },  -- Healing Potion
    [1710]  = { tier = 40, restore = 525 },  -- Greater Healing Potion
    [3928]  = { tier = 50, restore = 800 },  -- Superior Healing Potion
    [18839] = { tier = 55, restore = 1375 }, -- Combat Healing Potion
    [17348] = { tier = 58, restore = 1375 }, -- Major Healing Draught
    [13446] = { tier = 60, restore = 1400 }, -- Major Healing Potion
    [18253] = { tier = 62, restore = 1600 }, -- Major Rejuvenation Potion (HP + Mana)
    [22829] = { tier = 70, restore = 2000 }, -- Super Healing Potion
    [33447] = { tier = 80, restore = 3500 }, -- Runic Healing Potion
    -- Warlock Healthstones (independent CD from potions!)
    [5512]  = { tier = 12, restore = 100 },  -- Minor Healthstone
    [19004] = { tier = 13, restore = 110 },  -- Minor Healthstone (1/2)
    [19005] = { tier = 14, restore = 120 },  -- Minor Healthstone (2/2)
    [5511]  = { tier = 22, restore = 250 },  -- Lesser Healthstone
    [19006] = { tier = 23, restore = 275 },  -- Lesser Healthstone (1/2)
    [19007] = { tier = 24, restore = 300 },  -- Lesser Healthstone (2/2)
    [5509]  = { tier = 32, restore = 500 },  -- Healthstone
    [19008] = { tier = 33, restore = 550 },  -- Healthstone (1/2)
    [19009] = { tier = 34, restore = 600 },  -- Healthstone (2/2)
    [5510]  = { tier = 42, restore = 800 },  -- Greater Healthstone
    [19010] = { tier = 43, restore = 880 },  -- Greater Healthstone (1/2)
    [19011] = { tier = 44, restore = 960 },  -- Greater Healthstone (2/2)
    [9421]  = { tier = 52, restore = 1200 }, -- Major Healthstone
    [19012] = { tier = 53, restore = 1320 }, -- Major Healthstone (1/2)
    [19013] = { tier = 54, restore = 1440 }, -- Major Healthstone (2/2)
    [22103] = { tier = 66, restore = 2080 }, -- Master Healthstone
    [22104] = { tier = 67, restore = 2288 }, -- Master Healthstone (1/2)
    [22105] = { tier = 68, restore = 2496 }, -- Master Healthstone (2/2)
    [36889] = { tier = 75, restore = 3500 }, -- Demonic Healthstone
    [36892] = { tier = 80, restore = 4280 }, -- Fel Healthstone
    [36893] = { tier = 81, restore = 4708 }, -- Fel Healthstone (1/2)
    [36894] = { tier = 82, restore = 5136 }, -- Fel Healthstone (2/2)
}

local KNOWN_MANA_POTIONS = {
    [2455]  = { tier = 10, restore = 160 },  -- Minor Mana Potion
    [3385]  = { tier = 20, restore = 320 },  -- Lesser Mana Potion
    [3827]  = { tier = 30, restore = 525 },  -- Mana Potion
    [6149]  = { tier = 40, restore = 800 },  -- Greater Mana Potion
    [13443] = { tier = 50, restore = 1050 }, -- Superior Mana Potion
    [18841] = { tier = 55, restore = 1050 }, -- Combat Mana Potion
    [17351] = { tier = 58, restore = 1375 }, -- Major Mana Draught
    [13444] = { tier = 60, restore = 1800 }, -- Major Mana Potion
    [18253] = { tier = 62, restore = 1600 }, -- Major Rejuvenation Potion (HP + Mana)
    [22832] = { tier = 70, restore = 2400 }, -- Super Mana Potion
    [33448] = { tier = 80, restore = 4300 }, -- Runic Mana Potion
}

-- ---------------------------------------------------------------------------
-- Curated database of WoW Vanilla / Forever long-duration (5+ min) bonus items
-- (Flasks, Elixirs, Scrolls) with explicit tier ranking. Custom Forever items
-- are also detected dynamically via tooltip inspection below!
-- ---------------------------------------------------------------------------
local LONG_BUFF_ITEMS = {
    -- Flasks (2h)
    [13510] = { category = "flask", group = "elixir", tier = 90, duration = 7200, buffs = { 17628 } }, -- Flask of the Titans
    [13511] = { category = "flask", group = "elixir", tier = 90, duration = 7200, buffs = { 17627 } }, -- Flask of Distilled Wisdom
    [13512] = { category = "flask", group = "elixir", tier = 90, duration = 7200, buffs = { 17626 } }, -- Flask of Supreme Power
    [13513] = { category = "flask", group = "elixir", tier = 85, duration = 7200, buffs = { 17629 } }, -- Flask of Chromatic Resistance

    -- Guardian Elixirs: Armor / Defense (60 min)
    [5997]  = { category = "armor_elixir", group = "elixir", tier = 10, duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Minor Defense
    [3389]  = { category = "armor_elixir", group = "elixir", tier = 25, duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Defense
    [8951]  = { category = "armor_elixir", group = "elixir", tier = 40, duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Greater Defense
    [13445] = { category = "armor_elixir", group = "elixir", tier = 60, duration = 3600, buffs = { 673, 3166, 3220, 11348, 17534 } }, -- Elixir of Superior Defense

    -- Guardian Elixirs: Health / Fortitude / HP5 / MP5
    [2458]  = { category = "health_elixir", group = "elixir", tier = 15, duration = 3600, buffs = { 2378, 3593 } }, -- Elixir of Minor Fortitude
    [3825]  = { category = "health_elixir", group = "elixir", tier = 40, duration = 3600, buffs = { 2378, 3593 } }, -- Elixir of Fortitude
    [3382]  = { category = "troll_blood",   group = "elixir", tier = 10, duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Weak Troll's Blood
    [3388]  = { category = "troll_blood",   group = "elixir", tier = 25, duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Strong Troll's Blood
    [3826]  = { category = "troll_blood",   group = "elixir", tier = 40, duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Mighty Troll's Blood
    [20004] = { category = "troll_blood",   group = "elixir", tier = 60, duration = 3600, buffs = { 3219, 3222, 3223, 24361 } }, -- Major Troll's Blood
    [20007] = { category = "mp5_elixir",    group = "elixir", tier = 60, duration = 3600, buffs = { 24363 } }, -- Mageblood Potion/Elixir
    [9088]  = { category = "gift_arthas",   group = "elixir", tier = 50, duration = 1800, buffs = { 11371 } }, -- Gift of Arthas

    -- Battle Elixirs: Agility / Strength / Stats / Spell Power
    [2457]  = { category = "agility_elixir", group = "elixir", tier = 10, duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Minor Agility
    [3390]  = { category = "agility_elixir", group = "elixir", tier = 20, duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Lesser Agility
    [8949]  = { category = "agility_elixir", group = "elixir", tier = 35, duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Agility
    [9187]  = { category = "agility_elixir", group = "elixir", tier = 50, duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Greater Agility
    [13452] = { category = "agility_elixir", group = "elixir", tier = 65, duration = 3600, buffs = { 2374, 3160, 11328, 11334, 17538 } }, -- Elixir of the Mongoose

    [2454]  = { category = "strength_elixir", group = "elixir", tier = 10, duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Lion's Strength
    [3391]  = { category = "strength_elixir", group = "elixir", tier = 25, duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Ogre's Strength
    [9206]  = { category = "strength_elixir", group = "elixir", tier = 55, duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Elixir of Giants
    [13453] = { category = "strength_elixir", group = "elixir", tier = 50, duration = 3600, buffs = { 2367, 3164, 11405, 17537 } }, -- Elixir of Brute Force

    [3383]  = { category = "intellect_elixir", group = "elixir", tier = 20, duration = 3600, buffs = { 3166, 11396, 17535 } }, -- Elixir of Wisdom
    [9179]  = { category = "intellect_elixir", group = "elixir", tier = 45, duration = 3600, buffs = { 11396, 17535 } }, -- Elixir of Greater Intellect
    [13447] = { category = "intellect_elixir", group = "elixir", tier = 60, duration = 3600, buffs = { 11396, 17535 } }, -- Elixir of the Sages

    [9155]  = { category = "spell_power_elixir", group = "elixir", tier = 45, duration = 1800, buffs = { 11390, 17539 } }, -- Arcane Elixir
    [13454] = { category = "spell_power_elixir", group = "elixir", tier = 60, duration = 3600, buffs = { 11390, 17539 } }, -- Greater Arcane Elixir
    [6373]  = { category = "fire_power_elixir",  group = "elixir", tier = 35, duration = 1800, buffs = { 7844, 26276 } }, -- Elixir of Firepower
    [21546] = { category = "fire_power_elixir",  group = "elixir", tier = 60, duration = 1800, buffs = { 7844, 26276 } }, -- Elixir of Greater Firepower
    [9264]  = { category = "shadow_power_elixir", group = "elixir", tier = 55, duration = 1800, buffs = { 11474 } }, -- Elixir of Shadow Power
    [17708] = { category = "frost_power_elixir", group = "elixir", tier = 55, duration = 1800, buffs = { 21920 } }, -- Elixir of Frost Power

    -- Scrolls (30 min, Ranks I-V)
    [3013]  = { category = "scroll_armor", group = "scroll", tier = 10, duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [1478]  = { category = "scroll_armor", group = "scroll", tier = 20, duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [4421]  = { category = "scroll_armor", group = "scroll", tier = 35, duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [10305] = { category = "scroll_armor", group = "scroll", tier = 50, duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },
    [27500] = { category = "scroll_armor", group = "scroll", tier = 65, duration = 1800, buffs = { 8091, 8094, 8095, 12175, 33079 } },

    [1180]  = { category = "scroll_stamina", group = "scroll", tier = 10, duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [1711]  = { category = "scroll_stamina", group = "scroll", tier = 20, duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [4422]  = { category = "scroll_stamina", group = "scroll", tier = 35, duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [10307] = { category = "scroll_stamina", group = "scroll", tier = 50, duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },
    [27502] = { category = "scroll_stamina", group = "scroll", tier = 65, duration = 1800, buffs = { 8099, 8100, 8101, 12178, 33081 } },

    [954]   = { category = "scroll_strength", group = "scroll", tier = 10, duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [2289]  = { category = "scroll_strength", group = "scroll", tier = 20, duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [4426]  = { category = "scroll_strength", group = "scroll", tier = 35, duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [10310] = { category = "scroll_strength", group = "scroll", tier = 50, duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },
    [27503] = { category = "scroll_strength", group = "scroll", tier = 65, duration = 1800, buffs = { 8118, 8119, 8120, 12179, 33082 } },

    [3012]  = { category = "scroll_agility", group = "scroll", tier = 10, duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [1477]  = { category = "scroll_agility", group = "scroll", tier = 20, duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [4425]  = { category = "scroll_agility", group = "scroll", tier = 35, duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [10309] = { category = "scroll_agility", group = "scroll", tier = 50, duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },
    [27498] = { category = "scroll_agility", group = "scroll", tier = 65, duration = 1800, buffs = { 8115, 8116, 8117, 12174, 33077 } },

    [955]   = { category = "scroll_intellect", group = "scroll", tier = 10, duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [2290]  = { category = "scroll_intellect", group = "scroll", tier = 20, duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [4427]  = { category = "scroll_intellect", group = "scroll", tier = 35, duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [10308] = { category = "scroll_intellect", group = "scroll", tier = 50, duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },
    [27499] = { category = "scroll_intellect", group = "scroll", tier = 65, duration = 1800, buffs = { 8096, 8097, 8098, 12176, 33078 } },

    [1181]  = { category = "scroll_spirit", group = "scroll", tier = 10, duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [1712]  = { category = "scroll_spirit", group = "scroll", tier = 20, duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [4424]  = { category = "scroll_spirit", group = "scroll", tier = 35, duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [10306] = { category = "scroll_spirit", group = "scroll", tier = 50, duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
    [27501] = { category = "scroll_spirit", group = "scroll", tier = 65, duration = 1800, buffs = { 8112, 8113, 8114, 12177, 33080 } },
}

-- Situational long-duration potions excluded from generic auto-buff (best used via custom rules [+])
local EXCLUDED_AUTO_BUFF_ITEMS = {
    [5996] = true, [18294] = true, [9279] = true, -- Water Breathing
    [6372] = true, -- Swim Speed
    [3823] = true, [9172] = true, -- Invisibility
    [9224] = true, -- Demonslaying
    [9154] = true, [3828] = true, [9197] = true, -- Detect Undead / Detect Invis / Dream Vision
    [13506] = true, -- Flask of Petrification
}

-- ---------------------------------------------------------------------------
-- Tooltip scanner & item classification cache
-- ---------------------------------------------------------------------------
local scanTooltip
local itemMetaCache = {}

local function getScanTooltip()
    if scanTooltip then return scanTooltip end
    scanTooltip = CreateFrame("GameTooltip", "CFA_ConsumablesScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

local function readTooltipText(itemID, bag, slot)
    local lines = {}
    if C_TooltipInfo then
        local data
        if bag ~= nil and slot ~= nil and type(C_TooltipInfo.GetBagItem) == "function" then
            local ok, res = pcall(C_TooltipInfo.GetBagItem, bag, slot)
            if ok and type(res) == "table" then data = res end
        end
        if not data and type(C_TooltipInfo.GetItemByID) == "function" then
            local ok, res = pcall(C_TooltipInfo.GetItemByID, itemID)
            if ok and type(res) == "table" then data = res end
        end
        if data and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                local t = type(line) == "table" and safeStr(line.leftText) or nil
                if t then lines[#lines + 1] = t end
            end
        end
    end
    if #lines == 0 then
        local tip = getScanTooltip()
        tip:ClearLines()
        local ok = false
        if bag ~= nil and slot ~= nil and type(tip.SetBagItem) == "function" then
            ok = pcall(tip.SetBagItem, tip, bag, slot)
        end
        if not ok and type(tip.SetItemByID) == "function" then
            pcall(tip.SetItemByID, tip, itemID)
        end
        local n = tip:NumLines() or 0
        for i = 1, math.min(n, 16) do
            local fs = _G["CFA_ConsumablesScanTooltipTextLeft" .. i]
            local t = fs and safeStr(fs:GetText()) or nil
            if t then lines[#lines + 1] = t end
        end
    end
    return table.concat(lines, "\n")
end

local function parseDurationSeconds(lowerText)
    if not lowerText or lowerText == "" then return 0 end
    local best = 0
    for h in lowerText:gmatch("(%d+)%s*h[or][ua]?r") do
        best = math.max(best, (tonumber(h) or 0) * 3600)
    end
    for h in lowerText:gmatch("(%d+)%s*hora") do
        best = math.max(best, (tonumber(h) or 0) * 3600)
    end
    for m in lowerText:gmatch("(%d+)%s*min") do
        best = math.max(best, (tonumber(m) or 0) * 60)
    end
    return best
end

local function parseRestoreAmount(lowerText, keywordPatterns)
    if not lowerText or lowerText == "" then return 0 end
    local best = 0
    for _, pat in ipairs(keywordPatterns) do
        for a, b in lowerText:gmatch(pat) do
            local raw = b or a
            local cleaned = raw and raw:gsub("[%.,]", "") or ""
            local val = tonumber(cleaned) or 0
            if val > best then best = val end
        end
    end
    return best
end

local function inferDynamicLongBuffCategory(foldedText, foldedName, subClassID, spellID)
    -- Skip situational buffs (underwater breath, swim speed, invisibility, protection vs school)
    if foldedText:find("breathe underwater", 1, true) or foldedText:find("respirar debaixo", 1, true)
        or foldedText:find("swim speed", 1, true) or foldedText:find("velocidade de nado", 1, true)
        or foldedText:find("invisib", 1, true) or foldedText:find("slow fall", 1, true)
        or foldedText:find("queda lenta", 1, true) or foldedText:find("detect ", 1, true)
        or foldedText:find("detectar ", 1, true) then
        return nil, nil
    end
    local isScroll = (subClassID == 3 or subClassID == 4)
        and (foldedName:find("scroll", 1, true) or foldedName:find("pergaminho", 1, true))
    local group = isScroll and "scroll" or "elixir"
    local prefix = isScroll and "scroll_" or "elixir_"

    if foldedText:find("armor", 1, true) or foldedText:find("armadura", 1, true) then
        return prefix .. "armor", group
    elseif foldedText:find("agility", 1, true) or foldedText:find("agilidade", 1, true) then
        return prefix .. "agility", group
    elseif foldedText:find("strength", 1, true) or foldedText:find("forca", 1, true) then
        return prefix .. "strength", group
    elseif foldedText:find("intellect", 1, true) or foldedText:find("intelecto", 1, true) then
        return prefix .. "intellect", group
    elseif foldedText:find("stamina", 1, true) or foldedText:find("vigor", 1, true) then
        return prefix .. "stamina", group
    elseif foldedText:find("spirit", 1, true) or foldedText:find("espirito", 1, true) then
        return prefix .. "spirit", group
    elseif foldedText:find("spell damage", 1, true) or foldedText:find("poder magico", 1, true)
        or foldedText:find("dano magico", 1, true) or foldedText:find("dano de feitico", 1, true)
        or foldedText:find("spell power", 1, true) then
        return "spell_power_elixir", group
    elseif foldedText:find("mana per", 1, true) or foldedText:find("mana a cada", 1, true) then
        return "mp5_elixir", group
    elseif foldedText:find("maximum health", 1, true) or foldedText:find("vida maxima", 1, true)
        or foldedText:find("saude maxima", 1, true) then
        return "health_elixir", group
    elseif foldedText:find("attack power", 1, true) or foldedText:find("poder de ataque", 1, true) then
        return "attack_power_elixir", group
    elseif foldedText:find("critical", 1, true) or foldedText:find("critico", 1, true) then
        return "crit_elixir", group
    elseif spellID then
        return prefix .. "spell_" .. tostring(spellID), group
    end
    return nil, nil
end

local function inspectItem(itemID, bag, slot)
    if type(itemID) ~= "number" then return nil end
    local cached = itemMetaCache[itemID]
    if cached and cached.loaded then return cached end

    local getter = (C_Item and type(C_Item.GetItemInfo) == "function") and C_Item.GetItemInfo or GetItemInfo
    local ok, name, link, quality, itemLevel, minLevel, itemType, itemSubType,
        _, equipLoc, texture, sellPrice, classID, subClassID = safeCall(getter, itemID)
    if not ok or not safeStr(name) then
        return { itemID = itemID, name = "Item " .. tostring(itemID), loaded = false }
    end

    local spellGetter = (C_Item and type(C_Item.GetItemSpell) == "function") and C_Item.GetItemSpell or GetItemSpell
    local okSp, spellName, spellID = safeCall(spellGetter, itemID)
    spellName = okSp and safeStr(spellName) or nil
    spellID = okSp and safeNum(spellID, nil) or nil

    local tipText = readTooltipText(itemID, bag, slot)
    local foldedText = foldPT(tipText)
    local foldedName = foldPT(name)
    local foldedSub = foldPT(safeStr(itemSubType) or "")
    local foldedSpell = spellName and normalizeText(spellName) or ""

    local meta = {
        itemID = itemID,
        name = name,
        link = link,
        quality = safeNum(quality, 1) or 1,
        itemLevel = safeNum(itemLevel, 0) or 0,
        minLevel = safeNum(minLevel, 0) or 0,
        itemType = safeStr(itemType) or "",
        itemSubType = safeStr(itemSubType) or "",
        equipLoc = safeStr(equipLoc) or "",
        texture = texture or QUESTION_MARK,
        sellPrice = safeNum(sellPrice, 0) or 0,
        classID = safeNum(classID, -1) or -1,
        subClassID = safeNum(subClassID, -1) or -1,
        spellName = spellName,
        spellID = spellID,
        tipLen = #tipText,
        usable = (spellID ~= nil or spellName ~= nil or foldedText:find("use:", 1, true) ~= nil
            or foldedText:find("uso:", 1, true) ~= nil),
        isFood = false,
        isDrink = false,
        foodTier = 0,
        drinkTier = 0,
        foodRestore = 0,
        drinkRestore = 0,
        isHealPot = false,
        isManaPot = false,
        healPotTier = 0,
        manaPotTier = 0,
        healPotRestore = 0,
        manaPotRestore = 0,
        longBuff = nil,
        longBuffTier = 0,
        loaded = true,
    }

    local curatedMatch = false

    -- 1) Curated catalogs FIRST (work even before tooltip loads or when sellPrice == 0)
    local kf = KNOWN_FOODS[itemID]
    if kf then
        curatedMatch = true
        meta.isFood = true
        meta.foodTier = kf.tier or 0
        meta.foodRestore = kf.restore or 0
        meta.usable = true
        if spellID then knownFoodSpellIDs[spellID] = true end
    end
    local kd = KNOWN_DRINKS[itemID]
    if kd then
        curatedMatch = true
        meta.isDrink = true
        meta.drinkTier = kd.tier or 0
        meta.drinkRestore = kd.restore or 0
        meta.usable = true
        if spellID then knownDrinkSpellIDs[spellID] = true end
    end
    local khp = KNOWN_HEAL_POTIONS[itemID]
    if khp then
        curatedMatch = true
        meta.isHealPot = true
        meta.healPotTier = khp.tier or 0
        meta.healPotRestore = khp.restore or 0
        meta.usable = true
    end
    local kmp = KNOWN_MANA_POTIONS[itemID]
    if kmp then
        curatedMatch = true
        meta.isManaPot = true
        meta.manaPotTier = kmp.tier or 0
        meta.manaPotRestore = kmp.restore or 0
        meta.usable = true
    end

    -- 2) Dynamic Food / Drink detection (custom WoW Forever items + tooltip restore refinement)
    local isConsumable = (meta.classID == 0)
    local isFoodDrinkSub = isConsumable and (
        meta.subClassID == 5
        or foldedSub:find("food", 1, true) ~= nil
        or foldedSub:find("drink", 1, true) ~= nil
        or foldedSub:find("comida", 1, true) ~= nil
        or foldedSub:find("bebida", 1, true) ~= nil
    )
    local seatedHint = foldedText:find("seated", 1, true) ~= nil
        or foldedText:find("sentad", 1, true) ~= nil
        or foldedText:find("enquanto come", 1, true) ~= nil
        or foldedText:find("enquanto bebe", 1, true) ~= nil
        or foldedText:find("while eating", 1, true) ~= nil
        or foldedText:find("while drinking", 1, true) ~= nil
        or (isFoodDrinkSub and (foldedText:find("durante", 1, true) ~= nil or foldedText:find("over ", 1, true) ~= nil))
        or (spellID ~= nil and (FOOD_AURA_IDS[spellID] or DRINK_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID]))
        or (foldedSpell ~= "" and (nameLooksLikeFood(foldedSpell) or nameLooksLikeDrink(foldedSpell)))

    if isConsumable and (isFoodDrinkSub or seatedHint) and meta.subClassID ~= 1 and meta.subClassID ~= 2 and meta.subClassID ~= 3 then
        local mentionsHealth = foldedText:find("health", 1, true) ~= nil
            or foldedText:find("vida", 1, true) ~= nil
            or foldedText:find("saude", 1, true) ~= nil
        local mentionsMana = foldedText:find("mana", 1, true) ~= nil

        if (mentionsHealth and seatedHint)
            or (spellID and (FOOD_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID]))
            or (foldedSpell ~= "" and nameLooksLikeFood(foldedSpell)) then
            meta.isFood = true
            local parsed = parseRestoreAmount(foldedText, {
                "restores?%s+([%d%.,]+)%s+health",
                "restaura%s+([%d%.,]+)%s+p?o?n?t?o?s?%s*d?e?%s*vida",
                "restaura%s+([%d%.,]+)%s+de%s+vida",
                "restaura%s+([%d%.,]+)%s+de%s+saude",
                "([%d%.,]+)%s+health",
                "([%d%.,]+)%s+de%s+vida",
                "([%d%.,]+)%s+de%s+saude",
            })
            if parsed > meta.foodRestore then meta.foodRestore = parsed end
            if spellID then knownFoodSpellIDs[spellID] = true end
        end

        if (mentionsMana and seatedHint)
            or (spellID and (DRINK_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID]))
            or (foldedSpell ~= "" and nameLooksLikeDrink(foldedSpell)) then
            meta.isDrink = true
            local parsed = parseRestoreAmount(foldedText, {
                "restores?%s+([%d%.,]+)%s+mana",
                "restaura%s+([%d%.,]+)%s+p?o?n?t?o?s?%s*d?e?%s*mana",
                "restaura%s+([%d%.,]+)%s+de%s+mana",
                "([%d%.,]+)%s+mana",
                "([%d%.,]+)%s+de%s+mana",
            })
            if parsed > meta.drinkRestore then meta.drinkRestore = parsed end
            if spellID then knownDrinkSpellIDs[spellID] = true end
        end
    end

    -- 3) Dynamic Combat Healing / Mana Potion detection (custom WoW Forever potions)
    if isConsumable and not meta.isFood and not meta.isDrink and not EXCLUDED_AUTO_BUFF_ITEMS[itemID] then
        local dur = parseDurationSeconds(foldedText)
        local isBandage = foldedName:find("bandage", 1, true) ~= nil
            or foldedName:find("bandagem", 1, true) ~= nil
            or foldedName:find("atadura", 1, true) ~= nil
            or foldedSub:find("bandage", 1, true) ~= nil
            or foldedSub:find("bandagem", 1, true) ~= nil
        local looksLikePotion = (meta.subClassID == 1)
            or foldedSub:find("potion", 1, true) ~= nil
            or foldedSub:find("pocao", 1, true) ~= nil
            or foldedName:find("potion", 1, true) ~= nil
            or foldedName:find("pocao", 1, true) ~= nil
            or foldedName:find("draught", 1, true) ~= nil
            or foldedName:find("healthstone", 1, true) ~= nil
            or foldedName:find("pedra de vida", 1, true) ~= nil
            or foldedName:find("pedra da vida", 1, true) ~= nil
        local isOverTimeBuff = foldedText:find("per 5", 1, true) ~= nil
            or foldedText:find("every 5", 1, true) ~= nil
            or foldedText:find("a cada 5", 1, true) ~= nil
            or foldedText:find("maximum health", 1, true) ~= nil
            or foldedText:find("vida maxima", 1, true) ~= nil
            or foldedText:find("saude maxima", 1, true) ~= nil
        if looksLikePotion and not isBandage and not seatedHint and dur < 60 and not isOverTimeBuff then
            local restoresWord = foldedText:find("restor", 1, true) ~= nil
                or foldedText:find("restaur", 1, true) ~= nil
                or foldedText:find("recuper", 1, true) ~= nil
                or foldedText:find("heal", 1, true) ~= nil
                or foldedText:find("cura", 1, true) ~= nil
            local mentionsHP = foldedText:find("health", 1, true) ~= nil
                or foldedText:find("vida", 1, true) ~= nil
                or foldedText:find("saude", 1, true) ~= nil
            local mentionsMP = foldedText:find("mana", 1, true) ~= nil
            if restoresWord and mentionsHP then
                meta.isHealPot = true
                local parsed = parseRestoreAmount(foldedText, {
                    "([%d%.,]+)%s+to%s+([%d%.,]+)%s+health",
                    "([%d%.,]+)%s+a%s+([%d%.,]+)%s+p?o?n?t?o?s?%s*d?e?%s*vida",
                    "([%d%.,]+)%s+health",
                    "([%d%.,]+)%s+de%s+vida",
                    "([%d%.,]+)%s+pontos%s+de%s+vida",
                    "([%d%.,]+)%s+de%s+saude",
                })
                if parsed > meta.healPotRestore then meta.healPotRestore = parsed end
            end
            if restoresWord and mentionsMP then
                meta.isManaPot = true
                local parsed = parseRestoreAmount(foldedText, {
                    "([%d%.,]+)%s+to%s+([%d%.,]+)%s+mana",
                    "([%d%.,]+)%s+a%s+([%d%.,]+)%s+p?o?n?t?o?s?%s*d?e?%s*mana",
                    "([%d%.,]+)%s+mana",
                    "([%d%.,]+)%s+de%s+mana",
                    "([%d%.,]+)%s+pontos%s+de%s+mana",
                })
                if parsed > meta.manaPotRestore then meta.manaPotRestore = parsed end
            end
        end
    end

    -- 4) Long-duration (5+ min) bonus potions, elixirs, flasks and scrolls
    if not EXCLUDED_AUTO_BUFF_ITEMS[itemID] then
        local curated = LONG_BUFF_ITEMS[itemID]
        if curated then
            curatedMatch = true
            local buffs = {}
            for _, bid in ipairs(curated.buffs or {}) do buffs[#buffs + 1] = bid end
            if spellID then buffs[#buffs + 1] = spellID end
            meta.longBuff = {
                category = curated.category,
                group = curated.group,
                tier = curated.tier or 0,
                duration = curated.duration,
                buffs = buffs,
                buffName = spellName and normalizeText(spellName) or nil,
            }
            meta.longBuffTier = curated.tier or 0
            meta.usable = true
        elseif isConsumable and not meta.isFood and not meta.isDrink and not meta.isHealPot and not meta.isManaPot then
            local dur = parseDurationSeconds(foldedText)
            local looksLikeBuff = foldedText:find("increases", 1, true) ~= nil
                or foldedText:find("aumenta", 1, true) ~= nil
                or foldedText:find("regenerates", 1, true) ~= nil
                or foldedText:find("regenera", 1, true) ~= nil
                or foldedText:find("restores", 1, true) ~= nil
                or foldedText:find("restaura", 1, true) ~= nil
                or foldedName:find("elixir", 1, true) ~= nil
                or foldedName:find("flask", 1, true) ~= nil
                or foldedName:find("frasco", 1, true) ~= nil
                or foldedName:find("scroll", 1, true) ~= nil
                or foldedName:find("pergaminho", 1, true) ~= nil
            if dur >= 300 and looksLikeBuff then
                local cat, grp = inferDynamicLongBuffCategory(foldedText, foldedName, meta.subClassID, spellID)
                if cat then
                    meta.longBuff = {
                        category = cat,
                        group = grp,
                        tier = 0,
                        duration = dur,
                        buffs = spellID and { spellID } or {},
                        buffName = spellName and normalizeText(spellName) or nil,
                    }
                    meta.longBuffTier = 0
                end
            end
        end
    end

    -- Never permanently cache an unclassified item whose tooltip had not loaded yet!
    if tipText ~= "" or curatedMatch then
        itemMetaCache[itemID] = meta
    end
    return meta
end

-- ---------------------------------------------------------------------------
-- Inventory scanning (bags + action bar items) & cooldown/in-use checks
-- ---------------------------------------------------------------------------
local function containerNumSlots(bag)
    local fn = (C_Container and type(C_Container.GetContainerNumSlots) == "function" and C_Container.GetContainerNumSlots)
        or (type(GetContainerNumSlots) == "function" and GetContainerNumSlots)
    local ok, n = safeCall(fn, bag)
    return ok and safeNum(n, 0) or 0
end

local function containerItemID(bag, slot)
    if C_Container and type(C_Container.GetContainerItemID) == "function" then
        local ok, id = safeCall(C_Container.GetContainerItemID, bag, slot)
        if ok and type(id) == "number" then return id end
    end
    if type(GetContainerItemID) == "function" then
        local ok, id = safeCall(GetContainerItemID, bag, slot)
        if ok and type(id) == "number" then return id end
    end
    return nil
end

local function isItemOnCooldown(itemID, bag, slot)
    local t = now()
    if state.usedItemUntil[itemID] and t < state.usedItemUntil[itemID] then
        return true, "just_used"
    end

    local function checkStartDur(startVal, durVal, enableVal)
        local s = safeNum(startVal, nil)
        local d = safeNum(durVal, nil)
        local e = safeNum(enableVal, 1)
        if e == 0 then return false end
        if s and d and d > 0 then
            if (s + d - t) > 0.3 then return true end
        end
        return false
    end

    if C_Item and type(C_Item.GetItemCooldown) == "function" then
        local ok, s, d, e = safeCall(C_Item.GetItemCooldown, itemID)
        if ok and checkStartDur(s, d, e) then return true, "C_Item.GetItemCooldown" end
    elseif type(GetItemCooldown) == "function" then
        local ok, s, d, e = safeCall(GetItemCooldown, itemID)
        if ok and checkStartDur(s, d, e) then return true, "GetItemCooldown" end
    end

    if bag ~= nil and slot ~= nil then
        local fn = (C_Container and type(C_Container.GetContainerItemCooldown) == "function" and C_Container.GetContainerItemCooldown)
            or (type(GetContainerItemCooldown) == "function" and GetContainerItemCooldown)
        if fn then
            local ok, s, d, e = safeCall(fn, bag, slot)
            if ok and checkStartDur(s, d, e) then return true, "GetContainerItemCooldown" end
        end
    end

    -- Check if currently casting/channeling the item's spell
    local meta = itemMetaCache[itemID]
    if meta and meta.spellName then
        if addon.Compat and addon.Compat.CastingOrChanneling then
            local rem = addon.Compat.CastingOrChanneling(meta.spellName, "player")
            if rem and safeNum(rem, 0) > 0 then return true, "casting" end
        end
        if addon.Compat and addon.Compat.IsCurrentSpell and addon.Compat.IsCurrentSpell(meta.spellID or meta.spellName) then
            return true, "current_spell"
        end
    end

    return false, nil
end

local bagScanCache
local bagScanTime = 0

local function scanOwnedBagItems(force)
    local t = now()
    -- Cache invalidated immediately by BAG_UPDATE_DELAYED / ACTIONBAR_SLOT_CHANGED;
    -- 30s safety TTL avoids re-scanning 100+ bag slots every 0.8s.
    if not force and bagScanCache and (t - bagScanTime) < 30 then
        return bagScanCache
    end
    local items = {} -- [itemID] = { itemID, bag, slot, onBar, meta }
    local bagCount = tonumber(_G.NUM_BAG_SLOTS) or 4
    for bag = 0, bagCount do
        local slots = containerNumSlots(bag)
        for slot = 1, slots do
            local itemID = containerItemID(bag, slot)
            if itemID and not items[itemID] then
                local meta = inspectItem(itemID, bag, slot)
                local barButtons = addon.Visuals and addon.Visuals.FindItemButtons
                    and addon.Visuals.FindItemButtons(itemID) or {}
                items[itemID] = {
                    itemID = itemID,
                    bag = bag,
                    slot = slot,
                    onBar = (#barButtons > 0),
                    meta = meta,
                }
            end
        end
    end
    bagScanCache = items
    bagScanTime = t
    return items
end

-- ---------------------------------------------------------------------------
-- SavedVariables helpers (per-character)
-- ---------------------------------------------------------------------------
local function getConfig(create)
    if type(addon.charDb) ~= "table" then return nil end
    local cfg = addon.charDb.consumables
    if type(cfg) ~= "table" then
        if not create then return nil end
        cfg = {
            foodEnabled = false,
            foodThreshold = 50,
            drinkEnabled = false,
            drinkThreshold = 50,
            healPotEnabled = false,
            healPotThreshold = 40,
            manaPotEnabled = false,
            manaPotThreshold = 35,
            bonusEnabled = false,
            bonusElixirs = true,
            bonusScrolls = true,
            customRules = {},
            nextRuleId = 1,
        }
        addon.charDb.consumables = cfg
    end
    if cfg.foodThreshold == nil then cfg.foodThreshold = 50 end
    if cfg.drinkThreshold == nil then cfg.drinkThreshold = 50 end
    if cfg.healPotThreshold == nil then cfg.healPotThreshold = 40 end
    if cfg.manaPotThreshold == nil then cfg.manaPotThreshold = 35 end
    if cfg.bonusElixirs == nil then cfg.bonusElixirs = true end
    if cfg.bonusScrolls == nil then cfg.bonusScrolls = true end
    if type(cfg.customRules) ~= "table" then cfg.customRules = {} end
    if type(cfg.nextRuleId) ~= "number" then cfg.nextRuleId = #cfg.customRules + 1 end
    return cfg
end

function Consumables.GetConfig()
    return getConfig(true)
end

-- ---------------------------------------------------------------------------
-- Custom rules conditions (independent from class modules)
-- ---------------------------------------------------------------------------
local RULE_AXES = {
    {
        key = "combat",
        labelKey = "cons_axis_combat",
        fallback = "1. Combate",
        options = {
            { 1, "axis_in_combat",  "Em combate" },
            { 2, "axis_out_combat", "Fora de combate" },
        },
    },
    {
        key = "env",
        labelKey = "cons_axis_env",
        fallback = "2. Ambiente",
        options = {
            { 1, "PvE",                 "PvE" },
            { 2, "PvP",                 "PvP" },
            { 3, "cons_env_underwater", "Na água / submerso" },
        },
    },
    {
        key = "breath",
        labelKey = "cons_axis_breath",
        fallback = "3. Fôlego (água)",
        options = {
            { 1, "cons_breath_50", "Fôlego < 50%" },
            { 2, "cons_breath_30", "Fôlego < 30%" },
        },
    },
    {
        key = "hp",
        labelKey = "cons_axis_hp",
        fallback = "4. Vida do jogador",
        options = {
            { 1, "cons_hp_25", "Vida <= 25%" },
            { 2, "cons_hp_40", "Vida <= 40%" },
            { 3, "cons_hp_60", "Vida <= 60%" },
            { 4, "cons_hp_75", "Vida <= 75%" },
        },
    },
    {
        key = "mana",
        labelKey = "cons_axis_mana",
        fallback = "5. Mana do jogador",
        manaOnly = true,
        options = {
            { 1, "cons_mana_25", "Mana <= 25%" },
            { 2, "cons_mana_40", "Mana <= 40%" },
            { 3, "cons_mana_60", "Mana <= 60%" },
        },
    },
    {
        key = "target",
        labelKey = "cons_axis_target",
        fallback = "6. Alvo / Alcance",
        options = {
            { 1, "axis_attackable", "Inimigo atacável" },
            { 2, "axis_melee",      "Em alcance melee" },
            { 3, "axis_ranged",     "À distância (ranged)" },
            { 4, "axis_aoe_2",      "Área (2+ inimigos)" },
        },
    },
}

local function buildConsumableEnv()
    local inCombat = playerInCombat()
    local moving = playerIsMoving()
    local hpPct = playerHealthPct()
    local manaPct = playerManaPct()
    local swimming, breathPct = playerUnderwaterAndBreath()
    local isPvP = (type(addon.IsPvPInstance) == "function" and addon.IsPvPInstance()) or false
    local hasEnemy = (type(addon.UnitTargetExistsAndAttackable) == "function" and addon.UnitTargetExistsAndAttackable()) or false
    local isMelee = false
    if hasEnemy and type(addon.IsInMeleeRange) == "function" then
        local ok, m = pcall(addon.IsInMeleeRange, addon, "target")
        isMelee = ok and m == true
    end
    local enemies = hasEnemy and 1 or 0
    if C_NamePlate and type(C_NamePlate.EnumerateUnits) == "function" then
        local ok, units = pcall(function() return { C_NamePlate.EnumerateUnits() } end)
        if ok and type(units) == "table" then
            local c = 0
            for _, u in ipairs(units) do
                if addon.Enemy and addon:Enemy(u) then c = c + 1 end
            end
            if c > enemies then enemies = c end
        end
    end
    return {
        inCombat = inCombat,
        moving = moving,
        mounted = playerIsMounted(),
        hpPct = hpPct,
        manaPct = manaPct,
        hasMana = Consumables.PlayerHasMana(),
        swimming = swimming,
        breathPct = breathPct,
        isPvP = isPvP,
        hasEnemy = hasEnemy,
        isMelee = isMelee,
        isAoE = enemies >= 2,
        enemyCount = enemies,
        bagOpen = (addon.Visuals and addon.Visuals.IsAnyBagOpen and addon.Visuals.IsAnyBagOpen()) or false,
    }
end

local function isTriggerSpellRecent(rule)
    local trigID = tonumber(rule.triggerSpellID)
    local trigName = safeStr(rule.triggerSpellName)
    if not trigID and not trigName then return true end
    local window = tonumber(rule.triggerWindow) or 8
    local t = now()
    if trigID then
        local ts = state.lastCastByID[trigID]
        if ts and (t - ts) <= window then return true end
        local fam = addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[trigID]
        if fam then
            for _, id in ipairs(fam) do
                local fts = state.lastCastByID[id]
                if fts and (t - fts) <= window then return true end
            end
        end
    end
    if trigName then
        local ts = state.lastCastByName[normalizeText(trigName)]
        if ts and (t - ts) <= window then return true end
    end
    return false
end

local function ruleHasAnyCondition(rule)
    if type(rule) ~= "table" then return false end
    if rule.triggerSpellID or safeStr(rule.triggerSpellName) then return true end
    if type(rule.conditions) == "table" then
        for _, v in pairs(rule.conditions) do
            if tonumber(v) and tonumber(v) ~= 0 then return true end
        end
    end
    return false
end

local function evaluateCustomRule(rule, env)
    if type(rule) ~= "table" or rule.enabled == false or not tonumber(rule.itemID) then
        return false, "disabled_or_no_item"
    end
    local conds = type(rule.conditions) == "table" and rule.conditions or {}

    local vCombat = tonumber(conds.combat) or 0
    if vCombat == 1 and not env.inCombat then return false, "need_combat" end
    if vCombat == 2 and env.inCombat then return false, "need_out_of_combat" end

    local vEnv = tonumber(conds.env) or 0
    if vEnv == 1 and env.isPvP then return false, "need_pve" end
    if vEnv == 2 and not env.isPvP then return false, "need_pvp" end
    if vEnv == 3 and not env.swimming then return false, "need_underwater" end

    local vBreath = tonumber(conds.breath) or 0
    if vBreath == 1 then
        if not env.breathPct or env.breathPct >= 50 then return false, "breath_ok" end
    elseif vBreath == 2 then
        if not env.breathPct or env.breathPct >= 30 then return false, "breath_ok" end
    end

    local vHP = tonumber(conds.hp) or 0
    if vHP > 0 then
        local limits = { 25, 40, 60, 75 }
        local lim = limits[vHP]
        if not env.hpPct or env.hpPct > lim then return false, "hp_above_limit" end
    end

    local vMana = tonumber(conds.mana) or 0
    if vMana > 0 then
        local limits = { 25, 40, 60 }
        local lim = limits[vMana]
        if not env.hasMana or not env.manaPct or env.manaPct > lim then return false, "mana_above_limit" end
    end

    local vTarget = tonumber(conds.target) or 0
    if vTarget == 1 and not env.hasEnemy then return false, "need_enemy" end
    if vTarget == 2 and not (env.hasEnemy and env.isMelee) then return false, "need_melee" end
    if vTarget == 3 and not (env.hasEnemy and not env.isMelee) then return false, "need_ranged" end
    if vTarget == 4 and not (env.hasEnemy and env.isAoE) then return false, "need_aoe" end

    if rule.triggerSpellID or safeStr(rule.triggerSpellName) then
        if not isTriggerSpellRecent(rule) then return false, "waiting_trigger_spell" end
    end

    return true, "ok"
end

-- ---------------------------------------------------------------------------
-- Candidate ranking & buff matching
-- ---------------------------------------------------------------------------
local function isBetterCandidate(a, b, tierField, restoreField)
    if not b then return true end
    local ma, mb = a.meta, b.meta
    local ta = (tierField and ma[tierField]) or 0
    local tb = (tierField and mb[tierField]) or 0
    -- If both items are in our curated catalog, prefer the higher curated tier first
    -- (so e.g. Conjured Crystal Water [0c, 4200 mana] beats Refreshing Spring Water [1c, 151 mana]).
    if ta > 0 and tb > 0 and ta ~= tb then
        return ta > tb
    end
    -- Next, prefer higher parsed/cataloged restore amount (works for custom Forever items too)
    if restoreField then
        local ra, rb = ma[restoreField] or 0, mb[restoreField] or 0
        if ra ~= rb then return ra > rb end
    end
    -- Next, highest vendor value (sellPrice)
    if (ma.sellPrice or 0) ~= (mb.sellPrice or 0) then
        return (ma.sellPrice or 0) > (mb.sellPrice or 0)
    end
    -- Tie-breakers: itemLevel -> minLevel -> curated tier
    if (ma.itemLevel or 0) ~= (mb.itemLevel or 0) then
        return (ma.itemLevel or 0) > (mb.itemLevel or 0)
    end
    if (ma.minLevel or 0) ~= (mb.minLevel or 0) then
        return (ma.minLevel or 0) > (mb.minLevel or 0)
    end
    return ta > tb
end

local function isLongBuffActive(entry, aurasByID, aurasByName)
    local lb = entry.meta and entry.meta.longBuff
    if not lb then return false end
    local t = now()
    if state.usedCategoryUntil[lb.category] and t < state.usedCategoryUntil[lb.category] then
        return true
    end
    for _, bid in ipairs(lb.buffs or {}) do
        if aurasByID[bid] then return true end
    end
    if entry.meta.spellID and aurasByID[entry.meta.spellID] then
        return true
    end
    if lb.buffName and lb.buffName ~= "" and aurasByName[lb.buffName] then
        return true
    end
    -- If a Flask is active, treat flask category as satisfied
    if lb.category == "flask" then
        for _, fid in ipairs({ 17626, 17627, 17628, 17629 }) do
            if aurasByID[fid] then return true end
        end
    end
    return false
end

local function itemIsEligibleToShow(entry, bagOpen)
    if not entry or not entry.meta then return false end
    if (entry.meta.minLevel or 0) > playerLevel() then return false end
    -- When bag is open: can highlight in bag (and on bar if also bound).
    -- When bag is closed: only suggest if the item is on an action bar.
    if not bagOpen and not entry.onBar then return false end
    local onCD = isItemOnCooldown(entry.itemID, entry.bag, entry.slot)
    if onCD then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Main independent suggestion generator (called by Core every tick)
-- ---------------------------------------------------------------------------
function Consumables.GetSuggestions()
    local cfg = getConfig(false)
    if not cfg then return {} end
    if not cfg.foodEnabled and not cfg.drinkEnabled
        and not cfg.healPotEnabled and not cfg.manaPotEnabled
        and not cfg.bonusEnabled
        and (type(cfg.customRules) ~= "table" or #cfg.customRules == 0) then
        return {}
    end

    local env = buildConsumableEnv()
    local owned = scanOwnedBagItems(false)
    local aurasByID, aurasByName = collectPlayerAuras()
    local eating, drinking = checkEatingDrinking(aurasByID, aurasByName)

    local suggestions = {}
    local addedItemIDs = {}
    local function addSuggestion(itemID, color, reasonTag)
        if addedItemIDs[itemID] then return end
        addedItemIDs[itemID] = true
        suggestions[#suggestions + 1] = {
            kind = "item",
            itemID = itemID,
            color = color or "Utility",
            highlightBags = true,
            source = reasonTag,
        }
    end

    -- 1) Food (HP) and Drink/Water (Mana) — out of combat, standing still, not mounted.
    --    Both can glow simultaneously!
    --    When HP/Mana are Blizzard secret values (nil) even out of combat, fall back to:
    --      (a) post-combat reminder window (PLAYER_REGEN_ENABLED, 20s), and
    --      (b) open bag out of combat while standing still.
    if not env.inCombat and not env.moving and not env.mounted then
        local tNow = now()
        local foodNeeded
        if env.hpPct ~= nil then
            foodNeeded = env.hpPct < (cfg.foodThreshold or 50)
        else
            foodNeeded = (tNow < state.postCombatFoodUntil) or env.bagOpen
        end

        if cfg.foodEnabled and not eating and foodNeeded then
            local bestFood
            for _, entry in pairs(owned) do
                if entry.meta and entry.meta.isFood and itemIsEligibleToShow(entry, env.bagOpen) then
                    if isBetterCandidate(entry, bestFood, "foodTier", "foodRestore") then
                        bestFood = entry
                    end
                end
            end
            if bestFood then addSuggestion(bestFood.itemID, "Defensive", "food") end
        end

        local drinkNeeded
        if env.manaPct ~= nil then
            drinkNeeded = env.manaPct < (cfg.drinkThreshold or 50)
        else
            drinkNeeded = (tNow < state.postCombatDrinkUntil) or env.bagOpen
        end

        if cfg.drinkEnabled and env.hasMana and not drinking and drinkNeeded then
            local bestDrink
            for _, entry in pairs(owned) do
                if entry.meta and entry.meta.isDrink and itemIsEligibleToShow(entry, env.bagOpen) then
                    if isBetterCandidate(entry, bestDrink, "drinkTier", "drinkRestore") then
                        bestDrink = entry
                    end
                end
            end
            if bestDrink then addSuggestion(bestDrink.itemID, "Utility", "drink") end
        end
    end

    -- While actively eating or drinking out of combat, do not suggest bonus potions or custom rules
    -- that would interrupt resting (only the missing Food/Drink partner above may stay lit).
    if not env.inCombat and (eating or drinking) then
        return suggestions
    end

    -- 2) Combat Potions (Healing Potion / Healthstone & Mana Potion) — in combat, auto-picks best usable
    if env.inCombat and not env.mounted then
        if cfg.healPotEnabled and env.hpPct ~= nil and env.hpPct < (cfg.healPotThreshold or 40) then
            local bestHealPot
            for _, entry in pairs(owned) do
                if entry.meta and entry.meta.isHealPot and itemIsEligibleToShow(entry, env.bagOpen) then
                    if isBetterCandidate(entry, bestHealPot, "healPotTier", "healPotRestore") then
                        bestHealPot = entry
                    end
                end
            end
            if bestHealPot then addSuggestion(bestHealPot.itemID, "Defensive", "heal_pot") end
        end

        if cfg.manaPotEnabled and env.hasMana
            and env.manaPct ~= nil and env.manaPct < (cfg.manaPotThreshold or 35) then
            local bestManaPot
            for _, entry in pairs(owned) do
                if entry.meta and entry.meta.isManaPot and itemIsEligibleToShow(entry, env.bagOpen) then
                    if isBetterCandidate(entry, bestManaPot, "manaPotTier", "manaPotRestore") then
                        bestManaPot = entry
                    end
                end
            end
            if bestManaPot then addSuggestion(bestManaPot.itemID, "Utility", "mana_pot") end
        end
    end

    -- 3) Long-duration (5+ min) bonus potions, elixirs, flasks and scrolls
    if cfg.bonusEnabled and not env.mounted then
        local bestByCategory = {}
        for _, entry in pairs(owned) do
            local lb = entry.meta and entry.meta.longBuff
            if lb and itemIsEligibleToShow(entry, env.bagOpen) then
                local groupAllowed = (lb.group == "scroll" and cfg.bonusScrolls ~= false)
                    or (lb.group ~= "scroll" and cfg.bonusElixirs ~= false)
                if groupAllowed and not isLongBuffActive(entry, aurasByID, aurasByName) then
                    local curBest = bestByCategory[lb.category]
                    if isBetterCandidate(entry, curBest, "longBuffTier", nil) then
                        bestByCategory[lb.category] = entry
                    end
                end
            end
        end
        for cat, entry in pairs(bestByCategory) do
            addSuggestion(entry.itemID, "Utility", "bonus:" .. tostring(cat))
        end
    end

    -- 4) User-configured situational rules ([+] button)
    for _, rule in ipairs(cfg.customRules or {}) do
        local itemID = tonumber(rule.itemID)
        local entry = itemID and owned[itemID] or nil
        if entry and itemIsEligibleToShow(entry, env.bagOpen) then
            local okRule = evaluateCustomRule(rule, env)
            if okRule then
                -- Skip if this rule's item already has its own buff active
                local alreadyBuffed = false
                if entry.meta and entry.meta.spellID and aurasByID[entry.meta.spellID] then
                    alreadyBuffed = true
                elseif entry.meta and entry.meta.longBuff and isLongBuffActive(entry, aurasByID, aurasByName) then
                    alreadyBuffed = true
                end
                if not alreadyBuffed then
                    addSuggestion(itemID, "AoE", "rule:" .. tostring(rule.id))
                end
            end
        end
    end

    return suggestions
end

-- ---------------------------------------------------------------------------
-- Event tracking: immediate stop on cast/use, spell triggers, bag changes
-- ---------------------------------------------------------------------------
local tracker = CreateFrame("Frame", "CFA_ConsumablesTracker", UIParent)
tracker:RegisterEvent("BAG_UPDATE_DELAYED")
tracker:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterUnitEvent("UNIT_AURA", "player")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
tracker:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

tracker:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "UNIT_AURA" then
        invalidateAuraCache()
        return
    elseif event == "BAG_UPDATE_DELAYED" or event == "ACTIONBAR_SLOT_CHANGED" then
        bagScanCache = nil
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        bagScanCache = nil
        invalidateAuraCache()
        state.eatingBeliefUntil = 0
        state.drinkingBeliefUntil = 0
        state.postCombatFoodUntil = 0
        state.postCombatDrinkUntil = 0
        wipe(state.usedItemUntil)
        wipe(state.usedCategoryUntil)
        wipe(state.lastCastByID)
        wipe(state.lastCastByName)
    elseif event == "PLAYER_REGEN_DISABLED" then
        invalidateAuraCache()
        state.eatingBeliefUntil = 0
        state.drinkingBeliefUntil = 0
        state.postCombatFoodUntil = 0
        state.postCombatDrinkUntil = 0
    elseif event == "PLAYER_REGEN_ENABLED" then
        local untilT = now() + POST_COMBAT_WINDOW
        state.postCombatFoodUntil = untilT
        state.postCombatDrinkUntil = untilT
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_SENT" then
        local unit = arg1
        if unit ~= "player" then return end
        local rawSpellID = (event == "UNIT_SPELLCAST_SENT") and arg4 or arg3
        local spellID = safeNum(rawSpellID, nil)
        local spellName = spellID and addon.SpellName and addon.SpellName(spellID) or nil
        local normName = spellName and normalizeText(spellName) or nil
        local t = now()

        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if spellID then state.lastCastByID[spellID] = t end
            if normName and normName ~= "" then state.lastCastByName[normName] = t end
            state.lastCastSummary = tostring(spellName or spellID)
        end

        if spellID and (FOOD_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID] or knownFoodSpellIDs[spellID]) then
            state.eatingBeliefUntil = t + 3
            state.postCombatFoodUntil = 0
        end
        if spellID and (DRINK_AURA_IDS[spellID] or HYBRID_FOOD_DRINK_IDS[spellID] or knownDrinkSpellIDs[spellID]) then
            state.drinkingBeliefUntil = t + 3
            state.postCombatDrinkUntil = 0
        end
        if normName and normName ~= "" then
            if nameLooksLikeFood(normName) then
                state.eatingBeliefUntil = t + 3
                state.postCombatFoodUntil = 0
            end
            if nameLooksLikeDrink(normName) then
                state.drinkingBeliefUntil = t + 3
                state.postCombatDrinkUntil = 0
            end
        end

        -- Match against owned items' spellIDs to stop their glow immediately & clear triggered rules
        local owned = bagScanCache
        if owned and spellID then
            for itemID, entry in pairs(owned) do
                if entry.meta and entry.meta.spellID == spellID then
                    state.usedItemUntil[itemID] = t + 1.5
                    if entry.meta.isFood then
                        state.eatingBeliefUntil = t + 3
                        state.postCombatFoodUntil = 0
                    end
                    if entry.meta.isDrink then
                        state.drinkingBeliefUntil = t + 3
                        state.postCombatDrinkUntil = 0
                    end
                    if entry.meta.longBuff then
                        state.usedCategoryUntil[entry.meta.longBuff.category] = t + math.min(entry.meta.longBuff.duration or 300, 3600)
                    end
                    -- If this item was triggered by a spell rule, consume the trigger
                    local cfg = getConfig(false)
                    if cfg then
                        for _, rule in ipairs(cfg.customRules or {}) do
                            if tonumber(rule.itemID) == itemID and rule.triggerSpellID then
                                state.lastCastByID[tonumber(rule.triggerSpellID)] = nil
                                if safeStr(rule.triggerSpellName) then
                                    state.lastCastByName[normalizeText(rule.triggerSpellName)] = nil
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Chat diagnostic command: /cfa items (and /cfa food, /cfa consumables)
-- ---------------------------------------------------------------------------
function Consumables.DebugDump()
    local function P(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("|cff44ddff[CFA items]|r " .. table.concat(parts, " "))
    end

    local cfg = getConfig(true)
    local env = buildConsumableEnv()
    local owned = scanOwnedBagItems(true)
    local aurasByID, aurasByName, auraReadable = collectPlayerAuras()
    local eating, drinking = checkEatingDrinking(aurasByID, aurasByName)

    local openBags = (addon.Visuals and addon.Visuals.GetOpenBagSources and addon.Visuals.GetOpenBagSources()) or {}

    P("===== DIAGNÓSTICO FOOD, POTIONS & ITENS =====")
    P(string.format("combat=%s moving=%s mounted=%s bagOpen=%s (%s) hp=%s mana=%s hasMana=%s lvl=%d",
        tostring(env.inCombat), tostring(env.moving), tostring(env.mounted), tostring(env.bagOpen),
        (#openBags > 0) and table.concat(openBags, ",") or "nenhuma",
        env.hpPct and string.format("%.1f%%", env.hpPct) or "nil",
        env.manaPct and string.format("%.1f%%", env.manaPct) or "nil",
        tostring(env.hasMana), playerLevel()))
    local tNow = now()
    local pcFood = math.max(0, state.postCombatFoodUntil - tNow)
    local pcDrink = math.max(0, state.postCombatDrinkUntil - tNow)
    P(string.format("eating=%s drinking=%s aurasReadable=%s swimming=%s breath=%s postCombat=F:%.1fs/D:%.1fs lastCast=%s",
        tostring(eating), tostring(drinking), tostring(auraReadable),
        tostring(env.swimming), env.breathPct and string.format("%.1f%%", env.breathPct) or "nil",
        pcFood, pcDrink,
        tostring(state.lastCastSummary)))
    P(string.format("config: food=%s(<%d%%) drink=%s(<%d%%) healPot=%s(<%d%%) manaPot=%s(<%d%%) bonus=%s(elix=%s,scroll=%s) customRules=%d",
        tostring(cfg.foodEnabled), cfg.foodThreshold or 50,
        tostring(cfg.drinkEnabled), cfg.drinkThreshold or 50,
        tostring(cfg.healPotEnabled), cfg.healPotThreshold or 40,
        tostring(cfg.manaPotEnabled), cfg.manaPotThreshold or 35,
        tostring(cfg.bonusEnabled), tostring(cfg.bonusElixirs), tostring(cfg.bonusScrolls),
        #(cfg.customRules or {})))

    local pLvl = playerLevel()
    local bestFood, bestDrink, bestHealPot, bestManaPot
    local bonusList, allConsumables = {}, {}
    for _, entry in pairs(owned) do
        local m = entry.meta
        if m then
            if m.classID == 0 or m.isFood or m.isDrink or m.isHealPot or m.isManaPot or m.longBuff then
                allConsumables[#allConsumables + 1] = entry
            end
            local lvlOK = (m.minLevel or 0) <= pLvl
            if lvlOK and m.isFood and isBetterCandidate(entry, bestFood, "foodTier", "foodRestore") then bestFood = entry end
            if lvlOK and m.isDrink and isBetterCandidate(entry, bestDrink, "drinkTier", "drinkRestore") then bestDrink = entry end
            if lvlOK and m.isHealPot and isBetterCandidate(entry, bestHealPot, "healPotTier", "healPotRestore") then bestHealPot = entry end
            if lvlOK and m.isManaPot and isBetterCandidate(entry, bestManaPot, "manaPotTier", "manaPotRestore") then bestManaPot = entry end
            if m.longBuff then bonusList[#bonusList + 1] = entry end
        end
    end

    local function countButtons(itemID)
        local bagBtns = (addon.Visuals and addon.Visuals.FindBagItemButtons and addon.Visuals.FindBagItemButtons(itemID)) or {}
        local barBtns = (addon.Visuals and addon.Visuals.FindItemButtons and addon.Visuals.FindItemButtons(itemID)) or {}
        return #bagBtns, #barBtns
    end

    local function dumpBest(label, entry, tierField, restoreField)
        if not entry then
            P("  " .. label .. ": nenhum encontrado na bolsa (usável no seu nível)")
            return
        end
        local cd, cdSrc = isItemOnCooldown(entry.itemID, entry.bag, entry.slot)
        local nBag, nBar = countButtons(entry.itemID)
        P(string.format("  %s: [%d] %s (tier=%d valor=%dc restore=%d lvl=%d bag=%d:%d bagBtns=%d barBtns=%d cd=%s/%s)",
            label, entry.itemID, entry.meta.name,
            entry.meta[tierField] or 0, entry.meta.sellPrice, entry.meta[restoreField] or 0,
            entry.meta.minLevel, entry.bag, entry.slot, nBag, nBar, tostring(cd), tostring(cdSrc)))
    end

    dumpBest("Melhor Comida", bestFood, "foodTier", "foodRestore")
    dumpBest("Melhor Bebida", bestDrink, "drinkTier", "drinkRestore")
    dumpBest("Melhor Poção de Vida", bestHealPot, "healPotTier", "healPotRestore")
    dumpBest("Melhor Poção de Mana", bestManaPot, "manaPotTier", "manaPotRestore")

    P("  Poções/Pergaminhos 5+ min na bolsa:", #bonusList)
    for _, entry in ipairs(bonusList) do
        local lb = entry.meta.longBuff
        local active = isLongBuffActive(entry, aurasByID, aurasByName)
        local cd = isItemOnCooldown(entry.itemID, entry.bag, entry.slot)
        local nBag, nBar = countButtons(entry.itemID)
        P(string.format("    [%d] %s | cat=%s grp=%s tier=%d dur=%ds valor=%dc buffAtivo=%s bagBtns=%d barBtns=%d cd=%s",
            entry.itemID, entry.meta.name, lb.category, lb.group, lb.tier or 0, lb.duration,
            entry.meta.sellPrice, tostring(active), nBag, nBar, tostring(cd)))
    end

    P("  Regras personalizadas:", #(cfg.customRules or {}))
    for _, rule in ipairs(cfg.customRules or {}) do
        local okR, why = evaluateCustomRule(rule, env)
        local itemID = tonumber(rule.itemID)
        local entry = itemID and owned[itemID]
        local nm = entry and entry.meta and entry.meta.name or tostring(itemID)
        local cd = entry and isItemOnCooldown(itemID, entry.bag, entry.slot) or false
        P(string.format("    #%s [%s] %s | en=%s pass=%s (%s) inBag=%s onBar=%s cd=%s trig=%s",
            tostring(rule.id), tostring(itemID or "-"), nm, tostring(rule.enabled ~= false),
            tostring(okR), tostring(why), tostring(entry ~= nil), tostring(entry and entry.onBar or false),
            tostring(cd), tostring(rule.triggerSpellName or rule.triggerSpellID or "-")))
    end

    local activeSugs = Consumables.GetSuggestions()
    P("  Sugestões ativas agora:", #activeSugs)
    for _, s in ipairs(activeSugs) do
        local nBag, nBar = countButtons(s.itemID)
        P(string.format("    -> itemID=%d color=%s source=%s bagBtns=%d barBtns=%d",
            s.itemID, tostring(s.color), tostring(s.source), nBag, nBar))
    end

    table.sort(allConsumables, function(a, b) return a.itemID < b.itemID end)
    P("  Todos consumíveis (classID=0) escaneados na bolsa:", #allConsumables)
    for _, entry in ipairs(allConsumables) do
        local m = entry.meta
        local flags = {}
        if m.isFood then flags[#flags + 1] = "F" end
        if m.isDrink then flags[#flags + 1] = "D" end
        if m.isHealPot then flags[#flags + 1] = "HP" end
        if m.isManaPot then flags[#flags + 1] = "MP" end
        if m.longBuff then flags[#flags + 1] = "LB:" .. tostring(m.longBuff.category) end
        P(string.format("    [%d] %s | sub=%d(%s) lvl=%d price=%dc spell=%s(%s) flags=%s tipLen=%d",
            entry.itemID, m.name, m.subClassID, m.itemSubType, m.minLevel, m.sellPrice,
            tostring(m.spellName or "-"), tostring(m.spellID or "-"),
            (#flags > 0) and table.concat(flags, ",") or "NONE", m.tipLen or 0))
    end
    P("===== FIM DIAGNÓSTICO =====")
end

-- ---------------------------------------------------------------------------
-- Options Tab UI: "Food, Potions, Itens"
-- ---------------------------------------------------------------------------
local function collectKnownPlayerSpells()
    local spells = {}
    local seen = {}
    local function addSpell(id, name)
        id = safeNum(id, nil)
        name = safeStr(name)
        if not name and id and addon.SpellName then name = addon.SpellName(id) end
        if not name then return end
        local key = normalizeText(name)
        if key == "" or seen[key] then return end
        seen[key] = true
        local tex = QUESTION_MARK
        if id and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
            local ok, t = pcall(C_Spell.GetSpellTexture, id)
            if ok and t then tex = t end
        elseif id and type(GetSpellTexture) == "function" then
            local ok, t = pcall(GetSpellTexture, id)
            if ok and t then tex = t end
        end
        spells[#spells + 1] = { spellID = id, name = name, texture = tex }
    end

    -- 1) Action bar spells (most relevant abilities the player actually uses)
    if type(GetActionInfo) == "function" then
        for slot = 1, 180 do
            local ok, actionType, id = safeCall(GetActionInfo, slot)
            if ok and actionType == "spell" and type(id) == "number" then
                addSpell(id)
            end
        end
    end

    -- 2) Active class module rotation spells
    local mod = addon.activeModule
    if mod and type(mod.RotationSpecs) == "table" then
        for _, spec in pairs(mod.RotationSpecs) do
            if type(spec) == "table" and type(spec.nodes) == "table" then
                for _, node in ipairs(spec.nodes) do
                    if type(node.spellID) == "number" then
                        local knownID = (addon.Compat and addon.Compat.HighestKnownSpellID
                            and addon.Compat.HighestKnownSpellID(node.spellID)) or node.spellID
                        if not (addon.Compat and addon.Compat.SpellKnown) or addon.Compat.SpellKnown(knownID) then
                            addSpell(knownID)
                        end
                    end
                end
            end
        end
    end

    -- 3) Spellbook scan fallback
    if C_SpellBook and type(C_SpellBook.GetSpellBookItemInfo) == "function" then
        for i = 1, 200 do
            local ok, info = safeCall(C_SpellBook.GetSpellBookItemInfo, i, "spell")
            if ok and type(info) == "table" and info.name then
                addSpell(info.spellID or info.actionID or info.id, info.name)
            end
        end
    end

    table.sort(spells, function(a, b) return a.name:lower() < b.name:lower() end)
    return spells
end

local function collectUsableBagItems(selectedItemID)
    local owned = scanOwnedBagItems(true)
    local list = {}
    local seen = {}
    for itemID, entry in pairs(owned) do
        local m = entry.meta
        if m and (m.usable or m.classID == 0 or itemID == selectedItemID) then
            seen[itemID] = true
            list[#list + 1] = {
                itemID = itemID,
                name = m.name or ("Item " .. tostring(itemID)),
                texture = m.texture or QUESTION_MARK,
            }
        end
    end
    if selectedItemID and not seen[selectedItemID] then
        local m = inspectItem(selectedItemID)
        list[#list + 1] = {
            itemID = selectedItemID,
            name = (m and m.name or ("Item " .. tostring(selectedItemID))) .. " (" .. loc("cons_not_in_bag", "fora da bolsa") .. ")",
            texture = m and m.texture or QUESTION_MARK,
        }
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function formatRuleSummary(rule)
    local parts = {}
    local conds = type(rule.conditions) == "table" and rule.conditions or {}
    for _, axis in ipairs(RULE_AXES) do
        local v = tonumber(conds[axis.key]) or 0
        if v ~= 0 then
            for _, opt in ipairs(axis.options) do
                if opt[1] == v then
                    local axisTitle = loc(axis.labelKey, axis.fallback):gsub("^%d+%.%s*", "")
                    parts[#parts + 1] = axisTitle .. ": " .. loc(opt[2], opt[3])
                    break
                end
            end
        end
    end
    if rule.triggerSpellID or safeStr(rule.triggerSpellName) then
        local spName = safeStr(rule.triggerSpellName)
            or (rule.triggerSpellID and addon.SpellName and addon.SpellName(rule.triggerSpellID))
            or tostring(rule.triggerSpellID)
        parts[#parts + 1] = loc("cons_after_spell_prefix", "Após habilidade: ") .. tostring(spName)
    end
    if #parts == 0 then
        return loc("rot_no_condition", "- sem condições -")
    end
    return loc("rot_conditions_prefix", "Condições: ") .. table.concat(parts, " · ")
end

local function buildConsumablesTab(host)
    local parent, setContentHeight = addon.Options.CreateScrollableTab(host)
    local cfg = getConfig(true)
    local dynamicRows = {}

    local function makeHeader(yPos, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yPos)
        fs:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        fs:SetText(text)
        return yPos - 22
    end

    local function makeCompactSlider(anchorFrame, minV, maxV, initial, onChange)
        local slider = CreateFrame("Slider", nil, parent)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(5)
        pcall(function() slider:SetObeyStepOnDrag(true) end)
        slider:SetWidth(118)
        slider:SetHeight(16)
        slider:SetPoint("LEFT", anchorFrame, "RIGHT", 8, 0)

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture("Interface\\Buttons\\WHITE8X8")
        track:SetVertexColor(0.20, 0.20, 0.20, 0.95)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        track:SetHeight(6)

        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetWidth(10)
            thumb:SetHeight(16)
            thumb:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        end

        local valFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valFS:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        valFS:SetTextColor(1, 0.9, 0.6, 1)

        slider:SetScript("OnValueChanged", function(_, v)
            local rounded = math.floor((v + 2.5) / 5) * 5
            rounded = math.max(minV, math.min(maxV, rounded))
            onChange(rounded)
            valFS:SetText(tostring(rounded) .. "%")
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue(math.max(minV, math.min(maxV, self:GetValue() + (delta > 0 and 5 or -5))))
        end)
        slider:SetValue(initial)
        return slider
    end

    local function makeThresholdRow(yPos, labelText, checked, threshold, onToggle, onThreshold)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yPos)
        cb:SetChecked(checked and true or false)
        cb:SetScript("OnClick", function(self) onToggle(self:GetChecked() == true) end)

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetWidth(150)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(labelText)

        makeCompactSlider(lbl, 5, 95, threshold or 50, onThreshold)
        return yPos - 28
    end

    local y = -8
    -- Section 1: Food & Drink (HP / Mana)
    y = makeHeader(y, loc("cons_section_food_drink", "Comida e Água (fora de combate, parado)"))

    y = makeThresholdRow(y, loc("cons_food_enable", "Recomendar Comida (Vida)"),
        cfg.foodEnabled, cfg.foodThreshold,
        function(v) cfg.foodEnabled = v end,
        function(v) cfg.foodThreshold = v end)

    if Consumables.PlayerHasMana() then
        y = makeThresholdRow(y, loc("cons_drink_enable", "Recomendar Água (Mana)"),
            cfg.drinkEnabled, cfg.drinkThreshold,
            function(v) cfg.drinkEnabled = v end,
            function(v) cfg.drinkThreshold = v end)
    end

    local fdHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fdHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    fdHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    fdHint:SetJustifyH("LEFT")
    fdHint:SetWordWrap(true)
    fdHint:SetText(loc("cons_food_drink_hint",
        "Bolsa aberta: destaca o melhor item usável na bolsa (e na barra se estiver nela). Bolsa fechada: destaca na barra. Comida e água podem brilhar juntas e param ao comer/beber."))
    y = y - 34

    -- Section 2: Combat Potions (Healing / Healthstone & Mana) — automatic best-item ranking
    y = makeHeader(y, loc("cons_section_combat_pots", "Poções de Combate (em combate — escolhe a melhor)"))

    y = makeThresholdRow(y, loc("cons_heal_pot_enable", "Recomendar Poção de Vida"),
        cfg.healPotEnabled, cfg.healPotThreshold,
        function(v) cfg.healPotEnabled = v end,
        function(v) cfg.healPotThreshold = v end)

    if Consumables.PlayerHasMana() then
        y = makeThresholdRow(y, loc("cons_mana_pot_enable", "Recomendar Poção de Mana"),
            cfg.manaPotEnabled, cfg.manaPotThreshold,
            function(v) cfg.manaPotEnabled = v end,
            function(v) cfg.manaPotThreshold = v end)
    end

    local cpHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cpHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    cpHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    cpHint:SetJustifyH("LEFT")
    cpHint:SetWordWrap(true)
    cpHint:SetText(loc("cons_combat_pots_hint",
        "Em combate, destaca automaticamente a poção de vida/mana (ou pedra de vida) mais valiosa da bolsa/barra quando cair abaixo do % escolhido."))
    y = y - 30

    -- Section 3: Long-duration (5+ min) bonus potions, elixirs and scrolls
    y = makeHeader(y, loc("cons_section_bonus", "Poções de bônus e pergaminhos (5+ min)"))

    local function makeSimpleCheck(yPos, indent, labelText, checked, onToggle)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + indent, yPos)
        cb:SetChecked(checked and true or false)
        cb:SetScript("OnClick", function(self) onToggle(self:GetChecked() == true) end)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:SetText(labelText)
        return yPos - 24
    end

    y = makeSimpleCheck(y, 0, loc("cons_bonus_enable", "Recomendar poções de bônus / pergaminhos faltantes"),
        cfg.bonusEnabled, function(v) cfg.bonusEnabled = v end)
    y = makeSimpleCheck(y, 18, loc("cons_bonus_elixirs", "Elixires, frascos e poções de bônus (5+ min)"),
        cfg.bonusElixirs ~= false, function(v) cfg.bonusElixirs = v end)
    y = makeSimpleCheck(y, 18, loc("cons_bonus_scrolls", "Pergaminhos de atributos/armadura (30 min)"),
        cfg.bonusScrolls ~= false, function(v) cfg.bonusScrolls = v end)

    local bonusHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bonusHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    bonusHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    bonusHint:SetJustifyH("LEFT")
    bonusHint:SetWordWrap(true)
    bonusHint:SetText(loc("cons_bonus_hint",
        "Compara a bolsa com seus buffs ativos e destaca a poção/pergaminho mais caro de cada tipo faltante."))
    y = y - 28

    -- Section 3: Custom situational items & short-duration potions ([+] button)
    y = makeHeader(y, loc("cons_section_custom", "Poções situacionais e itens usáveis"))

    local addRuleBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addRuleBtn:SetSize(165, 22)
    addRuleBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    addRuleBtn:SetText(loc("cons_add_rule", "+ Adicionar item / regra"))
    y = y - 28

    local rulesStartY = y
    local rebuildCustomRows

    local function showItemChoices(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        picker(anchor, loc("equip_select_item", "Selecionar item"), function()
            local choices = {
                { header = loc("cons_bag_items_header", "Itens usáveis na bolsa") },
                {
                    label = loc("equip_no_item", "(nenhum item selecionado)"),
                    checked = not rule.itemID,
                    action = function() rule.itemID = nil end,
                },
            }
            for _, item in ipairs(collectUsableBagItems(tonumber(rule.itemID))) do
                local choice = item
                choices[#choices + 1] = {
                    label = string.format("|T%s:16:16|t %s", choice.texture or QUESTION_MARK, choice.name),
                    checked = tonumber(rule.itemID) == choice.itemID,
                    action = function() rule.itemID = choice.itemID end,
                }
            end
            return choices
        end, function() rebuildCustomRows() end)
    end

    local function showTriggerSpellChoices(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        picker(anchor, loc("cons_pick_spell", "Habilidade gatilho"), function()
            local choices = {
                { header = loc("cons_pick_spell_header", "Disparar após usar habilidade") },
                {
                    label = loc("cons_no_trigger_spell", "(nenhuma habilidade gatilho)"),
                    checked = not rule.triggerSpellID and not safeStr(rule.triggerSpellName),
                    action = function()
                        rule.triggerSpellID = nil
                        rule.triggerSpellName = nil
                    end,
                },
            }
            for _, sp in ipairs(collectKnownPlayerSpells()) do
                local spellChoice = sp
                choices[#choices + 1] = {
                    label = string.format("|T%s:16:16|t %s", spellChoice.texture or QUESTION_MARK, spellChoice.name),
                    checked = (rule.triggerSpellID ~= nil and rule.triggerSpellID == spellChoice.spellID)
                        or (safeStr(rule.triggerSpellName) == spellChoice.name),
                    action = function()
                        rule.triggerSpellID = spellChoice.spellID
                        rule.triggerSpellName = spellChoice.name
                        rule.triggerWindow = rule.triggerWindow or 8
                    end,
                }
            end
            return choices
        end, function() rebuildCustomRows() end)
    end

    local function showAddRuleCondition(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        local hasMana = Consumables.PlayerHasMana()
        picker(anchor, loc("rot_add_condition", "Adicionar condição"), function()
            local items = {}
            for _, axis in ipairs(RULE_AXES) do
                if not axis.manaOnly or hasMana then
                    local axisKey = axis.key
                    items[#items + 1] = { header = loc(axis.labelKey, axis.fallback) }
                    for _, opt in ipairs(axis.options) do
                        local val, lk, fb = opt[1], opt[2], opt[3]
                        local cur = type(rule.conditions) == "table" and tonumber(rule.conditions[axisKey]) or 0
                        items[#items + 1] = {
                            label = loc(lk, fb),
                            checked = (cur == val),
                            action = function()
                                rule.conditions = rule.conditions or {}
                                if tonumber(rule.conditions[axisKey]) == val then
                                    rule.conditions[axisKey] = nil
                                else
                                    rule.conditions[axisKey] = val
                                end
                            end,
                        }
                    end
                end
            end
            items[#items + 1] = { header = loc("cons_axis_spell_trigger", "7. Gatilho de habilidade") }
            items[#items + 1] = {
                label = loc("cons_choose_trigger_spell", "Escolher habilidade X..."),
                checked = (rule.triggerSpellID ~= nil or safeStr(rule.triggerSpellName) ~= nil),
                action = function()
                    if C_Timer and type(C_Timer.After) == "function" then
                        C_Timer.After(0, function() showTriggerSpellChoices(anchor, rule) end)
                    else
                        showTriggerSpellChoices(anchor, rule)
                    end
                end,
            }
            items[#items + 1] = { header = "------------------------" }
            items[#items + 1] = {
                label = loc("rot_clear_all", "Remover todas as condições"),
                checked = false,
                action = function()
                    rule.conditions = {}
                    rule.triggerSpellID = nil
                    rule.triggerSpellName = nil
                end,
            }
            return items
        end, function() rebuildCustomRows() end)
    end

    local function showRemoveRuleCondition(anchor, rule)
        local picker = addon.RotationEditor and addon.RotationEditor.ShowPicker
        if not picker then return end
        picker(anchor, loc("rot_remove_condition", "Remover condição"), function()
            local items = {}
            local any = false
            local conds = type(rule.conditions) == "table" and rule.conditions or {}
            for _, axis in ipairs(RULE_AXES) do
                local v = tonumber(conds[axis.key]) or 0
                if v ~= 0 then
                    local axisKey = axis.key
                    local optLabel = tostring(v)
                    for _, opt in ipairs(axis.options) do
                        if opt[1] == v then optLabel = loc(opt[2], opt[3]); break end
                    end
                    local axisName = loc(axis.labelKey, axis.fallback):gsub("^%d+%.%s*", "")
                    items[#items + 1] = {
                        label = axisName .. ": " .. optLabel,
                        action = function()
                            if type(rule.conditions) == "table" then rule.conditions[axisKey] = nil end
                        end,
                    }
                    any = true
                end
            end
            if rule.triggerSpellID or safeStr(rule.triggerSpellName) then
                local spName = safeStr(rule.triggerSpellName) or tostring(rule.triggerSpellID)
                items[#items + 1] = {
                    label = loc("cons_after_spell_prefix", "Após habilidade: ") .. spName,
                    action = function()
                        rule.triggerSpellID = nil
                        rule.triggerSpellName = nil
                    end,
                }
                any = true
            end
            if not any then
                items[#items + 1] = { header = loc("rot_none_active", "(nenhuma condição ativa)") }
            end
            return items
        end, function() rebuildCustomRows() end)
    end

    rebuildCustomRows = function()
        for _, r in ipairs(dynamicRows) do
            r:Hide()
            r:SetParent(nil)
        end
        dynamicRows = {}

        local ry = rulesStartY
        if #(cfg.customRules or {}) == 0 then
            local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, ry)
            empty:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, ry)
            empty:SetJustifyH("LEFT")
            empty:SetWordWrap(true)
            empty:SetText(loc("cons_custom_empty",
                "Nenhuma regra criada. Clique em '+ Adicionar item / regra' para configurar poções de vida/mana, respiração aquática, bombas de engenharia ou itens após usar uma habilidade."))
            dynamicRows[1] = empty
            setContentHeight(-ry + 48)
            return
        end

        for idx, rule in ipairs(cfg.customRules) do
            local currentRule = rule
            local currentIdx = idx
            local row = CreateFrame("Frame", nil, parent)
            row:SetHeight(48)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, ry)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, ry)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)
            bg:SetAllPoints()

            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            cb:SetChecked(currentRule.enabled ~= false)
            cb:SetScript("OnClick", function(self)
                currentRule.enabled = (self:GetChecked() == true)
            end)

            local itemBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            itemBtn:SetSize(166, 22)
            itemBtn:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            local itemIcon = itemBtn:CreateTexture(nil, "ARTWORK")
            itemIcon:SetSize(16, 16)
            itemIcon:SetPoint("LEFT", itemBtn, "LEFT", 4, 0)
            local itemMeta = currentRule.itemID and inspectItem(tonumber(currentRule.itemID)) or nil
            itemIcon:SetTexture(itemMeta and itemMeta.texture or QUESTION_MARK)
            local itemText = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", itemIcon, "RIGHT", 4, 0)
            itemText:SetPoint("RIGHT", itemBtn, "RIGHT", -4, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(itemMeta and itemMeta.name or loc("equip_select_item", "Selecionar item"))
            itemBtn:SetScript("OnClick", function(self) showItemChoices(self, currentRule) end)

            local addCondBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            addCondBtn:SetSize(24, 22)
            addCondBtn:SetPoint("LEFT", itemBtn, "RIGHT", 4, 0)
            addCondBtn:SetText("+")
            addCondBtn:SetScript("OnClick", function(self) showAddRuleCondition(self, currentRule) end)

            local remCondBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            remCondBtn:SetSize(24, 22)
            remCondBtn:SetPoint("LEFT", addCondBtn, "RIGHT", 3, 0)
            remCondBtn:SetText("-")
            remCondBtn:SetEnabled(ruleHasAnyCondition(currentRule))
            remCondBtn:SetScript("OnClick", function(self) showRemoveRuleCondition(self, currentRule) end)

            local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            delBtn:SetSize(24, 22)
            delBtn:SetPoint("LEFT", remCondBtn, "RIGHT", 4, 0)
            delBtn:SetText("X")
            delBtn:SetScript("OnClick", function()
                table.remove(cfg.customRules, currentIdx)
                if addon.RotationEditor and addon.RotationEditor.HidePicker then
                    addon.RotationEditor.HidePicker()
                end
                rebuildCustomRows()
            end)

            local summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            summary:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -26)
            summary:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -26)
            summary:SetJustifyH("LEFT")
            summary:SetText(formatRuleSummary(currentRule))

            dynamicRows[#dynamicRows + 1] = row
            ry = ry - 52
        end
        setContentHeight(-ry + 16)
    end

    addRuleBtn:SetScript("OnClick", function()
        local id = cfg.nextRuleId or (#cfg.customRules + 1)
        cfg.nextRuleId = id + 1
        cfg.customRules[#cfg.customRules + 1] = {
            id = id,
            enabled = true,
            itemID = nil,
            conditions = {},
            triggerSpellID = nil,
            triggerSpellName = nil,
            triggerWindow = 8,
        }
        rebuildCustomRows()
    end)

    rebuildCustomRows()
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("consumables", loc("opt_tab_consumables", "Food, Potions, Itens"), nil, buildConsumablesTab)
end
