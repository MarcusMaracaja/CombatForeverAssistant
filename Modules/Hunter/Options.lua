-- Combat Forever Assistant — Hunter module: /module tab.
-- The class the player is playing gets a tab in the menu; the tab holds the
-- module toggle, the spec override and the button that opens the rotation
-- editor window (Phase 2).
local moduleName, module = ...

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
        function() return module.db.hunterEnabled ~= false end,
        function(v) module.db.hunterEnabled = v end)

    y = y - 6
    header("Spec")

    local function radio(label, value)
        local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        b:SetWidth(22)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        b:SetChecked((module.charDb.hunterSpec or "auto") == value)
        b:SetScript("OnClick", function() module.charDb.hunterSpec = (value == "auto") and nil or value end)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
        fs:SetText(label)
        y = y - 26
        return b
    end

    radio("Automático (por habilidades/pontos)", "auto")
    radio("Beast Mastery", "BM")
    radio("Marksmanship", "MM")
    radio("Survival", "SV")

    y = y - 8
    header(module.L["rotation_editor_header"])
    module.Options.AddRotationEditorControls(parent, y, function()
        if type(module.OpenRotationEditor) == "function" then module.OpenRotationEditor() end
    end)
end

if module.Options and module.Options.RegisterTab then
    module.Options.RegisterTab("hunter", "Hunter", "HUNTER", BuildHunterTab)
end
