local _, addon = ...
local module = addon.modules.DRUID
local L = addon.L

addon.RotationEditor.Attach(module, {
    title = L["druid_tab"],
    storageKey = "druidRotation",
    specOrder = { "BAL", "CAT", "BEAR", "REST" },
})

local function BuildDruidTab(host)
    local parent, setContentHeight = addon.Options.CreateScrollableTab(host)
    local y = -8
    local specButtons = {}
    local formButtons = {}

    local function header(text)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        label:SetTextColor(1.0, 0.55, 0.10, 1)
        label:SetText(text)
        y = y - 22
    end

    local function checkbox(text, checked, onClick)
        local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        button:SetSize(22, 22)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        button:SetChecked(checked and true or false)
        button:SetScript("OnClick", function(self)
            onClick(self:GetChecked() == true)
        end)

        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", button, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        label:SetText(text)
        y = y - 25
        return button
    end

    checkbox(L["druid_enabled"], addon.db.druidEnabled ~= false, function(enabled)
        addon.db.druidEnabled = enabled
    end)

    header(L["druid_spec_header"])
    local specValues = { "auto", "BAL", "FER", "REST" }
    local specLabels = {
        auto = L["druid_spec_auto"],
        BAL = L["druid_spec_balance"],
        FER = L["druid_spec_feral"],
        REST = L["druid_spec_restoration"],
    }

    local function refreshSpecButtons()
        local selected = addon.charDb.druidSpec or "auto"
        for value, button in pairs(specButtons) do button:SetChecked(selected == value) end
    end
    for _, value in ipairs(specValues) do
        specButtons[value] = checkbox(specLabels[value], false, function()
            module:SetSpecOverride(value)
            refreshSpecButtons()
        end)
    end
    refreshSpecButtons()

    header(L["druid_feral_form"])
    local function refreshFormButtons()
        local selected = addon.charDb.druidFeralForm or "CAT"
        for value, button in pairs(formButtons) do button:SetChecked(selected == value) end
    end
    for _, entry in ipairs({
        { "CAT", L["druid_feral_cat"] },
        { "BEAR", L["druid_feral_bear"] },
    }) do
        local value, label = entry[1], entry[2]
        formButtons[value] = checkbox(label, false, function()
            module:SetFeralFormPreference(value)
            refreshFormButtons()
        end)
    end
    refreshFormButtons()

    header(L["rotation_editor_header"])
    y = addon.Options.AddRotationEditorControls(parent, y, module.OpenRotationEditor,
        L["druid_rotation_hint"])

    header(L["druid_extra_header"])
    local extraHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    extraHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    extraHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    extraHint:SetJustifyH("LEFT")
    extraHint:SetWordWrap(true)
    extraHint:SetText(L["druid_extra_hint"])
    y = y - extraHint:GetStringHeight() - 8
    checkbox(L["druid_extra_mark"], module:IsExtraSuggestionEnabled("mark"), function(enabled)
        module:SetExtraSuggestionEnabled("mark", enabled)
    end)
    checkbox(L["druid_extra_thorns"], module:IsExtraSuggestionEnabled("thorns"), function(enabled)
        module:SetExtraSuggestionEnabled("thorns", enabled)
    end)
    setContentHeight(-y + 12)
end

addon.Options.RegisterTab("druid", L["druid_tab"], "DRUID", BuildDruidTab)
