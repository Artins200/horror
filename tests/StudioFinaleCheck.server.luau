-- SERVER Command Bar during Play AFTER opening door 100. Do not run in edit mode.
-- Verifies the solid white chamber and a single entry sensor; the actual
-- audiovisual scare still requires the CLIENT Play check below.
local world = workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("GenerationBuild") == "ThresholdScareAndBlindPanic-v16"
	and world:GetAttribute("DoorsOpened") == 100,
	"Open all 100 doors in Nocturne-v16.rbxl (Play, not Run), then repeat this check")
local exit = world:FindFirstChild("Exit")
assert(exit, "Door 100 did not build a final space")
local floor = exit:FindFirstChild("Last floor")
local back = exit:FindFirstChild("Sealed white horizon")
local ceiling = exit:FindFirstChild("White void ceiling")
local entry = exit:FindFirstChild("End of the nightmare")
local witness = exit:FindFirstChild("TheLastWitness")
local sides, lights = 0, 0
for _, child in ipairs(exit:GetChildren()) do
	if child.Name == "White void wall" then
		sides = sides + 1
		assert(child.CanCollide and child.Anchored and child.Color.R > 0.93)
	elseif child.Name == "Unseen white light" then
		lights = lights + 1
		assert(child:FindFirstChildOfClass("PointLight").Brightness >= 6)
	end
end
assert(floor and floor.Anchored and floor.CanCollide and floor.Size.Z == 48
	and back and back.Anchored and back.CanCollide
	and ceiling and ceiling.Anchored and ceiling.CanCollide
	and sides == 2 and lights == 4 and entry and entry.CanTouch
	and not entry.CanCollide and not exit:FindFirstChild("White threshold")
	and math.abs(entry.Position.Z - (100 * 44 + 1.3)) < 0.05
	and witness and witness:GetAttribute("Concealed"),
	"White chamber has an open edge, missing floor or no ENTRANCE scare sensor")
for _, piece in ipairs(witness:GetDescendants()) do
	if piece:IsA("BasePart") then
		assert(piece.Transparency == 1 and not piece.CanCollide,
			"The last monster was visible before another player entered the room")
	elseif piece:IsA("Highlight") or piece:IsA("PointLight") then
		assert(not piece.Enabled, "The hidden figure shines through the white room")
	end
end
for _, name in ipairs({"музыка_для_слепого когда в одной комнате", "Scary sound", "scarygrowl 1"}) do
	local original = workspace:FindFirstChild(name)
	assert(original and original:IsA("Sound") and not original.IsPlaying,
		"Uploaded v14 Sound template missing or accidentally playing on server: " .. name)
end
print("NOCTURNE v16: 48-stud sealed white chamber; private scare sensor immediately behind door 100")
