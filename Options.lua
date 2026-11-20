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
local SIDE_W = 128
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
    frame = CreateFrame("Frame", "CFA_OptionsFrame", UIParent, "BackdropTemplate")
    frame:SetWidth(PANEL_W)
    frame:SetHeight(PANEL_H)
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
    if addon.db.posX and addon.db.posY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", addon.db.posX, addon.db.posY)
    end

    -- Drag strip (top bar) — the window moves by dragging it
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -52, 0) -- keep clear of the close X
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

    frame:SetScript("OnHide", function()
        if addon.Hunter and addon.Hunter.HidePicker then addon.Hunter.HidePicker() end
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
    b.txt:SetPoint("LEFT", 10, 0)
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
    local classTabs = {}
    local _, playerClass = UnitClass("player")
    for id, tab in pairs(tabs) do
        if not seen[id] and id ~= "equipment"
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

function Options.RegisterTab(id, title, classTag, buildFunc)
    tabs[id] = { title = title, classTag = classTag, build = buildFunc }
    if frame then Options.SelectTab(currentTab) end
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
    if addon.Hunter and addon.Hunter.HidePicker then addon.Hunter.HidePicker() end
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
-- Key button tab
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
    local y = -8
    local KB = addon.KeyButton

    local function header(text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        fs:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
        fs:SetText(text)
        y = y - 22
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

    local function header(text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        fs:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
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

    header(L["opt_visual_mode"])

    local modeRadios = {}
    local function refreshRadios()
        local mode = addon.db.visualMode or "circle"
        for otherMode, btn in pairs(modeRadios) do
            btn:SetChecked(otherMode == mode)
        end
    end

    local function radio(label, mode)
        local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        b:SetWidth(22)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
        modeRadios[mode] = b
        b:SetChecked((addon.db.visualMode or "circle") == mode)
        b:SetScript("OnClick", function()
            addon.db.visualMode = mode
            refreshRadios()
        end)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "RIGHT", 4, 0)
        fs:SetText(label)
        y = y - 26
    end

    radio(L["opt_visual_circle"], "circle")
    radio(L["opt_visual_border"], "border")

    -- Border width (0-60 px), applies to both circle and frame modes
    local bwLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bwLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, y)
    bwLabel:SetText(L["opt_border_width"] .. ":")
    y = y - 18

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0, 60)
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
    local function updateVal(v) valFS:SetText(tostring(math.floor(v)) .. " px") end
    slider:SetScript("OnValueChanged", function(self, v)
        local w = math.floor(v)
        addon.db.borderWidth = w
        updateVal(w)
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(0, math.min(60, self:GetValue() + (delta > 0 and 1 or -1))))
    end)
    slider:SetValue(addon.db.borderWidth or 12)
    y = y - 34

    checkbox(L["opt_key_button"],
        function() return addon.db.keyButton end,
        function(v) addon.db.keyButton = v end)

    checkbox(L["opt_key_button_always"],
        function() return addon.db.keyButtonAlways end,
        function(v)
            addon.db.keyButtonAlways = v
            if v and addon.KeyButton then addon.KeyButton.ShowPlaceholder() end
            if not v and addon.KeyButton then addon.KeyButton.Hide() end
        end)

    checkbox(L["opt_lock_key_button"],
        function() return addon.db.keyButtonLocked end,
        function(v)
            addon.db.keyButtonLocked = v
            if addon.KeyButton then addon.KeyButton.ApplyLock() end
        end)

    checkbox(L["opt_warn_outdated"],
        function() return addon.db.warnOutdated end,
        function(v) addon.db.warnOutdated = v end)

    -- Single highlight color (otherwise colors are per suggestion kind)
    local refreshSwatches
    local singleCheck
    singleCheck = checkbox(L["opt_single_color"],
        function() return addon.db.useSingleColor end,
        function(v)
            addon.db.useSingleColor = v
            if refreshSwatches then refreshSwatches() end
        end)

    local swatches = {}
    refreshSwatches = function()
        local sel = addon.db.singleColorIndex or 2
        for i, s in ipairs(swatches) do
            if addon.db.useSingleColor and i == sel then
                s.sel:Show()
            else
                s.sel:Hide()
            end
        end
    end

    for i, rgb in ipairs(addon.Visuals.PresetColors) do
        local s = CreateFrame("Button", nil, parent)
        s:SetWidth(22)
        s:SetHeight(22)
        s:SetPoint("TOPLEFT", parent, "TOPLEFT", 6 + (i - 1) * 28, y)
        s.sel = s:CreateTexture(nil, "BORDER")
        s.sel:SetTexture("Interface\\Buttons\\WHITE8X8")
        s.sel:SetVertexColor(1, 1, 1, 1)
        s.sel:SetWidth(26)
        s.sel:SetHeight(26)
        s.sel:SetPoint("CENTER", s, "CENTER", 0, 0)
        s.bg = s:CreateTexture(nil, "ARTWORK")
        s.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        s.bg:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        s.bg:SetWidth(22)
        s.bg:SetHeight(22)
        s.bg:SetPoint("CENTER", s, "CENTER", 0, 0)
        s:SetScript("OnClick", function()
            addon.db.useSingleColor = true
            addon.db.singleColorIndex = i
            if singleCheck then singleCheck:SetChecked(true) end
            refreshSwatches()
        end)
        swatches[i] = s
    end
    refreshSwatches()
    y = y - 30

    -- Test highlight: flashes the first spell in your spellbook for 1.5s
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
            local t = 0
            local ff = CreateFrame("Frame")
            ff:SetScript("OnUpdate", function(self, d)
                t = t + d
                if t > 1.5 then
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
            -- no spell in slot 1: flash nothing
            print(L["slash_help"])
        end
    end)
    y = y - 34

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
