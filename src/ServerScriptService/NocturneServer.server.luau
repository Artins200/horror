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
	SpawnDistance = 10, -- ordinary physical avatar on the first room's floor
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
	BlindLifetime = 24, -- enough time to track retreating players through stairs/doors
	MothLifetime = 18,
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
	plan = {},
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
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end
	if hum then
		hum.PlatformStand = false
		hum.WalkSpeed = CONFIG.WalkSpeed
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.AutoRotate = true
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
	local side = room.kind == "TURN" and Layout.TurnSide(room.index, state.seed) or 1
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
			for _, baseZ in ipairs({9, 32}) do
				local dz = baseZ + rng:NextNumber(-1.5, 1.5)
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
			for _, baseZ in ipairs({9, 32}) do
				makePainting(room, side, z + baseZ + rng:NextNumber(-2.1, 2.1),
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
			local dz = (side == -1 and 11 or 32) + rng:NextNumber(-1.2, 1.2)
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
			for _, baseZ in ipairs({10, 33}) do
				local dz = baseZ + rng:NextNumber(-1.4, 1.4)
				local x = side * 10.2
				roomBlock(room, "Shipping crate", 3.4, 3.2, 3.6, x, 1.6, z + dz,
					C.woodLight, Enum.Material.WoodPlanks)
				roomBlock(room, "Crate iron strap", 3.5, 0.17, 3.7, x, 2.5, z + dz,
					C.brassDark, Enum.Material.Metal)
			end
		end
	elseif kind == "DINING" then
		for _, baseZ in ipairs({12, 34}) do
			local dz = baseZ + rng:NextNumber(-1.2, 1.2)
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
				local frame = roomBlock(room, "Sealed window frame", 0.35, 7, 6.5, x, 8.9, z + dz,
					C.woodDark, Enum.Material.Wood)
				frame.CanCollide = false -- the sealed load-bearing wall still collides
				local glass = roomBlock(room, "Rain-stained opaque pane", 0.38, 5.8, 5.7,
					x - side * 0.22, 8.9, z + dz, Color3.fromRGB(48, 69, 65), Enum.Material.Glass)
				glass.Transparency = 0.28
				glass.CanCollide = false
				roomBlock(room, "Window mullion", 0.42, 5.8, 0.18, x - side * 0.45, 8.9,
					z + dz, C.brassDark, Enum.Material.Metal).CanCollide = false
				if dz ~= 20 then -- wardrobes and searchable drawers occupy this bay
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
		end
	elseif kind == "OFFICE" then
		for _, side in ipairs({-1, 1}) do
			for _, baseZ in ipairs({12, 33}) do
				local dz = baseZ + rng:NextNumber(-1.2, 1.2)
				roomBlock(room, "Clerk's desk", 3.3, 2.6, 4.2, side * 10.3, 1.3,
					z + dz, C.wood, Enum.Material.Wood)
				roomBlock(room, "Green leather writing pad", 2.6, 0.08, 3.1, side * 10.3, 2.64,
					z + dz, Color3.fromRGB(41, 62, 52), Enum.Material.Fabric)
				roomBlock(room, "Desk lamp stem", 0.14, 1.1, 0.14, side * 10.5, 3.2,
					z + dz + 1, C.brass, Enum.Material.Metal)
			end
		end
	elseif kind == "CHAPEL" then
		for _, side in ipairs({-1, 1}) do
			-- Leave the middle alcoves free for both wardrobe doors and the dresser.
			for _, baseZ in ipairs({9, 33, 38}) do
				local dz = baseZ + rng:NextNumber(-0.9, 0.9)
				roomBlock(room, "Ash-stained pew", 4.4, 0.46, 3.2,
					side * 10, 2.3, z + dz, C.woodDark, Enum.Material.Wood)
				roomBlock(room, "Carved pew back", 0.32, 3.3, 3.2,
					side * 12.1, 2.5, z + dz, C.woodLight, Enum.Material.Wood)
				for _, offset in ipairs({-1.3, 1.3}) do
					roomBlock(room, "Pew leg", 0.4, 2.1, 0.34,
						side * 10.9, 1.05, z + dz + offset, C.wood, Enum.Material.Wood)
				end
			end
		end
	elseif kind == "LAUNDRY" then
		for _, side in ipairs({-1, 1}) do
			for _, baseZ in ipairs({10, 32}) do
				local dz = baseZ + rng:NextNumber(-1.4, 1.4)
				local hamper = roomBlock(room, "Round wicker hamper", 3.0, 2.8, 2.8,
					side * 11.4, 1.5, z + dz, C.woodLight, Enum.Material.Wood)
				hamper.Shape = Enum.PartType.Cylinder
				hamper.CFrame = hamper.CFrame * CFrame.Angles(0, 0, math.pi / 2)
				local lid = roomBlock(room, "Shut hamper lid", 0.22, 3.0, 3.0,
					side * 11.4, 3.05, z + dz, C.brassDark, Enum.Material.Wood)
				lid.Shape = Enum.PartType.Cylinder
				lid.CFrame = lid.CFrame * CFrame.Angles(0, 0, math.pi / 2)
				local sheet = roomBlock(room, "Suspended aged linen", 0.16, rng:NextNumber(4.1, 6.3), 4.4,
					side * 12.8, 7.8, z + dz + 5, Color3.fromRGB(152, 151, 134), Enum.Material.Fabric)
				sheet.CanCollide = false
			end
		end
	elseif kind == "MIRROR" then
		for _, side in ipairs({-1, 1}) do
			for _, baseZ in ipairs({9, 33, 39}) do
				local dz = baseZ + rng:NextNumber(-1, 1)
				roomBlock(room, "Gilded standing mirror", 0.32, 8.7, 4.3,
					side * 13.8, 7.2, z + dz, C.brass, Enum.Material.Metal)
				local glass = roomBlock(room, "Clouded reflective glass", 0.12, 7.8, 3.6,
						side * 13.55, 7.2, z + dz, Color3.fromRGB(65, 79, 83), Enum.Material.Glass)
				glass.Reflectance = 0.24
				glass.CanCollide = false
			end
		end
	elseif kind == "TURN" then
		local side = Layout.TurnSide(room.index, state.seed)
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
			for _, baseZ in ipairs({12, 33}) do
				local dz = baseZ + rng:NextNumber(-1.5, 1.5)
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

local WALL_STYLES = {
	{wall = C.plaster, runner = C.carpet, trim = C.brassDark},
	{wall = Color3.fromRGB(38, 52, 49), runner = Color3.fromRGB(45, 52, 46), trim = Color3.fromRGB(89, 76, 54)},
	{wall = Color3.fromRGB(58, 52, 47), runner = Color3.fromRGB(81, 43, 38), trim = Color3.fromRGB(122, 94, 61)},
	{wall = Color3.fromRGB(38, 39, 55), runner = Color3.fromRGB(61, 31, 54), trim = Color3.fromRGB(89, 75, 101)},
}
local function flatRoom(room, rng)
	local model = room.model
	local z = room.index * L
	local y = room.entryY
	local style = WALL_STYLES[room.style]
	local wallColor = style.wall
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
			11.5, z + L / 2, style.trim, Enum.Material.Metal)
		roomBlock(room, "Gilded skirting", 0.3, 0.3, L - 0.7, side * (W / 2 - 0.92),
			0.18, z + L / 2, style.trim, Enum.Material.Metal)
		for _, dz in ipairs({5.5, 15, 29, 38.5}) do
			local shade = rng:NextInteger(-5, 5)
			local color = Color3.fromRGB(math.clamp(wallColor.R * 255 - 7 + shade, 0, 255),
				math.clamp(wallColor.G * 255 - 6 + shade, 0, 255),
				math.clamp(wallColor.B * 255 - 5 + shade, 0, 255))
			roomBlock(room, "Distressed wall panel", 0.08, 6.1, 7.0,
				side * (W / 2 - 0.84), 7.65, z + dz, color, Enum.Material.Concrete)
			roomBlock(room, "Gilt wall moulding", 0.17, 0.13, 7.2,
				side * (W / 2 - 0.89), 10.75, z + dz, style.trim, Enum.Material.Metal)
		end
		for _, dz in ipairs({12, 32}) do
			addLight(model, Vector3.new(side * (W / 2 - 2.5), y + 11.5,
				z + dz + rng:NextNumber(-1.7, 1.7)), room,
				rng:NextNumber(0.95, 1.75))
		end
	end
	for _, dz in ipairs({3.4, L / 2, L - 3.4}) do
		roomBlock(room, "Joined ceiling joist", W - 1.2, 0.36, 0.4,
			0, H - 0.12, z + dz, C.brassDark, Enum.Material.Metal)
	end
	if room.kind == "TURN" then
		local side = Layout.TurnSide(room.index, state.seed)
		local stops = {{0, 3}, {side * 8, 17}, {-side * 8, 28}, {0, 41}}
		for i = 2, #stops do
			local a, b = stops[i - 1], stops[i]
			local from = Vector3.new(a[1], y + 0.07, z + a[2])
			local to = Vector3.new(b[1], y + 0.07, z + b[2])
			local mid = (from + to) / 2
			local carpet = newPart(model, "Dogleg crimson runner", Vector3.new(6.2, 0.06, (to - from).Magnitude),
				CFrame.lookAt(mid, to), style.runner, Enum.Material.Fabric, 0, false)
			carpet.CanQuery = false
		end
	else
		local rug = roomBlock(room, "Worn crimson runner", 7.4, 0.06, L - 6,
			0, 0.055, z + L / 2, style.runner, Enum.Material.Fabric)
		rug.CanCollide = false
		for _, x in ipairs({-3.5, 3.5}) do
			local edging = roomBlock(room, "Runner gold edging", 0.1, 0.07, L - 6,
				x, 0.095, z + L / 2, style.trim, Enum.Material.Fabric)
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
		rng:NextNumber(0.65, 1.4))
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

-- Draw without replacement so the nine rooms of a bag don't repeat in a
-- fixed cycle, and the boundary between shuffled bags never repeats either.
-- Threats and keys have spaced random schedules; the first three encounters
-- stay predictable for teaching the player how to survive them.
local function planRooms(seed)
	local rng = Random.new(seed)
	local kinds = {"HALL", "LIBRARY", "GALLERY", "SUITE", "STORAGE", "FLOODED",
		"DINING", "CONSERVATORY", "OFFICE", "CHAPEL", "LAUNDRY", "MIRROR"}
	local threats = {"RUSH", "BLIND", "MOTH"}
	local bag, threatBag, previousKind, previousThreat = {}, {}, "HALL", nil
	local plan = {}
	local nextThreat, nextLock = 19, 4
	local function draw(pool, source, previous)
		if #pool == 0 then
			for _, value in ipairs(source) do table.insert(pool, value) end
		end
		local pick = rng:NextInteger(1, #pool)
		if #pool > 1 and pool[pick] == previous then pick = pick % #pool + 1 end
		return table.remove(pool, pick)
	end
	for index = 0, CONFIG.Doors - 1 do
		local stair, turn = Layout.IsStair(index), Layout.IsTurn(index, seed)
		local kind = stair and "STAIRWELL" or turn and "TURN" or index == 0 and "HALL"
		if not kind then
			kind = draw(bag, kinds, previousKind)
			previousKind = kind
		end
		local threat
		if index == 5 then threat = "RUSH"
		elseif index == 9 then threat = "BLIND"
		elseif index == 15 then threat = "MOTH"
		elseif index >= nextThreat and not stair and not turn then
			threat = draw(threatBag, threats, previousThreat)
			nextThreat = index + rng:NextInteger(3, 6)
		end
		if threat then previousThreat = threat end
		local locked = index >= nextLock and not stair and not turn and not threat
		if locked then nextLock = index + rng:NextInteger(5, 8) end
		plan[index] = {
			kind = kind, threat = threat, locked = locked,
			decorSeed = rng:NextInteger(1, 1000000000),
			style = rng:NextInteger(1, 4),
		}
	end
	return plan
end

buildRoom = function(index)
	if index < 0 or index >= CONFIG.Doors or state.rooms[index] then return end
	local z = index * L
	local plan = state.plan[index]
	local rng = Random.new(plan.decorSeed)
	local isStair = Layout.IsStair(index)
	local kind, threat, locked = plan.kind, plan.threat, plan.locked
	local model = Instance.new("Model")
	model.Name = string.format("Room_%03d_%s", index, kind)
	model:SetAttribute("RoomIndex", index)
	model:SetAttribute("Variant", kind)
	model:SetAttribute("Style", plan.style)
	model:SetAttribute("DecorSeed", plan.decorSeed)
	if Layout.IsTurn(index, state.seed) then model:SetAttribute("TurnSide", Layout.TurnSide(index, state.seed)) end
	model:SetAttribute("EntryY", Layout.EntranceY(index))
	model:SetAttribute("ExitY", Layout.ExitY(index))
	model:SetAttribute("Storey", math.floor(Layout.EntranceY(index) / Layout.StoreyRise) + 1)
	model:SetAttribute("Threat", threat or "NONE")
	model:SetAttribute("Locked", locked)
	model:SetAttribute("KeyFound", false)
	model.Parent = state.world
	local room = {
		index = index, model = model, kind = kind, style = plan.style,
		lamps = {}, closets = {}, entered = {},
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
		state.spawn.CFrame = CFrame.new(0, Layout.EntranceY(first) - 0.1, first * L + CONFIG.SpawnDistance)
			* CFrame.Angles(0, math.pi, 0)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local hiding = state.hidden[player]
		if hiding and hiding.closet.rootCF.Position.Z < first * L then leaveCloset(player, false) end
		local root = playerRoot(player)
		if root and root.Position.Z < first * L + 5 then
			root.CFrame = CFrame.new(0, Layout.EntranceY(first) + 3, first * L + CONFIG.SpawnDistance)
				* CFrame.Angles(0, math.pi, 0)
		end
	end
	for index, room in pairs(state.rooms) do
		local chased = state.rush and index >= state.rush.origin and index <= state.rush.limit
		local patrolled = state.blind and index >= state.blind.index - 3
			and index <= state.blind.index + 1
		local attracted = state.moth and index >= state.moth.index - 3
			and index <= state.moth.index + 1
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

-- Three entirely self-contained creature silhouettes. Their smooth parts and
-- surface details are display-only: damage is still decided by the server's
-- corridor-aware threat logic, not invisible collision on their appendages.
local function creaturePart(parent, name, size, cf, color, material, alpha, shape)
	local part = newPart(parent, name, size, cf, color, material, alpha or 0, false)
	if shape then part.Shape = shape end
	return part
end
local function creatureLimb(parent, name, from, to, width, color, material, alpha)
	local delta = to - from
	return creaturePart(parent, name, Vector3.new(delta.Magnitude, width, width),
		CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.pi / 2, 0),
		color, material or Enum.Material.SmoothPlastic, alpha, Enum.PartType.Cylinder)
end
local function creatureHalo(entity, fill, outline)
	local halo = Instance.new("Highlight")
	halo.Name = "Occluded silhouette edge"
	halo.Adornee = entity
	halo.DepthMode = Enum.HighlightDepthMode.Occluded
	halo.FillColor = fill
	halo.FillTransparency = 0.94
	halo.OutlineColor = outline
	halo.OutlineTransparency = 0.37
	halo.Parent = entity
end
local function creatureMist(part, name, offset, tint, rate, scale)
	local attachment = Instance.new("Attachment")
	attachment.Name = name .. " origin"
	attachment.Position = offset
	attachment.Parent = part
	local mist = Instance.new("ParticleEmitter")
	mist.Name = name
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(tint)
	mist.Transparency = NumberSequence.new(0.52, 1)
	mist.Size = NumberSequence.new(scale, scale * 1.65)
	mist.Rate = rate
	mist.Lifetime = NumberRange.new(0.45, 1.05)
	mist.Speed = NumberRange.new(0.3, 1.25)
	mist.SpreadAngle = Vector2.new(95, 95)
	mist.LightEmission = 0.08
	mist.Parent = attachment
end

-- Rush: foretold only by LIGHT, never by a warning sound. It starts three
-- rooms behind, navigates the enclosed stairs and offset archways, and keeps
-- chasing through doors opened while it is moving. A single door is no refuge.
local function makeRush()
	local entity = Instance.new("Model")
	entity.Name = "TheRush"
	entity.Parent = state.world
	local soot = Color3.fromRGB(16, 19, 23)
	local ash = Color3.fromRGB(41, 42, 45)
	local bone = Color3.fromRGB(123, 113, 100)
	local ember = Color3.fromRGB(222, 78, 48)
	local torso = creaturePart(entity, "Hollow black chest", Vector3.new(3.1, 5.2, 1.85),
		CFrame.new(0, 0.15, 0), soot, Enum.Material.Slate, 0.02, Enum.PartType.Ball)
	entity.PrimaryPart = torso
	creaturePart(entity, "Streaming coat tail", Vector3.new(3.9, 5.4, 1.55),
		CFrame.new(0, -1.3, 0.75) * CFrame.Angles(math.rad(8), 0, 0),
		ash, Enum.Material.Fabric, 0.16, Enum.PartType.Ball)
	local claws = {}
	for _, side in ipairs({-1, 1}) do
		local claw = Instance.new("Model")
		claw.Name = side == -1 and "Left hooked arm" or "Right hooked arm"
		claw.Parent = entity
		local hinge = CFrame.new(side * 1.55, 1.65, 0)
		claw.WorldPivot = hinge
		table.insert(claws, {model = claw, hinge = hinge, side = side})
		creaturePart(claw, "Raised crooked shoulder", Vector3.new(1.4, 1.6, 1.5),
			CFrame.new(side * 1.55, 1.65, 0), ash, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(claw, "Long upper arm", Vector3.new(side * 1.7, 1.4, -0.1),
			Vector3.new(side * 2.75, -0.35, -0.62), 0.63, soot)
		creaturePart(claw, "Knotted elbow", Vector3.new(0.7, 0.75, 0.7),
			CFrame.new(side * 2.75, -0.35, -0.62), ash, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(claw, "Sweeping forearm", Vector3.new(side * 2.75, -0.35, -0.62),
			Vector3.new(side * 3.0, -2.35, -1.45), 0.47, soot)
		for finger = 1, 3 do
			local spread = (finger - 2) * 0.33
			creatureLimb(claw, "Three hooked talons", Vector3.new(side * 3.0 + spread, -2.33, -1.42),
				Vector3.new(side * 3.3 + spread * 1.3, -3.22 - finger * 0.12, -2.04),
				0.13, bone, Enum.Material.Slate)
		end
		creatureLimb(entity, "Uneven trailing leg", Vector3.new(side * 0.79, -1.75, 0.18),
			Vector3.new(side * 1.14, -3.75, 0.65), 0.68, soot)
		creaturePart(entity, "Bare dragging foot", Vector3.new(1.45, 0.45, 1.65),
			CFrame.new(side * 1.15, -4.01, -0.13), soot,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		for rib = 1, 3 do
			creatureLimb(entity, "Exposed broken rib", Vector3.new(side * 0.29, 0.88 - rib * 0.72, -0.95),
				Vector3.new(side * 1.37, 1.12 - rib * 0.72, -0.56),
				0.14, ash, Enum.Material.Slate)
		end
	end
	local skull = creaturePart(entity, "Cracked funeral mask", Vector3.new(2.27, 2.55, 1.72),
		CFrame.new(0, 3.22, -0.46) * CFrame.Angles(math.rad(-9), 0, 0),
		bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
	for _, side in ipairs({-1, 1}) do
		creaturePart(entity, "Hollow eye socket", Vector3.new(0.68, 0.72, 0.19),
			CFrame.new(side * 0.52, 3.47, -1.29), soot,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		creaturePart(entity, "Dim ember behind bone", Vector3.new(0.21, 0.3, 0.13),
			CFrame.new(side * 0.53, 3.48, -1.4), ember,
			Enum.Material.Neon, 0.05, Enum.PartType.Ball)
		creatureLimb(entity, "Split antler of soot", Vector3.new(side * 0.7, 4.13, -0.2),
			Vector3.new(side * 1.31, 5.05, 0.25), 0.23, soot, Enum.Material.Slate)
	end
	creaturePart(entity, "Open dark jaw", Vector3.new(1.12, 0.62, 0.17),
		CFrame.new(0, 2.41, -1.29), soot, Enum.Material.Slate, 0, Enum.PartType.Ball)
	for tooth = -2, 2 do
		creaturePart(entity, "Uneven bone tooth", Vector3.new(0.14, 0.26, 0.1),
			CFrame.new(tooth * 0.2, 2.51 - math.abs(tooth) * 0.04, -1.39),
			bone, Enum.Material.Slate)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Embers through the mask"
	glow.Color = ember
	glow.Brightness = 1.4
	glow.Range = 12
	glow.Parent = skull
	creatureHalo(entity, Color3.fromRGB(28, 13, 18), Color3.fromRGB(127, 44, 42))
	-- The body's narrow silhouette is followed by a wide, thin ash wake:
	-- it suggests the room-wide danger without a flat opaque wall of parts.
	for _, x in ipairs({-9, -4.5, 0, 4.5, 9}) do
		creatureMist(torso, "Cold ash wake", Vector3.new(x, -1.8, 1.5),
			Color3.fromRGB(33, 30, 36), x == 0 and 28 or 13, x == 0 and 3.0 or 2.1)
	end
	return entity, claws, glow
end

local function pathPoint(z)
	local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(z))
	local localZ = math.clamp(z - index * L, 0, L)
	return Vector3.new(Layout.PathX(index, localZ, state.seed), Layout.WalkwayY(index, localZ) + 5, z)
end

local function killPlayer(player, humanoid, kind, entity)
	if humanoid.Health <= 0 then return end
	-- The victim's own client gets the ACTUAL creature for a close-up. Keep its
	-- model replicated until the scare ends, even if the patrol ends this frame.
	if entity then entity:SetAttribute("RecentKill", true) end
	remote:FireClient(player, "Jumpscare", kind, entity)
	humanoid.Health = 0
end
local function retireMonster(entity)
	if not entity.Parent then return end
	if entity:GetAttribute("RecentKill") then
		task.delay(1.6, function() if entity.Parent then entity:Destroy() end end)
	else
		entity:Destroy()
	end
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
	local entity, claws, glow = makeRush()
	local z = rush.positionZ
	entity:PivotTo(CFrame.lookAt(pathPoint(z), pathPoint(z) + Vector3.new(0, 0, 1)))
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
		local facing = CFrame.lookAt(point, point + Vector3.new(ahead.X - point.X, 0, 1))
		entity:PivotTo(facing)
		-- Its hooked arms flail as it rushes; only the visual models move.
		for _, claw in ipairs(claws) do
			claw.model:PivotTo(facing * claw.hinge * CFrame.Angles(
				math.sin(elapsed * 11 + claw.side) * 0.42, 0,
				claw.side * math.sin(elapsed * 8) * 0.17))
		end
		glow.Brightness = 1.15 + math.sin(elapsed * 15) * 0.25
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = playerRoot(player)
			if root and not state.hidden[player] and root.Position.Z >= previous - 4.5
				and root.Position.Z <= z + 4.5 then
				local crossing = pathPoint(math.clamp(root.Position.Z, previous, z))
				-- The wake sweeps the enclosed width, including side alcoves;
				-- only an occupied wardrobe grants shelter from this creature.
				if math.abs(root.Position.X) < W / 2 - 0.7
					and math.abs(root.Position.Y - (crossing.Y - 2)) < 5.5 then
					killPlayer(player, humanoid, "RUSH", entity)
				end
			end
		end
		if z >= allowed - 0.01 then stalled = stalled + dt else stalled = 0 end
		if z >= maxZ - 0.01 or stalled > 2.6 then break end
	end
	retireMonster(entity)
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

-- All roaming threats use the same door/archway centres. They may pursue a
-- player into THREE previous rooms or the next opened room, including stairs
-- and turns, but may not cut through masonry or the pruned rear boundary.
local function roamBounds(room)
	local first = math.max(0, state.opened - CONFIG.KeepBehind)
	return math.max(first, room.index - 3) * L + 4,
		math.min((room.index + 2) * L - 4, (state.opened + 1) * L - 4)
end
local function gateAhead(fromZ, toZ)
	local direction = toZ >= fromZ and 1 or -1
	local low = math.max(0, math.floor(math.min(fromZ, toZ) / L) - 1)
	local high = math.min(CONFIG.Doors - 1, math.floor(math.max(fromZ, toZ) / L) + 1)
	local nearest
	local function consider(z, x, room)
		if (direction == 1 and z > fromZ + 0.01 and z < toZ
			or direction == -1 and z < fromZ - 0.01 and z > toZ)
			and (not nearest or math.abs(z - fromZ) < math.abs(nearest.z - fromZ)) then
			nearest = {z = z, x = x, room = room}
		end
	end
	for index = low, high do
		if index > 0 then consider(index * L, 0, state.rooms[index - 1]) end
		if Layout.IsTurn(index, state.seed) then
			local side = Layout.TurnSide(index, state.seed)
			consider(index * L + 17, side * 8)
			consider(index * L + 28, -side * 8)
		end
	end
	return nearest, direction
end
local function walkRoute(position, destination, speed, dt, height)
	local gate, direction = gateAhead(position.Z, destination.Z)
	local x, z
	if gate then
		local holding = gate.z - direction * 2.5
		if gate.room and not gate.room.open then
			if math.abs(position.Z - gate.z) < 8 and not gate.room.busy then
				swingDoor(gate.room, true) -- a previously closed door is not a magic shield
			end
			z = holding
		elseif (gate.z - position.Z) * direction > 2.6
			or math.abs(position.X - gate.x) > 0.65 then
			z = holding -- line up with the clear opening BEFORE crossing its wall
		else
			z = gate.z + direction * 2.5
		end
		x = gate.x
	else
		z = destination.Z
		local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(z))
		x = Layout.PathX(index, math.clamp(z - index * L, 0, L), state.seed)
		-- Only close in sideways when both are within one unobstructed bay.
		local here = Layout.RoomIndexAt(position.Z)
		if here == index and math.abs(destination.Z - position.Z) < 10 then
			local localZ = z - index * L
			local hereZ = position.Z - index * L
			local sameBay = not Layout.IsTurn(index, state.seed)
				or (localZ < 14 and hereZ < 14)
				or (localZ > 20 and localZ < 25 and hereZ > 20 and hereZ < 25)
				or (localZ > 31 and hereZ > 31)
			if sameBay and not Layout.IsStair(index) then
				x = math.clamp(destination.X, -10.5, 10.5)
			end
		end
	end
	local dx, dz = x - position.X, z - position.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.02 then return position, nil end
	local step = math.min(length, speed * dt)
	local newX = position.X + dx / length * step
	local newZ = position.Z + dz / length * step
	local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(newZ))
	local floorY = Layout.WalkwayY(index, math.clamp(newZ - index * L, 0, L))
	return Vector3.new(newX, floorY + height, newZ), Vector3.new(dx, 0, dz)
end
local function roamingTarget(position, nearZ, farZ, patrolZ, kind)
	local destination, nearest = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		local info = state.players[player]
		if root and info and root.Position.Z >= nearZ and root.Position.Z <= farZ then
			local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(root.Position.Z))
			local floorY = Layout.WalkwayY(index, root.Position.Z - index * L)
			local awake = kind == "BLIND" and (state.hidden[player] or not info.crouching)
				or kind == "MOTH" and info.torchOn and not state.hidden[player]
			if math.abs(root.Position.Y - floorY - 3) < 5 and awake then
				local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if delta.Magnitude < nearest then
					nearest = delta.Magnitude
					destination = root.Position
				end
			end
		end
	end
	return destination or Vector3.new(0, position.Y, patrolZ), nearest
end

-- The Blind Guest comes FROM the room ahead. It cannot see a silent crouching
-- player, but hears footsteps and occupied wardrobes even across open doors.
local function makeBlind()
	local entity = Instance.new("Model")
	entity.Name = "TheBlindGuest"
	entity.Parent = state.world
	local wool = Color3.fromRGB(42, 50, 51)
	local fold = Color3.fromRGB(61, 70, 69)
	local dark = Color3.fromRGB(21, 29, 31)
	local brass = Color3.fromRGB(123, 109, 78)
	local skin = Color3.fromRGB(126, 132, 120)
	local ivory = Color3.fromRGB(199, 195, 175)
	local boneShade = Color3.fromRGB(147, 154, 139)
	local chest = creaturePart(entity, "Tailored wool chest", Vector3.new(2.5, 3.5, 1.35),
		CFrame.new(0, 0.82, 0.12), wool, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	entity.PrimaryPart = chest
	creaturePart(entity, "Narrow velvet waistcoat", Vector3.new(1.55, 3.02, 0.6),
		CFrame.new(0, 0.57, -0.52), dark, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	creaturePart(entity, "Rounded collar around the throat", Vector3.new(2.16, 0.83, 1.4),
		CFrame.new(0, 2.12, 0.12), dark, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	for foldIndex = -2, 2 do
		local offset = foldIndex * 0.47
		creaturePart(entity, "Overlapping hanging coat fold", Vector3.new(0.92, 3.5 + math.abs(offset) * 0.18, 1.24),
			CFrame.new(offset, -1.78 + math.abs(offset) * 0.14, 0.11 + math.abs(offset) * 0.13)
				* CFrame.Angles(0, 0, offset * 0.085),
			math.abs(foldIndex) % 2 == 0 and wool or fold, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	end
	for _, side in ipairs({-1, 1}) do
		creatureLimb(entity, "Slanted ivory lapel", Vector3.new(side * 0.31, 2.07, -0.57),
			Vector3.new(side * 0.88, -0.36, -0.81), 0.28, boneShade, Enum.Material.Fabric)
		creaturePart(entity, "Fabric lapel fold", Vector3.new(0.46, 1.55, 0.21),
			CFrame.new(side * 0.61, 0.95, -0.74) * CFrame.Angles(0, 0, side * 0.2),
			fold, Enum.Material.Fabric, 0, Enum.PartType.Ball)
		creaturePart(entity, "Stitched waist pocket", Vector3.new(0.53, 0.13, 0.19),
			CFrame.new(side * 0.87, -0.56, -0.52), brass, Enum.Material.Metal, 0, Enum.PartType.Ball)
		creaturePart(entity, "Rounded uniform epaulette", Vector3.new(1.16, 0.32, 1.02),
			CFrame.new(side * 1.18, 1.86, -0.01), fold, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	end
	for button = 0, 4 do
		local stud = creaturePart(entity, "Five tarnished uniform buttons", Vector3.new(0.15, 0.15, 0.13),
			CFrame.new(0, 1.49 - button * 0.56, -0.86), brass, Enum.Material.Metal, 0, Enum.PartType.Ball)
		stud.Reflectance = 0.08
	end
	local limbs = {}
	for _, side in ipairs({-1, 1}) do
		local arm = Instance.new("Model")
		arm.Name = side == -1 and "Left articulated sleeve" or "Right articulated sleeve"
		arm.Parent = entity
		local armHinge = CFrame.new(side * 1.17, 1.69, 0)
		arm.WorldPivot = armHinge
		table.insert(limbs, {model = arm, hinge = armHinge, side = side, sway = 0.12})
		creaturePart(arm, "Soft round shoulder", Vector3.new(1.1, 1.18, 1.12),
			CFrame.new(side * 1.18, 1.59, 0.04), wool, Enum.Material.Fabric, 0, Enum.PartType.Ball)
		creaturePart(arm, "Tapered wool upper sleeve", Vector3.new(0.88, 2.55, 0.94),
			CFrame.new(side * 1.45, 0.37, -0.16) * CFrame.Angles(0, 0, side * -0.12),
			wool, Enum.Material.Fabric, 0, Enum.PartType.Ball)
		creaturePart(arm, "Faded sleeve cuff", Vector3.new(0.66, 0.38, 0.68),
			CFrame.new(side * 1.61, -0.87, -0.43), fold, Enum.Material.Fabric, 0, Enum.PartType.Ball)
		creaturePart(arm, "Pale articulated forearm", Vector3.new(0.44, 1.35, 0.48),
			CFrame.new(side * 1.77, -1.49, -0.79) * CFrame.Angles(math.rad(-16), 0, 0),
			skin, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
		creaturePart(arm, "Knuckled gloved palm", Vector3.new(0.63, 0.4, 0.54),
			CFrame.new(side * 1.87, -2.12, -1.05), skin, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
		for finger = 1, 4 do
			local offset = (finger - 2.5) * 0.15
			creatureLimb(arm, "Four delicate searching fingers",
				Vector3.new(side * 1.87 + offset, -2.25, -1.04),
				Vector3.new(side * 1.94 + offset * 1.17, -2.87 - math.abs(offset), -1.4),
				0.1, skin)
		end
		local leg = Instance.new("Model")
		leg.Name = side == -1 and "Left walking leg" or "Right walking leg"
		leg.Parent = entity
		local legHinge = CFrame.new(side * 0.55, -1.72, 0.1)
		leg.WorldPivot = legHinge
		table.insert(limbs, {model = leg, hinge = legHinge, side = -side, sway = 0.17})
		creaturePart(leg, "Pressed dark trouser", Vector3.new(0.84, 2.31, 0.89),
			CFrame.new(side * 0.54, -2.64, 0.15), dark, Enum.Material.Fabric, 0, Enum.PartType.Ball)
		creaturePart(leg, "Well-worn leather shoe", Vector3.new(0.95, 0.53, 1.5),
			CFrame.new(side * 0.54, -4.15, -0.42), dark, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
	end
	local head = Instance.new("Model")
	head.Name = "Searching mask and neck"
	head.Parent = entity
	local hinge = CFrame.new(0, 2.37, -0.03)
	head.WorldPivot = hinge
	creaturePart(head, "Sinewed narrow neck", Vector3.new(0.69, 1.0, 0.73),
		CFrame.new(0, 2.46, -0.1), skin, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
	creaturePart(head, "Dark fabric hood", Vector3.new(2.0, 2.62, 1.66),
		CFrame.new(0, 3.57, 0.13), dark, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	local mask = creaturePart(head, "Sculpted ivory eyeless face", Vector3.new(1.64, 2.18, 1.06),
		CFrame.new(0, 3.51, -0.44) * CFrame.Angles(math.rad(-7), 0, 0),
		ivory, Enum.Material.Slate, 0, Enum.PartType.Ball)
	creaturePart(head, "High smooth forehead", Vector3.new(1.43, 0.82, 0.86),
		CFrame.new(0, 4.12, -0.56), ivory, Enum.Material.Slate, 0, Enum.PartType.Ball)
	for _, side in ipairs({-1, 1}) do
		creaturePart(head, "Hollow under the sealed eyelid", Vector3.new(0.53, 0.35, 0.13),
			CFrame.new(side * 0.39, 3.69, -0.963) * CFrame.Angles(0, 0, side * 0.13),
			dark, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creaturePart(head, "Sculpted cheekbone", Vector3.new(0.46, 0.46, 0.24),
			CFrame.new(side * 0.46, 3.23, -0.91), ivory, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(head, "Long arched eyebrow", Vector3.new(side * 0.13, 3.89, -0.94),
			Vector3.new(side * 0.69, 3.83, -0.87), 0.12, boneShade, Enum.Material.Slate)
		creatureLimb(head, "Tight eyelid seam", Vector3.new(side * 0.15, 3.7, -1.045),
			Vector3.new(side * 0.67, 3.66, -0.998), 0.07, skin, Enum.Material.Fabric)
		for stitch = 1, 4 do
			local x = side * (0.16 + stitch * 0.105)
			creatureLimb(head, "Hand-sewn eyelid stitch", Vector3.new(x, 3.78, -1.057),
				Vector3.new(x + side * 0.035, 3.6, -1.049), 0.039, dark)
		end
		creatureLimb(head, "Porcelain hairline fissure", Vector3.new(side * 0.64, 4.12, -0.8),
			Vector3.new(side * 0.5, 3.99, -0.95), 0.045, boneShade, Enum.Material.Slate)
	end
	creaturePart(head, "Gracefully tapered nose", Vector3.new(0.27, 0.84, 0.27),
		CFrame.new(0, 3.42, -1.04), boneShade, Enum.Material.Slate, 0, Enum.PartType.Ball)
	creaturePart(head, "Mouth hidden under frayed cloth", Vector3.new(0.9, 0.33, 0.24),
		CFrame.new(0, 2.95, -0.94), fold, Enum.Material.Fabric, 0, Enum.PartType.Ball)
	for stripe = 1, 3 do
		creatureLimb(head, "Frayed cloth wrapping", Vector3.new(-0.41, 2.9 + stripe * 0.065, -1.03),
			Vector3.new(0.42, 2.96 + stripe * 0.055, -1.03), 0.055, skin, Enum.Material.Fabric)
	end
	local light = Instance.new("PointLight")
	light.Name = "Pallid rim around the sculpted face"
	light.Color = Color3.fromRGB(177, 202, 181)
	light.Brightness = 0.7
	light.Range = 9
	light.Parent = mask
	creatureHalo(entity, Color3.fromRGB(52, 66, 61), Color3.fromRGB(170, 195, 171))
	creatureMist(chest, "Faint dust on the coat", Vector3.new(0, 0.3, 0.4),
		Color3.fromRGB(117, 130, 119), 5, 0.65)
	return entity, head, hinge, limbs
end

startBlind = function(room, epoch)
	if epoch ~= session or state.blind then return end
	state.blind = {index = room.index}
	remote:FireAllClients("Warning", "BLIND", room.index)
	for _, lamp in ipairs(room.lamps) do
		if lamp.light.Parent then lamp.light.Brightness = lamp.brightness * 0.45 end
	end
	task.wait(0.8)
	if epoch ~= session then return end
	local entity, mask, maskHinge, limbs = makeBlind()
	local startZ = room.index * L
	local position = Vector3.new(0, room.entryY + 4.7, startZ + 35)
	entity:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	local patrolZ = startZ + 7 -- walk from the FAR end to the entry and back
	local elapsed = 0
	while epoch == session and elapsed < CONFIG.BlindLifetime do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
		if epoch ~= session then break end
		elapsed = elapsed + dt
		local nearZ, farZ = roamBounds(room)
		local destination, nearest = roamingTarget(position, nearZ, farZ, patrolZ, "BLIND")
		if nearest == math.huge and math.abs(position.Z - patrolZ) < 1.1 then
			patrolZ = patrolZ == startZ + 7 and startZ + 37 or startZ + 7
			destination = Vector3.new(0, position.Y, patrolZ)
		end
		local old = position
		position = walkRoute(position, destination, nearest < math.huge and 19 or 9, dt, 4.7)
		local heading = Vector3.new(position.X - old.X, 0, position.Z - old.Z)
		if heading.Magnitude > 0.01 then
			local facing = CFrame.lookAt(position, position + heading)
			entity:PivotTo(facing)
			-- It tilts its head to listen while its shoulders and feet walk.
			mask:PivotTo(facing * maskHinge
				* CFrame.Angles(0, math.sin(elapsed * 1.7) * 0.17, math.sin(elapsed * 2.3) * 0.04))
			for _, limb in ipairs(limbs) do
				limb.model:PivotTo(facing * limb.hinge * CFrame.Angles(
					math.sin(elapsed * 6.6 + (limb.side == -1 and 0 or math.pi)) * limb.sway, 0, 0))
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = playerRoot(player)
			if root and root.Position.Z >= nearZ and root.Position.Z <= farZ then
				local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(root.Position.Z))
				local floorY = Layout.WalkwayY(index, root.Position.Z - index * L)
				if math.abs(root.Position.Y - floorY - 3) < 5 then
					local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
					local hiding = state.hidden[player]
					if hiding and delta.Magnitude < 7 and not hiding.closet.inspected then
						hiding.closet.inspected = true
						swingCloset(hiding.closet, true)
					end
					-- Contact is lethal even for crouching players in the PREVIOUS room.
					if delta.Magnitude < (hiding and 5.1 or 3.7) then
						killPlayer(player, humanoid, "BLIND", entity)
					end
				end
			end
		end
	end
	retireMonster(entity)
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
	local ivory = Color3.fromRGB(176, 189, 176)
	local wingIvory = Color3.fromRGB(119, 150, 140)
	local vein = Color3.fromRGB(67, 91, 86)
	local eyeColor = Color3.fromRGB(30, 51, 52)
	local glowColor = Color3.fromRGB(154, 223, 191)
	local core = creaturePart(entity, "Ribbed pale thorax", Vector3.new(2.1, 4.7, 1.52),
		CFrame.new(0, 0.1, 0), ivory, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
	entity.PrimaryPart = core
	creaturePart(entity, "Fine fur at the neck", Vector3.new(2.95, 1.53, 1.58),
		CFrame.new(0, 1.7, 0.1), ivory, Enum.Material.Fabric, 0.04, Enum.PartType.Ball)
	local mask = creaturePart(entity, "Still insect face", Vector3.new(1.72, 1.88, 1.3),
		CFrame.new(0, 2.89, -0.2), Color3.fromRGB(189, 201, 180),
		Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
	for _, side in ipairs({-1, 1}) do
		creaturePart(entity, "Black compound eye", Vector3.new(0.62, 0.84, 0.21),
			CFrame.new(side * 0.51, 3.05, -0.82) * CFrame.Angles(0, 0, side * 0.17),
			eyeColor, Enum.Material.Glass, 0.11, Enum.PartType.Ball)
		creaturePart(entity, "Light caught in the eye", Vector3.new(0.1, 0.21, 0.07),
			CFrame.new(side * 0.6, 3.26, -0.99), glowColor,
			Enum.Material.Neon, 0.22, Enum.PartType.Ball)
		creatureLimb(entity, "Feathered feeler", Vector3.new(side * 0.32, 3.62, -0.06),
			Vector3.new(side * 1.17, 4.63, -0.37), 0.17, vein, Enum.Material.Fabric)
		for n = 1, 3 do
			local x = side * (0.55 + n * 0.18)
			creatureLimb(entity, "Feeler bristle", Vector3.new(x, 3.9 + n * 0.21, -0.21),
				Vector3.new(x + side * 0.28, 4.28 + n * 0.24, -0.29),
				0.065, ivory, Enum.Material.Fabric)
		end
		creatureLimb(entity, "Folded praying forearm", Vector3.new(side * 0.92, 1.14, -0.29),
			Vector3.new(side * 1.12, -0.83, -1.12), 0.26, ivory)
		creatureLimb(entity, "Delicate lower limb", Vector3.new(side * 0.58, -1.67, -0.1),
			Vector3.new(side * 0.86, -4.34, -0.35), 0.22, vein)
		for claw = 1, 3 do
			creatureLimb(entity, "Fine hanging claw", Vector3.new(side * 1.12 + (claw - 2) * 0.14, -0.78, -1.13),
				Vector3.new(side * 1.15 + (claw - 2) * 0.17, -1.45, -1.61),
				0.095, vein)
		end
	end
	for stripe = 1, 5 do
		creaturePart(entity, "Abdomen seam", Vector3.new(1.5 - stripe * 0.06, 0.09, 0.32),
			CFrame.new(0, 0.4 - stripe * 0.55, -0.72), vein,
			Enum.Material.SmoothPlastic, 0.12, Enum.PartType.Ball)
	end
	-- Four overlapping, veined translucent wings instead of flat rectangles.
	-- Each side pivots at its thorax and flaps independently during the hunt.
	local wings = {}
	for _, side in ipairs({-1, 1}) do
		local wing = Instance.new("Model")
		wing.Name = side == -1 and "Veiled left wing" or "Veiled right wing"
		wing.Parent = entity
		local hinge = CFrame.new(side * 0.94, 0.75, 0.42)
		wing.WorldPivot = hinge
		for _, lobe in ipairs({{2.99, 1.72, 4.6, 3.3}, {2.74, -1.27, 4.17, 2.92}}) do
			local wingCF = CFrame.new(side * lobe[1], lobe[2], 0.59)
				* CFrame.Angles(0, side * 0.12, side * 0.18)
			local plate = creaturePart(wing, "Soft layered wing", Vector3.new(lobe[3], lobe[4], 0.23),
				wingCF, wingIvory, Enum.Material.Glass, 0.22, Enum.PartType.Ball)
			plate.CastShadow = false
			creaturePart(wing, "Dark eye on the wing", Vector3.new(0.86, 0.88, 0.11),
				CFrame.new(side * (lobe[1] + 0.57), lobe[2] + 0.13, 0.39), eyeColor,
				Enum.Material.Slate, 0.1, Enum.PartType.Ball)
			creaturePart(wing, "Pale ring round the wing eye", Vector3.new(1.08, 1.1, 0.08),
				CFrame.new(side * (lobe[1] + 0.57), lobe[2] + 0.13, 0.44), glowColor,
				Enum.Material.Neon, 0.39, Enum.PartType.Ball)
			creatureLimb(wing, "Wing main vein", Vector3.new(side * 1.0, 0.75, 0.4),
				Vector3.new(side * (lobe[1] + 1.35), lobe[2] + 0.58, 0.43),
				0.12, vein, Enum.Material.SmoothPlastic, 0.22)
		end
		for n = 1, 3 do
			creatureLimb(wing, "Radiating wing vein", Vector3.new(side * 1.45, 0.55, 0.36),
				Vector3.new(side * (3.1 + n * 0.46), 2.14 - n * 0.85, 0.41),
				0.075, vein, Enum.Material.SmoothPlastic, 0.22)
		end
		table.insert(wings, {model = wing, hinge = hinge, side = side})
	end
	local light = Instance.new("PointLight")
	light.Name = "Moth phosphor glow"
	light.Color = glowColor
	light.Brightness = 1.15
	light.Range = 14
	light.Parent = mask
	creatureHalo(entity, Color3.fromRGB(50, 81, 73), Color3.fromRGB(140, 194, 171))
	creatureMist(core, "Quiet moth dust", Vector3.new(0, -0.25, 0.5),
		glowColor, 11, 0.85)
	return entity, wings
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
	local entity, wings = makeMoth()
	local startZ = room.index * L
	local position = Vector3.new(0, room.entryY + 6.5, startZ + 32)
	entity:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	local patrolZ = startZ + 9
	local elapsed = 0
	while epoch == session and elapsed < CONFIG.MothLifetime do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
		if epoch ~= session then break end
		elapsed = elapsed + dt
		local nearZ, farZ = roamBounds(room)
		local destination, nearest = roamingTarget(position, nearZ, farZ, patrolZ, "MOTH")
		if nearest == math.huge and math.abs(position.Z - patrolZ) < 1.1 then
			patrolZ = patrolZ == startZ + 9 and startZ + 36 or startZ + 9
			destination = Vector3.new(0, position.Y, patrolZ)
		end
		local old = position
		local onRoute = walkRoute(position, destination, nearest < math.huge and 26 or 9, dt, 6.5)
		position = Vector3.new(onRoute.X, onRoute.Y + math.sin(elapsed * 4.1) * 0.28, onRoute.Z)
		local heading = Vector3.new(position.X - old.X, 0, position.Z - old.Z)
		if heading.Magnitude > 0.01 then
			local facing = CFrame.lookAt(position, position + heading)
			entity:PivotTo(facing)
			for _, wing in ipairs(wings) do
				wing.model:PivotTo(facing * wing.hinge * CFrame.Angles(
					0, wing.side * math.sin(elapsed * 5.2) * 0.17,
					wing.side * (0.09 + math.sin(elapsed * 6.3) * 0.25)))
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local root, humanoid = playerRoot(player)
			local info = state.players[player]
			if root and info and info.torchOn and not state.hidden[player]
				and root.Position.Z >= nearZ and root.Position.Z <= farZ then
				local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(root.Position.Z))
				local floorY = Layout.WalkwayY(index, root.Position.Z - index * L)
				if math.abs(root.Position.Y - floorY - 3) < 5 then
					local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
					if delta.Magnitude < 5.3 then killPlayer(player, humanoid, "MOTH", entity) end
				end
			end
		end
	end
	retireMonster(entity)
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
	local previousSeed = state.seed
	state.seed = CONFIG.Seed or Random.new():NextInteger(1, 1000000000)
	if not CONFIG.Seed and state.seed == previousSeed then
		state.seed = state.seed % 1000000000 + 1
	end
	state.plan = planRooms(state.seed)
	state.world:SetAttribute("Seed", state.seed)
	state.world:SetAttribute("CameraBuild", "NativeFirstPerson-v5")
	state.world:SetAttribute("DoorsOpened", 0)
	state.world:SetAttribute("TotalDoors", CONFIG.Doors)
	state.world:SetAttribute("Storeys", math.floor(Layout.EntranceY(CONFIG.Doors) / Layout.StoreyRise) + 1)
	buildRoom(0)
	buildRoom(1)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CheckpointSpawn"
	-- Standard Roblox spawn pad: its top is flush with the colliding subfloor
	-- rather than hidden below it. The avatar is a real, visible character.
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = CFrame.new(0, Layout.EntranceY(0) - 0.1, CONFIG.SpawnDistance)
		* CFrame.Angles(0, math.pi, 0)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = state.world
	state.spawn = spawn
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = spawn
		player:SetAttribute("Hidden", false)
		player:SetAttribute("Finished", false)
		remote:FireClient(player, "State", state.opened, state.seed, L)
	end
end

-- Preserve ordinary falling/ground contact even if a Studio template had
-- zero gravity; the binary place also stores Gravity and disables streaming.
Workspace.Gravity = 196.2
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
		-- The ordinary Roblox Humanoid owns movement and wall/floor contacts;
		-- a separate client script locks the engine camera to first person.
		humanoid.AutoRotate = true
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		local checkpoint = math.max(0, state.opened - 2)
		if not state.rooms[checkpoint] then checkpoint = math.max(0, state.opened - CONFIG.KeepBehind) end
		-- On the first run, the Roblox SpawnLocation handles the whole spawn:
		-- no scripted relocation or invisible replacement of the avatar.
		if checkpoint > 0 then
			character:PivotTo(CFrame.new(0, Layout.EntranceY(checkpoint) + 3,
				checkpoint * L + CONFIG.SpawnDistance) * CFrame.Angles(0, math.pi, 0))
		end
		remote:FireClient(player, "State", state.opened, state.seed, L)
		humanoid.Died:Connect(function()
			leaveCloset(player, false)
			remote:FireClient(player, "Death")
		end)
	end)
	player.RespawnLocation = state.spawn
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
		and root.Position.Y >= surfaceY - 3
		and root.Position.Y <= surfaceY + 10 then return end
	local target = math.max(first, math.min(state.opened, CONFIG.Doors - 1))
	root.CFrame = CFrame.new(0, Layout.EntranceY(target) + 3,
		target * L + CONFIG.SpawnDistance) * CFrame.Angles(0, math.pi, 0)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
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

print("[NOCTURNE v5 / native first person] 100 doors, shuffled room plan, sealed stairs; three roaming threats ready.")
