-- Combat Forever Assistant — Shared: per-character rotation overrides.
--
-- Extrai (para reuso por qualquer classe) a lógica de "overrides por
-- personagem" que o módulo do Hunter usava: ligar/desligar um nó, trocar a
-- condição, trocar os filtros e reordenar a cadeia.
--
-- Convenção de chamada (NUNCA misturar):
--   module:GetNodeOrder(specKey)            -> método (self implícito)
--   module:SetNodeOrder(specKey, order)      -> método
--   module:MoveNode(specKey, nodeId, delta)  -> método
--   module:GetEffectiveNodes(specKey)        -> método
--   module:SetNodeOverride(specKey, id, k, v)-> método
--   module:ResetRotationOverrides(specKey)   -> método
--   module.GetRotationDisabled(specKey)      -> FUNÇÃO COM PONTO (sem self)
--
-- Lição do Hunter (H-0196): chamada com "." em método que espera "self"
-- faz o argumento cair em self e o parâmetro chegar nil -> a rotação morre
-- silenciosamente. Este arquivo é a única fonte da verdade; qualquer novo
-- módulo deve usar addon:CreateRotationStore(module, "<prefixo>").
--
-- Armazenamento (por personagem):
--   charDb[<prefixo>Rotation][spec][nodeId] = { enabled=?, condition=?, filter=? }
--   charDb[<prefixo>Order][spec] = { "nodeId", ... }   (ordem customizada)
--
-- Semântica dos overrides:
--   enabled  = true/false  -> habilita/desabilita explicitamente
--   condition = ""         -> condição especial vazia (não volta ao padrão)
--   filter   = {}          -> remove explicitamente o filtro padrão
--   nil (somente no setter) -> remove o override e restaura o valor padrão
local _, addon = ...

-- ---------------------------------------------------------------------------
-- Cópias defensivas: o consumidor nunca recebe referências mutáveis dos nós
-- declarados, do SavedVariables ou da ordem persistida.
-- ---------------------------------------------------------------------------
local function copyValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do
        out[key] = copyValue(item)
    end
    return out
end

local function copyArray(values)
    local out = {}
    if type(values) ~= "table" then return out end
    for i, value in ipairs(values) do out[i] = value end
    return out
end

--- Cria (ou reinstala) a API de overrides no módulo informado.
--- @param module table do módulo de classe (Hunter, Druid, ...)
--- @param prefix string  "hunter" | "druid" (vira charDb.<prefix>Rotation)
function addon:CreateRotationStore(module, prefix)
    if type(module) ~= "table" then return false end
    if type(prefix) ~= "string" or prefix == "" then return false end
    local rotKey = prefix .. "Rotation"
    local orderKey = prefix .. "Order"

    local function charDb()
        return module.charDb
    end

    local function rotationOverrides(specKey)
        local db = charDb()
        return db and db[rotKey] and db[rotKey][specKey] or nil
    end

    local function rotationOrder(specKey)
        local db = charDb()
        return db and db[orderKey] and db[orderKey][specKey] or nil
    end

    local function removeEmptyContainers(db, specKey)
        if not db then return end
        if db[rotKey] and db[rotKey][specKey] and not next(db[rotKey][specKey]) then
            db[rotKey][specKey] = nil
        end
        if db[rotKey] and not next(db[rotKey]) then db[rotKey] = nil end
        if db[orderKey] and db[orderKey][specKey] and not next(db[orderKey][specKey]) then
            db[orderKey][specKey] = nil
        end
        if db[orderKey] and not next(db[orderKey]) then db[orderKey] = nil end
    end

    -- Ordem efetiva dos nós: customizada (^/v no editor) > padrão declarado.
    function module:GetNodeOrder(specKey)
        local order = rotationOrder(specKey)
        if type(order) == "table" and next(order) then return copyArray(order) end
        local spec = module.RotationSpecs and module.RotationSpecs[specKey]
        if not spec then return nil end
        local out = {}
        for _, node in ipairs(spec.nodes or {}) do out[#out + 1] = node.id end
        return out
    end

    function module:SetNodeOrder(specKey, order)
        local db = charDb()
        if not db then return false end

        -- Ordem vazia equivale a nenhuma ordem customizada.
        if type(order) ~= "table" or not next(order) then
            if db[orderKey] then db[orderKey][specKey] = nil end
            if db[orderKey] and not next(db[orderKey]) then db[orderKey] = nil end
            return true
        end

        db[orderKey] = db[orderKey] or {}
        db[orderKey][specKey] = copyArray(order)
        return true
    end

    function module:MoveNode(specKey, nodeId, delta)
        local unpackFn = table.unpack or unpack
        local order = self:GetNodeOrder(specKey)
        if not order then return false end
        order = unpackFn and { unpackFn(order) } or { unpack(order) }
        local index
        for i, id in ipairs(order) do
            if id == nodeId then
                index = i
                break
            end
        end
        if not index then return false end
        local target = index + delta
        if target < 1 or target > #order then return false end
        order[index], order[target] = order[target], order[index]
        self:SetNodeOrder(specKey, order)
        return true
    end

    -- Nós efetivos = nós declarados + overrides do personagem, na ordem final.
    -- Todos os nós são devolvidos, inclusive os desabilitados.
    function module:GetEffectiveNodes(specKey)
        local spec = module.RotationSpecs and module.RotationSpecs[specKey]
        if not spec then return nil end
        local overrides = rotationOverrides(specKey)
        local out = {}
        local defaultIndex = {}

        for i, base in ipairs(spec.nodes or {}) do
            defaultIndex[base.id] = i
            local node = copyValue(base)
            local override = overrides and overrides[base.id]
            if type(override) == "table" then
                if type(override.enabled) == "boolean" then node.enabled = override.enabled end
                if type(override.condition) == "string" then node.condition = override.condition end
                if type(override.filter) == "table" then node.filter = copyValue(override.filter) end
            end
            out[#out + 1] = node
        end

        -- ordem customizada por personagem vence a ordem declarada
        local custom = rotationOrder(specKey)
        if type(custom) == "table" and next(custom) then
            local position = {}
            for i, id in ipairs(custom) do position[id] = i end
            table.sort(out, function(a, b)
                local pa, pb = position[a.id], position[b.id]
                if pa and pb then return pa < pb end
                if pa then return true end
                if pb then return false end
                return (defaultIndex[a.id] or 0) < (defaultIndex[b.id] or 0)
            end)
        end
        return out
    end

    function module:SetNodeOverride(specKey, nodeId, key, value)
        local db = charDb()
        if not db then return false end

        -- Tipos válidos por campo. false é exclusivo de "enabled".
        -- nil é aceito apenas para remover o override existente.
        if key ~= "enabled" and key ~= "condition" and key ~= "filter" then return false end
        if value ~= nil then
            if key == "enabled" and type(value) ~= "boolean" then return false end
            if key == "condition" and type(value) ~= "string" then return false end
            if key == "filter" and type(value) ~= "table" then return false end
        end

        local bySpec = db[rotKey] and db[rotKey][specKey]
        local override = bySpec and bySpec[nodeId]

        if value == nil then
            -- nil remove o override: o valor padrão volta a vigorar.
            if override then
                override[key] = nil
                if not next(override) and bySpec then bySpec[nodeId] = nil end
            end
            removeEmptyContainers(db, specKey)
            return true
        end

        db[rotKey] = db[rotKey] or {}
        db[rotKey][specKey] = db[rotKey][specKey] or {}
        override = db[rotKey][specKey][nodeId]
        if not override then
            override = {}
            db[rotKey][specKey][nodeId] = override
        end

        if key == "filter" then
            override[key] = copyValue(value)
        else
            override[key] = value
        end
        return true
    end

    function module:ResetRotationOverrides(specKey)
        local db = charDb()
        if not db then return false end
        if db[rotKey] then db[rotKey][specKey] = nil end
        if db[orderKey] then db[orderKey][specKey] = nil end
        if db[rotKey] and not next(db[rotKey]) then db[rotKey] = nil end
        if db[orderKey] and not next(db[orderKey]) then db[orderKey] = nil end
        return true
    end

    -- FUNÇÃO COM PONTO (sem self implícito) — chamada pelo Core assim:
    --   module.GetRotationDisabled(specKey)
    -- Representa o estado efetivo, inclusive nós desabilitados por padrão.
    module.GetRotationDisabled = function(specKey)
        local nodes = module:GetEffectiveNodes(specKey)
        if not nodes then return nil end
        local disabled
        for _, node in ipairs(nodes) do
            if node.enabled == false then
                disabled = disabled or {}
                disabled[node.id] = true
            end
        end
        return disabled
    end

    return true
end
