-- CLIENT Command Bar during Play: open door 100 but stand JUST BEFORE it.
-- Run this check, click the viewport and WALK INTO THE WHITE ROOM naturally.
-- It does not teleport the avatar or manually fire RemoteEvents.
local player = game:GetService("Players").LocalPlayer
assert(player, "Run in the CLIENT Command Bar during Play")
local world = workspace:FindFirstChild("NocturneWorld")
local exit = world and world:FindFirstChild("Exit")
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
assert(world and world:GetAttribute("GenerationBuild") == "ThresholdScareAndBlindPanic-v16"
	and exit and root and humanoid and not player:GetAttribute("Finished")
	and root.Position.Z < 100 * 44 + 0.55,
	"In Nocturne-v16 Play, stand BEFORE the open door 100 and run this check")
print("Finale check armed: walk through door 100 now. It must scare you immediately.")
local deadline = os.clock() + 30
while not player:GetAttribute("Finished") and os.clock() < deadline do task.wait(0.03) end
assert(player:GetAttribute("Finished"), "Stepped into white room but no Finished event arrived")
local depth = root.Position.Z - 100 * 44
assert(depth >= 0.55 and depth < 8 and humanoid.Health > 0,
	"The scare occurred too late / outside the white-room entrance: " .. depth)
task.wait(0.20) -- network order of Finished attribute and personal RemoteEvent can differ
local hud = player:FindFirstChildOfClass("PlayerGui"):FindFirstChild("NocturneHUD")
local scare = hud and hud:FindFirstChild("Creature close-up")
local view = scare and scare:FindFirstChild("Attacking creature")
local stage = view and view:FindFirstChild("The approaching face")
local model = stage and (stage:FindFirstChild("TheLastWitness")
	or stage:FindFirstChild("Last glimpse of FINAL"))
local camera = workspace.CurrentCamera
assert(scare and scare.Visible and not hud:FindFirstChild("End card").Visible
	and model and model:FindFirstChildWhichIsA("BasePart", true)
	and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
	and player.CameraMode == Enum.CameraMode.LockFirstPerson
	and not root.Anchored and humanoid.WalkSpeed == 0,
	"At entry the CLOSE-UP must appear over the real, frozen Roblox avatar")
local veil = scare:FindFirstChild("Split second red flash")
assert(veil and veil.BackgroundTransparency > 0.6
	and view.CurrentCamera.FieldOfView < 45,
	"White wash still hides the giant face instead of showing it instantly")
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {character}
params.RespectCanCollide = true
local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
assert(hit and hit.Instance == exit:FindFirstChild("Last floor"),
	"No physical floor supports the real avatar at the white-room threshold")
local sound = game:GetService("SoundService"):FindFirstChild("Final close shriek")
assert(sound and sound.SoundId == "rbxasset://sounds/uuhhh.mp3",
	"The first-frame close-range shriek was not constructed")
print("NOCTURNE v16: face visible immediately at depth", depth,
	"studs; impact/shriek triggered; check that sound is audible in Play")
task.wait(3.15)
assert(hud:FindFirstChild("End card").Visible and not scare.Visible,
	"After holding the face, the finale did not proceed to victory")
