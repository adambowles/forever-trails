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
    overlay.provider:OnCanvasScaleChanged(); h:Frames(4)
    equal(overlay.lines[1].trail, line); equal(line.thickness, 1)
    h.map.canvas:SetSize(2000, 1000)
    overlay.provider:OnCanvasSizeChanged(); h:Frames(4)
    equal(line.start[1], 220); equal(line.start[2], -200)
    h:HideMap(); equal(overlay.used, 0); equal(overlay.frame.scripts.OnUpdate, nil)
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
end)

test("clearing history requires confirmation and preserves other characters", function()
    local h = Mock.New(); h:Boot(); h:Move(0.11, 0.2)
    h.FT.db.characters.B = { name = "Alt", realm = "Forever", pointCount = 0, sessions = {} }
    SlashCmdList.FOREVERTRAILS("clear")
    equal(h.FT.store.character.pointCount, 2)
    assert(h.popup and h.popup.OnAccept); h.popup.OnAccept()
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
