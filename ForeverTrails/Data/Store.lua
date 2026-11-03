local _, FT = ...
local Store = {}
Store.__index = Store
FT.Store = Store

local function removeValue(array, value)
    for i, entry in ipairs(array) do
        if entry == value then table.remove(array, i); return end
    end
end

function Store.New(db, guid, name, realm, now)
    local self = setmetatable({ db = db, guid = guid, mapIndex = {}, queue = {},
        queueHead = 1, pointCount = 0, revision = 0, now = now }, Store)
    local character = db.characters[guid]
    if not character then
        character = { name = name, realm = realm, sessions = {} }
        db.characters[guid] = character
    end
    character.name, character.realm = name, realm
    self.character = character
    local sequence = 0
    for characterGUID, owner in pairs(db.characters) do
        owner.pointCount = 0
        for _, session in ipairs(owner.sessions) do
            -- A reload/crash can leave a session open. Its last observed time is the end.
            session.endedAt = session.endedAt or session.startedAt
            for _, segment in ipairs(session.segments) do
                owner.pointCount = owner.pointCount + #segment.points
                self.pointCount = self.pointCount + #segment.points
                sequence = sequence + 1
                self.queue[#self.queue + 1] = { owner = owner, session = session,
                    segment = segment, sequence = sequence }
                if characterGUID == guid then self:IndexSegment(segment) end
            end
        end
    end
    table.sort(self.queue, function(a, b)
        if a.segment.startedAt == b.segment.startedAt then return a.sequence < b.sequence end
        return a.segment.startedAt < b.segment.startedAt
    end)
    self:EnforceLimits()
    return self
end

function Store:IndexSegment(segment)
    local entries = self.mapIndex[segment.mapID] or {}
    self.mapIndex[segment.mapID] = entries
    entries[#entries + 1] = segment
end

function Store:SegmentsForMap(mapID)
    return self.mapIndex[mapID] or {}
end

function Store:SegmentLimit()
    return math.min(FT.config.maxSegmentPoints, self.db.settings.characterPointLimit,
        self.db.settings.accountPointLimit)
end

function Store:StartSegment(sample, reason)
    if not self.session then
        self.session = { startedAt = sample.time, endedAt = sample.time, segments = {} }
        local sessions = self.character.sessions
        sessions[#sessions + 1] = self.session
    end
    local segment = {
        mapID = sample.mapID, artID = sample.artID, space = sample.space,
        scaleX = sample.scaleX, scaleY = sample.scaleY, mode = sample.mode,
        startedAt = sample.time, endedAt = sample.time, breakReason = reason,
        points = {},
    }
    self.session.segments[#self.session.segments + 1] = segment
    self:IndexSegment(segment)
    self.queue[#self.queue + 1] = { owner = self.character, session = self.session, segment = segment }
    self.active = segment
    return segment
end

function Store:Touch(sample)
    self.active.endedAt = sample.time
    self.session.endedAt = sample.time
end

function Store:Append(sample, replace)
    local segment = self.active
    local point = { sample.x, sample.y, math.max(0, sample.time - segment.startedAt) }
    if replace then
        segment.points[#segment.points] = point
    else
        segment.points[#segment.points + 1] = point
        self.pointCount = self.pointCount + 1
        self.character.pointCount = self.character.pointCount + 1
    end
    self:Touch(sample)
    self.revision = self.revision + 1
    self:EnforceLimits()
end

function Store:CloseSegment()
    self.active = nil
end

function Store:RemoveEntry(entry)
    local segment, owner, session = entry.segment, entry.owner, entry.session
    local count = #segment.points
    self.pointCount = self.pointCount - count
    owner.pointCount = owner.pointCount - count
    removeValue(session.segments, segment)
    if #session.segments == 0 then
        removeValue(owner.sessions, session)
        if self.session == session then self.session = nil end
    end
    if owner == self.character then
        removeValue(self.mapIndex[segment.mapID], segment)
    end
    entry.removed = true
    -- A tombstone must not keep pruned point arrays alive until queue compaction.
    entry.segment, entry.owner, entry.session = nil, nil, nil
    self.revision = self.revision + 1
end

function Store:EnforceLimits()
    -- The queue contains segment references, not copies of all point data.
    for i = self.queueHead, #self.queue do
        local entry = self.queue[i]
        if not entry.removed and entry.segment ~= self.active then
            if self.pointCount > self.db.settings.accountPointLimit
                or entry.owner.pointCount > self.db.settings.characterPointLimit then
                self:RemoveEntry(entry)
            end
        end
        if self.pointCount <= self.db.settings.accountPointLimit then
            local over = false
            for _, owner in pairs(self.db.characters) do
                if owner.pointCount > self.db.settings.characterPointLimit then over = true; break end
            end
            if not over then break end
        end
    end
    while self.queue[self.queueHead] and self.queue[self.queueHead].removed do
        self.queueHead = self.queueHead + 1
    end
    if self.queueHead > 1024 then
        local queue = {}
        for _, entry in ipairs(self.queue) do
            if not entry.removed then queue[#queue + 1] = entry end
        end
        self.queue, self.queueHead = queue, 1
    end
end

function Store:OldestTime()
    local oldest
    for _, session in ipairs(self.character.sessions) do
        for _, segment in ipairs(session.segments) do
            if not oldest or segment.startedAt < oldest then oldest = segment.startedAt end
        end
    end
    return oldest
end

function Store:ClearCharacter()
    self.active, self.session = nil, nil
    for _, entry in ipairs(self.queue) do
        if not entry.removed and entry.owner == self.character then self:RemoveEntry(entry) end
    end
    self.mapIndex = {}
    self:EnforceLimits()
end
