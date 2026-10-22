-- NOCTURNE / HUD, hiding treatment, light and close-up scares.
-- The separate NocturnePerspective script owns native first-person and poses
-- the actual Roblox arm, even if this larger HUD script cannot start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NocturneRemote")
local camera = Workspace.CurrentCamera
local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local GOLD = Color3.fromRGB(216, 174, 113)
local PALE = Color3.fromRGB(218, 228, 221)
local RED = Color3.fromRGB(196, 62, 55)
local DARK = Color3.fromRGB(8, 11, 16)
local SLOT_IDS = {"FLASHLIGHT", "PILL", "CRUCIFIX", "BANDAGE", "MEDKIT"}
local SLOT_NAMES = {"ФОНАРЬ", "ТАБЛЕТКИ", "КРЕСТ", "ПЛАСТЫРЬ", "АПТЕЧКА"}
local SLOT_GLYPHS = {"✦", "◆", "✝", "▣", "✚"}
local SLOT_COLORS = {GOLD, Color3.fromRGB(151, 191, 165), PALE,
	Color3.fromRGB(221, 179, 154), Color3.fromRGB(184, 203, 213)}
local counts = {FLASHLIGHT = 0, PILL = 0, CRUCIFIX = 0, BANDAGE = 0, MEDKIT = 0}
local selected, charge, flashlightOn, hasFlashlight = 1, 0, false, false
local pendingSelection = nil -- do not undo a click with a late inventory snapshot
local pillEffectUntil = 0
local hidden, dead, finished = false, false, false
local function damp(rate, dt) return 1 - math.exp(-rate * dt) end
local function hideRobloxBackpack()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
end
hideRobloxBackpack()

-- No instructions, objectives, danger text or full-screen warning flashes.
-- The only in-world UI is a small stamina line and an aim point; native
-- interaction prompts are icon-only. Mobile action buttons remain usable.
local ui = Instance.new("ScreenGui")
ui.Name = "NocturneHUD"
ui.IgnoreGuiInset = true
ui.ResetOnSpawn = false
ui.DisplayOrder = 50
local playerGui = player:WaitForChild("PlayerGui")
ui.Parent = playerGui

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
edge("Bottom vignette", UDim2.fromScale(1, 0.09), UDim2.fromScale(0, 0.91), 270)
edge("Left vignette", UDim2.fromScale(0.09, 1), UDim2.fromScale(0, 0), 0)
edge("Right vignette", UDim2.fromScale(0.09, 1), UDim2.fromScale(0.91, 0), 180)
local staminaTrack = frame(ui, "Stamina track", UDim2.fromOffset(108, 2),
	isTouch and UDim2.fromOffset(16, 99) or UDim2.new(0, 18, 1, -27), PALE, 0.79)
staminaTrack.ZIndex = 4
local staminaFill = frame(staminaTrack, "Stamina", UDim2.fromScale(1, 1),
	UDim2.fromScale(0, 0), PALE, 0)
staminaFill.ZIndex = 5
local healthTrack = frame(ui, "Health track", UDim2.fromOffset(108, 4),
	isTouch and UDim2.fromOffset(16, 84) or UDim2.new(0, 18, 1, -43), RED, 0.76)
healthTrack.ZIndex = 4
local healthFill = frame(healthTrack, "Health", UDim2.fromScale(1, 1),
	UDim2.fromScale(0, 0), RED, 0)
healthFill.ZIndex = 5

-- A tiny contextual hotbar replaces the full-width Roblox Backpack. Empty
-- slots are not drawn: it first appears after taking an ACTUAL usable item.
local SLOT_SIZE = isTouch and 44 or 42 -- keep mobile hit targets finger-sized
local SLOT_HEIGHT = isTouch and 49 or 47
local SLOT_GAP = 4
local BAR_PADDING = 5
local equipment = frame(ui, "Equipment bar", UDim2.fromOffset(0, SLOT_HEIGHT + BAR_PADDING * 2),
	UDim2.new(0.5, 0, 1, -10), Color3.fromRGB(17, 20, 23), 0.24)
equipment.AnchorPoint = Vector2.new(0.5, 1)
equipment.ZIndex = 6
equipment.Visible = false
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 7)
barCorner.Parent = equipment
local barEdge = Instance.new("UIStroke")
barEdge.Color = GOLD
barEdge.Transparency = 0.58
barEdge.Thickness = 1
barEdge.Parent = equipment
local inventorySlots = {}
local selectSlot -- bound below, after the server-owned torch control
local useButton -- created after the other mobile controls
for index, id in ipairs(SLOT_IDS) do
	local tile = button(equipment, "Slot " .. id, "", UDim2.fromOffset(SLOT_SIZE, SLOT_HEIGHT),
		UDim2.fromOffset(BAR_PADDING, BAR_PADDING))
	tile.ZIndex = 7
	tile.Visible = false
	tile.BackgroundColor3 = Color3.fromRGB(28, 32, 35)
	local numeral = label(tile, "Number", tostring(index), UDim2.fromOffset(13, 12),
		UDim2.fromOffset(3, 1), Enum.Font.GothamMedium, 9, GOLD)
	numeral.ZIndex = 9
	local glyph = label(tile, "Item symbol", SLOT_GLYPHS[index], UDim2.new(1, 0, 0, 29),
		UDim2.fromOffset(0, 3), Enum.Font.Garamond, 26, SLOT_COLORS[index], Enum.TextXAlignment.Center)
	glyph.ZIndex = 8
	local title = label(tile, "Item name", SLOT_NAMES[index], UDim2.new(1, -4, 0, 12),
		UDim2.new(0, 2, 1, -15), Enum.Font.GothamMedium, 9, PALE, Enum.TextXAlignment.Center)
	title.TextScaled = true
	title.ZIndex = 8
	local battery = frame(tile, "Charge", UDim2.fromOffset(SLOT_SIZE - 8, 2),
		UDim2.new(0, 4, 1, -2), GOLD, 0.1)
	battery.ZIndex = 9
	battery.Visible = false
	inventorySlots[index] = {tile = tile, charge = battery,
		stroke = tile:FindFirstChildOfClass("UIStroke")}
	tile.MouseButton1Click:Connect(function() if selectSlot then selectSlot(index, true) end end)
end
local wallet = label(ui, "Wallet", "◉ 0  ▤ 0  ▰ 0", UDim2.fromOffset(174, 17),
	isTouch and UDim2.fromOffset(16, 55) or UDim2.new(0, 18, 1, -53),
	Enum.Font.GothamMedium, 11, GOLD)
-- On phones, keep the wallet away from the centred hotbar and thumbstick.
wallet.AnchorPoint = isTouch and Vector2.new(0, 0) or Vector2.new(0, 1)
wallet.ZIndex = 7
wallet.Visible = false
local function redrawEquipment()
	local owned = 0
	for index, id in ipairs(SLOT_IDS) do
		local slot = inventorySlots[index]
		local hasItem = (counts[id] or 0) > 0
		slot.tile.Visible = hasItem
		if hasItem then
			slot.tile.Position = UDim2.fromOffset(BAR_PADDING + owned * (SLOT_SIZE + SLOT_GAP), BAR_PADDING)
			owned = owned + 1
		end
		slot.tile.BackgroundColor3 = selected == index and Color3.fromRGB(64, 52, 43)
			or Color3.fromRGB(28, 32, 35)
		slot.stroke.Transparency = selected == index and 0.05 or 0.7
		slot.stroke.Color = GOLD
		slot.stroke.Thickness = 1
		slot.charge.Visible = id == "FLASHLIGHT" and hasItem
		slot.charge.Size = UDim2.fromOffset(math.floor((SLOT_SIZE - 8) * math.clamp(charge, 0, 100) / 100), 2)
		slot.charge.BackgroundColor3 = charge < 20 and RED or GOLD
	end
	local width = owned * SLOT_SIZE + math.max(0, owned - 1) * SLOT_GAP + BAR_PADDING * 2
	equipment.Size = UDim2.fromOffset(width, SLOT_HEIGHT + BAR_PADDING * 2)
	equipment.Visible = owned > 0
	if useButton then
		local id = SLOT_IDS[selected]
		useButton.Visible = isTouch and not hidden and not dead and not finished
			and (counts[id] or 0) > 0 and id ~= "FLASHLIGHT"
		useButton.Text = SLOT_GLYPHS[selected] or "◆"
	end
end
redrawEquipment()
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

local spiderView = Instance.new("ViewportFrame")
spiderView.Name = "Jumping spider"
spiderView.Size = UDim2.fromScale(0.46, 0.48)
spiderView.AnchorPoint = Vector2.new(0.5, 0.5)
spiderView.Position = UDim2.fromScale(0.5, 0.58)
spiderView.BackgroundTransparency = 1
spiderView.Ambient = Color3.fromRGB(138, 125, 110)
spiderView.LightColor = PALE
spiderView.ZIndex = 17
spiderView.Visible = false
spiderView.Parent = ui
local spiderWorld = Instance.new("WorldModel")
spiderWorld.Parent = spiderView
local spiderCamera = Instance.new("Camera")
spiderCamera.FieldOfView = 55
spiderCamera.Parent = spiderView
spiderView.CurrentCamera = spiderCamera
local spiderToken = 0
local function showSpider(source)
	spiderToken = spiderToken + 1
	local token = spiderToken
	for _, child in ipairs(spiderWorld:GetChildren()) do child:Destroy() end
	local replica = source and source:IsA("Model") and source:Clone()
	if not replica then
		replica = Instance.new("Model")
		replica.Name = "DrawerSpider"
		local body = Instance.new("Part")
		body.Name = "Hairy abdomen"
		body.Size = Vector3.new(0.6, 0.35, 0.6)
		body.Shape = Enum.PartType.Ball
		body.Color = DARK
		body.Anchored = true
		body.CFrame = CFrame.new()
		body.Parent = replica
		replica.PrimaryPart = body
	end
	replica.Parent = spiderWorld
	replica:PivotTo(CFrame.new())
	spiderView.Visible = true
	spiderView.Size = UDim2.fromScale(0.12, 0.13)
	spiderCamera.CFrame = CFrame.lookAt(Vector3.new(0, 0.15, -5), Vector3.new())
	TweenService:Create(spiderView, TweenInfo.new(0.29, Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out), {Size = UDim2.fromScale(0.67, 0.70)}):Play()
	TweenService:Create(spiderCamera, TweenInfo.new(0.29, Enum.EasingStyle.Quart,
		Enum.EasingDirection.In), {
		CFrame = CFrame.lookAt(Vector3.new(0, 0.15, -0.85), Vector3.new()),
		FieldOfView = 62,
	}):Play()
	task.delay(0.67, function()
		if spiderToken ~= token then return end
		spiderView.Visible = false
		replica:Destroy()
	end)
end

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

-- After lingering in a wardrobe, a local blur and thin interference lines
-- cloud the actual sightline, without covering it or writing a warning.
local shelterBlur = Instance.new("BlurEffect")
shelterBlur.Name = "Wardrobe eyestrain"
shelterBlur.Size = 0
shelterBlur.Parent = Lighting
local shelterColor = Instance.new("ColorCorrectionEffect")
shelterColor.Name = "Wardrobe desaturation"
shelterColor.Saturation = 0
shelterColor.Contrast = 0
shelterColor.Parent = Lighting
local interference = {}
for i = 1, 8 do
	local line = frame(ui, "Sight interference", UDim2.new(1, 0, 0, i % 3 + 1),
		UDim2.fromScale(0, i / 9), Color3.fromRGB(201, 213, 207), 1)
	line.ZIndex = 14
	interference[i] = line
end
local closetPressure, visualPressure = 0, 0

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
lightButton.Visible = false -- there is no starting flashlight
useButton = button(ui, "Use selected item", "◆", UDim2.fromOffset(65, 47),
	UDim2.new(1, -93, 1, -339))
useButton.ZIndex = 18
redrawEquipment() -- starts hidden, including the touch-only item action
local exitButton = button(ui, "Leave wardrobe", "↩", UDim2.fromOffset(105, 52),
	UDim2.new(1, -124, 1, -222))
exitButton.ZIndex = 18
exitButton.Visible = false

-- No tutorial captions or button hints at the bottom of the screen.
-- Mobile action buttons are controls, not on-screen survival instructions.

-- Close arrival is mixed locally so a monster three rooms behind is still
-- LOUD when it actually appears. Files are shipped with Roblox's own character
-- audio; no third-party/private asset permission or download is required.
-- The light-flicker code never plays a sound (only a monster's arrival does).
local function localCue(name, file, volume, pitch)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxasset://sounds/" .. file
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	local echo = Instance.new("EchoSoundEffect")
	echo.Delay = 0.23
	echo.Feedback = 0.26
	echo.WetLevel = -12
	echo.DryLevel = 0
	echo.Parent = sound
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.DecayTime = 2.9
	reverb.Density = 0.72
	reverb.Diffusion = 0.82
	reverb.WetLevel = -8
	reverb.DryLevel = 0
	reverb.Parent = sound
	sound.Parent = SoundService
	return sound
end
local arrivalVoice = localCue("Creature at the threshold", "uuhhh.mp3", 1.65, 0.62)
local arrivalImpact = localCue("Corridor arrival impact", "action_jump_land.mp3", 1.12, 0.64)
local itemClick = localCue("Physical item used", "action_get_up.mp3", 0.31, 1.18)
local itemDenied = localCue("Item cannot be used yet", "action_get_up.mp3", 0.16, 0.67)
local spiderImpact = localCue("Drawer spider strike", "action_jump_land.mp3", 0.88, 1.35)
local roomLength = 44

-- Keep the real character and its collisions untouched. The separate native
-- perspective controller locally reveals its ordinary item-holding arms.
local peekCF = nil
local root = nil
local humanoid = nil
local head = nil
local elapsed = 0
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
	if hidden or dead or finished or not hasFlashlight or charge <= 0 then return end
	if selected ~= 1 then
		selected = 1
		pendingSelection = 1
		redrawEquipment()
	end
	-- One authoritative action equips AND toggles. Sending Select then Torch
	-- separately lost presses during a round trip; the server owns the state.
	remote:FireServer("Use", "FLASHLIGHT")
end
selectSlot = function(index, tapped)
	if hidden or dead or finished or not SLOT_IDS[index]
		or (counts[SLOT_IDS[index]] or 0) == 0 then return end
	if tapped and selected == index then
		remote:FireServer("Use", SLOT_IDS[index])
		return
	end
	selected = index
	pendingSelection = index
	remote:FireServer("Select", index)
	redrawEquipment()
end
local function cycleOwnedSlot(direction)
	for offset = 1, #SLOT_IDS do
		local index = (selected - 1 + direction * offset) % #SLOT_IDS + 1
		if (counts[SLOT_IDS[index]] or 0) > 0 then
			selectSlot(index)
			return
		end
	end
end
local function useSelected()
	if hidden or dead or finished then return end
	local id = SLOT_IDS[selected]
	if id and (counts[id] or 0) > 0 then
		remote:FireServer("Use", id) -- torch, cross and medicines share the same action
	end
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
local function fallbackMothSwarm()
	local swarm = Instance.new("Model")
	swarm.Name = "Last glimpse of MOTH"
	for i = 1, 14 do
		local x = math.sin(i * 2.4) * 1.15
		local y = math.cos(i * 1.8) * 0.85
		local z = math.sin(i * 1.4) * 0.35
		local body = Instance.new("Part")
		body.Name = "Tiny moth thorax"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(0.20, 0.18, 0.3)
		body.Color = Color3.fromRGB(36, 43, 41)
		body.Anchored = true
		body.CanCollide = false
		body.CFrame = CFrame.new(x, y, z)
		body.Parent = swarm
		if i == 1 then swarm.PrimaryPart = body end
		for _, side in ipairs({-1, 1}) do
			local wing = body:Clone()
			wing.Name = "Veined wing"
			wing.Size = Vector3.new(0.45, 0.04, 0.29)
			wing.Color = Color3.fromRGB(185, 200, 181)
			wing.Material = Enum.Material.Glass
			wing.Transparency = 0.3
			wing.CFrame = CFrame.new(x + side * 0.27, y + 0.08, z)
			wing.Parent = swarm
		end
	end
	return swarm
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
		local names = {RUSH = "TheRush", BLIND = "TheBlindGuest", ECHO = "TheEcho",
			MOTH = "ThePaleMoth", FINAL = "TheLastWitness"}
		monster = world and world:FindFirstChild(names[kind] or "", true)
	end
	local copy = monster and monster:Clone()
	if not copy then copy = kind == "MOTH" and fallbackMothSwarm() or fallbackScareFace(kind) end
	copy.Parent = scareWorld
	copy:PivotTo(CFrame.new(0, -0.15, 0))
	local eyeY = kind == "FINAL" and 3.93 or kind == "BLIND" and 3.75
		or kind == "MOTH" and 0 or 3.5
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
useButton.MouseButton1Click:Connect(useSelected)
exitButton.MouseButton1Click:Connect(function() remote:FireServer("Exit") end)

UserInputService.InputBegan:Connect(function(input, processed)
	-- Roblox's default Backpack/PlayerModule may mark number keys or gamepad
	-- actions as processed even after the stock Backpack is hidden. Do not
	-- discard our shortcuts; still respect text fields and the pause menu.
	if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
	if input.KeyCode == Enum.KeyCode.ButtonB then
		if hidden then remote:FireServer("Exit") else setCrouch(not crouching) end
		return
	end
	if hidden and input.KeyCode == Enum.KeyCode.E then
		remote:FireServer("Exit")
		return
	end
	local keyboardOrPad = input.UserInputType == Enum.UserInputType.Keyboard
		or input.UserInputType == Enum.UserInputType.Gamepad1
	if processed and not keyboardOrPad then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- A click in the 3-D scene uses the item in the real hand. Never let
		-- clicking a hotbar/touch GUI button also consume the PREVIOUS slot.
		local point = UserInputService:GetMouseLocation()
		for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(point.X, point.Y)) do
			if object:IsA("GuiButton") then return end
		end
		useSelected()
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
		setSprint(true)
	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
		setCrouch(not crouching)
	elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonY then
		toggleTorch()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonR1
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		useSelected()
	elseif input.KeyCode == Enum.KeyCode.DPadLeft then
		cycleOwnedSlot(-1)
	elseif input.KeyCode == Enum.KeyCode.DPadRight then
		cycleOwnedSlot(1)
	else
		for index, code in ipairs({Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
			Enum.KeyCode.Four, Enum.KeyCode.Five}) do
			if input.KeyCode == code then selectSlot(index); break end
		end
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
player:GetAttributeChangedSignal("Health"):Connect(function()
	healthFill.Size = UDim2.fromScale(math.clamp(player:GetAttribute("Health") or 100, 0, 100) / 100, 1)
end)
player:GetAttributeChangedSignal("TorchOn"):Connect(function()
	flashlightOn = player:GetAttribute("TorchOn") == true
	torch.Enabled = flashlightOn and not hidden and not dead and not finished
end)
player:GetAttributeChangedSignal("HasFlashlight"):Connect(function()
	hasFlashlight = player:GetAttribute("HasFlashlight") == true
	lightButton.Visible = isTouch and hasFlashlight and not hidden and not dead and not finished
end)
player:GetAttributeChangedSignal("TorchCharge"):Connect(function()
	charge = player:GetAttribute("TorchCharge") or 0
	redrawEquipment()
end)
player:GetAttributeChangedSignal("ClosetPressure"):Connect(function()
	closetPressure = math.clamp((player:GetAttribute("ClosetPressure") or 0) / 100, 0, 1)
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
	if event == "Inventory" then
		if type(a) ~= "table" then return end
		counts = a.items or counts
		if pendingSelection and a.selected ~= pendingSelection
			and (counts[SLOT_IDS[pendingSelection]] or 0) > 0 then
			selected = pendingSelection -- older server snapshot; keep the clicked slot
		else
			selected = a.selected or selected
			pendingSelection = nil
		end
		charge = a.charge or 0
		hasFlashlight = (counts.FLASHLIGHT or 0) > 0
		wallet.Text = string.format("◉ %d  ▤ %d  ▰ %d",
			a.coins or 0, a.notes or 0, a.gold or 0)
		wallet.Visible = (a.coins or 0) + (a.notes or 0) + (a.gold or 0) > 0
		healthFill.Size = UDim2.fromScale(math.clamp(a.health or 100, 0, 100) / 100, 1)
		lightButton.Visible = isTouch and hasFlashlight and not hidden and not dead and not finished
		redrawEquipment()
	elseif event == "State" then
		roomLength = type(c) == "number" and c or roomLength
		if not dead and not finished then modal.Visible = false end
	elseif event == "MonsterSpawn" then
		-- A loud cue for living players near the OPENED room, including a
		-- teammate still hiding one door behind it. Not a flicker cue.
		if root and not dead and (not finished or a == "FINAL")
			and type(b) == "number" and math.abs(root.Position.Z - b * roomLength) < roomLength * 3.7 then
			arrivalVoice.PlaybackSpeed = a == "MOTH" and 0.88 or a == "ECHO" and 0.74 or 0.60
			arrivalVoice:Stop()
			arrivalImpact:Stop()
			arrivalVoice:Play()
			arrivalImpact:Play()
		end
	elseif event == "ItemUsed" then
		if not dead then itemClick:Play() end
		if a == "PILL" then pillEffectUntil = os.clock() + 8 end
	elseif event == "ItemDenied" then
		-- Red border and a quiet dry click acknowledge an attempted action,
		-- without adding any on-screen explanation or wasting the consumable.
		if not dead and not finished then
			itemDenied:Play()
			for index, id in ipairs(SLOT_IDS) do
				if id == a and inventorySlots[index].tile.Visible then
					local stroke = inventorySlots[index].stroke
					stroke.Color = RED
					stroke.Thickness = 2
					task.delay(0.45, function()
						stroke.Color = GOLD
						stroke.Thickness = 1
					end)
					break
				end
			end
		end
	elseif event == "Spider" then
		if not dead and not finished then spiderImpact:Play(); showSpider(a) end
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
		redrawEquipment()
		lightButton.Visible = not hidden and isTouch and hasFlashlight
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
		-- Retain compatibility with older saves; this build uses the physical finale.
		showEnd(true)
	end
end)

local function onCharacter(character)
	local newRoot = character:WaitForChild("HumanoidRootPart")
	local newHumanoid = character:WaitForChild("Humanoid")
	local newHead = character:WaitForChild("Head", 8)
	if player.Character ~= character then return end -- late appearance from a previous life
	root, humanoid, head = newRoot, newHumanoid, newHead
	hideRobloxBackpack()
	hidden = false
	peekCF = nil
	dead = false
	finished = false
	pendingSelection = nil
	pillEffectUntil = 0
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
	closetPressure, visualPressure = 0, 0
	shelterBlur.Size = 0
	shelterColor.Saturation = 0
	exitButton.Visible = false
	sprintButton.Visible = isTouch
	redrawEquipment()
	lightButton.Visible = isTouch and hasFlashlight
	reticle.Visible = true
	player:SetAttribute("NocturnePeek", false)
	-- Native first person remains attached to the real Humanoid. The real
	-- avatar is never made transparent by THIS script or moved each frame.
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	restoreCamera()
	torchMount.Parent = camera
	flashlightOn = player:GetAttribute("TorchOn") == true
	hasFlashlight = player:GetAttribute("HasFlashlight") == true
	charge = player:GetAttribute("TorchCharge") or charge
	remote:FireServer("Torch", false) -- no free light on respawn
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
	if hidden then
		visualPressure = visualPressure + (closetPressure - visualPressure) * damp(6, dt)
	else
		visualPressure = math.max(0, visualPressure - dt * 0.72)
	end
	shelterBlur.Size = visualPressure * 13
	shelterColor.Saturation = -visualPressure * 0.63
	shelterColor.Contrast = visualPressure * 0.24
	for index, line in ipairs(interference) do
		line.BackgroundTransparency = 1 - visualPressure * (index % 2 == 0 and 0.13 or 0.21)
		line.Position = UDim2.fromScale(math.sin(elapsed * (11 + index)) * visualPressure * 0.028,
			(index + math.sin(elapsed * (4 + index)) * visualPressure * 0.8) / 9)
	end
	local pressure = 0
	if hidden and peekCF then
		-- The server still controls the threat. Measure its replicated model in
		-- the REAL room; the closer it gets to the wardrobe, the less steadily
		-- the player breathes. The clear centre stays visible at all times.
		local world = Workspace:FindFirstChild("NocturneWorld")
		if world then
			for _, name in ipairs({"TheRush", "TheEcho", "TheBlindGuest", "ThePaleMoth"}) do
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
	local targetFOV = hidden and (70 - pressure * 9) or (running and 79 or 73)
	if not hidden and os.clock() < pillEffectUntil then targetFOV = targetFOV + 5 end
	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * damp(4, dt)
	local held = player.Character and player.Character:FindFirstChild("HeldItem")
	local lens = held and held:GetAttribute("ItemKind") == "FLASHLIGHT"
		and held:FindFirstChild("Torch lens", true)
	local origin = head and head.Parent and head.Position or (root.Position + Vector3.new(0, 1.6, 0))
	if lens and lens:IsA("BasePart") then
		origin = lens.Position -- the beam begins in the REAL hand, not the head
		local otherPlayersBeam = lens:FindFirstChild("Selected torch beam")
		if otherPlayersBeam then otherPlayersBeam.Enabled = false end -- one local beam, aimed by native camera
	else
		origin = origin + camera.CFrame.RightVector * 0.45
	end
	torchMount.CFrame = CFrame.lookAt(origin, origin + camera.CFrame.LookVector)
	torch.Enabled = lens ~= nil and flashlightOn and hasFlashlight and charge > 0
		and not hidden and not dead and not finished
end)
