-- CLIENT Command Bar during Play (not Run): once without a key, again with
-- one from any LOCKED room. A native Roblox R6/R15 avatar stays grounded.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player, "Run this in the CLIENT Command Bar during Play")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local head = character:WaitForChild("Head")
task.wait(0.3)
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("CameraBuild") == "NativeFirstPerson-v8",
	"Open Nocturne-v8.rbxl in a NEW Studio tab")
local camera = workspace.CurrentCamera
assert(player.CameraMode == Enum.CameraMode.LockFirstPerson)
assert(camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
	"First person must follow the REAL Roblox Humanoid")
assert((camera.CFrame.Position - head.Position).Magnitude < 2.5,
	"Camera is detached from the character's head")
assert(not root.Anchored and humanoid.AutoRotate, "Character movement is locked")
assert(humanoid.FloorMaterial ~= Enum.Material.Air, "Character is not standing on a floor")
assert(not camera:FindFirstChild("AvatarArmsFirstPerson"),
	"Old detached viewmodel still covers the natural Roblox arm")
local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
local shoulder = character:FindFirstChild("RightShoulder", true)
	or character:FindFirstChild("Right Shoulder", true)
assert(right and shoulder and shoulder:IsA("Motor6D") and right.Transparency < 0.95,
	"Right hand must be part of the actual R6/R15 character and its joints")
local held = player:GetAttribute("HeldKey")
if held then
	local model = character:FindFirstChild("HeldKey")
	local grip = model and model:FindFirstChild("Key grip in Roblox hand", true)
	assert(model and model:FindFirstChild("Key stem", true)
		and grip and grip.Part0 == right and grip.Part1,
		"The drawer's physical key is not welded to the native hand")
	assert(right.LocalTransparencyModifier < 0.1
		and grip.Part1.LocalTransparencyModifier < 0.1,
		"Actual right hand/key were not revealed in the first-person view")
	local cam = camera.CFrame:PointToObjectSpace(right.Position)
	assert(cam.Z < 1.5, "Key arm is behind the player's head; inspect pose in Studio")
else
	assert(not character:FindFirstChild("HeldKey"), "A key is visible before pickup")
	assert(right.LocalTransparencyModifier > 0.9,
		"An arm hovers onscreen even when no key is held")
end
print("NOCTURNE v8: native first person, grounded humanoid, actual joined right arm",
	held or "no key", right.LocalTransparencyModifier)
