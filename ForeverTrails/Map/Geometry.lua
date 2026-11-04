local _, FT = ...
FT.Geometry = {}

-- Produces recent segments first. No edge may cross a segment or a map-art boundary.
function FT.Geometry.Edges(segments, artID, width, height, scale, emit, checkpoint)
    local sx, sy = width * scale, height * scale
    for i = #segments, 1, -1 do
        local segment = segments[i]
        if segment.artID == artID then
            local points = segment.points
            local anchor, previous
            for j = #points, 1, -1 do
                local point = points[j]
                if not anchor then
                    anchor = point
                elseif not previous then
                    previous = point
                else
                    local deviation, forward = FT.Simplify.Deviation(anchor, previous, point, sx, sy)
                    if not forward or deviation > FT.config.renderTolerance
                        or FT.Simplify.Distance(anchor, point, sx, sy) > 128 then
                        if not emit(anchor, previous) then return false end
                        anchor = previous
                    end
                    previous = point
                end
                checkpoint()
            end
            if previous and not emit(anchor, previous) then return false end
        end
        checkpoint()
    end
    return true
end
