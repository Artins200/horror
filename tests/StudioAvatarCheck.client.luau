-- Optional CLIENT Command Bar check in Roblox Studio, in a fresh Play session.
-- Native first-person camera must stay attached to the real, grounded avatar.
local player = game:GetService("Players").LocalPlayer
assert(player, "Run this in the CLIENT Command Bar while playing")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local head = character:WaitForChild("Head")
task.wait(2)
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("CameraBuild") == "NativeFirstPerson-v5",
	"Open Nocturne-v5.rbxl in a NEW Studio tab, not the cached v4")
local camera = workspace.CurrentCamera
assert(player.CameraMode == Enum.CameraMode.LockFirstPerson, "First-person camera is not enabled")
assert(camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
	"First-person camera must follow the REAL Humanoid, not a scriptable ghost")
assert((camera.CFrame.Position - head.Position).Magnitude < 2.5,
	"Camera is detached from the avatar's head")
assert(not root.Anchored and humanoid.AutoRotate, "Character movement is locked")
assert(humanoid.FloorMaterial ~= Enum.Material.Air, "Character is not standing on the floor")
-- Roblox itself may locally fade the head in first person. The game must not
-- change the real character's Transparency, nor use a pixel-block substitute.
local realArm = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
assert(realArm and realArm.Transparency < 0.95, "Roblox avatar limbs are not present")
local view = camera:FindFirstChild("AvatarArmsFirstPerson")
assert(view, "No first-person copies of the Roblox avatar arms")
local displayed, inFrame = 0, 0
local vertical = math.tan(math.rad(camera.FieldOfView / 2))
for _, part in ipairs(view:GetChildren()) do
	if part:IsA("BasePart") then
		assert(part.Anchored and not part.CanCollide and not part.CanTouch,
			"Display arm unexpectedly affects player collision")
		if part.Name ~= "Invisible torch light source" and part.Transparency < 0.95 then
			displayed = displayed + 1
			local localPoint = camera.CFrame:PointToObjectSpace(part.Position)
			if localPoint.Z < -0.2 and math.abs(localPoint.Y) < -localPoint.Z * vertical then
				inFrame = inFrame + 1
			end
		end
	end
end
assert(displayed >= 2 and inFrame >= 2,
	"Avatar arms exist but fall OUTSIDE the first-person camera frame")
print("NOCTURNE v5: real avatar hands INSIDE the native first-person frame; grounded physics OK")
