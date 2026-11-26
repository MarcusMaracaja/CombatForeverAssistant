-- Combat Forever Assistant — Hunter module: /cfa tab.
-- Visible only to Hunters: module toggle, spec override and rotation editor button.
local _, addon = ...

local Hunter = addon.modules.HUNTER

local function BuildHunterTab(parent)
    local y = -8

    local function header(text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        fs:SetTextColor(1.0, 0.55, 0.10, 1)
        fs:SetText(text)
        y = y - 22
    end

    local function checkbox(label, getter, setter)
        local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        b:SetWidth(22)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        b:SetChecked(getter() and true or false)
        b:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
        fs:SetText(label)
        y = y - 26
        return b
    end

    -- Toggle: module on/off (off = never suggest Hunter spells)
    checkbox("Habilitar rotação do Hunter",
        function() return not addon.db or addon.db.hunterEnabled ~= false end,
        function(v) if addon.db then addon.db.hunterEnabled = v end end)

    y = y - 6
    header("Spec")

    local radios = {}
    local function refreshRadios()
        local current = (addon.charDb and addon.charDb.hunterSpec) or "auto"
        for _, entry in ipairs(radios) do
            entry.btn:SetChecked(current == entry.value)
        end
    end

    local function radio(label, value)
        local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        b:SetWidth(22)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        b:SetScript("OnClick", function()
            if addon.charDb then
                addon.charDb.hunterSpec = (value == "auto") and nil or value
            end
            refreshRadios()
        end)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
        fs:SetText(label)
        y = y - 26
        radios[#radios + 1] = { btn = b, value = value }
        return b
    end

    radio("Automático (por habilidades/pontos)", "auto")
    radio("Beast Mastery", "BM")
    radio("Marksmanship", "MM")
    radio("Survival", "SV")
    refreshRadios()

    y = y - 8
    header("Rotação")

    local openEditor = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    openEditor:SetWidth(210)
    openEditor:SetHeight(24)
    openEditor:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    openEditor:SetText("Abrir editor de rotação")
    openEditor:SetScript("OnClick", function()
        if Hunter and Hunter.OpenRotationEditor then Hunter.OpenRotationEditor() end
    end)
    y = y - 30

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    hint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("O editor mostra as habilidades da rotação da spec e permite ligar/desligar, reordenar e editar condições de cada uma (por personagem).")
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("hunter", "Hunter", "HUNTER", BuildHunterTab)
end
