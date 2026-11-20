-- Combat Forever Assistant — Druid module: aba no /cfa.
--
-- A aba do Druid tem: ligar/desligar a rotação, o override da spec
-- (Automático / Feral / Equilíbrio / Restauração) e o botão do editor de
-- rotação (compartilhado com o Hunter).
local addonName, addon = ...
local module = addon.Druid

local L = module.L

local function BuildDruidTab(parent)
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

    local function radio(label, value)
        local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        b:SetWidth(22)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        b:SetChecked((module.charDb.druidSpec or "auto") == value)
        b:SetScript("OnClick", function() module.charDb.druidSpec = (value == "auto") and nil or value end)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
        fs:SetText(label)
        y = y - 26
        return b
    end

    checkbox(L["druid_enable"],
        function() return module.db.druidEnabled ~= false end,
        function(v) module.db.druidEnabled = v end)

    y = y - 6
    header(L["druid_spec_header"])

    radio(L["druid_spec_auto"], "auto")
    radio(L["druid_spec_feral"], "FERAL")
    radio(L["druid_spec_balance"], "BAL")
    radio(L["druid_spec_restoration"], "REST")

    y = y - 8
    header(L["druid_rotation_header"])

    local openEditor = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    openEditor:SetWidth(210)
    openEditor:SetHeight(24)
    openEditor:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    openEditor:SetText(L["druid_open_editor"])
    openEditor:SetScript("OnClick", function()
        if module.OpenRotationEditor then module.OpenRotationEditor() end
    end)
    y = y - 30

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["druid_editor_hint"])
end

if module.Options and module.Options.RegisterTab then
    module.Options.RegisterTab("druid", "Druid", "DRUID", BuildDruidTab)
end
