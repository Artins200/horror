--[=[
    БЕСКОНЕЧНЫЕ ЛЕСТНИЦЫ — клиент (StarterPlayerScripts > LocalScript)
    Отвечает за: HUD этажа, субтитры, полосу "смотри и не двигайся",
    ГЛИТЧИ (троится в глазах, зависает картинка, статика), скример,
    локальные звуки и отправку серверу направления камеры (чтобы
    сервер знал, обернулся ли ты на сталкера / смотришь ли на дефект).
    Старый LocalScript с проверкой падения заменён: падение теперь
    обрабатывает сервер (телепорт на чекпоинт этажа).
]=]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("HorrorRemotes", 15)
if not remotes then
	warn("[HorrorStairs] Сервер не создал HorrorRemotes — клиентские эффекты отключены")
	return
end
local fxEvent = remotes:WaitForChild("Fx")
local clientEvent = remotes:WaitForChild("Client")

----------------------------------------------------------------------
-- Эффекты в Lighting (локальные)
----------------------------------------------------------------------
local blur = Instance.new("BlurEffect")
blur.Name = "HorrorClientBlur"
blur.Size = 0
blur.Parent = Lighting
local clientCC = Instance.new("ColorCorrectionEffect")
clientCC.Name = "HorrorClientColor"
clientCC.Saturation = -0.15
clientCC.Contrast = 0.06
clientCC.Parent = Lighting

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HorrorGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(name, size, pos, color, transparency, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color or Color3.new(0, 0, 0)
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Visible = false
	f.Parent = gui
	return f
end
local function label(parent, name, size, pos, text, color, fontSize, z)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text or ""
	l.TextColor3 = color or Color3.fromRGB(235, 232, 225)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = fontSize or 20
	l.TextWrapped = true
	l.ZIndex = z or 2
	l.Parent = parent
	return l
end

-- Номер этажа (потом размывается)
local floorLabel = label(gui, "Floor", UDim2.new(1, 0, 0, 54), UDim2.new(0, 0, 0, 26),
	"", Color3.fromRGB(235, 232, 225), 34, 5)
floorLabel.Visible = false

-- Субтитры / подсказки
local msgBox = frame("Msg", UDim2.new(0.72, 0, 0, 118), UDim2.new(0.14, 0, 1, -150), Color3.fromRGB(8, 8, 11), 0.28, 4)
msgBox.Visible = false
local msgTitle = label(msgBox, "Title", UDim2.new(1, -20, 0, 42), UDim2.new(0, 10, 0, 6),
	"", Color3.fromRGB(255, 120, 120), 28, 5)
local msgText = label(msgBox, "Text", UDim2.new(1, -20, 0, 66), UDim2.new(0, 10, 0, 46),
	"", Color3.fromRGB(235, 232, 225), 19, 5)

-- Полоса удержания взгляда
local stareBox = frame("Stare", UDim2.new(0.44, 0, 0, 54), UDim2.new(0.28, 0, 1, -225), Color3.fromRGB(8, 8, 11), 0.25, 4)
local stareTitle = label(stareBox, "Title", UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 0, 2),
	"", Color3.fromRGB(255, 205, 150), 17, 5)
local stareBack = frame("Back", UDim2.new(1, -20, 0, 14), UDim2.new(0, 10, 0, 30), Color3.fromRGB(30, 30, 36), 0, 5)
stareBack.Visible = true
stareBack.Parent = stareBox
local stareFill = frame("Fill", UDim2.new(0, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(255, 70, 60), 0, 6)
stareFill.Visible = true
stareFill.Parent = stareBack
stareBox.Visible = false

-- Статика глитча (полосы)
local staticBars = {}
for i = 1, 14 do
	local b = frame("Static" .. i, UDim2.new(1, 0, 0, math.random(4, 26)),
		UDim2.new(0, 0, math.random(), 0), Color3.new(1, 1, 1), 0.55, 8)
	b.Parent = gui
	table.insert(staticBars, b)
end
local rgbTitle = label(gui, "Rgb", UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0.42, 0),
	"", Color3.fromRGB(255, 60, 60), 40, 9)
rgbTitle.Visible = false

-- Скример
local scare = frame("Scare", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Color3.new(0, 0, 0), 0, 20)
local function scareEye(x)
	local e = frame("Eye", UDim2.new(0, 54, 0, 22), UDim2.new(0.5, x, 0.36, 0), Color3.fromRGB(255, 30, 30), 0, 21)
	e.Visible = true
	e.Parent = scare
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = e
	return e
end
scareEye(-90)
scareEye(36)
local scareMouth = frame("Mouth", UDim2.new(0, 150, 0, 26), UDim2.new(0.5, -75, 0.58, 0), Color3.fromRGB(255, 30, 30), 0, 21)
scareMouth.Parent = scare
local scareText = label(scare, "Text", UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0.72, 0),
	"", Color3.fromRGB(255, 235, 235), 34, 22)

----------------------------------------------------------------------
-- Состояние эффектов
----------------------------------------------------------------------
local glitchUntil, glitchStrength = 0, 0
local freezeUntil, frozenCF = 0, nil
local msgToken = 0
local ghosts = {}

local function destroyGhosts()
	for _, g in ipairs(ghosts) do
		if g.Parent then g:Destroy() end
	end
	ghosts = {}
end

local function makeGhosts()
	destroyGhosts()
	local folder = workspace:FindFirstChild("Monsters")
	local monster = folder and folder:FindFirstChildWhichIsA("Model")
	if not monster then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	for _, side in ipairs({-1, 1}) do
		local ok, clone = pcall(function() return monster:Clone() end)
		if ok and clone then
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = 0.72
					d.Anchored = true
					d.CanCollide = false
				end
			end
			clone.Parent = workspace
			table.insert(ghosts, clone)
			local offset = cam.CFrame.RightVector * (side * 0.85)
			clone:PivotTo(monster:GetPivot() + offset)
		end
	end
end

local function playSound(name)
	local s = SoundService:FindFirstChild("Horror_" .. tostring(name))
	if s then
		s:Stop()
		s:Play()
	end
end

----------------------------------------------------------------------
-- События от сервера
----------------------------------------------------------------------
fxEvent.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Message" then
		msgToken = msgToken + 1
		local token = msgToken
		msgTitle.Text = tostring(a or "")
		msgText.Text = tostring(b or "")
		msgBox.Visible = true
		msgTitle.Visible = (a ~= nil and a ~= "")
		task.delay(tonumber(c) or 4, function()
			if msgToken == token then msgBox.Visible = false end
		end)
	elseif kind == "Floor" then
		local num = tonumber(a) or 1
		floorLabel.Text = string.format("ЭТАЖ %02d", num)
		floorLabel.TextColor3 = Color3.fromRGB(235, 232, 225)
		floorLabel.Visible = true
		task.delay(tonumber(b) or 4.5, function()
			-- Прошлый/текущий номер "размывается": считать надо было самому
			if floorLabel.Text == string.format("ЭТАЖ %02d", num) then
				floorLabel.Text = "ЭТАЖ ▓▓"
				floorLabel.TextColor3 = Color3.fromRGB(120, 120, 128)
			end
		end)
	elseif kind == "Glitch" then
		local strength = tonumber(a) or 1
		local duration = tonumber(b) or 1
		glitchStrength = strength
		glitchUntil = os.clock() + duration
		if strength >= 1.3 then makeGhosts() end
	elseif kind == "Stare" then
		stareBox.Visible = true
		stareTitle.Text = tostring(b or "")
		stareFill.Size = UDim2.new(math.clamp(tonumber(a) or 0, 0, 1), 0, 1, 0)
	elseif kind == "StareOff" then
		stareBox.Visible = false
	elseif kind == "Sound" then
		playSound(a)
	elseif kind == "Jumpscare" then
		scareText.Text = tostring(a or "ОНО ТЕБЯ НАШЛО")
		scare.Visible = true
		playSound("Screech")
		glitchStrength = 3
		glitchUntil = os.clock() + 1
		task.delay(1.05, function() scare.Visible = false end)
	end
end)

----------------------------------------------------------------------
-- Куда смотрит камера -> серверу (сталкер/дефект)
----------------------------------------------------------------------
task.spawn(function()
	while true do
		local cam = workspace.CurrentCamera
		if cam then
			clientEvent:FireServer("Camera", cam.CFrame.LookVector)
		end
		task.wait(0.12)
	end
end)

----------------------------------------------------------------------
-- Глитч-цикл: троится в глазах + зависания
----------------------------------------------------------------------
RunService:BindToRenderStep("HorrorGlitch", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local now = os.clock()
	if now < freezeUntil and frozenCF then
		cam.CFrame = frozenCF -- "зависший" кадр
		return
	end
	if now < glitchUntil then
		local s = glitchStrength
		blur.Size = math.random(6, 14) * s
		cam.FieldOfView = 70 + math.random(-7, 7) * s
		-- Тройная картинка: камера резко дёргается на 3 позиции
		local dx = math.random(-100, 100) / 100 * 0.22 * s
		local dy = math.random(-100, 100) / 100 * 0.16 * s
		cam.CFrame = cam.CFrame * CFrame.new(dx, dy, 0) * CFrame.Angles(0, 0, math.rad(math.random(-2, 2) * s))
		for _, bar in ipairs(staticBars) do
			bar.Visible = math.random() < 0.55
			bar.Position = UDim2.new(0, math.random(-30, 30), math.random(), 0)
			bar.BackgroundTransparency = math.random(35, 80) / 100
		end
		rgbTitle.Visible = s >= 1.4
		if rgbTitle.Visible then
			rgbTitle.Text = "ОБЕРНИСЬ"
			rgbTitle.Position = UDim2.new(0, math.random(-6, 6), 0.42, math.random(-4, 4))
		end
		-- Случайные микрозависания именно когда надо обернуться
		if s >= 1.2 and math.random() < 0.02 then
			frozenCF = cam.CFrame
			freezeUntil = now + math.random(7, 18) / 100
		end
	else
		if blur.Size ~= 0 then blur.Size = 0 end
		if cam.FieldOfView ~= 70 then cam.FieldOfView = 70 end
		for _, bar in ipairs(staticBars) do bar.Visible = false end
		rgbTitle.Visible = false
		if #ghosts > 0 then destroyGhosts() end
	end
end)

print("[HorrorStairs] Клиент готов.")
