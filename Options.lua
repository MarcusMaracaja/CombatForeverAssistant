-- Combat Forever Assistant — Options window.
-- Left sidebar of tabs (General + class modules + About), red close X,
-- dark panel with orange accent — the same visual language as before,
-- re-implemented from scratch.

local addonName, addon = ...
local L = addon.L

local Options = {}
addon.Options = Options

local frame
local tabs = {}        -- id -> { title, classTag, build }
local tabButtons = {}
local currentTab = "general"

local PANEL_W, PANEL_H = 520, 420
local MAX_PANEL_MARGIN = 32
local SIDE_W = 128
local CONTENT_W, CONTENT_H = PANEL_W - SIDE_W - 18, PANEL_H - 54
local SCROLLBAR_W = 24
local ORANGE = { 1.0, 0.55, 0.10 }
local BG = { 0.02, 0.02, 0.02, 1.0 }

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
    else
        -- fallback for clients without backdrop support
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(r, g, b, a)
        bg:SetAllPoints(f)
    end
end

local function createPanel()
    local uiWidth = tonumber(UIParent:GetWidth()) or (PANEL_W + MAX_PANEL_MARGIN)
    local uiHeight = tonumber(UIParent:GetHeight()) or (PANEL_H + MAX_PANEL_MARGIN)
    local maxWidth = math.max(PANEL_W, uiWidth - MAX_PANEL_MARGIN)
    local maxHeight = math.max(PANEL_H, uiHeight - MAX_PANEL_MARGIN)
    local panelWidth = math.max(PANEL_W, math.min(maxWidth, tonumber(addon.db.optionsWidth) or PANEL_W))
    local panelHeight = math.max(PANEL_H, math.min(maxHeight, tonumber(addon.db.optionsHeight) or PANEL_H))

    frame = CreateFrame("Frame", "CFA_OptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(panelWidth, panelHeight)
    frame:SetResizable(true)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(PANEL_W, PANEL_H, maxWidth, maxHeight)
    else
        if type(frame.SetMinResize) == "function" then frame:SetMinResize(PANEL_W, PANEL_H) end
        if type(frame.SetMaxResize) == "function" then frame:SetMaxResize(maxWidth, maxHeight) end
    end
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetAlpha(0.85)
    frame:EnableMouse(true)
    applyBackdrop(frame, BG[1], BG[2], BG[3], BG[4])
    -- belt-and-suspenders: explicit solid background (works even if the
    -- client's backdrop path silently no-ops)
    local solidBg = frame:CreateTexture(nil, "BACKGROUND")
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(BG[1], BG[2], BG[3], 1)
    solidBg:SetAllPoints()

    local artBg = frame:CreateTexture(nil, "BORDER")
    artBg:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Textures\\CombatForeverAssistant_Background.tga")
    artBg:SetSize(PANEL_W - 32, (PANEL_W - 32) * 768 / 1408)
    artBg:SetPoint("CENTER", frame, "CENTER", 0, -12)
    artBg:SetTexCoord(0, 1, 116 / 512, 395 / 512)
    artBg:SetAlpha(0.68)
    local function updateArtSize(width, height)
        local artWidth = math.min(width - 32, (height - 60) * 1408 / 768)
        artWidth = math.max(1, artWidth)
        artBg:SetSize(artWidth, artWidth * 768 / 1408)
    end
    frame:SetScript("OnSizeChanged", function(_, width, height)
        updateArtSize(width, height)
    end)
    updateArtSize(panelWidth, panelHeight)

    if addon.db.posX and addon.db.posY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", addon.db.posX, addon.db.posY)
    end

    -- Drag strip (top bar) — the window moves by dragging it
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -74, 0) -- keep clear of info "i" and close X
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
        addon.db.posX, addon.db.posY = nx, ny
    end)

    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    title:SetText(L["opt_title"])

    -- Red close X (always visible; ESC also closes)
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

    -- Info "i" button (explains the currently selected tab)
    local infoBtn = Options.CreateInfoButton(frame, function()
        local tab = tabs[currentTab]
        local tabTitle = (tab and tab.title) or tostring(currentTab or "")
        local helpKey = "help_" .. tostring(currentTab or "")
        local body = (tab and tab.helpText) or L[helpKey] or L["help_default"]
        return tabTitle .. " — " .. (L["info_help_suffix"] or "Ajuda"), body
    end)
    infoBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 0, -40)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDE_W)
    sidebar.bg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    sidebar.bg:SetVertexColor(0.06, 0.06, 0.06, 0.95)
    sidebar.bg:SetAllPoints()
    frame.sidebar = sidebar

    -- Content host
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", SIDE_W + 8, -44)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.content = content

    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 20)
    local gripMarks = {}
    for i = 1, 3 do
        local mark = resizeGrip:CreateTexture(nil, "OVERLAY")
        mark:SetTexture("Interface\\Buttons\\WHITE8X8")
        mark:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.65)
        mark:SetSize(2, 2)
        mark:SetPoint("BOTTOMRIGHT", resizeGrip, "BOTTOMRIGHT", -2 - (i - 1) * 4, 2 + (i - 1) * 4)
        gripMarks[i] = mark
    end
    resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resizeGrip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        frame:StopMovingOrSizing()
        local width, height = frame:GetSize()
        addon.db.optionsWidth = math.floor(width + 0.5)
        addon.db.optionsHeight = math.floor(height + 0.5)
    end)
    resizeGrip:SetScript("OnEnter", function()
        for _, mark in ipairs(gripMarks) do mark:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1) end
    end)
    resizeGrip:SetScript("OnLeave", function()
        for _, mark in ipairs(gripMarks) do mark:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.65) end
    end)

    frame:SetScript("OnHide", function()
        Options.HideHelp()
        if addon.RotationEditor and addon.RotationEditor.HidePicker then addon.RotationEditor.HidePicker() end
    end)
    tinsert(UISpecialFrames, "CFA_OptionsFrame")
    return frame
end

local function makeTabButton(id, index)
    local b = CreateFrame("Button", nil, frame.sidebar)
    b:SetWidth(SIDE_W)
    b:SetHeight(32)
    b:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 0, -(index - 1) * 32)
    b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.txt:SetPoint("LEFT", 8, 0)
    b.txt:SetPoint("RIGHT", -6, 0)
    b.txt:SetJustifyH("LEFT")
    b.txt:SetWordWrap(true)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.bg:SetVertexColor(0.09, 0.09, 0.09, 0)
    b.bg:SetAllPoints()
    b:SetScript("OnClick", function() Options.SelectTab(id) end)
    b:SetScript("OnEnter", function(self)
        if currentTab ~= id then self.bg:SetVertexColor(0.18, 0.10, 0.04, 0.9) end
    end)
    b:SetScript("OnLeave", function(self)
        if currentTab ~= id then self.bg:SetVertexColor(0.09, 0.09, 0.09, 0) end
    end)
    tabButtons[id] = b
    return b
end

local function refreshTabButtons()
    local order = { "general", "key" }
    local seen = { general = true, key = true, about = true }
    if tabs.assist then
        order[#order + 1] = "assist"
        seen.assist = true
    end
    local classTabs = {}
    local _, playerClass = UnitClass("player")
    for id, tab in pairs(tabs) do
        if not seen[id] and id ~= "equipment" and id ~= "consumables"
            and (not tab.classTag or tab.classTag == playerClass) then
            classTabs[#classTabs + 1] = id
        end
    end
    table.sort(classTabs, function(a, b)
        return (tabs[a].title or a) < (tabs[b].title or b)
    end)
    for _, id in ipairs(classTabs) do
        seen[id] = true
        order[#order + 1] = id
    end
    if tabs.equipment then order[#order + 1] = "equipment" end
    if tabs.consumables then order[#order + 1] = "consumables" end
    table.insert(order, "about")

    for i, id in ipairs(order) do
        local b = tabButtons[id] or makeTabButton(id, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 0, -(i - 1) * 32)
        b.txt:SetText(tabs[id] and tabs[id].title or id)
        if currentTab == id then
            b.bg:SetVertexColor(ORANGE[1], ORANGE[2] * 0.45, 0, 0.55)
            b.txt:SetTextColor(1, 0.9, 0.6, 1)
        else
            b.bg:SetVertexColor(0.09, 0.09, 0.09, 0)
            b.txt:SetTextColor(0.9, 0.9, 0.9, 1)
        end
        b:Show()
    end
    for id, b in pairs(tabButtons) do
        local inOrder = false
        for _, oid in ipairs(order) do if oid == id then inOrder = true break end end
        if not inOrder then b:Hide() end
    end
end

-- ---------------------------------------------------------------------------
-- Shared Help Popup & "i" Info Button (used by all /cfa tabs & secondary windows)
-- ---------------------------------------------------------------------------
local helpPopup

local function getHelpPopup()
    if helpPopup then return helpPopup end
    helpPopup = CreateFrame("Frame", "CFA_HelpPopup", UIParent, "BackdropTemplate")
    helpPopup:SetWidth(340)
    helpPopup:SetFrameStrata("TOOLTIP")
    helpPopup:SetToplevel(true)
    helpPopup:SetClampedToScreen(true)
    helpPopup:SetAlpha(1)
    helpPopup:EnableMouse(true)
    applyBackdrop(helpPopup, 0.04, 0.04, 0.04, 1.0)
    local solidBg = helpPopup:CreateTexture(nil, "BACKGROUND")
    solidBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    solidBg:SetVertexColor(0.04, 0.04, 0.04, 1.0)
    solidBg:SetAllPoints()

    local title = helpPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", -34, -10)
    title:SetJustifyH("LEFT")
    title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    helpPopup.title = title

    local close = CreateFrame("Button", nil, helpPopup)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.txt = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.txt:SetPoint("CENTER", 0, 1)
    close.txt:SetText("X")
    close.txt:SetTextColor(1, 0.25, 0.25, 1)
    close:SetScript("OnClick", function() helpPopup:Hide() end)

    local sep = helpPopup:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.35)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 10, -28)
    sep:SetPoint("TOPRIGHT", -10, -28)

    local body = helpPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 12, -36)
    body:SetPoint("TOPRIGHT", -12, -36)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    helpPopup.body = body

    helpPopup:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "CFA_HelpPopup") end
    return helpPopup
end

function Options.HideHelp()
    if helpPopup then helpPopup:Hide() end
end

function Options.ShowHelp(anchorBtn, titleText, bodyText)
    local p = getHelpPopup()
    if p:IsShown() and p.owner == anchorBtn and p.lastTitle == titleText then
        p:Hide()
        return
    end
    p.owner = anchorBtn
    p.lastTitle = titleText
    p.title:SetText(tostring(titleText or "Ajuda"))
    p.body:SetText(tostring(bodyText or L["help_default"] or ""))
    local textHeight = p.body:GetStringHeight() or 80
    p:SetHeight(math.max(90, math.min(460, textHeight + 52)))
    p:ClearAllPoints()
    p:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
    p:Raise()
    p:Show()
end

function Options.CreateInfoButton(parent, getHelpFn)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(22, 22)
    btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    applyBackdrop(btn, 0.08, 0.14, 0.18, 0.95)
    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("CENTER", 0, 0)
    txt:SetText("i")
    txt:SetTextColor(0.35, 0.85, 1.0, 1)
    btn.txt = txt
    btn:SetScript("OnEnter", function(self)
        self.txt:SetTextColor(1, 0.9, 0.4, 1)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["info_btn_tooltip"] or "Clique para ver para que serve esta aba", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.txt:SetTextColor(0.35, 0.85, 1.0, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    btn:SetScript("OnClick", function(self)
        if GameTooltip then GameTooltip:Hide() end
        if type(getHelpFn) == "function" then
            local t, b = getHelpFn()
            Options.ShowHelp(self, t, b)
        end
    end)
    return btn
end

function Options.RegisterTab(id, title, classTag, buildFunc, helpText)
    tabs[id] = { title = title, classTag = classTag, build = buildFunc, helpText = helpText }
    if frame then Options.SelectTab(currentTab) end
end

function Options.CreateScrollableTab(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(CONTENT_W - SCROLLBAR_W - 4, CONTENT_H)
    scroll:SetScrollChild(content)

    local function updateLayout()
        local width, height = parent:GetSize()
        if not width or width < 100 then width = CONTENT_W end
        if not height or height < 100 then height = CONTENT_H end
        scroll:SetSize(width, height)
        content:SetWidth(math.max(100, width - SCROLLBAR_W - 4))
    end
    parent:HookScript("OnSizeChanged", updateLayout)
    parent:HookScript("OnShow", updateLayout)
    updateLayout()
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maximum = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - delta * 32)))
    end)
    return content, function(height)
        content:SetHeight(math.max(1, height))
    end
end

function Options.AddRotationEditorControls(parent, y, openEditor, hintText)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(210, 24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    button:SetText(L["rotation_editor_open"])
    button:SetScript("OnClick", function()
        if type(openEditor) == "function" then
            openEditor()
        else
            print(L["rotation_editor_unavailable"])
        end
    end)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y - 30)
    hint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y - 30)
    hint:SetHeight(34)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText(hintText or L["rotation_editor_button_hint"])
    return y - 72
end

local contentFrames = {}

local function getContentFrame(id)
    if not contentFrames[id] then
        local f = CreateFrame("Frame", nil, frame.content)
        f:SetAllPoints(frame.content)
        f:Hide()
        contentFrames[id] = f
        local tab = tabs[id]
        if tab and tab.build then tab.build(f) end
    end
    return contentFrames[id]
end

function Options.SelectTab(id)
    Options.HideHelp()
    if addon.RotationEditor and addon.RotationEditor.HidePicker then addon.RotationEditor.HidePicker() end
    currentTab = id
    if not frame then createPanel() end
    for otherId, f in pairs(contentFrames) do f:Hide() end
    local f = getContentFrame(id)
    f:Show()
    refreshTabButtons()
end

function Options.Toggle()
    if not frame then
        createPanel()
        Options.SelectTab("general")
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- ---------------------------------------------------------------------------
-- Button tab
-- ---------------------------------------------------------------------------
local BG_SWATCHES = {
    { 0.05, 0.05, 0.05 }, -- near-black (default)
    { 0.00, 0.00, 0.00 }, -- black
    { 0.12, 0.12, 0.12 }, -- gray
    { 0.30, 0.06, 0.06 }, -- dark red
    { 0.06, 0.28, 0.06 }, -- dark green
    { 0.06, 0.08, 0.35 }, -- dark blue
}

local function eq3(a, b)
    a, b = a or { 0, 0, 0 }, b or { 0, 0, 0 }
    return math.abs((a[1] or 0) - (b[1] or 0)) < 0.01
        and math.abs((a[2] or 0) - (b[2] or 0)) < 0.01
        and math.abs((a[3] or 0) - (b[3] or 0)) < 0.01
end

function buildKeyButtonTab(parent)
    local tabFrame = parent
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetSize(CONTENT_W, CONTENT_H)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(CONTENT_W - SCROLLBAR_W - 4, 760)
    scroll:SetScrollChild(content)
    local function updateScrollLayout()
        local width, height = tabFrame:GetSize()
        if not width or width < 100 then width = CONTENT_W end
        if not height or height < 100 then height = CONTENT_H end
        scroll:SetSize(width, height)
        content:SetWidth(math.max(100, width - SCROLLBAR_W - 4))
    end
    tabFrame:HookScript("OnSizeChanged", updateScrollLayout)
    tabFrame:HookScript("OnShow", updateScrollLayout)
    updateScrollLayout()
    content:Show()
    scroll:Show()
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maximum = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maximum, current - delta * 32)))
    end)

    parent = content
    local y = -8
    local KB = addon.KeyButton

    local function header(text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        fs:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        fs:SetText(text)
        y = y - 22
    end

    local function checkbox(label, getter, setter)
        local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        button:SetWidth(22)
        button:SetHeight(22)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        button:SetChecked(getter() and true or false)
        button:SetScript("OnClick", function(self)
            setter(self:GetChecked() and true or false)
        end)
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        text:SetText(label)
        y = y - 26
        return button
    end

    local function makeSlider(minV, maxV, initial, onChange, fmt)
        local slider = CreateFrame("Slider", nil, parent)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(1)
        pcall(function() slider:SetObeyStepOnDrag(true) end)
        slider:SetWidth(170)
        slider:SetHeight(18)
        slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture("Interface\\Buttons\\WHITE8X8")
        track:SetVertexColor(0.18, 0.18, 0.18, 0.95)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        track:SetPoint("CENTER", slider, "CENTER", 0, 0)
        track:SetHeight(6)

        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetWidth(12)
            thumb:SetHeight(18)
            thumb:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        end

        local valFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valFS:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valFS:SetTextColor(1, 0.9, 0.6, 1)
        local function updateVal(v) valFS:SetText(fmt(math.floor(v))) end
        slider:SetScript("OnValueChanged", function(self, v)
            local w = math.floor(v)
            onChange(w)
            updateVal(w)
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue(math.max(minV, math.min(maxV, self:GetValue() + (delta > 0 and 1 or -1))))
        end)
        slider:SetValue(initial)
        y = y - 34
        return slider
    end

    local function swatchRow(colors, getRgb, setRgb)
        local btns = {}
        local function refresh()
            local cur = getRgb()
            for i, b in ipairs(btns) do
                if eq3(cur, colors[i]) then b.sel:Show() else b.sel:Hide() end
            end
        end
        for i, rgb in ipairs(colors) do
            local b = CreateFrame("Button", nil, parent)
            b:SetWidth(22)
            b:SetHeight(22)
            b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + (i - 1) * 28, y)
            b.sel = b:CreateTexture(nil, "BORDER")
            b.sel:SetTexture("Interface\\Buttons\\WHITE8X8")
            b.sel:SetVertexColor(1, 1, 1, 1)
            b.sel:SetWidth(26)
            b.sel:SetHeight(26)
            b.sel:SetPoint("CENTER", b, "CENTER", 0, 0)
            b.bg = b:CreateTexture(nil, "ARTWORK")
            b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            b.bg:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
            b.bg:SetWidth(22)
            b.bg:SetHeight(22)
            b.bg:SetPoint("CENTER", b, "CENTER", 0, 0)
            b:SetScript("OnClick", function()
                setRgb(rgb)
                refresh()
            end)
            btns[i] = b
        end
        refresh()
        y = y - 30
        return refresh
    end

    -- Highlight and key-button behavior
    header(L["opt_visual_mode"])
    local modeRadios = {}
    local function refreshRadios()
        local mode = addon.db.visualMode or "circle"
        for otherMode, button in pairs(modeRadios) do
            button:SetChecked(otherMode == mode)
        end
    end
    local function radio(label, mode)
        local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        button:SetWidth(22)
        button:SetHeight(22)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        modeRadios[mode] = button
        button:SetChecked((addon.db.visualMode or "circle") == mode)
        button:SetScript("OnClick", function()
            addon.db.visualMode = mode
            refreshRadios()
        end)
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        text:SetText(label)
        y = y - 26
    end
    radio(L["opt_visual_circle"], "circle")
    radio(L["opt_visual_border"], "border")
    radio(L["opt_visual_flame"], "flame")
    radio(L["opt_visual_lightning"], "lightning")
    radio(L["opt_visual_zoom"], "zoom")

    local borderLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    borderLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    borderLabel:SetText(L["opt_border_width"] .. ":")
    y = y - 18
    makeSlider(0, 60, addon.db.borderWidth or 12,
        function(width) addon.db.borderWidth = width end,
        function(width) return tostring(width) .. " px" end)

    checkbox(L["opt_key_button"],
        function() return addon.db.keyButton end,
        function(value) addon.db.keyButton = value end)
    checkbox(L["opt_key_button_always"],
        function() return addon.db.keyButtonAlways end,
        function(value)
            addon.db.keyButtonAlways = value
            if value and addon.KeyButton then addon.KeyButton.ShowPlaceholder() end
            if not value and addon.KeyButton then addon.KeyButton.Hide() end
        end)
    checkbox(L["opt_lock_key_button"],
        function() return addon.db.keyButtonLocked end,
        function(value)
            addon.db.keyButtonLocked = value
            if addon.KeyButton then addon.KeyButton.ApplyLock() end
        end)
    y = y - 8

    -- Size
    header(L["opt_key_size"] .. ":")
    local sizeSlider = makeSlider(24, 128, addon.db.keySize or 46,
        function(w) addon.db.keySize = w; KB.ApplyLook() end,
        function(v) return tostring(v) .. " px" end)

    -- Font
    header(L["opt_key_font"] .. ":")
    local fontBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    fontBtn:SetWidth(230)
    fontBtn:SetHeight(22)
    fontBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    fontBtn:SetText(KB.FontDisplayName(addon.db.keyFont))
    fontBtn:SetScript("OnClick", function()
        local list = KB.FontList
        local idx = 1
        for i, f in ipairs(list) do
            if f.file == addon.db.keyFont then idx = i break end
        end
        idx = idx % #list + 1
        addon.db.keyFont = list[idx].file
        fontBtn:SetText(list[idx].name)
        KB.ApplyLook()
    end)
    y = y - 30

    -- Background color
    header(L["opt_key_bg"] .. ":")
    local refreshBg = swatchRow(BG_SWATCHES,
        function() return addon.db.keyBgColor end,
        function(rgb) addon.db.keyBgColor = { rgb[1], rgb[2], rgb[3] }; KB.ApplyLook() end)

    -- Background transparency
    header(L["opt_key_alpha"] .. ":")
    local alphaSlider = makeSlider(0, 100, math.floor((addon.db.keyBgAlpha or 0.72) * 100),
        function(v) addon.db.keyBgAlpha = v / 100; KB.ApplyLook() end,
        function(v) return tostring(v) .. "%" end)

    -- Text color
    header(L["opt_key_text_color"] .. ":")
    local refreshText = swatchRow(addon.Visuals.PresetColors,
        function() return addon.db.keyTextColor end,
        function(rgb) addon.db.keyTextColor = { rgb[1], rgb[2], rgb[3] }; KB.ApplyLook() end)

    local refreshSwatches
    local singleCheck
    singleCheck = checkbox(L["opt_single_color"],
        function() return addon.db.useSingleColor end,
        function(value)
            addon.db.useSingleColor = value
            if refreshSwatches then refreshSwatches() end
        end)

    local swatches = {}
    refreshSwatches = function()
        local selected = addon.db.singleColorIndex or 2
        for i, swatch in ipairs(swatches) do
            if addon.db.useSingleColor and i == selected then
                swatch.sel:Show()
            else
                swatch.sel:Hide()
            end
        end
    end
    for i, rgb in ipairs(addon.Visuals.PresetColors) do
        local swatch = CreateFrame("Button", nil, parent)
        swatch:SetWidth(22)
        swatch:SetHeight(22)
        swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + (i - 1) * 28, y)
        swatch.sel = swatch:CreateTexture(nil, "BORDER")
        swatch.sel:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch.sel:SetVertexColor(1, 1, 1, 1)
        swatch.sel:SetWidth(26)
        swatch.sel:SetHeight(26)
        swatch.sel:SetPoint("CENTER", swatch, "CENTER", 0, 0)
        swatch.bg = swatch:CreateTexture(nil, "ARTWORK")
        swatch.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch.bg:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        swatch.bg:SetWidth(22)
        swatch.bg:SetHeight(22)
        swatch.bg:SetPoint("CENTER", swatch, "CENTER", 0, 0)
        swatch:SetScript("OnClick", function()
            addon.db.useSingleColor = true
            addon.db.singleColorIndex = i
            if singleCheck then singleCheck:SetChecked(true) end
            refreshSwatches()
        end)
        swatches[i] = swatch
    end
    refreshSwatches()
    y = y - 30

    local test = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    test:SetWidth(140)
    test:SetHeight(22)
    test:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    test:SetText(L["opt_test"])
    test:SetScript("OnClick", function()
        local _, id = GetActionInfo(1)
        if id and addon.Visuals then
            addon.Visuals.Show(id, "Utility")
            if addon.KeyButton then
                local had = addon.KeyButton.ShowFor(id)
                if not had then print(L["key_button_no_key"]) end
            end
            local elapsed = 0
            local timer = CreateFrame("Frame")
            timer:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed > 1.5 then
                    addon.Visuals.Hide()
                    if addon.KeyButton then
                        if addon.db.keyButtonAlways then
                            addon.KeyButton.ShowPlaceholder()
                        else
                            addon.KeyButton.Hide()
                        end
                    end
                    self:SetScript("OnUpdate", nil)
                end
            end)
        else
            print(L["slash_help"])
        end
    end)
    y = y - 34

    -- Hint
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    hint:SetTextColor(0.65, 0.65, 0.65, 1)
    hint:SetText(L["opt_key_hint"])
    y = y - 20

    -- Reset
    local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    reset:SetWidth(180)
    reset:SetHeight(24)
    reset:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    reset:SetText(L["opt_key_reset"])
    reset:SetScript("OnClick", function()
        KB.ResetAll()
        sizeSlider:SetValue(addon.db.keySize)
        fontBtn:SetText(KB.FontDisplayName(addon.db.keyFont))
        alphaSlider:SetValue(math.floor(addon.db.keyBgAlpha * 100))
        refreshBg()
        refreshText()
    end)
end

-- ---------------------------------------------------------------------------
-- General tab
-- ---------------------------------------------------------------------------
function buildGeneralTab(parent)
    local y = -8

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

    checkbox(L["opt_warn_outdated"],
        function() return addon.db.warnOutdated end,
        function(v) addon.db.warnOutdated = v end)

    local save = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    save:SetWidth(140)
    save:SetHeight(24)
    save:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    save:SetText(L["opt_save"])
    save:SetScript("OnClick", function()
        -- SavedVariables are written on logout/reload; this forces user-visible feedback.
        print(L["opt_save_done"])
    end)
end

-- ---------------------------------------------------------------------------
-- About tab
-- ---------------------------------------------------------------------------
function buildAboutTab(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -8)
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -8)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    local version = "?"
    local getMetadata = GetAddOnMetadata
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        getMetadata = C_AddOns.GetAddOnMetadata
    end
    if type(getMetadata) == "function" then
        local ok, value = pcall(getMetadata, addonName, "Version")
        if ok and type(value) == "string" and value ~= "" then version = value end
    end
    fs:SetText(L["about_body"] .. "\n\n" .. L["about_version"] .. ": " .. version)
end

-- Register built-in tabs eagerly so class modules can rely on Options existing.
Options.RegisterTab("general", L["opt_tab_general"], nil, buildGeneralTab)
Options.RegisterTab("key", L["opt_tab_key"], nil, buildKeyButtonTab)
Options.RegisterTab("about", L["opt_tab_about"], nil, buildAboutTab)
