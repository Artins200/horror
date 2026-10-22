-- CLIENT Command Bar during Play: cross door 100, WALK into the white room,
-- then run this BEFORE touching its far end. The normal Roblox avatar/camera
-- must remain physical while the real left hand covers the eyes.
local player = game:GetService("Players").LocalPlayer
assert(player, "Run in the CLIENT Command Bar during Play")
local world = workspace:FindFirstChild("NocturneWorld")
local exit = world and world:FindFirstChild("Exit")
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
assert(world and world:GetAttribute("GenerationBuild") == "WhiteVoidAndBlindAudio-v15"
	and exit and root and humanoid and player:GetAttribute("VoidWalk")
	and not player:GetAttribute("Finished"),
	"In Nocturne-v15 Play, cross door 100 and run this while walking in the white room")
task.wait(0.7) -- allow the hand and eye adaptation to finish rising
local camera = workspace.CurrentCamera
local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
local joint = character:FindFirstChild("LeftShoulder", true)
	or character:FindFirstChild("Left Shoulder", true)
local bloom = game:GetService("Lighting"):FindFirstChild("Void white bloom")
local grading = game:GetService("Lighting"):FindFirstChild("Void eye adaptation")
local hud = player:FindFirstChildOfClass("PlayerGui"):FindFirstChild("NocturneHUD")
local glare = hud and hud:FindFirstChild("White void glare")
assert(camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
	and player.CameraMode == Enum.CameraMode.LockFirstPerson and not root.Anchored
	and humanoid.WalkSpeed == 5 and humanoid.FloorMaterial ~= Enum.Material.Air,
	"The bright finale removed collisions or detached the normal Roblox first-person camera")
assert(hand and joint and joint:IsA("Motor6D")
	and hand.LocalTransparencyModifier < 0.15 and hand.Transparency < 0.95,
	"The final eye shield must be the player's ORIGINAL visible left R6/R15 arm")
local relative = camera.CFrame:PointToObjectSpace(hand.Position)
assert(math.abs(relative.X) < 2.5 and relative.Z < 1.5 and relative.Z > -4,
	"The real shielding hand is outside the camera view; inspect its shoulder pose")
assert(bloom and bloom.Intensity > 1.3 and grading and grading.Brightness > 0.20
	and glare and glare.BackgroundTransparency < 0.98
	and not hud:FindFirstChild("Equipment bar").Visible
	and not player:GetAttribute("TorchOn"),
	"Bright local emulation/empty HUD/torch shutdown was lost after door 100")
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {character}
params.RespectCanCollide = true
local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
assert(hit and hit.Instance == exit:FindFirstChild("Last floor"),
	"No physical floor is supporting the player in the white void")
print("NOCTURNE v15 white void: native camera, collidable floor, slow movement, REAL hand near eye",
	relative, "bloom", bloom.Intensity)
