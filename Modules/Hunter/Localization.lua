-- Combat Forever Assistant — Hunter module: Locales + core delegates.
-- Strings live in the core Locales.lua (ptBR primary). Only structural
-- wiring and back-compat aliases live here.
local moduleName, module = ...

local L = module.L
module.L = L
module.Localize = L

-- spellID -> localized name, rank stripped ("Fireball (Rank 3)" -> "Fireball")
local function stripRank(name)
    if type(name) ~= "string" then return nil end
    return (name:gsub("%s*%(.-%)%s*$", ""))
end

function module.SpellName(id)
    if not id then return nil end
    local name, rank = nil, nil
    if module.Compat and module.Compat.SpellInfoByID then
        name, rank = module.Compat.SpellInfoByID(id)
    end
    if not name and type(GetSpellInfo) == "function" then
        local ok, n, r = pcall(GetSpellInfo, id)
        if ok then name, rank = n, r end
    end
    if not name then return nil end
    return stripRank(name)
end

function module.ItemName(id)
    if module.Compat and module.Compat.SpellInfoByID then return end -- items not tracked here
    if type(GetItemInfo) == "function" then
        local ok, n = pcall(GetItemInfo, id)
        if ok then return n end
    end
    return nil
end

-- Convenience aliases used by the rotation scripts.
module.UnitTargetExistsAndAttackable = function()
    if not UnitExists("target") then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if ok and dead then return false end
    local ok2, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok2 then
        if _G.issecretvalue and issecretvalue(ok2) then return true end
        return false
    end
    if _G.issecretvalue and issecretvalue(canAttack) then return true end
    return canAttack and true or false
end

module.IsPvPTarget = function()
    if not (type(UnitIsPlayer) == "function" and UnitIsPlayer("target")) then return false end
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok or (_G.issecretvalue and issecretvalue(canAttack)) then return false end
    return canAttack and true or false
end
