local addonName, FT = ...
local Compat = {}
FT.Compat = Compat

function Compat.IsNumber(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function Compat.Now()
    return GetServerTime and GetServerTime() or time()
end

function Compat.Version()
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return metadata and metadata(addonName, "Version") or "unknown"
end

local function readableTrue(fn)
    if not fn then return false end
    local value = fn("player")
    if issecretvalue and issecretvalue(value) then return false end
    return value == true or value == 1
end

local function readPosition()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return nil, "Map API unavailable"
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not Compat.IsNumber(mapID) or mapID <= 0 then return nil, "No player map" end
    local info = C_Map.GetMapInfo(mapID)
    -- UIMapType: Zone=3, Dungeon=4, Micro=5. Do not record a continent fallback.
    if not info or not Compat.IsNumber(info.mapType)
        or info.mapType < 3 or info.mapType > 5 then
        return nil, "No supported zone or floor map"
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil, "Position unavailable in this area" end
    local x, y = pos:GetXY()
    if not Compat.IsNumber(x) or not Compat.IsNumber(y)
        or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then
        return nil, "Position unavailable in this area"
    end
    local artID = C_Map.GetMapArtID and C_Map.GetMapArtID(mapID) or 0
    if not Compat.IsNumber(artID) then return nil, "Map art unavailable" end
    local width, height
    if C_Map.GetMapWorldSize then
        -- Missing dimensions should not disable otherwise usable map coordinates.
        local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
        if ok and Compat.IsNumber(w) and Compat.IsNumber(h) and w > 0 and h > 0 then
            width, height = w, h
        end
    end
    local mode = "foot"
    if readableTrue(UnitOnTaxi) then mode = "flight"
    elseif readableTrue(UnitIsGhost) then mode = "ghost"
    elseif readableTrue(IsSwimming) then mode = "swimming"
    elseif readableTrue(IsMounted) then mode = "mounted" end

    return {
        mapID = mapID, artID = artID, x = x, y = y,
        scaleX = width or 1, scaleY = height or 1,
        space = width and "yards" or "normalised", mode = mode,
        time = Compat.Now(), tick = GetTime(),
    }
end

function Compat.ReadPosition()
    -- Secret/restricted values must never reach comparisons, geometry or SavedVariables.
    local ok, sample, reason = pcall(readPosition)
    if not ok then return nil, "Position temporarily restricted" end
    return sample, reason
end
