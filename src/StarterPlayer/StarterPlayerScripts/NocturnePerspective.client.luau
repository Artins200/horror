-- Native Roblox first-person camera on an ordinary, colliding R6/R15 Humanoid.
-- No viewmodel arms at all until THIS player actually holds a drawer key.
-- MeshParts/SpecialMeshes and the avatar's original colours/clothing are copied;
-- no pixel-block arms, independent flying camera or moved real limbs.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local camera
local character
local humanoid
local arms = {}
local shirt
local keyModel
local keyNumber
local pickupTime = 10
local turnTime = 10
local wasTurning = false
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
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.LocalTransparencyModifier = 0
	part.Transparency = 1
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

-- A miniature 3-D brass key drawn alongside the copied Roblox hand. The
-- server separately welds the corresponding physical key into the REAL hand,
-- so other players also see what was taken from the drawer.
local function makeViewKey()
	local model = Instance.new("Model")
	model.Name = "Key in avatar hand"
	local brass = Color3.fromRGB(194, 145, 72)
	local shadow = Color3.fromRGB(101, 68, 40)
	local function piece(name, size, offset, color, material, shape)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(offset)
		part.Color = color
		part.Material = material
		part.Shape = shape or Enum.PartType.Block
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = model
		return part
	end
	piece("Forged key shaft", Vector3.new(0.10, 0.55, 0.1), Vector3.new(0, -0.51, 0),
		brass, Enum.Material.Metal, Enum.PartType.Cylinder)
	for i = 1, 9 do
		local angle = i * math.pi * 2 / 9
		piece("Round key bow", Vector3.new(0.11, 0.11, 0.1),
			Vector3.new(math.cos(angle) * 0.19, math.sin(angle) * 0.19, 0),
			brass, Enum.Material.Metal, Enum.PartType.Ball)
	end
	piece("Key bit", Vector3.new(0.34, 0.1, 0.13), Vector3.new(0.12, -0.77, 0),
		brass, Enum.Material.Metal)
	piece("Notched tooth", Vector3.new(0.09, 0.13, 0.15), Vector3.new(0.26, -0.7, 0),
		shadow, Enum.Material.Metal)
	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = viewModel
	return model
end

local function syncKey()
	local current = player:GetAttribute("HeldKey")
	if current == keyNumber then return end
	keyNumber = current
	if keyModel then keyModel:Destroy(); keyModel = nil end
	if current then
		pickupTime = 0
		keyModel = makeViewKey()
	else
		pickupTime = 10
	end
end

local function onCharacter(avatar)
	local human = avatar:WaitForChild("Humanoid")
	if player.Character ~= avatar then return end
	character, humanoid = avatar, human
	if keyModel then keyModel:Destroy(); keyModel = nil end
	keyNumber = nil
	wasTurning = false
	turnTime = 10
	player:SetAttribute("NocturnePeek", false)
	lockCamera()
	if camera then viewModel.Parent = camera end
	buildArms()
	syncKey()
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterAppearanceLoaded:Connect(function(avatar)
	if avatar == character and player.Character == avatar then buildArms() end
end)
player:GetAttributeChangedSignal("HeldKey"):Connect(syncKey)
lockCamera() -- no wait for HUD, PlayerGui, server event or avatar appearance
if player.Character then task.spawn(onCharacter, player.Character) end

-- Position ordinary-sized limbs so only a small portion reaches the bottom of
-- the frame when carrying a key. Match elbows to wrists rather than laying
-- six disconnected parts across half the screen. The right hand raises the
-- KEY together with the arm on pickup and again while turning the lock.
local function between(from, to)
	return CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(-math.pi / 2, 0, 0)
end
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
	syncKey()
	local turning = player:GetAttribute("KeyTurning") == true
	if turning and not wasTurning then turnTime = 0 end
	wasTurning = turning
	local root = character:FindFirstChild("HumanoidRootPart")
	local speed = root and Vector3.new(root.AssemblyLinearVelocity.X, 0,
		root.AssemblyLinearVelocity.Z).Magnitude or 0
	dt = math.min(dt, 0.08)
	elapsed = elapsed + dt
	stride = stride + math.min(speed / 14, 1.4) * dt * 8
	pickupTime = math.min(10, pickupTime + dt)
	turnTime = math.min(10, turnTime + dt)
	local visible = keyNumber ~= nil and not peek and humanoid.Health > 0
	local actualKey = character:FindFirstChild("HeldKey")
	if actualKey then
		-- Only the owner hides the replicated key; everybody else sees it
		-- welded into the real R6/R15 hand.
		for _, part in ipairs(actualKey:GetDescendants()) do
			if part:IsA("BasePart") then part.LocalTransparencyModifier = 1 end
		end
	end
	local viewport = camera.ViewportSize
	local width = viewport and math.clamp(viewport.X / math.max(1, viewport.Y) / 1.5, 0.48, 1) or 1
	local pickup = math.sin(math.min(pickupTime / 0.85, 1) * math.pi) * 0.53
	local turn = turning and math.min(turnTime / 0.32, 1) or 0
	local sway = math.sin(stride) * math.min(speed / 14, 1) * 0.025
	local breathe = math.sin(elapsed * 1.55) * 0.009
	local hands = {
		[-1] = Vector3.new(-0.47 * width, -0.81 + pickup * 0.18 + breathe - sway, -1.82),
		[1] = Vector3.new(0.43 * width - turn * 0.21 * width,
			-0.72 + pickup + turn * 0.60 + breathe + sway, -1.82 - turn * 0.19),
	}
	for _, arm in ipairs(arms) do
		local side = arm.side
		local hand = hands[side]
		local wrist = hand + Vector3.new(side * 0.06, -0.19, 0.07)
		local elbow = hand + Vector3.new(side * 0.23, -0.73, 0.25)
		local shoulder = hand + Vector3.new(side * 0.44, -1.43, 0.44)
		local localCF
		if arm.segment == "upper" then
			localCF = between(shoulder, elbow)
		elseif arm.segment == "lower" then
			localCF = between(elbow, wrist)
		elseif arm.segment == "hand" then
			localCF = CFrame.new(hand) * CFrame.Angles(math.rad(18), 0, math.rad(side * 8))
		else -- the original single R6 arm, including its actual mesh or shirt
			localCF = between(shoulder, wrist)
		end
		arm.part.CFrame = camera.CFrame * localCF
		arm.part.LocalTransparencyModifier = 0
		arm.part.Transparency = visible and arm.source.Transparency or 1
	end
	if keyModel then
		keyModel:PivotTo(camera.CFrame * CFrame.new(hands[1] + Vector3.new(-0.045, 0.03, -0.29))
			* CFrame.Angles(math.rad(-18 - turn * 42), 0, math.rad(-15 - turn * 36)))
		-- Keep the invisible original held-key clone from showing in the
		-- wardrobe, on respawn or during the death camera transition.
		for _, part in ipairs(keyModel:GetDescendants()) do
			if part:IsA("BasePart") then part.Transparency = visible and 0 or 1 end
		end
	end
end)
print("[NOCTURNE v6 / native first person] avatar hands and key appear only when carried")
