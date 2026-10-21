// Exercise the real client source with a small Roblox-shaped Lua 5.3 stand-in.
// This cannot replace a Studio Play test. It catches regressions that leave the
// avatar locally invisible or the walking camera detached after hiding/respawn.
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
CFrame = {
    new = function(x, y, z)
        return {Position = type(x) == "table" and x or Vector3.new(x, y, z),
            LookVector = Vector3.new(0, 0, -1), RightVector = Vector3.new(1, 0, 0)}
    end,
    lookAt = function(from, to)
        return {Position = from, LookVector = to - from, RightVector = Vector3.new(1, 0, 0)}
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
function methods:WaitForChild(name) return self:FindFirstChild(name) end
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
    return setmetatable({_class=class, _children={}, Name=class,
        MouseButton1Click=signal(), MouseButton1Down=signal(), MouseButton1Up=signal(),
        MouseLeave=signal(), CharacterAdded=signal(), InputBegan=signal(), InputEnded=signal(),
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
task = {spawn=function(fn) fn() end, delay=function(_, _) end}
function require(module) return module.value end
layoutModule.value = (function()
${layout}
end)();
(function()
${client}
end)();
local function character(name)
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
    local arm = Instance.new("Part")
    arm.Name = "LeftHand"
    arm.LocalTransparencyModifier = 0
    arm.Parent = model
    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.CameraOffset = Vector3.new()
    humanoid.Parent = model
    model.Parent = workspace
    return model, root, head, arm, humanoid
end
local avatar, root, head, arm, humanoid = character("First life")
player.Character = avatar
player.CharacterAdded:Fire(avatar)
assert(player.CameraMode == Enum.CameraMode.Classic, "native camera mode not restored on spawn")
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
    "camera must follow the real Humanoid, not a free-floating origin")
assert(player.CameraMinZoomDistance >= 7, "camera zoomed inside the hidden avatar")
local originalCF = root.CFrame
runService.render(0.016)
assert(root.CFrame == originalCF and not root.Anchored, "client overrides physical character movement")
assert(head.LocalTransparencyModifier == 0 and arm.LocalTransparencyModifier == 0,
    "client hides the real Roblox avatar")
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
    "walking camera became Scriptable")
uiService.InputBegan:Fire({KeyCode=Enum.KeyCode.C}, false)
assert(humanoid.CameraOffset.Y == -0.65, "crouch no longer changes the avatar viewpoint")
local peek = CFrame.new(1, 5, 21)
remote.OnClientEvent:Fire("Hide", true, peek)
runService.render(0.016)
assert(camera.CameraType == Enum.CameraType.Scriptable and camera.CFrame == peek,
    "inside the wardrobe the stationary peek camera should open")
assert(root.CFrame == originalCF, "wardrobe camera moved the actual Roblox avatar")
remote.OnClientEvent:Fire("Hide", false)
runService.render(0.016)
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid,
    "camera failed to reattach after leaving wardrobe")
assert(head.LocalTransparencyModifier == 0 and arm.LocalTransparencyModifier == 0)
-- A second life must also recover if the player was still peeking at death.
remote.OnClientEvent:Fire("Hide", true, peek)
local nextAvatar, nextRoot, nextHead, nextArm, nextHumanoid = character("Second life")
player.Character = nextAvatar
player.CharacterAdded:Fire(nextAvatar)
runService.render(0.016)
assert(camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == nextHumanoid
    and nextHead.LocalTransparencyModifier == 0 and nextArm.LocalTransparencyModifier == 0
    and not nextRoot.Anchored, "respawn left an invisible, detached ghost")
local replacementCamera = Instance.new("Camera")
replacementCamera.CFrame = CFrame.new(0, 6, 3)
replacementCamera.CameraType = Enum.CameraType.Fixed
replacementCamera.FieldOfView = 70
replacementCamera.Parent = workspace
workspace.CurrentCamera = replacementCamera
runService.render(0.016)
assert(replacementCamera.CameraType == Enum.CameraType.Custom
    and replacementCamera.CameraSubject == nextHumanoid,
    "camera replacement stopped following the living avatar")
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
console.log("Client smoke test OK: visible Roblox avatar + native camera after spawn, wardrobe exit and respawn");
