-- Combat Forever Assistant — Warrior options tab (scrollable + shared rotation editor).
local _, addon = ...
local module = addon.modules.WARRIOR
local L = addon.L

local function BuildWarriorTab(host)
    local parent, setContentHeight = addon.Options.CreateScrollableTab(host)
    local y = -8
    local radioButtons = {}
    local radioValues = { "auto", "ARMS", "FURY", "PROT" }

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

    checkbox(L["warrior_enabled"], addon.db.warriorEnabled ~= false, function(enabled)
        addon.db.warriorEnabled = enabled
    end)

    header(L["warrior_spec_header"])
    local specLabels = {
        auto = L["warrior_spec_auto"],
        ARMS = L["warrior_spec_arms"],
        FURY = L["warrior_spec_fury"],
        PROT = L["warrior_spec_prot"],
    }
    local function refreshSpecButtons()
        local selected = addon.charDb and addon.charDb.warriorSpec or "auto"
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

    header(L["rotation_editor_header"])
    y = addon.Options.AddRotationEditorControls(parent, y, module.OpenRotationEditor,
        L["warrior_rotation_hint"])

    header(L["warrior_extra_header"])
    hint(L["warrior_extra_hint"])

    local extras = {
        { "battle_shout",     "warrior_buff_battle_shout" },
        { "commanding_shout", "warrior_buff_commanding_shout" },
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
    addon.Options.RegisterTab("warrior", L["warrior_tab"], "WARRIOR", BuildWarriorTab)
end
