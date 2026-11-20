local addonName, addon = ...
local module = addon.modules.SHAMAN
local L = addon.L

local function BuildShamanTab(parent)
    local y = -8
    local radioButtons = {}
    local radioValues = { "auto", "ELE", "ENH", "REST" }

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
        y = y - label:GetStringHeight() - 8
    end

    checkbox(L["shaman_enabled"], addon.db.shamanEnabled ~= false, function(enabled)
        addon.db.shamanEnabled = enabled
    end)

    header(L["shaman_spec_header"])
    local specLabels = {
        auto = L["shaman_spec_auto"],
        ELE = L["shaman_spec_ele"],
        ENH = L["shaman_spec_enh"],
        REST = L["shaman_spec_rest"],
    }
    local function refreshSpecButtons()
        local selected = addon.charDb.shamanSpec or "auto"
        for value, button in pairs(radioButtons) do
            button:SetChecked(selected == value)
        end
    end
    for _, value in ipairs(radioValues) do
        local button = checkbox(specLabels[value], false, function()
            module:SetSpecOverride(value)
            refreshSpecButtons()
        end)
        radioButtons[value] = button
    end
    refreshSpecButtons()

    hint(L["shaman_rotation_hint"])
    header(L["shaman_extra_header"])
    hint(L["shaman_extra_hint"])

    local extras = {
        { "lightning_shield", "shaman_buff_lightning_shield" },
        { "flametongue_weapon", "shaman_buff_flametongue" },
        { "windfury_weapon", "shaman_buff_windfury" },
        { "strength_of_earth", "shaman_buff_strength" },
        { "mana_spring", "shaman_buff_mana_spring" },
    }
    for _, entry in ipairs(extras) do
        local key, labelKey = entry[1], entry[2]
        checkbox(L[labelKey], module:IsExtraSuggestionEnabled(key), function(enabled)
            module:SetExtraSuggestionEnabled(key, enabled)
        end)
    end
end

if addon.Options and addon.Options.RegisterTab then
    addon.Options.RegisterTab("shaman", L["shaman_tab"], "SHAMAN", BuildShamanTab)
end
