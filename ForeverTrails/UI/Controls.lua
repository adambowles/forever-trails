local _, FT = ...
local Controls = {}
Controls.__index = Controls
FT.Controls = Controls

function Controls:Refresh()
    local settings = FT.db.settings
    self.show:SetChecked(settings.showTrails)
    self.record:SetText(settings.recording and "Pause recording" or "Resume recording")
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
    local button = CreateFrame("Button", nil, map, "UIPanelButtonTemplate")
    button:SetSize(72, 22)
    button:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -12, -12)
    button:SetFrameStrata("DIALOG")
    button:SetText("Trails")
    local panel = CreateFrame("Frame", nil, map, "BackdropTemplate")
    panel:SetSize(280, 190)
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(button:GetFrameLevel() + 1)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.08, 0.09, 0.08, 0.97)
    panel:SetBackdropBorderColor(0.30, 0.45, 0.32, 1)
    panel:EnableMouse(true)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Forever Trails  " .. FT.Compat.Version())
    local show = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    show:SetPoint("TOPLEFT", 8, -32)
    local label = show:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", show, "RIGHT", 2, 0)
    label:SetText("Show trails")
    show:SetScript("OnClick", function() FT.SetVisible(show:GetChecked()) end)
    local record = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    record:SetSize(145, 22)
    record:SetPoint("TOPLEFT", 12, -72)
    record:SetScript("OnClick", function() FT.SetRecording(not FT.db.settings.recording) end)
    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(95, 22)
    clear:SetPoint("LEFT", record, "RIGHT", 8, 0)
    clear:SetText("Clear history")
    clear:SetScript("OnClick", function() FT.ConfirmClear() end)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 12, -105)
    status:SetWidth(256)
    status:SetJustifyH("LEFT")
    self.panel, self.button, self.show, self.record, self.status = panel, button, show, record, status
    panel:SetScript("OnShow", function() self:Refresh() end)
    button:SetScript("OnClick", function() panel:SetShown(not panel:IsShown()) end)
    panel:Hide()
    return self
end
