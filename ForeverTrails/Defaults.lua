local _, FT = ...

FT.defaults = {
    recording = true,
    showTrails = true,
    trailColour = "green",
    characterPointLimit = 200000,
    accountPointLimit = 500000,
}

FT.config = {
    sampleInterval = 1,
    maxSampleGap = 5,
    minDistance = 2,                  -- yards when map dimensions are available
    fallbackMinDistance = 0.0004,    -- fraction of the map otherwise
    tolerance = 1,
    fallbackTolerance = 0.0002,
    maxSimplifySeconds = 10,
    maxSegmentPoints = 512,
    maxSegmentSeconds = 300,
    renderPointBudget = 300,         -- input points processed per frame
    renderLineLimit = 4096,          -- per buffer; two pooled Line regions per edge
    renderTolerance = 1.25,          -- pixels in the map viewport
}

FT.colourPresets = {
    { id = "green", name = "Green", r = 0.30, g = 0.85, b = 0.45 },
    { id = "cyan",  name = "Cyan",  r = 0.20, g = 0.90, b = 0.95 },
    { id = "blue",  name = "Blue",  r = 0.30, g = 0.55, b = 1.00 },
    { id = "gold",  name = "Gold",  r = 1.00, g = 0.78, b = 0.20 },
    { id = "red",   name = "Red",   r = 1.00, g = 0.30, b = 0.30 },
    { id = "white", name = "White", r = 1.00, g = 1.00, b = 1.00 },
}
FT.colourByID = {}
for _, preset in ipairs(FT.colourPresets) do FT.colourByID[preset.id] = preset end

function FT.GetTrailColour()
    local id = FT.db and FT.db.settings.trailColour
    return FT.colourByID[id] or FT.colourByID[FT.defaults.trailColour]
end
