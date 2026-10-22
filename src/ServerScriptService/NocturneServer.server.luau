-- NOCTURNE / a self-contained, original, 100-door horror game.
-- Everything in NocturneWorld is built on the server. The three uploaded v14
-- Sound templates are shipped with the place; doors never trust client numbers.

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
	VoidWalkSpeed = 5,
	VoidLength = 48,
	VoidScareOffset = 43,
	SprintSpeed = 19,
	CrouchSpeed = 7,
	SprintDrain = 19,
	StaminaRegen = 13,
	RushSpeed = 70,
	RushWarningSeconds = 3.2,
	RushMaximumSeconds = 18,
	MothLifetime = 20,
	MothSpeed = 17,
	MothGraceSeconds = 4,
	TorchDrain = 2.8, -- a found/bought torch lasts ~36 seconds of actual use
	ClosetWarning = 7,
	ClosetLimit = 14,
	KeyTurnSeconds = 0.7,
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
local SLOTS = {"FLASHLIGHT", "PILL", "CRUCIFIX", "BANDAGE", "MEDKIT"}
local PRICES = {FLASHLIGHT = 25, PILL = 12, CRUCIFIX = 60, BANDAGE = 10, MEDKIT = 32}
local VALUE = {COIN = 1, NOTE = 10, GOLD = 60}
local HEAL = {BANDAGE = 25, MEDKIT = 65}
-- Interactions stay reproducible for a seed, but a spider should be a surprise,
-- not something that happens in every few rooms. A hit also has a per-player
-- room cooldown so two nearby cabinets cannot chain-jumpscare the same person.
local DRAWER_SPIDER_CHANCE = 0.01
local WARDROBE_SPIDER_CHANCE = 0.006
local SPIDER_ROOM_COOLDOWN = 12

local function emptyItems()
	return {FLASHLIGHT = 0, PILL = 0, CRUCIFIX = 0, BANDAGE = 0, MEDKIT = 0}
end

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
	entering = {}, -- a reserved wardrobe while the REAL avatar steps inside
	keys = {}, -- door index carried by each player; the drawer key is not spent on pickup
	players = {},
	clock = 0,
	noises = {},
	noiseSerial = 0,
	rush = nil,
	blind = nil,
	moth = nil,
	echo = nil,
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

-- These filenames are shipped with Roblox's own character sounds (not
-- unpublished marketplace audio). Each sound has a real 3-D source, a soft
-- reflection and room reverb. Light flickers NEVER call this helper.
local function soundAt(part, name, file, volume, pitch, range, looped)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxasset://sounds/" .. file
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMode = Enum.RollOffMode.Inverse
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = range
	sound.Looped = looped or false
	local reflection = Instance.new("EchoSoundEffect")
	reflection.Name = "Short corridor reflection"
	reflection.Delay = 0.19
	reflection.Feedback = 0.21
	reflection.DryLevel = 0
	reflection.WetLevel = -16
	reflection.Parent = sound
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.Name = "Hotel masonry tail"
	reverb.DecayTime = 2.5
	reverb.Density = 0.62
	reverb.Diffusion = 0.78
	reverb.DryLevel = 0
	reverb.WetLevel = -12
	reverb.Parent = sound
	sound.Parent = part
	return sound
end

local function announceMonster(room, kind, entity)
	local body = entity.PrimaryPart
	if not body then return end
	soundAt(body, "Arrival in the hall", "uuhhh.mp3", 1.4,
		kind == "MOTH" and 0.82 or 0.58, 135):Play()
	soundAt(body, "Heavy arrival", "action_jump_land.mp3", 1.1, 0.55, 115):Play()
	-- A close, loud cue reaches the player even when the Rush begins three
	-- rooms behind. The local client checks that the player is near the room.
	remote:FireAllClients("MonsterSpawn", kind, room.index)
end

-- Keep the native E/touch/gamepad interaction affordance, but never show
-- explanatory action/object text over the scene.
local function iconPrompt(prompt)
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	return prompt
end

local function block(parent, name, sx, sy, sz, x, y, z, color, material)
	return newPart(parent, name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, material)
end

local function roomBlock(room, name, sx, sy, sz, x, relativeY, z, color, material)
	return block(room.model, name, sx, sy, sz, x, room.entryY + relativeY, z, color, material)
end

local function roomDetail(room, name, sx, sy, sz, x, relativeY, z, color, material)
	local detail = roomBlock(room, name, sx, sy, sz, x, relativeY, z, color, material)
	detail.CanCollide = false
	detail.CanQuery = false
	detail.CastShadow = false
	return detail
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
	-- Glass, a narrow metal crown and a wall mount catch the warm pool of light.
	-- These are non-colliding details; the fixture still uses ONE PointLight.
	local crown = newPart(parent, "Hammered brass lamp crown", Vector3.new(0.12, 1.27, 1.27),
		CFrame.new(position + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		C.brass, Enum.Material.Metal, 0, false)
	crown.Shape = Enum.PartType.Cylinder
	crown.CanQuery = false
	local shade = newPart(parent, "Smoked glass lamp shade", Vector3.new(1.1, 0.82, 1.1),
		CFrame.new(position + Vector3.new(0, -0.36, 0)), Color3.fromRGB(184, 139, 93),
		Enum.Material.Glass, 0.66, false)
	shade.Shape = Enum.PartType.Ball
	shade.CastShadow = false
	shade.CanQuery = false
	if math.abs(position.X) > W / 2 - 3 then
		local side = position.X < 0 and -1 or 1
		local plate = newPart(parent, "Sconce wall escutcheon", Vector3.new(0.14, 1.92, 0.94),
			CFrame.new(side * (W / 2 - 0.91), position.Y + 0.2, position.Z),
			C.brassDark, Enum.Material.Metal, 0, false)
		plate.CanQuery = false
		local arm = newPart(parent, "Sconce forged arm", Vector3.new(1.6, 0.11, 0.12),
			CFrame.new(side * (W / 2 - 1.7), position.Y + 0.12, position.Z),
			C.brass, Enum.Material.Metal, 0, false)
		arm.CanQuery = false
	end
	local bulb = newPart(parent, "Warm filament", Vector3.new(0.48, 0.42, 0.48),
		CFrame.new(position + Vector3.new(0, -0.3, 0)), color or C.lamp, Enum.Material.Neon, 0, false)
	bulb.Shape = Enum.PartType.Ball
	bulb.CanQuery = false
	local light = Instance.new("PointLight")
	light.Color = color or C.lamp
	light.Brightness = (brightness or 1.6) * (room.lightPower or 1)
	light.Range = 21
	-- One shadow-casting sconce per room keeps mobile lighting affordable.
	light.Shadows = #room.lamps == 0
	light.Parent = bulb
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust in the lamplight"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(237, 205, 166))
	dust.Transparency = NumberSequence.new(0.89, 1)
	dust.Size = NumberSequence.new(0.11, 0.24)
	dust.Rate = 0.17
	dust.Lifetime = NumberRange.new(3.5, 5.2)
	dust.Speed = NumberRange.new(0.08, 0.21)
	dust.SpreadAngle = Vector2.new(85, 85)
	dust.LightEmission = 0.1
	dust.Enabled = not room.dark
	dust.Parent = bulb
	local lamp = {light = light, bulb = bulb, dust = dust, brightness = light.Brightness,
		color = light.Color, normallyOn = not room.dark}
	table.insert(room.lamps, lamp)
	if room.dark then
		light.Enabled = false
		bulb.Material = Enum.Material.Glass
		bulb.Color = Color3.fromRGB(37, 42, 44)
		bulb.Transparency = 0.32
	end
	return fixture
end

local function setLamp(lamp, on, tint, intensity)
	if not lamp.light.Parent then return end
	lamp.light.Enabled = on
	lamp.light.Color = tint or lamp.color
	lamp.light.Brightness = lamp.brightness * (intensity or 1)
	lamp.dust.Enabled = on
	lamp.bulb.Material = on and Enum.Material.Neon or Enum.Material.Glass
	lamp.bulb.Color = on and (tint or lamp.color) or Color3.fromRGB(37, 42, 44)
	lamp.bulb.Transparency = on and 0 or 0.32
end

local function blackoutGuides(room)
	-- Three very weak, permanently lit PHYSICAL fixtures mark the floor and
	-- the middle furniture bay. All warm sconces stay broken in these rooms;
	-- switching the torch off therefore never plunges the player into black.
	local z = room.index * L
	for _, dz in ipairs({7, 22, 37}) do
		local glass = roomBlock(room, "Emergency glass", 0.65, 0.28, 0.65,
			0, 10.4, z + dz, Color3.fromRGB(84, 102, 111), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Ball
		glass.Transparency = 0.24
		glass.CanCollide = false
		glass.CastShadow = false
		local light = Instance.new("PointLight")
		light.Name = "Blackout floor glow"
		light.Color = Color3.fromRGB(124, 148, 158)
		light.Brightness = 0.38
		light.Range = 20
		light.Shadows = false
		light.Parent = glass
	end
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
	assembly:SetAttribute("Open", false)
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
	iconPrompt(prompt)
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

local function tweenPivot(model, from, to, duration, finished, active)
	local value = Instance.new("CFrameValue")
	value.Value = from
	local connection = value.Changed:Connect(function(cf)
		if model.Parent and (not active or active()) then model:PivotTo(cf) end
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
	if room.creak then room.creak:Play() end
	setModelCollision(room.door, false)
	local from = room.hinge * CFrame.Angles(0, room.open and -math.rad(105) or 0, 0)
	local to = room.hinge * CFrame.Angles(0, opening and -math.rad(105) or 0, 0)
	tweenPivot(room.door, from, to, 0.82, function()
		room.open = opening
		room.busy = false
		if room.door.Parent then
			room.door:SetAttribute("Open", opening)
			setModelCollision(room.door, true)
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

-- Only the server can award loot, spend money or enable a beam. The wallet
-- and inventory are personal; each actual drawer prize belongs to its first taker.
local updateHeldItem -- defined after the shared drawer/hand item modeller
local function syncInventory(player)
	local info = state.players[player]
	if not info then return end
	-- Keep selection on an actually owned item. When the last item is used up,
	-- the hotbar disappears; obtaining a new one selects it automatically.
	if info.items[SLOTS[info.selected]] == 0 then
		for index, id in ipairs(SLOTS) do
			if info.items[id] > 0 then info.selected = index; break end
		end
	end
	if info.selected ~= 1 or info.items.FLASHLIGHT == 0 then info.torchOn = false end
	player:SetAttribute("HasFlashlight", info.items.FLASHLIGHT > 0)
	player:SetAttribute("TorchOn", info.torchOn)
	player:SetAttribute("TorchCharge", math.ceil(info.charge))
	player:SetAttribute("Health", math.ceil(info.health))
	player:SetAttribute("SelectedItem", SLOTS[info.selected])
	player:SetAttribute("EquippedItem", info.items[SLOTS[info.selected]] > 0
		and playerRoot(player) and SLOTS[info.selected] or nil)
	if updateHeldItem then updateHeldItem(player) end
	local items = {}
	for _, id in ipairs(SLOTS) do items[id] = info.items[id] end
	remote:FireClient(player, "Inventory", {
		items = items, coins = info.coins, notes = info.notes, gold = info.gold,
		charge = math.ceil(info.charge), health = math.ceil(info.health), selected = info.selected,
	})
end

local function award(player, kind, amount)
	local info = state.players[player]
	if not info or not playerRoot(player) then return false end
	if VALUE[kind] then
		local field = ({COIN = "coins", NOTE = "notes", GOLD = "gold"})[kind]
		info[field] = info[field] + amount
	elseif info.items[kind] ~= nil then
		-- One per TYPE, not one item in total. A refused prize stays in its
		-- shared drawer until somebody eligible takes it (or the run resets).
		if amount ~= 1 or info.items[kind] > 0 then return false end
		local selectedID = SLOTS[info.selected]
		local selectedWasEmpty = info.items[selectedID] == 0
		info.items[kind] = 1
		if kind == "FLASHLIGHT" then info.charge = 100 end
		if selectedWasEmpty then
			for index, id in ipairs(SLOTS) do
				if id == kind then info.selected = index; break end
			end
		end
	else
		return false
	end
	syncInventory(player)
	return true
end

local tryCrucifix -- attached to all contact hazards after creature creation
local function damagePlayer(player, amount, kind, entity)
	local info, _, hum = state.players[player], playerRoot(player)
	if not info or not hum or player:GetAttribute("Finished") then return end
	if entity and entity:GetAttribute("Banished") then return info.health end
	if kind and entity and tryCrucifix and tryCrucifix(player, entity) then return info.health end
	info.health = math.max(0, math.min(info.health, hum.Health) - amount)
	if info.health <= 0 and kind then
		if entity then entity:SetAttribute("RecentKill", true) end
		remote:FireClient(player, "Jumpscare", kind, entity)
	end
	player:SetAttribute("Health", math.ceil(info.health))
	hum.Health = info.health
	return info.health
end

local function recordNoise(position, radius)
	state.noiseSerial = state.noiseSerial + 1
	state.noises[#state.noises + 1] = {
		position = position, radius = radius, at = state.clock, serial = state.noiseSerial,
	}
	if #state.noises > 64 then table.remove(state.noises, 1) end
end

local function spiderJump(player, cf)
	local spider = Instance.new("Model")
	spider.Name = "DrawerSpider"
	spider.Parent = state.world
	local body = newPart(spider, "Hairy abdomen", Vector3.new(0.55, 0.34, 0.65),
		cf, C.shadow, Enum.Material.Slate, 0, false)
	body.Shape = Enum.PartType.Ball
	spider.PrimaryPart = body
	local head = newPart(spider, "Spider head", Vector3.new(0.38, 0.28, 0.37),
		cf * CFrame.new(0, 0.02, -0.43), C.woodDark, Enum.Material.Slate, 0, false)
	head.Shape = Enum.PartType.Ball
	for _, side in ipairs({-1, 1}) do
		for leg = 1, 4 do
			local z = (leg - 2.5) * 0.22
			railBetween(spider, "Crooked spider leg",
				(cf * CFrame.new(side * 0.2, 0.08, z)).Position,
				(cf * CFrame.new(side * (0.65 + leg * 0.05), -0.16, z - 0.19)).Position,
				0.042, C.shadow)
		end
	end
	local eye = newPart(spider, "Glint in the spider eyes", Vector3.new(0.11, 0.1, 0.08),
		cf * CFrame.new(0, 0.09, -0.64), C.brass, Enum.Material.Neon, 0, false)
	eye.Shape = Enum.PartType.Ball
	spider.WorldPivot = cf
	recordNoise(cf.Position, 40)
	remote:FireClient(player, "Spider", spider)
	tweenPivot(spider, cf, cf * CFrame.new(0, 2.1, -2.5), 0.37, function()
		task.delay(1.3, function() if spider.Parent then spider:Destroy() end end)
	end)
end

local function maybeSpider(player, roomIndex, rolled, cf)
	local info = state.players[player]
	if not rolled or not info or roomIndex < (info.nextSpiderRoom or 0) then return end
	info.nextSpiderRoom = roomIndex + SPIDER_ROOM_COOLDOWN
	spiderJump(player, cf)
end

-- The two real hinged leaves open for the same interaction that takes the
-- character inside; there is no separate open/close prompt. A superseded
-- tween cannot pull the leaves back across someone entering or exiting.
local function swingCloset(closet, opening, finished)
	if closet.epoch ~= session or not closet.model.Parent then return end
	closet.motion = (closet.motion or 0) + 1
	local motion = closet.motion
	closet.moving = true
	if closet.creak then closet.creak:Play() end
	closet.prompt.Enabled = false
	closet.barrier.CanCollide = false
	for _, leaf in ipairs(closet.leaves) do
		setModelCollision(leaf.model, false)
	end
	local pending = #closet.leaves
	for _, leaf in ipairs(closet.leaves) do
		local angle = -leaf.side * math.rad(94)
		local from = leaf.model:GetPivot() -- also works if a previous swing was interrupted
		local to = leaf.hinge * CFrame.Angles(0, opening and angle or 0, 0)
		tweenPivot(leaf.model, from, to, 0.36, function()
			pending = pending - 1
			if pending ~= 0 or closet.motion ~= motion or not closet.model.Parent then return end
			closet.open = opening
			closet.moving = false
			closet.model:SetAttribute("Open", opening)
			closet.barrier.CanCollide = not opening
			for _, part in ipairs(closet.leaves) do setModelCollision(part.model, not opening) end
			closet.prompt.Enabled = not closet.occupant
			if finished then finished() end
		end, function() return closet.motion == motion end)
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
		local exitMotion = closet.motion
		task.delay(1.25, function()
			if closet.epoch == session and closet.motion == exitMotion
				and not closet.occupant and closet.model.Parent then
				swingCloset(closet, false) -- no second press to shut the wardrobe
			end
		end)
	elseif closet.model.Parent and not closet.moving then
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
	player:SetAttribute("ClosetPressure", 0)
	if teleport then recordNoise(closet.exitCF.Position, 52) end
	remote:FireClient(player, "Hide", false)
end

-- Death, a reset, a culled room or a disconnect can interrupt the step-in.
-- Cancel its physical tween and release the reservation so nobody remains
-- anchored outside (or leaves a permanently occupied wardrobe behind).
local function cancelClosetEntry(player)
	local entry = state.entering[player]
	if not entry then return end
	state.entering[player] = nil
	local closet = entry.closet
	if entry.tween then entry.tween:Cancel() end
	if closet.occupant == player then closet.occupant = nil end
	if closet.model.Parent then swingCloset(closet, false) end
	if entry.root.Parent then
		entry.root.Anchored = false
		entry.root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		entry.root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end
	if entry.hum.Parent then
		entry.hum.AutoRotate = true
		entry.hum.WalkSpeed = CONFIG.WalkSpeed
	end
	player:SetAttribute("EnteringWardrobe", false)
	remote:FireClient(player, "WardrobeEnter", false)
end

local function enterCloset(player, closet)
	local info = state.players[player]
	if closet.occupant or closet.moving or not closet.prompt.Enabled
		or state.hidden[player] or state.entering[player] or closet.epoch ~= session
		or not info or (info.closetCooldown or 0) > state.clock then return end
	local root, hum = playerRoot(player)
	if not root or not closet.model.Parent or player:GetAttribute("Finished") then return end
	-- A prompt across the back/side wall must not pull a player THROUGH it.
	local relative = closet.rootCF:PointToObjectSpace(root.Position)
	if math.abs(relative.X) > 5.8 or relative.Z > -1.55 or relative.Z < -7.1
		or math.abs(relative.Y) > 2.5 then return end
	local entry = {closet = closet, root = root, hum = hum}
	state.entering[player] = entry
	closet.occupant = player -- reserve on the FIRST press, before opening
	closet.inspected = false
	closet.prompt.Enabled = false
	info.sprinting = false
	info.crouching = false
	info.torchOn = false
	player:SetAttribute("Crouching", false)
	player:SetAttribute("ClosetPressure", 0)
	syncInventory(player)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	root.Anchored = true
	hum.AutoRotate = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	player:SetAttribute("EnteringWardrobe", true)
	remote:FireClient(player, "WardrobeEnter", true)
	recordNoise(closet.front, 58)
	if not closet.spiderChecked then
		closet.spiderChecked = true
		maybeSpider(player, closet.roomIndex, closet.spiderRoll,
			closet.rootCF * CFrame.new(0, 1, -1.8))
	end
	local function active()
		return state.entering[player] == entry and closet.occupant == player
			and closet.epoch == session and closet.model.Parent and root.Parent and hum.Health > 0
	end
	local function animateRoot(target, duration, finished)
		if not active() then return end
		local tween = TweenService:Create(root,
			TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
			{CFrame = target})
		entry.tween = tween
		tween.Completed:Connect(function(playback)
			if playback == Enum.PlaybackState.Completed and active() then finished() end
		end)
		tween:Play()
	end
	local function finishEntry()
		if not active() then return end
		root.CFrame = closet.rootCF -- only a final alignment INSIDE the wardrobe
		state.entering[player] = nil
		state.hidden[player] = {closet = closet, seconds = 0}
		player:SetAttribute("Hidden", true)
		player:SetAttribute("EnteringWardrobe", false)
		recordNoise(closet.front, 47)
		remote:FireClient(player, "Hide", true, closet.cameraCF)
		swingCloset(closet, false) -- close automatically after the avatar is inside
	end
	local function stepInside()
		if not active() then return end
		local distance = (root.Position - closet.entryCF.Position).Magnitude
		animateRoot(closet.entryCF, math.clamp(distance / 13, 0.14, 0.32), function()
			animateRoot(closet.rootCF, 0.42, finishEntry)
		end)
	end
	if closet.open then stepInside() else swingCloset(closet, true, stepInside) end
end

local function makeCloset(room, side, z, serial, floorY, passageHalfWidth)
	-- Local -Z faces the playable passage. Both landings and corridors place the
	-- whole shell inside a wall; its exit always points back to the clear centre.
	local cf = CFrame.new(side * (passageHalfWidth - 2.45), floorY, z)
		* CFrame.Angles(0, side * math.pi / 2, 0)
	local model = Instance.new("Model")
	model.Name = "Wardrobe_" .. serial
	model:SetAttribute("Open", false)
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
		-- A genuine central viewing gap and spaced louvres, not a full-height
		-- opaque slab hidden behind a fake GUI slit. Monster geometry can be
		-- seen THROUGH the closed leaves while the collision barrier stays solid.
		local centreX = leafSide * 1.17
		newPart(leaf, "Lower oak wardrobe panel", Vector3.new(1.32, 2.0, 0.18),
			cf * CFrame.new(centreX, 1.42, -1.52), C.wood, Enum.Material.Wood)
		for _, edgeX in ipairs({centreX - 0.57, centreX + 0.57}) do
			newPart(leaf, "Wardrobe vertical stile", Vector3.new(0.17, 8.05, 0.18),
				cf * CFrame.new(edgeX, 4.14, -1.52), C.wood, Enum.Material.Wood)
		end
		for j = 1, 7 do
			newPart(leaf, "Spaced wooden louvre", Vector3.new(1.14, 0.22, 0.13),
				cf * CFrame.new(centreX, 2.35 + j * 0.68, -1.66)
					* CFrame.Angles(math.rad(-16), 0, 0), C.woodLight, Enum.Material.Wood)
		end
		for _, edge in ipairs({0.63, 7.65}) do
			newPart(leaf, "Carved leaf rail", Vector3.new(1.32, 0.26, 0.18),
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
	iconPrompt(prompt)
	prompt.HoldDuration = 0 -- ONE tap/click opens, enters and closes
	prompt.MaxActivationDistance = 5.5 -- every visible approach is also accepted by the server
	prompt.RequiresLineOfSight = true -- never show an icon through the back/side wall
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = handles[-1]
	local closet = {
		model = model, barrier = barrier, leaves = leaves, prompt = prompt,
		creak = soundAt(handles[-1], "Wardrobe wood and hinges", "action_get_up.mp3",
			0.38, 0.62, 48),
		roomIndex = room.index, front = (cf * CFrame.new(0, 4, -1.6)).Position,
		rootCF = cf * CFrame.new(0, 3, 0.1),
		entryCF = cf * CFrame.new(0, 3, -2.55) * CFrame.Angles(0, math.pi, 0),
		cameraCF = cf * CFrame.new(0, 5.0, -1.02), -- eye close to the real gap, behind the leaves
		exitCF = cf * CFrame.new(0, 3, -3.45),
		epoch = session,
		spiderRoll = Random.new(state.seed + room.index * 197
			+ (serial == "A" and 13 or 71)):NextNumber() < WARDROBE_SPIDER_CHANCE,
		occupant = nil, open = false,
	}
	prompt.Triggered:Connect(function(player) enterCloset(player, closet) end)
	table.insert(room.closets, closet)
end

-- The drawer key stays there until somebody REALLY picks it up. A second copy
-- is welded to that player's ordinary R6/R15 right hand, visible to the group.
-- On death/disconnect the real key reappears in its open drawer, so a team
-- cannot soft-lock itself; only turning it in its own door consumes it.
local function putBackKey(player)
	local index = state.keys[player]
	state.keys[player] = nil
	player:SetAttribute("HeldKey", nil)
	player:SetAttribute("KeyTurning", false)
	local character = player.Character
	local held = character and character:FindFirstChild("HeldKey")
	if held then held:Destroy() end
	local room = index and state.rooms[index]
	if room and room.epoch == session and not room.unlocked and room.key then
		for _, part in ipairs(room.key.model:GetDescendants()) do
			if part:IsA("BasePart") then part.Transparency = 0 end
		end
		room.key.prompt.Enabled = true
		room.model:SetAttribute("KeyFound", false)
	end
	if updateHeldItem then updateHeldItem(player) end -- release the left hand
end

local function holdKey(player, key)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") then return false end
	local held = key:Clone()
	held.Name = "HeldKey"
	for _, descendant in ipairs(held:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then descendant:Destroy() end
	end
	local bow = held.PrimaryPart
	if not bow then held:Destroy(); return false end
	held.Parent = character
	-- Welds, not anchored display parts or a replacement Humanoid: Roblox's
	-- normal animation/physics keeps moving the owner's actual hand.
	-- The bow rests IN the palm, not below a dangling hand. Its teeth point
	-- forward and down until the player raises the actual arm at the lock.
	local palmY = hand.Name == "Right Arm" and -hand.Size.Y * 0.45 or -hand.Size.Y * 0.13
	held:PivotTo(hand.CFrame * CFrame.new(0, palmY, -0.17)
		* CFrame.Angles(math.rad(125), 0, math.rad(-12)))
	local parts = {}
	for _, part in ipairs(held:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			table.insert(parts, part)
			if part ~= bow then
				local joint = Instance.new("WeldConstraint")
				joint.Part0 = bow
				joint.Part1 = part
				joint.Parent = bow
			end
		end
	end
	local grip = Instance.new("WeldConstraint")
	grip.Name = "Key grip in Roblox hand"
	grip.Part0 = hand
	grip.Part1 = bow
	grip.Parent = bow
	for _, part in ipairs(parts) do part.Anchored = false end
	return true
end

-- Drawer contents are seeded once on the server. They belong to the first
-- eligible taker, not to every client; props ride the real drawer until claimed.
local function rollLoot(rng)
	-- Over half the drawers are empty. Cash is more common than equipment;
	-- the latter drops in only 13.5% of unlocked, non-key drawers.
	local roll = rng:NextNumber()
	if roll < 0.19 then return "COIN", rng:NextInteger(2, 6) end
	if roll < 0.33 then return "NOTE", rng:NextInteger(1, 2) end
	if roll < 0.34 then return "GOLD", 1 end
	if roll < 0.352 then return "FLASHLIGHT", 1 end
	if roll < 0.397 then return "PILL", 1 end
	if roll < 0.415 then return "CRUCIFIX", 1 end
	if roll < 0.46 then return "BANDAGE", 1 end
	if roll < 0.475 then return "MEDKIT", 1 end
	return nil, 0
end

local function makeLoot(drawer, cf, y, kind, amount)
	local model = Instance.new("Model")
	model.Name = "Loot_" .. kind
	model.Parent = drawer
	local base = cf * CFrame.new(0, y - 0.20, -0.62)
	local function piece(name, size, offset, tint, material, shape, alpha)
		local p = newPart(model, name, size, base * offset, tint, material, alpha or 0, false)
		if shape then p.Shape = shape end
		p.CanQuery = false
		return p
	end
	local primary
	if kind == "COIN" then
		for n = 1, math.min(amount, 5) do
			primary = piece("Stamped copper coin", Vector3.new(0.10, 0.37, 0.37),
				CFrame.new((n - 3) * 0.26, 0, 0) * CFrame.Angles(0, 0, math.pi / 2),
				C.brass, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	elseif kind == "NOTE" then
		primary = piece("Folded paper money", Vector3.new(0.88, 0.04, 0.47),
			CFrame.new(), Color3.fromRGB(129, 141, 111), Enum.Material.Fabric)
		piece("Print on the banknote", Vector3.new(0.6, 0.015, 0.20),
			CFrame.new(0, 0.026, 0), C.woodDark, Enum.Material.Fabric)
	elseif kind == "GOLD" then
		primary = piece("Rare gold ingot", Vector3.new(0.92, 0.28, 0.52),
			CFrame.new(), Color3.fromRGB(229, 171, 53), Enum.Material.Metal)
		piece("Ingot stamp", Vector3.new(0.50, 0.025, 0.22), CFrame.new(0, 0.15, 0),
			C.brassDark, Enum.Material.Metal)
	elseif kind == "FLASHLIGHT" then
		local steel = Color3.fromRGB(98, 107, 108)
		primary = piece("Machined torch barrel", Vector3.new(1.18, 0.35, 0.35),
			CFrame.new(), C.woodDark, Enum.Material.Metal, Enum.PartType.Cylinder)
		for _, x in ipairs({-0.15, -0.02, 0.11, 0.24}) do
			piece("Crosshatched grip ring", Vector3.new(0.055, 0.39, 0.39),
				CFrame.new(x, 0, 0), steel, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		piece("Knurled tail cap", Vector3.new(0.18, 0.40, 0.40),
			CFrame.new(0.64, 0, 0), steel, Enum.Material.Metal, Enum.PartType.Cylinder)
		piece("Flared torch head", Vector3.new(0.28, 0.53, 0.53),
			CFrame.new(-0.56, 0, 0), steel, Enum.Material.Metal, Enum.PartType.Cylinder)
		piece("Lens retaining ring", Vector3.new(0.10, 0.58, 0.58),
			CFrame.new(-0.72, 0, 0), C.brassDark, Enum.Material.Metal, Enum.PartType.Cylinder)
		local lens = piece("Torch lens", Vector3.new(0.055, 0.45, 0.45),
			CFrame.new(-0.79, 0, 0), Color3.fromRGB(222, 203, 157),
			Enum.Material.Glass, Enum.PartType.Cylinder, 0.17)
		piece("Recessed lamp filament", Vector3.new(0.067, 0.16, 0.16),
			CFrame.new(-0.83, 0, 0), Color3.fromRGB(255, 234, 193),
			Enum.Material.Neon, Enum.PartType.Cylinder, 0.18)
		piece("Raised power switch", Vector3.new(0.21, 0.09, 0.16),
			CFrame.new(0.28, 0.23, 0), steel, Enum.Material.Metal)
		-- Two physical cones make the held torch useful in blackout rooms:
		-- soft coverage up close and a focussed beam down the corridor. Both
		-- live in the REAL model so other players see the light, not a UI flash.
		local beam = Instance.new("SpotLight")
		beam.Name = "Selected torch beam"
		beam.Enabled = false
		beam.Face = Enum.NormalId.Left
		beam.Angle = 92
		beam.Range = 32
		beam.Brightness = 3.4
		beam.Color = Color3.fromRGB(255, 238, 208)
		beam.Shadows = false
		beam.Parent = lens
		local core = Instance.new("SpotLight")
		core.Name = "Selected torch core"
		core.Enabled = false
		core.Face = Enum.NormalId.Left
		core.Angle = 42
		core.Range = 56
		core.Brightness = 4.6
		core.Color = Color3.fromRGB(255, 250, 232)
		core.Shadows = false
		core.Parent = lens
	elseif kind == "PILL" then
		local amber = Color3.fromRGB(186, 146, 92)
		local vertical = CFrame.Angles(0, 0, math.pi / 2)
		primary = piece("Vial grip spine", Vector3.new(0.29, 0.65, 0.29),
			CFrame.new(), amber, Enum.Material.Glass, nil, 0.55)
		piece("Amber apothecary vial", Vector3.new(0.72, 0.46, 0.46),
			vertical, amber, Enum.Material.Glass, Enum.PartType.Cylinder, 0.23)
		piece("Dark sealed vial base", Vector3.new(0.09, 0.48, 0.48),
			CFrame.new(0, -0.35, 0) * vertical, C.brassDark,
			Enum.Material.Metal, Enum.PartType.Cylinder)
		piece("Wax bottle collar", Vector3.new(0.11, 0.52, 0.52),
			CFrame.new(0, 0.37, 0) * vertical, C.brass,
			Enum.Material.Metal, Enum.PartType.Cylinder)
		piece("Faceted glass stopper", Vector3.new(0.22, 0.30, 0.30),
			CFrame.new(0, 0.52, 0) * vertical, Color3.fromRGB(214, 202, 168),
			Enum.Material.Glass, Enum.PartType.Cylinder, 0.08)
		piece("Hand-printed medicine label", Vector3.new(0.32, 0.32, 0.025),
			CFrame.new(0, -0.07, -0.25), Color3.fromRGB(226, 208, 173), Enum.Material.Fabric)
		piece("Red dose seal", Vector3.new(0.23, 0.08, 0.027),
			CFrame.new(0, -0.07, -0.272), Color3.fromRGB(132, 50, 55), Enum.Material.Fabric)
		for _, x in ipairs({-0.1, 0.1}) do
			piece("Capsule inside glass", Vector3.new(0.14, 0.09, 0.10),
				CFrame.new(x, -0.22, 0), Color3.fromRGB(229, 225, 202),
				Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		end
	elseif kind == "CRUCIFIX" then
		local silver = Color3.fromRGB(158, 153, 135)
		primary = piece("Forged crucifix shaft", Vector3.new(0.17, 1.12, 0.19),
			CFrame.new(), silver, Enum.Material.Metal)
		piece("Forged crucifix arms", Vector3.new(0.77, 0.17, 0.19),
			CFrame.new(0, 0.24, 0), silver, Enum.Material.Metal)
		for _, x in ipairs({-0.37, 0.37}) do
			piece("Hammered arm finial", Vector3.new(0.15, 0.22, 0.24),
				CFrame.new(x, 0.24, 0), C.brassDark, Enum.Material.Metal, Enum.PartType.Ball)
		end
		piece("Lower finial", Vector3.new(0.23, 0.17, 0.22),
			CFrame.new(0, -0.58, 0), C.brassDark, Enum.Material.Metal, Enum.PartType.Ball)
		piece("Dark enamel heart", Vector3.new(0.30, 0.30, 0.08),
			CFrame.new(0, 0.24, -0.13), C.woodDark, Enum.Material.Slate, Enum.PartType.Ball)
		piece("Chipped ivory inset", Vector3.new(0.16, 0.16, 0.05),
			CFrame.new(0, 0.24, -0.18), Color3.fromRGB(227, 215, 183), Enum.Material.Marble)
		piece("Iron hanging loop", Vector3.new(0.13, 0.23, 0.16),
			CFrame.new(0, 0.64, 0), C.brassDark, Enum.Material.Metal, Enum.PartType.Ball)
	elseif kind == "BANDAGE" then
		local cloth = Color3.fromRGB(220, 212, 187)
		primary = piece("Rolled linen bandage", Vector3.new(0.58, 0.52, 0.52),
			CFrame.new(), cloth, Enum.Material.Fabric, Enum.PartType.Cylinder)
		for _, x in ipairs({-0.30, 0.30}) do
			piece("Wound linen edge", Vector3.new(0.045, 0.56, 0.56),
				CFrame.new(x, 0, 0), Color3.fromRGB(185, 173, 152),
				Enum.Material.Fabric, Enum.PartType.Cylinder)
			piece("Hollow roll centre", Vector3.new(0.052, 0.20, 0.20),
				CFrame.new(x * 1.12, 0, 0), C.woodDark,
				Enum.Material.Slate, Enum.PartType.Cylinder)
		end
		piece("Loose linen tab", Vector3.new(0.58, 0.05, 0.36),
			CFrame.new(0, -0.27, -0.27) * CFrame.Angles(math.rad(18), 0, 0),
			cloth, Enum.Material.Fabric)
		piece("Cloth wrapper stitching", Vector3.new(0.60, 0.03, 0.05),
			CFrame.new(0, -0.29, -0.36), C.brassDark, Enum.Material.Fabric)
	else
		local enamel = Color3.fromRGB(151, 47, 52)
		primary = piece("Enamelled medical tin", Vector3.new(1.14, 0.46, 0.84),
			CFrame.new(), enamel, Enum.Material.Metal)
		piece("Tin lid seam", Vector3.new(1.17, 0.06, 0.87),
			CFrame.new(0, 0.18, 0), C.brassDark, Enum.Material.Metal)
		piece("Raised medical lid", Vector3.new(1.11, 0.12, 0.81),
			CFrame.new(0, 0.27, 0), enamel, Enum.Material.Metal)
		piece("Ivory enamel cross", Vector3.new(0.51, 0.025, 0.12),
			CFrame.new(0, 0.342, 0), Color3.fromRGB(238, 224, 196))
		piece("Ivory enamel cross", Vector3.new(0.12, 0.026, 0.51),
			CFrame.new(0, 0.345, 0), Color3.fromRGB(238, 224, 196))
		for _, x in ipairs({-0.39, 0.39}) do
			piece("Medical case hinge", Vector3.new(0.15, 0.14, 0.10),
				CFrame.new(x, 0.02, 0.44), C.brass, Enum.Material.Metal)
		end
		piece("Pressed brass clasp", Vector3.new(0.20, 0.24, 0.09),
			CFrame.new(0, 0, -0.46), C.brass, Enum.Material.Metal)
		piece("Leather carrying strap", Vector3.new(0.61, 0.09, 0.16),
			CFrame.new(0, 0.43, 0.12), C.woodDark, Enum.Material.Fabric)
	end
	model.PrimaryPart = primary
	model:SetAttribute("LootKind", kind)
	model:SetAttribute("LootAmount", amount)
	return model
end

-- The same detailed physical model used in the drawer/shop is welded to an
-- actual R6/R15 hand. It is server-owned, so teammates see it too; there is
-- no extra floating first-person arm, Tool or Roblox Backpack. A carried key
-- reserves the right hand and moves the selected item to the LEFT real hand.
updateHeldItem = function(player)
	local info = state.players[player]
	local character = player.Character
	if not info or not character then return end
	local alive = playerRoot(player) ~= nil
	local id = alive and info.items[SLOTS[info.selected]] > 0 and SLOTS[info.selected] or nil
	local side = state.keys[player] ~= nil and "Left" or "Right"
	local hand = character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm")
	local held = character:FindFirstChild("HeldItem")
	if held and (not id or not hand or held:GetAttribute("ItemKind") ~= id
		or held:GetAttribute("GripHand") ~= side) then
		held:Destroy()
		held = nil
	end
	if not id or not hand or not hand:IsA("BasePart") then return end
	if not held then
		held = makeLoot(nil, CFrame.new(), 0.2, id, 1)
		held.Name = "HeldItem"
		held:SetAttribute("ItemKind", id)
		held:SetAttribute("GripHand", side)
		local palmY = hand.Name:find(" Arm") and -hand.Size.Y * 0.42 or -hand.Size.Y * 0.16
		local offset = id == "FLASHLIGHT" and -0.43 or id == "CRUCIFIX" and -0.52 or -0.30
		local orientation = id == "FLASHLIGHT" and CFrame.Angles(math.rad(-12), -math.pi / 2, 0)
			or id == "BANDAGE" and CFrame.Angles(0, math.pi / 2, 0)
			or CFrame.Angles(math.rad(-16), 0, 0)
		held:PivotTo(hand.CFrame * CFrame.new(side == "Left" and -0.08 or 0.08,
			palmY, offset) * orientation)
		local core = held.PrimaryPart
		if not core then held:Destroy(); return end
		for _, part in ipairs(held:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.Massless = true
				if part ~= core then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = core
					weld.Part1 = part
					weld.Parent = core
				end
			end
		end
		local grip = Instance.new("WeldConstraint")
		grip.Name = "Item grip in Roblox hand"
		grip.Part0 = hand
		grip.Part1 = core
		grip.Parent = core
		held.Parent = character
		for _, part in ipairs(held:GetDescendants()) do
			if part:IsA("BasePart") then part.Anchored = false end
		end
	end
	for _, name in ipairs({"Selected torch beam", "Selected torch core"}) do
		local beam = held:FindFirstChild(name, true)
		if beam then beam.Enabled = info.torchOn end
	end
end

-- The key is in exactly one of three physical drawers in the SAME room as its
-- locked door. Searching, taking and turning it are server-authoritative.
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
		local slide = soundAt(handle, "Sliding old drawer", "action_get_up.mp3", 0.42, 0.75, 43)
		local pickup = soundAt(handle, "Cache gathered", "action_jump_land.mp3", 0.25, 1.25, 28)
		drawer.WorldPivot = pivot
		local openPrompt = Instance.new("ProximityPrompt")
		openPrompt.Name = "OpenDrawer"
		iconPrompt(openPrompt)
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
			local bow = newPart(key, "Brass key bow", Vector3.new(0.2, 0.15, 0.2),
				cf * CFrame.new(0, drawerY - 0.22, -0.68), C.brassDark, Enum.Material.Metal, 1, false)
			bow.Shape = Enum.PartType.Ball
			key.PrimaryPart = bow
			for bead = 1, 10 do
				local angle = bead * math.pi * 2 / 10
				local loop = newPart(key, "Forged circular key loop", Vector3.new(0.13, 0.12, 0.13),
					cf * CFrame.new(math.cos(angle) * 0.24, drawerY - 0.22,
						-0.68 + math.sin(angle) * 0.24), C.brass, Enum.Material.Metal, 1, false)
				loop.Shape = Enum.PartType.Ball
			end
			newPart(key, "Key stem", Vector3.new(0.16, 0.15, 0.85),
				cf * CFrame.new(0, drawerY - 0.22, -0.22), C.brass, Enum.Material.Metal, 1, false)
			newPart(key, "Key teeth", Vector3.new(0.34, 0.15, 0.14),
				cf * CFrame.new(0.1, drawerY - 0.22, 0.18), C.brass, Enum.Material.Metal, 1, false)
			takePrompt = Instance.new("ProximityPrompt")
			takePrompt.Name = "TakeKey"
			iconPrompt(takePrompt)
			takePrompt.HoldDuration = 0.2
			takePrompt.MaxActivationDistance = 8
			takePrompt.RequiresLineOfSight = false
			takePrompt.KeyboardKeyCode = Enum.KeyCode.E
			takePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			takePrompt.Enabled = false
			takePrompt.Parent = bow
			room.key = {model = key, prompt = takePrompt}
			takePrompt.Triggered:Connect(function(player)
				if room.epoch ~= session or room.unlocked or not takePrompt.Enabled
					or state.keys[player] then return end
				local root = playerRoot(player)
				if not root or state.hidden[player] or state.entering[player]
					or (root.Position - bow.Position).Magnitude > 10 then return end
				if not holdKey(player, key) then return end
				takePrompt.Enabled = false
				for _, part in ipairs(key:GetDescendants()) do
					if part:IsA("BasePart") then part.Transparency = 1 end
				end
				state.keys[player] = room.index
				room.model:SetAttribute("KeyFound", true)
				player:SetAttribute("HeldKey", room.index + 1)
				updateHeldItem(player) -- key in the right hand, item in the left
			end)
		end
		local lootKind, amount = slot == keySlot and nil, 0
		if slot ~= keySlot then lootKind, amount = rollLoot(rng) end
		local loot = lootKind and makeLoot(drawer, cf, drawerY, lootKind, amount)
		local lootPrompt
		local claimed = false -- a drawer is a single physical cache for the WHOLE team
		if loot then
			drawer:SetAttribute("LootClaimed", false)
			lootPrompt = Instance.new("ProximityPrompt")
			lootPrompt.Name = "TakeLoot"
			iconPrompt(lootPrompt)
			lootPrompt.HoldDuration = 0.15
			lootPrompt.MaxActivationDistance = 7
			lootPrompt.RequiresLineOfSight = false
			lootPrompt.Enabled = false
			lootPrompt.Parent = loot.PrimaryPart
			lootPrompt.Triggered:Connect(function(player)
				if room.epoch ~= session or claimed or not lootPrompt.Enabled
					or not loot.Parent or not loot.PrimaryPart then return end
				local root = playerRoot(player)
				if not root or state.hidden[player] or state.entering[player]
					or (root.Position - loot.PrimaryPart.Position).Magnitude > 9 then return end
				-- Reserve BEFORE giving the prize: two simultaneous prompts cannot
				-- both pass. If a full inventory refuses it, release the cache.
				claimed = true
				if not award(player, lootKind, amount) then claimed = false; return end
				lootPrompt.Enabled = false
				drawer:SetAttribute("LootClaimed", true)
				pickup:Play()
				loot:Destroy() -- replicated to EVERY player, including late joiners
				recordNoise(root.Position, 29)
			end)
		end
		local spiderRoll = rng:NextNumber() < DRAWER_SPIDER_CHANCE
		local opened = false
		openPrompt.Triggered:Connect(function(player)
			if opened or room.epoch ~= session or not openPrompt.Enabled then return end
			local root = playerRoot(player)
			if not root or state.hidden[player] or state.entering[player]
				or (root.Position - handle.Position).Magnitude > 10 then return end
			opened = true
			openPrompt.Enabled = false
			slide:Play()
			recordNoise(handle.Position, 65)
			maybeSpider(player, room.index, spiderRoll, pivot * CFrame.new(0, 0.5, -1.4))
			tweenPivot(drawer, pivot, pivot * CFrame.new(0, 0, -1.25), 0.5, function()
				if room.epoch ~= session then return end
				if lootPrompt and loot and loot.Parent then lootPrompt.Enabled = true end
				if key and key.Parent then
					for _, part in ipairs(key:GetDescendants()) do
						if part:IsA("BasePart") then part.Transparency = 0 end
					end
					takePrompt.Enabled = true
				end
			end)
		end)
	end
end

local function pay(info, price)
	if info.coins + info.notes * VALUE.NOTE + info.gold * VALUE.GOLD < price then return false end
	local due = price
	local coins = math.min(info.coins, due)
	info.coins = info.coins - coins
	due = due - coins
	local notes = math.min(info.notes, math.ceil(due / VALUE.NOTE))
	info.notes = info.notes - notes
	due = due - notes * VALUE.NOTE
	if due > 0 then
		local bars = math.ceil(due / VALUE.GOLD)
		info.gold = info.gold - bars
		due = due - bars * VALUE.GOLD
	end
	info.coins = info.coins - due -- return change, never destroy the excess value
	return true
end

local function makeShop(room)
	local model = Instance.new("Model")
	model.Name = "After-fifty apothecary"
	model.Parent = room.model
	local z = room.index * L
	local y = room.entryY
	local lintel = block(model, "Shop gilt lintel", 5.1, 0.6, 29,
		-10, y + 9.1, z + 22, C.brassDark, Enum.Material.Metal)
	lintel.CanCollide = false
	local sign = block(model, "Apothecary sign", 3.9, 1.0, 0.17,
		-9.9, y + 8.5, z + 5.6, C.woodDark, Enum.Material.Wood)
	inscription(model, sign, "ЛАВКА", true)
	local goods = {
		{"FLASHLIGHT", 9, "ФОНАРЬ"}, {"PILL", 15, "ТАБЛЕТКИ"},
		{"CRUCIFIX", 22, "КРЕСТ"}, {"BANDAGE", 29, "ПЛАСТЫРЬ"},
		{"MEDKIT", 36, "АПТЕЧКА"},
	}
	for _, offer in ipairs(goods) do
		local id, dz, title = offer[1], offer[2], offer[3]
		block(model, "Solid shop counter", 3.1, 3.5, 4.5,
			-10, y + 1.75, z + dz, C.woodDark, Enum.Material.Wood)
		local glass = block(model, "Locked display glass", 3.15, 0.18, 4.55,
			-10, y + 3.6, z + dz, C.marble, Enum.Material.Glass)
		glass.CanCollide = false
		local specimen = makeLoot(model, CFrame.new(-10, y + 3.98, z + dz), 0.2, id, 1)
		for _, part in ipairs(specimen:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
		local plaque = newPart(model, "Shop price plate", Vector3.new(2.9, 1.1, 0.11),
			CFrame.new(-8.44, y + 2.6, z + dz) * CFrame.Angles(0, -math.pi / 2, 0),
			C.woodDark, Enum.Material.Metal, 0, false)
		inscription(model, plaque, title .. "  " .. PRICES[id], true)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Buy_" .. id
		iconPrompt(prompt)
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = plaque
		prompt.Triggered:Connect(function(player)
			local root = playerRoot(player)
			local info = state.players[player]
			if room.epoch ~= session or not root or not info
				or state.hidden[player] or state.entering[player]
				or state.opened < 51 or (root.Position - plaque.Position).Magnitude > 10
				or info.items[id] > 0 then return end -- no charge for a duplicate
			if not pay(info, PRICES[id]) then return end
			award(player, id, 1)
		end)
	end
	room.model:SetAttribute("Shop", true)
end

local function makePainting(room, side, z, accent)
	local x = side * (W / 2 - 0.8)
	roomBlock(room, "Tarnished picture frame", 0.24, 5.1, 5.3, x, 8.4, z,
		C.brassDark, Enum.Material.Metal)
	roomBlock(room, "Oil painting", 0.28, 4.45, 4.65, x - side * 0.15, 8.4, z,
		accent, Enum.Material.SmoothPlastic)
	roomDetail(room, "Painted distant ridge", 0.08, 0.62, 3.9,
		x - side * 0.32, 7.65, z - 0.05, Color3.fromRGB(33, 44, 50), Enum.Material.SmoothPlastic)
	roomDetail(room, "Painting horizon", 0.08, 0.18, 3.6, x - side * 0.36, 7.3, z,
		C.woodDark, Enum.Material.SmoothPlastic)
	local moon = roomDetail(room, "Distant moon in oil", 0.14, 0.72, 0.72,
		x - side * 0.35, 9.27, z + 1.05, Color3.fromRGB(171, 168, 146),
		Enum.Material.SmoothPlastic)
	moon.Shape = Enum.PartType.Ball
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
		local frames = (room.shape == "VESTIBULE" or room.shape == "NAVE")
			and {9, 30, 36} or {9, 33, 39}
		for _, side in ipairs({-1, 1}) do
			for _, baseZ in ipairs(frames) do
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
	Lighting.Brightness = 1.12
	-- Preserve the readable blackout floor; increase material contrast instead
	-- of making the whole corridor darker or obscuring it with grey fog.
	Lighting.Ambient = Color3.fromRGB(38, 42, 45)
	Lighting.OutdoorAmbient = Color3.fromRGB(19, 25, 30)
	Lighting.FogColor = Color3.fromRGB(20, 26, 32)
	Lighting.FogStart = 19
	Lighting.FogEnd = 120
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.48
	Lighting.EnvironmentSpecularScale = 0.29
	Lighting.ExposureCompensation = 0.06
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Name = "CorridorHaze"
	atmosphere.Density = 0.22
	atmosphere.Haze = 1.3
	atmosphere.Color = Color3.fromRGB(116, 131, 137)
	atmosphere.Decay = Color3.fromRGB(43, 33, 31)
	atmosphere.Parent = Lighting
	local grading = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	grading.Name = "ColdShadowsWarmLights"
	grading.TintColor = Color3.fromRGB(233, 235, 231)
	grading.Contrast = 0.17
	grading.Saturation = -0.13
	grading.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.23
	bloom.Size = 19
	bloom.Threshold = 1.8
	bloom.Parent = Lighting
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.16
	dof.NearIntensity = 0.03
	dof.FocusDistance = 24
	dof.InFocusRadius = 17
	dof.Parent = Lighting
	SoundService.AmbientReverb = Enum.ReverbType.Hallway
end

local openDoor -- assigned after room construction
local startRush -- assigned after room construction
local startBlind -- assigned after room construction
local startMoth -- assigned after room construction
local startEcho -- assigned after room construction
local buildRoom -- recursive reference for door callbacks
local makeFinalWitness -- defined with the other procedural creature sculptures

-- Every wall encloses the entire section, including the space UNDER an upper
-- landing. Only the central 7.4-stud doorway is open. Doorways on both sides
-- of a room always meet at the same height as their neighbour's doorway.
local function endWall(room, atZ, doorwayY, bottomY, topY, solid)
	local model = room.model
	local wallColor = room.wallColor
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
local function roomArchitecture(room)
	local z = room.index * L
	local style = WALL_STYLES[room.style]
	if room.shape == "VESTIBULE" then
		-- Two full-height cross-walls make distinct entrance/exit chambers.
		-- The 12.8-stud central passage stays wider than the numbered doors;
		-- wardrobes at z21/24 and the dresser at z17 remain accessible.
		for _, dz in ipairs({2.8, 41.2}) do
			for _, side in ipairs({-1, 1}) do
				roomBlock(room, "Vestibule cross-wall", W / 2 - 6.4, H, 0.85,
					side * (W / 2 + 6.4) / 2, H / 2, z + dz,
					style.wall, Enum.Material.Concrete)
				roomBlock(room, "Vestibule doorway moulding", 0.22, 10.8, 1,
					side * 6.4, 5.4, z + dz, style.trim, Enum.Material.Metal)
			end
			roomBlock(room, "Vestibule arch lintel", 12.8, H - 10.8, 0.86,
				0, (H + 10.8) / 2, z + dz, C.woodDark, Enum.Material.Wood)
		end
	elseif room.shape == "ARCADE" then
		for _, dz in ipairs({4.5, 39.5}) do
			for _, side in ipairs({-1, 1}) do
				local pillar = roomBlock(room, "Freestanding marble arcade column", 12.4, 1.08, 1.08,
					side * 9.2, 6.2, z + dz, C.marble, Enum.Material.Marble)
				pillar.Shape = Enum.PartType.Cylinder
				pillar.CFrame = pillar.CFrame * CFrame.Angles(0, 0, math.pi / 2)
				roomBlock(room, "Arcade gilded capital", 1.62, 0.53, 1.62,
					side * 9.2, 12.6, z + dz, style.trim, Enum.Material.Metal)
			end
			roomBlock(room, "Arcade transverse beam", 19.1, 0.7, 1.25,
				0, 13.1, z + dz, C.woodDark, Enum.Material.Wood)
		end
	elseif room.shape == "COFFERED" then
		for _, dz in ipairs({9, 18, 31, 39}) do
			roomBlock(room, "Deep coffered cross-vault", W - 1.4, 1.35, 1.15,
				0, H - 0.66, z + dz, C.woodDark, Enum.Material.Wood)
		end
		for _, side in ipairs({-1, 1}) do
			roomBlock(room, "Long arcade cornice", 0.4, 1.05, L - 1.5,
				side * 11.4, H - 0.55, z + L / 2, style.trim, Enum.Material.Metal)
		end
	elseif room.shape == "AISLE" then
		-- Open side aisles physically change the room's width as you traverse
		-- it. Each screen has a 3.2-stud side entrance; there are no sealed
		-- pockets or stairs to nowhere. A 12-stud central route stays clear.
		for _, side in ipairs({-1, 1}) do
			for _, dz in ipairs({{5.5, 8.4}, {11.6, 14}, {30, 32.4}, {35.6, 38.5}}) do
				local length = dz[2] - dz[1]
				roomBlock(room, "Side aisle masonry screen", 0.42, H, length,
					side * 6.2, H / 2, z + (dz[1] + dz[2]) / 2,
					style.wall, Enum.Material.Concrete)
			end
			for _, dz in ipairs({10, 34}) do
				roomBlock(room, "Aisle opening lintel", 0.6, H - 10.8, 3.2,
					side * 6.2, (H + 10.8) / 2, z + dz,
					C.woodDark, Enum.Material.Wood)
			end
		end
	elseif room.shape == "ROTUNDA" then
		for _, dz in ipairs({3.1, 41.6}) do
			for _, side in ipairs({-1, 1}) do
				local x = side * 9
				local shaft = roomBlock(room, "Rotunda monolithic column", 12.4, 1.04, 1.04,
					x, 6.2, z + dz, C.marble, Enum.Material.Marble)
				shaft.Shape = Enum.PartType.Cylinder
				shaft.CFrame = shaft.CFrame * CFrame.Angles(0, 0, math.pi / 2)
				roomBlock(room, "Rotunda square capital", 1.6, 0.53, 1.6,
					x, 12.65, z + dz, style.trim, Enum.Material.Metal)
			end
		end
		for spoke = 1, 8 do
			local theta = spoke * math.pi / 4
			local x, dz = math.cos(theta) * 8.9, math.sin(theta) * 8.9
			local spokeEnd = Vector3.new(x, room.entryY + H - 0.33, z + 22 + dz)
			local spokeStart = Vector3.new(0, room.entryY + H - 0.33, z + 22)
			local part = railBetween(room.model, "Rotunda ceiling spokes", spokeStart, spokeEnd,
				0.19, C.woodDark)
			part.Material = Enum.Material.Wood
		end
	elseif room.shape == "NAVE" then
		for _, dz in ipairs({2.8, 41.2}) do
			for _, side in ipairs({-1, 1}) do
				roomBlock(room, "Nave transept masonry", W / 2 - 6.8, H, 0.85,
					side * (W / 2 + 6.8) / 2, H / 2, z + dz,
					style.wall, Enum.Material.Concrete)
				roomBlock(room, "Nave upright", 0.36, 10.8, 1.2,
					side * 6.8, 5.4, z + dz, style.trim, Enum.Material.Metal)
			end
			roomBlock(room, "Nave hanging arch", 13.6, H - 10.8, 1.1,
				0, (H + 10.8) / 2, z + dz, C.woodDark, Enum.Material.Wood)
		end
		for _, side in ipairs({-1, 1}) do
			roomBlock(room, "Overhead nave gallery", 3.1, 0.7, 23,
				side * 12, H - 3.2, z + 22, C.woodDark, Enum.Material.Wood)
		end
	elseif room.shape == "CRYPT" then
		for _, side in ipairs({-1, 1}) do
			local x = side * 10.5
			roomBlock(room, "Crypt sealed plinth", 2.6, 2.8, 2.4,
				x, 1.4, z + 2.3, C.marble, Enum.Material.Marble)
			roomBlock(room, "Crypt faceless bust", 1.15, 2.2, 0.95,
				x, 3.48, z + 2.3, Color3.fromRGB(103, 112, 108), Enum.Material.Slate)
			for _, dz in ipairs({10, 22, 35}) do
				roomBlock(room, "Crypt wall niche", 0.2, 5.9, 3.5,
					side * 14.15, 9.7, z + dz, C.woodDark, Enum.Material.Slate)
				roomBlock(room, "Crypt arched lintel", 1.2, 0.65, 4.0,
					side * 13.4, 13.0, z + dz, style.trim, Enum.Material.Marble)
			end
		end
	end
end

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
	-- Fine inlaid planks read under the sconces, without raised edges that
	-- could change the height of the real walkable floor or block a raycast.
	for _, x in ipairs({-12.8, -10.4, -8.0, 8.0, 10.4, 12.8}) do
		roomDetail(room, "Inlaid floorboard joint", 0.035, 0.012, L - 1.6,
			x, 0.009, z + L / 2, C.woodDark, Enum.Material.Wood)
	end
	for _, dz in ipairs({6, 14, 30, 38}) do
		for _, side in ipairs({-1, 1}) do
			roomDetail(room, "Transverse parquet joint", 5.6, 0.012, 0.035,
				side * 10.4, 0.009, z + dz, C.woodDark, Enum.Material.Wood)
		end
	end
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
			for _, endZ in ipairs({-3.25, 3.25}) do
				roomDetail(room, "Engraved panel edge", 0.075, 5.7, 0.065,
					side * (W / 2 - 1), 7.65, z + dz + endZ,
					style.trim, Enum.Material.Metal)
			end
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
	local rosette = roomDetail(room, "Pressed metal ceiling rosette", 0.12, 2.7, 2.7,
		0, H - 0.42, z + L / 2, style.trim, Enum.Material.Metal)
	rosette.Shape = Enum.PartType.Cylinder
	rosette.CFrame = rosette.CFrame * CFrame.Angles(0, 0, math.pi / 2)
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
	elseif room.shape == "ROTUNDA" then
		-- A circular room is immediately identifiable FROM the doorway, not
		-- just by different wall paint or a random attribute on the Model.
		local disc = roomBlock(room, "Rotunda circular floor mosaic", 0.07, 10.5, 10.5,
			0, 0.08, z + 22, style.runner, Enum.Material.Marble)
		disc.Shape = Enum.PartType.Cylinder
		disc.CFrame = disc.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		disc.CanCollide = false
		for _, dz in ipairs({8, 36}) do
			roomBlock(room, "Rotunda approach carpet", 5.5, 0.06, 12,
				0, 0.055, z + dz, style.runner, Enum.Material.Fabric).CanCollide = false
		end
	elseif room.shape == "CRYPT" then
		for _, dz in ipairs({9, 22, 35}) do
			roomBlock(room, "Separated burial runner", 6.4, 0.06, 8,
				0, 0.055, z + dz, style.runner, Enum.Material.Fabric).CanCollide = false
		end
	else
		local width = room.shape == "AISLE" and 5.3 or 7.4
		local rug = roomBlock(room, "Worn crimson runner", width, 0.06, L - 6,
			0, 0.055, z + L / 2, style.runner, Enum.Material.Fabric)
		rug.CanCollide = false
		for _, x in ipairs({-width / 2 + 0.2, width / 2 - 0.2}) do
			local edging = roomBlock(room, "Runner gold edging", 0.1, 0.07, L - 6,
				x, 0.095, z + L / 2, style.trim, Enum.Material.Fabric)
			edging.CanCollide = false
		end
	end
	endWall(room, z + 0.45, y, y, y + H, room.index == 0)
	endWall(room, z + L - 0.45, y, y, y + H, false)
	roomArchitecture(room)
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
	if room.kind == "MARKET" then makeShop(room) end
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
	if room.dark then blackoutGuides(room) end
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
			room.wallColor, Enum.Material.Concrete)
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

-- The starting room ALSO varies. Each type and architectural plan is drawn
-- independently (not a fixed twelve-room loop); the last two draws are only
-- excluded to prevent immediately recognisable repetitions. The 30x44 outer
-- shell and door centres always meet, whatever the interior shape.
local function planRooms(seed)
	local rng = Random.new(seed)
	local kinds = {"HALL", "LIBRARY", "GALLERY", "SUITE", "STORAGE", "FLOODED",
		"DINING", "CONSERVATORY", "OFFICE", "CHAPEL", "LAUNDRY", "MIRROR"}
	local shapes = {"OPEN", "ARCADE", "COFFERED", "VESTIBULE", "AISLE",
		"ROTUNDA", "NAVE", "CRYPT"}
	local threats = {"RUSH", "BLIND", "MOTH", "ECHO"}
	local recent, recentShapes, threatBag, previousThreat = {}, {}, {}, nil
	local plan = {}
	local nextThreat, lastThreat, lastLock = rng:NextInteger(4, 8), -16, -5
	local forceThreat = 15
	local nextDark = rng:NextInteger(3, 6)
	local function drawThreat()
		if #threatBag == 0 then
			for _, name in ipairs(threats) do table.insert(threatBag, name) end
		end
		local pick = rng:NextInteger(1, #threatBag)
		if #threatBag > 1 and threatBag[pick] == previousThreat then pick = pick % #threatBag + 1 end
		return table.remove(threatBag, pick)
	end
	for index = 0, CONFIG.Doors - 1 do
		local stair, turn = Layout.IsStair(index), Layout.IsTurn(index, seed)
		local kind = stair and "STAIRWELL" or turn and "TURN"
		local shape = "FIXED"
		if not kind then
			local choices = {}
			for _, value in ipairs(kinds) do
				if value ~= recent[1] and value ~= recent[2] then table.insert(choices, value) end
			end
			kind = choices[rng:NextInteger(1, #choices)]
			table.insert(recent, kind)
			if #recent > 2 then table.remove(recent, 1) end
			local geometry = {}
			for _, value in ipairs(shapes) do
				-- Beds/pews/dining chairs would cover a side-aisle entrance.
				-- Keep their full-size furniture AND the lateral passage usable.
				local obstructed = value == "AISLE"
					and (kind == "SUITE" or kind == "DINING" or kind == "CHAPEL")
				if not obstructed and value ~= recentShapes[1] and value ~= recentShapes[2] then
					table.insert(geometry, value)
				end
			end
			shape = geometry[rng:NextInteger(1, #geometry)]
			table.insert(recentShapes, shape)
			if #recentShapes > 2 then table.remove(recentShapes, 1) end
		end
		local threat
		-- After an encounter there are at least 4 and at most 14 full rooms
		-- without a new monster. Eligible rooms still roll for its presence;
		-- stairs and doglegs never host a scripted encounter.
		if index >= nextThreat and not stair and not turn
			and (rng:NextNumber() < 0.62 or index >= forceThreat) then
			threat = drawThreat()
			lastThreat = index
			local eligible = {}
			for candidate = index + 5, math.min(CONFIG.Doors - 1, index + 15) do
				if not Layout.IsStair(candidate) and not Layout.IsTurn(candidate, seed) then
					table.insert(eligible, candidate)
				end
			end
			if #eligible > 0 then
				nextThreat = eligible[rng:NextInteger(1, #eligible)]
				forceThreat = eligible[#eligible]
			else
				nextThreat = CONFIG.Doors
			end
			previousThreat = threat
		end
		local locked = index >= 2 and index - lastLock >= 2 and not stair and not turn
			and not threat and rng:NextNumber() < 0.19
		if locked then lastLock = index end
		local dark = index >= nextDark and not stair
		if dark then nextDark = index + rng:NextInteger(3, 7) end
		plan[index] = {
			kind = kind, shape = shape, threat = threat, locked = locked, dark = dark,
			decorSeed = rng:NextInteger(1, 1000000000),
			style = rng:NextInteger(1, 4),
			lightPower = rng:NextNumber(0.78, 1.26),
		}
	end
	-- Exactly one findable shop per run, in a randomly chosen safe room AFTER
	-- door 50. Its counters replace that room's ordinary furniture, never a
	-- stair, lock, threat or narrow aisle; the central passage stays clear.
	local candidates = {}
	for index = 51, 86 do
		local room = plan[index]
		if room and not room.locked and not room.threat
			and (room.shape == "OPEN" or room.shape == "COFFERED") then
			table.insert(candidates, index)
		end
	end
	-- With 36 candidates spread over 12 interiors there is normally more
	-- than one; keep a fallback if a future layout changes that distribution.
	if #candidates == 0 then
		for index = 51, 95 do
			local room = plan[index]
			if room and not room.locked and not room.threat and room.shape ~= "FIXED"
				and room.shape ~= "AISLE" then table.insert(candidates, index) end
		end
	end
	local shopIndex = candidates[rng:NextInteger(1, #candidates)]
	plan[shopIndex].kind = "MARKET"
	plan[shopIndex].shop = true
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
	model:SetAttribute("Shape", plan.shape)
	model:SetAttribute("Dark", plan.dark)
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
		wallColor = WALL_STYLES[plan.style].wall, lightPower = plan.lightPower,
		shape = plan.shape, dark = plan.dark,
		lamps = {}, closets = {}, entered = {},
		entryY = Layout.EntranceY(index), exitY = Layout.ExitY(index),
		threat = threat, locked = locked, unlocked = not locked,
		open = false, busy = false, epoch = session,
	}
	state.rooms[index] = room
	-- Spatial room tone travels through an open door; old sections stop
	-- naturally when their containing room is pruned. No audio follows lamps.
	local air = newPart(model, "Unseen air in the corridor", Vector3.new(0.18, 0.18, 0.18),
		CFrame.new(0, room.entryY + 7, z + L / 2), C.shadow,
		Enum.Material.SmoothPlastic, 1, false)
	air.CanQuery = false
	room.air = soundAt(air, "Low draught in the masonry", "action_falling.ogg",
		room.dark and 0.10 or 0.075, 0.62, 58, true)
	room.air:Play()
	room.settling = soundAt(air, "Building settles", "action_get_up.mp3",
		0.25, 0.5, 66)
	if kind == "FLOODED" then
		room.water = soundAt(air, "Water beneath the boards", "action_swim.mp3",
			0.09, 0.68, 50, true)
		room.water:Play()
	end
	if isStair then stairRoom(room) else flatRoom(room, rng) end

	local door, leaf, prompt, hinge = hingeDoor(model, index + 1, z + L - 0.65, room.exitY)
	room.door = door
	room.leaf = leaf
	room.prompt = prompt
	room.hinge = hinge
	room.creak = soundAt(leaf, "Old door hinges", "action_get_up.mp3", 0.62, 0.67, 70)
	room.rattle = soundAt(leaf, "Locked brass rattle", "action_jump_land.mp3", 0.58, 0.78, 55)
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
		elseif room.threat == "ECHO" and not state.echo then
			room.threat = nil
			task.spawn(function() startEcho(room, mySession) end)
		end
	end)
end
-- A separate, genuinely collidable space follows door 100. Local exposure
-- makes its white-on-white surfaces look infinite; none of its edges are open.
local function enterVoidWalk(player, root, humanoid)
	local info = state.players[player]
	if not info or info.voidWalk or not root or not humanoid or humanoid.Health <= 0
		or state.hidden[player] or state.entering[player] or player:GetAttribute("Finished")
		or state.opened ~= CONFIG.Doors then return end
	local z = CONFIG.Doors * L
	if root.Position.Z < z + 2 or root.Position.Z > z + CONFIG.VoidLength - 3
		or math.abs(root.Position.X) > W / 2 - 1
		or math.abs(root.Position.Y - Layout.EntranceY(CONFIG.Doors) - 3) > 5 then return end
	info.voidWalk = true
	info.voidStart = state.clock
	info.sprinting, info.crouching, info.torchOn = false, false, false
	player:SetAttribute("Crouching", false)
	player:SetAttribute("VoidWalk", true)
	humanoid.WalkSpeed = CONFIG.VoidWalkSpeed
	syncInventory(player) -- extinguish the real hand torch, not the avatar
end

local function makeExit()
	if state.world:FindFirstChild("Exit") then return end
	local model = Instance.new("Model")
	model.Name = "Exit"
	model.Parent = state.world
	local z = CONFIG.Doors * L
	local y = Layout.EntranceY(CONFIG.Doors)
	local length = CONFIG.VoidLength
	local white = Color3.fromRGB(250, 253, 255)
	block(model, "Last floor", W, 1.3, length, 0, y - 0.65, z + length / 2,
		white, Enum.Material.SmoothPlastic)
	for _, side in ipairs({-1, 1}) do
		block(model, "White void wall", 0.8, H, length,
			side * (W / 2 - 0.4), y + H / 2, z + length / 2, white, Enum.Material.Neon)
	end
	block(model, "White void ceiling", W, 0.9, length, 0, y + H + 0.45,
		z + length / 2, white, Enum.Material.Neon)
	block(model, "Sealed white horizon", W, H, 0.8, 0, y + H / 2,
		z + length - 0.45, white, Enum.Material.Neon)
	-- Fine, non-colliding almost-erased floor coordinates suggest a broken
	-- simulation without turning this walk into another decorated corridor.
	for dz = 8, length - 4, 7 do
		local seam = newPart(model, "Faint emulation seam", Vector3.new(W - 1, 0.015, 0.035),
			CFrame.new(0, y + 0.016, z + dz), Color3.fromRGB(194, 221, 233),
			Enum.Material.SmoothPlastic, 0.84, false)
		seam.CanQuery = false
	end
	for _, dz in ipairs({6, 18, 30, 42}) do
		local source = newPart(model, "Unseen white light", Vector3.new(0.2, 0.2, 0.2),
			CFrame.new(0, y + H - 2, z + dz), white, Enum.Material.SmoothPlastic, 1, false)
		source.CanQuery = false
		local lamp = Instance.new("PointLight")
		lamp.Color = white
		lamp.Brightness = 6.5
		lamp.Range = 36
		lamp.Shadows = false
		lamp.Parent = source
	end
	-- This replicated model is ONLY a template for each player's close-up:
	-- never show it in the shared empty space to a teammate who has not arrived.
	local witness = makeFinalWitness(model)
	witness:PivotTo(CFrame.lookAt(Vector3.new(0, y + 5, z + length - 3),
		Vector3.new(0, y + 5, z + length - 15)))
	witness:SetAttribute("Concealed", true)
	for _, piece in ipairs(witness:GetDescendants()) do
		if piece:IsA("BasePart") then
			piece.Transparency = 1
		elseif piece:IsA("Highlight") or piece:IsA("PointLight")
			or piece:IsA("ParticleEmitter") then
			piece.Enabled = false
		end
	end
	local entry = newPart(model, "White threshold", Vector3.new(19, 9, 3),
		CFrame.new(0, y + 4.5, z + 3.5), white, Enum.Material.SmoothPlastic, 1, false)
	entry.CanTouch, entry.CanQuery = true, false
	local mySession = session
	entry.Touched:Connect(function(hit)
		if mySession ~= session then return end
		local avatar = hit:FindFirstAncestorOfClass("Model")
		local player = avatar and Players:GetPlayerFromCharacter(avatar)
		if player then
			local root, humanoid = playerRoot(player)
			enterVoidWalk(player, root, humanoid)
		end
	end)
	local trigger = newPart(model, "End of the nightmare", Vector3.new(19, 10, 3),
		CFrame.new(0, y + 5, z + CONFIG.VoidScareOffset), white,
		Enum.Material.SmoothPlastic, 1, false)
	trigger.CanTouch, trigger.CanQuery = true, false
	trigger.Touched:Connect(function(hit)
		if mySession ~= session then return end
		local avatar = hit:FindFirstAncestorOfClass("Model")
		local player = avatar and Players:GetPlayerFromCharacter(avatar)
		if not player or player:GetAttribute("Finished") then return end
		local root, humanoid = playerRoot(player)
		local info = state.players[player]
		if info and info.voidWalk and root and humanoid and humanoid.Health > 0
			and root.Position.Z >= z + CONFIG.VoidScareOffset - 1.5
			and state.clock - info.voidStart >= 4 then
			player:SetAttribute("Finished", true)
			humanoid.WalkSpeed = 0
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			-- Only this client gets the reveal and its audio. Other players still
			-- see an untouched, empty white horizon until they reach their end.
			remote:FireClient(player, "Finale", witness)
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
		local entering = state.entering[player]
		if entering and entering.closet.rootCF.Position.Z < first * L then
			cancelClosetEntry(player)
		end
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
		local swept = state.echo and index >= state.echo.origin and index <= state.echo.limit
		if index < first and not chased and not patrolled and not attracted and not swept then
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
	if state.hidden[player] or state.entering[player] then return end
	local room = state.rooms[index]
	if not room or room.epoch ~= session or room.busy or not room.prompt.Enabled then return end
	local root = playerRoot(player)
	if not root or (root.Position - room.leaf.Position).Magnitude > 12 then return end
	-- Previously visited doors really close and reopen. Neither a shut door nor
	-- a newly opened next door is a safe boundary against the Rush.
	if index < state.opened then
		recordNoise(room.leaf.Position, 53)
		swingDoor(room, not room.open)
		return
	end
	if index ~= state.opened or root.Position.Z < index * L + L - 13 then return end
	if not room.unlocked then
		if state.keys[player] == index then
			-- The same key must be in the finder’s real hand until it enters its
			-- OWN lock. The player's native Motor6D right arm raises that same
			-- welded key; only after the animation does the door open for the group.
			room.busy = true
			room.prompt.Enabled = false
			player:SetAttribute("KeyTurning", true)
			local mySession = session
			task.delay(CONFIG.KeyTurnSeconds, function()
				if room.epoch ~= session or mySession ~= session or not room.door.Parent then return end
				room.busy = false
				room.prompt.Enabled = true
				player:SetAttribute("KeyTurning", false)
				local holderRoot = playerRoot(player)
				if state.keys[player] ~= index or not holderRoot
					or (holderRoot.Position - room.leaf.Position).Magnitude > 12
					or state.opened ~= index then return end
				room.unlocked = true
				room.model:SetAttribute("Locked", false)
				putBackKey(player)
				if room.key.model.Parent then room.key.model:Destroy() end
				openDoor(player, index)
			end)
		else
			-- A physical rattle instead of advice about drawers or a key.
			recordNoise(room.leaf.Position, 62)
			room.rattle:Play()
			room.busy = true
			room.prompt.Enabled = false
			tweenPivot(room.door, room.hinge,
				room.hinge * CFrame.Angles(0, math.rad(-3), 0), 0.12, function()
				tweenPivot(room.door, room.hinge * CFrame.Angles(0, math.rad(-3), 0),
					room.hinge, 0.15, function()
						if room.epoch ~= session or not room.door.Parent then return end
						room.busy = false
						room.prompt.Enabled = true
					end)
			end)
		end
		return
	end
	-- Construct the next enclosed segment before swinging the leaf open.
	recordNoise(room.leaf.Position, 64)
	if index == CONFIG.Doors - 1 then makeExit() end
	state.opened = index + 1
	state.world:SetAttribute("DoorsOpened", state.opened)
	for nextIndex = state.opened, math.min(CONFIG.Doors - 1, state.opened + CONFIG.Ahead - 1) do
		buildRoom(nextIndex)
	end
	local nextRoom = state.rooms[state.opened]
	if nextRoom then
		nextRoom.prompt.Enabled = true
		-- Build BOTH the figure and its initial pose BEFORE the hinge moves.
		-- A teammate can see it through the doorway without touching a sensor.
		if nextRoom.threat == "BLIND" and not state.blind then
			nextRoom.threat = nil
			startBlind(nextRoom, session)
		elseif nextRoom.threat == "MOTH" and not state.moth then
			nextRoom.threat = nil
			startMoth(nextRoom, session)
		end
		if Random.new(state.seed + index * 283 + 7):NextNumber() < 0.32 then
			nextRoom.settling:Play()
		end
	end
	swingDoor(room, true)
	pruneRooms()
end

-- Four hazards and a separate final apparition, all sculpted from smooth
-- physical parts. Their limbs are display-only: damage is server-authoritative,
-- never caused by invisible collision on a decorative appendage.
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
	halo.OutlineTransparency = 0.57
	halo.Parent = entity
end

-- Thin irregular-looking pieces make a pale orbital rim WITHOUT a glowing
-- cartoon pupil, flat image asset or a Roblox decal. The face faces local -Z.
local function hollowEyes(parent, x, y, z, radiusX, radiusY, bone, void)
	for _, side in ipairs({-1, 1}) do
		local cx = side * x
		-- A continuous, pale ellipse remains visible behind the deeper void.
		-- The small uneven pieces roughen its contour, not replace the ring.
		creaturePart(parent, "Pale orbital surround",
			Vector3.new(radiusX * 2.55, radiusY * 2.43, 0.11),
			CFrame.new(cx, y, z + 0.02), bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creaturePart(parent, "Sunken eye pit", Vector3.new(radiusX * 2.1, radiusY * 2.03, 0.16),
			CFrame.new(cx, y, z - 0.04), void, Enum.Material.Slate, 0, Enum.PartType.Ball)
		for bead = 1, 14 do
			local theta = bead * math.pi * 2 / 14
			local fragment = creaturePart(parent, "Chalk orbital ring",
				Vector3.new(0.13, 0.18, 0.11),
				CFrame.new(cx + math.cos(theta) * radiusX, y + math.sin(theta) * radiusY, z - 0.1),
				bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
			fragment.CanCollide = false
		end
		creaturePart(parent, "Bottomless pupil", Vector3.new(radiusX * 1.45, radiusY * 1.54, 0.14),
			CFrame.new(cx, y - 0.025, z - 0.16), void, Enum.Material.Slate, 0, Enum.PartType.Ball)
	end
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
	return mist
end

-- Rush: foretold only by LIGHT, never by a warning sound. It starts three
-- rooms behind, navigates the enclosed stairs and offset archways, and keeps
-- chasing through doors opened while it is moving. A single door is no refuge.
local function makeRush()
	local entity = Instance.new("Model")
	entity.Name = "TheRush"
	entity.Parent = state.world
	local soot = Color3.fromRGB(11, 14, 18)
	local ash = Color3.fromRGB(40, 43, 46)
	local bone = Color3.fromRGB(176, 175, 161)
	local ghostWhite = Color3.fromRGB(215, 216, 196)
	local torso = creaturePart(entity, "Hollow black chest", Vector3.new(2.45, 5.05, 1.42),
		CFrame.new(0, 0.15, 0) * CFrame.Angles(math.rad(-10), 0, 0),
		soot, Enum.Material.Slate, 0.02, Enum.PartType.Ball)
	entity.PrimaryPart = torso
	creaturePart(entity, "Torn shadow behind the ribs", Vector3.new(2.8, 4.8, 1.16),
		CFrame.new(0, -1.4, 0.7) * CFrame.Angles(math.rad(8), 0, 0),
		ash, Enum.Material.Slate, 0.42, Enum.PartType.Ball)
	local claws, legs = {}, {}
	for _, side in ipairs({-1, 1}) do
		local claw = Instance.new("Model")
		claw.Name = side == -1 and "Left hooked arm" or "Right hooked arm"
		claw.Parent = entity
		local hinge = CFrame.new(side * 1.55, 1.65, 0)
		claw.WorldPivot = hinge
		table.insert(claws, {model = claw, hinge = hinge, side = side})
		creaturePart(claw, "Raised crooked shoulder", Vector3.new(0.96, 1.19, 0.97),
			CFrame.new(side * 1.55, 1.65, 0), ash, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(claw, "Long upper arm", Vector3.new(side * 1.7, 1.4, -0.1),
			Vector3.new(side * 2.75, -0.35, -0.62), 0.34, soot)
		creaturePart(claw, "Knotted elbow", Vector3.new(0.48, 0.54, 0.48),
			CFrame.new(side * 2.75, -0.35, -0.62), ash, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(claw, "Sweeping forearm", Vector3.new(side * 2.75, -0.35, -0.62),
			Vector3.new(side * 3.0, -2.35, -1.45), 0.26, soot)
		for finger = 1, 3 do
			local spread = (finger - 2) * 0.33
			creatureLimb(claw, "Three hooked talons", Vector3.new(side * 3.0 + spread, -2.33, -1.42),
				Vector3.new(side * 3.3 + spread * 1.3, -3.22 - finger * 0.12, -2.04),
				0.13, bone, Enum.Material.Slate)
		end
		local leg = Instance.new("Model")
		leg.Name = side == -1 and "Left running leg" or "Right running leg"
		leg.Parent = entity
		local hip = CFrame.new(side * 0.79, -1.78, 0.18)
		leg.WorldPivot = hip
		local knee = Vector3.new(side * 1.12, -3.23, 0.31)
		creaturePart(entity, "Joined hip socket", Vector3.new(0.84, 0.85, 0.74),
			CFrame.new(side * 0.79, -1.78, 0.18), soot, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(leg, "Thigh fixed to hip", hip.Position, knee, 0.67, soot, Enum.Material.Slate)
		creaturePart(leg, "Knee joint", Vector3.new(0.59, 0.60, 0.59),
			CFrame.new(knee), ash, Enum.Material.Slate, 0, Enum.PartType.Ball)
		local shin = Instance.new("Model")
		shin.Name = "Bent running shin"
		shin.Parent = leg
		shin.WorldPivot = CFrame.new(knee)
		creatureLimb(shin, "Long shin fixed to knee", knee,
			Vector3.new(side * 1.14, -4.55, 0.4), 0.39, soot, Enum.Material.Slate)
		creaturePart(shin, "Bare dragging foot", Vector3.new(0.8, 0.40, 1.24),
			CFrame.new(side * 1.14, -4.78, -0.18), soot,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		table.insert(legs, {model = leg, hinge = hip, shin = shin,
			kneeOffset = knee - hip.Position, side = side})
		for rib = 1, 3 do
			creatureLimb(entity, "Exposed broken rib", Vector3.new(side * 0.29, 0.88 - rib * 0.72, -0.95),
				Vector3.new(side * 1.37, 1.12 - rib * 0.72, -0.56),
				0.14, ash, Enum.Material.Slate)
		end
	end
	local skull = creaturePart(entity, "Cracked funeral mask", Vector3.new(2.19, 2.8, 1.35),
		CFrame.new(0, 3.23, -0.51) * CFrame.Angles(math.rad(-8), 0, 0),
		bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
	hollowEyes(entity, 0.53, 3.51, -1.21, 0.38, 0.43, ghostWhite, soot)
	for _, side in ipairs({-1, 1}) do
		creatureLimb(entity, "Asymmetric crack in the mask", Vector3.new(side * 0.89, 4.32, -0.83),
			Vector3.new(side * 0.69, 3.95, -1.15), 0.06, ash, Enum.Material.Slate)
	end
	local jaw = Instance.new("Model")
	jaw.Name = "Hinged split mandible"
	jaw.Parent = entity
	local jawHinge = CFrame.new(0, 2.72, -1.10)
	jaw.WorldPivot = jawHinge
	creaturePart(jaw, "Open dark jaw", Vector3.new(1.24, 0.55, 0.27),
		CFrame.new(0, 2.35, -1.29), soot, Enum.Material.Slate, 0, Enum.PartType.Ball)
	for tooth = -1, 1 do
		creaturePart(jaw, "Small enamel shard", Vector3.new(0.085, 0.19, 0.075),
			CFrame.new(tooth * 0.33, 2.47, -1.44), bone,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
	end
	for _, side in ipairs({-1, 1}) do
		creatureLimb(jaw, "Mandible tendon", Vector3.new(side * 0.53, 2.39, -1.16),
			Vector3.new(side * 0.81, 2.88, -0.83), 0.12, ash, Enum.Material.Slate)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Cold light on the mask"
	glow.Color = Color3.fromRGB(174, 186, 185)
	glow.Brightness = 0.75
	glow.Range = 10
	glow.Parent = skull
	creatureHalo(entity, Color3.fromRGB(28, 31, 34), Color3.fromRGB(140, 147, 145))
	-- The body's narrow silhouette is followed by a wide, thin ash wake:
	-- it suggests the room-wide danger without a flat opaque wall of parts.
	for _, x in ipairs({-9, -4.5, 0, 4.5, 9}) do
		creatureMist(torso, "Cold ash wake", Vector3.new(x, -1.8, 1.5),
			Color3.fromRGB(33, 30, 36), x == 0 and 28 or 13, x == 0 and 3.0 or 2.1)
	end
	return entity, claws, glow, jaw, jawHinge, legs
end

-- Echo is NOT a recoloured Rush. It has a narrow hanging body, porcelain
-- mask, connected pendulum arms and trailing veils hinged at the shoulders.
-- Returning passes physically open the veils and expose cracks in the mask.
local function makeEcho()
	local entity = Instance.new("Model")
	entity.Name = "TheEcho"
	entity.Parent = state.world
	local void = Color3.fromRGB(9, 12, 20)
	local charcoal = Color3.fromRGB(34, 37, 50)
	local bone = Color3.fromRGB(204, 216, 218)
	local chalk = Color3.fromRGB(234, 240, 235)
	local frost = Color3.fromRGB(135, 171, 188)
	local torso = creaturePart(entity, "Sunken echo thorax", Vector3.new(1.86, 4.88, 1.15),
		CFrame.new(0, 0.16, 0.31) * CFrame.Angles(math.rad(-17), 0, 0),
		void, Enum.Material.Slate, 0, Enum.PartType.Ball)
	entity.PrimaryPart = torso
	creaturePart(entity, "Hollow waist", Vector3.new(1.15, 1.26, 1.02),
		CFrame.new(0, -1.49, 0.38), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
	creatureLimb(entity, "Continuous narrow neck", Vector3.new(0, 1.72, -0.18),
		Vector3.new(0, 2.81, -0.53), 0.43, void, Enum.Material.Slate)
	local arms, legs, veils, shrouds = {}, {}, {}, {}
	for _, side in ipairs({-1, 1}) do
		local shoulder = Vector3.new(side * 1.34, 1.53, 0.09)
		creatureLimb(entity, "Spindly joined collar", Vector3.new(side * 0.28, 1.65, 0.02),
			shoulder, 0.31, charcoal, Enum.Material.Slate)
		creaturePart(entity, "Echo shoulder socket", Vector3.new(0.63, 0.76, 0.64),
			CFrame.new(shoulder), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		local arm = Instance.new("Model")
		arm.Name = side == -1 and "Left pendulum arm" or "Right pendulum arm"
		arm.Parent = entity
		local hinge = CFrame.new(shoulder)
		arm.WorldPivot = hinge
		table.insert(arms, {model = arm, hinge = hinge, side = side})
		local elbow = Vector3.new(side * 2.10, -0.52, -0.46)
		local wrist = Vector3.new(side * 2.52, -2.64, -1.09)
		creatureLimb(arm, "Echo upper arm", shoulder, elbow, 0.29, void, Enum.Material.Slate)
		creaturePart(arm, "Echo elbow joint", Vector3.new(0.38, 0.46, 0.37),
			CFrame.new(elbow), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(arm, "Suspended long forearm", elbow, wrist, 0.20, void, Enum.Material.Slate)
		creaturePart(arm, "Narrow connected palm", Vector3.new(0.37, 0.43, 0.40),
			CFrame.new(wrist), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		for finger = 1, 4 do
			local spread = (finger - 2.5) * 0.16
			creatureLimb(arm, "Thin listening fingers", wrist + Vector3.new(spread, -0.13, 0),
				wrist + Vector3.new(spread * 1.3, -0.91 - finger * 0.07, -0.46),
				0.085, frost, Enum.Material.Slate)
		end
		local hip = CFrame.new(side * 0.59, -1.80, 0.33)
		local knee = Vector3.new(side * 0.90, -3.28, 0.41)
		creaturePart(entity, "Echo joined hip", Vector3.new(0.68, 0.77, 0.68),
			hip, charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		local leg = Instance.new("Model")
		leg.Name = side == -1 and "Left echo leg" or "Right echo leg"
		leg.Parent = entity
		leg.WorldPivot = hip
		creatureLimb(leg, "Hanging thigh", hip.Position, knee, 0.46, void, Enum.Material.Slate)
		creaturePart(leg, "Echo knee joint", Vector3.new(0.44, 0.49, 0.44),
			CFrame.new(knee), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		local shin = Instance.new("Model")
		shin.Name = "Trailing echo shin"
		shin.Parent = leg
		shin.WorldPivot = CFrame.new(knee)
		creatureLimb(shin, "Attached narrow shin", knee,
			Vector3.new(side * 0.85, -4.48, 0.31), 0.27, void, Enum.Material.Slate)
		creaturePart(shin, "Quiet dragging foot", Vector3.new(0.59, 0.34, 1.01),
			CFrame.new(side * 0.86, -4.70, -0.19), charcoal,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		table.insert(legs, {model = leg, hinge = hip, shin = shin,
			kneeOffset = knee - hip.Position, side = side})
		local veil = Instance.new("Model")
		veil.Name = side == -1 and "Left trailing veil" or "Right trailing veil"
		veil.Parent = entity
		local veilHinge = CFrame.new(side * 0.86, 1.43, 0.51)
		veil.WorldPivot = veilHinge
		table.insert(veils, {model = veil, hinge = veilHinge, side = side})
		creatureLimb(veil, "Veil rooted in shoulder", veilHinge.Position,
			Vector3.new(side * 1.70, 0.73, 1.14), 0.39, charcoal, Enum.Material.Slate, 0.12)
		creatureLimb(veil, "Long receding veil", Vector3.new(side * 1.70, 0.73, 1.14),
			Vector3.new(side * 2.78, -1.46, 2.30), 0.26, charcoal, Enum.Material.Slate, 0.09)
		local shroud = creaturePart(veil, "Torn echo shroud", Vector3.new(1.03, 3.23, 0.34),
			CFrame.new(side * 2.40, -0.65, 1.72)
				* CFrame.Angles(math.rad(-19), 0, side * math.rad(14)),
			Color3.fromRGB(75, 83, 99), Enum.Material.Fabric, 0.57, Enum.PartType.Ball)
		table.insert(shrouds, shroud)
		creatureLimb(veil, "Frayed veil end", Vector3.new(side * 2.78, -1.46, 2.30),
			Vector3.new(side * 3.18, -2.87, 2.61), 0.12, frost, Enum.Material.Slate, 0.23)
		for rib = 1, 3 do
			creatureLimb(entity, "Fine bridged echo rib",
				Vector3.new(side * 0.22, 1.05 - rib * 0.66, -0.52),
				Vector3.new(side * 0.87, 1.13 - rib * 0.63, -0.27),
				0.11, charcoal, Enum.Material.Slate)
		end
	end
	creaturePart(entity, "Long hollow porcelain face", Vector3.new(1.92, 3.17, 1.13),
		CFrame.new(0, 3.42, -0.58) * CFrame.Angles(math.rad(-9), 0, 0),
		bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
	hollowEyes(entity, 0.46, 3.77, -1.18, 0.36, 0.49, chalk, void)
	local marks = {}
	for _, side in ipairs({-1, 1}) do
		table.insert(marks, creatureLimb(entity, "Return face fracture",
			Vector3.new(side * 0.91, 4.22, -0.94),
			Vector3.new(side * 0.77, 3.30, -1.11), 0.09, void, Enum.Material.Slate, 0.94))
		table.insert(marks, creatureLimb(entity, "Return jaw fracture",
			Vector3.new(side * 0.77, 3.30, -1.11),
			Vector3.new(side * 0.36, 2.58, -1.05), 0.08, void, Enum.Material.Slate, 0.94))
	end
	local jaw = Instance.new("Model")
	jaw.Name = "Echo shutter jaw"
	jaw.Parent = entity
	local jawHinge = CFrame.new(0, 2.72, -1.02)
	jaw.WorldPivot = jawHinge
	creaturePart(jaw, "Lower porcelain shutter", Vector3.new(1.08, 0.72, 0.40),
		CFrame.new(0, 2.41, -1.16), bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
	creaturePart(jaw, "Sealed black throat", Vector3.new(0.64, 0.23, 0.14),
		CFrame.new(0, 2.55, -1.39), void, Enum.Material.Slate, 0, Enum.PartType.Ball)
	for _, side in ipairs({-1, 1}) do
		creatureLimb(jaw, "Hinged echo tendon", Vector3.new(side * 0.45, 2.45, -1.06),
			Vector3.new(side * 0.63, 2.90, -0.78), 0.11, charcoal, Enum.Material.Slate)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Cold return-mask light"
	glow.Color = frost
	glow.Brightness = 0.70
	glow.Range = 11
	glow.Parent = entity:FindFirstChild("Long hollow porcelain face")
	creatureHalo(entity, Color3.fromRGB(25, 31, 39), Color3.fromRGB(119, 153, 173))
	local mist = {}
	for _, x in ipairs({-1.0, 0, 1.0}) do
		table.insert(mist, creatureMist(torso, "Receding echo dust",
			Vector3.new(x, -1.43, 1.00), frost, 5, 0.98))
	end
	return entity, arms, glow, jaw, jawHinge, legs, veils, marks, mist, shrouds
end

makeFinalWitness = function(parent)
	local figure = Instance.new("Model")
	figure.Name = "TheLastWitness"
	figure.Parent = parent
	local void = Color3.fromRGB(6, 9, 12)
	local flesh = Color3.fromRGB(27, 31, 32)
	local bone = Color3.fromRGB(204, 206, 188)
	local chalk = Color3.fromRGB(234, 232, 210)
	local chest = creaturePart(figure, "Impossible narrow torso", Vector3.new(1.85, 4.4, 1.12),
		CFrame.new(0, 0.08, 0.38) * CFrame.Angles(math.rad(-13), 0, 0),
		void, Enum.Material.Slate, 0, Enum.PartType.Ball)
	figure.PrimaryPart = chest
	for _, side in ipairs({-1, 1}) do
		creaturePart(figure, "Joined hip", Vector3.new(0.65, 0.63, 0.6),
			CFrame.new(side * 0.47, -1.7, 0.29), flesh, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(figure, "Joined thin thigh", Vector3.new(side * 0.47, -1.7, 0.29),
			Vector3.new(side * 0.72, -3.25, -0.12), 0.35, flesh, Enum.Material.Slate)
		creaturePart(figure, "Knee", Vector3.new(0.37, 0.43, 0.36),
			CFrame.new(side * 0.72, -3.23, -0.12), flesh, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(figure, "Thin shin", Vector3.new(side * 0.72, -3.2, -0.12),
			Vector3.new(side * 0.8, -4.43, 0), 0.2, void, Enum.Material.Slate)
		creaturePart(figure, "Foot without a shoe", Vector3.new(0.54, 0.27, 1.05),
			CFrame.new(side * 0.8, -4.55, -0.45), flesh,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		local elbow = Vector3.new(side * 1.79, -0.21, -0.66)
		local wrist = Vector3.new(side * 1.69, -2.98, -1.08)
		creaturePart(figure, "Joined shoulder", Vector3.new(0.79, 0.81, 0.74),
			CFrame.new(side * 0.97, 1.86, 0), flesh, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(figure, "Too long upper arm", Vector3.new(side * 0.97, 1.86, 0),
			elbow, 0.31, void, Enum.Material.Slate)
		creaturePart(figure, "Bony joint", Vector3.new(0.45, 0.46, 0.44),
			CFrame.new(elbow), flesh, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(figure, "Too long lower arm", elbow, wrist, 0.21, void, Enum.Material.Slate)
		creaturePart(figure, "Joined wrist", Vector3.new(0.31, 0.36, 0.32),
			CFrame.new(wrist), flesh, Enum.Material.Slate, 0, Enum.PartType.Ball)
		for finger = 1, 5 do
			local offset = (finger - 3) * 0.13
			creatureLimb(figure, "Dangling needle finger",
				Vector3.new(wrist.X + offset, -3.04, -1.12),
				Vector3.new(wrist.X + offset * 1.4, -4.05 - finger * 0.09, -1.37),
				0.065, flesh, Enum.Material.Slate)
		end
		for rib = 1, 4 do
			creatureLimb(figure, "Rib breaking the skin",
				Vector3.new(side * 0.14, 1.06 - rib * 0.51, -0.59),
				Vector3.new(side * 0.78, 1.12 - rib * 0.53, -0.41),
				0.09, flesh, Enum.Material.Slate)
		end
	end
	creatureLimb(figure, "Bent neck", Vector3.new(0, 1.78, -0.32),
		Vector3.new(0, 2.83, -0.58), 0.32, void, Enum.Material.Slate)
	local face = creaturePart(figure, "The face behind the dawn", Vector3.new(2.57, 3.22, 1.4),
		CFrame.new(0, 3.68, -0.65) * CFrame.Angles(math.rad(-9), 0, 0),
		bone, Enum.Material.Slate, 0, Enum.PartType.Ball)
	hollowEyes(figure, 0.63, 3.91, -1.37, 0.48, 0.55, chalk, void)
	creaturePart(figure, "Closed black mouth", Vector3.new(0.84, 0.13, 0.1),
		CFrame.new(0, 2.97, -1.31), void, Enum.Material.Slate, 0, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Name = "Light on the final eyes"
	light.Color = Color3.fromRGB(211, 220, 210)
	light.Brightness = 1.05
	light.Range = 12
	light.Parent = face
	creatureHalo(figure, Color3.fromRGB(35, 39, 40), Color3.fromRGB(194, 199, 181))
	return figure
end

local function pathPoint(z)
	local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(z))
	local localZ = math.clamp(z - index * L, 0, L)
	return Vector3.new(Layout.PathX(index, localZ, state.seed), Layout.WalkwayY(index, localZ) + 5, z)
end

tryCrucifix = function(player, entity)
	local info = state.players[player]
	if not info or state.hidden[player] or info.selected ~= 3
		or info.items.CRUCIFIX < 1 or not entity or not entity.Parent
		or entity:GetAttribute("Banished") then return false end
	info.items.CRUCIFIX = info.items.CRUCIFIX - 1
	entity:SetAttribute("Banished", true)
	for _, key in ipairs({"rush", "blind", "moth", "echo"}) do
		if state[key] and state[key].entity == entity then state[key].banished = true end
	end
	syncInventory(player)
	remote:FireClient(player, "ItemUsed", "CRUCIFIX")
	local pivot = entity:GetPivot()
	tweenPivot(entity, pivot, pivot * CFrame.new(0, -11, 0), 0.75, function()
		if entity.Parent then entity:Destroy() end
	end)
	return true
end

-- The equipped cross still saves its wearer on contact, but it can also be
-- deliberately raised against a nearby creature. Solid hotel walls/closed
-- doors block this short-range action; an empty corridor does not spend it.
local function raiseCrucifix(player, root)
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local nearest, distance = nil, 20
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true
	rayParams.FilterDescendantsInstances = {player.Character}
	for _, key in ipairs({"rush", "blind", "moth", "echo"}) do
		local threat = state[key]
		local entity = threat and threat.entity
		if entity and entity.Parent and entity.PrimaryPart and not threat.banished
			and not entity:GetAttribute("Banished") then
			local point = entity:GetPivot().Position
			local range = (point - origin).Magnitude
			if range <= distance then
				rayParams.FilterDescendantsInstances = {player.Character, entity}
				if not Workspace:Raycast(origin, point - origin, rayParams) then
					nearest, distance = entity, range
				end
			end
		end
	end
	return nearest ~= nil and tryCrucifix(player, nearest)
end

local function killPlayer(player, humanoid, kind, entity)
	if humanoid.Health <= 0 or player:GetAttribute("Finished")
		or (entity and entity:GetAttribute("Banished")) then return end
	if tryCrucifix(player, entity) then return end
	-- The victim's own client gets the ACTUAL creature for a close-up. Keep its
	-- model replicated until the scare ends, even if the patrol ends this frame.
	if entity then entity:SetAttribute("RecentKill", true) end
	remote:FireClient(player, "Jumpscare", kind, entity)
	local info = state.players[player]
	if info then info.health = 0; player:SetAttribute("Health", 0) end
	humanoid.Health = 0
end
local function retireMonster(entity)
	if not entity.Parent or entity:GetAttribute("Banished") then return end
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
	-- Only the PHYSICAL sconces/fittings blink. No GUI flash, colour wash,
	-- screen text or sound tells the player what the light means.
	local rng = Random.new(state.seed + room.index * 97 + 41)
	for _ = 1, math.ceil(CONFIG.RushWarningSeconds / 0.2) do
		if epoch ~= session then return end
		for index = origin, math.min(room.index + 1, limit) do
			local litRoom = state.rooms[index]
			if litRoom then
				for _, lamp in ipairs(litRoom.lamps) do
					setLamp(lamp, rng:NextNumber() > 0.48)
				end
			end
		end
		task.wait(0.2)
	end
	if epoch ~= session then return end
	local entity, claws, glow, jaw, jawHinge, legs = makeRush()
	rush.entity = entity
	local z = rush.positionZ
	entity:PivotTo(CFrame.lookAt(pathPoint(z), pathPoint(z) + Vector3.new(0, 0, 1)))
	announceMonster(room, "RUSH", entity) -- the flicker itself remains SILENT
	local maxZ = (limit + 1) * L - 4
	local elapsed, stalled = 0, 0
	while epoch == session and not rush.banished and elapsed < CONFIG.RushMaximumSeconds do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
		if epoch ~= session or rush.banished then break end
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
		jaw:PivotTo(facing * jawHinge
			* CFrame.Angles(-0.26 - math.sin(elapsed * 10) * 0.19, 0, 0))
		for _, leg in ipairs(legs) do
			local stride = math.sin(elapsed * 9 + (leg.side == -1 and 0 or math.pi))
			local hipCF = facing * leg.hinge * CFrame.Angles(stride * 0.37, 0, 0)
			leg.model:PivotTo(hipCF)
			leg.shin:PivotTo(hipCF * CFrame.new(leg.kneeOffset)
				* CFrame.Angles(math.max(0, stride) * 0.40, 0, 0))
		end
		glow.Brightness = 0.68 + math.sin(elapsed * 13) * 0.16
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
				setLamp(lamp, lamp.normallyOn)
			end
		end
	end
	state.rush = nil
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
	-- A room with side aisles has REAL inner screens. Roaming creatures use
	-- their side openings at z10/34 instead of phasing through masonry to a
	-- player in an alcove (including a player who retreated through a door).
	local here = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(position.Z))
	local target = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(destination.Z))
	local room = state.rooms[here]
	if room and room.shape == "AISLE" then
		local localZ = position.Z - here * L
		local targetZ = destination.Z - here * L
		local function screened(dz)
			return dz >= 5.5 and dz <= 14 or dz >= 30 and dz <= 38.5
		end
		local side = math.abs(position.X) > 6.6 and screened(localZ)
		local wantsSide = here == target and math.abs(destination.X) > 6.6 and screened(targetZ)
		local opposite = position.X * destination.X < 0
		if side and (here ~= target or not wantsSide or opposite)
			or wantsSide and math.abs(position.X) < 5.9 then
			local gap = (wantsSide and targetZ or localZ) < 22 and 10 or 34
			local gateZ = here * L + gap
			if math.abs(position.Z - gateZ) > 0.8 then
				destination = Vector3.new(position.X, destination.Y, gateZ)
			else
				destination = Vector3.new(wantsSide and destination.X or 0, destination.Y, gateZ)
			end
		end
	end
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
		if root and info and not player:GetAttribute("Finished")
			and root.Position.Z >= nearZ and root.Position.Z <= farZ then
			local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(root.Position.Z))
			local floorY = Layout.WalkwayY(index, root.Position.Z - index * L)
			local awake = kind == "MOTH" and info.torchOn and not state.hidden[player]
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

local function blindTarget(blind, position, nearZ, farZ, patrolZ)
	-- Latest AUDIBLE position wins, even if the previous sound was across a
	-- closed doorway. No position is read from a motionless player's avatar.
	for i = #state.noises, 1, -1 do
		local noise = state.noises[i]
		if noise.serial <= (blind.lastSerial or 0) then break end
		local planar = Vector3.new(noise.position.X - position.X, 0, noise.position.Z - position.Z)
		if noise.position.Z >= nearZ and noise.position.Z <= farZ
			and math.abs(noise.position.Y - position.Y) < 8
			and planar.Magnitude <= noise.radius then
			blind.lastSound = noise.position
			blind.lastHeard = state.clock
			blind.lastSerial = noise.serial
			break
		end
	end
	if blind.lastSound then
		local point = blind.lastSound
		local planar = Vector3.new(point.X - position.X, 0, point.Z - position.Z)
		if planar.Magnitude < 2.3 and state.clock - blind.lastHeard > 0.8 then
			blind.lastSound = nil
		else
			return point, planar.Magnitude
		end
	end
	return Vector3.new(0, position.Y, patrolZ), math.huge
end

-- The Blind Guest comes FROM the room ahead. It cannot see a silent crouching
-- player, but hears footsteps and occupied wardrobes even across open doors.
local function makeBlind()
	local entity = Instance.new("Model")
	entity.Name = "TheBlindGuest"
	entity.Parent = state.world
	-- Based on the supplied uncanny-humanoid reference: nearly black,
	-- emaciated and stooped, with an oval bone face and enormous empty eyes.
	-- No uniform, coat, neon pupils or block-built Roblox killer outfit.
	local soot = Color3.fromRGB(15, 18, 20)
	local charcoal = Color3.fromRGB(31, 35, 35)
	local sinew = Color3.fromRGB(51, 57, 54)
	local ivory = Color3.fromRGB(195, 197, 180)
	local rim = Color3.fromRGB(222, 223, 204)
	local void = Color3.fromRGB(3, 6, 8)
	local chest = creaturePart(entity, "Hunched hollow thorax", Vector3.new(1.67, 3.9, 1.08),
		CFrame.new(0, 0.48, 0.12) * CFrame.Angles(math.rad(-13), 0, 0),
		soot, Enum.Material.Slate, 0, Enum.PartType.Ball)
	entity.PrimaryPart = chest
	creaturePart(entity, "Sunken abdomen", Vector3.new(1.14, 1.75, 0.84),
		CFrame.new(0, -1.57, 0.32), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
	creatureLimb(entity, "Rigid sternum", Vector3.new(0, 1.53, -0.73),
		Vector3.new(0, -1.03, -0.54), 0.13, sinew, Enum.Material.Slate)
	for rib = 1, 5 do
		for _, side in ipairs({-1, 1}) do
			creatureLimb(entity, "Ribs under stretched skin",
				Vector3.new(side * 0.08, 1.12 - rib * 0.49, -0.7),
				Vector3.new(side * (0.73 - rib * 0.05), 1.32 - rib * 0.51, -0.49),
				0.085, sinew, Enum.Material.Slate)
		end
	end
	local limbs = {}
	for _, side in ipairs({-1, 1}) do
		creaturePart(entity, "Uneven shoulder blade", Vector3.new(0.78, 0.52, 0.8),
			CFrame.new(side * 0.92, 1.84, -0.06), charcoal,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		local arm = Instance.new("Model")
		arm.Name = side == -1 and "Left searching arm" or "Right searching arm"
		arm.Parent = entity
		local armHinge = CFrame.new(side * 0.95, 1.78, -0.15)
		arm.WorldPivot = armHinge
		table.insert(limbs, {model = arm, hinge = armHinge, side = side, sway = 0.16})
		local elbow = Vector3.new(side * 1.65, -0.45, -0.5)
		local wrist = Vector3.new(side * 1.87, -2.5, -0.9)
		creatureLimb(arm, "Stretch of upper arm", Vector3.new(side * 0.95, 1.79, -0.15),
			elbow, 0.35, soot, Enum.Material.Slate)
		creaturePart(arm, "Bony protruding elbow", Vector3.new(0.44, 0.43, 0.44),
			CFrame.new(elbow), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(arm, "Too long lower arm", elbow, wrist, 0.23, soot, Enum.Material.Slate)
		creaturePart(arm, "Palm with no fingerprints", Vector3.new(0.42, 0.51, 0.24),
			CFrame.new(wrist + Vector3.new(0, -0.25, -0.08)),
			charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		for finger = 1, 5 do
			local offset = (finger - 3) * 0.11
			creatureLimb(arm, "Threadlike feeling finger",
				Vector3.new(wrist.X + offset, -2.81, -0.94),
				Vector3.new(wrist.X + offset * 1.6 + side * 0.08,
					-3.6 - (finger % 2) * 0.12, -1.24), 0.065, sinew)
		end
		local leg = Instance.new("Model")
		leg.Name = side == -1 and "Left walking leg" or "Right walking leg"
		leg.Parent = entity
		local legHinge = CFrame.new(side * 0.46, -1.78, 0.25)
		leg.WorldPivot = legHinge
		creaturePart(entity, "Connected hip joint", Vector3.new(0.71, 0.72, 0.69),
			legHinge, soot, Enum.Material.Slate, 0, Enum.PartType.Ball)
		local knee = Vector3.new(side * 0.62, -3.08, -0.12)
		creatureLimb(leg, "Knot of dark thigh", Vector3.new(side * 0.44, -1.75, 0.24),
			knee, 0.38, soot, Enum.Material.Slate)
		creaturePart(leg, "Knobbed kneecap", Vector3.new(0.42, 0.43, 0.40),
			CFrame.new(knee), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		local shin = Instance.new("Model")
		shin.Name = "Flexing lower leg"
		shin.Parent = leg
		shin.WorldPivot = CFrame.new(knee)
		creatureLimb(shin, "Knifelike shin", knee,
			Vector3.new(side * 0.75, -4.28, 0.05), 0.24, soot, Enum.Material.Slate)
		creaturePart(shin, "Bare narrow foot", Vector3.new(0.55, 0.26, 1.11),
			CFrame.new(side * 0.76, -4.53, -0.46),
			charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
		table.insert(limbs, {model = leg, hinge = legHinge, side = -side,
			sway = 0.35, shin = shin, kneeOffset = knee - legHinge.Position})
	end
	local head = Instance.new("Model")
	head.Name = "Searching mask and neck"
	head.Parent = entity
	local hinge = CFrame.new(0, 2.33, -0.32)
	head.WorldPivot = hinge
	creatureLimb(head, "Craning thin neck", Vector3.new(0, 1.91, -0.41),
		Vector3.new(0, 2.94, -0.55), 0.34, soot, Enum.Material.Slate)
	creaturePart(head, "Back of bald skull", Vector3.new(2.12, 2.95, 1.16),
		CFrame.new(0, 3.55, -0.12), charcoal, Enum.Material.Slate, 0, Enum.PartType.Ball)
	local mask = creaturePart(head, "Oval ashen face", Vector3.new(2.12, 2.87, 1.1),
		CFrame.new(0, 3.54, -0.58) * CFrame.Angles(math.rad(-7), 0, 0),
		ivory, Enum.Material.Slate, 0, Enum.PartType.Ball)
	hollowEyes(head, 0.55, 3.73, -1.22, 0.39, 0.47, rim, void)
	for _, side in ipairs({-1, 1}) do
		creaturePart(head, "Hollow cheek", Vector3.new(0.4, 0.48, 0.18),
			CFrame.new(side * 0.64, 2.97, -1.04),
			Color3.fromRGB(130, 137, 127), Enum.Material.Slate, 0, Enum.PartType.Ball)
		creatureLimb(head, "Hairline fracture", Vector3.new(side * 0.84, 4.47, -0.66),
			Vector3.new(side * 0.92, 3.89, -1.08), 0.052, charcoal, Enum.Material.Slate)
	end
	creaturePart(head, "Mouth without a voice", Vector3.new(0.72, 0.15, 0.12),
		CFrame.new(0, 2.76, -1.15), void, Enum.Material.Slate, 0, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Name = "Face caught in the dark"
	light.Color = Color3.fromRGB(176, 189, 179)
	light.Brightness = 0.7
	light.Range = 10
	light.Parent = mask
	creatureHalo(entity, Color3.fromRGB(29, 32, 32), Color3.fromRGB(146, 151, 141))
	creatureMist(chest, "Breathless dust", Vector3.new(0, 0.5, 0.5),
		Color3.fromRGB(90, 100, 100), 4, 0.75)
	return entity, head, hinge, limbs
end

startBlind = function(room, epoch)
	if epoch ~= session or state.blind then return end
	-- Opening this very door makes a sound: the Guest is already inside and
	-- may investigate it, but never learns the location of a still player.
	local blind = {index = room.index, lastSerial = state.noiseSerial - 1}
	state.blind = blind
	local entity, mask, maskHinge, limbs = makeBlind()
	blind.entity = entity
	entity:SetAttribute("RoomIndex", room.index) -- clients mix music by actual room, not radius
	local startZ = room.index * L
	local position = Vector3.new(0, room.entryY + 4.7, startZ + 26)
	entity:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	for _, lamp in ipairs(room.lamps) do
		if lamp.normallyOn then setLamp(lamp, true, nil, 0.45) end
	end
	announceMonster(room, "BLIND", entity)
	-- All initialization above is synchronous with opening the door; ONLY
	-- the patrol yields, so no player needs to enter to make it appear.
	task.spawn(function()
		local patrolZ = startZ + 7 -- walk from the FAR end to the entry and back
		local elapsed = 0
		-- Remain in this room across exits and re-entries. Only retiring the
		-- inaccessible rear segment or a crucifix ends this encounter.
		while epoch == session and room.model.Parent and not blind.banished
			and state.opened <= room.index + CONFIG.KeepBehind do
			local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
			if epoch ~= session or blind.banished then break end
			elapsed = elapsed + dt
			local nearZ, farZ = roamBounds(room)
			local destination, nearest = blindTarget(blind, position, nearZ, farZ, patrolZ)
			if nearest == math.huge and math.abs(position.Z - patrolZ) < 1.1 then
				patrolZ = patrolZ == startZ + 7 and startZ + 37 or startZ + 7
				destination = Vector3.new(0, position.Y, patrolZ)
			end
			local old = position
			position = walkRoute(position, destination, nearest < math.huge and 19 or 9, dt, 4.7)
			local currentRoom = Layout.RoomIndexAt(position.Z)
			if entity:GetAttribute("RoomIndex") ~= currentRoom then
				entity:SetAttribute("RoomIndex", currentRoom) -- follows through open doors
			end
			local heading = Vector3.new(position.X - old.X, 0, position.Z - old.Z)
			if heading.Magnitude > 0.01 then
				local facing = CFrame.lookAt(position, position + heading)
				entity:PivotTo(facing)
				-- It tilts its head to listen while its shoulders and feet walk.
				mask:PivotTo(facing * maskHinge
					* CFrame.Angles(0, math.sin(elapsed * 1.7) * 0.17, math.sin(elapsed * 2.3) * 0.04))
				for _, limb in ipairs(limbs) do
					local step = math.sin(elapsed * 6.6 + (limb.side == -1 and 0 or math.pi))
					local rootCF = facing * limb.hinge * CFrame.Angles(step * limb.sway, 0, 0)
					limb.model:PivotTo(rootCF)
					if limb.shin then
					limb.shin:PivotTo(rootCF * CFrame.new(limb.kneeOffset)
							* CFrame.Angles(math.max(0, step) * 0.42, 0, 0))
					end
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
		for _, lamp in ipairs(room.lamps) do setLamp(lamp, lamp.normallyOn) end
		state.blind = nil
		pruneRooms()
	end)
end

-- The Pale Moth listens for a beam rather than footsteps. Turning the
-- flashlight OFF is the survival rule; crouching alone does nothing. It can
-- pass through an unlit player without damage and never causes a light blink.
local function makeMoth()
	-- Not one giant human-faced insect: eighteen individually visible moths,
	-- each with a tiny body, head and two fluttering, translucent wings.
	local entity = Instance.new("Model")
	entity.Name = "ThePaleMoth"
	entity.Parent = state.world
	local pale = Color3.fromRGB(181, 199, 178)
	local dark = Color3.fromRGB(26, 38, 36)
	local core = creaturePart(entity, "Swarm heart", Vector3.new(0.12, 0.12, 0.12),
		CFrame.new(), pale, Enum.Material.Glass, 1, Enum.PartType.Ball)
	entity.PrimaryPart = core
	local insects = {}
	for i = 1, 18 do
		local offset = Vector3.new(math.sin(i * 2.4) * (0.45 + i % 3 * 0.29),
			math.cos(i * 1.3) * 0.82, math.sin(i * 1.81) * 0.84)
		local moth = Instance.new("Model")
		moth.Name = string.format("Individual tiny moth %02d", i)
		moth.Parent = entity
		moth.WorldPivot = CFrame.new(offset)
		creaturePart(moth, "Tiny moth thorax", Vector3.new(0.17, 0.16, 0.32),
			CFrame.new(offset), dark, Enum.Material.Slate, 0, Enum.PartType.Ball)
		creaturePart(moth, "Pale moth head", Vector3.new(0.19, 0.17, 0.18),
			CFrame.new(offset + Vector3.new(0, 0, -0.19)), pale,
			Enum.Material.Slate, 0, Enum.PartType.Ball)
		for _, side in ipairs({-1, 1}) do
			creaturePart(moth, "Pinpoint black eye", Vector3.new(0.058, 0.058, 0.045),
				CFrame.new(offset + Vector3.new(side * 0.07, 0.04, -0.28)), dark,
				Enum.Material.Slate, 0, Enum.PartType.Ball)
		end
		local wings = {}
		for _, side in ipairs({-1, 1}) do
			local wing = Instance.new("Model")
			wing.Name = side == -1 and "Left moth wing" or "Right moth wing"
			wing.Parent = moth
			wing.WorldPivot = CFrame.new(offset + Vector3.new(side * 0.10, 0.06, 0.03))
			local membrane = creaturePart(wing, "Fine veined moth wing",
				Vector3.new(0.44, 0.035, 0.29),
				CFrame.new(offset + Vector3.new(side * 0.32, 0.07, 0.02))
					* CFrame.Angles(0, side * -0.22, side * 0.25),
				pale, Enum.Material.Glass, 0.36, Enum.PartType.Ball)
			membrane.CastShadow = false
			table.insert(wings, {model = wing, side = side})
		end
		table.insert(insects, {model = moth, offset = offset, wings = wings, phase = i * 1.93})
	end
	local light = Instance.new("PointLight")
	light.Name = "Weak light on the swarm"
	light.Color = Color3.fromRGB(123, 184, 158)
	light.Brightness = 0.45
	light.Range = 9
	light.Parent = core
	creatureHalo(entity, Color3.fromRGB(37, 53, 48), pale)
	creatureMist(core, "Fine airborne scales", Vector3.new(), pale, 5, 0.3)
	return entity, insects
end

local function flutterMoths(insects, facing, elapsed)
	for _, insect in ipairs(insects) do
		local flutter = insect.offset + Vector3.new(
			math.sin(elapsed * 3.1 + insect.phase) * 0.16,
			math.sin(elapsed * 4.4 + insect.phase) * 0.14,
			math.cos(elapsed * 3.5 + insect.phase) * 0.12)
		insect.model:PivotTo(facing * CFrame.new(flutter))
		for _, wing in ipairs(insect.wings) do
			wing.model:PivotTo(facing * CFrame.new(flutter)
				* CFrame.new(wing.side * 0.1, 0.06, 0.03)
				* CFrame.Angles(0, 0, wing.side * (0.28 + math.sin(elapsed * 19 + insect.phase) * 0.52)))
		end
	end
end

startMoth = function(room, epoch)
	if epoch ~= session or state.moth then return end
	local hunt = {index = room.index, bites = {}}
	state.moth = hunt
	local entity, insects = makeMoth()
	hunt.entity = entity
	local startZ = room.index * L
	local position = Vector3.new(0, room.entryY + 6.1, startZ + 24)
	local facing = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
	entity:PivotTo(facing)
	-- The whole swarm is behind the opening door, already visible. The
	-- four-second green-tinted grace period begins NOW, without text or bites.
	local cold = Color3.fromRGB(120, 197, 167)
	for _, lamp in ipairs(room.lamps) do
		if lamp.normallyOn or lamp == room.lamps[#room.lamps] then
			setLamp(lamp, true, cold, 0.28)
		end
	end
	announceMonster(room, "MOTH", entity)
	task.spawn(function()
		for i = 1, 8 do
			if epoch ~= session or hunt.banished then break end
			for _, lamp in ipairs(room.lamps) do
				if lamp.normallyOn or lamp == room.lamps[#room.lamps] then
					setLamp(lamp, true, cold, 0.25 + i * 0.026)
				end
			end
			flutterMoths(insects, facing, i * CONFIG.MothGraceSeconds / 8)
			task.wait(CONFIG.MothGraceSeconds / 8)
		end
		local patrolZ, elapsed = startZ + 9, 0
		while epoch == session and not hunt.banished and elapsed < CONFIG.MothLifetime do
			local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
			if epoch ~= session or hunt.banished then break end
			elapsed = elapsed + dt
			local nearZ, farZ = roamBounds(room)
			local destination, nearest = roamingTarget(position, nearZ, farZ, patrolZ, "MOTH")
			if nearest == math.huge and math.abs(position.Z - patrolZ) < 1.1 then
				patrolZ = patrolZ == startZ + 9 and startZ + 36 or startZ + 9
				destination = Vector3.new(0, position.Y, patrolZ)
			end
			local old = position
			local onRoute = walkRoute(position, destination,
				nearest < math.huge and CONFIG.MothSpeed or 7, dt, 6.1)
			position = Vector3.new(onRoute.X, onRoute.Y + math.sin(elapsed * 4) * 0.24, onRoute.Z)
			local heading = Vector3.new(position.X - old.X, 0, position.Z - old.Z)
			if heading.Magnitude > 0.01 then facing = CFrame.lookAt(position, position + heading) end
			entity:PivotTo(facing)
			flutterMoths(insects, facing, elapsed + CONFIG.MothGraceSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				local root = playerRoot(player)
				local info = state.players[player]
				if root and info and info.torchOn and not state.hidden[player]
					and root.Position.Z >= nearZ and root.Position.Z <= farZ then
					local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(root.Position.Z))
					local floorY = Layout.WalkwayY(index, root.Position.Z - index * L)
					local delta = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
					if math.abs(root.Position.Y - floorY - 3) < 5 and delta.Magnitude < 5.5
						and state.clock >= (hunt.bites[player] or 0) then
						hunt.bites[player] = state.clock + 1.1
						damagePlayer(player, 7, "MOTH", entity) -- gradual; light OFF = no bites
					end
				end
			end
		end
		retireMonster(entity)
		if epoch ~= session then return end
		for _, lamp in ipairs(room.lamps) do setLamp(lamp, lamp.normallyOn) end
		state.moth = nil
		pruneRooms()
	end)
end

-- The Echo crosses the SAME open route five alternating times: forward,
-- back, forward, back, then a final escape. The gaps invite leaving a closet;
-- remaining inside throughout is punished by the server's closet limit.
startEcho = function(room, epoch)
	if epoch ~= session or state.echo then return end
	local origin = math.max(0, room.index - 2)
	local nearZ = origin * L + 5
	local farZ = (room.index + 1) * L - 5
	local echo = {origin = origin, limit = room.index}
	state.echo = echo
	local rng = Random.new(state.seed + room.index * 151 + 17)
	for i = 1, 14 do
		if epoch ~= session or echo.banished then return end
		for index = origin, room.index do
			local lit = state.rooms[index]
			if lit then
				for _, lamp in ipairs(lit.lamps) do
					setLamp(lamp, rng:NextNumber() > 0.43)
				end
			end
		end
		task.wait(0.18)
	end
	if epoch ~= session then return end
	local entity, arms, glow, jaw, jawHinge, legs, veils, marks, mist, shrouds = makeEcho()
	echo.entity = entity
	local z, elapsed = nearZ, 0
	entity:PivotTo(CFrame.lookAt(pathPoint(z), pathPoint(z) + Vector3.new(0, 0, 1)))
	announceMonster(room, "ECHO", entity) -- not during the light warning
	local path = {farZ, nearZ, farZ, nearZ, farZ}
	for pass, target in ipairs(path) do
		if echo.banished or epoch ~= session then break end
		local returning = pass % 2 == 0
		for _, mark in ipairs(marks) do mark.Transparency = returning and 0.07 or 0.94 end
		for _, shroud in ipairs(shrouds) do shroud.Transparency = returning and 0.22 or 0.57 end
		for _, emitter in ipairs(mist) do emitter.Rate = returning and 14 or 5 end
		glow.Color = returning and Color3.fromRGB(207, 229, 235)
			or Color3.fromRGB(135, 171, 188)
		entity:SetAttribute("Returning", returning)
		entity:SetAttribute("EchoPass", pass)
		local direction = target > z and 1 or -1
		local frames = 0
		while not echo.banished and epoch == session and math.abs(target - z) > 0.1 and frames < 85 do
			local dt = math.min(RunService.Heartbeat:Wait(), 0.15)
			if epoch ~= session or echo.banished then break end
			frames = frames + 1
			elapsed = elapsed + dt
			local previous = z
			z = z + direction * math.min(math.abs(target - z), 76 * dt)
			local point = pathPoint(z)
			local facing = CFrame.lookAt(point, point + Vector3.new(0, 0, direction))
			entity:PivotTo(facing)
			for _, arm in ipairs(arms) do
				arm.model:PivotTo(facing * arm.hinge
					* CFrame.Angles(math.sin(elapsed * 7 + arm.side) * 0.28, 0, 0))
			end
			for _, veil in ipairs(veils) do
				veil.model:PivotTo(facing * veil.hinge * CFrame.Angles(
					math.sin(elapsed * 4.7 + veil.side) * 0.16,
					veil.side * (returning and 0.48 or 0.10),
					math.sin(elapsed * 5.4 + veil.side) * 0.08))
			end
			for _, leg in ipairs(legs) do
				local stride = math.sin(elapsed * 8 + (leg.side == -1 and 0 or math.pi))
				local hip = facing * leg.hinge * CFrame.Angles(stride * 0.33, 0, 0)
				leg.model:PivotTo(hip)
				leg.shin:PivotTo(hip * CFrame.new(leg.kneeOffset)
					* CFrame.Angles(math.max(0, stride) * 0.38, 0, 0))
			end
			jaw:PivotTo(facing * jawHinge * CFrame.Angles(
					(returning and -0.51 or -0.13) + math.sin(elapsed * 11) * 0.10, 0, 0))
			glow.Brightness = (returning and 1.16 or 0.70) + math.sin(elapsed * 12) * 0.16
			for _, player in ipairs(Players:GetPlayers()) do
				local root, humanoid = playerRoot(player)
				if root and not state.hidden[player]
					and root.Position.Z >= math.min(previous, z) - 4.5
					and root.Position.Z <= math.max(previous, z) + 4.5 then
					local crossing = pathPoint(math.clamp(root.Position.Z, nearZ, farZ))
					if math.abs(root.Position.X) < W / 2 - 0.7
						and math.abs(root.Position.Y - (crossing.Y - 2)) < 5.5 then
						killPlayer(player, humanoid, "ECHO", entity)
					end
				end
			end
		end
		-- Two and a half seconds to come out for air, then hide again.
		if pass < #path and not echo.banished then
			for i = 1, 13 do
				if epoch ~= session or echo.banished then break end
				for index = origin, room.index do
					local lit = state.rooms[index]
					if lit then
						for _, lamp in ipairs(lit.lamps) do
							setLamp(lamp, i % 4 ~= 1 and lamp.normallyOn)
						end
					end
				end
				task.wait(0.2)
			end
		end
	end
	retireMonster(entity)
	if epoch ~= session then return end
	for index = origin, room.index do
		local lit = state.rooms[index]
		if lit then for _, lamp in ipairs(lit.lamps) do setLamp(lamp, lamp.normallyOn) end end
	end
	state.echo = nil
	pruneRooms()
end

local function resetWorld()
	for player in pairs(state.keys) do putBackKey(player) end
	session = session + 1
	for player in pairs(state.entering) do cancelClosetEntry(player) end
	for player in pairs(state.hidden) do leaveCloset(player, false) end
	if state.world then state.world:Destroy() end
	local old = Workspace:FindFirstChild("NocturneWorld")
	if old then old:Destroy() end
	state.world = Instance.new("Folder")
	state.world.Name = "NocturneWorld"
	state.world.Parent = Workspace
	state.rooms = {}
	state.hidden = {}
	state.entering = {}
	state.keys = {}
	state.clock = 0
	state.noises = {}
	state.noiseSerial = 0
	state.opened = 0
	state.rush = nil
	state.blind = nil
	state.moth = nil
	state.echo = nil
	state.backSeal = nil
	for player, info in pairs(state.players) do
		info.items = emptyItems()
		info.coins, info.notes, info.gold = 0, 0, 0
		info.charge, info.health, info.selected = 0, 100, 1
		info.torchOn, info.pillUntil, info.closetCooldown = false, 0, 0
		info.voidWalk, info.voidStart = false, nil
		info.nextSpiderRoom = 0
		syncInventory(player)
	end
	local previousSeed = state.seed
	state.seed = CONFIG.Seed or Random.new():NextInteger(1, 1000000000)
	if not CONFIG.Seed and state.seed == previousSeed then
		state.seed = state.seed % 1000000000 + 1
	end
	state.plan = planRooms(state.seed)
	state.world:SetAttribute("Seed", state.seed)
	state.world:SetAttribute("CameraBuild", "NativeFirstPerson-v10")
	state.world:SetAttribute("GenerationBuild", "WhiteVoidAndBlindAudio-v15")
	local firstDoors = {}
	for index = 0, 7 do
		local room = state.plan[index]
		table.insert(firstDoors, string.format("%03d:%s/%s", index + 1, room.kind, room.shape))
	end
	print("[NOCTURNE v15] run seed", state.seed, table.concat(firstDoors, "  "))
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
		player:SetAttribute("EnteringWardrobe", false)
		player:SetAttribute("Finished", false)
		player:SetAttribute("VoidWalk", false)
		player:SetAttribute("HeldKey", nil)
		player:SetAttribute("KeyTurning", false)
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
	state.players[player] = {
		stamina = 100, sprinting = false, crouching = false, torchOn = false,
		items = emptyItems(), coins = 0, notes = 0, gold = 0,
		charge = 0, health = 100, selected = 1, pillUntil = 0, closetCooldown = 0,
		voidWalk = false, voidStart = nil, nextSpiderRoom = 0,
	}
	player:SetAttribute("Stamina", 100)
	syncInventory(player)
	player:SetAttribute("Hidden", false)
	player:SetAttribute("EnteringWardrobe", false)
	player:SetAttribute("Crouching", false)
	player:SetAttribute("Finished", false)
	player:SetAttribute("VoidWalk", false)
	player:SetAttribute("HeldKey", nil)
	player:SetAttribute("KeyTurning", false)
	player.CharacterAdded:Connect(function(character)
		cancelClosetEntry(player) -- a new life cannot inherit an old entrance tween
		local humanoid = character:WaitForChild("Humanoid", 12)
		local root = character:WaitForChild("HumanoidRootPart", 12)
		if not humanoid or not root then return end
		local info = state.players[player]
		if not info then return end
		info.stamina = 100
		info.sprinting = false
		info.crouching = false
		info.torchOn = false
		info.health = 100 -- a new life, but the run's wallet and items survive
		info.pillUntil = 0
		info.voidWalk, info.voidStart = false, nil
		player:SetAttribute("VoidWalk", false)
		player:SetAttribute("Stamina", 100)
		syncInventory(player)
		player:SetAttribute("Hidden", false)
		player:SetAttribute("EnteringWardrobe", false)
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
			putBackKey(player)
			cancelClosetEntry(player)
			leaveCloset(player, false)
			info.health = 0
			info.torchOn = false
			info.voidWalk, info.voidStart = false, nil
			player:SetAttribute("VoidWalk", false)
			syncInventory(player)
			remote:FireClient(player, "Death")
		end)
	end)
	-- CharacterAdded can precede the native R6/R15 hands. After Roblox
	-- finishes loading the appearance, reattach any carried selected model.
	player.CharacterAppearanceLoaded:Connect(function(character)
		if player.Character == character and state.players[player] then syncInventory(player) end
	end)
	player.RespawnLocation = state.spawn
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(registerPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(registerPlayer, player) end
Players.PlayerRemoving:Connect(function(player)
	putBackKey(player)
	cancelClosetEntry(player)
	leaveCloset(player, false)
	state.players[player] = nil
end)

remote.OnServerEvent:Connect(function(player, action, argument)
	local info = state.players[player]
	if not info then return end
	if state.entering[player] and action ~= "Ready" then return end
	if action == "Ready" then
		remote:FireClient(player, "State", state.opened, state.seed, L)
		syncInventory(player)
		return
	end
	if action == "Select" then
		if info.voidWalk then return end
		if typeof(argument) == "number" and argument == math.floor(argument)
			and argument >= 1 and argument <= #SLOTS
			and info.items[SLOTS[argument]] > 0 then
			info.selected = argument
			if argument ~= 1 then info.torchOn = false end
			syncInventory(player)
		end
		return
	elseif action == "Use" then
		if info.voidWalk then return end
		-- The item ID travels with the activation. Equipping and activating are
		-- one server action: a freshly clicked slot works even if the preceding
		-- Select/Inventory round trip has not arrived yet.
		if typeof(argument) ~= "string" then return end
		local slot
		for index, id in ipairs(SLOTS) do
			if argument == id then slot = index; break end
		end
		if not slot then return end
		local root, humanoid = playerRoot(player)
		if not humanoid or state.hidden[player] or player:GetAttribute("Finished") then return end
		local id = SLOTS[slot]
		if info.items[id] < 1 then
			syncInventory(player) -- repair a stale client hotbar without creating an item
			remote:FireClient(player, "ItemDenied", id)
			return
		end
		local selectionChanged = info.selected ~= slot
		info.selected = slot
		if slot ~= 1 then info.torchOn = false end
		if id == "FLASHLIGHT" then
			if info.charge <= 0 then
				if selectionChanged then syncInventory(player) end
				remote:FireClient(player, "ItemDenied", id)
				return
			end
			info.torchOn = not info.torchOn
			syncInventory(player)
			remote:FireClient(player, "ItemUsed", id)
			return
		elseif id == "CRUCIFIX" then
			if raiseCrucifix(player, root) then return end
			if selectionChanged then syncInventory(player) end
			remote:FireClient(player, "ItemDenied", id)
			return
		elseif id == "PILL" then
			info.pillUntil = state.clock + 8
		elseif HEAL[id] then
			local health = math.min(info.health, humanoid.Health)
			if health >= 100 then
				if selectionChanged then syncInventory(player) end
				remote:FireClient(player, "ItemDenied", id)
				return -- healthy players keep the bandage/kit for a later injury
			end
			info.health = math.min(100, health + HEAL[id])
			humanoid.Health = info.health
		end
		info.items[id] = info.items[id] - 1
		syncInventory(player)
		remote:FireClient(player, "ItemUsed", id)
		return
	end
	if action == "Exit" then
		leaveCloset(player, true)
	elseif action == "Sprint" then
		if typeof(argument) == "boolean" then
			info.sprinting = argument and not info.crouching and not info.voidWalk
		end
	elseif action == "Crouch" then
		if typeof(argument) == "boolean" and not state.hidden[player]
			and not player:GetAttribute("Finished") then
			info.crouching = argument and not info.voidWalk
			if argument then info.sprinting = false end
			player:SetAttribute("Crouching", info.crouching)
		end
	elseif action == "Torch" then
		if typeof(argument) == "boolean" then
			info.torchOn = argument and info.selected == 1 and info.items.FLASHLIGHT > 0
				and info.charge > 0 and not state.hidden[player]
				and playerRoot(player) ~= nil and not info.voidWalk
				and not player:GetAttribute("Finished") or false
			syncInventory(player)
		end
	elseif action == "Retry" then
		local oldHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local finished = player:GetAttribute("Finished") == true
		if (not finished and (not oldHum or oldHum.Health > 0)) or state.hidden[player] then return end
		if info.lastRetry and os.clock() - info.lastRetry < 1.5 then return end
		info.lastRetry = os.clock()
		local groupFinished = true
		for _, other in ipairs(Players:GetPlayers()) do
			local human = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if not other:GetAttribute("Finished") and (not human or human.Health > 0) then
				groupFinished = false
				break
			end
		end
		-- Regenerate the whole shared hotel when nobody is still exploring.
		-- A solo retry is always a new layout; one dead teammate cannot erase
		-- a living teammate's building from under their feet.
		if groupFinished then
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
	local lastZ = state.opened == CONFIG.Doors and CONFIG.Doors * L + CONFIG.VoidLength
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
	state.clock = state.clock + step
	local leader, leaderZ = nil, -math.huge
	local first = math.max(0, state.opened - CONFIG.KeepBehind)
	local farthest = state.opened == CONFIG.Doors and CONFIG.Doors * L + CONFIG.VoidLength
		or math.min(CONFIG.Doors, state.opened + CONFIG.Ahead) * L
	for player in pairs(state.players) do
		local root = playerRoot(player)
		if root and not player:GetAttribute("Finished") then
			local index = Layout.RoomIndexAt(root.Position.Z)
			local floorY = index >= CONFIG.Doors and Layout.EntranceY(CONFIG.Doors)
				or Layout.WalkwayY(index, math.clamp(root.Position.Z - index * L, 0, L))
			if root.Position.Z >= first * L - 1 and root.Position.Z <= farthest + 2
				and math.abs(root.Position.X) <= W / 2 + 1
				and math.abs(root.Position.Y - floorY - 3) < 7
				and root.Position.Z > leaderZ then
				leader, leaderZ = root, root.Position.Z
			end
		end
	end
	for player, info in pairs(state.players) do
		local root, humanoid = playerRoot(player)
		if humanoid then
			-- Roblox's default character Health script may try to regenerate;
			-- only bandages, kits or a fresh life may raise this server-owned cap.
			if humanoid.Health > info.health then humanoid.Health = info.health end
			if humanoid.Health < info.health then
				info.health = humanoid.Health
				player:SetAttribute("Health", math.ceil(info.health))
			end
		end
		local hiding = state.hidden[player]
		if hiding and humanoid then
			hiding.seconds = hiding.seconds + step
			local pressure = math.clamp((hiding.seconds - CONFIG.ClosetWarning)
				/ (CONFIG.ClosetLimit - CONFIG.ClosetWarning), 0, 1)
			local percent = math.floor(pressure * 100 + 0.5)
			if player:GetAttribute("ClosetPressure") ~= percent then
				player:SetAttribute("ClosetPressure", percent)
			end
			if hiding.seconds >= CONFIG.ClosetLimit then
				info.closetCooldown = state.clock + 6
				leaveCloset(player, true)
				damagePlayer(player, 19)
			end
		elseif humanoid and not player:GetAttribute("Finished") and not state.entering[player] then
			keepInsideHotel(player, root)
			-- Touched is normally immediate, but this heartbeat also handles a
			-- skipped sensor or a streaming/network timing gap on door 100.
			if info.voidWalk and root.Position.Z < CONFIG.Doors * L + 0.8 then
				info.voidWalk, info.voidStart = false, nil
				player:SetAttribute("VoidWalk", false)
			elseif not info.voidWalk then
				enterVoidWalk(player, root, humanoid)
			end
			local gap = leader and (leaderZ - root.Position.Z) / L or 0
			local catchup = gap >= 5 and 7 or gap >= 2.5 and 3 or 0
			if gap >= 7 and leader ~= root
				and state.clock >= (info.catchupCooldown or 0) then
				local index = math.min(CONFIG.Doors - 1, Layout.RoomIndexAt(leaderZ))
				local z = math.clamp(leaderZ - 7, index * L + 9, index * L + L - 11)
				local localZ = z - index * L
				root.CFrame = CFrame.new(Layout.PathX(index, localZ, state.seed),
					Layout.WalkwayY(index, localZ) + 3, z) * CFrame.Angles(0, math.pi, 0)
				root.AssemblyLinearVelocity = Vector3.new()
				root.AssemblyAngularVelocity = Vector3.new()
				info.catchupCooldown = state.clock + 10
				info.lastFootstep = state.clock
				damagePlayer(player, 36)
				catchup = 0
			end
			if humanoid.Health > 0 then
				-- Server velocity, not spoofable client MoveDirection, drives noise.
				local velocity = root.AssemblyLinearVelocity
				local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				local moving = horizontal > 1.8
				local running = info.sprinting and not info.crouching and not info.voidWalk
					and info.stamina > 0.5 and moving
				if moving and not info.crouching and not info.voidWalk
					and state.clock - (info.lastFootstep or -1) >= 0.62 then
					local reach = horizontal > 15 and 90 or horizontal > 7 and 65 or 44
					recordNoise(root.Position, reach)
					info.lastFootstep = state.clock
				end
				if running then
					info.stamina = math.max(0, info.stamina - CONFIG.SprintDrain * step)
				else
					info.stamina = math.min(100, info.stamina + CONFIG.StaminaRegen * step)
				end
				local fast = state.clock < info.pillUntil and 9 or 0
				local speed = info.voidWalk and CONFIG.VoidWalkSpeed
					or (info.crouching and CONFIG.CrouchSpeed
						or (running and CONFIG.SprintSpeed or CONFIG.WalkSpeed) + fast + catchup)
				if humanoid.WalkSpeed ~= speed then humanoid.WalkSpeed = speed end
				local rounded = math.floor(info.stamina + 0.5)
				if player:GetAttribute("Stamina") ~= rounded then player:SetAttribute("Stamina", rounded) end
				if info.torchOn and info.items.FLASHLIGHT > 0 then
					info.charge = math.max(0, info.charge - CONFIG.TorchDrain * step)
					if info.charge <= 0 then
						info.items.FLASHLIGHT = 0
						info.torchOn = false
						syncInventory(player)
					elseif player:GetAttribute("TorchCharge") ~= math.ceil(info.charge) then
						player:SetAttribute("TorchCharge", math.ceil(info.charge))
					end
				end
			end
		end
	end
end)

print("[NOCTURNE v15] solid white finale, individual Blind Guest music and native first person.")
