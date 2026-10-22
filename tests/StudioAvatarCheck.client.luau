-- CLIENT Command Bar in Roblox Studio, during Play (not Run). Run once before
-- finding a key, then again while carrying a key from a drawer (door 005).
local player = game:GetService("Players").LocalPlayer
assert(player, "Run this in the CLIENT Command Bar during Play")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local head = character:WaitForChild("Head")
task.wait(0.25)
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("CameraBuild") == "NativeFirstPerson-v7",
	"Open Nocturne-v7.rbxl in a NEW Studio tab")
local camera = workspace.CurrentCamera
assert(player.CameraMode == Enum.CameraMode.LockFirstPerson)
assert(camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
	"First person must follow the REAL Roblox Humanoid")
assert((camera.CFrame.Position - head.Position).Magnitude < 2.5,
	"Camera is detached from the character's head")
assert(not root.Anchored and humanoid.AutoRotate, "Character movement is locked")
assert(humanoid.FloorMaterial ~= Enum.Material.Air, "Character is not standing on a floor")
local real = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
assert(real and real.Transparency < 0.95, "Normal Roblox avatar hands are missing")
local view = camera:FindFirstChild("AvatarArmsFirstPerson")
assert(view, "Key-only avatar display is missing")
assert(not view:FindFirstChild("LeftHand") and not view:FindFirstChild("Left Arm"),
	"An unrelated left arm is floating beside the key")
local held = player:GetAttribute("HeldKey")
local displayed, inFrame = 0, 0
local vertical = math.tan(math.rad(camera.FieldOfView / 2))
local horizontal = vertical * camera.ViewportSize.X / camera.ViewportSize.Y
for _, part in ipairs(view:GetChildren()) do
	if part:IsA("BasePart") then
		assert(part.Anchored and not part.CanCollide and not part.CanTouch,
			"Copied arm must NEVER affect avatar physics")
		if part.Transparency < 0.95 then
			displayed = displayed + 1
			local v = camera.CFrame:PointToObjectSpace(part.Position)
			if v.Z < -0.2 and math.abs(v.Y) < -v.Z * vertical
				and math.abs(v.X) < -v.Z * horizontal then
				inFrame = inFrame + 1
			end
		end
	end
end
if held then
	local physical = character:FindFirstChild("HeldKey")
	local replica = view:FindFirstChild("Key in avatar hand")
	assert(physical and physical:FindFirstChild("Key stem"),
		"Physical drawer key is not in the right Roblox hand")
	assert(replica and replica:FindFirstChild("Key stem"),
		"Visible first-person copy of the same key is missing")
	assert(displayed >= 1 and inFrame >= 1,
		"The normal-sized gripping arm is not in the camera frame")
else
	assert(displayed == 0 and not view:FindFirstChild("Key in avatar hand"),
		"Arm appeared before a key was picked up")
end
print("NOCTURNE v7: real Humanoid grounded, native right arm", held or "no key",
	displayed, inFrame)
