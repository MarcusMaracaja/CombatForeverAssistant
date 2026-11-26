-- Combat Forever Assistant — Druid module: /cfa tab.
-- Clean options: enable toggle, spec override (Auto/Balance/Feral/Restoration),
-- rotation editor button, and Extra buff toggles. No forced Feral form selector
-- (the player chooses Cat or Bear form in-game and Feral adapts automatically).
local _, addon = ...

local Druid = addon.modules.DRUID
local L = addon.L

local function BuildDruidTab(host)
    local parent, setContentHeight = addon.Options.CreateScrollableTab(host)
    local y = -8
    local specButtons = {}

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
            onClick(self:GetChecked() and true or false)
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

    checkbox(L["druid_enabled"], not addon.db or addon.db.druidEnabled ~= false, function(enabled)
        if addon.db then addon.db.druidEnabled = enabled end
    end)

    header(L["druid_spec_header"])
    local specValues = { "auto", "BAL", "FER", "REST" }
    local specLabels = {
        auto = L["druid_spec_auto"],
        BAL  = L["druid_spec_balance"],
        FER  = L["druid_spec_feral"],
        REST = L["druid_spec_restoration"],
    }

    local function refreshSpecButtons()
        local selected = (addon.charDb and addon.charDb.druidSpec) or "auto"
        for value, button in pairs(specButtons) do button:SetChecked(selected == value) end
    end
    for _, value in ipairs(specValues) do
        local specVal = value
        specButtons[specVal] = checkbox(specLabels[specVal], false, function()
            Druid:SetSpecOverride(specVal)
            refreshSpecButtons()
        end)
    end
    refreshSpecButtons()

    header(L["rotation_editor_header"])
    y = addon.Options.AddRotationEditorControls(parent, y, function()
        if Druid and Druid.OpenRotationEditor then Druid.OpenRotationEditor() end
    end, L["druid_rotation_hint"])

    header(L["druid_extra_header"])
    local extraHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    extraHint:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    extraHint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    extraHint:SetJustifyH("LEFT")
    extraHint:SetWordWrap(true)
    extraHint:SetText(L["druid_extra_hint"])
    y = y - extraHint:GetStringHeight() - 8
    checkbox(L["druid_extra_mark"], Druid:IsExtraSuggestionEnabled("mark"), function(enabled)
        Druid:SetExtraSuggestionEnabled("mark", enabled)
    end)
    checkbox(L["druid_extra_thorns"], Druid:IsExtraSuggestionEnabled("thorns"), function(enabled)
        Druid:SetExtraSuggestionEnabled("thorns", enabled)
    end)
    setContentHeight(-y + 12)
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("druid", L["druid_tab"], "DRUID", BuildDruidTab)
end
