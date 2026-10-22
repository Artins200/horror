-- CLIENT Command Bar during Play: stand in the SAME room as the living Blind
-- Guest, run this, then leave through a door. Visual panic is now present
-- continuously, with a hard first-sight hit and sharp recurring bursts.
local player = game:GetService("Players").LocalPlayer
assert(player, "Run in the CLIENT Command Bar, not on the server")
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("GenerationBuild") == "ThresholdScareAndBlindPanic-v16",
	"Open Nocturne-v16.rbxl in a NEW Studio tab and press Play")
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
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
local pulse = service:FindFirstChild("Blind panic heartbeat")
local source = workspace:FindFirstChild("музыка_для_слепого когда в одной комнате")
assert(source and source:IsA("Sound") and music and scary and growl and pulse
	and music.Looped and not source.IsPlaying,
	"The original v14 Sound objects were not cloned locally")
local lighting = game:GetService("Lighting")
local grade = lighting:FindFirstChild("Blind Guest colour panic")
local blur = lighting:FindFirstChild("Blind Guest double vision")
local bloom = lighting:FindFirstChild("Blind Guest retinal overload")
local gui = player:FindFirstChildOfClass("PlayerGui"):FindFirstChild("NocturneHUD")
local bar = gui and gui:FindFirstChild("Blind signal fracture")
local veil = gui and gui:FindFirstChild("Blind chromatic bleed")
task.wait(0.25)
assert(sameRoom() and music.IsPlaying and music.Volume > 0.1
	and grade and grade.Saturation > 0.02 and blur and blur.Size > 0.5
	and bloom and bloom.Intensity > 0.03
	and bar and bar.BackgroundTransparency < 0.98
	and veil and veil.BackgroundTransparency < 1
	and workspace.CurrentCamera.CameraType == Enum.CameraType.Custom
	and workspace.CurrentCamera.CameraSubject == humanoid,
	"Guest's music/persistent distortion is missing or the native camera detached")
if not music.IsLoaded then
	warn("NOCTURNE: Sound playing but NOT LOADED; check Studio Output for audio permissions. "
		.. "The owner of the original v14 sound must allow this place to play it.")
end
print("NOCTURNE v16: Blind theme volume", music.Volume, "loaded:", music.IsLoaded,
	"-- stay for a coloured burst, then leave for the music fade")
task.spawn(function()
	local start, seen = os.clock(), false
	while sameRoom() and os.clock() - start < 9 do
		if blur.Size > 8 and bloom.Intensity > 1 and grade.Saturation > 0.8
			and bar.BackgroundTransparency < 0.5 and veil.BackgroundTransparency < 0.9 then
			seen = true
		end
		task.wait(0.06)
	end
	if sameRoom() and not seen then
		warn("NOCTURNE: no STRONG coloured/blurred panic in nine seconds; check Client Output")
	elseif seen then
		print("NOCTURNE v16: strong colour/blur/bloom/static spike; camera remains physical")
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
	assert(after < before and after > 0 and music.IsPlaying
		and blur.Size == 0 and bloom.Intensity == 0 and veil.BackgroundTransparency == 1,
		"Guest's theme cut off or personal visual panic followed it into another room")
	task.wait(6)
	assert(music.Volume < 0.02 and not music.IsPlaying,
		"The theme did not complete its gradual fade after exit")
	print("NOCTURNE v16: personal Blind Guest theme faded smoothly and stopped")
end)
