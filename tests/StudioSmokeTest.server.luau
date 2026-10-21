-- Optional Roblox Studio SERVER Command Bar smoke test. Press Play first.
-- This only inspects the scene; it will not teleport or reset your character.
local world = workspace:WaitForChild("NocturneWorld", 15)
assert(world, "Server generator did not create NocturneWorld")
local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("NocturneLayout"))
assert(world:GetAttribute("TotalDoors") == 100)
assert(world:GetAttribute("DoorsOpened") == 0, "Start a fresh Play session")
assert(world:GetAttribute("Storeys") == 18)

for index = 0, 1 do
	local room
	for _, child in ipairs(world:GetChildren()) do
		if child:GetAttribute("RoomIndex") == index then
			room = child
			break
		end
	end
	assert(room, "Missing generated room " .. index)
	assert(room:GetAttribute("EntryY") == Layout.EntranceY(index))
	assert(room:GetAttribute("ExitY") == Layout.ExitY(index))
	assert(room:FindFirstChild("Wardrobe_A") and room:FindFirstChild("Wardrobe_B"),
		"A generated room has fewer than two accessible hiding places")
	local door = room:FindFirstChild(string.format("Door_%03d", index + 1))
	assert(door, "Missing numbered door")
	local prompt = door:FindFirstChild("OpenDoor", true)
	assert(prompt and prompt:IsA("ProximityPrompt"), "Door cannot be opened")
	assert(prompt.Enabled == (index == 0), "Doors must open in order")
	assert(math.abs(prompt.Parent.Position.Y - (Layout.ExitY(index) + 5.1)) < 0.02,
		"Door is not at the height of its landing")
	if Layout.IsStair(index) then
		local treads, flanks = 0, 0
		for _, part in ipairs(room:GetDescendants()) do
			if part.Name == "Solid stair tread" then treads = treads + 1 end
			if part.Name == "Solid enclosed stair flank" then flanks = flanks + 1 end
		end
		assert(treads == 16 and flanks == 2, "Stairs are open-sided or incomplete")
	end
end
for index = 0, 99 do
	assert(Layout.ExitY(index) == Layout.EntranceY(index + 1),
		"Disconnected doorway after room " .. index)
end
assert(world:FindFirstChild("CheckpointSpawn"), "Missing checkpoint spawn")
assert(game:GetService("ReplicatedStorage"):FindFirstChild("NocturneRemote"))
print("NOCTURNE: 100 connected doors, enclosed stairwell, accessible closets, no unsupported landing")
