// Exercise the HUD separately from the independent perspective bootstrap.
// This does not replace Studio Play: it checks native camera transitions,
// crouch/torch messages and the full-screen model-based death scare.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const layout = fs.readFileSync(path.join(root, "src/ReplicatedStorage/NocturneLayout.luau"), "utf8");
const client = fs.readFileSync(path.join(root, "src/StarterPlayer/StarterPlayerScripts/NocturneClient.client.luau"), "utf8");
const mock = `
math.clamp = function(x, lo, hi) return math.min(hi, math.max(lo, x)) end
local vectorMeta = {
    __index = function(v, k)
        if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    end,
    __add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
    __sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
    __mul = function(a, b)
        if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
        return Vector3.new(b * a.X, b * a.Y, b * a.Z)
    end,
}
Vector3 = {new = function(x, y, z) return setmetatable({X=x or 0, Y=y or 0, Z=z or 0}, vectorMeta) end}
Vector2 = {new = function(x, y) return {X=x, Y=y} end}
local cfMeta = {
    __mul = function(a, b) return CFrame.new(a.Position + b.Position) end,
    __index = {Lerp = function(self, other, alpha)
        return CFrame.new(self.Position + (other.Position - self.Position) * alpha)
    end},
}
CFrame = {
    new = function(x, y, z)
        return setmetatable({Position = type(x) == "table" and x or Vector3.new(x, y, z),
            LookVector = Vector3.new(0, 0, -1), RightVector = Vector3.new(1, 0, 0)}, cfMeta)
    end,
    Angles = function() return CFrame.new() end,
    lookAt = function(from, to)
        return setmetatable({Position = from, LookVector = to - from,
            RightVector = Vector3.new(1, 0, 0)}, cfMeta)
    end,
}
Color3 = {new = function(...) return {...} end, fromRGB = function(...) return {...} end}
UDim = {new = function(...) return {...} end}
UDim2 = {new = function(...) return {...} end, fromScale = function(...) return {...} end,
    fromOffset = function(...) return {...} end}
NumberSequence = {new = function(...) return {...} end}
NumberSequenceKeypoint = {new = function(...) return {...} end}
TweenInfo = {new = function(...) return {...} end}
Enum = setmetatable({}, {__index = function(t, group)
    local values = setmetatable({}, {__index = function(g, key)
        local value = {Name=key, Value=200}
        rawset(g, key, value)
        return value
    end})
    rawset(t, group, values)
    return values
end})
local function signal()
    local s = {callbacks={}}
    function s:Connect(fn) table.insert(self.callbacks, fn); return {Disconnect=function() end} end
    function s:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
    return s
end
local methods = {}
function methods:GetChildren()
    local children = {}
    for _, child in ipairs(self._children) do
        if child.Parent == self then table.insert(children, child) end
    end
    return children
end
function methods:FindFirstChild(name)
    for _, child in ipairs(self:GetChildren()) do if child.Name == name then return child end end
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(self:GetChildren()) do if child._class == class then return child end end
end
function methods:GetDescendants()
    local list = {}
    for _, child in ipairs(self:GetChildren()) do
        table.insert(list, child)
        for _, nested in ipairs(child:GetDescendants()) do table.insert(list, nested) end
    end
    return list
end
function methods:Clone()
    local copy = Instance.new(self._class)
    for key, value in pairs(self) do
        if key ~= "_children" and key ~= "_class" and key ~= "_parent" then copy[key] = value end
    end
    for _, child in ipairs(self:GetChildren()) do child:Clone().Parent = copy end
    return copy
end
function methods:PivotTo(cf) self.WorldPivot = cf end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:GetGuiObjectsAtPosition() return self.guiAtMouse or {} end
function methods:SetAttribute(name, value)
    self._attributes[name] = value
    if self._attributeSignals[name] then self._attributeSignals[name]:Fire() end
end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:GetAttributeChangedSignal(name)
    self._attributeSignals[name] = self._attributeSignals[name] or signal()
    return self._attributeSignals[name]
end
function methods:IsA(class) return self._class == class
    or (class == "BasePart" and self._class == "Part")
    or (class == "GuiButton" and (self._class == "TextButton" or self._class == "ImageButton")) end
function methods:Play()
    assert(self._class == "Sound" and (self.SoundId and self.SoundId:match("^rbxasset://sounds/")
        or self.AudioContent and self.AudioContent:match("^rbxassetid://%d+$")),
        "lost a built-in or the actual supplied AudioContent asset")
    self.IsPlaying = true
    self.Plays = (self.Plays or 0) + 1
end
function methods:Stop() self.IsPlaying = false end
function methods:Destroy() self.Parent = nil end
local instMeta = {
    __index = function(t, k)
        if k == "Parent" then return rawget(t, "_parent") end
        return methods[k]
    end,
    __newindex = function(t, k, value)
        if k == "Parent" then
            rawset(t, "_parent", value)
            if value then table.insert(value._children, t) end
        else rawset(t, k, value) end
    end,
}
Instance = {new = function(class)
    return setmetatable({_class=class, _children={}, _attributes={}, _attributeSignals={}, Name=class,
        MouseButton1Click=signal(), MouseButton1Down=signal(), MouseButton1Up=signal(),
        MouseLeave=signal(), CharacterAdded=signal(), CharacterAppearanceLoaded=signal(),
        InputBegan=signal(), InputEnded=signal(),
        InputChanged=signal(), OnClientEvent=signal()}, instMeta)
end}
local player = Instance.new("Player")
player.Name = "VisibleTester"
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local remote = Instance.new("RemoteEvent")
remote.Name = "NocturneRemote"
remote.actions = {}
function remote:FireServer(action, value) table.insert(self.actions, {action, value}) end
local replicated = Instance.new("ReplicatedStorage")
remote.Parent = replicated
local layoutModule = Instance.new("ModuleScript")
layoutModule.Name = "NocturneLayout"
layoutModule.Parent = replicated
local camera = Instance.new("Camera")
camera.CFrame = CFrame.new(0, 6, 3)
camera.CameraType = Enum.CameraType.Custom
camera.FieldOfView = 70
camera.ViewportSize = {X=1920, Y=1080}
local workspace = Instance.new("Workspace")
workspace.CurrentCamera = camera
camera.Parent = workspace
for name, id in pairs({
    ["музыка_для_слепого когда в одной комнате"] = "129758955680794",
    ["Scary sound"] = "92039668540061",
    ["scarygrowl 1"] = "136894310375981",
}) do
    local source = Instance.new("Sound")
    source.Name = name
    source.AudioContent = "rbxassetid://" .. id -- v14 has NO SoundId
    source.Volume = 0.5
    source.IsPlaying = false
    source.Parent = workspace
end
local runService = Instance.new("RunService")
function runService:BindToRenderStep(_, _, callback) self.render = callback end
local uiService = Instance.new("UserInputService")
uiService.TouchEnabled = false
uiService.MouseEnabled = true
if uiService.TouchEnabled then camera.ViewportSize = {X=380,Y=780} end
function uiService:GetFocusedTextBox() return self.focusedTextBox end
function uiService:GetMouseLocation() return Vector2.new(960, 540) end
local guiService = Instance.new("GuiService")
guiService.MenuIsOpen = false
local tweenService = Instance.new("TweenService")
function tweenService:Create(target, _, props)
    return {Play=function()
        for key, value in pairs(props) do target[key] = value end
    end}
end
local lighting = Instance.new("Lighting")
local soundService = Instance.new("SoundService")
local starterGui = Instance.new("StarterGui")
starterGui.disabled = {}
function starterGui:SetCoreGuiEnabled(which, enabled) self.disabled[which] = not enabled end
local services = {Players=Instance.new("Players"), ReplicatedStorage=replicated, Workspace=workspace,
    RunService=runService, UserInputService=uiService, GuiService=guiService,
    TweenService=tweenService, Lighting=lighting, SoundService=soundService,
    StarterGui=starterGui}
services.Players.LocalPlayer = player
game = {GetService=function(_, name) return services[name] end}
local timers = {}
task = {spawn=function(fn) fn() end,
    delay=function(seconds, fn) table.insert(timers, {at=seconds, callback=fn}) end}
local function drainTimers()
    table.sort(timers, function(a,b) return a.at < b.at end)
    local current = timers
    timers = {}
    for _, timer in ipairs(current) do timer.callback() end
end
function require(module) return module.value end
layoutModule.value = (function()
${layout}
end)();
(function()
${client}
end)();
local function character(name, rig)
    local model = Instance.new("Model")
    model.Name = name
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.CFrame = CFrame.new(0, 3, 10)
    root.Position = root.CFrame.Position
    root.AssemblyLinearVelocity = Vector3.new()
    root.Anchored = false
    root.Parent = model
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Position = Vector3.new(0, 4.7, 10)
    head.LocalTransparencyModifier = 0
    head.Parent = model
    local firstArm
    local names = rig == "R6" and {"Left Arm", "Right Arm"}
        or {"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"}
    for _, limbName in ipairs(names) do
        local limb = Instance.new("Part")
        limb.Name = limbName
        limb.Archivable = true
        limb.Transparency = 0
        limb.LocalTransparencyModifier = 0
        limb.Parent = model
        firstArm = firstArm or limb
    end
    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.CameraOffset = Vector3.new()
    humanoid.MoveDirection = Vector3.new()
    humanoid.RigType = rig == "R6" and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15
    humanoid.Parent = model
    model.Parent = workspace
    return model, root, head, firstArm, humanoid
end
local avatar, root, head, arm, humanoid = character("First life")
player.Character = avatar
player.CharacterAdded:Fire(avatar)
assert(player.CameraMode == Enum.CameraMode.LockFirstPerson
    and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
    "HUD's camera transition detached from the actual Humanoid")
local arrival = soundService:FindFirstChild("Creature at the threshold")
local impact = soundService:FindFirstChild("Corridor arrival impact")
assert(arrival and impact and arrival:FindFirstChildOfClass("EchoSoundEffect")
    and arrival:FindFirstChildOfClass("ReverbSoundEffect"),
    "loud near-field monster cues or masonry echo are missing")
local music = soundService:FindFirstChild("Blind Guest / local theme")
local scary = soundService:FindFirstChild("Rare scary sound")
local growl = soundService:FindFirstChild("Rare scary growl")
assert(music and music.Looped and scary and growl
    and music.AudioContent == "rbxassetid://129758955680794"
    and scary.AudioContent == "rbxassetid://92039668540061"
    and growl.AudioContent == "rbxassetid://136894310375981"
    and not workspace:FindFirstChild("Scary sound").IsPlaying,
    "v14's genuine supplied AudioContent was not cloned for private local playback")
remote.OnClientEvent:Fire("MonsterSpawn", "BLIND", 0)
assert(arrival.IsPlaying and impact.IsPlaying and arrival.Plays == 1,
    "opening a resident monster room played no arrival sound")
remote.OnClientEvent:Fire("MonsterSpawn", "MOTH", 80)
assert(arrival.Plays == 1, "sound blasted a teammate eighty rooms away")
local gui = playerGui:FindFirstChild("NocturneHUD")
local reticle = gui:FindFirstChild("Reticle")
local scare = gui:FindFirstChild("Creature close-up")
local modal = gui:FindFirstChild("End card")
local view = scare:FindFirstChild("Attacking creature")
local stage = view:FindFirstChild("The approaching face")
assert(reticle.Visible and scare.Visible == false and modal.Visible == false
    and view.CurrentCamera and stage, "close-up/first-person UI not initialized")
for _,name in ipairs({"Controls", "Interaction status", "Threat flash", "Threat darkness",
    "Wardrobe controls", "Flashlight status", "Door caption", "Storey"}) do
    assert(not gui:FindFirstChild(name), "survival instruction/GUI flash is still on screen: " .. name)
end
assert(not modal:FindFirstChild("End detail"), "death menu still explains monsters")
local bar = gui:FindFirstChild("Equipment bar")
local wallet = gui:FindFirstChild("Wallet")
assert(bar and wallet and bar:FindFirstChild("Slot FLASHLIGHT")
    and bar:FindFirstChild("Slot PILL") and bar:FindFirstChild("Slot CRUCIFIX")
    and bar:FindFirstChild("Slot BANDAGE") and bar:FindFirstChild("Slot MEDKIT")
    and starterGui.disabled[Enum.CoreGuiType.Backpack]
    and starterGui.disabled[Enum.CoreGuiType.Health],
    "default Roblox Backpack/Health was not replaced by the custom hotbar")
assert(not bar.Visible and not wallet.Visible and not bar:FindFirstChild("Slot PILL").Visible,
    "an empty hotbar or wallet covers the corridor at spawn")
assert(lighting:FindFirstChild("Wardrobe eyestrain")
    and lighting:FindFirstChild("Wardrobe desaturation"),
    "long hiding has no client-only visual effects")
local originalCF = root.CFrame
runService.render(0.016)
assert(root.CFrame == originalCF and not root.Anchored
    and head.LocalTransparencyModifier == 0 and arm.LocalTransparencyModifier == 0,
    "HUD interfered with physical avatar or its real limbs")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.C}, false)
assert(humanoid.CameraOffset.Y == -0.65, "crouch no longer lowers the native camera")
local beforeLight = #remote.actions
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.F}, false)
assert(#remote.actions == beforeLight and not gui:FindFirstChild("Mobile torch").Visible,
    "F created a flashlight before the player found or bought one")
remote.OnClientEvent:Fire("Inventory", {items={FLASHLIGHT=0,PILL=0,CRUCIFIX=0,BANDAGE=0,MEDKIT=0},
    selected=1,charge=0,health=100,coins=3,notes=0,gold=0})
assert(wallet.Visible and not bar.Visible
    and (not uiService.TouchEnabled or (wallet.Position[1] == 16 and wallet.Position[2] == 55
        and gui:FindFirstChild("Health track").Position[2] == 84
        and gui:FindFirstChild("Stamina track").Position[2] == 99)),
    "taking money exposed an empty inventory or phone status covered the controls")
remote.OnClientEvent:Fire("Inventory", {items={FLASHLIGHT=0,PILL=1,CRUCIFIX=0,BANDAGE=0,MEDKIT=0},
    selected=2,charge=0,health=100,coins=3,notes=0,gold=0})
assert(bar.Visible and bar.Size[1] == (uiService.TouchEnabled and 54 or 52)
    and bar.Size[2] < 60 and bar.Size[1] < camera.ViewportSize.X
    and bar:FindFirstChild("Slot PILL").Visible
    and not bar:FindFirstChild("Slot FLASHLIGHT").Visible
    and not bar:FindFirstChild("Slot MEDKIT").Visible
    and gui:FindFirstChild("Use selected item").Visible == uiService.TouchEnabled,
    "hotbar did not shrink to only the collected item or lost touch controls")
local beforeEmpty = #remote.actions
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.Five}, false)
assert(#remote.actions == beforeEmpty, "number keys select invisible, unowned slots")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.DPadRight}, false)
assert(remote.actions[#remote.actions][1] == "Select" and remote.actions[#remote.actions][2] == 2,
    "gamepad cycling does not skip missing inventory types")
remote.OnClientEvent:Fire("Inventory", {items={FLASHLIGHT=0,PILL=0,CRUCIFIX=0,BANDAGE=0,MEDKIT=0},
    selected=1,charge=0,health=100,coins=3,notes=0,gold=0})
assert(not bar.Visible and wallet.Visible and not gui:FindFirstChild("Use selected item").Visible,
    "inventory or unused touch action stayed onscreen after the last item vanished")
remote.OnClientEvent:Fire("Inventory", {items={FLASHLIGHT=1,PILL=1,CRUCIFIX=1,BANDAGE=1,MEDKIT=1},
    selected=1,charge=100,health=72,coins=12,notes=2,gold=1})
player:SetAttribute("HasFlashlight", true)
player:SetAttribute("TorchCharge", 100)
player:SetAttribute("Health", 72)
assert(wallet.Text:find("12") and wallet.Text:find("2") and wallet.Text:find("1")
    and bar.Visible and bar.Size[1] == (uiService.TouchEnabled and 246 or 236)
    and bar.Size[2] < 60 and bar.Size[1] < camera.ViewportSize.X
    and bar:FindFirstChild("Slot PILL").Visible
    and not bar:FindFirstChild("Slot PILL"):FindFirstChild("Count")
    and bar:FindFirstChild("Slot FLASHLIGHT"):FindFirstChild("Charge").Visible
    and gui:FindFirstChild("Mobile torch").Visible == uiService.TouchEnabled,
    "five unique items, money or the compact battery indicator did not render")
-- In Play this is the server-replicated model, not a fake client viewmodel.
local heldTorch = Instance.new("Model")
heldTorch.Name = "HeldItem"
heldTorch:SetAttribute("ItemKind", "FLASHLIGHT")
heldTorch.Parent = avatar
local lens = Instance.new("Part")
lens.Name = "Torch lens"
lens.Position = Vector3.new(0.5, 4.1, 10)
lens.Parent = heldTorch
local teammateBeam = Instance.new("SpotLight")
teammateBeam.Name = "Selected torch beam"
teammateBeam.Enabled = true
teammateBeam.Parent = lens
local teammateCore = Instance.new("SpotLight")
teammateCore.Name = "Selected torch core"
teammateCore.Enabled = true
teammateCore.Parent = lens
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.F}, false)
assert(remote.actions[#remote.actions][1] == "Use" and remote.actions[#remote.actions][2] == "FLASHLIGHT",
    "found torch did not request an atomic server-owned light toggle")
if uiService.TouchEnabled then
    gui:FindFirstChild("Mobile torch").MouseButton1Click:Fire()
    assert(remote.actions[#remote.actions][1] == "Use"
        and remote.actions[#remote.actions][2] == "FLASHLIGHT",
        "the phone torch button did not activate the actual selected light")
end
player:SetAttribute("TorchOn", true)
runService.render(0.016)
local mount = camera:FindFirstChild("Invisible torch light source")
local light = mount:FindFirstChild("Hand torch flood")
local reach = mount:FindFirstChild("Hand torch reach")
local bounce = mount:FindFirstChild("Hand torch nearby light")
assert(light and reach and bounce and light.Enabled and reach.Enabled and bounce.Enabled
    and light.Brightness >= 3.2 and light.Angle >= 90 and light.Range >= 30
    and reach.Brightness >= 4.4 and reach.Range >= 52
    and reach.Angle < light.Angle / 2 and bounce.Brightness >= 0.8
    and bounce.Range >= 12 and not teammateBeam.Enabled and not teammateCore.Enabled
    and (mount.CFrame.Position - lens.Position).Magnitude < 0.1,
    "torch lacks its brighter near/wide/far light from the actual held lens")
player:SetAttribute("TorchCharge", 0)
runService.render(0)
assert(not light.Enabled and not reach.Enabled and not bounce.Enabled,
    "the strong local beam stayed on after battery depletion")
player:SetAttribute("TorchCharge", 100)
runService.render(0)
assert(light.Enabled and reach.Enabled and bounce.Enabled,
    "a charged selected flashlight failed to light the corridor again")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.Two}, false)
assert(remote.actions[#remote.actions][1] == "Select" and remote.actions[#remote.actions][2] == 2,
    "number keys did not select the custom pill slot")
player:SetAttribute("TorchOn", false)
assert(not light.Enabled and not reach.Enabled and not bounce.Enabled,
    "the bright beam remained on after a light-off acknowledgement")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.Q}, false)
assert(remote.actions[#remote.actions][1] == "Use" and remote.actions[#remote.actions][2] == "PILL",
    "selected consumable was not sent for server-authoritative use")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.One}, false)
player:SetAttribute("TorchCharge", 18)
assert(bar:FindFirstChild("Slot FLASHLIGHT"):FindFirstChild("Charge").BackgroundColor3[1] == 196,
    "low charge did not turn the battery indicator red")
-- Real controls: a world click activates the currently held item, not a GUI
-- click; processed number/Q keys still work when Roblox Backpack consumes them.
local mouse = {UserInputType=Enum.UserInputType.MouseButton1}
local beforeMouse = #remote.actions
uiService.InputBegan:Fire(mouse, false)
assert(#remote.actions == beforeMouse + 1
    and remote.actions[#remote.actions][1] == "Use"
    and remote.actions[#remote.actions][2] == "FLASHLIGHT",
    "clicking the 3-D scene did not activate the selected torch")
playerGui.guiAtMouse = {bar:FindFirstChild("Slot PILL")}
local beforeUI = #remote.actions
uiService.InputBegan:Fire(mouse, false)
uiService.InputBegan:Fire(mouse, true)
assert(#remote.actions == beforeUI, "a click on the HUD also consumed a different item")
playerGui.guiAtMouse = {}
guiService.MenuIsOpen = true
uiService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.Q}, true)
assert(#remote.actions == beforeUI, "pause menu triggered a hidden item")
guiService.MenuIsOpen = false
uiService.focusedTextBox = Instance.new("TextBox")
uiService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.Q}, true)
assert(#remote.actions == beforeUI, "typing in chat used the held item")
uiService.focusedTextBox = nil
local keyboard = Enum.UserInputType.Keyboard
uiService.InputBegan:Fire({UserInputType=keyboard,KeyCode=Enum.KeyCode.Two}, true)
assert(remote.actions[#remote.actions][1] == "Select" and remote.actions[#remote.actions][2] == 2,
    "Roblox-processed number key did not select medicine")
remote.OnClientEvent:Fire("Inventory", {items={FLASHLIGHT=1,PILL=1,CRUCIFIX=1,BANDAGE=1,MEDKIT=1},
    selected=1,charge=18,health=72,coins=12,notes=2,gold=1})
assert(bar:FindFirstChild("Slot PILL").BackgroundColor3[1] == 64,
    "an old inventory snapshot undid the clicked slot before its server ACK")
uiService.InputBegan:Fire({UserInputType=keyboard,KeyCode=Enum.KeyCode.Q}, true)
assert(remote.actions[#remote.actions][1] == "Use" and remote.actions[#remote.actions][2] == "PILL",
    "Roblox-processed Q did not activate the newly selected item")
remote.OnClientEvent:Fire("Inventory", {items={FLASHLIGHT=1,PILL=1,CRUCIFIX=1,BANDAGE=1,MEDKIT=1},
    selected=2,charge=18,health=72,coins=12,notes=2,gold=1})
uiService.InputBegan:Fire({UserInputType=keyboard,KeyCode=Enum.KeyCode.Three}, true)
assert(remote.actions[#remote.actions][1] == "Select" and remote.actions[#remote.actions][2] == 3)
uiService.InputBegan:Fire({UserInputType=keyboard,KeyCode=Enum.KeyCode.Q}, true)
assert(remote.actions[#remote.actions][1] == "Use" and remote.actions[#remote.actions][2] == "CRUCIFIX",
    "raising the cross still does nothing")
uiService.InputBegan:Fire({UserInputType=Enum.UserInputType.Gamepad1,
    KeyCode=Enum.KeyCode.ButtonR2}, true)
assert(remote.actions[#remote.actions][1] == "Use" and remote.actions[#remote.actions][2] == "CRUCIFIX",
    "gamepad trigger could not raise the cross")
local use = gui:FindFirstChild("Use selected item")
assert(use.Visible == uiService.TouchEnabled and use.Text == "✝",
    "phone lost its active cross button")
if uiService.TouchEnabled then
    use.MouseButton1Click:Fire()
    assert(remote.actions[#remote.actions][2] == "CRUCIFIX",
        "phone cross button did not send its activation")
end
bar:FindFirstChild("Slot CRUCIFIX").MouseButton1Click:Fire()
assert(remote.actions[#remote.actions][2] == "CRUCIFIX",
    "second tap/click of the selected cross slot did nothing")
remote.OnClientEvent:Fire("ItemDenied", "CRUCIFIX")
assert(bar:FindFirstChild("Slot CRUCIFIX"):FindFirstChildOfClass("UIStroke").Color[1] == 196
    and soundService:FindFirstChild("Item cannot be used yet").Plays == 1,
    "failed activation still gives no visible/audible acknowledgement")
drainTimers()
for _, pair in ipairs({{4, "BANDAGE", "▣"}, {5, "MEDKIT", "✚"}}) do
    local index, kind, symbol = pair[1], pair[2], pair[3]
    bar:FindFirstChild("Slot " .. kind).MouseButton1Click:Fire()
    assert(remote.actions[#remote.actions][1] == "Select"
        and remote.actions[#remote.actions][2] == index,
        "tapping a medical slot did not equip that item")
    if uiService.TouchEnabled then
        assert(use.Visible and use.Text == symbol,
            "phone's action button does not match the selected medical item")
        use.MouseButton1Click:Fire()
    else
        uiService.InputBegan:Fire(mouse, false)
    end
    assert(remote.actions[#remote.actions][1] == "Use"
        and remote.actions[#remote.actions][2] == kind,
        "medical item click/touch was not sent to the server")
end
local peek = CFrame.new(1, 5, 21)
local hotel = Instance.new("Folder")
hotel.Name = "NocturneWorld"
hotel.Parent = workspace
local monster = Instance.new("Model")
monster.Name = "TheBlindGuest"
monster.Parent = hotel
local body = Instance.new("Part")
body.Position = Vector3.new(1, 5, 27)
body.Parent = monster
monster.PrimaryPart = body
-- The server opens and physically moves the avatar after ONE prompt. During
-- that motion the client keeps the native camera on the real Humanoid, not a
-- detached fly camera, and cannot accidentally use an item or exit early.
local beforeEntry = #remote.actions
remote.OnClientEvent:Fire("WardrobeEnter", true)
runService.render(0.07)
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
    and player.CameraMode == Enum.CameraMode.LockFirstPerson
    and humanoid.CameraOffset.Y < 0 and not reticle.Visible
    and not gui:FindFirstChild("Leave wardrobe").Visible
    and not gui:FindFirstChild("Use selected item").Visible
    and root.CFrame == originalCF,
    "wardrobe entry replaced native first person or moved the real body on the CLIENT")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.E}, false)
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.Q}, false)
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.ButtonB}, false)
assert(#remote.actions == beforeEntry,
    "an entry-in-progress let a second click, exit or item activation interrupt it")
remote.OnClientEvent:Fire("WardrobeEnter", false) -- server cancelled a half-finished entry
assert(humanoid.CameraOffset.Y == 0 and reticle.Visible and not root.Anchored
    and camera.CameraType == Enum.CameraType.Custom,
    "cancelled entry left a frozen or detached viewpoint")
remote.OnClientEvent:Fire("WardrobeEnter", true)
camera.CFrame = CFrame.new(peek.Position + Vector3.new(0, 0, 1.15)) -- real avatar at the back
local nativeEye = camera.CFrame
remote.OnClientEvent:Fire("Hide", true, peek)
runService.render(0.016)
local firstGlide = (camera.CFrame.Position - peek.Position).Magnitude
assert(camera.CameraType == Enum.CameraType.Scriptable
    and firstGlide > 0.3 and firstGlide < (nativeEye.Position - peek.Position).Magnitude
    and player:GetAttribute("NocturnePeek") and not reticle.Visible,
    "final in-closet eye movement snapped or detached from the real avatar")
for _ = 1, 3 do runService.render(0.07) end
local left = gui:FindFirstChild("Left wardrobe edge")
assert((camera.CFrame.Position - peek.Position).Magnitude < 0.1
    and left.Size[1] < 0.2 and camera.FieldOfView < 70,
    "wardrobe hides the actual monster or has no nearby-threat pressure")
assert(root.CFrame == originalCF, "wardrobe viewpoint moved the physical avatar")
player:SetAttribute("ClosetPressure", 75)
runService.render(0.07)
assert(lighting:FindFirstChild("Wardrobe eyestrain").Size > 0
    and gui:FindFirstChild("Sight interference").BackgroundTransparency < 1,
    "long hiding no longer clouds the visible, physical wardrobe sightline")
player:SetAttribute("ClosetPressure", 0)
monster:Destroy()
hotel:Destroy()
remote.OnClientEvent:Fire("Hide", false)
runService.render(0.016)
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
    and player.CameraMode == Enum.CameraMode.LockFirstPerson
    and not player:GetAttribute("NocturnePeek") and reticle.Visible,
    "native first person did not return after the wardrobe")
local spider = Instance.new("Model")
spider.Name = "DrawerSpider"
local abdomen = Instance.new("Part")
abdomen.Name = "Hairy abdomen"
abdomen.Parent = spider
spider.PrimaryPart = abdomen
remote.OnClientEvent:Fire("Spider", spider)
local spiderView = gui:FindFirstChild("Jumping spider")
assert(spiderView.Visible and spiderView.CurrentCamera
    and spiderView:FindFirstChild("WorldModel"):FindFirstChild("DrawerSpider"),
    "drawer spider did not jump toward the actual screen")
drainTimers()
assert(not spiderView.Visible, "jumping spider remained stuck over the scene")
remote.OnClientEvent:Fire("Jumpscare", "ECHO", nil)
local fallback = stage:FindFirstChild("Last glimpse of ECHO")
local echoVeils = 0
for _, piece in ipairs(fallback and fallback:GetChildren() or {}) do
    if piece.Name == "Last trailing echo veil" then echoVeils = echoVeils + 1 end
end
assert(fallback and echoVeils == 2 and fallback.PrimaryPart.Size.X < 1.5,
    "late Echo replication turned its scare back into the ordinary Rush")
local monster = Instance.new("Model")
monster.Name = "TheBlindGuest"
local face = Instance.new("Part")
face.Name = "Oval ashen face"
face.Parent = monster
monster.Parent = workspace
remote.OnClientEvent:Fire("Jumpscare", "BLIND", monster)
assert(scare.Visible and not modal.Visible and not reticle.Visible
    and stage:FindFirstChild("TheBlindGuest")
    and stage:FindFirstChild("TheBlindGuest"):FindFirstChild("Oval ashen face"),
    "death close-up did not display the attacking monster")
remote.OnClientEvent:Fire("Death")
assert(not modal.Visible and scare.Visible,
    "retry menu erased the monster close-up instantly")
local deathHold=false
for _,timer in ipairs(timers) do
    if timer.at>=1.8 then deathHold=true end
end
assert(deathHold, "creature close-up ends before the unsettling second beat")
drainTimers()
assert(modal.Visible and not scare.Visible, "full-screen scare did not finish before retry screen")
-- Respawn cancels any old delayed modal and leaves a real R6 character.
local nextAvatar, nextRoot, nextHead, nextArm, nextHumanoid = character("Second life", "R6")
player.Character = nextAvatar
player.CharacterAdded:Fire(nextAvatar)
runService.render(0.016)
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == nextHumanoid
    and player.CameraMode == Enum.CameraMode.LockFirstPerson
    and not scare.Visible and not modal.Visible and reticle.Visible
    and nextHead.LocalTransparencyModifier == 0 and nextArm.LocalTransparencyModifier == 0
    and not nextRoot.Anchored, "HUD respawn left a detached or hidden avatar")
camera.ViewportSize={X=380,Y=780}
remote.OnClientEvent:Fire("Jumpscare", "MOTH", nil)
local moth = stage:FindFirstChild("Last glimpse of MOTH")
assert(scare.Visible and moth and moth:FindFirstChild("Tiny moth thorax"),
    "unreplicated moths fell back to a giant humanoid instead of a tiny swarm")
remote.OnClientEvent:Fire("Death")
drainTimers()
assert(modal.Visible and not scare.Visible and view.CurrentCamera.CFrame.Position.Z < -6.5,
    "portrait phone close-up cuts off both eyes instead of showing the whole mask")
camera.ViewportSize={X=1920,Y=1080}
player.CharacterAdded:Fire(nextAvatar)
local replacement = Instance.new("Camera")
replacement.CFrame = CFrame.new(0, 6, 3)
replacement.CameraType = Enum.CameraType.Fixed
replacement.FieldOfView = 70
replacement.ViewportSize = {X=1920, Y=1080}
replacement.Parent = workspace
workspace.CurrentCamera = replacement
runService.render(0.016)
assert(replacement.CameraType == Enum.CameraType.Custom
    and replacement.CameraSubject == nextHumanoid,
    "HUD camera replacement stopped following the living avatar")
remote.OnClientEvent:Fire("ItemUsed", "PILL")
for _ = 1, 12 do runService.render(0.07) end
assert(replacement.FieldOfView > 76,
    "using speed medicine gave no visible short-lived first-person response")
local replacementMount = replacement:FindFirstChild("Invisible torch light source")
local torch = replacementMount:FindFirstChild("Hand torch flood")
local replacementReach = replacementMount:FindFirstChild("Hand torch reach")
local replacementBounce = replacementMount:FindFirstChild("Hand torch nearby light")
local carried = Instance.new("Model")
carried.Name = "HeldItem"
carried:SetAttribute("ItemKind", "FLASHLIGHT")
carried.Parent = nextAvatar
local newLens = Instance.new("Part")
newLens.Name = "Torch lens"
newLens.Position = Vector3.new(0.4, 4, 10)
newLens.Parent = carried
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.F}, false)
player:SetAttribute("TorchOn", true)
runService.render(0.016)
assert(torch.Enabled and replacementReach.Enabled and replacementBounce.Enabled,
    "pre-finale found/bought torch lost its extra near and far light")
-- Music belongs only to the player's CURRENT room, follows the roaming Guest,
-- attacks briefly with disordered colours/lines/shake, then fades after exit.
local world = Instance.new("Folder")
world.Name = "NocturneWorld"
world.Parent = workspace
local blind = Instance.new("Model")
blind.Name = "TheBlindGuest"
blind:SetAttribute("RoomIndex", 0)
blind.Parent = world
local blindBody = Instance.new("Part")
blindBody.Position = Vector3.new(0, 4.7, 18)
blindBody.Parent = blind
blind.PrimaryPart = blindBody
local panicSeen = false
for _ = 1, 85 do
    replacement.CFrame = CFrame.new(0, 6, 3) -- Roblox's native CameraModule refreshes each frame
    runService.render(0.07)
    if lighting:FindFirstChild("Blind Guest double vision").Size > 0.1
        and gui:FindFirstChild("Blind signal fracture").BackgroundTransparency < 1 then
        panicSeen = true
    end
end
assert(music.IsPlaying and music.Plays == 1 and music.Volume > 0.25 and panicSeen
    and replacement.CameraType == Enum.CameraType.Custom
    and replacement.CameraSubject == nextHumanoid
    and not workspace:FindFirstChild("музыка_для_слепого когда в одной комнате").IsPlaying,
    "same-room Blind Guest music, personal panic or native camera is missing")
local beforeFade = music.Volume
blind:SetAttribute("RoomIndex", 1) -- monster followed a sound through a door
runService.render(0.07)
assert(music.IsPlaying and music.Volume < beforeFade and music.Volume > 0
    and lighting:FindFirstChild("Blind Guest double vision").Size == 0,
    "music cut off suddenly or panic followed a monster into another room")
for _ = 1, 115 do runService.render(0.07) end
assert(not music.IsPlaying and music.Volume < 0.01
    and music.Plays == 1 and not scary.IsPlaying and not growl.IsPlaying,
    "music never faded/stopped after leaving the Blind Guest")
blind.Parent = nil
-- Two supplied stingers are rare and can NEVER be layered together, even if
-- the first file is longer than the next random cooldown.
for _ = 1, 2100 do runService.render(0.07) end
assert((scary.Plays or 0) + (growl.Plays or 0) == 1
    and scary.IsPlaying ~= growl.IsPlaying,
    "rare sounds did not play independently after a long quiet interval")
for _ = 1, 2100 do runService.render(0.07) end
assert((scary.Plays or 0) + (growl.Plays or 0) == 1,
    "the other scary clip overlapped one already playing")
if scary.IsPlaying then scary.IsPlaying = false else growl.IsPlaying = false end
runService.render(0.07)
for _ = 1, 2100 do runService.render(0.07) end
assert((scary.Plays or 0) + (growl.Plays or 0) == 2
    and not (scary.IsPlaying and growl.IsPlaying),
    "second rare sound did not wait until first ended and its long cooldown passed")
nextRoot.Position = Vector3.new(0, 3, 100 * 44 + 5)
nextRoot.CFrame = CFrame.new(nextRoot.Position)
player:SetAttribute("VoidWalk", true)
local beforeVoidInput = #remote.actions
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.LeftShift, UserInputType=Enum.UserInputType.Keyboard}, false)
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.F, UserInputType=Enum.UserInputType.Keyboard}, false)
for _ = 1, 20 do runService.render(0.07) end
assert(#remote.actions == beforeVoidInput and not torch.Enabled and not replacementReach.Enabled
    and not replacementBounce.Enabled and not reticle.Visible and not bar.Visible
    and not gui:FindFirstChild("Health track").Visible
    and not gui:FindFirstChild("Mobile sprint").Visible
    and not scary.IsPlaying and not growl.IsPlaying
    and lighting:FindFirstChild("Void eye adaptation").Brightness > 0.25
    and lighting:FindFirstChild("Void white bloom").Intensity > 1.4
    and gui:FindFirstChild("White void glare").BackgroundTransparency < 1
    and soundService:FindFirstChild("White void sub-bass").IsPlaying
    and nextHumanoid.CameraOffset.Y < -0.1
    and replacement.CameraType == Enum.CameraType.Custom and replacement.CameraSubject == nextHumanoid
    and not nextRoot.Anchored,
    "white-void lighting/lean/slow controls broke the grounded native first person")
local witness=Instance.new("Model")
witness.Name="TheLastWitness"
local finalFace=Instance.new("Part")
finalFace.Name="The face behind the dawn"
finalFace.Transparency=1 -- invisible template must not spoil a teammate's walk
finalFace.Parent=witness
witness.Parent=world
nextRoot.Position = Vector3.new(0, 3, 100 * 44 + 43)
remote.OnClientEvent:Fire("Finale", witness)
local finalCopy = stage:FindFirstChild("TheLastWitness")
assert(scare.Visible and not modal.Visible and not reticle.Visible
    and finalCopy and finalCopy:FindFirstChild("The face behind the dawn").Transparency == 0
    and finalFace.Transparency == 1 and view.Size[1] == 1.29
    and soundService:FindFirstChild("Final bone impact").IsPlaying
    and (scary.IsPlaying ~= growl.IsPlaying),
    "end of the empty walk did not reveal a PRIVATE face with exclusive layered audio")
local finaleHold=false
for _,timer in ipairs(timers) do if timer.at>=3.25 then finaleHold=true end end
assert(finaleHold and not torch.Enabled and not replacementReach.Enabled
    and not replacementBounce.Enabled, "finale left a bright beam on the death screen")
drainTimers()
assert(modal.Visible and modal:FindFirstChild("End title").Text=="ВЫХОД"
    and not scare.Visible and replacement.CameraSubject==nextHumanoid
    and soundService:FindFirstChild("Final close shriek").Plays == 1
    and soundService:FindFirstChild("Final deep distortion").Plays == 1,
    "final sound design/scare did not lead to victory without detaching the camera")
-- Even if the last model has not replicated, the giant ring-eyed face remains.
witness.Parent = nil
player:SetAttribute("VoidWalk", false) -- authoritative respawn clears its old attribute
player.CharacterAdded:Fire(nextAvatar)
remote.OnClientEvent:Fire("Finale", nil)
local blank=stage:FindFirstChild("Last glimpse of FINAL")
local rings=0
for _,piece in ipairs(blank:GetChildren()) do
    if piece.Name=="Pale orbital rim" then rings=rings+1 end
end
assert(scare.Visible and rings==28 and not modal.Visible,
    "late final-model replication produced a blank jumpscare")
drainTimers()
assert(modal.Visible and not scare.Visible, "fallback finale never completed")
return true
`;
for (const device of ["desktop", "phone"]) {
  const source = device === "phone" ? mock.replace(
    "uiService.TouchEnabled = false\nuiService.MouseEnabled = true",
    "uiService.TouchEnabled = true\nuiService.MouseEnabled = false",
  ) : mock;
  if (device === "phone" && source === mock) throw new Error("Phone mock was not enabled");
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  const status = lauxlib.luaL_dostring(state, to_luastring(source));
  if (status !== lua.LUA_OK) {
    const error = to_jsstring(lua.lua_tostring(state, -1));
    const atLine = Number(error.match(/:(\d+):/)?.[1] ?? 0);
    const lines = source.split("\n");
    const nearby = lines.slice(Math.max(0, atLine - 4), atLine + 2).map((s, i) =>
      `${Math.max(1, atLine - 3) + i}: ${s}`).join("\n");
    throw new Error(`${device} HUD/avatar smoke test failed: ${error}\n${nearby}`);
  }
  console.log(`${device} HUD OK: owned slots, v14 audio, same-room panic/music fade, rare cues and private finale`);
}
