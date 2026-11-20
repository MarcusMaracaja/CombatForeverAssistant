-- Combat Forever Assistant — Hunter module: castable engine + aura beliefs.
local moduleName, module = ...
local addon = _G.CFA

module.L = module.L
local L = module.L
local BuffLib = module.BuffLib

-- ---------------------------------------------------------------------------
-- Castable engine: given a table describing a spell to cast, answer "can I
-- cast this now?". Kept deliberately small: the rotation proves spells out by
-- checking conditions + range/CD before suggesting.
-- ---------------------------------------------------------------------------
module.Castable = module.Castable or {}

-- Secret-number guard (this client degrades UNIT_* reads to secret values
-- while our code executes): anything we cannot read becomes `fallback`.
function module.SafeNumber(v, fallback)
    if type(v) ~= "number" then return fallback end
    if _G.issecretvalue and issecretvalue(v) then return fallback end
    return v
end

function module.SpellIDFromName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if module.Compat and module.Compat.SpellBookItem then
        for i = 1, 300 do
            local n, _ = module.Compat.SpellBookItem(i, "spell")
            if n == name then
                local ok, info = pcall(function()
                    if C_Spell and C_Spell.GetSpellInfo then
                        local o, i2 = pcall(C_Spell.GetSpellInfo, i)
                        return o and i2 and type(i2) == "table" and i2.spellID or nil
                    end
                end)
                return ok and info or nil
            end
            if n == nil then break end
        end
    end
    return nil
end

function module.SpellKnown(name)
    if module.Compat and module.Compat.SpellBookItem then
        for i = 1, 300 do
            local n, _ = module.Compat.SpellBookItem(i, "spell")
            if n == name then return true end
            if n == nil then break end
        end
        return false
    end
    return false
end

function module.IsOnCooldown(name, id)
    local known = id or module.SpellIDFromName(name)
    if not known then return false end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local ok, info = pcall(C_Spell.GetSpellCooldown, known)
    if not ok or type(info) ~= "table" then return false end
    -- This client reports cooldownStartTime/cooldownDuration (older field names
    -- startTime/duration on some paths); isActive == true means on recovery.
    local start = info.startTime or info.cooldownStartTime
    local dur = info.duration or info.cooldownDuration
    -- Guard against secret (tainted) numbers: never compare them arithmetically.
    -- This client degrades some cooldown reads to secret values while tainted.
    if _G.issecretvalue and (issecretvalue(start) or issecretvalue(dur)) then return true end
    if type(start) == "number" and type(dur) == "number" and start > 0 and dur > 0 then
        return (GetTime() - start) < dur
    end
    if info.isActive == true then
        -- GCD (~1.5s) is not a cooldown; anything else is treated as active
        if type(dur) == "number" and dur <= 1.5 then return false end
        return true
    end
    return false
end

function module.CheckCastable(z)
    if type(z) ~= "table" then return false end
    -- Usa o CheckIfSpellCastable robusto do Core (baseado no modelo clean-room), que cobre:
    -- spell conhecido, cooldown (spellID + slot da barra como reforço), GCD,
    -- alcance, auras (buff/debuff/myBuff/myDebuff), EnemyTargetNeeded,
    -- TargetThatUsesManaNeeded, NotIfActive, EvenIfNotUsable.
    z.Unit = z.Unit or "target"
    -- ATENÇÃO: CheckIfSpellCastable é definido como método (self implícito).
    -- Chamar com "." fazia o argumento cair em self e z chegar como nil —
    -- isso bloqueava TODA a rotação (só os aspectos, que não usam esse gate,
    -- apareciam). Sempre chamar com ":".
    return addon:CheckIfSpellCastable(z)
end

-- ---------------------------------------------------------------------------
-- Aura helpers via BuffLib (aura IDs — UnitBuff reports auras in this client)
-- ---------------------------------------------------------------------------
function module.HasFamilyBuff(unit, family)
    if not BuffLib or not BuffLib.HasFamily then return false end
    return BuffLib:HasFamily(unit, family) and true or false
end

function module.HasFamilyDebuff(unit, family, onlyMine)
    if not BuffLib or not BuffLib.Has then return false end
    return BuffLib:Has(unit, family) and true or false
end

local function targetMana()
    if not UnitExists("target") then return 0 end
    local ok, t = pcall(UnitPowerType, "target")
    return ok and t or 0
end

function module.TargetUsesMana()
    return targetMana() == 0
end

function module.TargetIsMeleeClass()
    if not UnitExists("target") then return false end
    local _, cls = UnitClass("target")
    return cls == "WARRIOR" or cls == "ROGUE"
end

-- Zona morta exclusiva do Hunter: 5 < distância <= 10 yards.
-- A medida é a única fonte autoritativa; sem leitura, retorna desconhecido.
function module:IsInDeadZoneRange(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    local distance = self:TargetDistance(unit)
    if not distance then return nil end
    return (distance > 5 and distance <= 10) and true or false
end

-- PvE silence/interrupt question: is the current enemy casting an
-- interruptible spell?
function module.IsTargetInterruptibleCasting(unit)
    unit = unit or "target"
    if addon.Compat and type(addon.Compat.IsInterruptibleCasting) == "function" then
        return addon.Compat.IsInterruptibleCasting(unit) and true or false
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Beliefs: track our own casts (UNIT_SPELLCAST_SUCCEEDED, filter "player")
-- instead of trusting UnitDebuff in combat (auras are secret there).
-- Slot counter increments on every PLAYER_TARGET_CHANGED — a new target
-- invalidates previous beliefs (GUID would be secret anyway).
-- ---------------------------------------------------------------------------
local markBeliefSlot = 0
module.MarkBelief = { slot = 0, active = false }
module.SerpentStingBelief = { slot = 0, applied = false, expires = 0 }
module.WingClipBelief = { slot = 0, applied = false, expires = 0 }
module.AspectBelief = nil
module.PET_IS_DEAD = false

-- Exposed so Scripts.lua can create the tracker frame (ordering: module load).
function module.OnTargetChanged()
    markBeliefSlot = markBeliefSlot + 1
    module.SerpentStingBelief.applied = false
    module.WingClipBelief.applied = false
end

function module.RegisterCast(castName)
    -- Nome secreto (cliente mascara dados em combate) não pode ser comparado.
    if type(castName) ~= "string" or castName == "" then return end
    if _G.issecretvalue and issecretvalue(castName) then return end
    local base = castName:lower():gsub("%s*%b()%s*$", "")
    local function strip(id)
        local n = module.SpellName(id)
        if not n then return nil end
        return n:lower():gsub("%s*%b()%s*$", "")
    end
    if strip(1130) == base then
        module.MarkBelief.active = true
        module.MarkBelief.slot = markBeliefSlot
        return
    end
    if strip(1978) == base then
        module.SerpentStingBelief.applied = true
        module.SerpentStingBelief.slot = markBeliefSlot
        module.SerpentStingBelief.expires = GetTime() + 15
        return
    end
    if strip(2974) == base then
        module.WingClipBelief.applied = true
        module.WingClipBelief.slot = markBeliefSlot
        module.WingClipBelief.expires = GetTime() + 12
        return
    end
    if strip(3045) == base then -- Rapid Fire: pure self CD, no belief needed
        return
    end
    -- aspect tracking (auras are secret in combat). Persisted per character:
    -- aspects don't expire on their own, so the belief can outlive /reload.
    local ids = { 5118, 13159, 13161, 13163, 13165, 20043 }
    for _, id in ipairs(ids) do
        if strip(id) == base then
            module.AspectBelief = { active = true, name = base, id = id, time = GetTime() }
            if module.charDb then
                module.charDb.aspectBelief = { id = id, name = base, time = GetTime() }
            end
            -- o jogador usou o aspecto: zera o contador de insistência
            module.AspectSuggestCount = 0
            module.AspectIgnore = {}
            return
        end
    end
end

function module.IsMarkedByUs()
    return module.MarkBelief.active and module.MarkBelief.slot == markBeliefSlot
end

function module.IsSerpentStingActive(unit)
    unit = unit or "target"
    if unit == "target" then
        local b = module.SerpentStingBelief
        if b.applied and b.slot == markBeliefSlot and GetTime() < b.expires then
            return true
        end
        b.applied = false
    end
    return module.HasFamilyBuff(unit, "SerpentSting")
end

-- Aura API readable? (outside combat yes; in combat the whole payload is secret)
function module.AspectAuraReadable()
    if not BuffLib or not BuffLib.Status then return true end
    local st = BuffLib:Status("player", "AspectOfTheHawk")
    return st and st.readable and true or false
end

local function stripAspectName(n)
    if type(n) ~= "string" then return "" end
    return n:lower():gsub("%s*%b()%s*$", "")
end

-- Semântica do aspecto (comportamento validado na referência clean-room):
--  1) aura do jogador — por NOME LOCALIZADO (funciona em ptBR) e por spellID;
--  2) BuffLib por família/aura ID;
--  3) crença do nosso próprio cast (sessão) — auras são secret em combate;
--  4) crença persistente por personagem (aspectos não expiram sozinhos).
-- IMPORTANTE: a crença NUNCA é ignorada. Antes, fora de combate (API legível)
-- o CFA descartava a crença e, como o BuffLib casa por nome em inglês, o
-- Aspecto do Guepardo ficava "sempre inativo" -> sugeria eternamente e
-- travava a rotação antes dela começar.
local function aspectActive(family, id)
    local name = module.SpellName(id)
    local base = stripAspectName(name)
    if module.HasBuff("player", id) then return true end
    if module.HasFamilyBuff("player", family) then return true end
    local b = module.AspectBelief
    if b and b.active and (b.id == id or stripAspectName(b.name) == base) then return true end
    local cb = module.charDb and module.charDb.aspectBelief
    if cb and (cb.id == id or stripAspectName(cb.name) == base) then return true end
    return false
end

-- Debuff readable by name (out of combat / not secret). Returns false in
-- combat when auras are secret — callers use beliefs there.
function module.HasDebuff(unit, name)
    if type(UnitDebuff) ~= "function" then return false end
    if type(name) ~= "string" or name == "" then return false end
    local want = name:lower():gsub("%s*%b()%s*$", "")
    for i = 1, 40 do
        local ok, n = pcall(UnitDebuff, unit, i)
        if not ok or not n then return false end
        if _G.issecretvalue and issecretvalue(n) then break end
        if n == name then return true end
        if n:lower():gsub("%s*%b()%s*$", "") == want then return true end
    end
    return false
end

function module.IsWingClipActive(unit)
    unit = unit or "target"
    if unit == "target" then
        local b = module.WingClipBelief
        if b.applied and b.slot == markBeliefSlot and GetTime() < b.expires then
            return true
        end
        b.applied = false
        return module.HasDebuff(unit, "Wing Clip")
    end
    return module.HasDebuff(unit, "Wing Clip")
end

function module.IsClipped(unit)
    return module.IsWingClipActive(unit)
end

function module.HasBuff(unit, spellIDOrName)
    unit = unit or "player"
    if not UnitExists(unit) then return false end
    local wantName
    if type(spellIDOrName) == "number" then
        wantName = module.SpellName(spellIDOrName)
    elseif type(spellIDOrName) == "string" then
        wantName = spellIDOrName
    end
    local wantClean = wantName and stripAspectName(wantName) or nil

    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for i = 1, 40 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not data or type(data) ~= "table" then break end
            local okId, sId = pcall(function()
                return tonumber(data.spellId or data.spellID or data.auraSpellId or data.auraSpellID)
            end)
            if okId and sId and type(spellIDOrName) == "number" and sId == spellIDOrName then
                return true
            end
            if wantClean and type(data.name) == "string"
                and not (_G.issecretvalue and issecretvalue(data.name))
                and stripAspectName(data.name) == wantClean then
                return true
            end
        end
    end

    return false
end

function module.IsAspectIDActive(id, family)
    return aspectActive(family or "Generic", id)
end

function module.IsAspectOfCheetahActive()
    return module.IsAspectIDActive(5118, "AspectOfTheCheetah")
end
function module.IsAspectOfPackActive()
    return module.IsAspectIDActive(13159, "AspectOfThePack")
end
function module.IsAspectOfHawkActive()
    return module.IsAspectIDActive(13165, "AspectOfTheHawk")
end
function module.IsAspectOfMonkeyActive()
    return module.IsAspectIDActive(13163, "AspectOfTheMonkey")
end
function module.IsAspectOfBeastActive()
    return module.IsAspectIDActive(13161, "AspectOfTheBeast")
end
function module.IsAspectOfWildActive()
    return module.IsAspectIDActive(20043, "AspectOfTheWild")
end

function module.IsAspectActive()
    return module.IsAspectOfHawkActive()
        or module.IsAspectOfCheetahActive()
        or module.IsAspectOfMonkeyActive()
        or module.IsAspectOfBeastActive()
        or module.IsAspectOfPackActive()
        or module.IsAspectOfWildActive()
end

function module.IsMarked(unit)
    unit = unit or "target"
    return module.HasFamilyBuff(unit, "HuntersMark") or module.HasDebuff(unit, "Hunter's Mark")
end

-- ---------------------------------------------------------------------------
-- Revive Pet — só sugere quando o pet está morto (sem corpo ou com corpo)
-- e nunca quando o pet está vivo ou dispensado/estábulo sem morte prévia.
-- ---------------------------------------------------------------------------
module.Castable = module.Castable or {}
module.Castable["Revive Pet"] = function()
    if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then return false end
    -- Pet inexistente e nunca detectado como morto (dispensado/estábulo): nada a reviver.
    if not UnitExists("pet") and not module.PET_IS_DEAD then return false end
    local z = {
        SpellName = module.SpellName(34497),
        SpellID = 34497,
        EnemyTargetNeeded = false,
    }
    return module.CheckCastable(z)
end
