-- Independent from the HUD and from the server remote. Even if either starts
-- late, Roblox's own CameraModule must follow a real, colliding Humanoid.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local camera
local character
local humanoid
local arms = {}
local shirt
local lastAttempt = 0
local elapsed = 0
local stride = 0
local viewModel = Instance.new("Model")
viewModel.Name = "AvatarArmsFirstPerson"

local function lockCamera()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	camera = Workspace.CurrentCamera
	if camera and humanoid and humanoid.Health > 0
		and not player:GetAttribute("Hidden") and not player:GetAttribute("NocturnePeek") then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function clearArms()
	for _, arm in ipairs(arms) do arm.part:Destroy() end
	arms = {}
	if shirt then shirt:Destroy(); shirt = nil end
end
local function copyArm(name, side, segment)
	local source = character and character:FindFirstChild(name)
	if not source or not source:IsA("BasePart") then return end
	local archived = source.Archivable
	source.Archivable = true
	local part = source:Clone()
	source.Archivable = archived
	if not part then return end
	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("WeldConstraint")
			or child:IsA("Script") or child:IsA("LocalScript") or child:IsA("Sound") then
			child:Destroy()
		end
	end
	-- Keep the avatar's OWN mesh, textures, skin and original clothing name.
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.LocalTransparencyModifier = 0
	part.Parent = viewModel
	table.insert(arms, {part = part, source = source, side = side, segment = segment})
end
local function buildArms()
	clearArms()
	if not character or not humanoid or humanoid.Parent ~= character then return end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		for _, side in ipairs({-1, 1}) do
			local prefix = side == -1 and "Left" or "Right"
			copyArm(prefix .. "UpperArm", side, "upper")
			copyArm(prefix .. "LowerArm", side, "lower")
			copyArm(prefix .. "Hand", side, "hand")
		end
	else
		copyArm("Left Arm", -1, "r6")
		copyArm("Right Arm", 1, "r6")
	end
	local originalShirt = character:FindFirstChildOfClass("Shirt")
	if originalShirt then
		local archived = originalShirt.Archivable
		originalShirt.Archivable = true
		shirt = originalShirt:Clone()
		originalShirt.Archivable = archived
		if shirt then shirt.Parent = viewModel end
	end
	lastAttempt = os.clock()
end

local function onCharacter(avatar)
	local human = avatar:WaitForChild("Humanoid")
	if player.Character ~= avatar then return end
	character, humanoid = avatar, human
	player:SetAttribute("NocturnePeek", false)
	lockCamera()
	if camera then viewModel.Parent = camera end
	buildArms()
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterAppearanceLoaded:Connect(function(avatar)
	if avatar == character and player.Character == avatar then buildArms() end
end)
lockCamera() -- do NOT wait for NocturneRemote, PlayerGui or character appearance
if player.Character then task.spawn(onCharacter, player.Character) end

-- CameraModule writes the final view at Camera priority; move ONLY the
-- noncolliding copies afterwards. No root CFrame, real limb or user input is
-- ever altered by this render callback.
RunService:BindToRenderStep("NocturnePerspective", Enum.RenderPriority.Camera.Value + 2, function(dt)
	camera = Workspace.CurrentCamera
	if not camera then return end
	if viewModel.Parent ~= camera then viewModel.Parent = camera end
	if not humanoid or not character or player.Character ~= character then return end
	local peek = player:GetAttribute("Hidden") == true or player:GetAttribute("NocturnePeek") == true
	if not peek and humanoid.Health > 0 then
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson
			or camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid then
			lockCamera()
		end
	end
	if #arms < 2 and os.clock() - lastAttempt > 1 then buildArms() end
	local root = character:FindFirstChild("HumanoidRootPart")
	local speed = root and Vector3.new(root.AssemblyLinearVelocity.X, 0,
		root.AssemblyLinearVelocity.Z).Magnitude or 0
	dt = math.min(dt, 0.08)
	elapsed = elapsed + dt
	stride = stride + math.min(speed / 14, 1.4) * dt * 8
	local sway = math.sin(stride) * math.min(speed / 14, 1) * 0.055
	local breathing = math.sin(elapsed * 1.65) * 0.012
	local visible = not peek and humanoid.Health > 0
	local viewport = camera.ViewportSize
	local width = viewport and math.clamp(viewport.X / math.max(1, viewport.Y) / 1.4, 0.5, 1) or 1
	for _, arm in ipairs(arms) do
		local side = arm.side
		local position, rotation
		if arm.segment == "upper" then
			position = Vector3.new(side * 0.79 * width, -0.52 + sway + breathing, -0.88)
			rotation = CFrame.Angles(math.rad(48), 0, math.rad(side * 16))
		elseif arm.segment == "lower" then
			position = Vector3.new(side * 0.73 * width, -0.66 + sway + breathing, -1.20)
			rotation = CFrame.Angles(math.rad(65), 0, math.rad(side * 8))
		elseif arm.segment == "hand" then
			position = Vector3.new(side * 0.68 * width, -0.58 + sway + breathing, -1.55)
			rotation = CFrame.Angles(math.rad(72), 0, math.rad(side * 6))
		else -- R6: the player's actual two Roblox arms, with their own mesh.
			position = Vector3.new(side * 0.82 * width, -0.60 + sway + breathing, -1.28)
			rotation = CFrame.Angles(math.rad(57), 0, math.rad(side * 12))
		end
		arm.part.CFrame = camera.CFrame * CFrame.new(position) * rotation
		arm.part.LocalTransparencyModifier = 0
		arm.part.Transparency = visible and arm.source.Transparency or 1
	end
end)
print("[NOCTURNE v5 / independent first-person boot] physical avatar camera + avatar arms ready")
