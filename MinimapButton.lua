-- Combat Forever Assistant — Minimap button (classic WoW minimap button art).
-- Left click toggles the options window; drag around the minimap edge to move it.

local addonName, addon = ...

local MinimapButton = {}
addon.Minimap = MinimapButton

local frame

local function createFrame()
    frame = CreateFrame("Button", "CFA_MinimapButton", Minimap)
    frame:SetSize(31, 31)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(8)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function position()
        local angle = (addon.charDb and addon.charDb.minimapAngle) or 210
        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Classic WoW minimap button chrome: metal ring + dark background + icon.
    local overlay = frame:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(19, 19)
    frame.icon:SetTexture("Interface\\AddOns\\CombatForeverAssistant\\Textures\\CFA_Minimap.tga")
    frame.icon:SetTexCoord(0, 1, 0, 1)
    frame.icon:SetPoint("TOPLEFT", 6, -6)

    frame:SetMovable(true)
    frame:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)
    frame:SetScript("OnDragStop", function(self)
        self.dragging = false
        local cx, cy = Minimap:GetCenter()
        local mx, my = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        mx, my = mx / scale, my / scale
        if cx and cy then
            if addon.charDb then
                addon.charDb.minimapAngle = math.deg(math.atan2(my - cy, mx - cx))
            end
            position()
        end
    end)
    frame:SetScript("OnUpdate", function(self)
        if self.dragging then
            local cx, cy = Minimap:GetCenter()
            local mx, my = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            mx, my = mx / scale, my / scale
            if cx and cy then
                if addon.charDb then
                    addon.charDb.minimapAngle = math.deg(math.atan2(my - cy, mx - cx))
                end
                position()
            end
        end
    end)
    frame:SetScript("OnClick", function()
        if addon.Options then addon.Options.Toggle() end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Combat Forever Assistant", 1, 0.82, 0.2)
        GameTooltip:AddLine("/cfa", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    position()
    return frame
end

function MinimapButton.Refresh()
    if addon.db.minimapHidden then
        if frame then frame:Hide() end
        return
    end
    if not frame then createFrame() end
    frame:Show()
end
