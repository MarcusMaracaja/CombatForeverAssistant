-- Combat Forever Assistant — Druid module: hub.
--
-- Monta o ambiente, detecta a spec, escolhe a rotação conforme a FORMA
-- atual, roda a rotação declarativa e só depois oferece as utilidades
-- (auto-buffs) e a racial.
--
-- ORDEM (utilitários NUNCA bloqueiam o combate):
--   1) rotação da spec/forma (combate)
--   2) racial (baixa prioridade)
--   3) auto-buffs (utilidade)
local addonName, addon = ...
local module = addon.Druid

-- ---------------------------------------------------------------------------
-- Cache de pontos por árvore (C_Traits). Declarado aqui porque o frame de
-- rastreio o invalida no respec (PLAYER_TALENT_CHANGED).
-- ---------------------------------------------------------------------------
local _talentCache = nil

-- ---------------------------------------------------------------------------
-- Frame de rastreio (crenças de aura + troca de alvo)
-- ---------------------------------------------------------------------------
local trackerFrame = CreateFrame("Frame", "CombatForeverAssistantDruidTracker", UIParent)
trackerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
trackerFrame:RegisterEvent("PLAYER_TALENT_CHANGED")
trackerFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
trackerFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
trackerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

trackerFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        if module.OnTargetChanged then module.OnTargetChanged() end
    elseif event == "PLAYER_TALENT_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        -- respec: o cache de pontos por árvore ficou velho
        _talentCache = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        module.Beliefs = { player = {}, target = {} }
        module.BeliefSlot = 0
        module.SuggestedUnits = module.SuggestedUnits or {}
        _talentCache = nil
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        if type(module.OnShapeshiftFormChanged) == "function" then
            pcall(module.OnShapeshiftFormChanged, module)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if type(spellID) == "number" and not (_G.issecretvalue and issecretvalue(spellID)) then
            -- O ID numérico não depende do nome (que pode ser secreto) e a
            -- família de ranks normaliza o spellID para a crença canônica.
            pcall(module.RegisterCast, nil, spellID)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Press suppress próprio do Druid
--
-- O Hunter usa seu próprio mapa/hook; o Druid não pode herdar esse estado pelo
-- __index do addon. O objetivo é simples: quando o jogador clica no botão que
-- acabou de piscar, a mesma spell deixa de ser sugerida durante 0,6 s.
-- ---------------------------------------------------------------------------
function module.OnSpinPressed(button)
    if not button or not button.GetAttribute then return end
    local action = button:GetAttribute("action")
    if not action then return end
    local actionType, id = GetActionInfo(tonumber(action) or action)
    if actionType == "spell" and id then
        local name = module.SpellName(id)
        if name then module.PressSuppress[name] = GetTime() + 0.6 end
    end
end

function module.IsPressSuppressed(spellName)
    if not spellName or spellName == "" then return false end
    local untilTime = module.PressSuppress[spellName]
    return not not (untilTime and GetTime() < untilTime)
end

function module.HookActionButtonPress()
    if module.HooksDone then return end
    module.HooksDone = true
    if type(hooksecurefunc) ~= "function" then return end

    if type(SecureActionButton_OnClick) == "function" then
        hooksecurefunc("SecureActionButton_OnClick", function(self)
            pcall(module.OnSpinPressed, self)
        end)
        return
    end

    local prefixes = {
        "ActionButton", "MultiBarRightButton", "MultiBarLeftButton",
        "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "PetActionButton", "StanceButton", "PossessButton",
    }
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and not button.cfaDruidPressHooked then
                button.cfaDruidPressHooked = true
                hooksecurefunc(button, "Click", function(self)
                    pcall(module.OnSpinPressed, self)
                end)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Helpers de ambiente
-- ---------------------------------------------------------------------------
local function safePct(cur, max)
    local c = module.SafeNumber(cur, nil)
    local m = module.SafeNumber(max, nil)
    if c and m and m > 0 then
        return math.floor(((c / m) * 100) + 0.5)
    end
    return 100
end

local function safePower(unit, ptype)
    if type(UnitPower) ~= "function" then return 0 end
    local ok, v = pcall(UnitPower, unit, ptype)
    if not ok then return 0 end
    return module.SafeNumber(v, 0) or 0
end

local function isCastingSomething(unit)
    -- Os tempos modernos são mais confiáveis que o nome: o cliente pode
    -- mascará-lo como valor secreto mesmo com cast/channel ativo.
    if addon.Compat and type(addon.Compat.CastingOrChanneling) == "function" then
        local ok, remaining = pcall(addon.Compat.CastingOrChanneling, nil, unit)
        if ok and type(remaining) == "number" and remaining > 0 then return true end
    end

    if type(UnitCastingInfo) == "function" then
        local ok, castName = pcall(UnitCastingInfo, unit)
        if ok and castName then
            if _G.issecretvalue and issecretvalue(castName) then return false end
            return true
        end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, channelName = pcall(UnitChannelInfo, unit)
        if ok and channelName then
            if _G.issecretvalue and issecretvalue(channelName) then return false end
            return true
        end
    end
    return false
end

local function combatOf(unit)
    if type(UnitAffectingCombat) ~= "function" then return false end
    local ok, v = pcall(UnitAffectingCombat, unit)
    if not ok then return true end
    if _G.issecretvalue and issecretvalue(v) then return true end
    return v and true or false
end

local function isMounted()
    if type(IsMounted) == "function" then
        local ok, v = pcall(IsMounted)
        if ok and v then return true end
    end
    if type(IsInMountedState) == "function" then
        local ok, v = pcall(IsInMountedState)
        if ok and v then return true end
    end
    return false
end

local function friendlyAlive(unit)
    if not UnitExists(unit) then return false end
    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
    if okD and dead then return false end
    local ok, canAttack = pcall(UnitCanAttack, "player", unit)
    -- Quando não é possível confirmar que o alvo é aliado, falhar fechado.
    if not ok then return false end
    if _G.issecretvalue and issecretvalue(canAttack) then return false end
    return (not canAttack) and true or false
end

-- Contagem de inimigos: usa o SmartAoe do MaxDps quando existe.
-- Retorna (quantidade, leituraConfiavel).
local function countEnemiesInCombat()
    if _G.MaxDps and type(_G.MaxDps.SmartAoe) == "function" then
        local ok, n = pcall(_G.MaxDps.SmartAoe)
        if ok then
            local v = module.SafeNumber(n, nil)
            if v then return v, true end
        end
    end
    -- Sem detector: 0 inimigos (os nós de área não sugerem) e leitura
    -- inconfiável -> os predicados que dependem de AoE passam (fail-open).
    return 0, false
end

function module:BuildEnv()
    local env = {}
    env.myHP = safePct(UnitHealth and UnitHealth("player"), UnitHealthMax and UnitHealthMax("player"))
    local powerType = module.GetPowerType()
    if powerType == 0 then
        env.manaPct = safePct(
            UnitPower and UnitPower("player", 0),
            UnitPowerMax and UnitPowerMax("player", 0)
        )
    else
        -- Energia/Rage não são mana; filtros de mana devem falhar fora da
        -- forma de conjurador.
        env.manaPct = nil
    end
    env.rage = safePower("player", 1)
    env.energy = safePower("player", 3)
    env.combo = module.GetComboPoints()
    env.targetCasting = isCastingSomething("target")
    env.targetInterruptible = module.IsTargetInterruptibleCasting("target")
    env.hasActiveEnemy = module.UnitTargetExistsAndAttackable()
    env.isPvP = module.IsPvPTarget()
    env.targetExists = (type(UnitExists) == "function" and UnitExists("target")) and true or false
    env.targetFriendlyAlive = friendlyAlive("target")
    env.inCombat = combatOf("player")
    local enemies, aoeKnown = countEnemiesInCombat()
    env.enemies = enemies
    env.aoeKnown = aoeKnown
    env.isAoE = enemies >= 2
    env.mounted = isMounted()
    env.form = module.GetForm()
    env.isMoonkin = module.IsMoonkinFormActive()

    -- Distância: o Druid não tem zona morta (5-10 yd) como o Hunter, mas
    -- saber se está em melee é útil (e o filtro de alcance do editor usa isso).
    env.isMelee = false
    env.tooCloseForRanged = false
    env.targetDistance = nil
    if env.targetExists then
        local dist = addon:TargetDistance("target")
        if dist then
            env.targetDistance = dist
            env.isMelee = dist <= 5
        else
            local melee = addon:IsInMeleeRange("target")
            if melee == true then
                env.targetDistance = 5
                env.isMelee = true
            elseif melee == false then
                env.targetDistance = 30
            else
                env.targetDistance = 100
            end
        end
    else
        env.targetDistance = 100
    end
    return env
end

-- ---------------------------------------------------------------------------
-- Detecção de spec
--
-- Em camadas (a mais confiável primeiro):
--   1) override manual (charDb.druidSpec) — sempre disponível na aba /cfa
--   2) GetSpecialization() (ID de spec: 102 Feral, 103 Balance, 105 Restauração)
--   3) C_Traits: assinatura das spells concedidas por nós de talento ativos
--   4) assinatura por spell comprovadamente aprendida
--   5) UNKNOWN — nunca escolher Feral por padrão sem evidência
--
-- Os nomes das árvores são "(sem nome)" neste cliente; por isso a assinatura
-- dos talentos ativos é mais confiável que a ordem ordinal das árvores.
-- ---------------------------------------------------------------------------
local SPEC_BY_ID = {
    [102] = "FERAL", -- Feral Druid
    [103] = "BAL",   -- Balance Druid
    [105] = "REST",  -- Restoration Druid
    [250] = "FERAL", -- Guardian (tratado como Feral/Urso)
}

-- Assinaturas por spec. Somente IDs exclusivos e comprovados nos dados
-- locais: spells compartilhadas por toda a classe não distinguem uma spec.
local TREE_SIGNATURES = {
    FERAL = { 1822, 1079, 5221, 22568, 9005 }, -- Rake/Rip/Shred/Ferocious Bite/Pounce
    BAL   = { 8950, 5570, 8921, 5176, 24858 },  -- Starfire/Insect Swarm/Moonfire/Wrath/Moonkin Form
    REST  = { 8936, 774 },                     -- Regrowth/Rejuvenation
}
-- Ordem determinística; não usar pairs() para escolher a spec.
local TREE_SPEC_ORDER = { "FERAL", "BAL", "REST" }

local function nodeRank(ni)
    local maxRank = 0
    for _, k in ipairs({ "currentRank", "ranksPurchased", "activeRank" }) do
        local v = ni[k]
        if type(v) == "number" and not (_G.issecretvalue and issecretvalue(v)) and v > maxRank then
            maxRank = v
        end
    end
    return maxRank
end

local function bestSignature(spells)
    local bestSpec, bestScore
    for _, spec in ipairs(TREE_SPEC_ORDER) do
        local score = 0
        for _, sid in ipairs(TREE_SIGNATURES[spec]) do
            if spells[sid] then score = score + 1 end
        end
        if score > 0 and (not bestScore or score > bestScore) then
            bestSpec, bestScore = spec, score
        end
    end
    return bestSpec, bestScore
end

local function talentTreeInfo()
    if _talentCache then return _talentCache end
    _talentCache = false
    if not (C_ClassTalents and C_Traits) then return false end
    local okCfg, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    if not okCfg or not cfg then return false end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not okInfo or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return false end
    local trees = {}
    for idx, treeID in ipairs(info.treeIDs) do
        local points = 0
        local spells = {}
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okNI, ni = pcall(C_Traits.GetNodeInfo, cfg, nodeID)
                if okNI and type(ni) == "table" then
                    local rank = nodeRank(ni)
                    points = points + rank
                    -- playerSpells de um nó não comprado não identifica a spec.
                    if rank > 0 and type(ni.playerSpells) == "table" then
                        for _, sid in ipairs(ni.playerSpells) do
                            if type(sid) == "number" and not (_G.issecretvalue and issecretvalue(sid)) then
                                spells[sid] = true
                            end
                        end
                    end
                end
            end
        end
        local detected, signatureScore = bestSignature(spells)
        trees[#trees + 1] = {
            index = idx,
            treeID = treeID,
            points = points,
            spec = detected,
            signatureScore = signatureScore or 0,
            spells = spells,
        }
    end
    _talentCache = { trees = trees }
    return _talentCache
end

local function detectBySpecialization()
    if type(GetSpecialization) ~= "function" then return nil end
    local ok, id = pcall(GetSpecialization)
    if not ok or type(id) ~= "number" then return nil end
    if _G.issecretvalue and issecretvalue(id) then return nil end
    local spec = SPEC_BY_ID[id]
    if spec then return spec, id end
    return nil, id
end

function module:DetectSpec()
    local override = module.charDb and module.charDb.druidSpec or nil
    if override == "FERAL" or override == "BAL" or override == "REST" then
        return override, "override"
    end

    -- 2) GetSpecialization (ID de spec) — o mais direto
    local spec, sid = detectBySpecialization()
    if spec then return spec, "GetSpecialization=" .. tostring(sid) end

    -- 3) C_Traits — assinatura das árvores ativas. Pontos sem assinatura não
    -- revelam a spec; não há fallback ordinal porque a ordem das árvores não é
    -- um contrato estável.
    local cache = talentTreeInfo()
    if cache and cache.trees then
        local scores, pointsBySpec = {}, {}
        for _, t in ipairs(cache.trees) do
            if t.spec and t.points > 0 and (t.signatureScore or 0) > 0 then
                scores[t.spec] = (scores[t.spec] or 0) + t.signatureScore
                pointsBySpec[t.spec] = (pointsBySpec[t.spec] or 0) + t.points
            end
        end
        local best, bestScore, bestPoints
        for _, spec in ipairs(TREE_SPEC_ORDER) do
            local score = scores[spec] or 0
            local points = pointsBySpec[spec] or 0
            if score > (bestScore or 0)
                or (score == (bestScore or 0) and score > 0 and points > (bestPoints or 0)) then
                best, bestScore, bestPoints = spec, score, points
            end
        end
        if best then
            return best, string.format("C_Traits assinatura (%s, %d pontos)", best, bestPoints or 0)
        end
    end

    -- 4) assinatura por spell comprovadamente aprendida. Estados desconhecidos
    -- não contam; sem evidência, a spec fica UNKNOWN e exige override manual.
    local function known(id)
        if not (addon.Compat and addon.Compat.SpellKnownState) then return false end
        return addon.Compat.SpellKnownState(id) == true
    end
    local best, bestScore
    for _, spec in ipairs(TREE_SPEC_ORDER) do
        local score = 0
        for _, id in ipairs(TREE_SIGNATURES[spec]) do
            if known(id) then score = score + 1 end
        end
        if score > (bestScore or 0) then best, bestScore = spec, score end
    end
    if best and bestScore > 0 then
        return best, "spells de " .. best
    end

    return "UNKNOWN", "sem spec confirmada"
end

-- Escolhe a rotação conforme a spec e a FORMA atual.
function module:PickRotation(env)
    local specKey = self:DetectSpec()
    if specKey == "FERAL" then
        if env.form == module.FORM_BEAR then return specKey, "BEAR" end
        if env.form == module.FORM_CAT then return specKey, "CAT" end
        return specKey, "SELF"
    elseif specKey == "BAL" then
        return specKey, "BAL"
    elseif specKey == "REST" then
        return specKey, "REST"
    end
    return "UNKNOWN", "UNKNOWN"
end

-- ---------------------------------------------------------------------------
-- Sugestão (mesma convenção do Hunter: Suggest/TryFlash/ReleaseSuggestion)
-- ---------------------------------------------------------------------------
module.TickFlashUsed = nil
module.PendingSuggestion = nil

function module:Suggest(spellID, color, unit)
    if module.TickFlashUsed then return false end
    module.TickFlashUsed = true
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(spellID) or spellID
    module.PendingSuggestion = { spellID = knownID or spellID, color = color or "Utility", unit = unit }
    return true
end

-- Libera o tick depois de uma sugestão utilitária ("passthrough"): a sugestão
-- continua como fallback, mas os nós seguintes podem substituí-la.
function module:ReleaseSuggestion()
    module.TickFlashUsed = nil
end

function module:TryFlash(spellID, color, condition, name, env, opts)
    if module.TickFlashUsed then return false end
    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(spellID) or spellID
    local spellName = module.SpellName(knownID or spellID)
    if not spellName then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: nome da spell não resolvido")
        return false
    end
    if type(module.IsPressSuppressed) == "function" and module.IsPressSuppressed(spellName) then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: botão pressionado agora")
        return false
    end
    if type(condition) == "function" then
        local ok, res = pcall(condition, env)
        if not ok or not res then
            addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: condição")
            return false
        end
    end
    -- Debuffs da própria rotação (Rip/Rake/Lacerate/Pounce/Insect Swarm/
    -- Moonfire) e debuff de qualquer fonte (Roar): verificados COM CRENÇA,
    -- porque em combate as auras do alvo são secretas e o gate do Core
    -- reprovaria sempre.
    if type(spellID) == "number" then
        if module.IsSelfDebuffSpell(spellID) and module.IsDebuffUp("target", spellID) then
            addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: debuff já aplicado")
            return false
        end
        if module.IsAnyDebuffSpell(spellID) and module.IsDebuffUp("target", spellID) then
            addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO: debuff já aplicado")
            return false
        end
    end
    local dbg = {}
    local castable = module.CheckCastable({
        SpellName = spellName,
        SpellID = knownID or spellID,
        EnemyTargetNeeded = not (opts and opts.noEnemy),
        NoRangeCheck = (opts and opts.noRange) and true or nil,
        NotIfActive = (opts and opts.notIfActive) and true or nil,
        Debug = dbg,
    })
    module.LastCastDebug = dbg
    if not castable then
        addon:DebugPrint("tryflash", tostring(name or spellID), "BLOQUEADO:", tostring(dbg.reason))
        return false
    end
    addon:DebugPrint("tryflash", tostring(name or spellID), "OK (sugere)")
    return module:Suggest(knownID or spellID, color)
end

-- ---------------------------------------------------------------------------
-- Auto-buffs (utilidade) — MotW / Thorns / Nature's Grasp
--
-- Rodam DEPOIS da rotação da spec e usam a verificação de aura COM CRENÇA
-- (o gate de buff do Core não lê aura secreta em combate).
-- Anti-spam: se o jogador ignorar a sugestão por 10s contínuos, pausa 30s
-- (nunca travar a rotação).
-- ---------------------------------------------------------------------------
module.UtilitySuggestCount = {}
module.UtilityIgnore = {}

local UTILITY_BUFFS = {
    { id = 1126,  key = "mark_missing",   name = "Mark of the Wild", unit = "friendly_or_player" },
    { id = 467,   key = "thorns_missing", name = "Thorns", unit = "friendly_or_player" },
    { id = 16689, key = "enred_missing",  name = "Nature's Grasp", unit = "player" },
}

function module:TrySelfBuff(spec, env)
    local pred = module.RotationPredicates and module.RotationPredicates[spec.key]
    if not pred or type(pred.fn) ~= "function" then return false end
    local ok, res = pcall(pred.fn, env)
    if not ok or not res then return false end

    local ignoreUntil = module.UtilityIgnore[spec.id]
    if ignoreUntil and GetTime() < ignoreUntil then return false end

    local knownID = addon.Compat and addon.Compat.HighestKnownSpellID and addon.Compat.HighestKnownSpellID(spec.id) or spec.id
    local spellName = module.SpellName(knownID)
    if not spellName then return false end
    if type(module.IsPressSuppressed) == "function" and module.IsPressSuppressed(spellName) then return false end

    -- Marca da Selva e Espinhos usam a unidade inteligente: alvo aliado vivo
    -- quando selecionado; caso contrário, o próprio jogador. Nature's Grasp
    -- permanece no jogador.
    local unit = "player"
    if spec.unit == "friendly_or_player" and env.targetExists and env.targetFriendlyAlive then
        unit = "target"
    end
    if module.IsBuffUp(unit, spec.id) then return false end

    local dbg = {}
    local castable = module.CheckCastable({
        SpellName = spellName,
        SpellID = knownID,
        Unit = unit,
        EnemyTargetNeeded = false,
        NoRangeCheck = true,
        Debug = dbg,
    })
    if not castable then
        addon:DebugPrint("auto-buff", spec.name, "BLOQUEADO:", tostring(dbg.reason))
        return false
    end

    local now = GetTime()
    local firstSeen = module.UtilityFirstSeen[spec.id]
    if not firstSeen then
        firstSeen = now
        module.UtilityFirstSeen[spec.id] = firstSeen
    end
    module.UtilitySuggestCount[spec.id] = (module.UtilitySuggestCount[spec.id] or 0) + 1
    if now - firstSeen >= 10 then
        module.UtilityIgnore[spec.id] = now + 30
        module.UtilityFirstSeen[spec.id] = nil
        module.UtilitySuggestCount[spec.id] = 0
        addon:DebugPrint("auto-buff", spec.name, "pausado 30s (10s ignorados)")
        return false
    end
    if module.SuggestedUnits then
        module.SuggestedUnits[spec.id] = { unit = unit, expiresAt = GetTime() + 2 }
    end
    local suggested = module:Suggest(knownID, "Utility", unit)
    if not suggested and module.SuggestedUnits then module.SuggestedUnits[spec.id] = nil end
    return suggested
end

-- ---------------------------------------------------------------------------
-- Pipeline principal
-- ---------------------------------------------------------------------------
function module:GetSuggestion()
    local _, myClass = UnitClass("player")
    if myClass ~= "DRUID" then return nil end
    if module.db and module.db.druidEnabled == false then return nil end
    module.TickFlashUsed = nil
    module.PendingSuggestion = nil
    if type(module.HookActionButtonPress) == "function" then
        pcall(module.HookActionButtonPress, module)
    end
    if isMounted() then
        addon:DebugPrint("GetSuggestion: montado — nada sugerido")
        return nil
    end
    if isCastingSomething("player") then
        addon:DebugPrint("GetSuggestion: conjurando/canalizando — nada sugerido")
        return nil
    end

    local env = module:BuildEnv()
    local specKey, rotKey = module:PickRotation(env)
    addon:DebugPrint(string.format(
        "druid env: spec=%s rot=%s | forma=%s | inimigo=%s | combate=%s | melee=%s | dist=%s | aoe=%s | hp=%s | mana=%s | energy=%s | combo=%s",
        tostring(specKey), tostring(rotKey), tostring(env.form), tostring(env.hasActiveEnemy),
        tostring(env.inCombat), tostring(env.isMelee), tostring(env.targetDistance),
        tostring(env.isAoE), tostring(env.myHP), tostring(env.manaPct),
        tostring(env.energy), tostring(env.combo)))

    -- 1) Rotação da spec/forma (combate) — vem primeiro, sempre
    if rotKey and addon.RunDeclaredRotation then
        addon:RunDeclaredRotation(module, rotKey, env)
        if module.PendingSuggestion then return module.PendingSuggestion end
    end

    -- 2) Racial (baixa prioridade: só quando a rotação não tem nada a dizer).
    --    Fica ANTES dos auto-buffs porque é um cooldown de combate (ex.
    --    Fúria dos Berserker) e os auto-buffs são utilidade pura.
    if addon.SuggestRacial and addon:SuggestRacial(module, env) then
        return module.PendingSuggestion
    end

    -- 3) Auto-buffs (utilidade) — depois da spec e da racial: nunca bloqueiam
    --    o combate
    for _, spec in ipairs(UTILITY_BUFFS) do
        if module:TrySelfBuff(spec, env) then return module.PendingSuggestion end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- /cfa debug — relatório da rotação no estado atual
-- ---------------------------------------------------------------------------
function module:DebugRotation()
    local env = module:BuildEnv()
    local specKey, rotKey = module:PickRotation(env)
    print("|cff44ddff[CFA dbg]|r ===== RELATÓRIO DA ROTAÇÃO (DRUID) =====")
    print(string.format("|cff44ddff[CFA dbg]|r spec=%s (%s) | rotação=%s | forma=%s | lua=%s",
        tostring(specKey), tostring(select(2, module:DetectSpec())), tostring(rotKey),
        tostring(env.form), tostring(env.isMoonkin)))
    print(string.format("|cff44ddff[CFA dbg]|r inimigo=%s | combate=%s | melee=%s | dist=%s | aoe=%s (confiável=%s) | hp=%s | mana=%s | energy=%s | combo=%s",
        tostring(env.hasActiveEnemy), tostring(env.inCombat), tostring(env.isMelee),
        tostring(env.targetDistance), tostring(env.isAoE), tostring(env.aoeKnown),
        tostring(env.myHP), tostring(env.manaPct), tostring(env.energy), tostring(env.combo)))
    -- dados brutos da detecção (para conferir a ordem das árvores em jogo)
    local cache = talentTreeInfo()
    if cache and cache.trees then
        for _, t in ipairs(cache.trees) do
            print(string.format("|cff44ddff[CFA dbg]|r árvore %d (id=%s): pontos=%d | assinatura=%s | sinais=%d",
                t.index, tostring(t.treeID), t.points, tostring(t.spec or "?"),
                t.signatureScore or 0))
        end
    else
        print("|cff44ddff[CFA dbg]|r C_Traits indisponível")
    end
    print("|cff44ddff[CFA dbg]|r --- nós da rotação ---")
    local nodes = module:GetEffectiveNodes(rotKey) or {}
    local preds = module.RotationPredicates or {}
    for _, node in ipairs(nodes) do
        local condOK = true
        if node.enabled == false then
            condOK = false
        elseif node.condition and node.condition ~= "" then
            local p = preds[node.condition]
            if type(p) == "table" and type(p.fn) == "function" then
                local ok, r = pcall(p.fn, env)
                condOK = ok and r and true or false
            end
        end
        local name = module.SpellName(node.spellID)
        local knownID = (addon.Compat and addon.Compat.HighestKnownSpellID
            and addon.Compat.HighestKnownSpellID(node.spellID)) or node.spellID
        local dbg = {}
        local cast = false
        if condOK and name then
            local opts = node.opts or {}
            cast = module.CheckCastable({
                SpellName = name, SpellID = knownID,
                EnemyTargetNeeded = not opts.noEnemy,
                NoRangeCheck = opts.noRange and true or nil,
                NotIfActive = opts.notIfActive and true or nil,
                Debug = dbg,
            }) and true or false
        end
        print(string.format("|cff44ddff[CFA dbg]|r %-22s cond=%-5s known=%-5s cast=%-5s %s",
            tostring(node.id), tostring(condOK),
            tostring(addon.Compat.SpellKnown(knownID)), tostring(cast), tostring(dbg.reason or "")))
    end
end

-- ---------------------------------------------------------------------------
-- /cfa status
-- ---------------------------------------------------------------------------
function module:GetStatus()
    local spec, source = self:DetectSpec()
    local enabled = not (module.db and module.db.druidEnabled == false)
    local env = module:BuildEnv()
    local formName
    if env.isMoonkin then
        formName = "Lua"
    elseif env.form == module.FORM_BEAR then
        formName = "Urso"
    elseif env.form == module.FORM_CAT then
        formName = "Gato"
    elseif env.form == module.FORM_UNKNOWN then
        formName = "Desconhecida"
    else
        formName = "Conjurador"
    end
    local PT = (GetLocale and GetLocale() == "ptBR")
    if PT then
        return string.format("Druid — spec %s (%s) — %s — forma: %s", tostring(spec), tostring(source),
            enabled and "ligado" or "desligado", formName)
    end
    return string.format("Druid — spec %s (%s) — %s — form: %s", tostring(spec), tostring(source),
        enabled and "enabled" or "disabled", formName)
end

-- ---------------------------------------------------------------------------
-- Registro no core
-- ---------------------------------------------------------------------------
addon:CreateRotationStore(module, "druid")
addon:RegisterModule("DRUID", module)
