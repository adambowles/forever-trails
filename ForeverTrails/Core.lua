local addonName, FT = ...
local events = CreateFrame("Frame")
FT.suspended = true

function FT.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4dd973Forever Trails:|r " .. message)
end

function FT.Refresh()
    if FT.overlay then FT.overlay:MarkDirty() end
    if FT.controls and FT.controls.panel:IsShown() then FT.controls:Refresh() end
end

function FT.SetVisible(visible)
    if not FT.db then return end
    FT.db.settings.showTrails = not not visible
    FT.Refresh()
end

function FT.SetRecording(enabled)
    if not FT.db then return end
    FT.db.settings.recording = not not enabled
    if FT.recorder then FT.recorder:Break(enabled and "resume" or "pause") end
    FT.Refresh()
end

function FT.SetTrailColour(id)
    if not FT.db or not FT.colourByID[id] then return false end
    if FT.db.settings.trailColour == id then return true end
    FT.db.settings.trailColour = id
    -- Recolour visible and partly prepared lines without rebuilding their geometry.
    if FT.overlay then FT.overlay:ApplyColour() end
    if FT.controls then FT.controls:Refresh() end
    return true
end

local function canClearHistory()
    if not InCombatLockdown() then return true end
    FT.Print("History cannot be cleared during combat. Try again afterwards.")
    return false
end

function FT.ConfirmClear()
    if not canClearHistory() then return end
    if not FT.confirmation then
        FT.confirmation = FT.Controls.NewConfirmation(function()
            -- A refused acceptance must require a new explicit confirmation.
            FT.confirmation:Hide()
            if not canClearHistory() then return end
            if FT.recorder then FT.recorder:Break("cleared") end
            if FT.store then FT.store:ClearCharacter() end
            if FT.overlay then FT.overlay:Reset() end
            FT.Refresh()
        end)
    end
    FT.confirmation:Show()
end

function FT.TryAttachMap()
    if not FT.db or FT.overlay or not WorldMapFrame then return end
    if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED retries; sampling continues.
    local map = WorldMapFrame
    if not map.GetCanvas then return end
    FT.overlay = FT.Overlay.New(map)
    FT.controls = FT.Controls.New(map)
end

function FT.Sample()
    if not FT.db or not FT.recorder or FT.suspended or not FT.db.settings.recording then return end
    local revision = FT.store.revision
    FT.recorder:Observe(FT.Compat.ReadPosition())
    if FT.store.revision ~= revision and FT.overlay then FT.overlay:MarkDirty() end
    if FT.controls and FT.controls.panel:IsShown() then FT.controls:Refresh() end
end

local function enterWorld()
    if not FT.db then return end
    if not FT.store then
        local guid = UnitGUID("player")
        if not guid then return end
        FT.store = FT.Store.New(FT.db, guid, UnitName("player"), GetRealmName(), FT.Compat.Now())
        FT.recorder = FT.Recorder.New(FT.store)
    end
    FT.suspended = false
    FT.recorder:Break("enter-world")
    FT.Sample()
    FT.TryAttachMap()
    FT.Refresh()
end

local function slash(message)
    local command = (message or ""):match("^%s*(%S*)"):lower()
    if not FT.db then FT.Print("Recording disabled: " .. (FT.error or "not loaded")); return end
    if command == "pause" then FT.SetRecording(false)
    elseif command == "resume" then FT.SetRecording(true)
    elseif command == "show" then FT.SetVisible(true)
    elseif command == "hide" then FT.SetVisible(false)
    elseif command == "clear" then FT.ConfirmClear()
    elseif command == "status" then
        local count = FT.store and FT.store.character.pointCount or 0
        local total = FT.store and FT.store.pointCount or 0
        local oldest = FT.store and FT.store:OldestTime()
        FT.Print(string.format("v%s; sampling every %ss; %s; %s character / %s account points; oldest %s.",
            FT.Compat.Version(), FT.config.sampleInterval,
            FT.db.settings.recording and (FT.recorder and FT.recorder.status or "waiting") or "paused",
            count, total, oldest and date("%d %b %Y %H:%M", oldest) or "none"))
    else
        FT.Print("/ft status | pause | resume | show | hide | clear. Map controls: Trails button.")
    end
end

SLASH_FOREVERTRAILS1 = "/ft"
SLASH_FOREVERTRAILS2 = "/forevertrails"
SlashCmdList.FOREVERTRAILS = slash

events:SetScript("OnEvent", function(_, event, name, blockedFunction)
    if event == "ADDON_LOADED" then
        if name == addonName then
            local db, err = FT.Migrations.Open(ForeverTrailsDB)
            FT.db, FT.error = db, err
            if not db then FT.Print(err); return end
            ForeverTrailsDB = db
            FT.ticker = C_Timer.NewTicker(FT.config.sampleInterval, FT.Sample)
        end
        FT.TryAttachMap()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
        enterWorld()
    elseif event == "PLAYER_LEAVING_WORLD" or event == "LOADING_SCREEN_ENABLED" or event == "PLAYER_LOGOUT" then
        FT.suspended = true
        if FT.recorder then FT.recorder:Break(event:lower()) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        FT.TryAttachMap()
        if FT.overlay then FT.overlay:ApplyFrameLevel() end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if name == addonName then
            local functionName = tostring(blockedFunction or "unknown")
            local key = event .. ":" .. functionName
            FT.reportedBlockedActions = FT.reportedBlockedActions or {}
            if not FT.reportedBlockedActions[key] then
                FT.reportedBlockedActions[key] = true
                FT.Print("WoW blocked " .. functionName .. ". Please report this function name.")
            end
        end
    elseif FT.recorder then
        FT.recorder:Break(event:lower())
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_LOGOUT",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_REGEN_ENABLED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    events:RegisterEvent(event)
end
