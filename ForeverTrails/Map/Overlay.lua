local _, FT = ...
local Overlay = {}
Overlay.__index = Overlay
FT.Overlay = Overlay

function Overlay.New(map)
    local self = setmetatable({ map = map, lines = {}, used = 0, dirty = true }, Overlay)
    self.frame = CreateFrame("Frame", nil, map:GetCanvas())
    self.frame:SetAllPoints(map:GetCanvas())
    self.frame:SetFrameLevel(map:GetCanvas():GetFrameLevel() + 2)
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

function Overlay:Reset()
    self.job, self.truncated = nil, false
    self.frame:SetScript("OnUpdate", nil)
    for _, pair in ipairs(self.lines) do pair.border:Hide(); pair.trail:Hide() end
    self.used = 0
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
    if self.used >= FT.config.renderLineLimit then return false end
    self.used = self.used + 1
    local pair = self.lines[self.used]
    if not pair then
        pair = { border = self.frame:CreateLine(nil, "ARTWORK", nil, 0),
            trail = self.frame:CreateLine(nil, "ARTWORK", nil, 1) }
        self.lines[self.used] = pair
    end
    for _, line in pairs(pair) do
        line:SetStartPoint("TOPLEFT", self.frame, a[1] * width, -a[2] * height)
        line:SetEndPoint("TOPLEFT", self.frame, b[1] * width, -b[2] * height)
        line:Show()
    end
    pair.border:SetThickness(4 / scale)
    pair.border:SetColorTexture(0.03, 0.06, 0.04, 0.8)
    pair.trail:SetThickness(2 / scale)
    pair.trail:SetColorTexture(0.30, 0.85, 0.45, 0.9)
    return true
end

function Overlay:Begin()
    self:Reset()
    self.dirty = false
    if not FT.store or not FT.db.settings.showTrails then return end
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
        local complete = FT.Geometry.Edges(segments, artID, width, height, scale,
            function(a, b) return self:Draw(a, b, width, height, scale) end,
            function()
                count = count + 1
                if count >= FT.config.renderPointBudget then
                    count = 0
                    coroutine.yield()
                end
            end)
        self.truncated = not complete
    end)
end

function Overlay:Update()
    if not self.map:IsShown() or not FT.db.settings.showTrails then self:Reset(); return end
    if not self.job then
        if not self.dirty then self.frame:SetScript("OnUpdate", nil); return end
        self:Begin()
        -- Reset() removes the script; keep incremental jobs running until complete.
        self.frame:SetScript("OnUpdate", function() self:Update() end)
    end
    if not self.job then return end
    local ok, err = coroutine.resume(self.job)
    if not ok then
        self:Reset()
        FT.Print("Map overlay stopped: " .. tostring(err))
        return
    end
    if coroutine.status(self.job) == "dead" then
        self.job = nil
        if FT.controls then FT.controls:Refresh() end
    end
end
