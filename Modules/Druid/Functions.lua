-- Combat Forever Assistant — Druid module: formas, auras, crenças e helpers.
--
-- Lições do Hunter aplicadas aqui (H-0196/H-0197):
--   * CheckIfSpellCastable é MÉTODO (self implícito) -> chamar com ":".
--   * Auras em combate são SECRETAS -> nunca comparar valores secretos e
--     nunca indexar tabela com nome/ID secreto; usar CRENÇA do próprio cast.
--   * Crença é sempre honrada (nunca "descartada" quando a leitura falha).
--   * "Fail-open": leitura ilegível não pode matar a rotação.
local addonName, addon = ...
local module = addon.Druid

-- ---------------------------------------------------------------------------
-- Nomes de spell (rank removido) — mesma convenção do módulo do Hunter.
-- ---------------------------------------------------------------------------
local function stripRank(name)
    if type(name) ~= "string" then return nil end
    return (name:gsub("%s*%(.-%)%s*$", ""))
end

local function baseName(name)
    if type(name) ~= "string" then return nil end
    local s = stripRank(name)
    if not s then return nil end
    return s:lower()
end

function module.SpellName(id)
    if not id then return nil end
    local name = nil
    if addon.Compat and addon.Compat.SpellInfoByID then
        name = addon.Compat.SpellInfoByID(id)
    end
    if not name and type(GetSpellInfo) == "function" then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then name = n end
    end
    if type(name) ~= "string" then return nil end
    if _G.issecretvalue and issecretvalue(name) then return nil end
    return stripRank(name)
end

function module.SafeNumber(v, fallback)
    if type(v) ~= "number" then return fallback end
    if _G.issecretvalue and issecretvalue(v) then return fallback end
    return v
end

-- CheckCastable: FUNÇÃO COM PONTO (sem self). O Core chama
-- module.CheckCastable(z) — nunca module:CheckCastable(z).
function module.CheckCastable(z)
    if type(z) ~= "table" then return false end
    z.Unit = z.Unit or "target"
    -- CheckIfSpellCastable é método (self implícito): SEMPRE com ":".
    return addon:CheckIfSpellCastable(z)
end

-- ---------------------------------------------------------------------------
-- Alvos
-- ---------------------------------------------------------------------------
module.UnitTargetExistsAndAttackable = function()
    if not UnitExists("target") then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if ok and dead then return false end
    local ok2, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok2 then return true end -- fail-open
    if _G.issecretvalue and issecretvalue(canAttack) then return true end
    return canAttack and true or false
end

module.IsPvPTarget = function()
    if not (type(UnitIsPlayer) == "function" and UnitIsPlayer("target")) then return false end
    local ok, canAttack = pcall(UnitCanAttack, "player", "target")
    if not ok or (_G.issecretvalue and issecretvalue(canAttack)) then return false end
    return canAttack and true or false
end

module.IsTargetInterruptibleCasting = function(unit)
    unit = unit or "target"
    if addon.Compat and type(addon.Compat.IsInterruptibleCasting) == "function" then
        return addon.Compat.IsInterruptibleCasting(unit) and true or false
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Formas
--
-- O tipo de poder identifica Gato/Urso com alta confiabilidade:
--   RAGE (1)    -> Urso
--   ENERGIA (3) -> Gato
--   MANA (0)    -> conjurador ou Lua
-- GetShapeshiftForm, quando existe, confirma Lua e a saída da forma. Se as
-- leituras ficarem ilegíveis, a última forma conhecida é preservada; nunca
-- inventamos "conjurador" a partir de uma leitura desconhecida.
-- ---------------------------------------------------------------------------
local FORM_CASTER, FORM_CAT, FORM_BEAR, FORM_UNKNOWN = 0, 1, 2, 3
module.FORM_CASTER, module.FORM_CAT, module.FORM_BEAR = FORM_CASTER, FORM_CAT, FORM_BEAR
module.FORM_UNKNOWN = FORM_UNKNOWN

function module.GetPowerType()
    if type(UnitPowerType) ~= "function" then return nil end
    local ok, pt = pcall(UnitPowerType, "player")
    if not ok then return nil end
    if type(pt) ~= "number" then return nil end
    if _G.issecretvalue and issecretvalue(pt) then return nil end
    return pt
end

local function readShapeshiftForm()
    if type(GetShapeshiftForm) ~= "function" then return nil end
    local ok, form = pcall(GetShapeshiftForm)
    if not ok then return nil end
    if type(form) ~= "number" then return nil end
    if _G.issecretvalue and issecretvalue(form) then return nil end
    return form
end

module.ReadShapeshiftForm = readShapeshiftForm

local function clearMoonkinBelief()
    if module.Beliefs.player then
        module.Beliefs.player[24858] = nil
        module.Beliefs.player[24907] = nil
    end
    module.MoonkinFormActive = false
end

function module.GetForm()
    local shape = readShapeshiftForm()
    module.ShapeshiftForm = shape
    local pt = module.GetPowerType()

    if pt == 1 then
        module.LastKnownForm = FORM_BEAR
        clearMoonkinBelief()
        return FORM_BEAR
    end
    if pt == 3 then
        module.LastKnownForm = FORM_CAT
        clearMoonkinBelief()
        return FORM_CAT
    end
    if pt == 0 then
        module.LastKnownForm = FORM_CASTER
        return FORM_CASTER
    end

    if shape == 1 then
        module.LastKnownForm = FORM_CAT
        return FORM_CAT
    end
    if shape == 2 then
        module.LastKnownForm = FORM_BEAR
        return FORM_BEAR
    end
    if shape == 0 or shape == 3 then
        module.LastKnownForm = FORM_CASTER
        return FORM_CASTER
    end
    if module.LastKnownForm ~= nil then return module.LastKnownForm end
    return FORM_UNKNOWN
end

function module.OnShapeshiftFormChanged()
    local shape = readShapeshiftForm()
    module.ShapeshiftForm = shape
    local pt = module.GetPowerType()

    if shape == 3 then
        module.MoonkinFormActive = true
        return
    end
    if pt == 1 or pt == 3 or shape == 1 or shape == 2 then
        clearMoonkinBelief()
        return
    end

    -- Evento de saída sem API de shapeshift: a aura confiável decide. Estado
    -- ilegível não mantém uma crença antiga de Moonkin por uma hora.
    local auraState = module.AuraState("player", "HELPFUL", 24858)
    if auraState ~= true then
        local moonkinAura = module.AuraState("player", "HELPFUL", 24907)
        auraState = moonkinAura
    end
    module.MoonkinFormActive = (auraState == true)
    if not module.MoonkinFormActive then clearMoonkinBelief() end
end

function module.IsMoonkinFormActive()
    local shape = readShapeshiftForm()
    module.ShapeshiftForm = shape
    if shape == 3 then return true end

    local pt = module.GetPowerType()
    if pt == 1 or pt == 3 or shape == 1 or shape == 2 then return false end

    -- Crença do próprio cast permanece válida enquanto não houve evento de
    -- saída; a auditoria de forma limpa essa crença na troca de forma.
    local playerBeliefs = module.Beliefs and module.Beliefs.player
    local belief = playerBeliefs and (playerBeliefs[24858] or playerBeliefs[24907])
    if belief and belief.expires and GetTime() < belief.expires then return true end

    local state = module.AuraState("player", "HELPFUL", 24858)
    if state == true then return true end
    local moonkinAura = module.AuraState("player", "HELPFUL", 24907)
    if moonkinAura == true then return true end
    return module.MoonkinFormActive == true
end

function module.GetComboPoints()
    if type(UnitComboPoint) == "function" then
        local ok, n = pcall(UnitComboPoint, "player")
        if ok then
            local v = module.SafeNumber(n, nil)
            if v then return v end
        end
    end
    if type(UnitPower) == "function" then
        local ok, n = pcall(UnitPower, "player", 4)
        if ok then
            local v = module.SafeNumber(n, nil)
            if v then return v end
        end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Leitura de auras em TRÊS estados
--   true  = a aura está ativa
--   false = a aura NÃO está ativa (leitura confiável)
--   nil   = ilegível (o cliente mascarou os dados) -> use a crença
-- Nunca comparar nem indexar por valor secreto.
-- ---------------------------------------------------------------------------
function module.AuraState(unit, filter, wantID)
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function") then return nil end
    if not unit or not UnitExists(unit) then return false end

    -- A mesma spell pode aparecer em outro rank. O ID canônico continua
    -- reconhecendo toda a família conhecida pelo Core.
    local family = addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[wantID] or nil
    local familyIDs = {}
    local wantNames = {}
    local function addName(id)
        local name = baseName(module.SpellName(id))
        if name then wantNames[name] = true end
    end
    addName(wantID)
    if family then
        for _, id in ipairs(family) do
            familyIDs[id] = true
            addName(id)
        end
    end

    local sawUnknown = false
    for i = 1, 40 do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok then return nil end
        if not data or type(data) ~= "table" then break end
        local name = data.name
        local sid = data.spellId or data.spellID or data.auraSpellId or data.auraSpellID
        local nameSecret = (type(name) ~= "string") or (_G.issecretvalue and issecretvalue(name))
        local idSecret = (type(sid) ~= "number") or (_G.issecretvalue and issecretvalue(sid))
        if nameSecret and idSecret then
            sawUnknown = true
        else
            if not nameSecret then
                local normalized = baseName(name)
                if normalized and wantNames[normalized] then return true end
            end
            if not idSecret and (sid == wantID or familyIDs[sid]) then return true end
        end
    end
    if sawUnknown then return nil end
    return false
end

-- ---------------------------------------------------------------------------
-- Crenças de aura: acreditamos no que NÓS MESMOS conjuramos
-- (UNIT_SPELLCAST_SUCCEEDED). O nome (localizado) é a chave — assim o rank
-- da spell não importa. Durações generosas: errar para "ainda ativo" apenas
-- faz o addon não sugerir umaspell que já está no alvo.
-- ---------------------------------------------------------------------------
local BELIEF_SPECS = {
    { id = 1126,  en = "Mark of the Wild",    duration = 3600, unit = "player" }, -- auto-buff
    { id = 467,   en = "Thorns",              duration = 600,  unit = "player" }, -- auto-buff
    { id = 16689, en = "Nature's Grasp",      duration = 45,   unit = "player" }, -- auto-buff
    { id = 99,    en = "Demoralizing Roar",   duration = 30,   unit = "target" }, -- debuff no alvo
    { id = 1079,  en = "Rip",                 duration = 16,   unit = "target" },
    { id = 1822,  en = "Rake",                duration = 12,   unit = "target" },
    { id = 54802, en = "Lacerate",            duration = 12,   unit = "target" },
    { id = 9005,  en = "Pounce",              duration = 12,   unit = "target" },
    { id = 5570,  en = "Insect Swarm",        duration = 12,   unit = "target" },
    { id = 8921,  en = "Moonfire",            duration = 12,   unit = "target" },
    { id = 768,   en = "Cat Form",            duration = 3600, unit = "player" },
    { id = 5487,  en = "Bear Form",           duration = 3600, unit = "player" },
    { id = 24858, en = "Moonkin Form",        duration = 3600, unit = "player" },
}

module.Beliefs = { player = {}, target = {} }
module.BeliefSlot = 0
module.SuggestedUnits = module.SuggestedUnits or {}

local beliefIndex = nil
local function buildBeliefIndex()
    if beliefIndex then return beliefIndex end
    beliefIndex = { byName = {}, byID = {} }
    for _, spec in ipairs(BELIEF_SPECS) do
        local localName = module.SpellName(spec.id)
        local key = baseName(localName or spec.en)
        if key then beliefIndex.byName[key] = spec end
        beliefIndex.byID[spec.id] = spec
        local family = addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[spec.id]
        if family then
            for _, id in ipairs(family) do beliefIndex.byID[id] = spec end
        end
    end
    return beliefIndex
end

function module.OnTargetChanged()
    module.BeliefSlot = module.BeliefSlot + 1
    -- as crenças de debuff no alvo deixam de valer (novo alvo)
    local targetBeliefs = module.Beliefs and module.Beliefs.target
    if targetBeliefs then
        for _, b in pairs(targetBeliefs) do b.slot = nil end
    end
end

function module.RegisterCast(castName, spellID)
    local index = buildBeliefIndex()
    local spec
    if type(spellID) == "number" and not (_G.issecretvalue and issecretvalue(spellID)) then
        spec = index.byID[spellID]
    end

    -- O nome continua como fallback para clientes que não fornecem o ID.
    -- Nome secreto não pode ser comparado.
    if not spec then
        if type(castName) ~= "string" or castName == "" then return end
        if _G.issecretvalue and issecretvalue(castName) then return end
        local key = baseName(castName)
        if not key then return end
        spec = index.byName[key]
    end
    if not spec then return end

    local now = GetTime()
    local unit = spec.unit
    local suggested = module.SuggestedUnits and module.SuggestedUnits[spec.id]
    if suggested and suggested.expiresAt and now <= suggested.expiresAt then
        unit = suggested.unit or unit
    end

    module.Beliefs[unit] = module.Beliefs[unit] or {}
    local b = module.Beliefs[unit][spec.id] or {}
    b.expires = now + spec.duration
    b.unit = unit
    if unit == "target" then b.slot = module.BeliefSlot end
    module.Beliefs[unit][spec.id] = b
    if module.SuggestedUnits then module.SuggestedUnits[spec.id] = nil end
    -- o jogador usou o buff: zera a contagem de insistência
    if module.UtilitySuggestCount then module.UtilitySuggestCount[spec.id] = 0 end
    if module.UtilityFirstSeen then module.UtilityFirstSeen[spec.id] = nil end
    if module.UtilityIgnore then module.UtilityIgnore[spec.id] = nil end
end

-- O buff/debuff está ativo?
--   true  = ativo
--   false = inativo
--
-- ORDEM DA LEITURA (lição do Hunter H-0196): a CRENÇA NUNCA é ignorada.
-- Antes, o addon descartava a crença quando a API de aura respondia, e o
-- buff/sugestão ficava "sempre ativo" (o jogador nunca via a sugestão) ou
-- "sempre ausente" (sugestão infinita). Se NÓS conjuramos, acreditamos.
function module.IsAuraUp(unit, spellID, filter)
    unit = unit or "player"
    -- 1) Crença do nosso próprio cast (sempre honrada, mas somente na mesma
    -- unidade). Um buff no jogador nunca satisfaz um debuff no alvo.
    local unitBeliefs = module.Beliefs and module.Beliefs[unit]
    local b = unitBeliefs and unitBeliefs[spellID]
    if not b and unitBeliefs and addon.Compat and addon.Compat.FamilyOf then
        local family = addon.Compat.FamilyOf[spellID]
        if family then
            for _, id in ipairs(family) do
                b = unitBeliefs[id]
                if b then break end
            end
        end
    end
    if b and b.expires and GetTime() < b.expires then
        local valid = true
        if b.unit == "target" and b.slot ~= module.BeliefSlot then valid = false end
        if valid then return true end
    end
    -- 2) Leitura direta pela categoria explícita. A categoria NÃO é inferida
    -- pela unidade: um aliado pode ter buffs, e o alvo pode ter ambos.
    local state = module.AuraState(unit, filter or "HELPFUL", spellID)
    if state == true then return true end
    return false
end

module.IsBuffUp = function(unit, spellID)
    return module.IsAuraUp(unit or "player", spellID, "HELPFUL")
end

module.IsDebuffUp = function(unit, spellID)
    return module.IsAuraUp(unit or "target", spellID, "HARMFUL")
end

-- ---------------------------------------------------------------------------
-- "Está atrás do alvo?"
--
-- O cliente não expõe a direção do modelo (o modelo clean-room usava uma API que não
-- existe no Forever) -> a condição "behind" é INERTE, igual no modelo clean-room: o Shred
-- (que exige estar atrás) não é sugerido. Mantido assim para preservar a
-- paridade de comportamento; se um dia houver API confiável, é só plugged
-- aqui.
-- ---------------------------------------------------------------------------
function module.IsBehindTarget()
    return false
end

-- ---------------------------------------------------------------------------
-- Debuffs que a própria rotação aplica (o "meu debuff" é verificado aqui, com
-- crença — o gate do Core não conhece crenças e em combate reprovaria sempre).
-- ---------------------------------------------------------------------------
module.SELF_DEBUFF_SPELLS = {
    [1079] = true,  -- Rip
    [1822] = true,  -- Rake
    [54802] = true, -- Lacerate (ID canônico)
    [9005] = true,  -- Pounce
    [5570] = true,  -- Insect Swarm
    [8921] = true,  -- Moonfire
}

-- Debuff de qualquer fonte que o jogador não deve repassar (Roar).
module.ANY_DEBUFF_SPELLS = {
    [99] = true, -- Demoralizing Roar
}

local function spellIsInCanonicalSet(spellID, canonicalSet)
    if type(spellID) ~= "number" then return false end
    if canonicalSet[spellID] then return true end
    local family = addon.Compat and addon.Compat.FamilyOf and addon.Compat.FamilyOf[spellID]
    if not family then return false end
    for _, id in ipairs(family) do
        if canonicalSet[id] then return true end
    end
    return false
end

function module.IsSelfDebuffSpell(spellID)
    return spellIsInCanonicalSet(spellID, module.SELF_DEBUFF_SPELLS)
end

function module.IsAnyDebuffSpell(spellID)
    return spellIsInCanonicalSet(spellID, module.ANY_DEBUFF_SPELLS)
end
