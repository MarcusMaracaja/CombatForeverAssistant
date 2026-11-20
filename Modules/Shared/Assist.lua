local _, addon = ...
local L = addon.L
local frame = CreateFrame("Frame")
local statusText

local legacyEnabled = addon.db.assistSmartTabEnabled ~= false
if addon.db.assistTabEnabled == nil then addon.db.assistTabEnabled = legacyEnabled end
if addon.db.assistShiftTabEnabled == nil then addon.db.assistShiftTabEnabled = legacyEnabled end

local function isInPvPInstance()
    if type(IsInInstance) ~= "function" then return false end
    local inInstance, instanceType = IsInInstance()
    return inInstance == true and instanceType == "pvp"
end

local function refreshStatus()
    if not statusText then return end
    local anyEnabled = addon.db.assistTabEnabled ~= false
        or addon.db.assistShiftTabEnabled ~= false
    if not anyEnabled then
        statusText:SetText(L["assist_status_disabled"])
        statusText:SetTextColor(0.7, 0.7, 0.7)
    elseif isInPvPInstance() then
        statusText:SetText(L["assist_status_active"])
        statusText:SetTextColor(0.3, 1, 0.3)
    else
        statusText:SetText(L["assist_status_inactive"])
        statusText:SetTextColor(1, 0.8, 0.2)
    end
end

local function updateOverride()
    ClearOverrideBindings(frame)
    if isInPvPInstance() then
        if addon.db.assistTabEnabled ~= false then
            SetOverrideBinding(frame, true, "TAB", "TARGETNEARESTENEMYPLAYER")
        end
        if addon.db.assistShiftTabEnabled ~= false then
            SetOverrideBinding(frame, true, "SHIFT-TAB", "TARGETPREVIOUSENEMYPLAYER")
        end
    end
    refreshStatus()
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:SetScript("OnEvent", updateOverride)

local function BuildAssistTab(host)
    local parent = host
    local y = -8

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    title:SetTextColor(1, 0.55, 0.1, 1)
    title:SetText(L["assist_title"])
    y = y - 28

    local function addCheckbox(setting, labelKey)
        local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        checkbox:SetSize(22, 22)
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        checkbox:SetChecked(addon.db[setting] ~= false)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        label:SetText(L[labelKey])
        checkbox:SetScript("OnClick", function(self)
            addon.db[setting] = self:GetChecked() and true or false
            updateOverride()
        end)
        y = y - 34
    end

    addCheckbox("assistTabEnabled", "assist_nearest_enabled")
    addCheckbox("assistShiftTabEnabled", "assist_previous_enabled")

    local description = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    description:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)
    description:SetText(L["assist_description"])
    y = y - description:GetStringHeight() - 12

    statusText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    statusText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y)
    statusText:SetJustifyH("LEFT")
    refreshStatus()
end

addon.Options.RegisterTab("assist", L["assist_tab"], nil, BuildAssistTab)
