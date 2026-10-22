-- Optional Roblox Studio SERVER Command Bar smoke test. Press Play first.
-- This only inspects the scene; it will not teleport or reset your character.
local world = workspace:WaitForChild("NocturneWorld", 15)
assert(world, "Server generator did not create NocturneWorld")
local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("NocturneLayout"))
assert(world:GetAttribute("TotalDoors") == 100)
assert(world:GetAttribute("CameraBuild") == "NativeFirstPerson-v10"
	and world:GetAttribute("GenerationBuild") == "SinglePressWardrobe-v13",
	"Old place loaded: open Nocturne-v13.rbxl in a NEW Studio tab")
assert(world:GetAttribute("DoorsOpened") == 0, "Start a fresh Play session")
assert(world:GetAttribute("Storeys") == 18)
assert(math.abs(workspace.Gravity - 196.2) < 0.01, "Gravity is disabled: the player will float")
assert(not workspace.StreamingEnabled, "Floor geometry must not stream out from under the player")
assert(game:GetService("SoundService").AmbientReverb == Enum.ReverbType.Hallway,
	"Audio reverb was not enabled in Play")

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
	assert(type(room:GetAttribute("Shape")) == "string" and type(room:GetAttribute("Dark")) == "boolean",
		"Room shape/darkness were not generated")
	local air = room:FindFirstChild("Low draught in the masonry", true)
	assert(air and air:IsA("Sound") and air.Looped
		and air:FindFirstChildOfClass("EchoSoundEffect")
		and air:FindFirstChildOfClass("ReverbSoundEffect"),
		"A generated room has no playable spatial ambience with reflections")
	if index == 0 then
		local shape = room:GetAttribute("Shape")
		assert(shape ~= "FIXED", "First room is still the old, constant foyer")
		local required = {AISLE = "Side aisle masonry screen",
			ROTUNDA = "Rotunda monolithic column", NAVE = "Nave transept masonry",
			CRYPT = "Crypt sealed plinth", VESTIBULE = "Vestibule cross-wall",
			ARCADE = "Freestanding marble arcade column",
			COFFERED = "Deep coffered cross-vault"}
		assert(not required[shape] or room:FindFirstChild(required[shape]),
			"A random architecture label did not build a visible structure")
		print("NOCTURNE v13 seed", world:GetAttribute("Seed"), "first room",
			room:GetAttribute("Variant"), shape, "— compare these after a NEW Play")
	end
	assert(room:FindFirstChild("Wardrobe_A") and room:FindFirstChild("Wardrobe_B"),
		"A generated room has fewer than two accessible hiding places")
	for _, name in ipairs({"Wardrobe_A", "Wardrobe_B"}) do
		local wardrobe = room:FindFirstChild(name)
		assert(wardrobe:FindFirstChild("Left hinged leaf") and wardrobe:FindFirstChild("Right hinged leaf"),
			"Wardrobe has no moving leaves")
		local hidePrompt = wardrobe:FindFirstChild("HideInside", true)
		assert(hidePrompt and hidePrompt.HoldDuration == 0
			and not wardrobe:FindFirstChild("CloseWardrobe", true),
			"Wardrobe requires extra presses to open or close instead of one to enter")
	end
	if not Layout.IsStair(index) then
		local floor = room:FindFirstChild("Continuous wooden subfloor")
		local inlay = room:FindFirstChild("Inlaid floorboard joint")
		local rosette = room:FindFirstChild("Pressed metal ceiling rosette")
		local shade = room:FindFirstChild("Smoked glass lamp shade")
		assert(inlay and rosette and shade and not inlay.CanCollide
			and not rosette.CanCollide and not shade.CanCollide,
			"material detail is missing or blocks the player")
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
	assert(prompt.ActionText == "" and prompt.ObjectText == "", "No text hints over the game")
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
local side = Layout.TurnSide(6, world:GetAttribute("Seed"))
assert(Layout.PathX(6, 17, world:GetAttribute("Seed")) == side * 8
	and Layout.PathX(6, 28, world:GetAttribute("Seed")) == -side * 8)
local spawn = world:FindFirstChild("CheckpointSpawn")
assert(spawn and spawn.CanCollide and spawn.Anchored
	and math.abs(spawn.Position.Y + spawn.Size.Y / 2 - Layout.EntranceY(0)) < 0.01,
	"Checkpoint spawn pad is not flush with the solid foyer floor")
assert(game:GetService("ReplicatedStorage"):FindFirstChild("NocturneRemote"))
-- Unlike an XML inspection, this checks whether the live avatar is grounded.
local player = game:GetService("Players"):GetPlayers()[1]
if player then
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	task.wait(1) -- allow the avatar to settle on the floor after spawning
	assert(not root.Anchored and humanoid.AutoRotate, "Avatar physics/rotation is disabled")
	assert(player:GetAttribute("HasFlashlight") == false and player:GetAttribute("TorchOn") == false
		and player:GetAttribute("EquippedItem") == nil and not character:FindFirstChild("HeldItem"),
		"Starting avatar received a free flashlight or a floating item")
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
