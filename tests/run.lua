local Mock = dofile("tests/mock_wow.lua")
local passed, failed = 0, 0

local function equal(actual, expected, message)
    assert(actual == expected, (message or "Values differ") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n") end
end

local function sample(t, x, y, changes)
    local result = { time = 1000 + t, tick = t, x = x, y = y or 0.2,
        mapID = 1, artID = 11, scaleX = 1000, scaleY = 1000, space = "yards", mode = "foot" }
    for key, value in pairs(changes or {}) do result[key] = value end
    return result
end

local function fixture(settings)
    local h = Mock.New()
    local FT = h.FT
    local db = assert(FT.Migrations.Open())
    for key, value in pairs(settings or {}) do db.settings[key] = value end
    local store = FT.Store.New(db, "A", "Traveller", "Forever", 1000)
    return h, FT.Recorder.New(store), store, db
end

local function segments(store)
    local result = {}
    for _, session in ipairs(store.character.sessions) do
        for _, segment in ipairs(session.segments) do result[#result + 1] = segment end
    end
    return result
end

local function drawnTrail()
    local h = Mock.New(); h:Boot()
    for i = 1, 30 do h:Move(0.1 + i * 0.003, 0.2 + (i % 2) * 0.006) end
    h:ShowMap(); h:Frames(4)
    assert(h.FT.overlay.used > 1)
    return h, h.FT.overlay
end

test("one-second sampling and immediate recording after entering world", function()
    local h = Mock.New(); h:Boot()
    equal(#h.tickers, 1); equal(h.tickers[1].interval, 1)
    equal(h.FT.store.character.pointCount, 1)
    h:Fire("ADDON_LOADED", "AnotherAddon")
    equal(#h.tickers, 1)
end)

test("player position is independent of the displayed map", function()
    local h = Mock.New(); h:Boot(); h:ShowMap(99)
    h:Move(0.11, 0.2)
    local all = segments(h.FT.store)
    equal(all[1].mapID, 1); equal(#all[1].points, 2)
    h:Frames(4); equal(h.FT.overlay.used, 0)
end)

test("coordinates are finite, bounded and non-secret", function()
    local h = Mock.New()
    for _, invalid in ipairs({ -1, 2, math.huge, -math.huge, 0/0 }) do
        h.x = invalid; equal(h.FT.Compat.ReadPosition(), nil)
    end
    h.secret = setmetatable({}, { __lt = function() error("secret comparison") end })
    h.x = h.secret
    equal(h.FT.Compat.ReadPosition(), nil)
    h.x, h.y = 0, 0; equal(h.FT.Compat.ReadPosition(), nil)
    h.x, h.y = 0, 0.5; assert(h.FT.Compat.ReadPosition())
end)

test("continent fallbacks are not recorded as zones", function()
    local h = Mock.New(); h.mapType = 2
    equal(h.FT.Compat.ReadPosition(), nil)
end)

test("missing dimensions fall back to normalised distances", function()
    local h = Mock.New(); h.width, h.height = nil, nil
    local position = assert(h.FT.Compat.ReadPosition())
    equal(position.space, "normalised"); equal(position.scaleX, 1)
    C_Map.GetMapWorldSize = function() error("Unavailable") end
    equal(assert(h.FT.Compat.ReadPosition()).space, "normalised")
end)

test("flight, ghost, mount and swimming categories are recognised", function()
    local h = Mock.New()
    for flag, expected in pairs({ taxi = "flight", ghost = "ghost", mounted = "mounted", swimming = "swimming" }) do
        h[flag] = true
        equal(assert(h.FT.Compat.ReadPosition()).mode, expected)
        h[flag] = false
    end
end)

test("straight paths are simplified but endpoints and time are preserved", function()
    local _, rec, store = fixture()
    for i = 0, 9 do rec:Observe(sample(i, 0.1 + i * 0.005)) end
    local points = segments(store)[1].points
    equal(#points, 2); equal(points[1][1], 0.1); equal(points[2][3], 9)
end)

test("sharp corners and backtracking survive simplification", function()
    local _, rec, store = fixture()
    rec:Observe(sample(0, 0.1, 0.1))
    rec:Observe(sample(1, 0.11, 0.1))
    rec:Observe(sample(2, 0.11, 0.11))
    rec:Observe(sample(3, 0.11, 0.1))
    equal(#segments(store)[1].points, 4)
end)

test("a sampled loop remains a loop", function()
    local _, rec, store = fixture()
    local positions = { {0.1,0.1}, {0.12,0.1}, {0.12,0.12}, {0.1,0.12}, {0.1,0.1} }
    for i, p in ipairs(positions) do rec:Observe(sample(i, p[1], p[2])) end
    local points = segments(store)[1].points
    equal(#points, 5); equal(points[1][1], points[5][1]); equal(points[1][2], points[5][2])
end)

test("stationary observations do not accumulate points", function()
    local _, rec, store = fixture()
    for i = 0, 600 do rec:Observe(sample(i, 0.1)) end
    assert(store.character.pointCount <= 5)
end)

test("idle arrival and departure timestamps survive resumed movement", function()
    local _, rec, store = fixture()
    rec:Observe(sample(0, 0.1)); rec:Observe(sample(1, 0.11))
    for i = 2, 8 do rec:Observe(sample(i, 0.11)) end
    rec:Observe(sample(9, 0.12)); rec:Observe(sample(10, 0.13))
    local points = segments(store)[1].points
    equal(points[2][3], 1); equal(points[3][3], 8)
    equal(points[2][1], points[3][1])
end)

test("map, map-art, floor and coordinate changes break routes", function()
    for _, changes in ipairs({ { mapID = 2 }, { artID = 12 },
        { space = "normalised", scaleX = 1, scaleY = 1 }, { scaleX = 999 } }) do
        local _, rec, store = fixture()
        rec:Observe(sample(0, 0.1)); rec:Observe(sample(1, 0.11, 0.2, changes))
        equal(#segments(store), 2)
    end
end)

test("movement category changes create separate segments", function()
    local _, rec, store = fixture()
    rec:Observe(sample(0, 0.1)); rec:Observe(sample(1, 0.11, nil, { mode = "mounted" }))
    equal(#segments(store), 2); equal(segments(store)[2].mode, "mounted")
end)

test("teleports break a line but normal taxis remain continuous", function()
    local _, rec, store = fixture()
    rec:Observe(sample(0, 0.1)); rec:Observe(sample(1, 0.9))
    equal(#segments(store), 2); equal(segments(store)[2].breakReason, "position-jump")
    local _, flight, flightStore = fixture()
    flight:Observe(sample(0, 0.1, nil, { mode = "flight" }))
    flight:Observe(sample(1, 0.25, nil, { mode = "flight" }))
    equal(#segments(flightStore), 1)
end)

test("missing positions and long or backwards time gaps break routes", function()
    local _, rec, store = fixture()
    rec:Observe(sample(0, 0.1)); rec:Observe(nil, "Unavailable")
    equal(rec.status, "Unavailable")
    rec:Observe(sample(1, 0.11)); rec:Observe(sample(10, 0.12))
    rec:Observe(sample(11, 0.13, nil, { time = 999 }))
    equal(#segments(store), 4)
end)

test("normalised-coordinate fallback still simplifies and detects jumps", function()
    local _, rec, store = fixture()
    local changes = { scaleX = 1, scaleY = 1, space = "normalised" }
    for i = 0, 5 do rec:Observe(sample(i, 0.1 + i * 0.002, nil, changes)) end
    equal(#segments(store)[1].points, 2)
    rec:Observe(sample(6, 0.9, nil, changes)); equal(#segments(store), 2)
end)

test("storage chunks repeat the boundary endpoint and stay bounded", function()
    local h, rec, store = fixture()
    h.FT.config.maxSegmentPoints, h.FT.config.tolerance = 3, 0
    for i = 0, 6 do rec:Observe(sample(i, 0.1 + i * 0.005, 0.2 + (i % 2) * 0.005)) end
    local all = segments(store)
    assert(#all >= 3)
    for i, seg in ipairs(all) do
        assert(#seg.points <= 3)
        if i > 1 then
            local previous = all[i-1].points
            equal(previous[#previous][1], seg.points[1][1])
            equal(previous[#previous][2], seg.points[1][2])
        end
    end
end)

test("oldest complete segments are pruned at the character limit", function()
    local h, rec, store = fixture({ characterPointLimit = 6 })
    h.FT.config.maxSegmentPoints, h.FT.config.tolerance = 3, 0
    for i = 0, 30 do rec:Observe(sample(i, 0.1 + i * 0.005, 0.2 + (i % 2) * 0.005)) end
    assert(store.character.pointCount <= 6); assert(store:OldestTime() > 1000)
    assert(store.active and #store.active.points > 0)
    local count = 0
    for _, seg in ipairs(store:SegmentsForMap(1)) do count = count + #seg.points end
    equal(count, store.character.pointCount)
end)

test("account retention removes old history across characters", function()
    local h, rec, first, db = fixture({ characterPointLimit = 20, accountPointLimit = 7 })
    for i = 0, 4 do rec:Observe(sample(i, 0.1, nil, { mapID = i + 1 })) end
    rec:Break("logout")
    local second = h.FT.Store.New(db, "B", "Other", "Forever", 1005)
    local otherRec = h.FT.Recorder.New(second)
    for i = 5, 10 do otherRec:Observe(sample(i, 0.1, nil, { mapID = i + 1 })) end
    assert(second.pointCount <= 7); assert(first.character.pointCount < 5)
    equal(second.character.pointCount, 6)
end)

test("reload reconstructs counts and starts a new session", function()
    local h, rec, store, db = fixture()
    rec:Observe(sample(0, 0.1)); rec:Observe(sample(1, 0.11)); rec:Break("logout")
    store.character.pointCount = 999999
    local reloaded = h.FT.Store.New(db, "A", "Traveller", "Forever", 1010)
    equal(reloaded.character.pointCount, 2)
    h.FT.Recorder.New(reloaded):Observe(sample(10, 0.2))
    equal(#store.character.sessions, 2); equal(reloaded.character.pointCount, 3)
end)

test("unknown schema is preserved and recording is disabled", function()
    local h = Mock.New()
    local original = { schemaVersion = 99, characters = {}, settings = {}, sentinel = "keep" }
    ForeverTrailsDB = original
    h:Fire("ADDON_LOADED", "ForeverTrails")
    equal(h.FT.db, nil); equal(ForeverTrailsDB, original); equal(original.sentinel, "keep")
    equal(#h.tickers, 0)
end)

test("settings limits are validated without replacing history", function()
    local h = Mock.New()
    local db = { schemaVersion = 1, characters = {}, settings = { characterPointLimit = -1,
        accountPointLimit = 3.9, recording = false } }
    equal(h.FT.Migrations.Open(db), db)
    equal(db.settings.characterPointLimit, 200000); equal(db.settings.accountPointLimit, 3)
    equal(db.settings.recording, false)
end)

test("pause and loading events prevent connecting across missing travel", function()
    local h = Mock.New(); h:Boot()
    h.FT.SetRecording(false); h:Move(0.5, 0.2)
    equal(h.FT.store.character.pointCount, 1)
    h.FT.SetRecording(true); h:Move(0.51, 0.2)
    equal(#segments(h.FT.store), 2)
    h:Fire("LOADING_SCREEN_ENABLED"); h:Move(0.8, 0.2)
    equal(h.FT.store.character.pointCount, 2)
    h:Fire("LOADING_SCREEN_DISABLED")
    equal(#segments(h.FT.store), 3)
end)

test("hidden overlay keeps recording without any render work", function()
    local h = Mock.New(); h:Boot()
    h.FT.SetVisible(false); h:ShowMap(); h:Move(0.11, 0.2); h:Frames(4)
    equal(h.FT.store.character.pointCount, 2)
    equal(h.FT.overlay.used, 0); equal(h.FT.overlay.frame.scripts.OnUpdate, nil)
end)

test("map lines use correct coordinates, pooling and zoom-adjusted thickness", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    h:ShowMap(); h:Frames(4)
    local overlay = h.FT.overlay
    equal(overlay.used, 1); equal(#h.messages, 0)
    local line = overlay.lines[1].trail
    equal(line.start[1], 110); equal(line.start[2], -100)
    equal(line.finish[1], 100); equal(line.thickness, 2)
    h.map.scale = 2
    h:Frames(4)
    equal(overlay.lines[1].trail.thickness, 1)
    h.map.canvas:SetSize(2000, 1000)
    h:Frames(4)
    equal(overlay.lines[1].trail, line) -- the two render buffers reuse their line pools
    equal(line.start[1], 220); equal(line.start[2], -200)
    h:HideMap(); h:Frames(1)
    equal(overlay.used, 0); equal(overlay.frame.scripts.OnUpdate, nil)
end)

test("recording updates keep the completed trail visible until the redraw finishes", function()
    local h, overlay = drawnTrail()
    local line = overlay.lines[1].trail
    local x, y, count = line.start[1], line.start[2], overlay.used
    h.FT.config.renderPointBudget = 2
    h:Move(0.2, 0.21); h:Frames(1)
    assert(overlay.job and coroutine.status(overlay.job) == "suspended")
    assert(line:IsShown(), "Existing trail disappeared during an incremental redraw")
    equal(overlay.back.frame:IsShown(), false)
    equal(line.start[1], x); equal(line.start[2], y); equal(overlay.used, count)
    h:Frames(60)
    equal(overlay.job, nil)
    assert(overlay.lines[1].trail:IsShown())
    equal(overlay.lines[1].trail.start[1], 200)
    equal(line:IsShown(), false)
end)

test("points arriving during a redraw queue another update without restarting it", function()
    local h, overlay = drawnTrail()
    local front = overlay.front
    h.FT.config.renderPointBudget = 2
    h:Move(0.2, 0.21); h:Frames(1)
    local job = overlay.job
    h:Move(0.24, 0.22); h:Frames(1)
    equal(overlay.job, job); equal(overlay.front, front)
    assert(front.frame:IsShown())
    h:Frames(80)
    equal(overlay.job, nil)
    equal(overlay.lines[1].trail.start[1], 240)
    equal(#h.messages, 0)
end)

test("failed redraws retain the last completed trail", function()
    local h, overlay = drawnTrail()
    local line, count = overlay.lines[1].trail, overlay.used
    h.FT.Geometry.Edges = function() error("test redraw failure") end
    overlay:MarkDirty(); h:Frames(1)
    equal(overlay.job, nil); equal(overlay.used, count)
    assert(line:IsShown()); equal(overlay.back.frame:IsShown(), false)
    assert(h.messages[1]:find("test redraw failure", 1, true))
end)

test("shorter drawings hide unused pooled lines before their buffer is shown", function()
    local h, overlay = drawnTrail()
    overlay:MarkDirty(); h:Frames(4) -- populate both pools
    local seg = segments(h.FT.store)[1]
    seg.points = { seg.points[1], seg.points[#seg.points] }
    h.FT.config.renderPointBudget = 2
    overlay:MarkDirty(); h:Frames(60)
    equal(overlay.used, 1); assert(#overlay.lines > 1)
    for i = 2, #overlay.lines do
        equal(overlay.lines[i].trail:IsShown(), false)
        equal(overlay.lines[i].border:IsShown(), false)
    end
end)

test("map changes, hiding and deletion discard pending and completed drawings", function()
    for _, action in ipairs({ "map", "hide", "clear" }) do
        local h, overlay = drawnTrail()
        h.FT.config.renderPointBudget = 2
        h:Move(0.2, 0.21); h:Frames(1)
        assert(overlay.job)
        if action == "map" then
            h.map.mapID = 99; h:Frames(1)
        elseif action == "hide" then
            h.FT.SetVisible(false)
        else
            h.FT.ConfirmClear(); h.FT.confirmation.delete:Click()
        end
        equal(overlay.job, nil); equal(overlay.used, 0)
        equal(overlay.front.frame:IsShown(), false)
        equal(overlay.back.frame:IsShown(), false)
        h:Frames(60)
        equal(overlay.used, 0)
    end
end)

test("the map menu offers six presets and recolours existing lines without a redraw", function()
    local h, overlay = drawnTrail()
    local controls = h.FT.controls
    local front, revision = overlay.front, h.FT.store.revision
    local expected = { "Green", "Cyan", "Blue", "Gold", "Red", "White" }
    h.FT.Geometry.Edges = function() error("Colour changes must not rebuild geometry") end
    controls.button:Click()
    local count = 0
    for _ in pairs(controls.colours) do count = count + 1 end
    equal(count, #expected)
    for i, preset in ipairs(h.FT.colourPresets) do
        equal(preset.name, expected[i])
        controls.colours[preset.id]:Click()
        equal(h.FT.db.settings.trailColour, preset.id)
        for id, choice in pairs(controls.colours) do equal(choice:GetChecked(), id == preset.id) end
        controls.colours[preset.id]:Click() -- selected presets cannot be deselected
        equal(controls.colours[preset.id]:GetChecked(), true)
        equal(overlay.front, front); equal(overlay.job, nil)
        for j = 1, overlay.used do
            local line = overlay.lines[j].trail
            assert(line:IsShown())
            equal(line.color[1], preset.r); equal(line.color[2], preset.g); equal(line.color[3], preset.b)
        end
        h:Frames(1)
    end
    equal(h.FT.store.revision, revision); equal(#h.messages, 0)
    equal(h.FT.SetTrailColour("unknown"), false)
    equal(h.FT.db.settings.trailColour, "white")
end)

test("changing colour during a redraw updates both buffers and later points", function()
    local h, overlay = drawnTrail()
    h.FT.config.renderPointBudget = 2
    h:Move(0.2, 0.21); h:Frames(3)
    local job = overlay.job
    assert(job and overlay.back.used > 0)
    h.FT.controls.colours.gold:Click()
    local gold = h.FT.colourByID.gold
    equal(overlay.job, job)
    for _, buffer in ipairs({ overlay.front, overlay.back }) do
        for i = 1, buffer.used do equal(buffer.lines[i].trail.color[1], gold.r) end
    end
    h:Frames(60)
    equal(overlay.job, nil)
    for i = 1, overlay.used do
        equal(overlay.lines[i].trail.color[1], gold.r)
        equal(overlay.lines[i].trail.color[2], gold.g)
        equal(overlay.lines[i].trail.color[3], gold.b)
    end
end)

test("colour settings survive reload without replacing recorded history", function()
    local h, overlay = drawnTrail()
    h.FT.controls.colours.blue:Click()
    local saved, oldSession = h.FT.db, h.FT.store.character.sessions[1]
    local reloaded = Mock.New()
    ForeverTrailsDB = saved
    reloaded:Boot()
    equal(reloaded.FT.db, saved)
    equal(reloaded.FT.db.settings.trailColour, "blue")
    equal(reloaded.FT.store.character.sessions[1], oldSession)
    reloaded:ShowMap(); reloaded:Frames(1); reloaded.FT.controls.button:Click()
    equal(reloaded.FT.controls.colours.blue:GetChecked(), true)
    assert(overlay.used > 0)
end)

test("older or invalid colour settings default to green while preserving history", function()
    local h = Mock.New()
    local old = { schemaVersion = 1, characters = {}, settings = {} }
    equal(h.FT.Migrations.Open(old), old); equal(old.settings.trailColour, "green")
    for _, value in ipairs({ "missing", false, 42, {} }) do
        local characters = {}
        local db = { schemaVersion = 1, characters = characters, settings = { trailColour = value } }
        equal(h.FT.Migrations.Open(db), db)
        equal(db.characters, characters); equal(db.settings.trailColour, "green")
    end
end)

test("outdoor trails draw above map art and below quest and player markers", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    h:ShowMap(); h:Frames(4)
    local overlay = h.FT.overlay
    equal(overlay.used, 1)
    local layer = overlay.frame:GetFrameLevel()
    equal(overlay.front.frame:GetFrameLevel(), layer)
    equal(overlay.back.frame:GetFrameLevel(), layer)
    equal(overlay.front.frame.parent, h.map:GetCanvas())
    equal(overlay.back.frame.parent, h.map:GetCanvas())
    local levels = h.map:GetPinFrameLevelsManager()
    for _, art in ipairs({ "PIN_FRAME_LEVEL_MAP_EXPLORATION", "PIN_FRAME_LEVEL_FOG_OF_WAR",
        "PIN_FRAME_LEVEL_QUEST_BLOB", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" }) do
        assert(layer > levels:GetValidFrameLevel(art), "Trail is underneath " .. art)
    end
    for _, marker in ipairs({ "PIN_FRAME_LEVEL_DIG_SITE", "PIN_FRAME_LEVEL_QUEST_OFFER",
        "PIN_FRAME_LEVEL_GROUP_MEMBER" }) do
        assert(layer < levels:GetValidFrameLevel(marker), "Trail covers " .. marker)
    end
    equal(overlay.frame.parent, h.map:GetCanvas())
    equal(overlay.frame.mouseEnabled, false)
end)

test("trail setup leaves native map definitions and existing pins untouched", function()
    local h = Mock.New()
    local before, definitions = {}, {}
    local levels = h.map:GetPinFrameLevelsManager()
    for name, level in pairs(levels.definitions) do definitions[name] = level end
    for _, pin in ipairs(h.map.pins) do before[pin] = pin:GetFrameLevel() end
    levels.InsertFrameLevelAbove = function() error("Addon must not change shared map definitions") end
    h.map.ExecuteOnAllPins = function() error("Addon must not update native map pins") end
    h:Boot()
    h:ShowMap(); h:Move(0.11, 0.2); h:Frames(4)
    for name, level in pairs(levels.definitions) do equal(level, definitions[name]) end
    for name, level in pairs(definitions) do equal(levels.definitions[name], level) end
    for _, pin in ipairs(h.map.pins) do
        equal(pin:GetFrameLevel(), before[pin])
    end
end)

test("map attachment needs no native provider and leaves native handlers untouched", function()
    local h = Mock.New()
    MapCanvasDataProviderMixin, CreateFromMixins = nil, nil
    h.map.SetScript = function() error("Addon must not replace native map scripts") end
    h.map.HookScript = function() error("Addon must not run inside native map scripts") end
    h:Boot(); h:Move(0.11, 0.2); h:ShowMap(); h:Frames(4)
    equal(#h.map.providers, 0)
    assert(h.FT.overlay.used > 0)
    equal(h.FT.overlay.frame.scripts.OnUpdate, nil)
    equal(h.FT.overlay.observer.parent, nil)
end)

test("map close finishes before private overlay cleanup and controls hide", function()
    local h, overlay = drawnTrail()
    local controls = h.FT.controls
    controls.button:Click(); assert(controls.panel:IsShown())
    h:HideMap()
    -- Native HideUIPanel can finish its binding changes without addon callbacks.
    assert(overlay.used > 0)
    h:Frames(1)
    equal(overlay.used, 0); equal(overlay.job, nil)
    equal(controls.root:IsShown(), false); equal(controls.panel:IsShown(), false)
    h:Move(0.2, 0.21)
    h:ShowMap(); h:Frames(4)
    assert(overlay.used > 0); assert(controls.button:IsShown())
    equal(controls.panel:IsShown(), false)
end)

test("interactive controls and confirmation stay outside native map navigation", function()
    local h, overlay = drawnTrail()
    h.FT.ConfirmClear()
    equal(h.FT.controls.root.parent, UIParent)
    equal(h.FT.confirmation.parent, UIParent)
    for _, frame in ipairs(h.frames) do
        if frame.kind == "Button" or frame.kind == "CheckButton" then
            local parent = frame.parent
            while parent do
                assert(parent ~= h.map, "Interactive addon frame entered the native map tree")
                parent = parent.parent
            end
        end
    end
    equal(next(StaticPopupDialogs), nil)
    equal(overlay.front.frame.mouseEnabled, false)
    equal(overlay.back.frame.mouseEnabled, false)
end)

test("art changes cancel a partially prepared trail without a native map callback", function()
    local h, overlay = drawnTrail()
    h.FT.config.renderPointBudget = 2
    h:Move(0.2, 0.21); h:Frames(1)
    local job = overlay.job
    assert(job)
    h.artID = 12; h:Frames(1)
    assert(overlay.job ~= job)
    equal(overlay.used, 0)
    h:Frames(60); equal(overlay.used, 0)
    h.artID = 11; h:Frames(60); assert(overlay.used > 0)
end)

test("map setup waits for combat to end while recording continues", function()
    local h = Mock.New()
    h.inCombat = true
    h:Boot(); h:Move(0.11, 0.2)
    equal(h.FT.overlay, nil); equal(h.FT.controls, nil)
    equal(#h.map.providers, 0); equal(h.FT.store.character.pointCount, 2)
    local last = h.FT.recorder.last
    h.inCombat = false; h:Fire("PLAYER_REGEN_ENABLED")
    assert(h.FT.overlay and h.FT.controls)
    equal(#h.map.providers, 0); equal(h.FT.recorder.last, last)
    local overlay = h.FT.overlay
    h:Fire("PLAYER_REGEN_ENABLED"); equal(h.FT.overlay, overlay)
    h:ShowMap(); h:Frames(4); equal(h.FT.overlay.used, 1)
end)

test("a map addon loaded in combat attaches automatically afterwards", function()
    local h = Mock.New()
    WorldMapFrame = nil
    h:Boot(); equal(h.FT.overlay, nil)
    h.inCombat, WorldMapFrame = true, h.map
    h:Fire("ADDON_LOADED", "Blizzard_WorldMap")
    equal(h.FT.overlay, nil)
    h.inCombat = false; h:Fire("PLAYER_REGEN_ENABLED")
    assert(h.FT.overlay); equal(#h.map.providers, 0)
end)

test("recording redraws do not repeatedly set frame levels", function()
    local h, overlay = drawnTrail()
    h.FT.controls.panel:Show()
    local writes = h.frameLevelWrites
    for i = 1, 5 do h:Move(0.19 + i * 0.003, 0.2 + (i % 2) * 0.006); h:Frames(4) end
    equal(h.frameLevelWrites, writes)
    assert(overlay.used > 0)
end)

test("frame-level updates are deferred in combat and applied on recovery", function()
    local h, overlay = drawnTrail()
    local previous, writes = overlay.frame:GetFrameLevel(), h.frameLevelWrites
    h.inCombat = true
    -- Simulate another provider changing its layer definitions while we are locked.
    local levels = h.map:GetPinFrameLevelsManager()
    levels.definitions.PIN_FRAME_LEVEL_MAP_HIGHLIGHT = previous + 1
    h:Move(0.2, 0.21); h:Frames(4)
    equal(overlay.frame:GetFrameLevel(), previous)
    equal(h.frameLevelWrites, writes)
    equal(h.FT.store.character.pointCount > 0, true)
    h.inCombat = false; h:Fire("PLAYER_REGEN_ENABLED")
    assert(overlay.frame:GetFrameLevel() > previous)
    equal(#h.messages, 0)
end)

test("history confirmation is not opened or accepted during combat", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    h.inCombat = true
    h.FT.ConfirmClear(); equal(h.FT.confirmation, nil)
    h.inCombat = false
    h.FT.ConfirmClear(); assert(h.FT.confirmation:IsShown())
    h.inCombat = true
    h.FT.confirmation.delete:Click(); equal(h.FT.store.character.pointCount, 2)
    equal(h.FT.confirmation:IsShown(), false)
    h.inCombat = false
    h.FT.ConfirmClear(); h.FT.confirmation.delete:Click()
    equal(h.FT.store.character.pointCount, 0)
end)

test("blocked-action diagnostics name the function without interrupting recording", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    local last = h.FT.recorder.last
    h:Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "SetFrameLevel")
    equal(#h.messages, 0)
    h:Fire("ADDON_ACTION_BLOCKED", "ForeverTrails", "SetPreferredGamepadInteractTarget")
    equal(#h.messages, 1)
    assert(h.messages[1]:find("SetPreferredGamepadInteractTarget", 1, true))
    equal(h.FT.recorder.last, last)
    h:Fire("ADDON_ACTION_BLOCKED", "ForeverTrails", "SetPreferredGamepadInteractTarget")
    equal(#h.messages, 1)
    h:Fire("ADDON_ACTION_FORBIDDEN", "ForeverTrails", "SetFrameLevel")
    equal(#h.messages, 2)
end)

test("trail ordering follows managed layer changes after a map refresh", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    h:ShowMap(); h:Frames(4)
    local overlay = h.FT.overlay
    local before = overlay.frame:GetFrameLevel()
    local levels = h.map:GetPinFrameLevelsManager()
    assert(levels:InsertFrameLevelAbove("OTHER_ADDON_LAYER", "PIN_FRAME_LEVEL_MAP_EXPLORATION"))
    h.map:ExecuteOnAllPins(function(pin) pin:ApplyFrameLevel() end)
    h:Frames(4)
    assert(overlay.frame:GetFrameLevel() > before, "Trail did not follow the shifted layer")
    assert(overlay.frame:GetFrameLevel() > levels:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT"))
    h:HideMap(); h:ShowMap(); h:Frames(4)
    assert(overlay.frame:GetFrameLevel() < levels:GetValidFrameLevel("PIN_FRAME_LEVEL_QUEST_OFFER"))
    equal(overlay.used, 1); equal(#h.messages, 0)
end)

test("geometry does not connect different segments or map-art versions", function()
    local h = Mock.New()
    local emitted = {}
    h.FT.Geometry.Edges({
        { artID = 11, points = { {0.1,0.1}, {0.2,0.1} } },
        { artID = 12, points = { {0.2,0.1}, {0.3,0.1} } },
        { artID = 11, points = { {0.8,0.8}, {0.9,0.8} } },
    }, 11, 1000, 1000, 1, function(a,b)
        emitted[#emitted+1] = {a,b}; return true
    end, function() end)
    equal(#emitted, 2); equal(emitted[1][1][1], 0.9); equal(emitted[2][1][1], 0.2)
end)

test("large overlays yield per frame and do not mutate stored history", function()
    local h = Mock.New(); h:Boot()
    local seg = segments(h.FT.store)[1]
    for i = 2, 3000 do seg.points[i] = { 0.1 + i * 0.0001, 0.2, i } end
    h:ShowMap(); h:Frames(1)
    assert(h.FT.overlay.job and coroutine.status(h.FT.overlay.job) == "suspended")
    h:Frames(30)
    equal(h.FT.overlay.job, nil); equal(#seg.points, 3000); equal(#h.messages, 0)
end)

test("display capping retains recordings and reports truncation", function()
    local h = Mock.New(); h:Boot()
    h.FT.config.renderLineLimit = 3
    for i = 1, 9 do h:Move(0.1 + i * 0.01, 0.2 + (i % 2) * 0.02) end
    local count = h.FT.store.character.pointCount
    h:ShowMap(); h:Frames(10)
    equal(h.FT.overlay.used, 3); equal(h.FT.overlay.truncated, true)
    equal(h.FT.store.character.pointCount, count)
    h.FT.controls:Refresh()
    assert(h.FT.controls.status.textValue:find("display limit", 1, true))
    h.FT.overlay:MarkDirty(); h:Frames(10)
    for _, buffer in ipairs({ h.FT.overlay.front, h.FT.overlay.back }) do
        assert(#buffer.lines <= h.FT.config.renderLineLimit)
    end
end)

test("clearing history requires confirmation and preserves other characters", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    h.FT.db.characters.B = { name = "Alt", realm = "Forever", pointCount = 0, sessions = {} }
    SlashCmdList.FOREVERTRAILS("clear")
    equal(h.FT.store.character.pointCount, 2)
    assert(h.FT.confirmation:IsShown()); h.FT.confirmation.cancel:Click()
    equal(h.FT.confirmation:IsShown(), false); equal(h.FT.store.character.pointCount, 2)
    SlashCmdList.FOREVERTRAILS("clear")
    assert(h.FT.confirmation:IsShown()); h.FT.confirmation.delete:Click()
    equal(h.FT.store.character.pointCount, 0); assert(h.FT.db.characters.B)
    h:Move(0.12, 0.2); equal(h.FT.store.character.pointCount, 1)
end)

test("long recording remains within point and metadata retention limits", function()
    local h, rec, store = fixture({ characterPointLimit = 1000, accountPointLimit = 1500 })
    h.FT.config.tolerance = 0
    for i = 0, 25000 do
        local x = 0.2 + (i % 100) * 0.0001
        rec:Observe(sample(i, x, 0.2 + (i % 2) * 0.005))
    end
    assert(store.pointCount <= 1000)
    assert(#store.queue <= 1030)
    assert(#store.character.sessions <= 2)
    for _, entry in ipairs(store.queue) do
        if entry.removed then equal(entry.segment, nil) end
    end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
