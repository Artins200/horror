-- CLIENT Command Bar during Play (not Run): run empty-handed, after a loot
-- pickup/selection, and with a key. Both actual R6/R15 hands stay grounded.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player, "Run this in the CLIENT Command Bar during Play")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local head = character:WaitForChild("Head")
task.wait(0.3)
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("CameraBuild") == "NativeFirstPerson-v10",
	"Open Nocturne-v16.rbxl in a NEW Studio tab")
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
local hud = player:WaitForChild("PlayerGui"):WaitForChild("NocturneHUD", 10)
local bar = hud and hud:FindFirstChild("Equipment bar")
assert(bar and bar.AbsoluteSize.X <= 250 and bar.AbsoluteSize.Y <= 60,
	"Inventory is still covering the bottom half of the screen")
local visibleSlots = 0
for _, id in ipairs({"FLASHLIGHT", "PILL", "CRUCIFIX", "BANDAGE", "MEDKIT"}) do
	local tile = bar:FindFirstChild("Slot " .. id)
	if tile and tile.Visible then visibleSlots = visibleSlots + 1 end
end
assert(bar.Visible == (visibleSlots > 0),
	"Empty inventory appears on screen or held items have no hotbar")
local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
local shoulder = character:FindFirstChild("RightShoulder", true)
	or character:FindFirstChild("Right Shoulder", true)
assert(right and shoulder and shoulder:IsA("Motor6D") and right.Transparency < 0.95,
	"Right hand must be part of the actual R6/R15 character and its joints")
local selected = player:GetAttribute("EquippedItem")
local item = selected and character:WaitForChild("HeldItem", 5) or character:FindFirstChild("HeldItem")
if selected then
	local side = player:GetAttribute("HeldKey") and "Left" or "Right"
	local hand = character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm")
	local grip = item and item:FindFirstChild("Item grip in Roblox hand", true)
	local details = 0
	assert(item and item:GetAttribute("ItemKind") == selected
		and item:GetAttribute("GripHand") == side and grip and grip.Part0 == hand,
		"Selected item has no server-owned model welded to a real hand")
	for _, part in ipairs(item:GetDescendants()) do
		if part:IsA("BasePart") then
			details = details + 1
			assert(not part.Anchored and not part.CanCollide and not part.CanQuery,
				"Held item has a frozen/free-standing piece or an invisible collision")
		end
	end
	assert(details >= 5 and hand.LocalTransparencyModifier < 0.1,
		"Detailed item or genuine Roblox holding arm is invisible")
	local relative = camera.CFrame:PointToObjectSpace(grip.Part1.Position)
	assert(relative.Z < 1.5 and relative.Z > -4 and math.abs(relative.X) < 3.5,
		"Held model drifted away from the visible first-person hand")
	if selected == "FLASHLIGHT" then
		local lens = item:FindFirstChild("Torch lens", true)
		local beam = lens and lens:FindFirstChild("Selected torch beam")
		local reach = lens and lens:FindFirstChild("Selected torch core")
		assert(lens and beam and reach and player:GetAttribute("HasFlashlight")
			and beam.Brightness >= 3.2 and beam.Range >= 30
			and reach.Brightness >= 4.4 and reach.Range >= 52,
			"Selected hand torch has no bright wide/far physical beams")
		local mount = camera:FindFirstChild("Invisible torch light source")
		local flood = mount and mount:FindFirstChild("Hand torch flood")
		local core = mount and mount:FindFirstChild("Hand torch reach")
		local nearby = mount and mount:FindFirstChild("Hand torch nearby light")
		local on = player:GetAttribute("TorchOn") == true
		assert(flood and core and nearby and flood.Enabled == on
			and core.Enabled == on and nearby.Enabled == on,
			"Found torch has no visible light in Play, or stayed on when switched off")
	end
else
	assert(not item, "Item model remained in the hand after use or discharge")
end
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
	if not selected then
		assert(right.LocalTransparencyModifier > 0.9,
			"An arm hovers onscreen even when nothing is held")
	else
		assert(right.LocalTransparencyModifier < 0.1,
			"Equipped item in right hand was hidden by first-person fading")
	end
end
print("NOCTURNE v16: first-person grounded real Roblox hands",
	held or "no key", selected or "no selected item", right.LocalTransparencyModifier)
