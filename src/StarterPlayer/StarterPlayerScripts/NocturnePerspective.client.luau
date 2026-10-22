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
local keyFromAvatar = false
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
	-- A single REAL-avatar right arm grips the key. The idle left arm no
	-- longer hovers inexplicably in front of the player's face.
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		copyArm("RightUpperArm", 1, "upper")
		copyArm("RightLowerArm", 1, "lower")
		copyArm("RightHand", 1, "hand")
	else
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

-- Display the EXACT physical key already welded to the owner's Roblox hand.
-- Attribute replication may beat model replication by a frame; only then do
-- we use a temporary copy of the SAME bow/stem/teeth geometry as the drawer.
local function prepareViewKey(model)
	model.Name = "Key in avatar hand"
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = false
			child.LocalTransparencyModifier = 0
			child.Transparency = 1
		elseif child:IsA("WeldConstraint") or child:IsA("Constraint")
			or child:IsA("ProximityPrompt") or child:IsA("Script") or child:IsA("LocalScript") then
			child:Destroy()
		end
	end
	model.Parent = viewModel
	return model
end
local function makeViewKey()
	local actual = character and character:FindFirstChild("HeldKey")
	if actual and actual:IsA("Model") and actual.PrimaryPart then
		local archived = actual.Archivable
		actual.Archivable = true
		local clone = actual:Clone()
		actual.Archivable = archived
		if clone and clone.PrimaryPart then
			keyFromAvatar = true
			return prepareViewKey(clone)
		end
		if clone then clone:Destroy() end
	end
	keyFromAvatar = false
	local model = Instance.new("Model")
	local function piece(name, size, offset, color, shape)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(offset)
		part.Color = color
		part.Material = Enum.Material.Metal
		part.Shape = shape or Enum.PartType.Block
		part.Parent = model
		return part
	end
	local brass, patina = Color3.fromRGB(155, 115, 65), Color3.fromRGB(83, 66, 49)
	model.PrimaryPart = piece("Brass key bow", Vector3.new(0.2, 0.15, 0.2),
		Vector3.new(), patina, Enum.PartType.Ball)
	for bead = 1, 10 do
		local angle = bead * math.pi * 2 / 10
		piece("Forged circular key loop", Vector3.new(0.13, 0.12, 0.13),
			Vector3.new(math.cos(angle) * 0.24, 0, math.sin(angle) * 0.24),
			brass, Enum.PartType.Ball)
	end
	piece("Key stem", Vector3.new(0.16, 0.15, 0.85), Vector3.new(0, 0, 0.46), brass)
	piece("Key teeth", Vector3.new(0.34, 0.15, 0.14), Vector3.new(0.1, 0, 0.86), brass)
	return prepareViewKey(model)
end

local function syncKey()
	local current = player:GetAttribute("HeldKey")
	if current == keyNumber and (not current or keyModel) then
		if current and not keyFromAvatar and character then
			local actual = character:FindFirstChild("HeldKey")
			if actual and actual.PrimaryPart then
				keyModel:Destroy()
				keyModel = makeViewKey()
			end
		end
		return
	end
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
	keyFromAvatar = false
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

-- CFrame.lookAt's local -Z points at the next joint. Rotate so the
-- avatar limb's native +Y (toward its shoulder) points at that joint instead.
-- Using the COPIED parts' Size.Y makes wrist/elbow/shoulder actually meet for
-- different R15 body scales, rather than six independently posed blocks.
local function between(distal, proximal)
	return CFrame.lookAt((distal + proximal) / 2, proximal) * CFrame.Angles(-math.pi / 2, 0, 0)
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
	local expected = humanoid.RigType == Enum.HumanoidRigType.R15 and 3 or 1
	if #arms < expected and os.clock() - lastAttempt > 1 then buildArms() end
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
		-- Only the owner hides the welded original; the group still sees it.
		for _, part in ipairs(actualKey:GetDescendants()) do
			if part:IsA("BasePart") then part.LocalTransparencyModifier = 1 end
		end
	end
	local viewport = camera.ViewportSize
	local width = viewport and math.clamp(viewport.X / math.max(1, viewport.Y) / 1.5, 0.48, 1) or 1
	local pickup = math.sin(math.min(pickupTime / 0.55, 1) * math.pi) * 0.53
	local turn = turning and math.min(turnTime / 0.38, 1) or 0
	local sway = math.sin(stride) * math.min(speed / 14, 1) * 0.018
	local breathe = math.sin(elapsed * 1.55) * 0.007
	local hand = Vector3.new(0.43 * width - turn * 0.22 * width,
		-0.92 + pickup + turn * 0.63 + breathe + sway, -1.82 - turn * 0.40)
	local segments = {}
	for _, arm in ipairs(arms) do segments[arm.segment] = arm end
	local grip = hand
	if segments.hand and segments.lower and segments.upper then
		local handLength = segments.hand.part.Size.Y
		local wrist = hand + Vector3.new(0.018, handLength * 0.48, 0.06)
		local elbow = wrist + Vector3.new(0.33, 0.81, 0.48) * segments.lower.part.Size.Y
		local shoulder = elbow + Vector3.new(0.48, 0.54, 0.69) * segments.upper.part.Size.Y
		segments.hand.part.CFrame = camera.CFrame * between(hand * 2 - wrist, wrist)
		segments.lower.part.CFrame = camera.CFrame * between(wrist, elbow)
		segments.upper.part.CFrame = camera.CFrame * between(elbow, shoulder)
		grip = hand + Vector3.new(0, -handLength * 0.13, -0.17)
	elseif segments.r6 then
		local length = segments.r6.part.Size.Y
		local shoulder = hand + Vector3.new(0.38, 0.74, 0.56) * length
		segments.r6.part.CFrame = camera.CFrame * between(hand, shoulder)
		grip = hand + Vector3.new(0, length * 0.05, -0.17)
	end
	for _, arm in ipairs(arms) do
		arm.part.LocalTransparencyModifier = 0
		arm.part.Transparency = visible and arm.source.Transparency or 1
	end
	if keyModel then
		-- The bow is in the palm. Pickup and the lock-turn move this SAME
		-- replica with the hand; the shaft turns forward into the keyhole.
		keyModel:PivotTo(camera.CFrame * CFrame.new(grip)
			* CFrame.Angles(math.rad(125 + turn * 45), 0, math.rad(-12 + turn * 55)))
		for _, part in ipairs(keyModel:GetDescendants()) do
			if part:IsA("BasePart") then part.Transparency = visible and 0 or 1 end
		end
	end
end)
print("[NOCTURNE v7 / native first person] real-avatar right arm and same physical key are displayed only while carried")
