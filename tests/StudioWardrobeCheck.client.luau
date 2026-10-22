-- Optional CLIENT Command Bar check in Studio Play. Stand in front of a
-- closed wardrobe, run this, click the viewport and press E ONCE. No prompts
-- are fired by this test; it watches the actual input and physical avatar.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player, "Run in the CLIENT Command Bar during Play, not Run")
local world = workspace:WaitForChild("NocturneWorld", 10)
assert(world and world:GetAttribute("GenerationBuild") == "WhiteVoidAndBlindAudio-v15",
	"Open Nocturne-v15.rbxl in a NEW Studio tab and press Play")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
assert(humanoid.Health > 0 and not player:GetAttribute("Hidden")
	and not player:GetAttribute("EnteringWardrobe"), "Start OUTSIDE a wardrobe")
local prompt, closest = nil, math.huge
for _, object in ipairs(world:GetDescendants()) do
	if object:IsA("ProximityPrompt") and object.Name == "HideInside" and object.Enabled then
		local distance = (object.Parent.Position - root.Position).Magnitude
		if distance < closest then prompt, closest = object, distance end
	end
end
assert(prompt and closest < 5.3, "Stand immediately in front of a wardrobe before running this")
local wardrobe = prompt.Parent.Parent.Parent
assert(wardrobe:IsA("Model") and wardrobe.Name:match("^Wardrobe_")
	and prompt.HoldDuration == 0 and not wardrobe:FindFirstChild("CloseWardrobe", true),
	"This wardrobe still has a separate open/close action")
local start = root.Position
local sawEntry, sawOpen, sawMovement = false, false, false
print("Wardrobe check: click the viewport and press E once near", wardrobe.Name)
local deadline = os.clock() + 12
while not player:GetAttribute("Hidden") and os.clock() < deadline do
	if player:GetAttribute("EnteringWardrobe") then
		sawEntry = true
		assert(workspace.CurrentCamera.CameraType == Enum.CameraType.Custom
			and workspace.CurrentCamera.CameraSubject == humanoid,
			"The entry animation detached the first-person camera from the real Humanoid")
		if (root.Position - start).Magnitude > 0.35 then sawMovement = true end
	end
	if wardrobe:GetAttribute("Open") then sawOpen = true end
	task.wait(0.03)
end
task.wait(0.12) -- allow attributes and the final physical root pose to replicate
if (root.Position - start).Magnitude > 0.35 then sawMovement = true end
assert(sawEntry and sawOpen and sawMovement and player:GetAttribute("Hidden")
	and not player:GetAttribute("EnteringWardrobe") and root.Anchored,
	"One press did not open the leaves and MOVE the real avatar into hiding")
task.wait(0.36) -- allow the real leaves to close behind the avatar
assert(wardrobe:GetAttribute("Open") == false and not prompt.Enabled
	and workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable,
	"Wardrobe stayed open or the view did not move behind the real slats")
print("Wardrobe check: entered and closed with one E. Press E again to leave.")
