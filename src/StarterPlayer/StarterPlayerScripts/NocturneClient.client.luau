-- NOCTURNE / HUD, hiding treatment, light and close-up scares.
-- The separate NocturnePerspective script owns native first-person and copies
-- real avatar limbs, even if this larger HUD script cannot start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NocturneRemote")
local camera = Workspace.CurrentCamera
local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local GOLD = Color3.fromRGB(216, 174, 113)
local PALE = Color3.fromRGB(218, 228, 221)
local RED = Color3.fromRGB(196, 62, 55)
local DARK = Color3.fromRGB(8, 11, 16)
local function damp(rate, dt) return 1 - math.exp(-rate * dt) end

-- No instructions, objectives, danger text or full-screen warning flashes.
-- The only in-world UI is a small stamina line and an aim point; native
-- interaction prompts are icon-only. Mobile action buttons remain usable.
local ui = Instance.new("ScreenGui")
ui.Name = "NocturneHUD"
ui.IgnoreGuiInset = true
ui.ResetOnSpawn = false
ui.DisplayOrder = 50
ui.Parent = player:WaitForChild("PlayerGui")

local function frame(parent, name, size, position, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color or DARK
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end
local function label(parent, name, value, size, position, font, fontSize, color, align)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Text = value
	t.Size = size
	t.Position = position
	t.BackgroundTransparency = 1
	t.Font = font or Enum.Font.Gotham
	t.TextSize = fontSize or 18
	t.TextColor3 = color or PALE
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextStrokeColor3 = DARK
	t.TextStrokeTransparency = 0.7
	t.Parent = parent
	return t
end
local function button(parent, name, text, size, position)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Size = size
	b.Position = position
	b.Font = Enum.Font.GothamBold
	b.TextSize = 17
	b.TextColor3 = PALE
	b.BackgroundColor3 = Color3.fromRGB(31, 37, 42)
	b.BackgroundTransparency = 0.12
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Transparency = 0.5
	stroke.Thickness = 1
	stroke.Parent = b
	return b
end
local function edge(name, size, pos, rotation)
	local f = frame(ui, name, size, pos, Color3.new(0, 0, 0), 0)
	f.ZIndex = 2
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = f
end
edge("Top vignette", UDim2.fromScale(1, 0.13), UDim2.fromScale(0, 0), 90)
edge("Bottom vignette", UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.82), 270)
edge("Left vignette", UDim2.fromScale(0.09, 1), UDim2.fromScale(0, 0), 0)
edge("Right vignette", UDim2.fromScale(0.09, 1), UDim2.fromScale(0.91, 0), 180)
local staminaTrack = frame(ui, "Stamina track", UDim2.fromOffset(108, 2),
	UDim2.new(0, 18, 1, -27), PALE, 0.79)
staminaTrack.ZIndex = 4
local staminaFill = frame(staminaTrack, "Stamina", UDim2.fromScale(1, 1),
	UDim2.fromScale(0, 0), PALE, 0)
staminaFill.ZIndex = 5
local reticle = frame(ui, "Reticle", UDim2.fromOffset(3, 3),
	UDim2.fromScale(0.5, 0.5), PALE, 0.25)
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.ZIndex = 5

-- A dying player gets a close-up of the attacking creature, not a brief red
-- wash hidden immediately behind the retry menu. ViewportFrame never takes
-- control of the real camera or the physical avatar.
local scare = frame(ui, "Creature close-up", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), DARK, 0)
scare.ZIndex = 18
scare.Visible = false
scare.Active = true
local scareView = Instance.new("ViewportFrame")
scareView.Name = "Attacking creature"
scareView.Size = UDim2.fromScale(1.14, 1.14)
scareView.AnchorPoint = Vector2.new(0.5, 0.5)
scareView.Position = UDim2.fromScale(0.5, 0.5)
scareView.BackgroundTransparency = 1
scareView.Ambient = Color3.fromRGB(89, 95, 92)
scareView.LightColor = Color3.fromRGB(220, 205, 180)
scareView.LightDirection = Vector3.new(-0.45, -0.3, -1)
scareView.ZIndex = 19
scareView.Parent = scare
local scareWorld = Instance.new("WorldModel")
scareWorld.Name = "The approaching face"
scareWorld.Parent = scareView
local scareCamera = Instance.new("Camera")
scareCamera.FieldOfView = 52
scareCamera.Parent = scareView
scareView.CurrentCamera = scareCamera
local scareVeil = frame(scare, "Split second red flash", UDim2.fromScale(1, 1),
	UDim2.fromScale(0, 0), RED, 1)
scareVeil.ZIndex = 20
local scareToken = 0

-- These dark edges frame the actual open sightline through the slatted
-- wardrobe doors. They do NOT cover the centre or draw advice over a monster.
local leftPanel = frame(ui, "Left wardrobe edge", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0),
	Color3.fromRGB(19, 15, 16), 0.03)
leftPanel.ZIndex = 12
local rightPanel = frame(ui, "Right wardrobe edge", UDim2.fromScale(0, 1), UDim2.fromScale(1, 0),
	Color3.fromRGB(19, 15, 16), 0.03)
rightPanel.AnchorPoint = Vector2.new(1, 0)
rightPanel.ZIndex = 12
for _, panel in ipairs({leftPanel, rightPanel}) do
	for j = 1, 3 do
		local strip = frame(panel, "Wood grain", UDim2.new(0, 1, 1, 0),
			UDim2.fromScale(j / 4, 0), GOLD, 0.86)
		strip.ZIndex = 13
	end
end

local modal = frame(ui, "End card", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), DARK, 0.06)
modal.ZIndex = 25
modal.Visible = false
modal.Active = true
local modalEyebrow = label(modal, "Eyebrow", "ПОРАЖЕНИЕ", UDim2.fromScale(0.7, 0.055),
	UDim2.fromScale(0.15, 0.29), Enum.Font.GothamMedium, 13, RED, Enum.TextXAlignment.Center)
modalEyebrow.ZIndex = 26
local modalTitle = label(modal, "End title", "ПРОХОЖДЕНИЕ ПРЕРВАНО", UDim2.fromScale(0.86, 0.14),
	UDim2.fromScale(0.07, 0.36), Enum.Font.Garamond, 52, PALE, Enum.TextXAlignment.Center)
modalTitle.TextScaled = true
modalTitle.ZIndex = 26
local retryButton = button(modal, "Try again", "ПОПРОБОВАТЬ СНОВА", UDim2.fromOffset(272, 48),
	UDim2.fromScale(0.5, 0.67))
retryButton.AnchorPoint = Vector2.new(0.5, 0)
retryButton.ZIndex = 27

local sprintButton = button(ui, "Mobile sprint", "»", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -277))
sprintButton.ZIndex = 18
sprintButton.Visible = isTouch
local crouchButton = button(ui, "Mobile crouch", "↓", UDim2.fromOffset(100, 53),
	UDim2.new(1, -122, 1, -215))
crouchButton.ZIndex = 18
crouchButton.Visible = isTouch
local lightButton = button(ui, "Mobile torch", "☼", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -153))
lightButton.ZIndex = 18
lightButton.Visible = isTouch
local exitButton = button(ui, "Leave wardrobe", "↩", UDim2.fromOffset(105, 52),
	UDim2.new(1, -124, 1, -222))
exitButton.ZIndex = 18
exitButton.Visible = false

-- No tutorial captions or button hints at the bottom of the screen.
-- Mobile action buttons are controls, not on-screen survival instructions.

-- Studio cannot reliably read local built-in sound files. Do not create or
-- preload failing Sound instances; threats are intentionally signalled visually.

-- Keep the real character and its collisions untouched. Roblox's first-person
-- CameraModule fades the body locally; we display ONLY non-colliding copies of
-- its own textured limbs. Never fade the whole avatar or move its root here.
local peekCF = nil
local root = nil
local humanoid = nil
local head = nil
local hidden = false
local dead = false
local finished = false
local elapsed = 0
local flashlightOn = true
local sprinting = false
local crouching = false

local torchMount = Instance.new("Part")
torchMount.Name = "Invisible torch light source"
torchMount.Size = Vector3.new(0.2, 0.2, 0.2)
torchMount.Anchored = true
torchMount.CanCollide = false
torchMount.CanTouch = false
torchMount.CanQuery = false
torchMount.CastShadow = false
torchMount.Transparency = 1
torchMount.Parent = camera
local torch = Instance.new("SpotLight")
torch.Name = "Weak hand torch"
torch.Angle = 69
torch.Range = 29
torch.Brightness = 1.35
torch.Color = Color3.fromRGB(255, 221, 179)
torch.Face = Enum.NormalId.Front
torch.Shadows = true
torch.Enabled = false
torch.Parent = torchMount

local function setSprint(on)
	if on and (crouching or hidden or dead or finished) then return end
	if sprinting == on then return end
	sprinting = on
	remote:FireServer("Sprint", on)
end
local function setCrouch(on)
	if hidden or dead or finished or crouching == on then return end
	if on then setSprint(false) end
	crouching = on
	crouchButton.Text = on and "↑" or "↓"
	-- Only change the native camera's target height. Avatar motion/collision
	-- remain with Roblox's Humanoid, and the server owns the crouch speed.
	if humanoid then humanoid.CameraOffset = Vector3.new(0, on and -0.65 or 0, 0) end
	remote:FireServer("Crouch", on)
end
local function toggleTorch()
	if hidden or dead or finished then return end
	flashlightOn = not flashlightOn
	torch.Enabled = flashlightOn
	remote:FireServer("Torch", flashlightOn)
end
local function fallbackScareFace(kind)
	-- Streaming/order-of-replication fallback. Even without the source model,
	-- the final room and death scene show the same huge hollow orbital rings.
	local model = Instance.new("Model")
	model.Name = "Last glimpse of " .. tostring(kind)
	local color = kind == "MOTH" and Color3.fromRGB(177, 187, 175)
		or kind == "BLIND" and Color3.fromRGB(196, 199, 182)
		or Color3.fromRGB(207, 207, 189)
	local function oval(name, size, cf, tint)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Slate
		part.Color = tint
		part.CFrame = cf
		part.Parent = model
		return part
	end
	local body = oval("A body in the dark", Vector3.new(1.6, 4.3, 1),
		CFrame.new(0, -0.3, 0.5), Color3.fromRGB(19, 23, 25))
	model.PrimaryPart = body
	oval("Last mask", Vector3.new(2.55, 3.22, 1.28), CFrame.new(0, 3.32, -0.47), color)
	for _, side in ipairs({-1, 1}) do
		oval("Continuous pale eye surround", Vector3.new(1.22, 1.35, 0.12),
			CFrame.new(side * 0.63, 3.59, -1.12), color)
		oval("Black orbital hollow", Vector3.new(0.98, 1.15, 0.15),
			CFrame.new(side * 0.63, 3.59, -1.19), DARK)
		for bead = 1, 14 do
			local theta = bead * 2 * math.pi / 14
			oval("Pale orbital rim", Vector3.new(0.15, 0.18, 0.13),
				CFrame.new(side * 0.63 + math.cos(theta) * 0.45,
					3.59 + math.sin(theta) * 0.52, -1.25), color)
		end
		oval("Black pupil", Vector3.new(0.58, 0.7, 0.12),
			CFrame.new(side * 0.63, 3.57, -1.31), DARK)
	end
	oval("Still mouth", Vector3.new(0.83, 0.18, 0.13), CFrame.new(0, 2.53, -1.14), DARK)
	return model
end
local function showScare(kind, source)
	scareToken = scareToken + 1
	local token = scareToken
	reticle.Visible = false
	scare.Visible = true
	for _, child in ipairs(scareWorld:GetChildren()) do child:Destroy() end
	local monster = source
	if not monster or not monster:IsA("Model") then
		local world = Workspace:FindFirstChild("NocturneWorld")
		local names = {RUSH = "TheRush", BLIND = "TheBlindGuest",
			MOTH = "ThePaleMoth", FINAL = "TheLastWitness"}
		monster = world and world:FindFirstChild(names[kind] or "", true)
	end
	local copy = monster and monster:Clone()
	if not copy then copy = fallbackScareFace(kind) end
	copy.Parent = scareWorld
	copy:PivotTo(CFrame.new(0, -0.15, 0))
	local eyeY = kind == "FINAL" and 3.93 or kind == "BLIND" and 3.75
		or kind == "MOTH" and 3.18 or 3.5
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local aspect = viewport.X / math.max(1, viewport.Y)
	-- Keep BOTH dark eyes in frame on a tall phone as well as a wide monitor.
	-- A fixed -2.4 close-up cropped the entire mask to its nose on mobile.
	local nearDistance = math.clamp(1.4 + 1.23 / (math.tan(math.rad(20))
		* math.max(0.42, aspect)), 3.1, 11)
	local farDistance = math.max(10.5, nearDistance + 5)
	scareView.Ambient = kind == "MOTH" and Color3.fromRGB(124, 150, 140)
		or kind == "RUSH" and Color3.fromRGB(137, 144, 146)
		or Color3.fromRGB(157, 161, 151)
	scareView.LightColor = Color3.fromRGB(243, 234, 211)
	scareVeil.BackgroundColor3 = kind == "FINAL" and Color3.fromRGB(214, 225, 213)
		or kind == "MOTH" and Color3.fromRGB(129, 171, 154)
		or kind == "RUSH" and Color3.fromRGB(126, 141, 151)
		or Color3.fromRGB(177, 190, 181)
	scareVeil.BackgroundTransparency = 0.78
	-- Hold the distant silhouette for a heartbeat, then snap to a face that
	-- fills the screen. Two SHORT flashes and a clear hold replace a red wash
	-- that used to cover the monster before the retry card appeared.
	scareCamera.FieldOfView = 58
	scareCamera.CFrame = CFrame.lookAt(Vector3.new(0, eyeY + 0.12, -farDistance),
		Vector3.new(0, eyeY, 0))
	task.delay(0.28, function()
		if token ~= scareToken then return end
		scareVeil.BackgroundTransparency = 0.12
		TweenService:Create(scareCamera,
			TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{CFrame = CFrame.lookAt(Vector3.new(0.12, eyeY + 0.16, -nearDistance - 0.4),
				Vector3.new(0, eyeY, -0.2)), FieldOfView = 44}):Play()
		TweenService:Create(scareVeil, TweenInfo.new(0.12),
			{BackgroundTransparency = 0.93}):Play()
	end)
	task.delay(0.61, function()
		if token ~= scareToken then return end
		scareVeil.BackgroundTransparency = 0.38
		TweenService:Create(scareVeil, TweenInfo.new(0.15),
			{BackgroundTransparency = 0.96}):Play()
		TweenService:Create(scareCamera, TweenInfo.new(0.12),
			{CFrame = CFrame.lookAt(Vector3.new(-0.14, eyeY + 0.03, -nearDistance),
				Vector3.new(0, eyeY, -0.3)), FieldOfView = 40}):Play()
	end)
end
local function showEnd(win)
	if win then
		finished = true
		modalEyebrow.Text = "100 / 100  ·  РАССВЕТ"
		modalEyebrow.TextColor3 = GOLD
		modalTitle.Text = "ВЫХОД"
		retryButton.Text = "СЫГРАТЬ ЕЩЁ РАЗ"
	else
		dead = true
		setSprint(false)
		modalEyebrow.Text = "ПОРАЖЕНИЕ"
		modalEyebrow.TextColor3 = RED
		modalTitle.Text = "ПРОХОЖДЕНИЕ ПРЕРВАНО"
		retryButton.Text = "ПОПРОБОВАТЬ СНОВА"
	end
	modal.Visible = true
	reticle.Visible = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

retryButton.MouseButton1Click:Connect(function()
	if dead or finished then
		modal.Visible = false
		remote:FireServer("Retry")
	end
end)
sprintButton.MouseButton1Down:Connect(function() setSprint(true) end)
sprintButton.MouseButton1Up:Connect(function() setSprint(false) end)
sprintButton.MouseLeave:Connect(function() if isTouch then setSprint(false) end end)
crouchButton.MouseButton1Click:Connect(function() setCrouch(not crouching) end)
lightButton.MouseButton1Click:Connect(toggleTorch)
exitButton.MouseButton1Click:Connect(function() remote:FireServer("Exit") end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.ButtonB and not UserInputService:GetFocusedTextBox() then
		if hidden then remote:FireServer("Exit") else setCrouch(not crouching) end
		return -- Roblox's default jump binding may consume this gamepad button.
	end
	if hidden and input.KeyCode == Enum.KeyCode.E then
		remote:FireServer("Exit")
		return
	end
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
		setSprint(true)
	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
		setCrouch(not crouching)
	elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonY then
		toggleTorch()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
		setSprint(false)
	end
end)
-- Camera input on mouse, touch and gamepad is handled by Roblox's PlayerModule;
-- consuming and reapplying those deltas caused the detached, flying viewpoint.

player:GetAttributeChangedSignal("Stamina"):Connect(function()
	local stamina = math.clamp(player:GetAttribute("Stamina") or 100, 0, 100)
	staminaFill.Size = UDim2.fromScale(stamina / 100, 1)
	staminaFill.BackgroundColor3 = stamina < 20 and RED or PALE
end)

local function restoreCamera()
	camera = Workspace.CurrentCamera
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then camera.CameraSubject = humanoid end
	end
end

remote.OnClientEvent:Connect(function(event, a, b, c)
	if event == "State" then
		if not dead and not finished then modal.Visible = false end
	elseif event == "Hide" then
		hidden = a
		player:SetAttribute("NocturnePeek", hidden)
		setSprint(false)
		crouching = false
		if humanoid then humanoid.CameraOffset = Vector3.new(0, 0, 0) end
		crouchButton.Text = "↓"
		crouchButton.Visible = not hidden and isTouch
		reticle.Visible = not hidden and not dead and not finished
		if a then
			-- An anchored character can peek through the wardrobe. Scriptable
			-- camera is used ONLY here, never while walking the hotel.
			peekCF = b
			if camera and peekCF then
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = peekCF
			end
			TweenService:Create(leftPanel, TweenInfo.new(0.32), {Size = UDim2.fromScale(0.13, 1)}):Play()
			TweenService:Create(rightPanel, TweenInfo.new(0.32), {Size = UDim2.fromScale(0.13, 1)}):Play()
		else
			peekCF = nil
			restoreCamera()
			TweenService:Create(leftPanel, TweenInfo.new(0.27), {Size = UDim2.fromScale(0, 1)}):Play()
			TweenService:Create(rightPanel, TweenInfo.new(0.27), {Size = UDim2.fromScale(0, 1)}):Play()
		end
		exitButton.Visible = hidden and isTouch
		sprintButton.Visible = not hidden and isTouch
		lightButton.Visible = not hidden and isTouch
	elseif event == "Jumpscare" then
		showScare(a, b)
	elseif event == "Death" then
		if scare.Visible then
			dead = true
			setSprint(false)
			local token = scareToken
			task.delay(1.85, function()
				if scareToken ~= token or not dead then return end
				scare.Visible = false
				showEnd(false)
			end)
		else
			showEnd(false)
		end
	elseif event == "Finale" then
		finished = true
		setSprint(false)
		torch.Enabled = false
		showScare("FINAL", a)
		local token = scareToken
		task.delay(2.4, function()
			if scareToken ~= token or not finished then return end
			scare.Visible = false
			showEnd(true)
		end)
	elseif event == "Victory" then
		-- Keep compatibility with older servers; v7 uses the physical finale.
		showEnd(true)
	end
end)

local function onCharacter(character)
	local newRoot = character:WaitForChild("HumanoidRootPart")
	local newHumanoid = character:WaitForChild("Humanoid")
	local newHead = character:WaitForChild("Head", 8)
	if player.Character ~= character then return end -- late appearance from a previous life
	root, humanoid, head = newRoot, newHumanoid, newHead
	hidden = false
	peekCF = nil
	dead = false
	finished = false
	scareToken = scareToken + 1 -- cancel a previous life's delayed death card
	scare.Visible = false
	for _, child in ipairs(scareWorld:GetChildren()) do child:Destroy() end
	crouching = false
	humanoid.CameraOffset = Vector3.new(0, 0, 0)
	crouchButton.Text = "↓"
	crouchButton.Visible = isTouch
	modal.Visible = false
	leftPanel.Size = UDim2.fromScale(0, 1)
	rightPanel.Size = UDim2.fromScale(0, 1)
	exitButton.Visible = false
	sprintButton.Visible = isTouch
	lightButton.Visible = isTouch
	reticle.Visible = true
	player:SetAttribute("NocturnePeek", false)
	-- Native first person remains attached to the real Humanoid. The real
	-- avatar is never made transparent by THIS script or moved each frame.
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	restoreCamera()
	torchMount.Parent = camera
	remote:FireServer("Torch", flashlightOn)
	setSprint(false)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end
remote:FireServer("Ready")

-- Roblox's CameraModule drives the camera in every playable room. This
-- callback touches only camera-local display parts, never the real character
-- or HumanoidRootPart; collision stays with Roblox's physical avatar.
RunService:BindToRenderStep("NocturneEffects", Enum.RenderPriority.Camera.Value + 1, function(dt)
	dt = math.min(dt, 0.07)
	elapsed = elapsed + dt
	if scare.Visible then
		scareView.Position = UDim2.new(0.5, math.random(-12, 12), 0.5, math.random(-9, 9))
	end
	local current = Workspace.CurrentCamera
	if current ~= camera then
		camera = current
		torchMount.Parent = camera
		if hidden and peekCF and camera then
			camera.CameraType = Enum.CameraType.Scriptable
		elseif humanoid then
			restoreCamera()
		end
	end
	if not camera or not root or not humanoid or not root.Parent then return end
	local pressure = 0
	if hidden and peekCF then
		-- The server still controls the threat. Measure its replicated model in
		-- the REAL room; the closer it gets to the wardrobe, the less steadily
		-- the player breathes. The clear centre stays visible at all times.
		local world = Workspace:FindFirstChild("NocturneWorld")
		if world then
			for _, name in ipairs({"TheRush", "TheBlindGuest", "ThePaleMoth"}) do
				local monster = world:FindFirstChild(name)
				local body = monster and monster.PrimaryPart
				if body then
					local distance = (body.Position - peekCF.Position).Magnitude
					pressure = math.max(pressure, math.clamp(1 - distance / 30, 0, 1))
				end
			end
		end
		local breath = math.sin(elapsed * (2.2 + pressure * 3.2))
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = peekCF * CFrame.new(
			breath * (0.013 + pressure * 0.041) + math.sin(elapsed * 17) * pressure * 0.008,
			math.sin(elapsed * 1.2) * 0.012, 0)
			* CFrame.Angles(0, math.sin(elapsed * 0.9) * 0.009 * (1 + pressure), 0)
		leftPanel.BackgroundTransparency = math.clamp(0.14 - pressure * (0.105 + breath * 0.018), 0.01, 0.14)
		rightPanel.BackgroundTransparency = leftPanel.BackgroundTransparency
	elseif camera.CameraType == Enum.CameraType.Scriptable then
		restoreCamera() -- also recovers after death/respawn inside a wardrobe
	end
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = not hidden and not dead and horizontalSpeed > 1.5
		and humanoid.MoveDirection.Magnitude > 0.05
	local running = moving and not crouching and horizontalSpeed > 15
	camera.FieldOfView = camera.FieldOfView + ((hidden and (70 - pressure * 9) or (running and 79 or 73))
		- camera.FieldOfView) * damp(4, dt)
	local origin = head and head.Parent and head.Position or (root.Position + Vector3.new(0, 1.6, 0))
	origin = origin + camera.CFrame.RightVector * 0.45
	torchMount.CFrame = CFrame.lookAt(origin, origin + camera.CFrame.LookVector)
	torch.Enabled = flashlightOn and not hidden and not dead and not finished
end)
