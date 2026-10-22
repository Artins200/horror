-- Native first person: the ACTUAL R6/R15 hands hold the key and selected item.
-- No cloned limb, fake wrist, free camera or replacement physics avatar.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local character, humanoid
local shoulder, elbow, wrist
local leftShoulder, leftElbow, leftWrist
local original = {}
local pieces, leftPieces = {}, {}
local elapsed, pickup, itemPickup, turn = 0, 1, 1, 0
local lastKey, lastItem, turning, posed = nil, nil, false, false

local function lockCamera()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	local camera = Workspace.CurrentCamera
	if camera and humanoid and humanoid.Health > 0
		and not player:GetAttribute("Hidden") and not player:GetAttribute("NocturnePeek") then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function resetPose()
	if not posed then return end
	for motor, cf in pairs(original) do
		if motor.Parent then motor.C0 = cf end
	end
	posed = false
end

local function bindArm()
	resetPose()
	original, pieces, leftPieces = {}, {}, {}
	if not character then return end
	local r15 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
	shoulder = character:FindFirstChild(r15 and "RightShoulder" or "Right Shoulder", true)
	elbow = r15 and character:FindFirstChild("RightElbow", true) or nil
	wrist = r15 and character:FindFirstChild("RightWrist", true) or nil
	leftShoulder = character:FindFirstChild(r15 and "LeftShoulder" or "Left Shoulder", true)
	leftElbow = r15 and character:FindFirstChild("LeftElbow", true) or nil
	leftWrist = r15 and character:FindFirstChild("LeftWrist", true) or nil
	-- R6 has no elbows/wrists: ipairs stops at a nil hole, so remember
	-- each joint independently rather than accidentally skipping LEFT shoulder.
	local function remember(joint)
		if joint and joint:IsA("Motor6D") then original[joint] = joint.C0 end
	end
	remember(shoulder)
	remember(elbow)
	remember(wrist)
	remember(leftShoulder)
	remember(leftElbow)
	remember(leftWrist)
	local right = r15 and {"RightUpperArm", "RightLowerArm", "RightHand"} or {"Right Arm"}
	local left = r15 and {"LeftUpperArm", "LeftLowerArm", "LeftHand"} or {"Left Arm"}
	for _, name in ipairs(right) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then table.insert(pieces, part) end
	end
	for _, name in ipairs(left) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then table.insert(leftPieces, part) end
	end
end

local function onCharacter(avatar)
	local human = avatar:WaitForChild("Humanoid")
	if player.Character ~= avatar then return end
	resetPose()
	character, humanoid = avatar, human
	lastKey, lastItem, turning, pickup, itemPickup, turn = nil, nil, false, 1, 1, 0
	player:SetAttribute("NocturnePeek", false)
	lockCamera()
	bindArm()
end

player.CharacterAdded:Connect(onCharacter)
player.CharacterAppearanceLoaded:Connect(function(avatar)
	if avatar == character then bindArm() end
end)
lockCamera() -- first person survives a HUD error or delayed PlayerGui
if player.Character then task.spawn(onCharacter, player.Character) end

local function pose(motor, degreesX, degreesZ)
	if not motor or not original[motor] then return end
	local base = original[motor]
	-- Rotate in the parent limb's axes BEFORE the avatar's own rig rotation.
	-- Motor6D still joins each REAL Roblox mesh to the next at its stock joint.
	motor.C0 = CFrame.new(base.Position)
		* CFrame.Angles(math.rad(degreesX), 0, math.rad(degreesZ)) * base.Rotation
	posed = true
end

RunService:BindToRenderStep("NocturnePerspective", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local camera = Workspace.CurrentCamera
	if not camera or not character or player.Character ~= character or not humanoid then return end
	local peek = player:GetAttribute("Hidden") or player:GetAttribute("NocturnePeek")
	if not peek and humanoid.Health > 0 and (player.CameraMode ~= Enum.CameraMode.LockFirstPerson
		or camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid) then
		lockCamera()
	end
	if not shoulder or not shoulder.Parent then bindArm() end
	local key = player:GetAttribute("HeldKey")
	local item = character:FindFirstChild("HeldItem")
	local itemId = item and item:GetAttribute("ItemKind") or nil
	local gripHand = item and item:GetAttribute("GripHand") or nil
	local alive = not peek and humanoid.Health > 0
	local rightVisible = alive and (key ~= nil or itemId ~= nil and gripHand == "Right")
	local leftVisible = alive and itemId ~= nil and gripHand == "Left"
	if key ~= lastKey then
		pickup = key and 0 or 1
		lastKey = key
	end
	if itemId ~= lastItem then
		itemPickup = itemId and 0 or 1
		lastItem = itemId
	end
	local nowTurning = player:GetAttribute("KeyTurning") == true
	if nowTurning and not turning then turn = 0 end
	turning = nowTurning
	dt = math.min(dt, 0.08)
	elapsed = elapsed + dt
	pickup = math.min(1, pickup + dt / 0.42)
	itemPickup = math.min(1, itemPickup + dt / 0.34)
	turn = nowTurning and math.min(1, turn + dt / 0.35) or math.max(0, turn - dt / 0.25)
	resetPose()
	if rightVisible and shoulder and original[shoulder] then
		local step = math.sin(elapsed * 5.5) * 1.7
		if key ~= nil then
			-- The original right-hand key pose still raises it INTO the lock.
			pose(shoulder, pickup * (70 + turn * 23) + step, pickup * 10)
			if elbow then pose(elbow, -pickup * (43 + turn * 13), 0) end
			if wrist then pose(wrist, pickup * 5, -pickup * (10 + turn * 8)) end
		else
			-- Relaxed grip for a torch/medicine: ordinary-sized connected limbs.
			pose(shoulder, itemPickup * 48 + step, itemPickup * 6)
			if elbow then pose(elbow, -itemPickup * 33, 0) end
			if wrist then pose(wrist, -itemPickup * 4, 0) end
		end
	end
	if leftVisible and leftShoulder and original[leftShoulder] then
		pose(leftShoulder, itemPickup * 46, -itemPickup * 7)
		if leftElbow then pose(leftElbow, -itemPickup * 31, 0) end
		if leftWrist then pose(leftWrist, -itemPickup * 4, 0) end
	end
	-- CameraModule normally fades the character in first person. Restore
	-- ONLY the real jointed limbs currently holding something, and their
	-- welded server-owned models; all avatar collisions remain untouched.
	for _, part in ipairs(pieces) do
		if part.Parent then part.LocalTransparencyModifier = rightVisible and 0 or 1 end
	end
	for _, part in ipairs(leftPieces) do
		if part.Parent then part.LocalTransparencyModifier = leftVisible and 0 or 1 end
	end
	local heldKey = character:FindFirstChild("HeldKey")
	if heldKey then
		for _, part in ipairs(heldKey:GetDescendants()) do
			if part:IsA("BasePart") then part.LocalTransparencyModifier = alive and key ~= nil and 0 or 1 end
		end
	end
	if item then
		for _, part in ipairs(item:GetDescendants()) do
			if part:IsA("BasePart") then part.LocalTransparencyModifier = alive and 0 or 1 end
		end
	end
end)
print("[NOCTURNE v12 / native first person] actual R6/R15 hands, key and selected item")
