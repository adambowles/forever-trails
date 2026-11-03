local _, FT = ...

FT.defaults = {
    recording = true,
    showTrails = true,
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
    renderLineLimit = 4096,          -- two pooled Line regions per edge
    renderTolerance = 1.25,          -- pixels in the map viewport
}
