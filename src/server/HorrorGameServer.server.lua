--[=[
    БЕСКОНЕЧНЫЕ ЛЕСТНИЦЫ / ENDLESS STAIRS — HORROR
    ServerScriptService > Script (этот файл вшит в 13123.rbxl билдером)

    КАК БЫЛА ПОНЯТА КАРТА ИЗ 13123.rbxl
    -----------------------------------
    В Workspace есть ОДНА маленькая комната-модель "Room" (6 деталей):
      Pivot оригинала : (-3.013, 10.704, -63.537)
      Потолок         : центр пивота +8.330 Y, размер 31.923 x 0.324 x 35.776
      Пол             : центр пивота -8.330 Y, тот же размер,
                        верх пола = пивот -8.168 Y
      Западная стена  : пивот -15.800 X (глухая)
      Восточная стена : пивот +15.800 X, крывает только Z от -4.06 до +17.56,
                        поэтому в ней ОСТАВЛЕН ПРОЁМ по Z от -17.89 до -4.06
                        (центр проёма: локально +15.80 X / -10.97 Z)
      Север/юг стены  : пивот +/-17.726 Z

    Автор карты подсказал: ПЕРВАЯ копия комнаты стоит на
      (3.868, 30.621, -30.577)
    Отсюда шаг одного этажа (он повторяется бесконечно):
      STEP = (3.868, 30.621, -30.577) - (-3.013, 10.704, -63.537)
           = ( 6.881, 19.917,  32.960)
    Этаж N: Pivot = PivotОригинала + STEP * N.
    Между этажами сервер достраивает лестничный пролёт в стиле моделей
    "Escadas" с карты: выход через восточный проём -> площадка ->
    20 ступеней наверх вдоль +Z -> верхняя площадка -> вход в следующий
    восточный проём. Всё остальное барахло со старой карты НЕ удаляется,
    а уезжает в ServerStorage > OriginalMapBackup.

    4 ТИПА МОНСТРОВ / СОБЫТИЙ
    -------------------------
    1) СТАЛКЕР ЗА СПИНОЙ. Идёт сзади, шёпот + в глазах троится/глючит/
       зависает. Надо ОБЕРНУТЬСЯ и смотреть на него (~0.45 c), иначе
       через StalkerKillTime секунд он съест игрока.
    2) ЗВУКОВОЙ. При входе на этаж: замри и слушай. Если звук ЕСТЬ —
       беги на ПРЕДЫДУЩИЙ этаж, подожди, потом заходи заново.
       Не успел вернуться / полез вглубь — съест.
    3) МОНСТР ЭТАЖЕЙ (ВЫБОР). Перед некоторыми этажами (6, 11, 16, ...)
       лестница упирается в 3 двери с номерами комнат. Правильная —
       только следующая по счёту. Номера ПРОШЛЫХ этажей на табличках
       размываются в "▓▓▓▓", подсмотреть нельзя — надо было СЧИТАТЬ.
       Ошибся дверью — смерть.
    4) ДЕФЕКТ КОМНАТЫ. В комнате что-то не так (лишнее/красное/не то/
       чего-то не хватает). Надо подойти вплотную, СМОТРЕТЬ на дефект
       и СТОЯТЬ НЕ ДВИГАЯСЬ 5 секунд. Двинулся — таймер в ноль.
       Успех — телепорт на следующий этаж, выход до этого закрыт.

    Игра рассчитана в первую очередь на соло / кооп с общим прогрессом:
    этаж и активное событие общие на сервер, монстр выбирает игрока,
    который зашёл на этаж.
]=]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local CONFIG = {
	FloorsAhead = 2,          -- сколько этажей держать сгенерированными вперёд
	StalkerSpawnDelay = 7,    -- cекунд намёков до появления сталкера
	StalkerKillTime = 30,     -- секунд от появления до смерти, если не обернуться
	StalkerGazeNeed = 0.45,   -- сколько секунд суммарно смотреть на него
	StalkerGazeDot = 0.60,    -- косинус: насколько прямо надо смотреть
	SoundListenTime = 4.5,    -- если звука нет — столько надо простоять/прослушать вход
	SoundCueDelay = 1.6,      -- через сколько после входа раздастся звук (если он есть)
	SoundEscapeTime = 8,      -- секунд на побег вниз после звука
	SoundCueChance = 0.75,    -- шанс, что звук вообще будет (на первом звуковом этаже — всегда)
	DefectStareTime = 5,      -- СТОЛЬКО стоять и смотреть на дефект
	DefectStareDistance = 9,  -- насколько близко надо подойти (стады)
	DefectMoveReset = 1.15,   -- сдвинулся больше чем на это (стады) — таймер в ноль
	WalkSpeed = 16,
}

-- Звуки: только встроенная классика Roblox (rbxasset://), внешних ассетов нет.
-- Все звуковые подсказки дублируются субтитрами на экране, поэтому игра
-- проходима и без звука. Сюда можно вписать свои rbxassetid в Studio.
local SOUND_DEFS = {
	Drone = {Id = "rbxasset://sounds/bass.wav", Volume = 0.16, Speed = 0.45, Looped = true},
	Whisper = {Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Speed = 0.32, Looped = false},
	Cue = {Id = "rbxasset://sounds/swoosh.wav", Volume = 1.0, Speed = 0.42, Looped = false},
	Screech = {Id = "rbxasset://sounds/uuhhh.mp3", Volume = 1.0, Speed = 0.55, Looped = false},
	Good = {Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 1.25, Looped = false},
	Click = {Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 0.8, Looped = false},
}

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("HorrorRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "HorrorRemotes"
	remotes.Parent = ReplicatedStorage
end
local fxEvent = remotes:FindFirstChild("Fx") or Instance.new("RemoteEvent")
fxEvent.Name = "Fx"
fxEvent.Parent = remotes
local clientEvent = remotes:FindFirstChild("Client") or Instance.new("RemoteEvent")
clientEvent.Name = "Client"
clientEvent.Parent = remotes

local function fx(player, ...)
	if player then
		fxEvent:FireClient(player, ...)
	else
		fxEvent:FireAllClients(...)
	end
end
local function say(player, title, text, seconds)
	fx(player, "Message", title or "", text or "", seconds or 4)
end
local function sayAll(title, text, seconds)
	say(nil, title, text, seconds)
end
local function playLocal(player, soundName)
	fx(player, "Sound", soundName)
end
local function playLocalAll(soundName)
	playLocal(nil, soundName)
end

----------------------------------------------------------------------
-- Звуковые объекты
----------------------------------------------------------------------
for name, def in pairs(SOUND_DEFS) do
	local s = SoundService:FindFirstChild("Horror_" .. name)
	if not s then
		s = Instance.new("Sound")
		s.Name = "Horror_" .. name
		s.Parent = SoundService
	end
	s.SoundId = def.Id
	s.Volume = def.Volume
	s.PlaybackSpeed = def.Speed
	s.Looped = def.Looped
end
local drone = SoundService:FindFirstChild("Horror_Drone")
if drone and not drone.IsPlaying then
	drone:Play()
end

----------------------------------------------------------------------
-- Атмосфера
----------------------------------------------------------------------
Lighting.ClockTime = 0.25
Lighting.Brightness = 1.1
Lighting.Ambient = Color3.fromRGB(28, 30, 40)
Lighting.OutdoorAmbient = Color3.fromRGB(12, 13, 20)
Lighting.FogColor = Color3.fromRGB(8, 9, 13)
Lighting.FogStart = 18
Lighting.FogEnd = 135
Lighting.EnvironmentDiffuseScale = 0.25
Lighting.EnvironmentSpecularScale = 0.2
do
	local cc = Lighting:FindFirstChild("HorrorColor") or Instance.new("ColorCorrectionEffect")
	cc.Name = "HorrorColor"
	cc.Brightness = -0.05
	cc.Contrast = 0.16
	cc.Saturation = -0.38
	cc.TintColor = Color3.fromRGB(196, 208, 230)
	cc.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = 0.55
		bloom.Size = 28
		bloom.Threshold = 1.4
	end
end

----------------------------------------------------------------------
-- Утилиты построения
----------------------------------------------------------------------
local WALL_COLOR = Color3.fromRGB(99, 95, 98)     -- цвет деталей Room/Escadas с карты
local DARK_COLOR = Color3.fromRGB(163, 162, 165) -- цвет сырых деталей с карты

local function makePart(parent, name, size, cf, color, material, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or WALL_COLOR
	p.Material = material or Enum.Material.Concrete
	p.Anchored = true
	p.CanCollide = not (opts and opts.NoCollide)
	p.CanTouch = not (opts and opts.NoTouch)
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts and opts.Transparency then p.Transparency = opts.Transparency end
	if opts and opts.Shape then p.Shape = opts.Shape end
	p.Parent = parent
	return p
end

local function makeLabel(parentPart, face, text, textColor, size)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 48
	gui.Parent = parentPart
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor or Color3.fromRGB(230, 228, 220)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	if size then label.TextSize = size end
	label.Parent = gui
	return label
end

local function getHRP(player)
	local char = player and player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil end
	return hrp, hum
end

----------------------------------------------------------------------
-- Шаблон комнаты: ищем ИМЕННО маленькую Room (6 деталей), а не большую
-- оболочку Room №2. Заодно вычисляем геометрию из самих деталей.
----------------------------------------------------------------------
local templateRoom = nil
local templateRoomSize = math.huge
for _, child in ipairs(Workspace:GetChildren()) do
	if child:IsA("Model") and child.Name == "Room" then
		local _, size = child:GetBoundingBox()
		local volume = size.X * size.Y * size.Z
		if volume < templateRoomSize then
			templateRoomSize = volume
			templateRoom = child
		end
	end
end
if not templateRoom then
	error("[HorrorStairs] В Workspace не найдена модель Room — проверь, что открыт 13123.rbxl")
end

local TEMPLATE_PIVOT = templateRoom:GetPivot().Position
-- Координата из подсказки автора карты:
local FIRST_COPY_PIVOT = Vector3.new(3.868, 30.621, -30.577)
local STEP = FIRST_COPY_PIVOT - TEMPLATE_PIVOT -- (6.881, 19.917, 32.960)

-- Геометрия внутри шаблона (локально от пивота):
local floorTopOffset = -8.168 -- верх пола
local gapX, gapZ = 15.80, -10.97 -- центр восточного проёма
do
	local pivot = TEMPLATE_PIVOT
	local lowestTop, eastWall = math.huge, nil
	local floorHalfZ = 17.888
	for _, d in ipairs(templateRoom:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = d.Position - pivot
			if d.Size.Y < 1 and rel.Y < 0 then -- горизонтальная плита снизу = пол
				local top = rel.Y + d.Size.Y / 2
				if top < lowestTop then lowestTop = top end
				floorHalfZ = d.Size.Z / 2
			end
			if d.Size.X < 1 and rel.X > 10 then eastWall = d end -- восточная стена
		end
	end
	if lowestTop < math.huge then floorTopOffset = lowestTop end
	if eastWall then
		local rel = eastWall.Position - pivot
		gapX = rel.X
		-- стена крывает Z [rel.Z - Size.Z/2, rel.Z + Size.Z/2], проём — остаток до края пола
		local wallMinZ = rel.Z - eastWall.Size.Z / 2
		gapZ = (-floorHalfZ + wallMinZ) / 2
	end
end

local function pivotFor(floorIndex) -- floorIndex: 0 = оригинал
	return TEMPLATE_PIVOT + STEP * floorIndex
end
local function floorTopY(floorIndex)
	return pivotFor(floorIndex).Y + floorTopOffset
end
local function spawnPos(floorIndex)
	local p = pivotFor(floorIndex)
	return Vector3.new(p.X - 9, floorTopY(floorIndex) + 3.2, p.Z)
end
local function spawnCF(floorIndex)
	local pos = spawnPos(floorIndex)
	return CFrame.new(pos, pos + Vector3.new(1, 0, 0)) -- лицом на восток, к лестнице
end

----------------------------------------------------------------------
-- Карта: лишнее — в бэкап, сырой клон шаблона — в ServerStorage
----------------------------------------------------------------------
local floorsFolder = Instance.new("Folder")
floorsFolder.Name = "HorrorFloors"
floorsFolder.Parent = Workspace
local connectorsFolder = Instance.new("Folder")
connectorsFolder.Name = "HorrorConnectors"
connectorsFolder.Parent = Workspace
local monstersFolder = Instance.new("Folder")
monstersFolder.Name = "Monsters"
monstersFolder.Parent = Workspace

-- Сырой (без декора) клон комнаты для бесконечных копий:
local rawTemplate = templateRoom:Clone()
rawTemplate.Name = "RoomTemplateRaw"
rawTemplate.Parent = ServerStorage

do
	local backup = Instance.new("Folder")
	backup.Name = "OriginalMapBackup"
	backup.Parent = ServerStorage
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	for _, child in ipairs(Workspace:GetChildren()) do
		if child ~= templateRoom and child ~= spawn
			and child ~= floorsFolder and child ~= connectorsFolder and child ~= monstersFolder
			and not child:IsA("Terrain") and not child:IsA("Camera")
			and child.Name ~= "Baseplate" then
			child.Parent = backup
		end
	end
	-- Террейн под картой не нужен (внизу всё равно база), но и не мешает.
end

----------------------------------------------------------------------
-- Состояние игры
----------------------------------------------------------------------
local floors = {}     -- [floorIndex] = record
local connectors = {} -- [floorIndex] = record пролёта floorIndex -> floorIndex+1
local choiceDoors = {} -- [BasePart] = {Connector=record, Correct=bool, Number=int}
local state = {
	currentFloor = 0,
	activeEvent = nil, -- таблица активного события монстра
	started = false,
}
local lastCameraLook = {} -- [Player] = Vector3 (куда смотрит камера)
local lastCameraAt = {}
local touchDebounce = {} -- [Player] = время последнего EnterTrigger

local eventTypes = {}
local function eventTypeFor(floorIndex)
	if eventTypes[floorIndex] then return eventTypes[floorIndex] end
	local t
	if floorIndex <= 0 then
		t = "Safe"
	elseif floorIndex == 1 then
		t = "Stalker" -- обучающий сталкер
	elseif floorIndex == 2 then
		t = "Sound"   -- обучающий звуковой (звук будет всегда)
	elseif floorIndex == 3 then
		t = "Defect"  -- обучающий дефект
	elseif floorIndex % 5 == 0 then
		t = "Choice"  -- этажи 6, 11, 16, ... (индексы 5, 10, 15)
	else
		local rng = Random.new(90210 + floorIndex * 7919)
		local roll = rng:NextNumber()
		if roll < 0.36 then
			t = "Stalker"
		elseif roll < 0.66 then
			t = "Sound"
		else
			t = "Defect"
		end
		-- Перед выбором не ставим дефект: дефект телепортит, а выбор — двери.
		if (floorIndex + 1) % 5 == 0 and t == "Defect" then t = "Stalker" end
	end
	eventTypes[floorIndex] = t
	return t
end

----------------------------------------------------------------------
-- Декор комнаты (базовый, одинаковый на всех этажах — иначе дефект
-- нельзя было бы заметить) + сам дефект на дефектных этажах.
----------------------------------------------------------------------
local POSTER_TEXTS = {
	"НЕ ОБОРАЧИВАЙСЯ", "СЧИТАЙ ЭТАЖИ", "ТИХО", "ОНО СЛЫШИТ",
	"НЕ ВЕРЬ НОМЕРАМ", "СМОТРИ ВНИМАТЕЛЬНО", "5 СЕКУНД ТИШИНЫ",
}

local function addDecor(model, floorIndex)
	local pivot = pivotFor(floorIndex)
	local topY = floorTopY(floorIndex)
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	decor.Parent = model
	local record = {}

	-- Потолочная лампа
	local lamp = makePart(decor, "CeilingLamp", Vector3.new(1.4, 0.25, 1.4),
		CFrame.new(pivot + Vector3.new(0, 7.72, 0)), Color3.fromRGB(70, 68, 64), Enum.Material.Metal, {NoTouch = true})
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Name = "LampLight"
	light.Color = Color3.fromRGB(255, 207, 150)
	light.Brightness = 1.5
	light.Range = 30
	light.Shadows = true
	light.Parent = lamp
	record.Lamp, record.LampLight = lamp, light
	-- Иногда лампа противно мигает (атмосфера, НЕ дефект)
	if (floorIndex % 3) == 2 then
		task.spawn(function()
			while lamp.Parent do
				light.Enabled = true
				task.wait(Random.new():NextNumber(1.5, 5))
				light.Enabled = false
				task.wait(Random.new():NextNumber(0.04, 0.14))
			end
		end)
	end

	-- Ящик
	record.Crate = makePart(decor, "Crate", Vector3.new(2.6, 2.6, 2.6),
		CFrame.new(pivot + Vector3.new(-11.5, floorTopOffset + 1.3, -12)),
		Color3.fromRGB(94, 78, 58), Enum.Material.Wood, {NoTouch = true})
	-- Стул (сиденье + спинка)
	local chair = Instance.new("Model")
	chair.Name = "Chair"
	chair.Parent = decor
	record.ChairSeat = makePart(chair, "Seat", Vector3.new(2.4, 0.35, 2.2),
		CFrame.new(pivot + Vector3.new(7, floorTopOffset + 1.25, 9.5)),
		Color3.fromRGB(72, 70, 68), Enum.Material.Fabric, {NoTouch = true})
	makePart(chair, "Back", Vector3.new(2.4, 2.6, 0.35),
		CFrame.new(pivot + Vector3.new(7, floorTopOffset + 2.6, 10.55)),
		Color3.fromRGB(72, 70, 68), Enum.Material.Fabric, {NoTouch = true})
	record.Chair = chair
	-- Труба по западной стене
	makePart(decor, "Pipe", Vector3.new(0.35, 0.35, 26),
		CFrame.new(pivot + Vector3.new(-15.35, floorTopOffset + 5.2, 0)),
		Color3.fromRGB(88, 92, 96), Enum.Material.Metal, {NoTouch = true})
	-- Плакат на западной стене (лицом на восток = NormalId.Right у тонкой по X детали)
	local poster = makePart(decor, "Poster", Vector3.new(0.18, 4, 5.4),
		CFrame.new(pivot + Vector3.new(-15.55, floorTopOffset + 5.4, -7)),
		Color3.fromRGB(178, 168, 142), Enum.Material.SmoothPlastic, {NoTouch = true})
	poster.CanCollide = false
	makeLabel(poster, Enum.NormalId.Right, POSTER_TEXTS[(floorIndex % #POSTER_TEXTS) + 1],
		Color3.fromRGB(40, 36, 32))
	record.Poster = poster
	-- Батарея на южной стене
	for i = 0, 4 do
		makePart(decor, "Radiator", Vector3.new(0.5, 3, 0.35),
			CFrame.new(pivot + Vector3.new(-4 + i * 1.1, floorTopOffset + 1.7, -17.35)),
			Color3.fromRGB(96, 98, 100), Enum.Material.Metal, {NoTouch = true})
	end

	-- Табличка с номером этажа у восточной стены (на глухом куске стены)
	local plaque = makePart(model, "FloorPlaque", Vector3.new(3.6, 2, 0.18),
		CFrame.new(pivot + Vector3.new(gapX - 0.65, floorTopOffset + 6, 10))
			* CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(52, 54, 58), Enum.Material.Metal, {NoTouch = true})
	plaque.CanCollide = false
	record.PlaqueLabel = makeLabel(plaque, Enum.NormalId.Front,
		string.format("ЭТАЖ\n%02d", floorIndex + 1), Color3.fromRGB(235, 230, 215))

	-- ДЕФЕКТ (только на дефектных этажах)
	record.DefectTarget = nil
	if eventTypeFor(floorIndex) == "Defect" then
		local variant = (floorIndex % 6) + 1
		if variant == 1 then
			-- Лишний КРАСНЫЙ стул посреди комнаты
			local seat = makePart(decor, "AnomalyTarget", Vector3.new(2.4, 0.35, 2.2),
				CFrame.new(pivot + Vector3.new(1.5, floorTopOffset + 1.25, 1.5)) * CFrame.Angles(0, math.rad(33), 0),
				Color3.fromRGB(178, 30, 30), Enum.Material.SmoothPlastic, {NoTouch = true})
			makePart(decor, "AnomalyBack", Vector3.new(2.4, 2.6, 0.35),
				CFrame.new(pivot + Vector3.new(1.5, floorTopOffset + 2.6, 1.5)) * CFrame.Angles(0, math.rad(33), 0)
					* CFrame.new(0, 0, 1.05),
				Color3.fromRGB(178, 30, 30), Enum.Material.SmoothPlastic, {NoTouch = true})
			record.DefectTarget = seat
		elseif variant == 2 then
			-- Парящий чёрный шар с красным глазом
			local eye = makePart(decor, "AnomalyTarget", Vector3.new(2.2, 2.2, 2.2),
				CFrame.new(pivot + Vector3.new(0, floorTopOffset + 5.6, -4)),
				Color3.fromRGB(8, 8, 10), Enum.Material.SmoothPlastic, {NoTouch = true, Shape = Enum.PartType.Ball})
			eye.CanCollide = false
			local pupil = makePart(decor, "AnomalyPupil", Vector3.new(0.6, 0.6, 0.6),
				CFrame.new(pivot + Vector3.new(0, floorTopOffset + 5.6, -5.05)),
				Color3.fromRGB(255, 30, 30), Enum.Material.Neon, {NoTouch = true, Shape = Enum.PartType.Ball})
			pupil.CanCollide = false
			record.DefectTarget = eye
		elseif variant == 3 then
			-- Лампа стала красной
			lamp.Color = Color3.fromRGB(255, 40, 40)
			lamp.Material = Enum.Material.Neon
			light.Color = Color3.fromRGB(255, 50, 50)
			record.DefectTarget = lamp
		elseif variant == 4 then
			-- Ящик парит и наклонён
			local crate = makePart(decor, "AnomalyTarget", Vector3.new(2.6, 2.6, 2.6),
				CFrame.new(pivot + Vector3.new(5, floorTopOffset + 5.4, -7)) * CFrame.Angles(0.5, 0.3, 0.6),
				Color3.fromRGB(94, 78, 58), Enum.Material.Wood, {NoTouch = true})
			crate.CanCollide = false
			record.DefectTarget = crate
		elseif variant == 5 then
			-- Ящик ИСЧЕЗ, осталось только тёмное пятно
			record.Crate:Destroy()
			record.Crate = nil
			local stain = makePart(decor, "AnomalyTarget", Vector3.new(3.2, 0.08, 3.2),
				CFrame.new(pivot + Vector3.new(-11.5, floorTopOffset + 0.07, -12)),
				Color3.fromRGB(14, 13, 14), Enum.Material.SmoothPlastic, {NoTouch = true})
			stain.CanCollide = false
			record.DefectTarget = stain
		else
			-- Лишняя чёрная дверь на западной стене
			local door = makePart(decor, "AnomalyTarget", Vector3.new(0.5, 7.2, 3.6),
				CFrame.new(pivot + Vector3.new(-15.25, floorTopOffset + 3.6, 8.5)),
				Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic, {NoTouch = true})
			record.DefectTarget = door
		end
	end
	record.Decor = decor
	return record
end

local function setPlaqueBlurred(floorIndex, blurred)
	local rec = floors[floorIndex]
	if rec and rec.PlaqueLabel then
		rec.PlaqueLabel.Text = blurred and "▓▓▓▓\n▓▓" or string.format("ЭТАЖ\n%02d", floorIndex + 1)
	end
end

----------------------------------------------------------------------
-- Барьер на выход (закрывает восточный проём)
----------------------------------------------------------------------
local function setBarrier(rec, enabled)
	local existing = rec.Model:FindFirstChild("ExitBarrier")
	if enabled and not existing then
		local pivot = pivotFor(rec.Index)
		local barrier = makePart(rec.Model, "ExitBarrier", Vector3.new(1.2, 16.2, 13.8),
			CFrame.new(pivot + Vector3.new(gapX, 0, gapZ)),
			Color3.new(1, 1, 1), Enum.Material.ForceField, {NoTouch = true})
		barrier.Transparency = 1
	elseif not enabled and existing then
		existing:Destroy()
	end
end

----------------------------------------------------------------------
-- Монстр (собирается из деталей, внешних ассетов нет)
----------------------------------------------------------------------
local function buildMonster(name)
	local model = Instance.new("Model")
	model.Name = name
	local function mp(partName, size, offset, color, material)
		local p = makePart(model, partName, size, CFrame.new(offset), color, material, {NoTouch = true})
		p.CanCollide = false
		return p
	end
	local black = Color3.fromRGB(10, 10, 13)
	local torso = mp("Torso", Vector3.new(2.5, 5, 1.3), Vector3.new(0, 0, 0), black, Enum.Material.SmoothPlastic)
	mp("LegL", Vector3.new(0.8, 4.6, 0.8), Vector3.new(-0.7, -4.6, 0), black, Enum.Material.SmoothPlastic)
	mp("LegR", Vector3.new(0.8, 4.6, 0.8), Vector3.new(0.7, -4.6, 0), black, Enum.Material.SmoothPlastic)
	mp("ArmL", Vector3.new(0.6, 6.4, 0.6), Vector3.new(-1.85, -0.6, 0), black, Enum.Material.SmoothPlastic)
	mp("ArmR", Vector3.new(0.6, 6.4, 0.6), Vector3.new(1.85, -0.6, 0), black, Enum.Material.SmoothPlastic)
	mp("Head", Vector3.new(1.7, 1.9, 1.7), Vector3.new(0, 3.45, 0), black, Enum.Material.SmoothPlastic)
	mp("EyeL", Vector3.new(0.28, 0.28, 0.15), Vector3.new(-0.38, 3.6, -0.86), Color3.fromRGB(255, 25, 25), Enum.Material.Neon)
	mp("EyeR", Vector3.new(0.28, 0.28, 0.15), Vector3.new(0.38, 3.6, -0.86), Color3.fromRGB(255, 25, 25), Enum.Material.Neon)
	mp("Mouth", Vector3.new(0.9, 0.18, 0.12), Vector3.new(0, 2.85, -0.86), Color3.fromRGB(255, 25, 25), Enum.Material.Neon)
	model.PrimaryPart = torso
	model.Parent = monstersFolder
	return model
end

local function placeMonsterInFrontOf(model, player, distance)
	local hrp = getHRP(player)
	if not hrp then return end
	local pos = hrp.Position + hrp.CFrame.LookVector * (distance or 5)
	local pivotY = hrp.Position.Y + 1.5
	model:PivotTo(CFrame.new(Vector3.new(pos.X, pivotY, pos.Z), Vector3.new(hrp.Position.X, pivotY, hrp.Position.Z)))
end

----------------------------------------------------------------------
-- Смерть от монстра + респавн на текущем этаже
----------------------------------------------------------------------
local dying = {}
local function killPlayer(player, reason)
	if not player or dying[player] then return end
	dying[player] = true
	playLocal(player, "Screech")
	fx(player, "Jumpscare", reason or "ОНО ТЕБЯ НАШЛО")
	task.spawn(function()
		task.wait(0.9)
		local _, hum = getHRP(player)
		if hum then hum.Health = 0 end
		task.wait(0.5)
		dying[player] = nil
	end)
end

local function teleportPlayer(player, floorIndex)
	local hrp = getHRP(player)
	if hrp then
		hrp.CFrame = spawnCF(floorIndex)
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

----------------------------------------------------------------------
-- Генерация этажа и пролёта
----------------------------------------------------------------------
local generateFloor, generateConnector, startEvent, advanceFloor -- forward

local function onPlayerEnterFloor(player, floorIndex, via)
	local now = os.clock()
	if touchDebounce[player] and now - touchDebounce[player] < 0.8 then return end
	touchDebounce[player] = now
	local rec = floors[floorIndex]
	if not rec then return end
	if floorIndex == state.currentFloor + 1 then
		if rec.Type == "Choice" and not rec.ChoiceSolved then return end -- сначала двери!
		advanceFloor(player, floorIndex)
	elseif floorIndex == state.currentFloor then
		if rec.Type == "Sound" and rec.EventDone and not rec.ReentryNotified then
			rec.ReentryNotified = true
			say(player, "", "Теперь тихо. Оно ушло. Можно идти дальше.", 3.5)
		end
	end
end

generateFloor = function(floorIndex)
	if floors[floorIndex] and floors[floorIndex].Model and floors[floorIndex].Model.Parent then
		return floors[floorIndex]
	end
	local model
	if floorIndex == 0 then
		model = templateRoom -- оригинал остаётся первым этажом
	else
		model = rawTemplate:Clone()
	end
	model.Name = string.format("Floor_%03d", floorIndex + 1)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true -- на карте половина деталей Room НЕ заанкорена и упала бы
			d.CanTouch = false
		end
	end
	model:PivotTo(CFrame.new(pivotFor(floorIndex)))
	model.Parent = floorsFolder
	model:SetAttribute("FloorIndex", floorIndex)
	model:SetAttribute("EventType", eventTypeFor(floorIndex))

	local rec = {
		Index = floorIndex,
		Model = model,
		Type = eventTypeFor(floorIndex),
		EventDone = false,
		ChoiceSolved = false,
		Visited = false,
	}
	floors[floorIndex] = rec
	local decor = addDecor(model, floorIndex)
	for k, v in pairs(decor) do rec[k] = v end

	-- Триггер входа (just внутри восточного проёма)
	local pivot = pivotFor(floorIndex)
	-- Триггер целиком ВНУТРИ комнаты (западнее барьера), чтобы барьер
	-- события не вытолкнул игрока, едва он вошёл.
	local trigger = makePart(model, "EnterTrigger", Vector3.new(6, 7.5, 10.5),
		CFrame.new(pivot + Vector3.new(gapX - 4.8, floorTopOffset + 3.4, gapZ)),
		Color3.new(1, 1, 1), Enum.Material.ForceField, {})
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then onPlayerEnterFloor(player, floorIndex, "trigger") end
	end)
	rec.Trigger = trigger

	if rec.Type == "Choice" then
		setBarrier(rec, true) -- в комнату нельзя, пока не выбрал дверь на пролёте
	end
	return rec
end

local function onChoiceDoorTouched(part, hit)
	local door = choiceDoors[part]
	if not door or door.Connector.Solved then return end
	local char = hit:FindFirstAncestorOfClass("Model")
	local player = char and Players:GetPlayerFromCharacter(char)
	if not player or dying[player] then return end
	local now = os.clock()
	if touchDebounce[player] and now - touchDebounce[player] < 1.2 then return end
	touchDebounce[player] = now
	local nextIndex = door.Connector.NextIndex
	if door.Correct then
		door.Connector.Solved = true
		local rec = floors[nextIndex]
		if rec then
			rec.ChoiceSolved = true
			setBarrier(rec, false)
		end
		for p in pairs(choiceDoors) do
			if choiceDoors[p].Connector == door.Connector and p.Parent then p:Destroy() end
		end
		playLocal(player, "Good")
		say(player, "ВЕРНАЯ ДВЕРЬ", string.format("Это и правда этаж %d. Иди внутрь.", nextIndex + 1), 3.5)
		teleportPlayer(player, nextIndex)
		advanceFloor(player, nextIndex)
	else
		say(player, "", "Не тот номер...", 1.2)
		killPlayer(player, "ТЫ ВЫБРАЛ НЕ ТУ КОМНАТУ")
	end
end

generateConnector = function(floorIndex)
	if connectors[floorIndex] and connectors[floorIndex].Model and connectors[floorIndex].Model.Parent then
		return connectors[floorIndex]
	end
	local bPivot = pivotFor(floorIndex)
	local tPivot = pivotFor(floorIndex + 1)
	local bTop = floorTopY(floorIndex)
	local model = Instance.new("Model")
	model.Name = string.format("Connector_%03d_%03d", floorIndex + 1, floorIndex + 2)
	model.Parent = connectorsFolder
	local rec = {Index = floorIndex, NextIndex = floorIndex + 1, Model = model, Solved = false, IsChoice = false}
	connectors[floorIndex] = rec

	-- Нижняя площадка (из восточного проёма наружу)
	makePart(model, "LandingLow", Vector3.new(13, 0.5, 7),
		CFrame.new(bPivot + Vector3.new(gapX + 5.5, floorTopOffset - 0.25, gapZ)),
		WALL_COLOR, Enum.Material.Concrete, {NoTouch = true})
	-- Верхняя площадка
	makePart(model, "LandingHigh", Vector3.new(13, 0.5, 7),
		CFrame.new(tPivot + Vector3.new(gapX + 5.5, floorTopOffset - 0.25, gapZ)),
		WALL_COLOR, Enum.Material.Concrete, {NoTouch = true})

	-- Ступени: 20 штук, подъём STEP.Y, бег вдоль +Z (как Escadas на карте)
	local STEPS = 20
	local zStart = bPivot.Z + gapZ + 3.5
	local zEnd = tPivot.Z + gapZ - 3.5
	local flightX = bPivot.X + gapX + 10.4
	for i = 1, STEPS do
		local t = i / STEPS
		local z = zStart + (zEnd - zStart) * ((i - 0.5) / STEPS)
		local top = bTop + STEP.Y * t
		makePart(model, "Step", Vector3.new(5, 0.5, (zEnd - zStart) / STEPS + 0.18),
			CFrame.new(Vector3.new(flightX, top - 0.25, z)),
			WALL_COLOR, Enum.Material.Concrete, {NoTouch = true})
	end
	-- Сегментные ограждения + внешняя стена пролёта (чтобы не падать)
	local spanZ = zEnd - zStart
	for seg = 0, 5 do
		local t = (seg + 0.5) / 6
		local z = zStart + spanZ * t
		local y = bTop + STEP.Y * t
		for _, sideX in ipairs({flightX - 2.85, flightX + 2.85}) do
			local guard = makePart(model, "Guard", Vector3.new(0.35, 4.6, spanZ / 6 + 0.1),
				CFrame.new(Vector3.new(sideX, y + 2.1, z)),
				DARK_COLOR, Enum.Material.Concrete, {NoTouch = true})
			guard.Transparency = (sideX < flightX) and 1 or 0 -- западная — невидимая, восточная — стена
		end
		if seg % 2 == 0 then
			local lamp = makePart(model, "StairLamp", Vector3.new(0.3, 0.9, 0.3),
				CFrame.new(Vector3.new(flightX + 2.55, y + 3.4, z)),
				Color3.fromRGB(255, 205, 145), Enum.Material.Neon, {NoTouch = true})
			lamp.CanCollide = false
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 196, 128)
			l.Brightness = 0.9
			l.Range = 15
			l.Parent = lamp
		end
	end

	-- ВЫБОР КОМНАТЫ: 3 двери поперёк верхней площадки перед проёмом
	if eventTypeFor(floorIndex + 1) == "Choice" then
		rec.IsChoice = true
		local topGapZ = tPivot.Z + gapZ
		local correctNumber = floorIndex + 2 -- человеческий номер следующего этажа
		local numbers = {correctNumber, correctNumber + 2, correctNumber - 1}
		if numbers[3] < 1 then numbers[3] = correctNumber + 5 end
		-- Перемешать позиции детерминированно по номеру этажа
		local rng = Random.new(4242 + floorIndex)
		for i = #numbers, 2, -1 do
			local j = rng:NextInteger(1, i)
			numbers[i], numbers[j] = numbers[j], numbers[i]
		end
		local sign = makePart(model, "ChoiceSign", Vector3.new(0.35, 1.6, 13),
			CFrame.new(Vector3.new(tPivot.X + gapX - 0.35, floorTopY(floorIndex + 1) + 8.6, topGapZ)),
			Color3.fromRGB(40, 40, 44), Enum.Material.Metal, {NoTouch = true})
		sign.CanCollide = false
		makeLabel(sign, Enum.NormalId.Right, "ВЫБЕРИ СВОЮ КОМНАТУ", Color3.fromRGB(255, 120, 120))
		for i, num in ipairs(numbers) do
			local z = topGapZ + (i - 2) * 4.05
			local door = makePart(model, "ChoiceDoor", Vector3.new(0.6, 7.4, 3.6),
				CFrame.new(Vector3.new(tPivot.X + gapX - 0.1, floorTopY(floorIndex + 1) + 3.7, z))
					* CFrame.Angles(0, math.rad(-90), 0),
				Color3.fromRGB(52, 46, 40), Enum.Material.Wood, {})
			makeLabel(door, Enum.NormalId.Front, "КОМНАТА\n" .. tostring(num), Color3.fromRGB(240, 235, 220))
			choiceDoors[door] = {Connector = rec, Correct = (num == correctNumber), Number = num}
			door.Touched:Connect(function(hit) onChoiceDoorTouched(door, hit) end)
		end
	end
	return rec
end

local function ensureGenerated(upToIndex)
	for i = 0, upToIndex do
		generateFloor(i)
	end
	for i = 0, upToIndex - 1 do
		generateConnector(i)
	end
end

local function destroyOldFloors()
	for idx, rec in pairs(floors) do
		if idx < state.currentFloor - 1 then
			if rec.Model then rec.Model:Destroy() end
			floors[idx] = nil
		end
	end
	for idx, rec in pairs(connectors) do
		if idx < state.currentFloor - 1 then
			if rec.Model then rec.Model:Destroy() end
			connectors[idx] = nil
		end
	end
end

----------------------------------------------------------------------
-- События монстров
----------------------------------------------------------------------
local function startStalker(player, floorIndex)
	local rec = floors[floorIndex]
	setBarrier(rec, true) -- выход закрыт, пока не обернёшься
	state.activeEvent = {
		Type = "Stalker", Floor = floorIndex, Player = player, Time = 0,
		Phase = "Hints", Spawned = false, Gaze = 0, HintStage = 0,
	}
	say(player, "?", "Воздух стал гуще. Проверяй, что у тебя ЗА СПИНОЙ.", 4)
end

local function startSound(player, floorIndex)
	local rec = floors[floorIndex]
	local cuePresent = (floorIndex == 2) or (Random.new():NextNumber() < CONFIG.SoundCueChance)
	state.activeEvent = {
		Type = "Sound", Floor = floorIndex, Player = player, Time = 0,
		Phase = "Listen", CuePresent = cuePresent, CueFired = false, DeepWarned = false,
	}
	say(player, "СТОЙ", "Замри у входа и СЛУШАЙ. Если что-то услышишь — беги на этаж вниз.", 4.5)
end

local function startDefect(player, floorIndex)
	local rec = floors[floorIndex]
	setBarrier(rec, true) -- выход закрыт, пока дефект не "сожжён" взглядом
	state.activeEvent = {
		Type = "Defect", Floor = floorIndex, Player = player, Time = 0,
		Progress = 0, Anchor = nil,
	}
	say(player, "ЧТО-ТО НЕ ТАК", "В этой комнате есть ДЕФЕКТ. Найди его, подойди вплотную и смотри на него 5 секунд, не двигаясь.", 6)
end

startEvent = function(floorIndex, player)
	local rec = floors[floorIndex]
	if not rec then return end
	rec.Visited = true
	if rec.Type == "Stalker" and not rec.EventDone then
		startStalker(player, floorIndex)
	elseif rec.Type == "Sound" and not rec.EventDone then
		startSound(player, floorIndex)
	elseif rec.Type == "Defect" and not rec.EventDone then
		startDefect(player, floorIndex)
	elseif rec.Type == "Safe" then
		say(player, string.format("ЭТАЖ %d", floorIndex + 1), "Тихо. Поднимайся по лестнице на востоке комнаты. И считай этажи.", 5)
	else
		say(player, string.format("ЭТАЖ %d", floorIndex + 1), "Дальше. Лестница — на востоке.", 3.5)
	end
end

advanceFloor = function(player, floorIndex)
	if floorIndex == state.currentFloor and state.started then return end
	if not floors[floorIndex] then generateFloor(floorIndex) end
	state.currentFloor = floorIndex
	state.started = true
	-- Прошлые номера больше не подсмотреть:
	for i = 0, floorIndex - 1 do
		setPlaqueBlurred(i, true)
	end
	setPlaqueBlurred(floorIndex, false)
	ensureGenerated(floorIndex + CONFIG.FloorsAhead)
	destroyOldFloors()
	fx(player, "Floor", floorIndex + 1, 4.5)
	playLocal(player, "Click")
	startEvent(floorIndex, player)
	print(string.format("[HorrorStairs] Игрок %s дошёл до этажа %d (%s)",
		player and player.Name or "?", floorIndex + 1, eventTypeFor(floorIndex)))
end

----------------------------------------------------------------------
-- Камера игрока (клиент шлёт, куда смотрит)
----------------------------------------------------------------------
clientEvent.OnServerEvent:Connect(function(player, kind, look)
	if kind == "Camera" and typeof(look) == "Vector3" then
		lastCameraLook[player] = look
		lastCameraAt[player] = os.clock()
	end
end)

local function gazeDot(player, targetPos)
	local hrp = getHRP(player)
	local look = lastCameraLook[player]
	if not hrp or not look or (os.clock() - (lastCameraAt[player] or 0)) > 1.5 then return -1 end
	local dir = targetPos - hrp.Position
	if dir.Magnitude < 0.01 then return -1 end
	return look:Dot(dir.Unit)
end

local function isInFloor(player, floorIndex)
	local hrp = getHRP(player)
	if not hrp then return false end
	local p = pivotFor(floorIndex)
	return math.abs(hrp.Position.X - p.X) < 17
		and math.abs(hrp.Position.Z - p.Z) < 19
		and math.abs(hrp.Position.Y - (p.Y + floorTopOffset)) < 13
end

----------------------------------------------------------------------
-- Обновление активного события (главный цикл)
----------------------------------------------------------------------
local function clearEvent(rec)
	if rec then
		rec.EventDone = true
		setBarrier(rec, false)
	end
	state.activeEvent = nil
end

local function updateStalker(ev, dt)
	local rec = floors[ev.Floor]
	local player = ev.Player
	local hrp = player and getHRP(player)
	if not rec or not hrp then return end
	ev.Time = ev.Time + dt

	if ev.Phase == "Hints" then
		if ev.HintStage == 0 and ev.Time > 2 then
			ev.HintStage = 1
			playLocal(player, "Whisper")
			fx(player, "Glitch", 0.8, 1.2)
			say(player, "", "Сзади что-то шевельнулось...", 2.5)
		elseif ev.HintStage == 1 and ev.Time > 4.5 then
			ev.HintStage = 2
			playLocal(player, "Whisper")
			fx(player, "Glitch", 1.4, 1.6)
			say(player, "", "Оно дышит тебе в затылок. ОБЕРНИСЬ.", 2.5)
		elseif ev.Time >= CONFIG.StalkerSpawnDelay then
			ev.Phase = "Active"
			ev.Time = 0
			local monster = buildMonster("Monster_Stalker")
			ev.Monster = monster
			local behind = hrp.Position - hrp.CFrame.LookVector * 6.5
			local y = hrp.Position.Y + 4.0
			monster:PivotTo(CFrame.new(Vector3.new(behind.X, y, behind.Z),
				Vector3.new(hrp.Position.X, y, hrp.Position.Z)))
			playLocal(player, "Cue")
			fx(player, "Glitch", 2, 2.5)
			say(player, "ОБЕРНИСЬ!", "Оно прямо за тобой. Смотри на него!", 3)
		end
		return
	end

	-- Active: монстр крадётся за спиной, но не успевает за резким поворотом
	local monster = ev.Monster
	if monster and monster.Parent then
		local targetPos = hrp.Position - hrp.CFrame.LookVector * 6.5
		local cur = monster:GetPivot()
		local newPos = cur.Position:Lerp(Vector3.new(targetPos.X, hrp.Position.Y + 1.6, targetPos.Z),
			math.min(1, dt * 1.15))
		monster:PivotTo(CFrame.new(newPos, Vector3.new(hrp.Position.X, newPos.Y, hrp.Position.Z)))
	end

	-- Смотрит ли игрок на монстра?
	local gaze = monster and gazeDot(player, monster:GetPivot().Position) or -1
	if gaze > CONFIG.StalkerGazeDot then
		ev.Gaze = ev.Gaze + dt
		fx(player, "Stare", math.min(1, ev.Gaze / CONFIG.StalkerGazeNeed), "СМОТРИ НА НЕГО...")
	else
		ev.Gaze = math.max(0, ev.Gaze - dt * 1.5)
		if ev.Gaze <= 0 then fx(player, "StareOff") end
	end
	-- Глитчи усиливаются со временем
	if math.random() < dt * 1.6 then
		fx(player, "Glitch", 1.2 + (ev.Time / CONFIG.StalkerKillTime) * 1.6, 0.9)
		playLocal(player, "Whisper")
	end

	if ev.Gaze >= CONFIG.StalkerGazeNeed then
		fx(player, "StareOff")
		playLocalAll("Screech")
		if monster then monster:Destroy() end
		say(player, "ОНО УШЛО", "Ты успел обернуться. Выход открыт.", 3.5)
		clearEvent(rec)
	elseif ev.Time >= CONFIG.StalkerKillTime then
		fx(player, "StareOff")
		if monster then
			placeMonsterInFrontOf(monster, player, 4)
			task.delay(0.15, function() if monster.Parent then monster:Destroy() end end)
		end
		state.activeEvent = nil
		if rec then rec.EventDone = false end -- после респавна попробует снова
		killPlayer(player, "ТЫ НЕ ОБЕРНУЛСЯ")
	end
end

local function updateSound(ev, dt)
	local rec = floors[ev.Floor]
	local player = ev.Player
	if not rec or not getHRP(player) then return end
	ev.Time = ev.Time + dt

	if ev.Phase == "Listen" then
		if ev.CuePresent and not ev.CueFired and ev.Time >= CONFIG.SoundCueDelay then
			ev.CueFired = true
			ev.Phase = "Cue"
			ev.Time = 0
			-- Источник звука — над головой, у потолка этажа
			local pivot = pivotFor(ev.Floor)
			local src = makePart(monstersFolder, "SoundSource", Vector3.new(1, 1, 1),
				CFrame.new(pivot + Vector3.new(0, 7, 0)), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, {NoTouch = true})
			src.Transparency = 1
			src.CanCollide = false
			local s = Instance.new("Sound")
			s.SoundId = SOUND_DEFS.Cue.Id
			s.Volume = 1
			s.PlaybackSpeed = 0.38
			s.Parent = src
			s:Play()
			Debris:AddItem(src, 4)
			playLocal(player, "Cue")
			fx(player, "Glitch", 1.6, 1.8)
			say(player, "ТЫ ЭТО СЛЫШАЛ", "Что-то наверху. БЕГИ НА ЭТАЖ ВНИЗ и жди там!", 4)
		elseif not ev.CuePresent and ev.Time >= CONFIG.SoundListenTime then
			say(player, "ТИХО", "Звука не было. Этот этаж чист, иди дальше.", 3.5)
			clearEvent(rec)
		end
	elseif ev.Phase == "Cue" then
		-- Полез вглубь комнаты вместо побега — времени почти нет
		local pivot = pivotFor(ev.Floor)
		local hrp = getHRP(player)
		if hrp and not ev.DeepWarned and hrp.Position.X < pivot.X + 3 then
			ev.DeepWarned = true
			ev.Time = math.max(ev.Time, CONFIG.SoundEscapeTime - 2.2)
			say(player, "", "Не туда! НАЗАД, ВНИЗ!", 2)
		end
		if isInFloor(player, ev.Floor - 1) then
			say(player, "ОНО УШЛО", "Шаги наверху стихли. Подожди секунду и заходи заново.", 3.5)
			playLocal(player, "Good")
			clearEvent(rec)
		elseif ev.Time >= CONFIG.SoundEscapeTime then
			local monster = buildMonster("Monster_Sound")
			placeMonsterInFrontOf(monster, player, 4.5)
			task.delay(0.15, function() if monster.Parent then monster:Destroy() end end)
			state.activeEvent = nil
			rec.EventDone = false
			killPlayer(player, "ТЫ ОСТАЛСЯ, ХОТЯ СЛЫШАЛ ЕГО")
		end
	end
end

local function updateDefect(ev, dt)
	local rec = floors[ev.Floor]
	local player = ev.Player
	local hrp = player and getHRP(player)
	if not rec or not hrp then return end
	local target = rec.DefectTarget
	if not target or not target.Parent then
		clearEvent(rec) -- дефекта нет (не должен случаться) — не запираем игрока
		return
	end
	ev.Time = ev.Time + dt
	-- Близость меряем по ГОРИЗОНТАЛИ: дефект может быть на потолке (красная
	-- лампа) или парить — к нему надо "подойти и встать под/рядом".
	local flat = hrp.Position - target.Position
	local dist = Vector3.new(flat.X, 0, flat.Z).Magnitude
	local moving = hrp.AssemblyLinearVelocity.Magnitude > 1.6
	local gaze = gazeDot(player, target.Position)
	local standing = false
	if dist <= CONFIG.DefectStareDistance and gaze > 0.72 and not moving then
		if not ev.Anchor then ev.Anchor = hrp.Position end
		if (hrp.Position - ev.Anchor).Magnitude <= CONFIG.DefectMoveReset then
			standing = true
		end
	end
	if standing then
		ev.Progress = ev.Progress + dt
	else
		if ev.Progress > 0 and (moving or (ev.Anchor and (hrp.Position - ev.Anchor).Magnitude > CONFIG.DefectMoveReset)) then
			say(player, "", "Ты двинулся — отсчёт сначала.", 1.6)
		end
		ev.Progress = 0
		ev.Anchor = hrp.Position
	end
	if ev.Progress > 0 then
		fx(player, "Stare", math.min(1, ev.Progress / CONFIG.DefectStareTime), "НЕ ДВИГАЙСЯ... СМОТРИ НА ДЕФЕКТ")
	else
		fx(player, "StareOff")
	end

	if ev.Progress >= CONFIG.DefectStareTime then
		fx(player, "StareOff")
		playLocal(player, "Good")
		fx(player, "Glitch", 1, 1.2)
		local tp = target.Position
		target:Destroy()
		rec.DefectTarget = nil
		say(player, "ДЕФЕКТ СГОРЕЛ", "Комната отпустила тебя. Перенос на следующий этаж...", 3)
		clearEvent(rec)
		task.spawn(function()
			task.wait(0.8)
			local nextIndex = state.currentFloor + 1
			if not floors[nextIndex] then ensureGenerated(nextIndex) end
			if floors[nextIndex] and floors[nextIndex].Type == "Choice" then
				-- К дверям выбора: на верхнюю площадку пролёта
				local hrp2 = getHRP(player)
				if hrp2 then
					local tpv = pivotFor(nextIndex)
					hrp2.CFrame = CFrame.new(
						Vector3.new(tpv.X + gapX + 5.5, floorTopY(nextIndex) + 3.2, tpv.Z + gapZ),
						Vector3.new(tpv.X + gapX - 4, floorTopY(nextIndex) + 3.2, tpv.Z + gapZ))
				end
			else
				teleportPlayer(player, nextIndex)
				advanceFloor(player, nextIndex)
			end
		end)
		local _ = tp
	end
end

----------------------------------------------------------------------
-- Игроки
----------------------------------------------------------------------
local function onCharacterAdded(player, character)
	task.wait(0.4)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = CONFIG.WalkSpeed end
	teleportPlayer(player, state.currentFloor)
	-- Если монстр убил игрока посреди события — событие начнётся заново
	local rec = floors[state.currentFloor]
	if rec and not rec.EventDone and not state.activeEvent
		and (rec.Type == "Stalker" or rec.Type == "Sound" or rec.Type == "Defect") then
		startEvent(state.currentFloor, player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char) onCharacterAdded(player, char) end)
	if player.Character then onCharacterAdded(player, player.Character) end
	fx(player, "Floor", state.currentFloor + 1, 4)
	if state.currentFloor == 0 then
		task.delay(1.2, function()
			say(player, "БЕСКОНЕЧНЫЕ ЛЕСТНИЦЫ",
				"Поднимайся. Считай этажи. Слушай. Оборачивайся. Лестница наверх — через проём на востоке комнаты.", 7)
		end)
	end
end)
Players.PlayerRemoving:Connect(function(player)
	lastCameraLook[player] = nil
	lastCameraAt[player] = nil
	if state.activeEvent and state.activeEvent.Player == player then
		if state.activeEvent.Monster then state.activeEvent.Monster:Destroy() end
		state.activeEvent = nil
		local rec = floors[state.currentFloor]
		if rec and rec.Type ~= "Defect" then rec.EventDone = false end
		if rec and rec.Type == "Defect" then setBarrier(rec, false) end
	end
end)

----------------------------------------------------------------------
-- Старт мира
----------------------------------------------------------------------
ensureGenerated(CONFIG.FloorsAhead)
state.currentFloor = 0
state.started = true
setPlaqueBlurred(0, false)
print(string.format("[HorrorStairs] Готово. Шаблон Room пивот=%s, STEP=%s, первый клон=%s",
	tostring(TEMPLATE_PIVOT), tostring(STEP), tostring(FIRST_COPY_PIVOT)))

----------------------------------------------------------------------
-- Главный цикл
----------------------------------------------------------------------
local fallCheck = 0
while true do
	local dt = task.wait(0.1)
	local ev = state.activeEvent
	if ev then
		if ev.Type == "Stalker" then updateStalker(ev, dt)
		elseif ev.Type == "Sound" then updateSound(ev, dt)
		elseif ev.Type == "Defect" then updateDefect(ev, dt)
		end
	end
	fallCheck = fallCheck + dt
	if fallCheck > 0.7 then
		fallCheck = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local hrp = getHRP(player)
			if hrp then
				-- Упал сквозь мир / с пролёта — назад на чекпоинт этажа, без смерти
				if hrp.Position.Y < floorTopY(state.currentFloor) - 32 then
					teleportPlayer(player, state.currentFloor)
					say(player, "", "Лестница не отпускает вниз.", 2)
				end
				-- Страховка: зашёл на следующий этаж ногами, а триггер не сработал
				if not state.activeEvent and floors[state.currentFloor + 1]
					and floors[state.currentFloor + 1].Type ~= "Choice"
					and isInFloor(player, state.currentFloor + 1) then
					advanceFloor(player, state.currentFloor + 1)
				end
			end
		end
	end
end
