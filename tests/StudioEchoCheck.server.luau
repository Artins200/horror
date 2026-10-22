-- Optional SERVER Command Bar check: run while Echo is crossing or returning.
-- Echo appears only in an Echo encounter, after the silent lamp warning.
local world = workspace:WaitForChild("NocturneWorld", 10)
assert(world and world:GetAttribute("GenerationBuild") == "SinglePressWardrobe-v13",
	"Open Nocturne-v13.rbxl in a NEW Studio tab and press Play")
local echo = world:FindFirstChild("TheEcho")
assert(echo and echo.PrimaryPart,
	"Wait for the returning Echo to appear, then run this BEFORE its fifth pass")
local rush = world:FindFirstChild("TheRush")
local mask = echo:FindFirstChild("Long hollow porcelain face")
local left = echo:FindFirstChild("Left trailing veil")
local right = echo:FindFirstChild("Right trailing veil")
local leftShroud = left and left:FindFirstChild("Torn echo shroud")
local rightShroud = right and right:FindFirstChild("Torn echo shroud")
local mark = echo:FindFirstChild("Return face fracture")
local shoulder = echo:FindFirstChild("Echo shoulder socket")
local hip = echo:FindFirstChild("Echo joined hip")
local arm = echo:FindFirstChild("Left pendulum arm")
local leg = echo:FindFirstChild("Left echo leg")
assert(mask and leftShroud and rightShroud and mark and shoulder and hip
	and arm and leg and echo:FindFirstChild("Echo shutter jaw")
	and not echo:FindFirstChild("Cracked funeral mask")
	and (not rush or rush:FindFirstChild("Cracked funeral mask")),
	"Returning monster is still the original Rush painted a different colour")
local total, blocks = 0, 0
for _, part in ipairs(echo:GetDescendants()) do
	if part:IsA("BasePart") then
		total = total + 1
		if part:IsA("Part") and part.Shape == Enum.PartType.Block then blocks = blocks + 1 end
		assert(part.Anchored and not part.CanCollide and not part.CanTouch,
			"Echo has a blocking or free-floating decorative limb")
	end
end
assert(total >= 82 and blocks == 0, "Echo lost its sculpted connected silhouette")
local pass = echo:GetAttribute("EchoPass")
local returning = echo:GetAttribute("Returning")
assert(type(pass) == "number" and returning == (pass % 2 == 0),
	"Echo is not alternating forward/returning passes")
if returning then
	assert(mark.Transparency < 0.15 and leftShroud.Transparency < 0.3
		and rightShroud.Transparency < 0.3,
		"Returning Echo did not open its torn shroud and face cracks")
else
	assert(mark.Transparency > 0.9 and leftShroud.Transparency > 0.5,
		"Forward Echo did not fold its veil back")
end
print("NOCTURNE v13 Echo: separate model, pass", pass,
	"returning", returning, "sculpted parts", total)
