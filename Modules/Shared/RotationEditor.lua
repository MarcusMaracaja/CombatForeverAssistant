-- Combat Forever Assistant — Shared: editor de rotação (genérico).
--
-- Janela escura com acento laranja e X vermelho. Mostra os nós de rotação de
-- uma "spec" (ou forma) e deixa o jogador:
--   * ligar/desligar nós por personagem;
--   * adicionar/remover condições por nó (6 eixos de filtro + predicados
--     especiais) — o "em que condições esta habilidade é chamada";
--   * clicar no ícone do nó para piscar o botão na barra de ação (teste);
--   * reordenar a cadeia com ^ / v.
--
-- É genérico de propósito: o Hunter e o Druid usam a MESMA janela, cada um
-- com seus próprios dados (specs, predicados e chaves no charDb).
--
-- Uso:
--   local editor = addon:CreateRotationEditor(module, {
--       frameName = "CFA_HunterRotationEditor",
--       scrollName = "CFA_HunterRotationEditorScroll",
--       pickerName = "CFA_HunterRotationPicker",
--       title = "Editor de rotação — Hunter",
--       tabs = { { "BM", "Beast Mastery" }, ... },
--       defaultSpec = "SV",
--   })
--   module.OpenRotationEditor = editor.Open
--
-- Lição do Hunter (H-0186/H-0197): frames globais com nome fixo colidem
-- quando dois módulos abrem o editor -> o prefixo vem da configuração.
local _, addon = ...

local PANEL_W, PANEL_H = 560, 440
local ROW_H = 46
local ORANGE = { 1.0, 0.55, 0.10 }
-- Opaco: o painel translúcido anterior deixava a janela de trás vazar
local BG = { 0.02, 0.02, 0.02, 1.0 }

function addon:CreateRotationEditor(mod, cfg)
    if type(mod) ~= "table" then return nil end
    cfg = cfg or {}

    local frame, scrollChild
    local picker = nil
    local tabButtons = {}
    local cardFrames = {}
    local currentSpec = cfg.defaultSpec or "SV"

    local function resolveCurrentSpec()
        local detected
        if type(cfg.resolveSpec) == "function" then
            local ok, value = pcall(cfg.resolveSpec, mod)
            if ok then detected = value end
        elseif mod.DetectSpec then
            local ok, value = pcall(mod.DetectSpec, mod)
            if ok then detected = value end
        end
        if detected and mod.RotationSpecs and mod.RotationSpecs[detected] then
            return detected
        end
        return cfg.defaultSpec or currentSpec
    end
    local selectSpec -- forward declaration (os botões re-renderizam a aba)

    local L = mod.L or addon.L

    local PTBR = (GetLocale and GetLocale() or "enUS") == "ptBR"
    local function Loc(key, fallback)
        if L and L[key] then return L[key] end
        return fallback or key
    end

    local function applyBackdrop(f, r, g, b, a)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = true, tileSize = 8, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            f:SetBackdropColor(r, g, b, a)
            f:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.55)
        end
    end

    local function specIcon(spellID)
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
            if ok and tex then return tex end
        end
        if type(GetSpellTexture) == "function" then
            local ok, tex = pcall(GetSpellTexture, spellID)
            if ok and tex then return tex end
        end
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local function colorOf(c)
        local map = {
            Damage    = { 1.0, 0.27, 0.27 },
            AoE       = { 1.0, 0.55, 0.10 },
            Interrupt = { 1.0, 1.0,  0.15 },
            Defensive = { 0.2, 1.0,  0.2  },
            Utility   = { 0.2, 0.8,  1.0  },
            Aqua      = { 0.2, 0.9,  0.9  },
            Yellow    = { 1.0, 0.95, 0.3  },
            Orange    = { 1.0, 0.6,  0.15 },
            Pink      = { 1.0, 0.5,  0.75 },
            White     = { 1.0, 1.0,  1.0  },
            Purple    = { 0.7, 0.45, 1.0  },
            Green     = { 0.35, 1.0, 0.35 },
        }
        return map[c] or map.Utility
    end

    -- -----------------------------------------------------------------------
    -- Texto de condição (2ª linha do cartão)
    -- -----------------------------------------------------------------------
    local function stripAxisNumber(label)
        local result = (label or ""):gsub("^%d+%.%s*", "")
        return result
    end

    local function axisOptionLabel(axis, value)
        for _, opt in ipairs(axis.options or {}) do
            if opt[1] == value then
                local lk = opt[2]
                return (L and L[lk]) or lk
            end
        end
        return tostring(value)
    end

    local function NodeConditionText(node)
        local parts = {}
        if node.condition and node.condition ~= "" then
            local p = mod.RotationPredicates and mod.RotationPredicates[node.condition]
            parts[#parts + 1] = Loc("rot_special_prefix", "Especial: ") .. ((p and p.label) or node.condition)
        end
        if type(node.filter) == "table" then
            for _, axis in ipairs(addon.FilterAxes or {}) do
                local v = tonumber(node.filter[axis.key]) or 0
                if v ~= 0 then
                    local axisName = stripAxisNumber(Loc(axis.labelKey, axis.key))
                    parts[#parts + 1] = axisName .. ": " .. axisOptionLabel(axis, v)
                end
            end
        end
        if #parts == 0 then return Loc("rot_no_condition", "- sem condições -") end
        return Loc("rot_conditions_prefix", "Condições: ") .. table.concat(parts, " · ")
    end

    local function getFilterTable(node)
        if type(node.filter) == "table" then
            local f = {}
            for k, v in pairs(node.filter) do f[k] = v end
            return f
        end
        return {}
    end

    -- -----------------------------------------------------------------------
    -- Picker popup (o menu flutuante de condições)
    -- -----------------------------------------------------------------------
    local function GetPicker()
        if picker then return picker end
        -- parentado à janela do editor: esconde/move junto, sempre acima
        picker = CreateFrame("Frame", cfg.pickerName or "CFA_RotationPicker", frame or UIParent, "BackdropTemplate")
        picker:SetWidth(250)
        picker:SetFrameStrata("TOOLTIP")
        picker:EnableMouse(true)
        applyBackdrop(picker, 0.04, 0.04, 0.04, 1.0)
        local solidBg = picker:CreateTexture(nil, "BACKGROUND")
        solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        solidBg:SetVertexColor(0.04, 0.04, 0.04, 1.0)
        solidBg:SetAllPoints()
        picker.rows = {}
        local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        picker.title = title
        local sf = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 8, -26)
        sf:SetPoint("BOTTOMRIGHT", -28, 8)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll() or 0
            local childH = picker.child and picker.child:GetHeight() or 0
            local visible = self:GetHeight() or 0
            local maxScroll = math.max(0, childH - visible)
            self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - (delta > 0 and 30 or -30))))
        end)
        picker.scroll = sf
        local child = CreateFrame("Frame", nil, sf)
        child:SetWidth(212)
        sf:SetScrollChild(child)
        picker.child = child
        if type(UISpecialFrames) == "table" and picker.GetName then
            tinsert(UISpecialFrames, picker:GetName())
        end
        return picker
    end

    local function RebuildPickerRows(p, titleText, getItems, afterAction)
        p.title:SetText(titleText)
        for _, r in ipairs(p.rows) do r:Hide(); r:SetParent(nil) end
        p.rows = {}
        local y = 0
        for _, item in ipairs(getItems()) do
            local row = CreateFrame(item.header and "Frame" or "Button", nil, p.child)
            local h = item.header and 16 or 20
            row:SetHeight(h)
            row:SetPoint("TOPLEFT", p.child, "TOPLEFT", 0, -y)
            row:SetWidth(206)
            if item.header then
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                fs:SetPoint("LEFT", 2, 0)
                fs:SetText(item.header)
            else
                row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.mark:SetPoint("LEFT", 6, 0)
                row.mark:SetText(item.checked and "|cffff8800●|r" or "")
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("LEFT", 20, 0)
                fs:SetPoint("RIGHT", -2, 0)
                fs:SetJustifyH("LEFT")
                fs:SetText(item.label)
                row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
                local hl = row:GetHighlightTexture()
                if hl then hl:SetVertexColor(0.35, 0.2, 0.05, 0.5) end
                row:SetScript("OnClick", function()
                    item.action()
                    if afterAction then afterAction() end
                    RebuildPickerRows(p, titleText, getItems, afterAction)
                end)
            end
            y = y + h + 1
            p.rows[#p.rows + 1] = row
        end
        p.child:SetHeight(math.max(1, y))
        p:SetHeight(math.min(400, math.max(64, 34 + y)))
    end

    local function ShowPicker(anchorBtn, titleText, getItems, afterAction)
        local p = GetPicker()
        if p:IsShown() and p.owner == anchorBtn then
            p:Hide()
            return
        end
        p.owner = anchorBtn
        RebuildPickerRows(p, titleText, getItems, afterAction)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
        p:Show()
    end

    local function sortedPredicateKeys(preds)
        local keys = {}
        for k in pairs(preds) do keys[#keys + 1] = k end
        table.sort(keys)
        return keys
    end

    local function BuildAddItems(specKey, node)
        local items = {}
        local function Header(t) items[#items + 1] = { header = t } end
        local function Item(label, active, action)
            items[#items + 1] = { label = label, checked = active and true or false, action = action }
        end
        for _, axis in ipairs(addon.FilterAxes or {}) do
            Header(Loc(axis.labelKey, axis.key))
            for _, opt in ipairs(axis.options) do
                local value, lk = opt[1], opt[2]
                local label = (L and L[lk]) or lk
                local cur = type(node.filter) == "table" and tonumber(node.filter[axis.key]) or 0
                Item(label, cur == value, function()
                    local f = getFilterTable(node)
                    if tonumber(f[axis.key]) == value then
                        f[axis.key] = nil
                    else
                        f[axis.key] = value
                    end
                    if next(f) then
                        mod:SetNodeOverride(specKey, node.id, "filter", f)
                    else
                        -- {} limpa explicitamente o filtro padrão; nil restauraria
                        -- o filtro herdado do nó.
                        mod:SetNodeOverride(specKey, node.id, "filter", {})
                    end
                end)
            end
        end
        local preds = mod.RotationPredicates or {}
        Header(Loc("rot_special_header", "Especial"))
        Item(Loc("rot_always", "Sempre"), (not node.condition or node.condition == ""), function()
            mod:SetNodeOverride(specKey, node.id, "condition", "")
        end)
        for _, key in ipairs(sortedPredicateKeys(preds)) do
            local p = preds[key]
            Item((p and p.label) or key, node.condition == key, function()
                mod:SetNodeOverride(specKey, node.id, "condition", key)
            end)
        end
        Header("------------------------")
        Item(Loc("rot_clear_all", "Remover todas as condições"), false, function()
            mod:SetNodeOverride(specKey, node.id, "condition", "")
            mod:SetNodeOverride(specKey, node.id, "filter", {})
        end)
        return items
    end

    local function BuildRemoveItems(specKey, node)
        local items = {}
        local function Header(t) items[#items + 1] = { header = t } end
        local function Item(label, action)
            items[#items + 1] = { label = label, action = action }
        end
        local any = false
        if node.condition and node.condition ~= "" then
            local p = mod.RotationPredicates and mod.RotationPredicates[node.condition]
            Item(Loc("rot_special_prefix", "Especial: ") .. ((p and p.label) or node.condition), function()
                mod:SetNodeOverride(specKey, node.id, "condition", "")
            end)
            any = true
        end
        if type(node.filter) == "table" then
            for _, axis in ipairs(addon.FilterAxes or {}) do
                local v = tonumber(node.filter[axis.key])
                if v and v ~= 0 then
                    local axisName = stripAxisNumber(Loc(axis.labelKey, axis.key))
                    Item(axisName .. ": " .. axisOptionLabel(axis, v), function()
                        local f = getFilterTable(node)
                        f[axis.key] = nil
                        if next(f) then
                            mod:SetNodeOverride(specKey, node.id, "filter", f)
                        else
                            mod:SetNodeOverride(specKey, node.id, "filter", {})
                        end
                    end)
                    any = true
                end
            end
        end
        if not any then Header(Loc("rot_none_active", "(nenhuma condição ativa)")) end
        Header("------------------------")
        Item(Loc("rot_clear_all", "Remover todas as condições"), function()
            mod:SetNodeOverride(specKey, node.id, "condition", "")
            mod:SetNodeOverride(specKey, node.id, "filter", {})
        end)
        return items
    end

    -- -----------------------------------------------------------------------
    -- Cartões
    -- -----------------------------------------------------------------------
    local function cardDesaturate(iconBtn, disabled)
        local n = iconBtn:GetNormalTexture()
        if n and n.SetDesaturated then n:SetDesaturated(disabled and true or false) end
    end

    local function createCard(parent, specKey, node, y)
        local card = CreateFrame("Frame", nil, parent)
        card:SetHeight(ROW_H)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        card.bg = card:CreateTexture(nil, "BACKGROUND")
        card.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        card.bg:SetVertexColor(0.09, 0.09, 0.09, 1.0)
        card.bg:SetAllPoints()

        local cb = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
        cb:SetWidth(20)
        cb:SetHeight(20)
        cb:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -2)

        -- Ícone = clique para piscar o botão da barra (teste)
        local iconBtn = CreateFrame("Button", nil, card)
        iconBtn:SetWidth(26)
        iconBtn:SetHeight(26)
        iconBtn:SetPoint("TOPLEFT", cb, "TOPRIGHT", 2, 0)
        local tex = specIcon(node.spellID)
        iconBtn:SetNormalTexture(tex)
        iconBtn:SetPushedTexture(tex)
        iconBtn:SetHighlightTexture(tex, "ADD")
        local n = iconBtn:GetNormalTexture()
        if n then n:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        local pTex = iconBtn:GetPushedTexture()
        if pTex then pTex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        local hTex = iconBtn:GetHighlightTexture()
        if hTex then hTex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        iconBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tostring(node.name or node.id), 1, 1, 1)
            GameTooltip:AddLine(Loc("rot_click_test", "Clique para testar o flash na barra."), 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        iconBtn:SetScript("OnClick", function()
            addon:FlashSpell(node.spellID, node.color or "Utility")
        end)

        local rgb = colorOf(node.color)
        local hex = string.format("%02x%02x%02x", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
        local nameFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 6, -3)
        nameFS:SetWidth(170)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")

        local addBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        addBtn:SetWidth(26)
        addBtn:SetHeight(20)
        addBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 240, -2)
        addBtn:SetText("+")

        local removeBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        removeBtn:SetWidth(26)
        removeBtn:SetHeight(20)
        removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 3, 0)
        removeBtn:SetText("-")

        -- reordenar: move este nó uma posição para cima/baixo na cadeia
        local up = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        up:SetWidth(18)
        up:SetHeight(18)
        up:SetPoint("TOPLEFT", card, "TOPLEFT", 302, -2)
        up:SetText("^")
        local down = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        down:SetWidth(18)
        down:SetHeight(18)
        down:SetPoint("TOPLEFT", card, "TOPLEFT", 324, -2)
        down:SetText("v")
        up:SetScript("OnClick", function()
            if mod.MoveNode then mod:MoveNode(specKey, node.id, -1) end
            selectSpec(specKey)
        end)
        down:SetScript("OnClick", function()
            if mod.MoveNode then mod:MoveNode(specKey, node.id, 1) end
            selectSpec(specKey)
        end)

        local condFS = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        condFS:SetPoint("TOPLEFT", card, "TOPLEFT", 46, -24)
        condFS:SetWidth(PANEL_W - 70)
        condFS:SetJustifyH("LEFT")
        condFS:SetJustifyV("MIDDLE")

        local function refresh()
            local effective = {}
            if mod.GetEffectiveNodes then
                local nodes = mod:GetEffectiveNodes(specKey)
                if nodes then
                    for _, nd in ipairs(nodes) do effective[nd.id] = nd end
                end
            end
            local cur = effective[node.id] or node
            local disabled = (cur.enabled == false)
            cb:SetChecked(not disabled)
            cardDesaturate(iconBtn, disabled)
            nameFS:SetText((disabled and "|cff888888" or ("|cff" .. hex)) .. (node.name or node.id) .. "|r")
            condFS:SetText(NodeConditionText(cur))
        end

        cb:SetScript("OnClick", function(self)
            -- Persistir o booleano real: true precisa habilitar um nó cujo
            -- padrão esteja desabilitado; false o desabilita explicitamente.
            mod:SetNodeOverride(specKey, node.id, "enabled", self:GetChecked() and true or false)
            refresh()
        end)
        local function freshNode()
            local nodes = (mod.GetEffectiveNodes and mod:GetEffectiveNodes(specKey)) or {}
            for _, nd in ipairs(nodes) do if nd.id == node.id then return nd end end
            return node
        end
        addBtn:SetScript("OnClick", function(self)
            ShowPicker(self, Loc("rot_add_condition", "Adicionar condição"),
                function() return BuildAddItems(specKey, freshNode()) end, refresh)
        end)
        removeBtn:SetScript("OnClick", function(self)
            ShowPicker(self, Loc("rot_remove_condition", "Remover condição"),
                function() return BuildRemoveItems(specKey, freshNode()) end, refresh)
        end)

        refresh()
        return card
    end

    local function layoutSpec()
        -- Um popup continuar aberto não pode permitir que o jogador reaplique
        -- overrides antigos depois de
        -- trocar de aba, reordenar ou restaurar a rotação padrão.
        if picker then
            picker:Hide()
            picker.owner = nil
        end
        if not scrollChild then return end
        for _, c in ipairs(cardFrames) do c:Hide(); c:SetParent(nil) end
        cardFrames = {}
        local nodes = (mod.GetEffectiveNodes and mod:GetEffectiveNodes(currentSpec)) or nil
        if not nodes then
            nodes = mod.RotationSpecs and mod.RotationSpecs[currentSpec] and mod.RotationSpecs[currentSpec].nodes or {}
        end
        local y = 0
        for _, n in ipairs(nodes) do
            cardFrames[#cardFrames + 1] = createCard(scrollChild, currentSpec, n, y)
            y = y - (ROW_H + 4)
        end
        scrollChild:SetHeight(math.max(-y, 1))
    end

    function selectSpec(specKey)
        currentSpec = specKey
        for k, b in pairs(tabButtons) do
            local active = (k == currentSpec)
            b.bg:SetVertexColor(active and ORANGE[1] or 0.09, active and ORANGE[2] * 0.45 or 0.09, 0, 1.0)
            b.txt:SetTextColor(active and 1.0 or 0.9, active and 0.9 or 0.9, active and 0.6 or 0.9, 1)
        end
        layoutSpec()
    end

    local function createPanel()
        frame = CreateFrame("Frame", cfg.frameName or "CFA_RotationEditor", UIParent, "BackdropTemplate")
        frame:SetWidth(PANEL_W)
        frame:SetHeight(PANEL_H)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:SetToplevel(true)
        frame:EnableMouse(true)
        if type(UISpecialFrames) == "table" and frame.GetName then
            tinsert(UISpecialFrames, frame:GetName())
        end
        applyBackdrop(frame, BG[1], BG[2], BG[3], BG[4])
        -- fundo sólido explícito (o backdrop pode falhar em silêncio)
        local solidBg = frame:CreateTexture(nil, "BACKGROUND")
        solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        solidBg:SetVertexColor(BG[1], BG[2], BG[3], 1)
        solidBg:SetAllPoints()
        -- fechar o editor também fecha o menu flutuante
        frame:SetScript("OnHide", function()
            if picker then
                picker:Hide()
                picker.owner = nil
            end
        end)

        -- Barra de arrasto
        local drag = CreateFrame("Frame", nil, frame)
        drag:SetPoint("TOPLEFT", 0, 0)
        drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, 0)
        drag:SetHeight(34)
        drag:EnableMouse(true)
        drag:SetScript("OnMouseDown", function(self)
            local mx, my = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local cx, cy = frame:GetCenter()
            if cx and cy then
                self.isDown = true
                self.dx = cx - mx / scale
                self.dy = cy - my / scale
            end
        end)
        drag:SetScript("OnMouseUp", function(self) self.isDown = false end)
        drag:SetScript("OnUpdate", function(self)
            if not self.isDown then return end
            if not IsMouseButtonDown("LeftButton") then self.isDown = false return end
            local mx, my = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local ux, uy = UIParent:GetCenter()
            local nx = mx / scale + self.dx - ux
            local ny = my / scale + self.dy - uy
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
        end)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        title:SetText(cfg.title or "Editor de rotação")

        local close = CreateFrame("Button", nil, frame)
        close:SetWidth(26)
        close:SetHeight(26)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetFrameLevel(frame:GetFrameLevel() + 20)
        close.txt = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        close.txt:SetPoint("CENTER", 0, 1)
        close.txt:SetText("X")
        close.txt:SetTextColor(1, 0.25, 0.25, 1)
        close:SetScript("OnClick", function() frame:Hide() end)
        close:SetScript("OnEnter", function(self) self.txt:SetTextColor(1, 0.45, 0.45, 1) end)
        close:SetScript("OnLeave", function(self) self.txt:SetTextColor(1, 0.25, 0.25, 1) end)

        -- Abas de spec/forma
        local defs = cfg.tabs or {}
        local sx = 14
        local gap = 8
        local tabWidth = 140
        if #defs > 0 then
            local available = PANEL_W - 28 - gap * (#defs - 1)
            tabWidth = math.min(140, math.max(72, math.floor(available / #defs)))
        end
        for _, def in ipairs(defs) do
            local key, label = def[1], def[2]
            local b = CreateFrame("Button", nil, frame)
            b:SetWidth(tabWidth)
            b:SetHeight(30)
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -40)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            b.bg:SetVertexColor(0.09, 0.09, 0.09, 1.0)
            b.bg:SetAllPoints()
            b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.txt:SetPoint("CENTER", 0, 0)
            b.txt:SetText(label)
            b:SetScript("OnClick", function() selectSpec(key) end)
            tabButtons[key] = b
            sx = sx + tabWidth + gap
        end

        local scrollFrame = CreateFrame("ScrollFrame", cfg.scrollName or "CFA_RotationEditorScroll", frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 14, -76)
        scrollFrame:SetPoint("BOTTOMRIGHT", -32, 46)
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(PANEL_W - 70)
        scrollChild:SetHeight(400)
        scrollFrame:SetScrollChild(scrollChild)

        local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        reset:SetWidth(230)
        reset:SetHeight(24)
        reset:SetPoint("BOTTOMLEFT", 14, 12)
        reset:SetText("Restaurar rotação padrão")
        reset:SetScript("OnClick", function()
            if mod.ResetRotationOverrides then
                mod:ResetRotationOverrides(currentSpec)
            end
            selectSpec(currentSpec)
        end)

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMRIGHT", -14, 16)
        hint:SetText("Clique para ligar/desligar.")

        -- spec/forma inicial: a detectada pelo módulo (se houver)
        currentSpec = resolveCurrentSpec()
        selectSpec(currentSpec)
    end

    local function Open()
        if not frame then createPanel() end
        currentSpec = resolveCurrentSpec()
        selectSpec(currentSpec)
        frame:Raise()
        frame:Show()
    end

    return { Open = Open }
end
