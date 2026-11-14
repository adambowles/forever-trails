-- Strict, deliberately small client boundary. Unknown UI methods fail normally.
local Mock = {}

function Mock.New()
    local h = { now = 1000, tick = 0, x = 0.1, y = 0.2, mapID = 1, artID = 11,
        width = 1000, height = 1000, mapType = 3, frames = {}, tickers = {}, messages = {} }
    local Frame = {}
    Frame.__index = Frame
    function Frame:SetSize(w, v) self.width, self.height = w, v end
    function Frame:SetWidth(w) self.width = w end
    function Frame:SetAllPoints(target) self.sizeTarget = target or self.parent end
    function Frame:GetWidth() return self.sizeTarget and self.sizeTarget:GetWidth() or self.width or 100 end
    function Frame:GetHeight() return self.sizeTarget and self.sizeTarget:GetHeight() or self.height or 100 end
    function Frame:SetPoint(...) self.anchor = { ... } end
    function Frame:SetFrameLevel(level)
        assert(not h.inCombat, "Frame-level mutation attempted during combat lockdown")
        h.frameLevelWrites = (h.frameLevelWrites or 0) + 1
        self.level = level
    end
    function Frame:GetFrameLevel() return self.level or 100 end
    function Frame:SetFrameStrata(strata) self.strata = strata end
    function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function Frame:SetBackdrop(value) self.backdrop = value end
    function Frame:SetBackdropColor(...) self.bg = { ... } end
    function Frame:SetBackdropBorderColor(...) self.border = { ... } end
    function Frame:SetText(value) self.textValue = value end
    function Frame:SetJustifyH(value) self.justify = value end
    function Frame:SetChecked(value) self.checked = value end
    function Frame:GetChecked() return self.checked end
    function Frame:SetScript(name, fn) self.scripts[name] = fn end
    function Frame:Click()
        if self.kind == "CheckButton" then self.checked = not self.checked end
        if self.scripts.OnClick then self.scripts.OnClick(self) end
    end
    function Frame:RegisterEvent(name) self.events[name] = true end
    function Frame:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
    function Frame:Show()
        local changed = not self.shown
        self.shown = true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function Frame:Hide()
        local changed = self.shown
        self.shown = false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function Frame:SetShown(value) if value then self:Show() else self:Hide() end end
    local function frame(parent)
        return setmetatable({ parent = parent, shown = true, scripts = {}, events = {} }, Frame)
    end
    function Frame:CreateFontString() return frame(self) end
    function Frame:CreateLine(_, layer, template, subLevel)
        assert(layer == "ARTWORK" and template == nil and type(subLevel) == "number")
        local line = frame(self)
        -- Line endpoints take (point, relativeTo, x, y), unlike Frame:SetPoint.
        function line:SetStartPoint(point, relativeTo, x, y, extra)
            assert(point == "TOPLEFT" and relativeTo == self.parent and extra == nil)
            assert(type(x) == "number" and type(y) == "number")
            self.start = { x, y }
        end
        function line:SetEndPoint(point, relativeTo, x, y, extra)
            assert(point == "TOPLEFT" and relativeTo == self.parent and extra == nil)
            assert(type(x) == "number" and type(y) == "number")
            self.finish = { x, y }
        end
        function line:SetThickness(thickness) assert(thickness > 0); self.thickness = thickness end
        function line:SetColorTexture(...) self.color = { ... } end
        return line
    end
    CreateFrame = function(kind, _, parent, template)
        if h.inCombat and parent then
            error("Map UI creation attempted during combat lockdown")
        end
        local result = frame(parent)
        result.kind = kind
        assert(kind ~= "DropdownButton", "Shared dropdowns enter the native gamepad menu flow")
        h.frames[#h.frames + 1] = result
        return result
    end
    CreateFromMixins = function(...)
        local result = {}
        for i = 1, select("#", ...) do
            for key, value in pairs(select(i, ...)) do result[key] = value end
        end
        return result
    end
    MapCanvasDataProviderMixin = {
        OnAdded = function(self, map) self.owningMap = map end,
    }
    UIParent = frame()
    h.map = CreateFrame("Frame", nil, UIParent)
    h.map.shown, h.map.mapID, h.map.scale = false, 1, 1
    h.map.canvas, h.map.container = CreateFrame("Frame", nil, h.map), CreateFrame("Frame", nil, h.map)
    h.map.canvas:SetSize(1000, 500)
    h.map.providers = {}
    function h.map:GetCanvas() return self.canvas end
    function h.map:GetCanvasContainer() return self.container end
    function h.map:GetMapID() return self.mapID end
    function h.map:GetCanvasScale() return self.scale end
    -- Outdoor map art is drawn by managed pins far above the base canvas.
    -- Model the native layer insertion/shift contract, including existing pins.
    h.map.pinFrameLevelsManager = { definitions = {
        PIN_FRAME_LEVEL_DEFAULT = 2000,
        PIN_FRAME_LEVEL_MAP_EXPLORATION = 2002,
        PIN_FRAME_LEVEL_FOG_OF_WAR = 2006,
        PIN_FRAME_LEVEL_QUEST_BLOB = 2007,
        PIN_FRAME_LEVEL_MAP_HIGHLIGHT = 2009,
        PIN_FRAME_LEVEL_DEBUG = 2010,
        PIN_FRAME_LEVEL_DIG_SITE = 2014,
        PIN_FRAME_LEVEL_QUEST_OFFER = 2500,
        PIN_FRAME_LEVEL_GROUP_MEMBER = 4000,
    } }
    function h.map.pinFrameLevelsManager:GetValidFrameLevel(name)
        return assert(self.definitions[name], "Unregistered map frame level: " .. name)
    end
    function h.map.pinFrameLevelsManager:InsertFrameLevelAbove(name, relative)
        if self.definitions[name] or not self.definitions[relative] then return false end
        local target = self.definitions[relative] + 1
        for key, level in pairs(self.definitions) do
            if level >= target then self.definitions[key] = level + 1 end
        end
        self.definitions[name] = target
        return true
    end
    function h.map:GetPinFrameLevelsManager() return self.pinFrameLevelsManager end
    h.map.pins = {}
    function h.map:ExecuteOnAllPins(callback)
        for _, pin in ipairs(self.pins) do callback(pin) end
    end
    for _, levelType in ipairs({ "PIN_FRAME_LEVEL_MAP_EXPLORATION", "PIN_FRAME_LEVEL_FOG_OF_WAR",
        "PIN_FRAME_LEVEL_QUEST_BLOB", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "PIN_FRAME_LEVEL_DEBUG", "PIN_FRAME_LEVEL_DIG_SITE",
        "PIN_FRAME_LEVEL_QUEST_OFFER", "PIN_FRAME_LEVEL_GROUP_MEMBER" }) do
        local pin = CreateFrame("Frame", nil, h.map.canvas)
        pin.frameLevelType = levelType
        function pin:ApplyFrameLevel()
            self:SetFrameLevel(h.map:GetPinFrameLevelsManager():GetValidFrameLevel(self.frameLevelType))
        end
        pin:ApplyFrameLevel()
        h.map.pins[#h.map.pins + 1] = pin
    end
    function h.map:AddDataProvider()
        error("Addon must not register callbacks inside the native map flow")
    end
    WorldMapFrame = h.map
    C_Map = {
        GetBestMapForUnit = function(unit) assert(unit == "player"); return h.mapID end,
        GetMapInfo = function() return { mapType = h.mapType } end,
        GetPlayerMapPosition = function(mapID, unit)
            assert(mapID == h.mapID and unit == "player")
            if h.missing then return nil end
            return { GetXY = function() return h.x, h.y end }
        end,
        GetMapArtID = function() return h.artID end,
        GetMapWorldSize = function() return h.width, h.height end,
    }
    GetServerTime = function() return h.now end
    GetTime = function() return h.tick end
    InCombatLockdown = function() return h.inCombat or false end
    time = GetServerTime
    date = os.date
    UnitOnTaxi = function() return h.taxi or false end
    UnitIsGhost = function() return h.ghost or false end
    IsSwimming = function() return h.swimming or false end
    IsMounted = function() return h.mounted or false end
    UnitGUID = function() return "Player-A" end
    UnitName = function() return "Traveller" end
    GetRealmName = function() return "Forever" end
    issecretvalue = function(value) return value == h.secret and h.secret ~= nil end
    C_AddOns = { GetAddOnMetadata = function(_, key)
        assert(key == "Version")
        for line in io.lines("ForeverTrails/ForeverTrails.toc") do
            local value = line:match("^## Version: (.+)$")
            if value then return value end
        end
    end }
    C_Timer = { NewTicker = function(interval, callback)
        local ticker = { interval = interval, callback = callback }
        h.tickers[#h.tickers + 1] = ticker
        return ticker
    end }
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) h.messages[#h.messages + 1] = text end }
    SlashCmdList, StaticPopupDialogs = {}, {}
    StaticPopup_Show = function()
        error("Shared popups enter the native gamepad focus flow")
    end
    ForeverTrailsDB = nil
    h.FT = {}
    for line in io.lines("ForeverTrails/ForeverTrails.toc") do
        if line:match("%.lua$") then
            assert(loadfile("ForeverTrails/" .. line))("ForeverTrails", h.FT)
        end
    end
    function h:Fire(event, ...)
        for _, f in ipairs(self.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end
    function h:Boot()
        self:Fire("ADDON_LOADED", "ForeverTrails")
        self:Fire("PLAYER_ENTERING_WORLD")
    end
    function h:Move(x, y, dt)
        self.x, self.y = x, y
        self.tick, self.now = self.tick + (dt or 1), self.now + (dt or 1)
        self.FT.Sample()
    end
    function h:ShowMap(mapID)
        self.map.mapID = mapID or self.map.mapID
        self.map:Show()
        for _, provider in ipairs(self.map.providers) do provider:OnShow(); provider:OnMapChanged() end
    end
    function h:HideMap()
        for _, provider in ipairs(self.map.providers) do provider:OnHide() end
        self.map:Hide()
    end
    function h:Frames(count)
        for _ = 1, count or 1 do
            for _, f in ipairs(self.frames) do
                if f:IsShown() and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1 / 60) end
            end
        end
    end
    return h
end

return Mock
