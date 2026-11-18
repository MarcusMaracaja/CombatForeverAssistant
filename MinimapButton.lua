-- Combat Forever Assistant — Minimap button (self-drawn, no libraries).
-- Left click toggles the options window; drag around the minimap edge to move it.

local addonName, addon = ...

local MinimapButton = {}
addon.Minimap = MinimapButton

local frame

local function createFrame()
    frame = CreateFrame("Button", "CFA_MinimapButton", Minimap)
    frame:SetWidth(34)
    frame:SetHeight(34)
    frame:SetFrameStrata("MEDIUM")
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
    frame.icon:SetWidth(22)
    frame.icon:SetHeight(22)
    frame.icon:SetPoint("CENTER", 0, 0)

    frame.ring = addon.Visuals and addon.Visuals.DashRing(frame, 16, 2.5, { 1.0, 0.55, 0.10 }, 12)
        or nil -- Visuals always loads before this file; fallback kept for safety

    local function position()
        local angle = (addon.charDb and addon.charDb.minimapAngle) or 210
        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

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
            local angle = math.deg(math.atan2(my - cy, mx - cx))
            if addon.charDb then addon.charDb.minimapAngle = angle end
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
                local angle = math.deg(math.atan2(my - cy, mx - cx))
                if addon.charDb then addon.charDb.minimapAngle = angle end
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
