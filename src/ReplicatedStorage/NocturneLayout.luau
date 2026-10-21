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

-- A dogleg stays within a sealed room; both doorways still meet at x = 0.
-- Keep the tutorial turn at room 6. Each later group of ten has ONE seeded
-- candidate, avoiding stairs. This changes the actual route between runs,
-- while retaining exactly ten walkable turns and 100 connected doorways.
function Layout.IsTurn(index, seed)
	if index == 6 then return true end
	if seed == nil then return index >= 16 and index % 10 == 6 end
	local group = math.floor(index / 10)
	if group < 1 or group > 9 then return false end
	local candidates = {}
	for candidate = group * 10 + 2, math.min(group * 10 + 9, 99) do
		if not Layout.IsStair(candidate) and candidate ~= 15 then
			table.insert(candidates, candidate)
		end
	end
	local n = seed % 1000003 + group * 7919
	local mixed = (n * 48271 + 12347) % 2147483647
	return index == candidates[math.floor(mixed / 47) % #candidates + 1]
end

-- Seeded LEFT/RIGHT direction adds more variation without breaking geometry.
function Layout.TurnSide(index, seed)
	local n = ((seed or 0) % 1000003) + math.floor(index / 10) * 7919
	local mixed = (n * 48271 + 12347) % 2147483647
	return math.floor(mixed / 65536) % 2 == 0 and 1 or -1
end

-- Monsters follow both offset openings instead of cutting through partitions.
-- Values at z=17 and z=28 are the centres of the two archways.
function Layout.PathX(index, localZ, seed)
	if not Layout.IsTurn(index, seed) then return 0 end
	local side = Layout.TurnSide(index, seed)
	local stops = {{0, 0}, {12, 8}, {17, 8}, {28, -8}, {33, -8}, {40, 0}, {44, 0}}
	for i = 2, #stops do
		if localZ <= stops[i][1] then
			local a, b = stops[i - 1], stops[i]
			local t = math.max(0, math.min(1, (localZ - a[1]) / (b[1] - a[1])))
			return side * (a[2] + (b[2] - a[2]) * t)
		end
	end
	return 0
end

function Layout.RoomIndexAt(z)
	return math.max(0, math.floor(z / Layout.RoomLength))
end

return Layout
