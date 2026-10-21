-- Optional Roblox Studio SERVER Command Bar smoke test. Press Play first.
-- This only inspects the scene; it will not teleport or reset your character.
local world = workspace:WaitForChild("NocturneWorld", 15)
assert(world, "Server generator did not create NocturneWorld")
local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("NocturneLayout"))
assert(world:GetAttribute("TotalDoors") == 100)
assert(world:GetAttribute("DoorsOpened") == 0, "Start a fresh Play session")
assert(world:GetAttribute("Storeys") == 18)
assert(math.abs(workspace.Gravity - 196.2) < 0.01, "Gravity is disabled: the player will float")
assert(not workspace.StreamingEnabled, "Floor geometry must not stream out from under the player")

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
	for _, name in ipairs({"Wardrobe_A", "Wardrobe_B"}) do
		local wardrobe = room:FindFirstChild(name)
		assert(wardrobe:FindFirstChild("Left hinged leaf") and wardrobe:FindFirstChild("Right hinged leaf"),
			"Wardrobe has no moving leaves")
		assert(wardrobe:FindFirstChild("HideInside", true), "Wardrobe has no interaction")
	end
	if not Layout.IsStair(index) then
		local floor = room:FindFirstChild("Continuous wooden subfloor")
		assert(floor and floor.Anchored and floor.CanCollide
			and math.abs(floor.Position.Y + floor.Size.Y / 2 - Layout.EntranceY(index)) < 0.01,
			"The playable room has no solid floor")
		for _, wall in ipairs(room:GetChildren()) do
			if wall.Name == "Load-bearing corridor wall" then
				assert(wall.Anchored and wall.CanCollide, "Corridor wall has no collision")
			end
		end
		local dresser = room:FindFirstChild("Three-drawer dresser")
		assert(dresser and dresser:FindFirstChild("Drawer_1") and dresser:FindFirstChild("Drawer_3"),
			"A searchable dresser is missing")
	end
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
			if part.Name == "Solid stair tread" or part.Name == "Solid enclosed stair flank" then
				assert(part.Anchored and part.CanCollide, "Stair treads and walls must be solid")
				if part.Name == "Solid stair tread" then treads = treads + 1 else flanks = flanks + 1 end
			end
		end
		for _, name in ipairs({"Lower stair landing", "Upper stair landing"}) do
			local landing = room:FindFirstChild(name)
			assert(landing and landing.Anchored and landing.CanCollide, "Missing solid " .. name)
		end
		assert(treads == 16 and flanks == 2, "Stairs are open-sided or incomplete")
	end
end
for index = 0, 99 do
	assert(Layout.ExitY(index) == Layout.EntranceY(index + 1),
		"Disconnected doorway after room " .. index)
end
assert(Layout.IsTurn(6) and not Layout.IsStair(6))
assert(Layout.PathX(6, 17) == 8 and Layout.PathX(6, 28) == -8)
assert(world:FindFirstChild("CheckpointSpawn"), "Missing checkpoint spawn")
assert(game:GetService("ReplicatedStorage"):FindFirstChild("NocturneRemote"))
-- Unlike an XML inspection, this checks whether the live avatar is grounded.
local player = game:GetService("Players"):GetPlayers()[1]
if player then
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	task.wait(1) -- allow the avatar to settle on the floor after spawning
	assert(not root.Anchored and humanoid.AutoRotate, "Avatar physics/rotation is disabled")
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Exclude
	cast.FilterDescendantsInstances = {character}
	cast.RespectCanCollide = true
	local ground = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), cast)
	assert(ground and ground.Instance:IsDescendantOf(world)
		and root.Position.Y - ground.Position.Y < 6, "No walkable geometry below the avatar")
	assert(humanoid.FloorMaterial ~= Enum.Material.Air, "Avatar is not physically standing on the floor")
end
print("NOCTURNE: 100 connected doors; solid floors/stairs/walls; avatar grounded; Play-test threats separately")
