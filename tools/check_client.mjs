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
local cfMeta = {__mul = function(a, b) return CFrame.new(a.Position + b.Position) end}
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
function methods:SetAttribute(name, value) self._attributes[name] = value end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:GetAttributeChangedSignal(_) return signal() end
function methods:IsA(class) return self._class == class or (class == "BasePart" and self._class == "Part") end
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
    return setmetatable({_class=class, _children={}, _attributes={}, Name=class,
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
local runService = Instance.new("RunService")
function runService:BindToRenderStep(_, _, callback) self.render = callback end
local uiService = Instance.new("UserInputService")
uiService.TouchEnabled = false
uiService.MouseEnabled = true
function uiService:GetFocusedTextBox() return nil end
local tweenService = Instance.new("TweenService")
function tweenService:Create(target, _, props)
    return {Play=function()
        for key, value in pairs(props) do target[key] = value end
    end}
end
local services = {Players=Instance.new("Players"), ReplicatedStorage=replicated, Workspace=workspace,
    RunService=runService, UserInputService=uiService, TweenService=tweenService}
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
local originalCF = root.CFrame
runService.render(0.016)
assert(root.CFrame == originalCF and not root.Anchored
    and head.LocalTransparencyModifier == 0 and arm.LocalTransparencyModifier == 0,
    "HUD interfered with physical avatar or its real limbs")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.C}, false)
assert(humanoid.CameraOffset.Y == -0.65, "crouch no longer lowers the native camera")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.F}, false)
assert(remote.actions[#remote.actions][1] == "Torch" and remote.actions[#remote.actions][2] == false,
    "turning off the light did not signal the Moth survival rule")
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
remote.OnClientEvent:Fire("Hide", true, peek)
runService.render(0.016)
local left = gui:FindFirstChild("Left wardrobe edge")
assert(camera.CameraType == Enum.CameraType.Scriptable
    and (camera.CFrame.Position - peek.Position).Magnitude < 0.1
    and player:GetAttribute("NocturnePeek") and not reticle.Visible
    and left.Size[1] < 0.2 and camera.FieldOfView < 70,
    "wardrobe hides the actual monster or has no nearby-threat pressure")
assert(root.CFrame == originalCF, "wardrobe viewpoint moved the physical avatar")
monster:Destroy()
hotel:Destroy()
remote.OnClientEvent:Fire("Hide", false)
runService.render(0.016)
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid
    and player.CameraMode == Enum.CameraMode.LockFirstPerson
    and not player:GetAttribute("NocturnePeek") and reticle.Visible,
    "native first person did not return after the wardrobe")
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
assert(scare.Visible and stage:FindFirstChild("Last glimpse of MOTH"),
    "a monster not yet replicated to the client left the jumpscare blank")
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
local torch=replacement:FindFirstChild("Invisible torch light source")
    :FindFirstChild("Weak hand torch")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.F}, false)
runService.render(0.016)
assert(torch.Enabled, "pre-finale torch did not work")
local witness=Instance.new("Model")
witness.Name="TheLastWitness"
local finalFace=Instance.new("Part")
finalFace.Name="The face behind the dawn"
finalFace.Parent=witness
witness.Parent=workspace
remote.OnClientEvent:Fire("Finale", witness)
assert(scare.Visible and not modal.Visible and not reticle.Visible
    and stage:FindFirstChild("TheLastWitness")
    and stage:FindFirstChild("TheLastWitness"):FindFirstChild("The face behind the dawn"),
    "door 100 did not show its REAL final creature BEFORE the victory screen")
local finaleHold=false
for _,timer in ipairs(timers) do if timer.at>=2.4 then finaleHold=true end end
assert(finaleHold and not torch.Enabled, "finale has no held beat or leaves the torch on")
drainTimers()
assert(modal.Visible and modal:FindFirstChild("End title").Text=="ВЫХОД"
    and not scare.Visible and replacement.CameraSubject==nextHumanoid,
    "final scare did not lead to victory without detaching the real camera")
-- Even if the last model has not replicated, the giant ring-eyed face remains.
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
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const status = lauxlib.luaL_dostring(state, to_luastring(mock));
if (status !== lua.LUA_OK) {
  const error = to_jsstring(lua.lua_tostring(state, -1));
  const atLine = Number(error.match(/:(\d+):/)?.[1] ?? 0);
  const lines = mock.split("\n");
  const nearby = lines.slice(Math.max(0, atLine - 4), atLine + 2).map((s, i) =>
    `${Math.max(1, atLine - 3) + i}: ${s}`).join("\n");
  throw new Error(`Client avatar/camera smoke test failed: ${error}\n${nearby}`);
}
console.log("HUD smoke test OK: physical camera/crouch/torch and monster close-up precedes retry menu");
