-- CLIENT Command Bar during Play: stay in the SAME room as the living Blind
-- Guest, run this, then leave through a door. Watch/hear the panic and fade.
-- The delayed probes print to Client Output while you keep playing.
local player = game:GetService("Players").LocalPlayer
assert(player, "Run in the CLIENT Command Bar, not on the server")
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("GenerationBuild") == "WhiteVoidAndBlindAudio-v15",
	"Open Nocturne-v15.rbxl in a NEW Studio tab and press Play")
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local guest = world:FindFirstChild("TheBlindGuest")
local function sameRoom()
	return root and root.Parent and guest and guest.Parent and not guest:GetAttribute("Banished")
		and guest:GetAttribute("RoomIndex") == math.floor(root.Position.Z / 44)
end
assert(sameRoom(), "Run while your real character is in the SAME room as the Blind Guest")
local service = game:GetService("SoundService")
local music = service:FindFirstChild("Blind Guest / local theme")
local scary = service:FindFirstChild("Rare scary sound")
local growl = service:FindFirstChild("Rare scary growl")
local source = workspace:FindFirstChild("музыка_для_слепого когда в одной комнате")
assert(source and source:IsA("Sound") and music and scary and growl and music.Looped
	and not source.IsPlaying, "The original v14 Sound objects were not cloned locally")
task.wait(1.1)
assert(sameRoom() and music.IsPlaying and music.Volume > 0.1,
	"The Blind Guest's music is not playing while both of you are in the same room")
if not music.IsLoaded then
	warn("NOCTURNE: the Sound is playing but NOT LOADED. Check Studio Output for audio permissions; "
		.. "the owner of IDs in Nocturne-v14 must grant this place access.")
end
local grade = game:GetService("Lighting"):FindFirstChild("Blind Guest colour panic")
local blur = game:GetService("Lighting"):FindFirstChild("Blind Guest double vision")
local gui = player:FindFirstChildOfClass("PlayerGui"):FindFirstChild("NocturneHUD")
local bar = gui and gui:FindFirstChild("Blind signal fracture")
assert(grade and blur and bar and workspace.CurrentCamera.CameraType == Enum.CameraType.Custom,
	"Panic effects or the normal Humanoid first-person camera are missing")
print("NOCTURNE v15: supplied Blind Guest music playing locally at", music.Volume,
	"loaded:", music.IsLoaded, "-- now leave this room; music should fade rather than cut")
task.spawn(function()
	local start = os.clock()
	local panicSeen = false
	while sameRoom() and os.clock() - start < 20 do
		if blur.Size > 0 and grade.Saturation > 0 and bar.BackgroundTransparency < 1 then
			panicSeen = true
		end
		task.wait(0.08)
	end
	if sameRoom() and not panicSeen then
		warn("NOCTURNE: no colour panic observed after 20 seconds; inspect Client Output")
	elseif panicSeen then
		print("NOCTURNE v15: irregular colour/blur/signal panic observed; camera remains attached")
	end
end)
task.spawn(function()
	local start = os.clock()
	while sameRoom() and os.clock() - start < 70 do task.wait(0.08) end
	if sameRoom() then
		warn("NOCTURNE: fade not sampled; step into a different room before 70 seconds")
		return
	end
	local before = music.Volume
	task.wait(0.20)
	local after = music.Volume
	assert(after < before and after > 0 and music.IsPlaying,
		"Music cut off instead of fading after leaving the Blind Guest's room")
	task.wait(6)
	assert(music.Volume < 0.02 and not music.IsPlaying,
		"The Blind Guest theme did not finish its gradual fade after exit")
	print("NOCTURNE v15: personal Blind Guest theme faded smoothly and stopped")
end)
