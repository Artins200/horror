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
local Layout = require(ReplicatedStorage:WaitForChild("NocturneLayout"))
local camera = Workspace.CurrentCamera
local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local GOLD = Color3.fromRGB(216, 174, 113)
local PALE = Color3.fromRGB(218, 228, 221)
local RED = Color3.fromRGB(196, 62, 55)
local DARK = Color3.fromRGB(8, 11, 16)
local function damp(rate, dt) return 1 - math.exp(-rate * dt) end

-- A drawn interface, not imported images. It remains legible at low light and
-- scales with the viewport. Default ProximityPrompts keep native mobile/gamepad use.
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
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = f
end
edge("Top vignette", UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0), 90)
edge("Bottom vignette", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.7), 270)
edge("Left vignette", UDim2.fromScale(0.19, 1), UDim2.fromScale(0, 0), 0)
edge("Right vignette", UDim2.fromScale(0.19, 1), UDim2.fromScale(0.81, 0), 180)

local topLine = frame(ui, "Fine top rule", UDim2.new(1, -72, 0, 1), UDim2.new(0, 36, 0, 35), GOLD, 0.58)
topLine.ZIndex = 4
local brand = label(ui, "Title", "N O C T U R N E", UDim2.new(0, 350, 0, 38),
	UDim2.new(0, 39, 0, 42), Enum.Font.Garamond, 30, GOLD)
brand.ZIndex = 4
local tagline = label(ui, "Tagline", "100 ДВЕРЕЙ  ·  18 ЭТАЖЕЙ", UDim2.new(0, 370, 0, 22),
	UDim2.new(0, 40, 0, 80), Enum.Font.GothamMedium, 11, PALE)
tagline.TextTransparency = 0.27
tagline.ZIndex = 4
local doorTitle = label(ui, "Door caption", "СЛЕДУЮЩАЯ ДВЕРЬ", UDim2.new(0, 228, 0, 22),
	UDim2.new(1, -263, 0, 43), Enum.Font.GothamMedium, 11, GOLD, Enum.TextXAlignment.Right)
doorTitle.ZIndex = 4
local doorLabel = label(ui, "Door number", "001  /  100", UDim2.new(0, 230, 0, 45),
	UDim2.new(1, -265, 0, 65), Enum.Font.Garamond, 34, PALE, Enum.TextXAlignment.Right)
doorLabel.ZIndex = 4
local progressBase = frame(ui, "Progress track", UDim2.new(0, 204, 0, 2),
	UDim2.new(1, -241, 0, 112), GOLD, 0.79)
progressBase.ZIndex = 4
local progressFill = frame(progressBase, "Progress", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), GOLD, 0)
progressFill.ZIndex = 5
local floorLabel = label(ui, "Storey", "ЭТАЖ 01  /  18", UDim2.new(0, 215, 0, 24),
	UDim2.new(1, -253, 0, 122), Enum.Font.GothamMedium, 12, GOLD, Enum.TextXAlignment.Right)
floorLabel.ZIndex = 4

local staminaCaption = label(ui, "Stamina label", "ДЫХАНИЕ", UDim2.new(0, 170, 0, 22),
	UDim2.new(0, 40, 1, -93), Enum.Font.GothamMedium, 11, GOLD)
staminaCaption.ZIndex = 4
local staminaTrack = frame(ui, "Stamina track", UDim2.new(0, 168, 0, 3),
	UDim2.new(0, 40, 1, -66), PALE, 0.78)
staminaTrack.ZIndex = 4
local staminaFill = frame(staminaTrack, "Stamina", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), PALE, 0)
staminaFill.ZIndex = 5
local help = label(ui, "Controls", isTouch and "СЛЕВА — ИДТИ   ·   СПРАВА — ОСМОТР" or
	"WASD — идти   SHIFT — бег   C/CTRL — присесть   E — действие   F — фонарь", UDim2.new(0.67, 0, 0, 25),
	UDim2.new(0.5, 0, 1, -49), Enum.Font.GothamMedium, 11, PALE, Enum.TextXAlignment.Center)
help.AnchorPoint = Vector2.new(0.5, 0)
help.TextTransparency = 0.25
help.ZIndex = 4
local flashLabel = label(ui, "Flashlight status", "F  ·  ФОНАРЬ", UDim2.new(0, 175, 0, 24),
	UDim2.new(1, -211, 1, -76), Enum.Font.GothamMedium, 12, GOLD, Enum.TextXAlignment.Right)
flashLabel.ZIndex = 4

local notice = label(ui, "Interaction status", "", UDim2.new(0.84, 0, 0, 74), UDim2.fromScale(0.08, 0.69),
	Enum.Font.Garamond, 27, GOLD, Enum.TextXAlignment.Center)
notice.TextWrapped = true
notice.TextTransparency = 1
notice.ZIndex = 8
local reticle = frame(ui, "Reticle", UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5), PALE, 0.25)
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.ZIndex = 5
local redWash = frame(ui, "Threat flash", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), RED, 1)
redWash.ZIndex = 10
redWash.Active = false
local darkness = frame(ui, "Threat darkness", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), DARK, 1)
darkness.ZIndex = 9
darkness.Active = false

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

-- Two wooden panels leave a narrow slit while hidden. The server actually anchors
-- the character inside the wardrobe; the overlay is only a camera treatment.
local leftPanel = frame(ui, "Left wardrobe door", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0),
	Color3.fromRGB(19, 15, 16), 0.03)
leftPanel.ZIndex = 12
local rightPanel = frame(ui, "Right wardrobe door", UDim2.fromScale(0, 1), UDim2.fromScale(1, 0),
	Color3.fromRGB(19, 15, 16), 0.03)
rightPanel.AnchorPoint = Vector2.new(1, 0)
rightPanel.ZIndex = 12
for _, panel in ipairs({leftPanel, rightPanel}) do
	for j = 1, 4 do
		local strip = frame(panel, "Wood grain", UDim2.new(0, 1, 1, 0),
			UDim2.fromScale(j / 5, 0), GOLD, 0.86)
		strip.ZIndex = 13
	end
end
local hiddenNote = label(ui, "Wardrobe controls", "E — ВЫЙТИ  ·  ШКАФ НЕ ЗАЩИЩАЕТ ОТ СЛЕПОГО",
	UDim2.fromScale(0.46, 0.08), UDim2.fromScale(0.27, 0.84),
	Enum.Font.Garamond, 20, PALE, Enum.TextXAlignment.Center)
hiddenNote.Visible = false
hiddenNote.TextWrapped = true
hiddenNote.ZIndex = 14

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
local modalDetail = label(modal, "End detail", "Свет — спрячься от погони. Слепой — присядь и не прикасайся.",
	UDim2.fromScale(0.78, 0.09), UDim2.fromScale(0.11, 0.51),
	Enum.Font.Gotham, 16, GOLD, Enum.TextXAlignment.Center)
modalDetail.TextWrapped = true
modalDetail.ZIndex = 26
local retryButton = button(modal, "Try again", "ПОПРОБОВАТЬ СНОВА", UDim2.fromOffset(272, 48),
	UDim2.fromScale(0.5, 0.67))
retryButton.AnchorPoint = Vector2.new(0.5, 0)
retryButton.ZIndex = 27

local sprintButton = button(ui, "Mobile sprint", "БЕГ", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -277))
sprintButton.ZIndex = 18
sprintButton.Visible = isTouch
local crouchButton = button(ui, "Mobile crouch", "ПРИСЕСТЬ", UDim2.fromOffset(100, 53),
	UDim2.new(1, -122, 1, -215))
crouchButton.ZIndex = 18
crouchButton.Visible = isTouch
local lightButton = button(ui, "Mobile torch", "СВЕТ", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -153))
lightButton.ZIndex = 18
lightButton.Visible = isTouch
local exitButton = button(ui, "Leave wardrobe", "ВЫЙТИ", UDim2.fromOffset(105, 52),
	UDim2.new(1, -124, 1, -222))
exitButton.ZIndex = 18
exitButton.Visible = false

-- Show the real character and hotel immediately on spawn: no opaque intro
-- hiding the first seconds of ordinary Roblox movement.

if isTouch then
	-- Portrait phones have a separate compact header and large action targets.
	topLine.Size = UDim2.new(1, -28, 0, 1)
	topLine.Position = UDim2.fromOffset(14, 13)
	brand.Size = UDim2.fromOffset(220, 31)
	brand.Position = UDim2.fromOffset(15, 19)
	brand.TextSize = 21
	tagline.Size = UDim2.fromOffset(210, 17)
	tagline.Position = UDim2.fromOffset(16, 51)
	tagline.TextSize = 9
	doorTitle.Size = UDim2.fromOffset(125, 19)
	doorTitle.Position = UDim2.new(1, -142, 0, 20)
	doorTitle.TextSize = 9
	doorLabel.Size = UDim2.fromOffset(130, 35)
	doorLabel.Position = UDim2.new(1, -147, 0, 41)
	doorLabel.TextSize = 24
	progressBase.Size = UDim2.fromOffset(125, 2)
	progressBase.Position = UDim2.new(1, -145, 0, 79)
	floorLabel.Size = UDim2.fromOffset(130, 20)
	floorLabel.Position = UDim2.new(1, -148, 0, 84)
	floorLabel.TextSize = 10
	staminaCaption.Position = UDim2.new(0, 17, 1, -89)
	staminaTrack.Size = UDim2.fromOffset(119, 3)
	staminaTrack.Position = UDim2.new(0, 17, 1, -64)
	help.Size = UDim2.new(1, -20, 0, 22)
	help.Position = UDim2.new(0.5, 0, 1, -32)
	help.Text = "СЛЕВА — ИДТИ    ·    СПРАВА — СМОТРЕТЬ"
	help.TextSize = 9
	flashLabel.Visible = false
	notice.Size = UDim2.fromScale(0.9, 0.12)
	notice.Position = UDim2.fromScale(0.05, 0.66)
	notice.TextSize = 21
	hiddenNote.Text = "ВЫЙТИ — СПРАВА  ·  ШКАФ ОПАСЕН"
	hiddenNote.Size = UDim2.fromScale(0.6, 0.11)
	hiddenNote.Position = UDim2.fromScale(0.2, 0.81)
	hiddenNote.TextSize = 15
end

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
local danger = 0
local warningRoom = -1
local warningKind = nil
local roomLength = Layout.RoomLength
local finalFloor = math.floor(Layout.EntranceY(100) / Layout.StoreyRise) + 1
local displayedFloor = -1
local fright = 0
local elapsed = 0
local noticeId = 0
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
	crouchButton.Text = on and "ВСТАТЬ" or "ПРИСЕСТЬ"
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
	flashLabel.Text = flashlightOn and "F  ·  ФОНАРЬ" or "F  ·  ВКЛЮЧИТЬ"
	flashLabel.TextColor3 = flashlightOn and GOLD or Color3.fromRGB(136, 143, 146)
end
local function showNotice(text, color, duration)
	noticeId = noticeId + 1
	local current = noticeId
	notice.Text = text
	notice.TextColor3 = color or GOLD
	TweenService:Create(notice, TweenInfo.new(0.24), {TextTransparency = 0}):Play()
	task.delay(duration or 3.3, function()
		if current == noticeId then
			TweenService:Create(notice, TweenInfo.new(1.1), {TextTransparency = 1}):Play()
		end
	end)
end
local function setDoor(opened)
	local nextNumber = math.clamp(opened + 1, 1, 100)
	doorLabel.Text = string.format("%03d  /  100", nextNumber)
	TweenService:Create(progressFill, TweenInfo.new(0.7, Enum.EasingStyle.Quad),
		{Size = UDim2.fromScale(opened / 100, 1)}):Play()
end
local function fallbackScareFace(kind)
	local model = Instance.new("Model")
	model.Name = "Last glimpse of " .. tostring(kind)
	local color = kind == "MOTH" and Color3.fromRGB(149, 183, 167)
		or kind == "BLIND" and Color3.fromRGB(195, 194, 177)
		or Color3.fromRGB(114, 105, 97)
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
	local face = oval("Last mask", Vector3.new(2.7, 3.5, 1.45), CFrame.new(0, 2.7, 0), color)
	model.PrimaryPart = face
	for _, side in ipairs({-1, 1}) do
		oval("Hollow eye", Vector3.new(0.7, 0.78, 0.18),
			CFrame.new(side * 0.67, 3.05, -0.7), DARK)
		oval("Hairline shadow", Vector3.new(0.27, 1.2, 0.16),
			CFrame.new(side * 0.7, 2.3, -0.58), RED)
	end
	oval("Open jaw", Vector3.new(0.8, 0.8, 0.2), CFrame.new(0, 1.82, -0.73), DARK)
	return model
end
local function showScare(kind, source)
	scareToken = scareToken + 1
	local token = scareToken
	fright = 1
	reticle.Visible = false
	scare.Visible = true
	scareVeil.BackgroundTransparency = 0.1
	for _, child in ipairs(scareWorld:GetChildren()) do child:Destroy() end
	local monster = source
	if not monster or not monster:IsA("Model") then
		local world = Workspace:FindFirstChild("NocturneWorld")
		local names = {RUSH = "TheRush", BLIND = "TheBlindGuest", MOTH = "ThePaleMoth"}
		monster = world and world:FindFirstChild(names[kind] or "", true)
	end
	local copy = monster and monster:Clone()
	if not copy then copy = fallbackScareFace(kind) end
	copy.Parent = scareWorld
	copy:PivotTo(CFrame.new(0, -0.15, 0))
	scareView.Ambient = kind == "MOTH" and Color3.fromRGB(65, 101, 87)
		or kind == "BLIND" and Color3.fromRGB(95, 109, 99)
		or Color3.fromRGB(124, 53, 49)
	scareCamera.FieldOfView = 52
	scareCamera.CFrame = CFrame.lookAt(Vector3.new(0, 2.75, -9.5), Vector3.new(0, 2.45, 0))
	TweenService:Create(scareCamera, TweenInfo.new(0.43, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{CFrame = CFrame.lookAt(Vector3.new(0, 2.65, -2.3), Vector3.new(0, 2.5, 0))}):Play()
	TweenService:Create(scareVeil, TweenInfo.new(0.17), {BackgroundTransparency = 0.86}):Play()
	task.delay(0.26, function()
		if token ~= scareToken then return end
		scareVeil.BackgroundTransparency = 0.15
		TweenService:Create(scareVeil, TweenInfo.new(0.3), {BackgroundTransparency = 0.93}):Play()
	end)
end
local function showEnd(win)
	if win then
		finished = true
		modalEyebrow.Text = "100 / 100  ·  РАССВЕТ"
		modalEyebrow.TextColor3 = GOLD
		modalTitle.Text = "ВЫХОД"
		modalDetail.Text = "100 / 100 · Все двери пройдены."
		retryButton.Text = "СЫГРАТЬ ЕЩЁ РАЗ"
	else
		dead = true
		setSprint(false)
		modalEyebrow.Text = "ПОРАЖЕНИЕ"
		modalEyebrow.TextColor3 = RED
		modalTitle.Text = "ПРОХОЖДЕНИЕ ПРЕРВАНО"
		modalDetail.Text = "Погоня — шкаф. Слепой — присесть и обойти. Мотылёк — выключить фонарь."
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
		roomLength = c or Layout.RoomLength
		setDoor(a or 0)
		if not dead and not finished then modal.Visible = false end
	elseif event == "Door" then
		setDoor(a)
	elseif event == "Locked" then
		showNotice(string.format("ДВЕРЬ %03d ЗАПЕРТА  ·  КЛЮЧ В ЯЩИКАХ", a), GOLD, 4)
	elseif event == "Key" then
		showNotice(string.format("КЛЮЧ НАЙДЕН  ·  ДВЕРЬ %03d", a), GOLD, 3)
	elseif event == "Hide" then
		hidden = a
		player:SetAttribute("NocturnePeek", hidden)
		setSprint(false)
		crouching = false
		if humanoid then humanoid.CameraOffset = Vector3.new(0, 0, 0) end
		crouchButton.Text = "ПРИСЕСТЬ"
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
			TweenService:Create(leftPanel, TweenInfo.new(0.32), {Size = UDim2.fromScale(0.33, 1)}):Play()
			TweenService:Create(rightPanel, TweenInfo.new(0.32), {Size = UDim2.fromScale(0.33, 1)}):Play()
			hiddenNote.Visible = true
		else
			peekCF = nil
			restoreCamera()
			TweenService:Create(leftPanel, TweenInfo.new(0.27), {Size = UDim2.fromScale(0, 1)}):Play()
			TweenService:Create(rightPanel, TweenInfo.new(0.27), {Size = UDim2.fromScale(0, 1)}):Play()
			hiddenNote.Visible = false
		end
		exitButton.Visible = hidden and isTouch
		sprintButton.Visible = not hidden and isTouch
	elseif event == "Warning" then
		warningKind = a
		warningRoom = b
		local nearby = root and math.abs(root.Position.Z - b * roomLength) < roomLength * 4.1
		if nearby then
			danger = a == "RUSH" and 1 or 0.35
			if a == "RUSH" then
				showNotice("МИГАЕТ СВЕТ  ·  ПОГОНЯ СЗАДИ  ·  СПРЯЧЬСЯ", RED, 4.2)
			elseif a == "BLIND" then
				showNotice("СЛЕПОЙ ВПЕРЕДИ  ·  ПРИСЯДЬ  ·  ОБОЙДИ", PALE, 4.5)
			elseif a == "MOTH" then
				showNotice("МОТЫЛЁК ИЩЕТ СВЕТ  ·  ВЫКЛЮЧИ ФОНАРЬ", GOLD, 4.5)
			end
		end
	elseif event == "Safe" then
		if warningKind == a and warningRoom == b then
			danger = 0
			warningKind = nil
			warningRoom = -1
		end
	elseif event == "Jumpscare" then
		showScare(a, b)
	elseif event == "Death" then
		if scare.Visible then
			dead = true
			setSprint(false)
			local token = scareToken
			task.delay(1.1, function()
				if scareToken ~= token or not dead then return end
				scare.Visible = false
				showEnd(false)
			end)
		else
			showEnd(false)
		end
	elseif event == "Victory" then
		setDoor(100)
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
	danger = 0
	warningKind = nil
	warningRoom = -1
	crouching = false
	humanoid.CameraOffset = Vector3.new(0, 0, 0)
	crouchButton.Text = "ПРИСЕСТЬ"
	crouchButton.Visible = isTouch
	displayedFloor = -1
	modal.Visible = false
	leftPanel.Size = UDim2.fromScale(0, 1)
	rightPanel.Size = UDim2.fromScale(0, 1)
	hiddenNote.Visible = false
	exitButton.Visible = false
	sprintButton.Visible = isTouch
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
	local roomIndex = Layout.RoomIndexAt(root.Position.Z)
	local storey = math.floor(Layout.EntranceY(roomIndex) / Layout.StoreyRise) + 1
	if Layout.IsStair(roomIndex)
		and root.Position.Y > Layout.EntranceY(roomIndex) + Layout.StoreyRise / 2 + 3 then
		storey = storey + 1
	end
	if storey ~= displayedFloor then
		displayedFloor = storey
		floorLabel.Text = string.format("ЭТАЖ %02d  /  %02d", storey, finalFloor)
	end

	if hidden and peekCF then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = peekCF
	elseif camera.CameraType == Enum.CameraType.Scriptable then
		restoreCamera() -- also recovers after death/respawn inside a wardrobe
	end
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = not hidden and not dead and horizontalSpeed > 1.5
		and humanoid.MoveDirection.Magnitude > 0.05
	local running = moving and not crouching and horizontalSpeed > 15
	camera.FieldOfView = camera.FieldOfView + ((hidden and 70 or (running and 79 or 73))
		+ danger * 2 - camera.FieldOfView) * damp(4, dt)
	local origin = head and head.Parent and head.Position or (root.Position + Vector3.new(0, 1.6, 0))
	origin = origin + camera.CFrame.RightVector * 0.45
	torchMount.CFrame = CFrame.lookAt(origin, origin + camera.CFrame.LookVector)
	torch.Enabled = flashlightOn and not hidden and not dead and not finished

	fright = math.max(0, fright - dt * 0.65)
	local pulse = danger > 0 and (0.11 + 0.085 * math.sin(elapsed * 9)) or 0
	redWash.BackgroundTransparency = math.clamp(1 - fright * 0.63 - pulse, 0.03, 1)
	darkness.BackgroundTransparency = math.clamp(1 - danger * 0.13 - (hidden and 0.09 or 0), 0, 1)
end)
