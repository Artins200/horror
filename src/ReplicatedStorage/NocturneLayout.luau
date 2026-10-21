-- Single source of truth for the hotel's physical route. The same module is
-- available to the server generator and to the first-person HUD.
local Layout = {
	RoomLength = 44,
	RoomWidth = 30,
	RoomHeight = 16,
	DoorWidth = 7.4,
	RoomsPerStorey = 6,
	StoreyRise = 12,
	StairWidth = 13,
	StairSteps = 16,
	StairStart = 7,
	StairEnd = 37,
}

-- The first staircase follows door 001. Thereafter it occurs every six rooms.
function Layout.IsStair(index)
	return index > 0 and index % Layout.RoomsPerStorey == 1
end

function Layout.EntranceY(index)
	assert(index >= 0, "Room index must be non-negative")
	return math.floor((index + Layout.RoomsPerStorey - 2) / Layout.RoomsPerStorey) * Layout.StoreyRise
end

function Layout.ExitY(index)
	return Layout.EntranceY(index) + (Layout.IsStair(index) and Layout.StoreyRise or 0)
end

-- The step at z is solid all the way down to its foundation. Positions exactly
-- at a boundary use the LOWER tread, so there is no accidental raised lip.
function Layout.WalkwayY(index, localZ)
	local base = Layout.EntranceY(index)
	if not Layout.IsStair(index) or localZ <= Layout.StairStart then return base end
	if localZ >= Layout.StairEnd then return base + Layout.StoreyRise end
	local progress = (localZ - Layout.StairStart) / (Layout.StairEnd - Layout.StairStart)
	local step = math.min(Layout.StairSteps, math.max(1, math.ceil(progress * Layout.StairSteps)))
	return base + step * Layout.StoreyRise / Layout.StairSteps
end

function Layout.RoomIndexAt(z)
	return math.max(0, math.floor(z / Layout.RoomLength))
end

return Layout
