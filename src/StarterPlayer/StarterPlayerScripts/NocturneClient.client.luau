-- NOCTURNE / HUD, hiding treatment, light and close-up scares.
-- The separate NocturnePerspective script owns native first-person and poses
-- the actual Roblox arm, even if this larger HUD script cannot start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
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
local SLOT_IDS = {"FLASHLIGHT", "PILL", "CRUCIFIX", "BANDAGE", "MEDKIT"}
local SLOT_NAMES = {"ФОНАРЬ", "ТАБЛЕТКИ", "КРЕСТ", "ПЛАСТЫРЬ", "АПТЕЧКА"}
local SLOT_GLYPHS = {"✦", "◆", "✝", "▣", "✚"}
local SLOT_COLORS = {GOLD, Color3.fromRGB(151, 191, 165), PALE,
	Color3.fromRGB(221, 179, 154), Color3.fromRGB(184, 203, 213)}
local counts = {FLASHLIGHT = 0, PILL = 0, CRUCIFIX = 0, BANDAGE = 0, MEDKIT = 0}
local selected, charge, flashlightOn, hasFlashlight = 1, 0, false, false
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
local healthTrack = frame(ui, "Health track", UDim2.fromOffset(108, 4),
	UDim2.new(0, 18, 1, -43), RED, 0.76)
healthTrack.ZIndex = 4
local healthFill = frame(healthTrack, "Health", UDim2.fromScale(1, 1),
	UDim2.fromScale(0, 0), RED, 0)
healthFill.ZIndex = 5

-- Five handmade slots sit where Roblox's default Backpack would be. This is
-- not the built-in inventory in disguise: server snapshots own every count.
local equipment = frame(ui, "Equipment bar", UDim2.new(0.92, 0, 0, 90),
	UDim2.new(0.5, 0, 1, -9), Color3.fromRGB(17, 20, 23), 0.16)
equipment.AnchorPoint = Vector2.new(0.5, 1)
equipment.ZIndex = 6
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 10)
barCorner.Parent = equipment
local barEdge = Instance.new("UIStroke")
barEdge.Color = GOLD
barEdge.Transparency = 0.48
barEdge.Thickness = 1
barEdge.Parent = equipment
local inventorySlots = {}
local selectSlot -- bound below, after the server-owned torch control
for index, id in ipairs(SLOT_IDS) do
	local tile = button(equipment, "Slot " .. id, "", UDim2.new(0.177, 0, 0, 74),
		UDim2.new(0.013 + (index - 1) * 0.201, 0, 0, 8))
	tile.ZIndex = 7
	tile.BackgroundColor3 = Color3.fromRGB(28, 32, 35)
	local numeral = label(tile, "Number", tostring(index), UDim2.new(0, 18, 0, 16),
		UDim2.fromOffset(5, 2), Enum.Font.GothamMedium, 11, GOLD)
	numeral.ZIndex = 8
	local glyph = label(tile, "Item symbol", SLOT_GLYPHS[index], UDim2.new(1, 0, 0, 39),
		UDim2.fromOffset(0, 7), Enum.Font.Garamond, 34, SLOT_COLORS[index], Enum.TextXAlignment.Center)
	glyph.ZIndex = 8
	local title = label(tile, "Item name", SLOT_NAMES[index], UDim2.new(1, -4, 0, 15),
		UDim2.new(0, 2, 1, -18), Enum.Font.GothamMedium, 10, PALE, Enum.TextXAlignment.Center)
	title.ZIndex = 8
	local count = label(tile, "Count", "", UDim2.fromOffset(28, 16),
		UDim2.new(1, -31, 0, 2), Enum.Font.GothamBold, 12, PALE, Enum.TextXAlignment.Right)
	count.ZIndex = 8
	local battery = frame(tile, "Charge", UDim2.new(1, -8, 0, 2),
		UDim2.new(0, 4, 1, -2), GOLD, 0.1)
	battery.ZIndex = 9
	battery.Visible = false
	inventorySlots[index] = {tile = tile, count = count, glyph = glyph, charge = battery}
	tile.MouseButton1Click:Connect(function() if selectSlot then selectSlot(index, true) end end)
end
local wallet = label(ui, "Wallet", "◉ 0   ▤ 0   ▰ 0", UDim2.fromOffset(260, 23),
	UDim2.new(0.5, 0, 1, -105), Enum.Font.GothamMedium, 15, GOLD, Enum.TextXAlignment.Center)
wallet.AnchorPoint = Vector2.new(0.5, 1)
wallet.ZIndex = 7
local function redrawEquipment()
	for index, id in ipairs(SLOT_IDS) do
		local slot = inventorySlots[index]
		local amount = counts[id] or 0
		slot.count.Text = amount > 0 and ("×" .. amount) or ""
		slot.glyph.TextTransparency = amount > 0 and 0 or 0.73
		slot.tile.BackgroundColor3 = selected == index and Color3.fromRGB(64, 52, 43)
			or Color3.fromRGB(28, 32, 35)
		slot.charge.Visible = id == "FLASHLIGHT" and amount > 0
		slot.charge.Size = UDim2.new(math.max(0, charge) / 100, -8, 0, 2)
		slot.charge.BackgroundColor3 = charge < 20 and RED or GOLD
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
local useButton = button(ui, "Use selected item", "◆", UDim2.fromOffset(77, 53),
	UDim2.new(1, -99, 1, -339))
useButton.ZIndex = 18
useButton.Visible = isTouch
local exitButton = button(ui, "Leave wardrobe", "↩", UDim2.fromOffset(105, 52),
	UDim2.new(1, -124, 1, -222))
exitButton.ZIndex = 18
exitButton.Visible = false

-- No tutorial captions or button hints at the bottom of the screen.
-- Mobile action buttons are controls, not on-screen survival instructions.

-- Studio cannot reliably read local built-in sound files. Do not create or
-- preload failing Sound instances; threats are intentionally signalled visually.

-- Keep the real character and its collisions untouched. The separate native
-- perspective controller locally reveals only its ordinary key-holding arm.
local peekCF = nil
local root = nil
local humanoid = nil
local head = nil
local hidden = false
local dead = false
local finished = false
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
		remote:FireServer("Select", 1)
		redrawEquipment()
	end
	remote:FireServer("Torch", not flashlightOn) -- server confirms via TorchOn attribute
end
selectSlot = function(index, tapped)
	if hidden or dead or finished or not SLOT_IDS[index] then return end
	if tapped and selected == index and (counts[SLOT_IDS[index]] or 0) > 0 then
		if index == 1 then toggleTorch()
		elseif index ~= 3 then remote:FireServer("Use", SLOT_IDS[index]) end
		return
	end
	selected = index
	remote:FireServer("Select", index)
	redrawEquipment()
end
local function useSelected()
	if hidden or dead or finished then return end
	if selected == 1 then toggleTorch()
	elseif selected ~= 3 and (counts[SLOT_IDS[selected]] or 0) > 0 then
		remote:FireServer("Use", SLOT_IDS[selected])
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
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonR1 then
		useSelected()
	elseif input.KeyCode == Enum.KeyCode.DPadLeft then
		selectSlot((selected - 2) % #SLOT_IDS + 1)
	elseif input.KeyCode == Enum.KeyCode.DPadRight then
		selectSlot(selected % #SLOT_IDS + 1)
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
		selected = a.selected or selected
		charge = a.charge or 0
		hasFlashlight = (counts.FLASHLIGHT or 0) > 0
		wallet.Text = string.format("◉ %d    ▤ %d    ▰ %d",
			a.coins or 0, a.notes or 0, a.gold or 0)
		healthFill.Size = UDim2.fromScale(math.clamp(a.health or 100, 0, 100) / 100, 1)
		lightButton.Visible = isTouch and hasFlashlight and not hidden and not dead and not finished
		redrawEquipment()
	elseif event == "State" then
		if not dead and not finished then modal.Visible = false end
	elseif event == "Spider" then
		if not dead and not finished then showSpider(a) end
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
		useButton.Visible = not hidden and isTouch
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
	useButton.Visible = isTouch
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
	camera.FieldOfView = camera.FieldOfView + ((hidden and (70 - pressure * 9) or (running and 79 or 73))
		- camera.FieldOfView) * damp(4, dt)
	local origin = head and head.Parent and head.Position or (root.Position + Vector3.new(0, 1.6, 0))
	origin = origin + camera.CFrame.RightVector * 0.45
	torchMount.CFrame = CFrame.lookAt(origin, origin + camera.CFrame.LookVector)
	torch.Enabled = flashlightOn and hasFlashlight and charge > 0
		and not hidden and not dead and not finished
end)
