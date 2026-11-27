-- Combat Forever Assistant — Priest options tab (scrollable + shared rotation editor).
local _, addon = ...
local module = addon.modules.PRIEST
local L = addon.L

local function BuildPriestTab(host)
    local parent, setContentHeight = addon.Options.CreateScrollableTab(host)
    local y = -8
    local radioButtons = {}
    local radioValues = { "auto", "SHAD", "DISC", "HOLY" }

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

    local function hint(text)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
        label:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        label:SetText(text)
        y = y - math.max(24, label:GetStringHeight()) - 8
    end

    checkbox(L["priest_enabled"], addon.db.priestEnabled ~= false, function(enabled)
        addon.db.priestEnabled = enabled
    end)

    header(L["priest_spec_header"])
    local specLabels = {
        auto = L["priest_spec_auto"],
        SHAD = L["priest_spec_shad"],
        DISC = L["priest_spec_disc"],
        HOLY = L["priest_spec_holy"],
    }
    local function refreshSpecButtons()
        local selected = addon.charDb and addon.charDb.priestSpec or "auto"
        for value, button in pairs(radioButtons) do
            button:SetChecked(selected == value)
        end
    end
    for _, value in ipairs(radioValues) do
        local specVal = value
        radioButtons[specVal] = checkbox(specLabels[specVal], false, function()
            module:SetSpecOverride(specVal)
            refreshSpecButtons()
        end)
    end
    refreshSpecButtons()

    header(L["priest_heal_mode_header"])
    local healModeButtons = {}
    local healModeValues = { "auto", "always", "off" }
    local healModeLabels = {
        auto   = L["priest_heal_mode_auto"],
        always = L["priest_heal_mode_always"],
        off    = L["priest_heal_mode_off"],
    }
    local function refreshHealModeButtons()
        local selected = module:GetHealMode()
        for value, button in pairs(healModeButtons) do
            button:SetChecked(selected == value)
        end
    end
    for _, value in ipairs(healModeValues) do
        local modeVal = value
        healModeButtons[modeVal] = checkbox(healModeLabels[modeVal], false, function()
            module:SetHealMode(modeVal)
            refreshHealModeButtons()
        end)
    end
    refreshHealModeButtons()
    hint(L["priest_heal_mode_hint"])

    header(L["rotation_editor_header"])
    y = addon.Options.AddRotationEditorControls(parent, y, module.OpenRotationEditor,
        L["priest_rotation_hint"])

    header(L["priest_extra_header"])
    hint(L["priest_extra_hint"])

    local extras = {
        { "fortitude",         "priest_buff_fortitude" },
        { "inner_fire",        "priest_buff_inner_fire" },
        { "divine_spirit",     "priest_buff_divine_spirit" },
        { "shadow_protection", "priest_buff_shadow_protection" },
        { "fear_ward",         "priest_buff_fear_ward" },
    }
    for _, entry in ipairs(extras) do
        local key, labelKey = entry[1], entry[2]
        checkbox(L[labelKey], module:IsExtraSuggestionEnabled(key), function(enabled)
            module:SetExtraSuggestionEnabled(key, enabled)
        end)
    end

    setContentHeight(-y + 12)
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("priest", L["priest_tab"], "PRIEST", BuildPriestTab)
end
