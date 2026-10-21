-- NOCTURNE / first-person presentation. The server owns doors, hiding and damage.
-- Camera yaw/pitch are smoothed independently of mouse input: this is not Roblox's
-- stock instant-turn first person camera. Works with mouse, touch and a gamepad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

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
local function angleDifference(a, b) return (a - b + math.pi) % (2 * math.pi) - math.pi end
local function yawOf(cf) return math.atan2(-cf.LookVector.X, -cf.LookVector.Z) end

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
local tagline = label(ui, "Tagline", "ОТЕЛЬ, КОТОРЫЙ ПОМНИТ", UDim2.new(0, 370, 0, 22),
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
local help = label(ui, "Controls", isTouch and "ПРОВЕДИ СПРАВА — ОСМОТР   ·   КНОПКИ СПРАВА" or
	"WASD — идти    SHIFT — бег    E — действие    Q/R — наклон    F — фонарь", UDim2.new(0.67, 0, 0, 25),
	UDim2.new(0.5, 0, 1, -49), Enum.Font.GothamMedium, 11, PALE, Enum.TextXAlignment.Center)
help.AnchorPoint = Vector2.new(0.5, 0)
help.TextTransparency = 0.25
help.ZIndex = 4
local flashLabel = label(ui, "Flashlight status", "F  ·  ФОНАРЬ", UDim2.new(0, 175, 0, 24),
	UDim2.new(1, -211, 1, -76), Enum.Font.GothamMedium, 12, GOLD, Enum.TextXAlignment.Right)
flashLabel.ZIndex = 4

local notice = label(ui, "Subtitles", "", UDim2.new(0.84, 0, 0, 74), UDim2.fromScale(0.08, 0.69),
	Enum.Font.Garamond, 27, GOLD, Enum.TextXAlignment.Center)
notice.TextWrapped = true
notice.TextTransparency = 1
notice.ZIndex = 8
local centerDot = frame(ui, "Reticle", UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5), PALE, 0.35)
centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
centerDot.ZIndex = 5

local redWash = frame(ui, "Threat flash", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), RED, 1)
redWash.ZIndex = 10
redWash.Active = false
local darkness = frame(ui, "Threat darkness", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), DARK, 1)
darkness.ZIndex = 9
darkness.Active = false

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
local hiddenNote = label(ui, "Hidden reminder", "ТИШЕ.  ОН ПРОЙДЁТ МИМО.     E — ВЫЙТИ",
	UDim2.fromScale(0.46, 0.08), UDim2.fromScale(0.27, 0.84),
	Enum.Font.Garamond, 20, PALE, Enum.TextXAlignment.Center)
hiddenNote.Visible = false
hiddenNote.ZIndex = 14

local modal = frame(ui, "End card", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), DARK, 0.06)
modal.ZIndex = 25
modal.Visible = false
modal.Active = true
local modalEyebrow = label(modal, "Eyebrow", "ДВЕРЬ ЗАКРЫЛАСЬ", UDim2.fromScale(0.7, 0.055),
	UDim2.fromScale(0.15, 0.29), Enum.Font.GothamMedium, 13, RED, Enum.TextXAlignment.Center)
modalEyebrow.ZIndex = 26
local modalTitle = label(modal, "End title", "ОН НАШЁЛ ТЕБЯ", UDim2.fromScale(0.86, 0.14),
	UDim2.fromScale(0.07, 0.36), Enum.Font.Garamond, 52, PALE, Enum.TextXAlignment.Center)
modalTitle.TextScaled = true
modalTitle.ZIndex = 26
local modalDetail = label(modal, "End detail", "В следующий раз спрячься, когда моргнёт свет.",
	UDim2.fromScale(0.78, 0.09), UDim2.fromScale(0.11, 0.51),
	Enum.Font.Gotham, 16, GOLD, Enum.TextXAlignment.Center)
modalDetail.TextWrapped = true
modalDetail.ZIndex = 26
local retryButton = button(modal, "Try again", "ПОПРОБОВАТЬ СНОВА", UDim2.fromOffset(272, 48),
	UDim2.fromScale(0.5, 0.67))
retryButton.AnchorPoint = Vector2.new(0.5, 0)
retryButton.ZIndex = 27

local sprintButton = button(ui, "Mobile sprint", "БЕГ", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -215))
sprintButton.ZIndex = 18
sprintButton.Visible = isTouch
local lightButton = button(ui, "Mobile torch", "СВЕТ", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -153))
lightButton.ZIndex = 18
lightButton.Visible = isTouch
local exitButton = button(ui, "Leave wardrobe", "ВЫЙТИ", UDim2.fromOffset(105, 52),
	UDim2.new(1, -124, 1, -222))
exitButton.ZIndex = 18
exitButton.Visible = false

local intro = frame(ui, "Opening title card", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), DARK, 0)
intro.ZIndex = 30
local introSmall = label(intro, "Intro caption", "100 ДВЕРЕЙ  ·  ОДНА НОЧЬ", UDim2.fromScale(0.86, 0.07),
	UDim2.fromScale(0.07, 0.39), Enum.Font.GothamMedium, 14, GOLD, Enum.TextXAlignment.Center)
introSmall.ZIndex = 31
local introBig = label(intro, "Intro hotel", "N O C T U R N E", UDim2.fromScale(0.9, 0.1),
	UDim2.fromScale(0.05, 0.46), Enum.Font.Garamond, 49, PALE, Enum.TextXAlignment.Center)
introBig.ZIndex = 31
local introRule = frame(intro, "Intro rule", UDim2.fromScale(0.2, 0.001), UDim2.fromScale(0.4, 0.57), GOLD, 0.25)
introRule.ZIndex = 31

task.delay(1.5, function()
	TweenService:Create(intro, TweenInfo.new(1.8), {BackgroundTransparency = 1}):Play()
	TweenService:Create(introSmall, TweenInfo.new(1.2), {TextTransparency = 1}):Play()
	TweenService:Create(introBig, TweenInfo.new(1.2), {TextTransparency = 1}):Play()
	TweenService:Create(introRule, TweenInfo.new(1.2), {BackgroundTransparency = 1}):Play()
	task.delay(2, function() if intro.Parent then intro:Destroy() end end)
end)

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
	hiddenNote.Text = "ТИШЕ.  ВЫЙТИ — СПРАВА"
	hiddenNote.Size = UDim2.fromScale(0.6, 0.11)
	hiddenNote.Position = UDim2.fromScale(0.2, 0.81)
	hiddenNote.TextSize = 15
end

-- Built-in Roblox sounds: the game also works when a sound is unavailable. No
-- private audio IDs, external textures or DOORS assets are required.
local function sound(name, id, volume)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local knock = sound("Distant knock", "rbxasset://sounds/impact_generic.mp3", 0.26)
local doorSound = sound("Oak door", "rbxasset://sounds/impact_generic.mp3", 0.34)
local heartbeat = sound("Low heartbeat", "rbxasset://sounds/bass.wav", 0.48)
local scareSound = sound("The Murmur", "rbxasset://sounds/uuhhh.mp3", 0.65)
local stepSound = sound("Footsteps", "rbxasset://sounds/impact_generic.mp3", 0.045)
local function play(s, rate)
	s.PlaybackSpeed = rate or 1
	s.TimePosition = 0
	s:Play()
end

local yaw, pitch = math.pi, 0
local targetYaw, targetPitch = math.pi, 0
local peekYaw = math.pi
local peekPosition = nil
local cameraPosition = nil
local root = nil
local humanoid = nil
local hidden = false
local dead = false
local finished = false
local danger = 0
local warningRoom = -1
local roomLength = Layout.RoomLength
local finalFloor = math.floor(Layout.EntranceY(100) / Layout.StoreyRise) + 1
local displayedFloor = -1
local fright = 0
local shake = 0
local stride = 0
local stepTimer = 0
local lastAmbient = 0
local elapsed = 0
local noticeId = 0
local flashlightOn = true
local sprinting = false
local leanAxis = 0
local lean = 0
local cameraRoll = 0
local touchLook = Vector2.new(0, 0)
local stickLook = Vector2.new(0, 0)

local viewModel = Instance.new("Model")
viewModel.Name = "NocturneHandsLocalOnly"
viewModel.Parent = camera
local function viewPart(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Parent = viewModel
	return p
end
local leftSleeve = viewPart("Left coat sleeve", Vector3.new(0.35, 0.8, 0.42), Color3.fromRGB(22, 29, 33), Enum.Material.Fabric)
local rightSleeve = viewPart("Right coat sleeve", Vector3.new(0.35, 0.8, 0.42), Color3.fromRGB(22, 29, 33), Enum.Material.Fabric)
local leftHand = viewPart("Left hand", Vector3.new(0.31, 0.35, 0.33), Color3.fromRGB(115, 91, 79), Enum.Material.SmoothPlastic)
local rightHand = viewPart("Right hand", Vector3.new(0.31, 0.35, 0.33), Color3.fromRGB(115, 91, 79), Enum.Material.SmoothPlastic)
local torchMount = viewPart("Invisible torch light source", Vector3.new(0.2, 0.2, 0.2),
	Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
torchMount.Transparency = 1
local torch = Instance.new("SpotLight")
torch.Name = "Weak hand torch"
torch.Angle = 69
torch.Range = 29
torch.Brightness = 1.35
torch.Color = Color3.fromRGB(255, 221, 179)
torch.Face = Enum.NormalId.Front
torch.Shadows = true
torch.Enabled = flashlightOn
torch.Parent = torchMount

local function setSprint(on)
	if sprinting == on then return end
	sprinting = on
	remote:FireServer("Sprint", on)
end
local function toggleTorch()
	flashlightOn = not flashlightOn
	torch.Enabled = flashlightOn
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
local function showEnd(win)
	if win then
		finished = true
		modalEyebrow.Text = "100 / 100  ·  РАССВЕТ"
		modalEyebrow.TextColor3 = GOLD
		modalTitle.Text = "ТЫ ВЫБРАЛСЯ"
		modalDetail.Text = "Отель остался позади. Кажется."
		retryButton.Text = "СЫГРАТЬ ЕЩЁ РАЗ"
	else
		dead = true
		setSprint(false)
		modalEyebrow.Text = "ДВЕРЬ ЗАКРЫЛАСЬ"
		modalEyebrow.TextColor3 = RED
		modalTitle.Text = "ОН НАШЁЛ ТЕБЯ"
		modalDetail.Text = "Когда моргает свет, спрячься в шкафу. Выходи, когда он пройдёт."
		retryButton.Text = "ПОПРОБОВАТЬ СНОВА"
	end
	modal.Visible = true
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
lightButton.MouseButton1Click:Connect(toggleTorch)
exitButton.MouseButton1Click:Connect(function() remote:FireServer("Exit") end)

UserInputService.InputBegan:Connect(function(input, processed)
	if hidden and (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonB) then
		remote:FireServer("Exit")
		return
	end
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
		setSprint(true)
	elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonY then
		toggleTorch()
	elseif input.KeyCode == Enum.KeyCode.Q then
		leanAxis = -1
	elseif input.KeyCode == Enum.KeyCode.R then
		leanAxis = 1
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
		setSprint(false)
	elseif input.KeyCode == Enum.KeyCode.Q and leanAxis == -1 then
		leanAxis = 0
	elseif input.KeyCode == Enum.KeyCode.R and leanAxis == 1 then
		leanAxis = 0
	end
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.Touch and camera
		and input.Position.X > camera.ViewportSize.X * 0.46 then
		touchLook = touchLook + Vector2.new(input.Delta.X, input.Delta.Y)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stickLook = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

player:GetAttributeChangedSignal("Stamina"):Connect(function()
	local stamina = math.clamp(player:GetAttribute("Stamina") or 100, 0, 100)
	staminaFill.Size = UDim2.fromScale(stamina / 100, 1)
	staminaFill.BackgroundColor3 = stamina < 20 and RED or PALE
end)

remote.OnClientEvent:Connect(function(event, a, b, c)
	if event == "State" then
		roomLength = c or Layout.RoomLength
		setDoor(a or 0)
		if not dead and not finished then modal.Visible = false end
	elseif event == "Door" then
		setDoor(a)
		play(doorSound, 0.69)
		if a == 100 then showNotice("Это последняя дверь.", GOLD, 5) end
	elseif event == "Hide" then
		hidden = a
		setSprint(false)
		if a then
			leanAxis = 0
			peekYaw = yawOf(b)
			targetYaw = peekYaw
			targetPitch = 0
			peekPosition = b.Position
			cameraPosition = peekPosition
			TweenService:Create(leftPanel, TweenInfo.new(0.32), {Size = UDim2.fromScale(0.33, 1)}):Play()
			TweenService:Create(rightPanel, TweenInfo.new(0.32), {Size = UDim2.fromScale(0.33, 1)}):Play()
			hiddenNote.Visible = true
			centerDot.Visible = false
			showNotice("Затаи дыхание.", PALE, 2.4)
		else
			peekPosition = nil
			TweenService:Create(leftPanel, TweenInfo.new(0.27), {Size = UDim2.fromScale(0, 1)}):Play()
			TweenService:Create(rightPanel, TweenInfo.new(0.27), {Size = UDim2.fromScale(0, 1)}):Play()
			hiddenNote.Visible = false
			centerDot.Visible = true
		end
		exitButton.Visible = hidden and isTouch
		sprintButton.Visible = not hidden and isTouch
	elseif event == "Warning" then
		warningRoom = a
		local nearby = root and math.abs(root.Position.Z - a * roomLength) < roomLength * 2.2
		if nearby then
			danger = 1
			shake = 0.2
			play(heartbeat, 0.54)
			showNotice("СВЕТ МОРГАЕТ.  СПРЯЧЬСЯ.", RED, 4)
		end
	elseif event == "Safe" then
		if warningRoom == a then
			danger = 0
			warningRoom = -1
			if not dead then showNotice("Шаги стихли.", PALE, 2.7) end
		end
	elseif event == "Whisper" then
		if not dead then
			showNotice(a, Color3.fromRGB(169, 188, 191), 3.6)
			play(knock, 0.35)
		end
	elseif event == "Jumpscare" then
		fright = 1
		shake = 2
		play(scareSound, 0.67)
		redWash.BackgroundTransparency = 0.05
	elseif event == "Death" then
		showEnd(false)
	elseif event == "Victory" then
		setDoor(100)
		showEnd(true)
	end
end)

local function onCharacter(character)
	root = character:WaitForChild("HumanoidRootPart")
	humanoid = character:WaitForChild("Humanoid")
	hidden = false
	peekPosition = nil
	dead = false
	finished = false
	danger = 0
	warningRoom = -1
	displayedFloor = -1
	modal.Visible = false
	leftPanel.Size = UDim2.fromScale(0, 1)
	rightPanel.Size = UDim2.fromScale(0, 1)
	hiddenNote.Visible = false
	exitButton.Visible = false
	sprintButton.Visible = isTouch
	centerDot.Visible = true
	yaw = math.pi
	targetYaw = math.pi
	pitch = 0
	targetPitch = 0
	cameraPosition = nil
	leanAxis = 0
	lean = 0
	cameraRoll = 0
	camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	setSprint(false)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end
remote:FireServer("Ready")

RunService:BindToRenderStep("NocturneSmoothFirstPerson", Enum.RenderPriority.Camera.Value + 1, function(dt)
	dt = math.min(dt, 0.07)
	elapsed = elapsed + dt
	local current = Workspace.CurrentCamera
	if current ~= camera then
		camera = current
		viewModel.Parent = camera
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
	camera.CameraType = Enum.CameraType.Scriptable
	if not dead and not finished and not UserInputService:GetFocusedTextBox() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

	local mouse = UserInputService:GetMouseDelta()
	if not dead and not finished then
		targetYaw = targetYaw - mouse.X * 0.00205 - touchLook.X * 0.0035
		targetPitch = targetPitch - mouse.Y * 0.00205 - touchLook.Y * 0.0035
		local stick = stickLook.Magnitude > 0.16 and stickLook or Vector2.new(0, 0)
		targetYaw = targetYaw - stick.X * dt * 2.1
		targetPitch = targetPitch + stick.Y * dt * 1.7
	end
	touchLook = Vector2.new(0, 0)
	if hidden then
		targetYaw = peekYaw + math.clamp(angleDifference(targetYaw, peekYaw), -0.19, 0.19)
		targetPitch = math.clamp(targetPitch, -0.17, 0.16)
	else
		targetPitch = math.clamp(targetPitch, -1.34, 1.34)
	end
	-- Response ≈ 70 ms: cinematic inertia without excessive mouse latency.
	yaw = yaw + angleDifference(targetYaw, yaw) * damp(14.5, dt)
	pitch = pitch + (targetPitch - pitch) * damp(13.5, dt)

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = not hidden and not dead and horizontalSpeed > 1.5 and humanoid.MoveDirection.Magnitude > 0.05
	local moveAmount = moving and math.clamp(horizontalSpeed / 15, 0, 1.25) or 0
	local running = moving and horizontalSpeed > 15
	stride = stride + dt * (running and 12.5 or 9.4) * moveAmount
	local bob = math.sin(stride * 2) * 0.042 * moveAmount
	local sidewaysBob = math.cos(stride) * 0.033 * moveAmount
	local breath = math.sin(elapsed * (danger > 0 and 3.7 or 1.65)) * (hidden and 0.017 or 0.012)
	lean = lean + ((hidden and 0 or leanAxis) - lean) * damp(8, dt)
	local targetPosition
	if hidden then
		targetPosition = peekPosition or (root.Position + Vector3.new(0, 2, 0))
	else
		targetPosition = root.Position + Vector3.new(sidewaysBob, 1.58 + bob + breath, 0)
			+ camera.CFrame.RightVector * lean * 0.22
	end
	if not cameraPosition or (targetPosition - cameraPosition).Magnitude > 9 then
		cameraPosition = targetPosition
	else
		cameraPosition = cameraPosition:Lerp(targetPosition, damp(hidden and 22 or 17, dt))
	end
	-- A little roll when turning or strafing, plus a soft recovery after scares.
	local strafe = humanoid.MoveDirection:Dot(camera.CFrame.RightVector)
	local rollTarget = math.clamp(-mouse.X * 0.00052, -0.035, 0.035) - strafe * 0.024
		+ lean * 0.085 + math.sin(stride) * 0.007 * moveAmount
	cameraRoll = cameraRoll + (rollTarget - cameraRoll) * damp(10, dt)
	shake = math.max(0, shake - dt * 1.65)
	local jitter = shake * math.sin(elapsed * 49) * 0.019
	local targetCF = CFrame.new(cameraPosition + Vector3.new(0, jitter, 0))
		* CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch + jitter * 0.24, 0, cameraRoll + jitter)
	camera.CFrame = targetCF
	camera.FieldOfView = camera.FieldOfView + ((hidden and 66 or (running and 83 or 76)) + danger * 2
		- camera.FieldOfView) * damp(4, dt)
	if not hidden and not dead and humanoid.Health > 0 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	end
	-- Keep the local avatar invisible; the lightweight coat/hands are camera-only.
	for _, piece in ipairs(player.Character and player.Character:GetDescendants() or {}) do
		if piece:IsA("BasePart") then piece.LocalTransparencyModifier = 1 end
	end
	local armSwing = math.sin(stride) * 0.045 * moveAmount
	local visible = not hidden and not dead and not finished
	for _, part in ipairs({leftSleeve, rightSleeve, leftHand, rightHand}) do
		part.Transparency = visible and 0 or 1
	end
	leftSleeve.CFrame = targetCF * CFrame.new(-0.83, -0.83 + armSwing, -1.15)
		* CFrame.Angles(math.rad(-23), 0, math.rad(-16))
	rightSleeve.CFrame = targetCF * CFrame.new(0.83, -0.83 - armSwing, -1.15)
		* CFrame.Angles(math.rad(-23), 0, math.rad(16))
	leftHand.CFrame = targetCF * CFrame.new(-0.76, -0.49 + armSwing, -1.43)
	rightHand.CFrame = targetCF * CFrame.new(0.76, -0.49 - armSwing, -1.43)
	torchMount.CFrame = targetCF * CFrame.new(0.45, -0.29, -0.8)
	torch.Enabled = flashlightOn and visible and not (danger > 0 and math.sin(elapsed * 42) > 0.92)

	fright = math.max(0, fright - dt * 0.65)
	local pulse = danger > 0 and (0.11 + 0.085 * math.sin(elapsed * 9)) or 0
	redWash.BackgroundTransparency = math.clamp(1 - fright * 0.63 - pulse, 0.03, 1)
	darkness.BackgroundTransparency = math.clamp(1 - danger * 0.13 - (hidden and 0.09 or 0), 0, 1)
	if danger > 0 and not dead and elapsed - lastAmbient > 1.1 then
		lastAmbient = elapsed
		play(heartbeat, 0.49 + 0.04 * math.sin(elapsed))
	elseif danger == 0 and not dead and elapsed - lastAmbient > 22 then
		lastAmbient = elapsed
		play(knock, 0.25 + 0.08 * math.sin(elapsed))
	end
	if moving then
		stepTimer = stepTimer + dt
		if stepTimer > (running and 0.37 or 0.55) then
			stepTimer = 0
			play(stepSound, running and 1.13 or 0.88)
		end
	else
		stepTimer = 0
	end
end)
