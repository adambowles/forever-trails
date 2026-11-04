local _, FT = ...
local Simplify = {}
FT.Simplify = Simplify

function Simplify.Distance(a, b, scaleX, scaleY)
    local dx, dy = (b[1] - a[1]) * scaleX, (b[2] - a[2]) * scaleY
    return math.sqrt(dx * dx + dy * dy)
end

function Simplify.Deviation(a, b, c, scaleX, scaleY)
    local dx, dy = (c[1] - a[1]) * scaleX, (c[2] - a[2]) * scaleY
    local bx, by = (b[1] - a[1]) * scaleX, (b[2] - a[2]) * scaleY
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared == 0 then return math.sqrt(bx * bx + by * by), false end
    local projection = (bx * dx + by * dy) / lengthSquared
    local t = math.max(0, math.min(1, projection))
    local ex, ey = bx - t * dx, by - t * dy
    return math.sqrt(ex * ex + ey * ey), projection > 0 and projection < 1
end

function Simplify.CanReplace(a, b, c, scaleX, scaleY, tolerance)
    -- Duplicate positions carry idle arrival/departure times; preserve both.
    if (a[1] == b[1] and a[2] == b[2]) or (b[1] == c[1] and b[2] == c[2]) then
        return false
    end
    if c[3] - a[3] > FT.config.maxSimplifySeconds then return false end
    local deviation, forward = Simplify.Deviation(a, b, c, scaleX, scaleY)
    return forward and deviation <= tolerance
end
