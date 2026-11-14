local _, FT = ...
local Controls = {}
Controls.__index = Controls
FT.Controls = Controls

local function backdrop(panel)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.08, 0.09, 0.08, 0.97)
    panel:SetBackdropBorderColor(0.30, 0.45, 0.32, 1)
    panel:EnableMouse(true)
end

function Controls:SetMapShown(shown)
    if self.root:IsShown() == shown then return end
    self.root:SetShown(shown)
    if not shown then self.panel:Hide() end
end

function Controls:Refresh()
    local settings = FT.db.settings
    self.show:SetChecked(settings.showTrails)
    self.record:SetText(settings.recording and "Pause recording" or "Resume recording")
    for id, button in pairs(self.colours) do
        button:SetChecked(settings.trailColour == id)
    end
    local status = FT.suspended and "Loading / outside world"
        or (not settings.recording and "Paused")
        or (FT.recorder and FT.recorder.status) or "Waiting for position"
    local count = FT.store and FT.store.character.pointCount or 0
    local oldest = FT.store and FT.store:OldestTime()
    local storage = string.format("%s points retained", count)
    if oldest then storage = storage .. "\nOldest: " .. date("%d %b %Y", oldest) end
    if FT.overlay and FT.overlay.truncated then
        storage = storage .. "\nShowing newest sections (display limit)"
    end
    self.status:SetText(status .. "\n" .. storage)
end

function Controls.New(map)
    local self = setmetatable({}, Controls)
    -- Anchor to the map, but keep interactive frames outside its descendant tree
    -- so native gamepad navigation never enlists these addon-owned controls.
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetAllPoints(map)
    root:SetFrameStrata("DIALOG")
    root:Hide()
    local button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    button:SetSize(72, 22)
    button:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -12, -12)
    button:SetFrameStrata("DIALOG")
    button:SetText("Trails")
    local panel = CreateFrame("Frame", nil, root, "BackdropTemplate")
    panel:SetSize(280, 276)
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(button:GetFrameLevel() + 1)
    backdrop(panel)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Forever Trails  " .. FT.Compat.Version())
    local show = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    show:SetPoint("TOPLEFT", 8, -32)
    local label = show:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", show, "RIGHT", 2, 0)
    label:SetText("Show trails")
    show:SetScript("OnClick", function() FT.SetVisible(show:GetChecked()) end)
    local colourLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colourLabel:SetPoint("TOPLEFT", 12, -76)
    colourLabel:SetText("Trail colour")
    self.colours = {}
    -- An inline single-selection preset grid avoids the shared MenuProxy focus
    -- path used by native dropdowns on Forever's gamepad UI.
    for i, preset in ipairs(FT.colourPresets) do
        local id = preset.id
        local choice = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        choice:SetSize(24, 24)
        choice:SetPoint("TOPLEFT", 8 + ((i - 1) % 3) * 87, -90 - math.floor((i - 1) / 3) * 28)
        local name = choice:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("LEFT", choice, "RIGHT", 0, 0)
        name:SetText(preset.name)
        choice:SetScript("OnClick", function() FT.SetTrailColour(id); self:Refresh() end)
        self.colours[id] = choice
    end
    local record = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    record:SetSize(145, 22)
    record:SetPoint("TOPLEFT", 12, -150)
    record:SetScript("OnClick", function() FT.SetRecording(not FT.db.settings.recording) end)
    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(95, 22)
    clear:SetPoint("LEFT", record, "RIGHT", 8, 0)
    clear:SetText("Clear history")
    clear:SetScript("OnClick", function() FT.ConfirmClear() end)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 12, -185)
    status:SetWidth(256)
    status:SetJustifyH("LEFT")
    self.root, self.panel, self.button = root, panel, button
    self.show, self.record, self.status = show, record, status
    panel:SetScript("OnShow", function() self:Refresh() end)
    button:SetScript("OnClick", function() panel:SetShown(not panel:IsShown()) end)
    panel:Hide()
    return self
end

function Controls.NewConfirmation(accept)
    -- No StaticPopup or gamepad frame registration: deletion is a private dialog.
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(360, 110)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    backdrop(panel)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 14, -14)
    text:SetWidth(332)
    text:SetText("Delete all Forever Trails history for this character?")
    local delete = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    delete:SetSize(100, 22)
    delete:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 14)
    delete:SetText("Delete")
    delete:SetScript("OnClick", accept)
    local cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    cancel:SetSize(100, 22)
    cancel:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 4, 14)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() panel:Hide() end)
    panel.delete, panel.cancel = delete, cancel
    panel:Hide()
    return panel
end
