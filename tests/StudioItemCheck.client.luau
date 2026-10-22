-- Optional CLIENT Command Bar check in Studio Play, after you find/buy an item.
-- This tests the live RemoteEvent/server/replicated effect, not physical input.
-- Also press Q / click the 3-D scene / tap the item button yourself in Play.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Run this in the CLIENT Command Bar during Play, not Run")
local world = workspace:WaitForChild("NocturneWorld", 10)
assert(world and world:GetAttribute("GenerationBuild") == "ThresholdScareAndBlindPanic-v16",
	"Open Nocturne-v16.rbxl in a NEW Studio tab and press Play")
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
assert(humanoid.Health > 0 and not player:GetAttribute("Hidden")
	and not player:GetAttribute("Crouching"), "Stand outside the wardrobe before testing")
local id = player:GetAttribute("EquippedItem")
assert(id, "Pick up or buy an item and select its hotbar slot first")
local remote = ReplicatedStorage:WaitForChild("NocturneRemote")
local previousHealth = math.min(humanoid.Health, player:GetAttribute("Health") or 100)
local previousSpeed = humanoid.WalkSpeed
local previousLight = player:GetAttribute("TorchOn") == true
local reply
local connection = remote.OnClientEvent:Connect(function(event, item)
	if item == id and (event == "ItemUsed" or event == "ItemDenied") then reply = event end
end)
remote:FireServer("Use", id)
local deadline = os.clock() + 3
while not reply and os.clock() < deadline do task.wait(0.05) end
connection:Disconnect()
assert(reply, "No response from the server: check the FIRST red line in Client/Server Output")
task.wait(0.25) -- allow character attributes and WalkSpeed to replicate
if id == "FLASHLIGHT" then
	assert(reply == "ItemUsed" and player:GetAttribute("TorchOn") ~= previousLight,
		"Selected hand flashlight did not switch on/off")
elseif id == "PILL" then
	assert(reply == "ItemUsed" and humanoid.WalkSpeed > previousSpeed
		and player:GetAttribute("EquippedItem") ~= id,
		"Pill was not consumed or did not increase the real Humanoid's speed")
elseif id == "BANDAGE" or id == "MEDKIT" then
	if previousHealth >= 100 then
		assert(reply == "ItemDenied" and player:GetAttribute("EquippedItem") == id,
			"Healing item should remain in hand at full health")
	else
		assert(reply == "ItemUsed" and humanoid.Health > previousHealth
			and player:GetAttribute("EquippedItem") ~= id,
			"Healing item did not restore health and disappear from the hand")
	end
elseif id == "CRUCIFIX" then
	assert((reply == "ItemUsed" and player:GetAttribute("EquippedItem") ~= id)
		or (reply == "ItemDenied" and player:GetAttribute("EquippedItem") == id),
		"Cross failed to banish a nearby visible threat or was spent with no target")
else
	error("Unknown selected item: " .. tostring(id))
end
print("NOCTURNE v16: live item action", id, reply,
	"health", humanoid.Health, "speed", humanoid.WalkSpeed,
	"light", player:GetAttribute("TorchOn"))
