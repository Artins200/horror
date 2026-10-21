-- NOCTURNE / a self-contained, original, 100-door horror game.
-- Everything in NocturneWorld is built on the server. There are no toolbox models
-- or third-party asset IDs, and opening a door never trusts a number sent by a client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Layout = require(ReplicatedStorage:WaitForChild("NocturneLayout"))

local CONFIG = {
	Doors = 100,
	Ahead = 2,
	KeepBehind = 8,
	WalkSpeed = 12,
	SprintSpeed = 19,
	CrouchSpeed = 7,
	SprintDrain = 19,
	StaminaRegen = 13,
	RushSpeed = 70,
	RushWarningSeconds = 3.2,
	RushMaximumSeconds = 18,
	BlindLifetime = 14,
	MothLifetime = 12,
	-- Set to an integer for a repeatable layout, or leave nil for a new run.
	Seed = nil,
}

local C = {
	plaster = Color3.fromRGB(43, 52, 54),
	plasterAlt = Color3.fromRGB(51, 48, 50),
	wood = Color3.fromRGB(42, 30, 29),
	woodLight = Color3.fromRGB(72, 51, 40),
	woodDark = Color3.fromRGB(27, 22, 24),
	brass = Color3.fromRGB(155, 115, 65),
	brassDark = Color3.fromRGB(83, 66, 49),
	carpet = Color3.fromRGB(70, 25, 36),
	marble = Color3.fromRGB(72, 77, 77),
	lamp = Color3.fromRGB(255, 193, 108),
	shadow = Color3.fromRGB(9, 10, 15),
}
local L = Layout.RoomLength
local W = Layout.RoomWidth
local H = Layout.RoomHeight

local previousRemote = ReplicatedStorage:FindFirstChild("NocturneRemote")
if previousRemote then previousRemote:Destroy() end
local remote = Instance.new("RemoteEvent")
remote.Name = "NocturneRemote"
remote.Parent = ReplicatedStorage

local preview = Workspace:FindFirstChild("StudioPreview")
if preview then preview:Destroy() end
local previewStair = Workspace:FindFirstChild("PreviewEnclosedStair")
if previewStair then previewStair:Destroy() end
local previewSpawn = Workspace:FindFirstChild("PreviewSpawn")
if previewSpawn then previewSpawn:Destroy() end

local session = 0
local state = {
	world = nil,
	rooms = {},
	opened = 0,
	seed = 0,
	hidden = {},
	players = {},
	rush = nil,
	blind = nil,
	moth = nil,
	spawn = nil,
	backSeal = nil,
}

local function newPart(parent, name, size, cf, color, material, transparency, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.CastShadow = p.Transparency < 0.8
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function block(parent, name, sx, sy, sz, x, y, z, color, material)
	return newPart(parent, name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, material)
end

local function roomBlock(room, name, sx, sy, sz, x, relativeY, z, color, material)
	return block(room.model, name, sx, sy, sz, x, room.entryY + relativeY, z, color, material)
end

local function railBetween(parent, name, a, b, radius, color)
	local midpoint = (a + b) / 2
	local direction = b - a
	local part = newPart(parent, name, Vector3.new(direction.Magnitude, radius * 2, radius * 2),
		CFrame.lookAt(midpoint, b) * CFrame.Angles(0, math.pi / 2, 0), color, Enum.Material.Metal, 0, false)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function addLight(parent, position, room, brightness, color)
	local fixture = newPart(parent, "Oxidised brass sconce", Vector3.new(1.2, 0.32, 1.2),
		CFrame.new(position), C.brassDark, Enum.Material.Metal)
	local bulb = newPart(parent, "Warm filament", Vector3.new(0.48, 0.42, 0.48),
		CFrame.new(position + Vector3.new(0, -0.3, 0)), color or C.lamp, Enum.Material.Neon, 0, false)
	bulb.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = color or C.lamp
	light.Brightness = brightness or 1.6
	light.Range = 21
	-- One shadow-casting sconce per room keeps mobile lighting affordable.
	light.Shadows = #room.lamps == 0
	light.Parent = bulb
	table.insert(room.lamps, {light = light, bulb = bulb, brightness = light.Brightness})
	return fixture
end

local function inscription(parent, part, text, small)
	local face = Instance.new("SurfaceGui")
	face.Name = "Inscription"
	face.Face = Enum.NormalId.Front
	face.CanvasSize = Vector2.new(512, 512)
	face.LightInfluence = 0.18
	face.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Letters"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = C.brass
	label.TextStrokeColor3 = C.woodDark
	label.TextStrokeTransparency = 0.6
	label.Text = text
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.Parent = face
	if small then
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.16, 0)
		pad.PaddingRight = UDim.new(0.16, 0)
		pad.Parent = label
	end
end

local function hingeDoor(parent, doorNumber, z, floorY)
	local assembly = Instance.new("Model")
	assembly.Name = string.format("Door_%03d", doorNumber)
	assembly.Parent = parent
	local leaf = block(assembly, "Solid oak door", 6.6, 10.2, 0.42,
		0, floorY + 5.1, z, C.woodLight, Enum.Material.WoodPlanks)
	for _, x in ipairs({-1.7, 1.7}) do
		block(assembly, "Raised door panel", 2.7, 7.1, 0.11, x, floorY + 4.5, z - 0.28,
			C.wood, Enum.Material.Wood)
		block(assembly, "Carved panel inset", 2.38, 6.7, 0.12, x, floorY + 4.5, z - 0.36,
			C.woodLight, Enum.Material.Wood)
	end
	block(assembly, "Brass door kickplate", 6.2, 0.55, 0.08, 0, floorY + 0.56, z - 0.27,
		C.brassDark, Enum.Material.Metal)
	local plate = block(assembly, "Number plaque", 2.35, 1.65, 0.09, 0, floorY + 8.25, z - 0.35,
		C.woodDark, Enum.Material.Metal)
	inscription(assembly, plate, string.format("%03d", doorNumber), true)
	local knob = newPart(assembly, "Door handle", Vector3.new(0.43, 0.43, 0.43),
		CFrame.new(2.58, floorY + 4.5, z - 0.51), C.brass, Enum.Material.Metal)
	knob.Shape = Enum.PartType.Ball
	block(assembly, "Keyhole escutcheon", 0.48, 0.88, 0.08,
		2.58, floorY + 3.54, z - 0.48, C.brassDark, Enum.Material.Metal)
	block(assembly, "Cut keyhole", 0.1, 0.3, 0.09,
		2.58, floorY + 3.53, z - 0.54, C.shadow, Enum.Material.Metal)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenDoor"
	prompt.ActionText = "Открыть"
	prompt.ObjectText = string.format("Дверь %03d", doorNumber)
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = leaf
	-- The model pivot is the left hinge. All the carved details swing with the door.
	local hinge = CFrame.new(-3.3, floorY, z)
	assembly.WorldPivot = hinge
	return assembly, leaf, prompt, hinge
end

local function tweenPivot(model, from, to, duration, finished)
	local value = Instance.new("CFrameValue")
	value.Value = from
	local connection = value.Changed:Connect(function(cf)
		if model.Parent then model:PivotTo(cf) end
	end)
	local tween = TweenService:Create(value,
		TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Value = to})
	tween.Completed:Connect(function()
		connection:Disconnect()
		value:Destroy()
		if finished then finished() end
	end)
	tween:Play()
end

local function setModelCollision(model, enabled)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.CanCollide = enabled end
	end
end

local function swingDoor(room, opening)
	if room.busy or not room.door.Parent then return end
	room.busy = true
	room.prompt.Enabled = false
	setModelCollision(room.door, false)
	local from = room.hinge * CFrame.Angles(0, room.open and -math.rad(105) or 0, 0)
	local to = room.hinge * CFrame.Angles(0, opening and -math.rad(105) or 0, 0)
	tweenPivot(room.door, from, to, 0.82, function()
		room.open = opening
		room.busy = false
		if room.door.Parent then
			setModelCollision(room.door, true)
			room.prompt.ActionText = opening and "Закрыть" or "Открыть"
			room.prompt.Enabled = true
		end
	end)
end

local function playerRoot(player)
	local character = player.Character
	if not character then return nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return nil, nil end
	return root, humanoid
end

-- The two leaves are real hinged models. An open wardrobe is only a usable
-- hiding place after its doors have finished swinging; no static fake slats.
local function swingCloset(closet, opening)
	if closet.epoch ~= session or not closet.model.Parent then return end
	closet.motion = (closet.motion or 0) + 1
	local motion = closet.motion
	closet.prompt.Enabled = false
	closet.closePrompt.Enabled = false
	closet.barrier.CanCollide = false
	for _, leaf in ipairs(closet.leaves) do
		setModelCollision(leaf.model, false)
	end
	local pending = #closet.leaves
	for _, leaf in ipairs(closet.leaves) do
		local angle = -leaf.side * math.rad(94)
		local from = leaf.hinge * CFrame.Angles(0, closet.open and angle or 0, 0)
		local to = leaf.hinge * CFrame.Angles(0, opening and angle or 0, 0)
		tweenPivot(leaf.model, from, to, 0.46, function()
			pending = pending - 1
			if pending ~= 0 or closet.motion ~= motion or not closet.model.Parent then return end
			closet.open = opening
			closet.barrier.CanCollide = not opening
			for _, part in ipairs(closet.leaves) do setModelCollision(part.model, not opening) end
			closet.prompt.ActionText = opening and "Спрятаться" or "Открыть шкаф"
			closet.prompt.Enabled = not closet.occupant
			closet.closePrompt.Enabled = opening and not closet.occupant
		end)
	end
end

local function leaveCloset(player, teleport)
	local hiding = state.hidden[player]
	if not hiding then return end
	state.hidden[player] = nil
	local closet = hiding.closet
	if closet.occupant == player then closet.occupant = nil end
	if teleport and closet.model.Parent then
		swingCloset(closet, true)
		task.delay(1.4, function()
			if closet.epoch == session and not closet.occupant and closet.model.Parent then
				swingCloset(closet, false)
			end
		end)
	elseif closet.model.Parent then
		closet.prompt.Enabled = true
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if root then
		root.Anchored = false
		if teleport and hum and hum.Health > 0 then root.CFrame = closet.exitCF end
	end
	if hum then
		hum.WalkSpeed = CONFIG.WalkSpeed
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.AutoRotate = false
	end
	player:SetAttribute("Hidden", false)
	remote:FireClient(player, "Hide", false)
end

local function enterCloset(player, closet)
	if closet.occupant or state.hidden[player] or closet.epoch ~= session or not state.players[player] then return end
	local root, hum = playerRoot(player)
	if not root or (root.Position - closet.front).Magnitude > 11 then return end
	if player:GetAttribute("Finished") then return end
	if not closet.open then
		swingCloset(closet, true)
		return
	end
	closet.occupant = player
	closet.inspected = false
	closet.prompt.Enabled = false
	closet.closePrompt.Enabled = false
	state.hidden[player] = {closet = closet}
	state.players[player].sprinting = false
	state.players[player].crouching = false
	player:SetAttribute("Crouching", false)
	root.CFrame = closet.rootCF
	root.Anchored = true
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	player:SetAttribute("Hidden", true)
	swingCloset(closet, false)
	remote:FireClient(player, "Hide", true, closet.cameraCF)
end

local function makeCloset(room, side, z, serial, floorY, passageHalfWidth)
	-- Local -Z faces the playable passage. Both landings and corridors place the
	-- whole shell inside a wall; its exit always points back to the clear centre.
	local cf = CFrame.new(side * (passageHalfWidth - 2.45), floorY, z)
		* CFrame.Angles(0, side * math.pi / 2, 0)
	local model = Instance.new("Model")
	model.Name = "Wardrobe_" .. serial
	model.Parent = room.model
	local function panel(name, size, localCF, color, material, alpha, collide)
		return newPart(model, name, size, cf * localCF, color, material, alpha, collide)
	end
	panel("Wardrobe back", Vector3.new(3.8, 8.5, 0.24), CFrame.new(0, 4.25, 1.4), C.woodDark, Enum.Material.Wood)
	for _, x in ipairs({-1.83, 1.83}) do
		panel("Wardrobe side", Vector3.new(0.2, 8.5, 2.9), CFrame.new(x, 4.25, 0), C.wood, Enum.Material.Wood)
		panel("Door frame", Vector3.new(0.23, 8.6, 0.34), CFrame.new(x, 4.25, -1.48), C.brassDark, Enum.Material.Metal)
	end
	panel("Wardrobe roof", Vector3.new(3.9, 0.24, 3.05), CFrame.new(0, 8.52, 0), C.woodDark, Enum.Material.Wood)
	panel("Wardrobe floor", Vector3.new(3.6, 0.18, 2.8), CFrame.new(0, 0.1, 0), C.wood, Enum.Material.Wood)
	local barrier = panel("Closed wardrobe collision", Vector3.new(3.3, 8.1, 0.1),
		CFrame.new(0, 4.1, -1.48), C.woodDark, Enum.Material.Wood, 1, true)
	local leaves, handles = {}, {}
	for _, leafSide in ipairs({-1, 1}) do
		local leaf = Instance.new("Model")
		leaf.Name = leafSide == -1 and "Left hinged leaf" or "Right hinged leaf"
		leaf.Parent = model
		local centreX = leafSide * 0.87
		newPart(leaf, "Oak wardrobe leaf", Vector3.new(1.74, 8.05, 0.18),
			cf * CFrame.new(centreX, 4.14, -1.52), C.wood, Enum.Material.Wood)
		for j = 1, 8 do
			newPart(leaf, "Inset wooden louvre", Vector3.new(1.48, 0.31, 0.12),
				cf * CFrame.new(centreX, 0.79 + j * 0.78, -1.66)
					* CFrame.Angles(math.rad(-16), 0, 0), C.woodLight, Enum.Material.Wood)
		end
		for _, edge in ipairs({0.63, 7.65}) do
			newPart(leaf, "Carved leaf rail", Vector3.new(1.76, 0.26, 0.18),
				cf * CFrame.new(centreX, edge, -1.68), C.brassDark, Enum.Material.Wood)
		end
		handles[leafSide] = newPart(leaf, "Wardrobe handle", Vector3.new(0.27, 0.73, 0.2),
			cf * CFrame.new(leafSide * 0.23, 4.2, -1.77), C.brass, Enum.Material.Metal, 0, false)
		local hinge = cf * CFrame.new(leafSide * 1.72, 0, -1.52)
		leaf.WorldPivot = hinge
		table.insert(leaves, {model = leaf, hinge = hinge, side = leafSide})
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HideInside"
	prompt.ActionText = "Открыть шкаф"
	prompt.ObjectText = "Шкаф"
	prompt.HoldDuration = 0.22
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = handles[-1]
	local closePrompt = Instance.new("ProximityPrompt")
	closePrompt.Name = "CloseWardrobe"
	closePrompt.ActionText = "Закрыть шкаф"
	closePrompt.ObjectText = "Шкаф"
	closePrompt.HoldDuration = 0.22
	closePrompt.MaxActivationDistance = 8
	closePrompt.RequiresLineOfSight = false
	closePrompt.KeyboardKeyCode = Enum.KeyCode.E
	closePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	closePrompt.Enabled = false
	closePrompt.Parent = handles[1]
	local closet = {
		model = model, barrier = barrier, leaves = leaves, prompt = prompt, closePrompt = closePrompt,
		front = (cf * CFrame.new(0, 4, -1.6)).Position,
		rootCF = cf * CFrame.new(0, 3, 0.1),
		cameraCF = cf * CFrame.new(0, 5.0, -0.1),
		exitCF = cf * CFrame.new(0, 3, -3.45),
		epoch = session,
		occupant = nil, open = false,
	}
	prompt.Triggered:Connect(function(player) enterCloset(player, closet) end)
	closePrompt.Triggered:Connect(function(player)
		local root = playerRoot(player)
		if closet.open and not closet.occupant and root
			and (root.Position - closet.front).Magnitude < 11 then swingCloset(closet, false) end
	end)
	table.insert(room.closets, closet)
end

-- The key is in exactly one of three physical drawers in the SAME room as its
-- locked door. Prompts and distance checks live on the server; finding a key
-- unlocks that numbered door for everyone in the current run.
local function makeDresser(room, rng)
	local side = room.kind == "TURN" and Layout.TurnSide(room.index) or 1
	local dresserZ = room.kind == "TURN" and 22 or (room.kind == "CONSERVATORY" and 14.5 or 17)
	local z = room.index * L + dresserZ
	local cf = CFrame.new(side * 10.9, room.entryY, z) * CFrame.Angles(0, side * math.pi / 2, 0)
	local dresser = Instance.new("Model")
	dresser.Name = "Three-drawer dresser"
	dresser.Parent = room.model
	local function bodyPart(name, size, offset, color)
		return newPart(dresser, name, size, cf * offset, color, Enum.Material.Wood)
	end
	bodyPart("Solid dresser back", Vector3.new(4.6, 4.05, 0.24),
		CFrame.new(0, 2.03, 1.27), C.woodDark)
	for _, x in ipairs({-2.22, 2.22}) do
		bodyPart("Dresser end panel", Vector3.new(0.22, 4.05, 2.55),
			CFrame.new(x, 2.03, 0), C.wood)
	end
	bodyPart("Marble writing top", Vector3.new(4.9, 0.2, 2.9),
		CFrame.new(0, 4.12, 0), C.marble)
	for _, railY in ipairs({0.43, 1.48, 2.54, 3.6}) do
		bodyPart("Drawer aperture rail", Vector3.new(4.3, 0.13, 0.24),
			CFrame.new(0, railY, -1.35), C.woodDark)
	end
	local keySlot = room.locked and rng:NextInteger(1, 3) or 0
	for slot = 1, 3 do
		local drawerY = 0.94 + (slot - 1) * 1.06
		local drawer = Instance.new("Model")
		drawer.Name = "Drawer_" .. slot
		drawer.Parent = dresser
		local pivot = cf * CFrame.new(0, drawerY, -1.36)
		local function drawerPart(name, size, offset, color, material)
			return newPart(drawer, name, size, cf * offset, color, material or Enum.Material.Wood)
		end
		drawerPart("Sliding drawer front", Vector3.new(4.13, 0.89, 0.18),
			CFrame.new(0, drawerY, -1.42), C.woodLight)
		drawerPart("Drawer bottom", Vector3.new(3.8, 0.13, 2.05),
			CFrame.new(0, drawerY - 0.37, -0.22), C.woodDark)
		for _, x in ipairs({-1.89, 1.89}) do
			drawerPart("Drawer inner side", Vector3.new(0.13, 0.6, 2.05),
				CFrame.new(x, drawerY - 0.08, -0.22), C.wood)
		end
		local handle = drawerPart("Brass drawer pull", Vector3.new(0.82, 0.22, 0.18),
			CFrame.new(0, drawerY, -1.58), C.brass, Enum.Material.Metal)
		drawer.WorldPivot = pivot
		local openPrompt = Instance.new("ProximityPrompt")
		openPrompt.Name = "OpenDrawer"
		openPrompt.ActionText = "Выдвинуть"
		openPrompt.ObjectText = "Ящик " .. slot
		openPrompt.HoldDuration = 0.27
		openPrompt.MaxActivationDistance = 8
		openPrompt.RequiresLineOfSight = false
		openPrompt.KeyboardKeyCode = Enum.KeyCode.E
		openPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		openPrompt.Parent = handle
		local key, takePrompt
		if slot == keySlot then
			key = Instance.new("Model")
			key.Name = "Key_for_door_" .. (room.index + 1)
			key.Parent = drawer
			local bow = newPart(key, "Brass key bow", Vector3.new(0.56, 0.15, 0.56),
				cf * CFrame.new(0, drawerY - 0.22, -0.68), C.brass, Enum.Material.Metal, 1, false)
			bow.Shape = Enum.PartType.Cylinder
			newPart(key, "Key stem", Vector3.new(0.16, 0.15, 0.85),
				cf * CFrame.new(0, drawerY - 0.22, -0.22), C.brass, Enum.Material.Metal, 1, false)
			newPart(key, "Key teeth", Vector3.new(0.34, 0.15, 0.14),
				cf * CFrame.new(0.1, drawerY - 0.22, 0.18), C.brass, Enum.Material.Metal, 1, false)
			takePrompt = Instance.new("ProximityPrompt")
			takePrompt.Name = "TakeKey"
			takePrompt.ActionText = "Взять ключ"
			takePrompt.ObjectText = string.format("Дверь %03d", room.index + 1)
			takePrompt.HoldDuration = 0.2
			takePrompt.MaxActivationDistance = 8
			takePrompt.RequiresLineOfSight = false
			takePrompt.KeyboardKeyCode = Enum.KeyCode.E
			takePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			takePrompt.Enabled = false
			takePrompt.Parent = bow
			takePrompt.Triggered:Connect(function(player)
				if room.epoch ~= session or room.unlocked or not takePrompt.Enabled then return end
				local root = playerRoot(player)
				if not root or state.hidden[player]
					or (root.Position - bow.Position).Magnitude > 10 then return end
				room.unlocked = true
				room.model:SetAttribute("KeyFound", true)
				room.model:SetAttribute("Locked", false)
				room.prompt.ActionText = "Открыть"
				key:Destroy()
				remote:FireAllClients("Key", room.index + 1)
			end)
		end
		local opened = false
		openPrompt.Triggered:Connect(function(player)
			if opened or room.epoch ~= session or not openPrompt.Enabled then return end
			local root = playerRoot(player)
			if not root or state.hidden[player]
				or (root.Position - handle.Position).Magnitude > 10 then return end
			opened = true
			openPrompt.Enabled = false
			tweenPivot(drawer, pivot, pivot * CFrame.new(0, 0, -1.25), 0.5, function()
				if key and key.Parent and room.epoch == session then
					for _, part in ipairs(key:GetDescendants()) do
						if part:IsA("BasePart") then part.Transparency = 0 end
					end
					takePrompt.Enabled = true
				end
			end)
		end)
	end
end

local function makePainting(room, side, z, accent)
	local x = side * (W / 2 - 0.8)
	roomBlock(room, "Tarnished picture frame", 0.24, 5.1, 5.3, x, 8.4, z,
		C.brassDark, Enum.Material.Metal)
	roomBlock(room, "Oil painting", 0.28, 4.45, 4.65, x - side * 0.15, 8.4, z,
		accent, Enum.Material.SmoothPlastic)
	roomBlock(room, "Painting horizon", 0.29, 0.18, 3.6, x - side * 0.3, 7.3, z,
		C.woodDark, Enum.Material.SmoothPlastic)
end

local function furnish(room, rng)
	local kind = room.kind
	local z = room.index * L
	if kind == "LIBRARY" then
		for _, side in ipairs({-1, 1}) do
			for _, dz in ipairs({9, 32}) do
				local x = side * 11.7
				roomBlock(room, "Archive shelving", 2.2, 9.2, 7.0, x, 4.6, z + dz,
					C.woodDark, Enum.Material.Wood)
				for shelf = 1, 4 do
					roomBlock(room, "Shelf edge", 2.42, 0.25, 7.1, x, shelf * 1.8, z + dz,
						C.brassDark, Enum.Material.Wood)
					for book = 1, 5 do
						local offset = (book - 3) * 1.12
						roomBlock(room, "Old book", 0.42, 1.2 + rng:NextNumber(0, 0.35), 0.8,
							x - side * 1.25, shelf * 1.8 + 0.7, z + dz + offset,
							Color3.fromRGB(rng:NextInteger(45, 90), rng:NextInteger(28, 55), rng:NextInteger(27, 53)),
							Enum.Material.Fabric)
					end
				end
			end
		end
	elseif kind == "GALLERY" then
		for _, side in ipairs({-1, 1}) do
			for _, dz in ipairs({9, 32}) do
				makePainting(room, side, z + dz,
					Color3.fromRGB(rng:NextInteger(31, 86), rng:NextInteger(40, 80), rng:NextInteger(55, 96)))
			end
		end
		for _, dz in ipairs({13, 34}) do
			roomBlock(room, "Empty pedestal", 2.4, 3.0, 2.4, -9.3, 1.5, z + dz,
				C.marble, Enum.Material.Marble)
		end
	elseif kind == "SUITE" then
		for _, side in ipairs({-1, 1}) do
			local x = side * 10.4
			local dz = side == -1 and 11 or 32
			roomBlock(room, "Four-poster bed", 7.4, 1.4, 6.4, x, 0.75, z + dz,
				C.woodDark, Enum.Material.Wood)
			roomBlock(room, "Dusty bedspread", 6.6, 0.25, 5.8, x, 1.56, z + dz,
				C.carpet, Enum.Material.Fabric)
			for _, xOffset in ipairs({-2.8, 2.8}) do
				roomBlock(room, "Bed post", 0.37, 5.1, 0.37, x + xOffset, 3.4, z + dz - 2.7,
					C.woodLight, Enum.Material.Wood)
			end
			roomBlock(room, "Nightstand", 2.4, 2.4, 2.4, side * 11.5, 1.2, z + (side == -1 and 16 or 38),
				C.wood, Enum.Material.Wood)
		end
	elseif kind == "FLOODED" then
		for j = 1, 6 do
			local x = rng:NextNumber(-8, 8)
			local dz = rng:NextNumber(8, L - 7)
			local puddle = roomBlock(room, "Shallow black water", rng:NextNumber(2, 5), 0.04,
				rng:NextNumber(3, 7), x, 0.065, z + dz, Color3.fromRGB(15, 31, 42), Enum.Material.Glass)
			puddle.Transparency = 0.37
			puddle.Reflectance = 0.24
			puddle.CanCollide = false
		end
		for _, side in ipairs({-1, 1}) do
			roomBlock(room, "Leaking pipe", 0.45, 0.45, 25, side * 13.6, 11.1, z + L / 2,
				C.brassDark, Enum.Material.Metal)
		end
	elseif kind == "STORAGE" then
		for _, side in ipairs({-1, 1}) do
			for _, dz in ipairs({10, 33}) do
				local x = side * 10.2
				roomBlock(room, "Shipping crate", 3.4, 3.2, 3.6, x, 1.6, z + dz,
					C.woodLight, Enum.Material.WoodPlanks)
				roomBlock(room, "Crate iron strap", 3.5, 0.17, 3.7, x, 2.5, z + dz,
					C.brassDark, Enum.Material.Metal)
			end
		end
	elseif kind == "DINING" then
		for _, dz in ipairs({12, 34}) do
			roomBlock(room, "Carved dining table", 5.4, 0.3, 8, -9, 2.75, z + dz, C.woodLight, Enum.Material.Wood)
			roomBlock(room, "Linen table runner", 3.9, 0.04, 7.6, -9, 2.93,
				z + dz, Color3.fromRGB(149, 143, 122), Enum.Material.Fabric).CanCollide = false
			for _, placeZ in ipairs({-2.5, 0, 2.5}) do
				local plate = roomBlock(room, "Dusty porcelain plate", 1.05, 0.11, 1.05,
					-7.45, 2.98, z + dz + placeZ, Color3.fromRGB(159, 155, 144), Enum.Material.SmoothPlastic)
				plate.Shape = Enum.PartType.Ball
				plate.CanCollide = false
			end
			for _, endZ in ipairs({-3.1, 3.1}) do
				roomBlock(room, "Dining table leg", 0.47, 2.6, 0.47, -9, 1.3, z + dz + endZ,
					C.woodDark, Enum.Material.Wood)
			end
			for _, chairZ in ipairs({-2.5, 0, 2.5}) do
				roomBlock(room, "Upholstered chair", 1.6, 0.24, 1.6, -4.7, 1.65, z + dz + chairZ,
					C.carpet, Enum.Material.Fabric)
				roomBlock(room, "Carved chair back", 0.34, 3.1, 1.6, -3.85, 2.2, z + dz + chairZ,
					C.wood, Enum.Material.Wood)
			end
		end
	elseif kind == "CONSERVATORY" then
		for _, dz in ipairs({9, 20, 32}) do
			for _, side in ipairs({-1, 1}) do
				local x = side * 13.55
				roomBlock(room, "Sealed window frame", 0.35, 7, 6.5, x, 8.9, z + dz,
					C.woodDark, Enum.Material.Wood)
				local glass = roomBlock(room, "Rain-stained opaque pane", 0.38, 5.8, 5.7,
					x - side * 0.22, 8.9, z + dz, Color3.fromRGB(48, 69, 65), Enum.Material.Glass)
				glass.Transparency = 0.28
				roomBlock(room, "Window mullion", 0.42, 5.8, 0.18, x - side * 0.45, 8.9,
					z + dz, C.brassDark, Enum.Material.Metal)
				roomBlock(room, "Planter with dark soil", 1.5, 1.6, 3.4,
					side * 11.7, 0.8, z + dz, C.woodDark, Enum.Material.Wood)
				roomBlock(room, "Ficus trunk", 0.18, 3.3, 0.19,
					side * 11.7, 3.15, z + dz, C.wood, Enum.Material.Wood)
				for _, spread in ipairs({-1, 0, 1}) do
					local leaf = roomBlock(room, "Ficus canopy", 1.75, 0.9, 1.5,
						side * (11.7 - spread * 0.48), 4.3 + math.abs(spread) * 0.35,
						z + dz + spread * 0.7, Color3.fromRGB(34, 65, 49), Enum.Material.Grass)
					leaf.Shape = Enum.PartType.Ball
					leaf.CanCollide = false
				end
			end
		end
	elseif kind == "OFFICE" then
		for _, side in ipairs({-1, 1}) do
			for _, dz in ipairs({12, 33}) do
				roomBlock(room, "Clerk's desk", 3.3, 2.6, 4.2, side * 10.3, 1.3,
					z + dz, C.wood, Enum.Material.Wood)
				roomBlock(room, "Green leather writing pad", 2.6, 0.08, 3.1, side * 10.3, 2.64,
					z + dz, Color3.fromRGB(41, 62, 52), Enum.Material.Fabric)
				roomBlock(room, "Desk lamp stem", 0.14, 1.1, 0.14, side * 10.5, 3.2,
					z + dz + 1, C.brass, Enum.Material.Metal)
			end
		end
	elseif kind == "TURN" then
		local side = Layout.TurnSide(room.index)
		local wallColor = room.index % 4 == 2 and C.plasterAlt or C.plaster
		for _, gate in ipairs({{17, side * 8}, {28, -side * 8}}) do
			local dz, gateX = gate[1], gate[2]
			local left, right = gateX - 4.3, gateX + 4.3
			roomBlock(room, "Dogleg masonry partition", left + W / 2, H, 0.85,
				(left - W / 2) / 2, H / 2, z + dz, wallColor, Enum.Material.Concrete)
			roomBlock(room, "Dogleg masonry partition", W / 2 - right, H, 0.85,
				(right + W / 2) / 2, H / 2, z + dz, wallColor, Enum.Material.Concrete)
			roomBlock(room, "Dogleg arch lintel", 8.6, H - 11, 0.88,
				gateX, (H + 11) / 2, z + dz, C.woodDark, Enum.Material.Wood)
			for _, edgeX in ipairs({left, right}) do
				roomBlock(room, "Dogleg brass jamb", 0.26, 11, 0.98,
					edgeX, 5.5, z + dz, C.brassDark, Enum.Material.Metal)
			end
		end
		makePainting(room, -side, z + 9, Color3.fromRGB(54, 67, 75))
		makePainting(room, side, z + 36, Color3.fromRGB(73, 52, 61))
	else -- HALL / vestibule: architectural detail instead of furniture.
		for _, side in ipairs({-1, 1}) do
			for _, dz in ipairs({12, 33}) do
				roomBlock(room, "Fluted pillar", 1.1, 11, 1.1,
					side * 12.9, 5.5, z + dz, C.marble, Enum.Material.Slate)
				roomBlock(room, "Pillar capital", 1.7, 0.6, 1.7,
					side * 12.9, 11.25, z + dz, C.brassDark, Enum.Material.Metal)
			end
		end
	end
end

local function configureLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0.7
	Lighting.Ambient = Color3.fromRGB(12, 17, 22)
	Lighting.OutdoorAmbient = Color3.fromRGB(6, 9, 14)
	Lighting.FogColor = Color3.fromRGB(14, 21, 27)
	Lighting.FogStart = 15
	Lighting.FogEnd = 95
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.ExposureCompensation = -0.2
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Name = "CorridorHaze"
	atmosphere.Density = 0.39
	atmosphere.Haze = 2.3
	atmosphere.Color = Color3.fromRGB(108, 128, 137)
	atmosphere.Decay = Color3.fromRGB(34, 24, 27)
	atmosphere.Parent = Lighting
	local grading = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	grading.Name = "ColdShadowsWarmLights"
	grading.TintColor = Color3.fromRGB(214, 227, 238)
	grading.Contrast = 0.22
	grading.Saturation = -0.32
	grading.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.37
	bloom.Size = 26
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.2
	dof.NearIntensity = 0.04
	dof.FocusDistance = 22
	dof.InFocusRadius = 18
	dof.Parent = Lighting
	SoundService.AmbientReverb = Enum.ReverbType.Hallway
end

local openDoor -- assigned after room construction
local startRush -- assigned after room construction
local startBlind -- assigned after room construction
local startMoth -- assigned after room construction
local buildRoom -- recursive reference for door callbacks

-- Every wall encloses the entire section, including the space UNDER an upper
-- landing. Only the central 7.4-stud doorway is open. Doorways on both sides
-- of a room always meet at the same height as their neighbour's doorway.
local function endWall(room, atZ, doorwayY, bottomY, topY, solid)
	local model = room.model
	local wallColor = room.index % 4 == 2 and C.plasterAlt or C.plaster
	if solid then
		block(model, "Solid lobby end wall", W, topY - bottomY, 0.8,
			0, (topY + bottomY) / 2, atZ, wallColor, Enum.Material.Concrete)
		return
	end
	if doorwayY > bottomY then
		block(model, "Masonry beneath upper doorway", W, doorwayY - bottomY, 0.8,
			0, (doorwayY + bottomY) / 2, atZ, wallColor, Enum.Material.Concrete)
	end
	local clearHeight = 10.8
	for _, side in ipairs({-1, 1}) do
		block(model, "Doorway side masonry", (W - Layout.DoorWidth) / 2, topY - doorwayY, 0.8,
			side * (W + Layout.DoorWidth) / 4, (topY + doorwayY) / 2, atZ,
			wallColor, Enum.Material.Concrete)
		block(model, "Structural door jamb", 0.33, clearHeight, 1.0,
			side * Layout.DoorWidth / 2, doorwayY + clearHeight / 2, atZ,
			C.brassDark, Enum.Material.Metal)
	end
	local above = topY - doorwayY - clearHeight
	if above > 0 then
		block(model, "Lintel and upper wall", Layout.DoorWidth, above, 0.8,
			0, doorwayY + clearHeight + above / 2, atZ, wallColor, Enum.Material.Concrete)
	end
	block(model, "Doorway threshold", Layout.DoorWidth - 0.5, 0.14, 1.1,
		0, doorwayY - 0.07, atZ, C.brassDark, Enum.Material.Metal)
end

local function flatRoom(room, rng)
	local model = room.model
	local z = room.index * L
	local y = room.entryY
	local wallColor = room.index % 4 == 2 and C.plasterAlt or C.plaster
	roomBlock(room, "Continuous wooden subfloor", W, 1.3, L, 0, -0.65, z + L / 2,
		C.wood, Enum.Material.WoodPlanks)
	roomBlock(room, "Continuous interior ceiling", W, 0.9, L, 0, H + 0.45, z + L / 2,
		C.woodDark, Enum.Material.Wood)
	for _, side in ipairs({-1, 1}) do
		roomBlock(room, "Load-bearing corridor wall", 0.8, H, L, side * (W / 2 - 0.4),
			H / 2, z + L / 2, wallColor, Enum.Material.Concrete)
		roomBlock(room, "Oak wainscot", 0.13, 4.2, L - 0.7, side * (W / 2 - 0.86),
			2.1, z + L / 2, C.woodDark, Enum.Material.Wood)
		roomBlock(room, "Picture rail", 0.25, 0.22, L - 0.7, side * (W / 2 - 0.9),
			11.5, z + L / 2, C.brassDark, Enum.Material.Metal)
		roomBlock(room, "Gilded skirting", 0.3, 0.3, L - 0.7, side * (W / 2 - 0.92),
			0.18, z + L / 2, C.brassDark, Enum.Material.Metal)
		for _, dz in ipairs({5.5, 15, 29, 38.5}) do
			local color = (room.index + dz) % 3 == 0 and Color3.fromRGB(35, 42, 43)
				or Color3.fromRGB(39, 48, 49)
			roomBlock(room, "Distressed wall panel", 0.08, 6.1, 7.0,
				side * (W / 2 - 0.84), 7.65, z + dz, color, Enum.Material.Concrete)
			roomBlock(room, "Gilt wall moulding", 0.17, 0.13, 7.2,
				side * (W / 2 - 0.89), 10.75, z + dz, C.brassDark, Enum.Material.Metal)
		end
		for _, dz in ipairs({12, 32}) do
			addLight(model, Vector3.new(side * (W / 2 - 2.5), y + 11.5, z + dz), room,
				room.index % 9 == 6 and 0.8 or 1.6)
		end
	end
	for _, dz in ipairs({3.4, L / 2, L - 3.4}) do
		roomBlock(room, "Joined ceiling joist", W - 1.2, 0.36, 0.4,
			0, H - 0.12, z + dz, C.brassDark, Enum.Material.Metal)
	end
	if room.kind == "TURN" then
		local side = Layout.TurnSide(room.index)
		local stops = {{0, 3}, {side * 8, 17}, {-side * 8, 28}, {0, 41}}
		for i = 2, #stops do
			local a, b = stops[i - 1], stops[i]
			local from = Vector3.new(a[1], y + 0.07, z + a[2])
			local to = Vector3.new(b[1], y + 0.07, z + b[2])
			local mid = (from + to) / 2
			local carpet = newPart(model, "Dogleg crimson runner", Vector3.new(6.2, 0.06, (to - from).Magnitude),
				CFrame.lookAt(mid, to), C.carpet, Enum.Material.Fabric, 0, false)
			carpet.CanQuery = false
		end
	else
		local rug = roomBlock(room, "Worn crimson runner", 7.4, 0.06, L - 6,
			0, 0.055, z + L / 2, C.carpet, Enum.Material.Fabric)
		rug.CanCollide = false
		for _, x in ipairs({-3.5, 3.5}) do
			local edging = roomBlock(room, "Runner gold edging", 0.1, 0.07, L - 6,
				x, 0.095, z + L / 2, C.brassDark, Enum.Material.Fabric)
			edging.CanCollide = false
		end
	end
	endWall(room, z + 0.45, y, y, y + H, room.index == 0)
	endWall(room, z + L - 0.45, y, y, y + H, false)
	if room.index == 0 then
		local sign = roomBlock(room, "Hotel sign", 12, 2.2, 0.15,
			0, 9.5, z + 0.86, C.woodDark, Enum.Material.Wood)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.CanvasSize = Vector2.new(900, 180)
		gui.LightInfluence = 0.05
		gui.Parent = sign
		local letters = Instance.new("TextLabel")
		letters.Size = UDim2.fromScale(1, 1)
		letters.BackgroundTransparency = 1
		letters.Font = Enum.Font.Garamond
		letters.TextColor3 = C.brass
		letters.TextScaled = true
		letters.Text = "N O C T U R N E"
		letters.Parent = gui
	end
	furnish(room, rng)
	makeDresser(room, rng)
	if room.kind == "TURN" then
		-- Closets remain on the entrance and exit sides of BOTH dogleg arches.
		makeCloset(room, -1, z + 7, "A", y, W / 2)
		makeCloset(room, 1, z + 39, "B", y, W / 2)
	else
		makeCloset(room, -1, z + 21, "A", y, W / 2)
		makeCloset(room, 1, z + 24, "B", y, W / 2)
	end
	addLight(model, Vector3.new(0, y + H - 1.7, z + L / 2), room,
		room.index % 9 == 6 and 0.55 or 1.15)
end

local function stairRoom(room)
	local model = room.model
	local z = room.index * L
	local y = room.entryY
	local upper = room.exitY
	local width = Layout.StairWidth
	local half = width / 2
	local start = Layout.StairStart
	local finish = Layout.StairEnd
	local steps = Layout.StairSteps
	local rise = Layout.StoreyRise / steps
	local treadDepth = (finish - start) / steps
	local flankWidth = (W - width) / 2
	local fullHeight = H + Layout.StoreyRise

	-- The two flanks are SOLID MASONRY, not railings next to an exposed void.
	-- No accessible space remains beside, under, or behind the stair flight.
	block(model, "Stair foundation", W, 1.3, L,
		0, y - 0.95, z + L / 2, C.woodDark, Enum.Material.Concrete)
	for _, side in ipairs({-1, 1}) do
		block(model, "Solid enclosed stair flank", flankWidth, fullHeight, L,
			side * (W + width) / 4, y + fullHeight / 2, z + L / 2,
			C.plaster, Enum.Material.Concrete)
		for _, dz in ipairs({4, 12, 22, 32, 40}) do
			local surface = Layout.WalkwayY(room.index, dz)
			block(model, "Stair wall pilaster", 0.24, 9, 0.48,
				side * (half - 0.13), surface + 4.5, z + dz,
				C.woodDark, Enum.Material.Wood)
		end
	end
	endWall(room, z + 0.45, y, y, upper + H, false)
	endWall(room, z + L - 0.45, upper, y, upper + H, false)

	block(model, "Lower stair landing", width + 0.04, 1.0, start + 0.04,
		0, y - 0.5, z + start / 2, C.wood, Enum.Material.WoodPlanks)
	block(model, "Upper stair landing", width + 0.04, 1.0, L - finish + 0.04,
		0, upper - 0.5, z + (finish + L) / 2, C.wood, Enum.Material.WoodPlanks)
	block(model, "Lower enclosed ceiling", width + 0.04, 0.9, start + 0.04,
		0, y + H + 0.45, z + start / 2, C.woodDark, Enum.Material.Wood)
	block(model, "Upper enclosed ceiling", width + 0.04, 0.9, L - finish + 0.04,
		0, upper + H + 0.45, z + (finish + L) / 2, C.woodDark, Enum.Material.Wood)

	for step = 1, steps do
		local near = z + start + (step - 1) * treadDepth
		local far = near + treadDepth
		local treadY = y + step * rise
		-- Solid, slightly overlapping risers. There is never an unsupported gap.
		block(model, "Solid stair tread", width + 0.05, treadY - y + 0.2,
			treadDepth + 0.05, 0, (treadY + y - 0.2) / 2, (near + far) / 2,
			C.wood, Enum.Material.WoodPlanks)
		local runner = block(model, "Stair runner", 6.6, 0.05, treadDepth - 0.04,
			0, treadY + 0.035, (near + far) / 2, C.carpet, Enum.Material.Fabric)
		runner.CanCollide = false
		local edge = block(model, "Brass tread nosing", width - 0.3, 0.08, 0.14,
			0, treadY + 0.045, near + 0.08, C.brassDark, Enum.Material.Metal)
		edge.CanCollide = false
		block(model, "Stepped enclosed ceiling", width + 0.05, 0.9, treadDepth + 0.05,
			0, treadY + H + 0.45, (near + far) / 2, C.woodDark, Enum.Material.Wood)
		block(model, "Sealed ceiling riser", width + 0.06, rise + 0.12, 0.17,
			0, y + H + (step - 0.5) * rise, near, C.woodDark, Enum.Material.Wood)
	end

	for _, side in ipairs({-1, 1}) do
		local railX = side * (half - 0.53)
		railBetween(model, "Continuous wall-mounted handrail",
			Vector3.new(railX, y + 3.2, z + start + 0.05),
			Vector3.new(railX, upper + 3.2, z + finish - 0.05), 0.13, C.brass)
		for _, step in ipairs({2, 6, 10, 14}) do
			local dz = start + (step - 0.5) * treadDepth
			local footY = y + step * rise
			local railY = y + 3.2 + (dz - start) / (finish - start) * Layout.StoreyRise
			block(model, "Stair handrail bracket", 0.16, railY - footY, 0.16,
				railX, (railY + footY) / 2, z + dz, C.brassDark, Enum.Material.Metal)
		end
	end
	for _, dz in ipairs({5, 17, 29, 40}) do
		local walkY = Layout.WalkwayY(room.index, dz)
		local side = dz % 2 == 0 and -1 or 1
		addLight(model, Vector3.new(side * (half - 1.3), walkY + 10.6, z + dz),
			room, dz == 29 and 0.8 or 1.45)
	end

	local floorPlaque = block(model, "Upper landing floor number", 4.2, 1.4, 0.1,
		0, upper + 12.2, z + L - 0.95, C.woodDark, Enum.Material.Metal)
	inscription(model, floorPlaque,
		string.format("ЭТАЖ %02d", math.floor(upper / Layout.StoreyRise) + 1), true)
	-- These are on real, walkable landings, NEVER behind a flight or under a slab.
	makeCloset(room, -1, z + 3.4, "A", y, half)
	makeCloset(room, 1, z + 40.4, "B", upper, half)
end

buildRoom = function(index)
	if index < 0 or index >= CONFIG.Doors or state.rooms[index] then return end
	local z = index * L
	local rng = Random.new(state.seed + index * 7417)
	local isStair = Layout.IsStair(index)
	local kinds = {"HALL", "LIBRARY", "GALLERY", "SUITE", "STORAGE", "FLOODED",
		"DINING", "CONSERVATORY", "OFFICE"}
	-- A seeded cycle guarantees every interior appears; relying on the first
	-- draw of similarly seeded Random instances clusters the same few kinds.
	local variant = kinds[((index * 5 + math.floor(index / 11) + state.seed) % #kinds) + 1]
	local kind = isStair and "STAIRWELL" or (Layout.IsTurn(index) and "TURN" or
		(index == 0 and "HALL" or variant))
	local threat = not isStair and index >= 5 and
		(index % 12 == 5 and "RUSH" or index % 12 == 9 and "BLIND"
			or index % 12 == 3 and "MOTH" or nil) or nil
	local locked = not isStair and index >= 4 and index % 7 == 4 and not threat
	local model = Instance.new("Model")
	model.Name = string.format("Room_%03d_%s", index, kind)
	model:SetAttribute("RoomIndex", index)
	model:SetAttribute("Variant", kind)
	model:SetAttribute("EntryY", Layout.EntranceY(index))
	model:SetAttribute("ExitY", Layout.ExitY(index))
	model:SetAttribute("Storey", math.floor(Layout.EntranceY(index) / Layout.StoreyRise) + 1)
	model:SetAttribute("Threat", threat or "NONE")
	model:SetAttribute("Locked", locked)
	model:SetAttribute("KeyFound", false)
	model.Parent = state.world
	local room = {
		index = index, model = model, kind = kind, lamps = {}, closets = {}, entered = {},
		entryY = Layout.EntranceY(index), exitY = Layout.ExitY(index),
		threat = threat, locked = locked, unlocked = not locked,
		open = false, busy = false, epoch = session,
	}
	state.rooms[index] = room
	if isStair then stairRoom(room) else flatRoom(room, rng) end

	local door, leaf, prompt, hinge = hingeDoor(model, index + 1, z + L - 0.65, room.exitY)
	room.door = door
	room.leaf = leaf
	room.prompt = prompt
	room.hinge = hinge
	prompt.ActionText = locked and "Нужен ключ" or "Открыть"
	prompt.Enabled = index == state.opened
	local mySession = session
	prompt.Triggered:Connect(function(player)
		if mySession ~= session then return end
		openDoor(player, index)
	end)

	local sensorZ = isStair and 4.0 or 9.0
	local entry = newPart(model, "Room entry sensor", Vector3.new(8, 6.5, 2.6),
		CFrame.new(0, room.entryY + 3.4, z + sensorZ),
		Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1, false)
	entry.CanTouch = true
	entry.CanQuery = false
	entry.Touched:Connect(function(hit)
		if mySession ~= session then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or room.entered[player] then return end
		local root = playerRoot(player)
		if not root or math.abs(root.Position.Z - (z + sensorZ)) > 8 then return end
		room.entered[player] = true
		if room.threat == "RUSH" and not state.rush then
			room.threat = nil
			task.spawn(function() startRush(room, mySession) end)
		elseif room.threat == "BLIND" and not state.blind then
			room.threat = nil
			task.spawn(function() startBlind(room, mySession) end)
		elseif room.threat == "MOTH" and not state.moth then
			room.threat = nil
			task.spawn(function() startMoth(room, mySession) end)
		end
	end)
end
local function makeExit()
	if state.world:FindFirstChild("Exit") then return end
	local model = Instance.new("Model")
	model.Name = "Exit"
	model.Parent = state.world
	local z = CONFIG.Doors * L
	local y = Layout.EntranceY(CONFIG.Doors)
	block(model, "Last floor", W, 1.3, 34, 0, y - 0.65, z + 17, C.marble, Enum.Material.Marble)
	for _, side in ipairs({-1, 1}) do
		block(model, "Pale exit wall", 0.8, H, 34, side * (W / 2 - 0.4), y + H / 2,
			z + 17, Color3.fromRGB(153, 163, 156), Enum.Material.Marble)
	end
	block(model, "Exit ceiling", W, 0.9, 34, 0, y + H + 0.45, z + 17,
		Color3.fromRGB(191, 200, 186), Enum.Material.Marble)
	local portal = block(model, "Morning", 19, 12, 0.45, 0, y + 6, z + 32,
		Color3.fromRGB(255, 242, 200), Enum.Material.Neon)
	portal.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 225, 173)
	light.Range = 42
	light.Brightness = 8
	light.Parent = portal
	local trigger = newPart(model, "End of the nightmare", Vector3.new(19, 10, 5),
		CFrame.new(0, y + 5, z + 25), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1, false)
	trigger.CanTouch = true
	trigger.CanQuery = false
	local mySession = session
	trigger.Touched:Connect(function(hit)
		if mySession ~= session then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or player:GetAttribute("Finished") then return end
		local root = playerRoot(player)
		if root and root.Position.Z > z + 20 then
			player:SetAttribute("Finished", true)
			remote:FireClient(player, "Victory")
		end
	end)
end

local function pruneRooms()
	local first = math.max(0, state.opened - CONFIG.KeepBehind)
	if state.spawn then
		state.spawn.CFrame = CFrame.new(0, Layout.EntranceY(first) - 0.75, first * L + 6)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local hiding = state.hidden[player]
		if hiding and hiding.closet.rootCF.Position.Z < first * L then leaveCloset(player, false) end
		local root = playerRoot(player)
		if root and root.Position.Z < first * L + 5 then
			root.CFrame = CFrame.new(0, Layout.EntranceY(first) + 3, first * L + 6)
				* CFrame.Angles(0, math.pi, 0)
		end
	end
	for index, room in pairs(state.rooms) do
		local chased = state.rush and index >= state.rush.origin and index <= state.rush.limit
		local patrolled = state.blind and index == state.blind.index
		local attracted = state.moth and index == state.moth.index
		if index < first and not chased and not patrolled and not attracted then
			room.model:Destroy()
			state.rooms[index] = nil
		end
	end
	-- Deleting the previous room must not leave a walkable doorway into void.
	if state.backSeal and state.backSeal.Parent then state.backSeal:Destroy() end
	state.backSeal = nil
	if first > 0 and state.rooms[first] then
		local floorY = state.rooms[first].entryY
		state.backSeal = block(state.rooms[first].model, "The corridor closes behind you",
			7.25, 10.8, 0.45, 0, floorY + 5.4, first * L + 0.95,
			C.woodDark, Enum.Material.Wood)
		block(state.backSeal, "Final brass line", 6.5, 0.09, 0.08,
			0, floorY + 6.8, first * L + 1.22, C.brassDark, Enum.Material.Metal)
	end
end

openDoor = function(player, index)
	if state.hidden[player] then return end
	local room = state.rooms[index]
	if not room or room.epoch ~= session or room.busy or not room.prompt.Enabled then return end
	local root = playerRoot(player)
	if not root or (root.Position - room.leaf.Position).Magnitude > 12 then return end
	-- Previously visited doors really close and reopen. Neither a shut door nor
	-- a newly opened next door is a safe boundary against the Rush.
	if index < state.opened then
		swingDoor(room, not room.open)
		return
	end
	if index ~= state.opened or root.Position.Z < index * L + L - 13 then return end
	if not room.unlocked then
		remote:FireClient(player, "Locked", index + 1)
		return
	end
	-- Construct the next enclosed segment before swinging the leaf open.
	if index == CONFIG.Doors - 1 then makeExit() end
	state.opened = index + 1
	state.world:SetAttribute("DoorsOpened", state.opened)
	for nextIndex = state.opened, math.min(CONFIG.Doors - 1, state.opened + CONFIG.Ahead - 1) do
		buildRoom(nextIndex)
	end
	if state.rooms[state.opened] then state.rooms[state.opened].prompt.Enabled = true end
	swingDoor(room, true)
	remote:FireAllClients("Door", state.opened)
	pruneRooms()
end

-- Rush: foretold only by LIGHT, never by a warning sound. It starts three
-- rooms behind, navigates the enclosed stairs and offset archways, and keeps
-- chasing through doors opened while it is moving. A single door is no refuge.
local function makeRush()
	local entity = Instance.new("Model")
	entity.Name = "TheRush"
	entity.Parent = state.world
	local body = newPart(entity, "Soot-black silhouette", Vector3.new(10, 6.5, 3.6),
		CFrame.new(), C.shadow, Enum.Material.SmoothPlastic, 0.08, false)
	body.Shape = Enum.PartType.Ball
	entity.PrimaryPart = body
	newPart(entity, "Room-wide black wake", Vector3.new(W - 1.4, 9.2, 0.2),
		CFrame.new(0, 0, 1), C.shadow, Enum.Material.SmoothPlastic, 0.72, false)
	local skull = newPart(entity, "Faceless head", Vector3.new(2.75, 2.9, 2.5),
		CFrame.new(0, 3.45, -0.25), C.shadow, Enum.Material.SmoothPlastic, 0, false)
	skull.Shape = Enum.PartType.Ball
	for _, side in ipairs({-1, 1}) do
		local eye = newPart(entity, "Ember eye", Vector3.new(0.38, 0.55, 0.18),
			CFrame.new(side * 0.7, 3.7, -1.5), Color3.fromRGB(246, 46, 37),
			Enum.Material.Neon, 0, false)
		eye.Shape = Enum.PartType.Ball
		for j = 1, 3 do
			newPart(entity, "Raking limb", Vector3.new(0.33, 3.8 + j * 1.3, 0.34),
				CFrame.new(side * (1.5 + j * 0.6), -1.2 - j * 0.7, j * 0.6)
					* CFrame.Angles(0, 0, math.rad(side * (17 + 8 * j))),
				C.shadow, Enum.Material.SmoothPlastic, 0, false)
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(202, 30, 24)
	glow.Brightness = 2.3
	glow.Range = 14
	glow.Parent = skull
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Cold vapor"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 55
	smoke.Lifetime = NumberRange.new(0.45, 1.1)
	smoke.Speed = NumberRange.new(0.2, 1.8)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new(2.5, 5)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Color = ColorSequence.new(Color3.fromRGB(25, 24, 32))
	smoke.Parent = body
	return entity
end

local function pathPoint(z)
	local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(z))
	local localZ = math.clamp(z - index * L, 0, L)
	return Vector3.new(Layout.PathX(index, localZ), Layout.WalkwayY(index, localZ) + 5, z)
end

local function killPlayer(player, humanoid)
	if humanoid.Health <= 0 then return end
	remote:FireClient(player, "Jumpscare")
	humanoid.Health = 0
end

startRush = function(room, epoch)
	if epoch ~= session or state.rush then return end
	local origin = math.max(0, room.index - 3)
	local limit = math.min(CONFIG.Doors - 1, room.index + 3)
	local rush = {origin = origin, limit = limit, positionZ = origin * L + 5}
	state.rush = rush
	remote:FireAllClients("Warning", "RUSH", room.index)
	local rng = Random.new(state.seed + room.index * 97 + 41)
	for _ = 1, math.ceil(CONFIG.RushWarningSeconds / 0.2) do
		if epoch ~= session then return end
		for index = origin, math.min(room.index + 1, limit) do
			local litRoom = state.rooms[index]
			if litRoom then
				for _, lamp in ipairs(litRoom.lamps) do
					if lamp.light.Parent then
						local on = rng:NextNumber() > 0.48
						lamp.light.Enabled = on
						lamp.bulb.Transparency = on and 0 or 0.94
						end
				end
			end
		end
		task.wait(0.2)
	end
	if epoch ~= session then return end
	local entity = makeRush()
	local z = rush.positionZ
	local maxZ = (limit + 1) * L - 4
	local elapsed, stalled = 0, 0
	while epoch == session and elapsed < CONFIG.RushMaximumSeconds do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
		if epoch ~= session then break end
		elapsed = elapsed + dt
		local allowed = math.min(maxZ, (state.opened + 1) * L - 4)
		local previous = z
		z = math.min(allowed, z + CONFIG.RushSpeed * dt)
		rush.positionZ = z
		local point = pathPoint(z)
		local ahead = pathPoint(math.min(maxZ, z + 1.5))
		entity:PivotTo(CFrame.lookAt(point, point + Vector3.new(ahead.X - point.X, 0, 1)))
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = playerRoot(player)
			if root and not state.hidden[player] and root.Position.Z >= previous - 4.5
				and root.Position.Z <= z + 4.5 then
				local crossing = pathPoint(math.clamp(root.Position.Z, previous, z))
				-- The wake sweeps the enclosed width, including side alcoves;
				-- only an occupied wardrobe grants shelter from this creature.
				if math.abs(root.Position.X) < W / 2 - 0.7
					and math.abs(root.Position.Y - (crossing.Y - 2)) < 5.5 then
					killPlayer(player, humanoid)
				end
			end
		end
		if z >= allowed - 0.01 then stalled = stalled + dt else stalled = 0 end
		if z >= maxZ - 0.01 or stalled > 2.6 then break end
	end
	if entity.Parent then entity:Destroy() end
	if epoch ~= session then return end
	for index = origin, math.min(room.index + 1, limit) do
		local litRoom = state.rooms[index]
		if litRoom then
			for _, lamp in ipairs(litRoom.lamps) do
				if lamp.light.Parent then
					lamp.light.Enabled = true
					lamp.light.Brightness = lamp.brightness
					lamp.bulb.Transparency = 0
				end
			end
		end
	end
	state.rush = nil
	remote:FireAllClients("Safe", "RUSH", room.index)
	pruneRooms()
end

-- The Blind Guest comes FROM the room ahead. It has no vision: crouching
-- players are ignored unless they touch it. Standing, sprinting or hiding in
-- a creaking wardrobe draws it straight to that position. Wardrobes are NOT a
-- universal shield; the Guest will find and kill their occupants.
local function makeBlind()
	local entity = Instance.new("Model")
	entity.Name = "TheBlindGuest"
	entity.Parent = state.world
	local body = newPart(entity, "Gaunt overcoat", Vector3.new(2.75, 6.2, 1.9),
		CFrame.new(0, 0, 0), Color3.fromRGB(60, 64, 61), Enum.Material.Fabric, 0, false)
	entity.PrimaryPart = body
	local skull = newPart(entity, "Porcelain mask", Vector3.new(2.0, 2.35, 1.45),
		CFrame.new(0, 3.7, -0.2), Color3.fromRGB(165, 163, 148), Enum.Material.SmoothPlastic, 0, false)
	skull.Shape = Enum.PartType.Ball
	for _, side in ipairs({-1, 1}) do
		newPart(entity, "Sewn-shut eye", Vector3.new(0.62, 0.1, 0.16),
			CFrame.new(side * 0.48, 4.02, -0.94) * CFrame.Angles(0, 0, side * 0.3),
			C.woodDark, Enum.Material.Fabric, 0, false)
		newPart(entity, "Searching arm", Vector3.new(0.4, 5.6, 0.52),
			CFrame.new(side * 2.1, -1.0, -0.8) * CFrame.Angles(0, 0, side * 0.19),
			Color3.fromRGB(130, 130, 120), Enum.Material.SmoothPlastic, 0, false)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(179, 205, 182)
	light.Brightness = 0.9
	light.Range = 11
	light.Parent = skull
	return entity
end

startBlind = function(room, epoch)
	if epoch ~= session or state.blind then return end
	local blind = {index = room.index}
	state.blind = blind
	remote:FireAllClients("Warning", "BLIND", room.index)
	for _, lamp in ipairs(room.lamps) do
		if lamp.light.Parent then lamp.light.Brightness = lamp.brightness * 0.45 end
	end
	task.wait(0.8)
	if epoch ~= session then return end
	local entity = makeBlind()
	local startZ = room.index * L
	local position = Vector3.new(0, room.entryY + 4.7, startZ + 35)
	local elapsed = 0
	while epoch == session and elapsed < CONFIG.BlindLifetime do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
		if epoch ~= session then break end
		elapsed = elapsed + dt
		local destination
		local nearest = math.huge
		for _, player in ipairs(Players:GetPlayers()) do
			local root = playerRoot(player)
			local info = state.players[player]
			if root and info and root.Position.Z > startZ + 2 and root.Position.Z < startZ + L - 1
				and math.abs(root.Position.Y - room.entryY - 3) < 5
				and (state.hidden[player] or not info.crouching) then
				local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if delta.Magnitude < nearest then
					nearest = delta.Magnitude
					destination = root.Position
				end
				local hiding = state.hidden[player]
				if hiding and delta.Magnitude < 7 and not hiding.closet.inspected then
					hiding.closet.inspected = true
					swingCloset(hiding.closet, true)
				end
			end
		end
		if not destination then
			destination = Vector3.new(math.sin(elapsed * 0.66) * 4.5, position.Y,
				startZ + 23 + math.cos(elapsed * 0.48) * 12)
		end
		local dx, dz = destination.X - position.X, destination.Z - position.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local speed = nearest < math.huge and 24 or 11
		local step = math.min(distance, speed * dt)
		if distance > 0.01 then
			position = Vector3.new(position.X + dx / distance * step,
				room.entryY + 4.7 + math.sin(elapsed * 5) * 0.13,
				position.Z + dz / distance * step)
			entity:PivotTo(CFrame.lookAt(position, position + Vector3.new(dx / distance, 0, dz / distance)))
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = playerRoot(player)
			if root and root.Position.Z > startZ and root.Position.Z < startZ + L
				and math.abs(root.Position.Y - room.entryY - 3) < 5 then
				local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if delta.Magnitude < (state.hidden[player] and 5.1 or 3.7) then
					-- Contact kills even if the player is crouched.
					killPlayer(player, humanoid)
				end
			end
		end
	end
	if entity.Parent then entity:Destroy() end
	if epoch ~= session then return end
	for _, lamp in ipairs(room.lamps) do
		if lamp.light.Parent then lamp.light.Brightness = lamp.brightness end
	end
	state.blind = nil
	remote:FireAllClients("Safe", "BLIND", room.index)
	pruneRooms()
end

-- The Pale Moth listens for a beam rather than footsteps. Turning the
-- flashlight OFF is the survival rule; crouching alone does nothing. It can
-- pass through an unlit player without damage and never causes a light blink.
local function makeMoth()
	local entity = Instance.new("Model")
	entity.Name = "ThePaleMoth"
	entity.Parent = state.world
	local core = newPart(entity, "Waxy floating body", Vector3.new(2.4, 4.2, 1.8),
		CFrame.new(), Color3.fromRGB(165, 173, 160), Enum.Material.SmoothPlastic, 0.18, false)
	core.Shape = Enum.PartType.Ball
	entity.PrimaryPart = core
	for _, side in ipairs({-1, 1}) do
		local wing = newPart(entity, "Veined moth wing", Vector3.new(5.5, 4.7, 0.19),
			CFrame.new(side * 3.5, 0.9, 0.5) * CFrame.Angles(0, side * 0.23, side * 0.17),
			Color3.fromRGB(119, 136, 128), Enum.Material.Glass, 0.35, false)
		wing.CastShadow = false
		newPart(entity, "Wing vein", Vector3.new(4.5, 0.1, 0.23),
			CFrame.new(side * 3.5, 0.9, 0.35) * CFrame.Angles(0, 0, side * 0.17),
			C.brassDark, Enum.Material.Metal, 0, false)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(154, 222, 177)
	light.Brightness = 1.35
	light.Range = 16
	light.Parent = core
	return entity
end

startMoth = function(room, epoch)
	if epoch ~= session or state.moth then return end
	state.moth = {index = room.index}
	remote:FireAllClients("Warning", "MOTH", room.index)
	for _, lamp in ipairs(room.lamps) do
		if lamp.light.Parent then lamp.light.Brightness = lamp.brightness * 0.65 end
	end
	task.wait(0.7)
	if epoch ~= session then return end
	local entity = makeMoth()
	local startZ = room.index * L
	local position = Vector3.new(0, room.entryY + 6.5, startZ + 32)
	local elapsed = 0
	while epoch == session and elapsed < CONFIG.MothLifetime do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
		if epoch ~= session then break end
		elapsed = elapsed + dt
		local destination
		local nearest = math.huge
		for _, player in ipairs(Players:GetPlayers()) do
			local root = playerRoot(player)
			local info = state.players[player]
			if root and info and info.torchOn and not state.hidden[player]
				and root.Position.Z > startZ + 2 and root.Position.Z < startZ + L - 1
				and math.abs(root.Position.Y - room.entryY - 3) < 5 then
				local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if delta.Magnitude < nearest then
					nearest = delta.Magnitude
					destination = root.Position
				end
			end
		end
		if not destination then
			destination = Vector3.new(math.sin(elapsed * 0.57) * 5.2,
				position.Y, startZ + 21 + math.cos(elapsed * 0.48) * 11)
		end
		local dx, dz = destination.X - position.X, destination.Z - position.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local speed = nearest < math.huge and 28 or 9
		local step = math.min(distance, speed * dt)
		if distance > 0.01 then
			position = Vector3.new(position.X + dx / distance * step,
				room.entryY + 6.5 + math.sin(elapsed * 4.1) * 0.36,
				position.Z + dz / distance * step)
			entity:PivotTo(CFrame.lookAt(position, position + Vector3.new(dx / distance, 0, dz / distance)))
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = playerRoot(player)
			local info = state.players[player]
			if root and info and info.torchOn and not state.hidden[player]
				and root.Position.Z > startZ and root.Position.Z < startZ + L
				and math.abs(root.Position.Y - room.entryY - 3) < 5 then
				local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if delta.Magnitude < 5.3 then killPlayer(player, humanoid) end
			end
		end
	end
	if entity.Parent then entity:Destroy() end
	if epoch ~= session then return end
	for _, lamp in ipairs(room.lamps) do
		if lamp.light.Parent then lamp.light.Brightness = lamp.brightness end
	end
	state.moth = nil
	remote:FireAllClients("Safe", "MOTH", room.index)
	pruneRooms()
end

local function resetWorld()
	session = session + 1
	for player in pairs(state.hidden) do leaveCloset(player, false) end
	if state.world then state.world:Destroy() end
	local old = Workspace:FindFirstChild("NocturneWorld")
	if old then old:Destroy() end
	state.world = Instance.new("Folder")
	state.world.Name = "NocturneWorld"
	state.world.Parent = Workspace
	state.rooms = {}
	state.hidden = {}
	state.opened = 0
	state.rush = nil
	state.blind = nil
	state.moth = nil
	state.backSeal = nil
	state.seed = CONFIG.Seed or math.floor((os.time() + session * 7919) % 100000000)
	state.world:SetAttribute("Seed", state.seed)
	state.world:SetAttribute("DoorsOpened", 0)
	state.world:SetAttribute("TotalDoors", CONFIG.Doors)
	state.world:SetAttribute("Storeys", math.floor(Layout.EntranceY(CONFIG.Doors) / Layout.StoreyRise) + 1)
	buildRoom(0)
	buildRoom(1)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CheckpointSpawn"
	spawn.Size = Vector3.new(4, 0.4, 4)
	spawn.CFrame = CFrame.new(0, Layout.EntranceY(0) - 0.75, 6)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = state.world
	state.spawn = spawn
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Hidden", false)
		player:SetAttribute("Finished", false)
		remote:FireClient(player, "State", state.opened, state.seed, L)
	end
end

configureLighting()
Players.CharacterAutoLoads = false
resetWorld()

local function registerPlayer(player)
	state.players[player] = {stamina = 100, sprinting = false, crouching = false, torchOn = true}
	player:SetAttribute("Stamina", 100)
	player:SetAttribute("Hidden", false)
	player:SetAttribute("Crouching", false)
	player:SetAttribute("Finished", false)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 12)
		local root = character:WaitForChild("HumanoidRootPart", 12)
		if not humanoid or not root then return end
		state.players[player].stamina = 100
		state.players[player].sprinting = false
		state.players[player].crouching = false
		state.players[player].torchOn = true
		player:SetAttribute("Stamina", 100)
		player:SetAttribute("Hidden", false)
		player:SetAttribute("Crouching", false)
		humanoid.WalkSpeed = CONFIG.WalkSpeed
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		local checkpoint = math.max(0, state.opened - 2)
		if not state.rooms[checkpoint] then checkpoint = math.max(0, state.opened - CONFIG.KeepBehind) end
		root.CFrame = CFrame.new(0, Layout.EntranceY(checkpoint) + 3, checkpoint * L + 6)
			* CFrame.Angles(0, math.pi, 0)
		remote:FireClient(player, "State", state.opened, state.seed, L)
		humanoid.Died:Connect(function()
			leaveCloset(player, false)
			remote:FireClient(player, "Death")
		end)
	end)
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(registerPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(registerPlayer, player) end
Players.PlayerRemoving:Connect(function(player)
	leaveCloset(player, false)
	state.players[player] = nil
end)

remote.OnServerEvent:Connect(function(player, action, argument)
	local info = state.players[player]
	if not info then return end
	if action == "Ready" then
		remote:FireClient(player, "State", state.opened, state.seed, L)
		return
	end
	if action == "Exit" then
		leaveCloset(player, true)
	elseif action == "Sprint" then
		if typeof(argument) == "boolean" then info.sprinting = argument and not info.crouching end
	elseif action == "Crouch" then
		if typeof(argument) == "boolean" and not state.hidden[player]
			and not player:GetAttribute("Finished") then
			info.crouching = argument
			if argument then info.sprinting = false end
			player:SetAttribute("Crouching", argument)
		end
	elseif action == "Torch" then
		if typeof(argument) == "boolean" then info.torchOn = argument end
	elseif action == "Retry" then
		local oldHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local finished = player:GetAttribute("Finished") == true
		if (not finished and (not oldHum or oldHum.Health > 0)) or state.hidden[player] then return end
		if info.lastRetry and os.clock() - info.lastRetry < 1.5 then return end
		info.lastRetry = os.clock()
		if #Players:GetPlayers() == 1 then
			resetWorld()
		else
			player:SetAttribute("Finished", false)
		end
		player:LoadCharacter()
	end
end)

-- Collision is the primary protection. This is a last-resort unstuck guard for
-- streaming/network glitches, not a substitute for the solid stair geometry.
local function keepInsideHotel(player, root)
	local first = math.max(0, state.opened - CONFIG.KeepBehind)
	local lastZ = state.opened == CONFIG.Doors and CONFIG.Doors * L + 34
		or math.min(CONFIG.Doors, state.opened + CONFIG.Ahead) * L
	local index = Layout.RoomIndexAt(root.Position.Z)
	local surfaceY = index >= CONFIG.Doors and Layout.EntranceY(CONFIG.Doors)
		or Layout.WalkwayY(index, root.Position.Z - index * L)
	if math.abs(root.Position.X) <= W / 2 + 1
		and root.Position.Z >= first * L - 1
		and root.Position.Z <= lastZ + 2
		and root.Position.Y >= surfaceY - 3 then return end
	local target = math.max(first, math.min(state.opened, CONFIG.Doors - 1))
	root.CFrame = CFrame.new(0, Layout.EntranceY(target) + 3, target * L + 6)
		* CFrame.Angles(0, math.pi, 0)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator = accumulator + dt
	if accumulator < 0.12 then return end
	local step = math.min(accumulator, 0.4)
	accumulator = 0
	for player, info in pairs(state.players) do
		local root, humanoid = playerRoot(player)
		if humanoid and not state.hidden[player] and not player:GetAttribute("Finished") then
			keepInsideHotel(player, root)
			-- MoveDirection is client-only on Roblox; replicated root velocity is
			-- the reliable server-side test for whether sprint drains stamina.
			local velocity = root.AssemblyLinearVelocity
			local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 1
			local running = info.sprinting and not info.crouching and info.stamina > 0.5 and moving
			if running then
				info.stamina = math.max(0, info.stamina - CONFIG.SprintDrain * step)
			else
				info.stamina = math.min(100, info.stamina + CONFIG.StaminaRegen * step)
			end
			local speed = info.crouching and CONFIG.CrouchSpeed or (running and CONFIG.SprintSpeed or CONFIG.WalkSpeed)
			if humanoid.WalkSpeed ~= speed then humanoid.WalkSpeed = speed end
			local rounded = math.floor(info.stamina + 0.5)
			if player:GetAttribute("Stamina") ~= rounded then player:SetAttribute("Stamina", rounded) end
		end
	end
end)

print("[NOCTURNE] 100 doors, 17 enclosed stairs, 10 turns; keys, hinged wardrobes and three threats ready.")
