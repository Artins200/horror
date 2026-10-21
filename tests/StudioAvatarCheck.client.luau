-- Optional Roblox Studio CLIENT Command Bar check in a fresh Play session.
-- Run next to the player, not on the server: LocalTransparencyModifier is local.
local player = game:GetService("Players").LocalPlayer
assert(player, "Run this in the CLIENT Command Bar while playing")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local head = character:WaitForChild("Head")
task.wait(2) -- wait until camera and avatar appearance have settled
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("CameraBuild") == "VisibleAvatar-v3",
	"Old place loaded: open the NEW 13123.rbxl")
local camera = workspace.CurrentCamera
assert(player.CameraMode == Enum.CameraMode.Classic, "Character locked in ghost first-person mode")
assert(camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
	"Walking camera must be Roblox's native, humanoid-following camera")
assert((camera.CFrame.Position - head.Position).Magnitude > 3,
	"Camera is still inside the invisible avatar")
assert(head.LocalTransparencyModifier < 0.9, "Avatar's head is locally hidden")
local visibleArms = 0
for _, name in ipairs({"Left Arm", "Right Arm", "LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand"}) do
	local arm = character:FindFirstChild(name)
	if arm and arm:IsA("BasePart") and arm.Transparency < 0.9 and arm.LocalTransparencyModifier < 0.9 then
		visibleArms = visibleArms + 1
	end
end
assert(visibleArms >= 2, "Avatar arms are not visible in the native camera")
assert(not root.Anchored and humanoid.AutoRotate, "Avatar movement is locked")
assert(humanoid.FloorMaterial ~= Enum.Material.Air, "Avatar is not standing on a surface")
print("NOCTURNE v3: visible Roblox avatar, third-person camera and solid floor OK")
