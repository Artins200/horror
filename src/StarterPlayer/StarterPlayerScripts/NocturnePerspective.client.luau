-- Native Roblox first person, with the ACTUAL right arm and welded drawer key.
-- No clone, fake wrist, free camera or replacement avatar can detach at a joint.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local character, humanoid
local shoulder, elbow, wrist
local original = {}
local pieces = {}
local elapsed, pickup, turn = 0, 1, 0
local lastKey, turning, posed = nil, false, false

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
	original, pieces = {}, {}
	if not character then return end
	local r15 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
	shoulder = character:FindFirstChild(r15 and "RightShoulder" or "Right Shoulder", true)
	elbow = r15 and character:FindFirstChild("RightElbow", true) or nil
	wrist = r15 and character:FindFirstChild("RightWrist", true) or nil
	for _, joint in ipairs({shoulder, elbow, wrist}) do
		if joint and joint:IsA("Motor6D") then original[joint] = joint.C0 end
	end
	local names = r15 and {"RightUpperArm", "RightLowerArm", "RightHand"} or {"Right Arm"}
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then table.insert(pieces, part) end
	end
end

local function onCharacter(avatar)
	local human = avatar:WaitForChild("Humanoid")
	if player.Character ~= avatar then return end
	resetPose()
	character, humanoid = avatar, human
	lastKey, turning, pickup, turn = nil, false, 1, 0
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
	local visible = key ~= nil and not peek and humanoid.Health > 0
	if key ~= lastKey then
		pickup = key and 0 or 1
		lastKey = key
	end
	local nowTurning = player:GetAttribute("KeyTurning") == true
	if nowTurning and not turning then turn = 0 end
	turning = nowTurning
	dt = math.min(dt, 0.08)
	elapsed = elapsed + dt
	pickup = math.min(1, pickup + dt / 0.42)
	turn = nowTurning and math.min(1, turn + dt / 0.35) or math.max(0, turn - dt / 0.25)
	if visible and shoulder and original[shoulder] then
		local step = math.sin(elapsed * 5.5) * 1.7
		-- The upper arm reaches forward, the native elbow bends the forearm,
		-- and the same welded key follows the native hand into the keyhole.
		pose(shoulder, pickup * (70 + turn * 23) + step, pickup * 10)
		if elbow then pose(elbow, -pickup * (43 + turn * 13), 0) end
		if wrist then pose(wrist, pickup * 5, -pickup * (10 + turn * 8)) end
	else
		resetPose()
	end
	-- Roblox's first-person controller normally fades the whole character.
	-- Override ONLY the connected right limbs and the physical key, locally;
	-- the full colliding avatar remains visible to the rest of the group.
	for _, part in ipairs(pieces) do
		if part.Parent then part.LocalTransparencyModifier = visible and 0 or 1 end
	end
	local held = character:FindFirstChild("HeldKey")
	if held then
		for _, part in ipairs(held:GetDescendants()) do
			if part:IsA("BasePart") then part.LocalTransparencyModifier = visible and 0 or 1 end
		end
	end
end)
print("[NOCTURNE v9 / native first person] actual R6/R15 arm and welded key; no viewmodel clones")
