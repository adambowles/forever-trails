local _, FT = ...
local Overlay = {}
Overlay.__index = Overlay
FT.Overlay = Overlay
local MAP_ART_FRAME_LEVEL = "PIN_FRAME_LEVEL_MAP_HIGHLIGHT"

local function newBuffer(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:EnableMouse(false)
    frame:Hide()
    return { frame = frame, lines = {}, used = 0, truncated = false }
end

function Overlay.New(map)
    local self = setmetatable({ map = map, used = 0, dirty = true }, Overlay)
    self.frame = CreateFrame("Frame", nil, map:GetCanvas())
    self.frame:SetAllPoints(map:GetCanvas())
    self.front, self.back = newBuffer(map:GetCanvas()), newBuffer(map:GetCanvas())
    self.lines = self.front.lines
    self:ApplyFrameLevel()
    self.frame:EnableMouse(false)
    -- The existing map ScrollFrame clips its scrolling canvas and all descendants.
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = function() self:Reset(); self:MarkDirty() end
    provider.OnShow = function() self:MarkDirty() end
    provider.OnHide = function() self:Reset() end
    provider.RefreshAllData = function() self:MarkDirty() end
    provider.RemoveAllData = function() self:Reset() end
    provider.OnCanvasScaleChanged = function() self:MarkDirty() end
    provider.OnCanvasSizeChanged = function() self:Reset(); self:MarkDirty() end
    map:AddDataProvider(provider)
    self.provider = provider
    self:MarkDirty()
    return self
end

function Overlay:ApplyFrameLevel()
    if InCombatLockdown() then return false end
    -- Read the existing ordering without modifying Blizzard's definitions or pins.
    -- The stock map's debug band separates this last art layer from normal markers.
    local level = self.map:GetPinFrameLevelsManager():GetValidFrameLevel(MAP_ART_FRAME_LEVEL) + 1
    if level == self.appliedFrameLevel then return true end
    self.frame:SetFrameLevel(level)
    self.front.frame:SetFrameLevel(level)
    self.back.frame:SetFrameLevel(level)
    self.appliedFrameLevel = level
    return true
end

function Overlay:Reset()
    self.job, self.truncated = nil, false
    self.frame:SetScript("OnUpdate", nil)
    for _, buffer in ipairs({ self.front, self.back }) do
        buffer.frame:Hide()
        buffer.used, buffer.truncated = 0, false
    end
    self.used = 0
end

function Overlay:ApplyColour()
    local colour = FT.GetTrailColour()
    for _, buffer in ipairs({ self.front, self.back }) do
        for i = 1, buffer.used do
            buffer.lines[i].trail:SetColorTexture(colour.r, colour.g, colour.b, 0.9)
        end
    end
end

function Overlay:MarkDirty()
    self.dirty = true
    if self.map:IsShown() and FT.db and FT.db.settings.showTrails then
        self.frame:SetScript("OnUpdate", function() self:Update() end)
    elseif FT.db and not FT.db.settings.showTrails then
        self:Reset()
    end
end

function Overlay:Draw(a, b, width, height, scale)
    if a[1] == b[1] and a[2] == b[2] then return true end
    local buffer = self.back
    if buffer.used >= FT.config.renderLineLimit then return false end
    buffer.used = buffer.used + 1
    local pair = buffer.lines[buffer.used]
    if not pair then
        pair = { border = buffer.frame:CreateLine(nil, "ARTWORK", nil, 0),
            trail = buffer.frame:CreateLine(nil, "ARTWORK", nil, 1) }
        buffer.lines[buffer.used] = pair
    end
    for _, line in pairs(pair) do
        line:SetStartPoint("TOPLEFT", buffer.frame, a[1] * width, -a[2] * height)
        line:SetEndPoint("TOPLEFT", buffer.frame, b[1] * width, -b[2] * height)
        line:Show()
    end
    pair.border:SetThickness(4 / scale)
    pair.border:SetColorTexture(0.03, 0.06, 0.04, 0.8)
    pair.trail:SetThickness(2 / scale)
    local colour = FT.GetTrailColour()
    pair.trail:SetColorTexture(colour.r, colour.g, colour.b, 0.9)
    return true
end

function Overlay:Begin()
    -- Keep the completed drawing visible while preparing its replacement off-screen.
    local buffer = self.back
    buffer.frame:Hide()
    buffer.used = 0
    self.dirty = false
    if not FT.store or not FT.db.settings.showTrails then return end
    -- Another map provider may have inserted a layer since the previous draw.
    self:ApplyFrameLevel()
    local mapID = self.map:GetMapID()
    local width, height = self.frame:GetWidth(), self.frame:GetHeight()
    local scale = self.map:GetCanvasScale()
    if not mapID or width <= 0 or height <= 0 or not scale or scale <= 0 then
        self.dirty = true
        return
    end
    local artID = C_Map.GetMapArtID(mapID) or 0
    local segments = FT.store:SegmentsForMap(mapID)
    local count = 0
    self.job = coroutine.create(function()
        local function checkpoint()
            count = count + 1
            if count >= FT.config.renderPointBudget then
                count = 0
                coroutine.yield()
            end
        end
        local complete = FT.Geometry.Edges(segments, artID, width, height, scale,
            function(a, b) return self:Draw(a, b, width, height, scale) end, checkpoint)
        -- Retire unused pooled lines before showing a shorter replacement drawing.
        for i = buffer.used + 1, #buffer.lines do
            buffer.lines[i].border:Hide()
            buffer.lines[i].trail:Hide()
            checkpoint()
        end
        buffer.truncated = not complete
    end)
end

function Overlay:Commit()
    self.front, self.back = self.back, self.front
    -- Only completed drawings become visible; the swap occurs within one UI frame.
    self.front.frame:Show()
    self.back.frame:Hide()
    self.lines, self.used = self.front.lines, self.front.used
    self.truncated = self.front.truncated
    if FT.controls then FT.controls:Refresh() end
end

function Overlay:Update()
    if not self.map:IsShown() or not FT.db.settings.showTrails then self:Reset(); return end
    if not self.job then
        if not self.dirty then self.frame:SetScript("OnUpdate", nil); return end
        self:Begin()
    end
    if not self.job then
        if not self.dirty then self.frame:SetScript("OnUpdate", nil) end
        return
    end
    local ok, err = coroutine.resume(self.job)
    if not ok then
        self.job = nil
        self.back.frame:Hide()
        self.back.used = 0
        self.frame:SetScript("OnUpdate", nil)
        FT.Print("Map overlay stopped: " .. tostring(err))
        return
    end
    if coroutine.status(self.job) == "dead" then
        self.job = nil
        self:Commit()
    end
end
