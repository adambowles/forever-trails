local _, FT = ...
local Recorder = {}
Recorder.__index = Recorder
FT.Recorder = Recorder

function Recorder.New(store)
    return setmetatable({ store = store, reason = "session" }, Recorder)
end

function Recorder:Break(reason)
    self.store:CloseSegment()
    self.last, self.idleSince = nil, nil
    self.reason = reason
end

local function distance(a, b)
    return FT.Simplify.Distance({ a.x, a.y }, { b.x, b.y }, b.scaleX, b.scaleY)
end

local function boundary(a, b)
    if a.mapID ~= b.mapID then return "map" end
    if a.artID ~= b.artID then return "map-art" end
    if a.space ~= b.space or a.scaleX ~= b.scaleX or a.scaleY ~= b.scaleY then return "coordinates" end
    if a.mode ~= b.mode then return "movement" end
    local dt = b.tick - a.tick
    if dt <= 0 or dt > FT.config.maxSampleGap or b.time < a.time then return "sample-gap" end
    local maximum = b.space == "yards" and (b.mode == "flight" and 200 or 70) or 0.06
    local slack = b.space == "yards" and 25 or 0.005
    if distance(a, b) > maximum * dt + slack then return "position-jump" end
end

function Recorder:Start(sample, reason)
    self.store:StartSegment(sample, reason)
    self.store:Append(sample)
    self.last, self.idleSince = sample, nil
end

function Recorder:Observe(sample, unavailableReason)
    if not sample then
        self:Break("unavailable")
        self.status = unavailableReason or "Position unavailable in this area"
        return
    end
    self.status = "Recording"
    local previous = self.last
    local reason = previous and boundary(previous, sample)
    if reason then self:Break(reason) end
    if not self.store.active then self:Start(sample, self.reason); return end

    local segment = self.store.active
    -- Bound active segments so complete old segments can always be pruned.
    if #segment.points >= self.store:SegmentLimit()
        or sample.time - segment.startedAt >= FT.config.maxSegmentSeconds then
        self:Break("chunk")
        self:Start(previous, "chunk") -- repeat only the boundary point to preserve continuity
        segment = self.store.active
    end
    local points, minimum = segment.points, FT.config.minDistance
    if sample.space ~= "yards" then minimum = FT.config.fallbackMinDistance end
    local lastPoint = points[#points]
    local moved = FT.Simplify.Distance(lastPoint, { sample.x, sample.y }, sample.scaleX, sample.scaleY)
    if moved < minimum then
        if distance(previous, sample) < minimum * 0.1 then
            self.idleSince = self.idleSince or previous.time
        end
        self.store:Touch(sample)
        self.last = sample
        return
    end

    local idle = self.idleSince and previous.time - self.idleSince >= 2
    if idle and previous.time > segment.startedAt + lastPoint[3]
        and #points < self.store:SegmentLimit() - 1 then
        -- Preserve the departure time, without generating points throughout the idle period.
        self.store:Append(previous)
    end
    local candidate = { sample.x, sample.y, sample.time - segment.startedAt }
    local tolerance = sample.space == "yards" and FT.config.tolerance or FT.config.fallbackTolerance
    local replace = not idle and #points >= 2 and FT.Simplify.CanReplace(
        points[#points - 1], points[#points], candidate, sample.scaleX, sample.scaleY, tolerance)
    self.store:Append(sample, replace)
    self.last, self.idleSince = sample, nil
end
