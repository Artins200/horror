// Offline server smoke test in a tiny Lua 5.3 Roblox-object stand-in. This does
// not replace a Roblox Studio Play test, but actually executes the server source,
// creates the first two rooms and walks the numbered prompt route through 100.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const layout = fs.readFileSync(path.join(root, "src/ReplicatedStorage/NocturneLayout.luau"), "utf8");
const server = fs.readFileSync(path.join(root, "src/ServerScriptService/NocturneServer.server.luau"), "utf8");
const mock = `
local function signal()
    local s = {callbacks = {}}
    function s:Connect(f)
        table.insert(self.callbacks, f)
        return {Disconnect = function() end}
    end
    function s:Fire(...)
        for _, f in ipairs(self.callbacks) do f(...) end
    end
    function s:Wait() return 0.1 end
    return s
end
local vectorMethods = {}
function vectorMethods:Dot(v) return self.X * v.X + self.Y * v.Y + self.Z * v.Z end
local vectorMeta = {
    __index = function(v, k)
        if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
        return vectorMethods[k]
    end,
    __add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
    __sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
    __div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end,
    __mul = function(a, b)
        if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
        return Vector3.new(b * a.X, b * a.Y, b * a.Z)
    end,
}
Vector3 = {new = function(x, y, z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0}, vectorMeta) end}
Vector2 = {new = function(x, y) return {X=x,Y=y} end}
local cfMeta = {
    __mul = function(a, b) return CFrame.new(a.Position + b.Position) end,
    __index = {PointToWorldSpace = function(self, v) return self.Position + v end},
}
CFrame = {
    new = function(x, y, z)
        local p = type(x) == "table" and x or Vector3.new(x or 0, y or 0, z or 0)
        return setmetatable({Position=p}, cfMeta)
    end,
    Angles = function() return CFrame.new() end,
    lookAt = function(a) return CFrame.new(a) end,
}
Color3 = {new = function() return {} end, fromRGB = function() return {} end}
UDim = {new = function() return {} end}
UDim2 = {fromScale = function() return {} end}
TweenInfo = {new = function() return {} end}
Enum = setmetatable({}, {__index = function(t, k)
    local values = setmetatable({}, {__index = function(_, v) return v end})
    rawset(t, k, values)
    return values
end})
Random = {new = function(seed)
    local r = {value = math.floor(seed) % 2147483647}
    function r:NextNumber(lo, hi)
        self.value = (self.value * 48271) % 2147483647
        local ratio = self.value / 2147483647
        if lo == nil then return ratio end
        return lo + ratio * (hi - lo)
    end
    function r:NextInteger(lo, hi) return math.min(hi, math.floor(self:NextNumber(lo, hi + 1))) end
    return r
end}
local methods = {}
function methods:GetChildren()
    local result = {}
    for _, child in ipairs(rawget(self, "_children")) do
        if child.Parent == self then table.insert(result, child) end
    end
    return result
end
function methods:GetDescendants()
    local result = {}
    local function add(node)
        for _, child in ipairs(node:GetChildren()) do
            table.insert(result, child)
            add(child)
        end
    end
    add(self)
    return result
end
function methods:FindFirstChild(name, recursive)
    for _, child in ipairs(self:GetChildren()) do
        if child.Name == name then return child end
        if recursive then
            local found = child:FindFirstChild(name, true)
            if found then return found end
        end
    end
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(self:GetChildren()) do if child._class == class then return child end end
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:SetAttribute(name, value) self._attributes[name] = value end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:IsA(class) return self._class == class or (class == "BasePart" and
    (self._class == "Part" or self._class == "SpawnLocation")) end
function methods:Destroy()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    self.Parent = nil
end
function methods:PivotTo(cf) self.WorldPivot = cf end
local instMeta = {
    __index = function(t, k)
        if k == "Parent" then return rawget(t, "_parent") end
        if k == "CFrame" then return rawget(t, "_cf") end
        if k == "Position" then return (rawget(t, "_cf") or CFrame.new()).Position end
        return methods[k]
    end,
    __newindex = function(t, k, v)
        if k == "Parent" then
            rawset(t, "_parent", v)
            if v then table.insert(v._children, t) end
        elseif k == "CFrame" then
            rawset(t, "_cf", v)
        else rawset(t, k, v) end
    end,
}
Instance = {new = function(class)
    local obj = setmetatable({_class=class, _children={}, _attributes={}, Name=class,
        Touched=signal(), Changed=signal(), Triggered=signal(), Died=signal(),
        CharacterAdded=signal(), OnServerEvent=signal(), Completed=signal()}, instMeta)
    return obj
end}
local services = {}
for _, name in ipairs({"Players", "ReplicatedStorage", "Workspace", "Lighting", "SoundService", "TweenService", "RunService"}) do
    services[name] = Instance.new(name)
end
services.Players.PlayerAdded = signal()
services.Players.PlayerRemoving = signal()
function services.Players:GetPlayers() return self._players or {} end
function services.Players:GetPlayerFromCharacter(character)
    for _, player in ipairs(self:GetPlayers()) do if player.Character == character then return player end end
end
services.ReplicatedStorage.Name = "ReplicatedStorage"
function services.ReplicatedStorage:WaitForChild(name)
    if name == "NocturneLayout" then return NocturneLayout end
    return self:FindFirstChild(name)
end
function require(module) return module end
function services.TweenService:Create(instance, _, props)
    local tween = {Completed=signal()}
    function tween:Play()
        if props.Value then instance.Value = props.Value; instance.Changed:Fire(props.Value) end
        self.Completed:Fire()
    end
    return tween
end
services.RunService.Heartbeat = signal()
task = {spawn = function(f) f() end, defer = function(f) f() end, wait = function() return 0.1 end}
function services.ReplicatedStorage:FireClient() end
function services.ReplicatedStorage:FireAllClients() end
local oldNew = Instance.new
Instance.new = function(class)
    local object = oldNew(class)
    if class == "RemoteEvent" then
        function object:FireClient() end
        function object:FireAllClients() end
    end
    return object
end
game = {GetService = function(_, name) return services[name] end}
function typeof(value) return type(value) end
NocturneLayout = (function()
${layout}
end)();
(function()
${server}
end)()
local player = Instance.new("Player")
player.Name = "SmokeTester"
player.CharacterAdded = signal()
function player:LoadCharacter()
    local character = Instance.new("Model")
    character.Name = self.Name
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.CFrame = CFrame.new(0, 3, 0)
    root.AssemblyLinearVelocity = Vector3.new()
    root.Parent = character
    local human = Instance.new("Humanoid")
    human.Name = "Humanoid"
    human.Health = 100
    human.Died = signal()
    human.Parent = character
    self.Character = character
    self.CharacterAdded:Fire(character)
end
services.Players._players = {player}
services.Players.PlayerAdded:Fire(player)
local world = services.Workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("DoorsOpened") == 0)
local function roomAt(index)
    for _, child in ipairs(world:GetChildren()) do
        if child:GetAttribute("RoomIndex") == index then return child end
    end
end
for index = 0, 99 do
    local room = roomAt(index)
    assert(room, "missing generated room " .. index)
    assert(room:GetAttribute("EntryY") == NocturneLayout.EntranceY(index))
    assert(room:GetAttribute("ExitY") == NocturneLayout.ExitY(index))
    local wardrobes = 0
    local treads = 0
    local solidFlanks = 0
    for _, child in ipairs(room:GetDescendants()) do
        if child.Name == "Wardrobe_A" or child.Name == "Wardrobe_B" then wardrobes = wardrobes + 1 end
        if child.Name == "Solid stair tread" then treads = treads + 1 end
        if child.Name == "Solid enclosed stair flank" then solidFlanks = solidFlanks + 1 end
    end
    assert(wardrobes == 2, "room without two accessible wardrobe models at " .. index)
    if NocturneLayout.IsStair(index) then
        assert(treads == 16 and solidFlanks == 2, "unclosed stairwell at " .. index)
    else
        assert(treads == 0)
    end
    -- Enter AND leave a wardrobe on both real stair landings. An upper hide
    -- must put us back on the UPPER landing, not beneath the floor slab.
    if index == 0 or NocturneLayout.IsStair(index) then
        for _, name in ipairs({"Wardrobe_A", "Wardrobe_B"}) do
            local closet = room:FindFirstChild(name)
            local hidePrompt = closet:FindFirstChild("HideInside", true)
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            root.CFrame = CFrame.new(hidePrompt.Parent.Position)
            hidePrompt.Triggered:Fire(player)
            assert(player:GetAttribute("Hidden") and root.Anchored, "closet did not hide player")
            services.ReplicatedStorage:FindFirstChild("NocturneRemote").OnServerEvent:Fire(player, "Exit")
            assert(not player:GetAttribute("Hidden") and not root.Anchored, "closet cannot be left")
            local landingY = name == "Wardrobe_B" and NocturneLayout.ExitY(index)
                or NocturneLayout.EntranceY(index)
            assert(math.abs(root.Position.Y - landingY - 3) < 0.01, "wardrobe exit is under a floor")
        end
    end
    if NocturneLayout.IsStair(index) then
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) - 10,
            index * NocturneLayout.RoomLength + 40)
        services.RunService.Heartbeat:Fire(0.2)
        assert(root.Position.Y >= NocturneLayout.EntranceY(index) + 3,
            "falling underneath a landing did not trigger safe return")
    end
    local door = room:FindFirstChild(string.format("Door_%03d", index + 1))
    assert(door, "missing numbered door " .. index + 1)
    local prompt = door:FindFirstChild("OpenDoor", true)
    assert(prompt and prompt.Enabled, "door not enterable from room " .. index)
    local leaf = prompt.Parent
    assert(math.abs(leaf.Position.Y - (NocturneLayout.ExitY(index) + 5.1)) < 0.01)
    player.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(0, NocturneLayout.ExitY(index) + 3,
        (index + 1) * NocturneLayout.RoomLength - 5)
    prompt.Triggered:Fire(player)
    assert(world:GetAttribute("DoorsOpened") == index + 1, "player trapped by door " .. index + 1)
    if index < 99 then
        assert(roomAt(index + 1), "door opens into a void at " .. index + 1)
    else
        assert(world:FindFirstChild("Exit"), "door 100 has no finale")
    end
end
local first = 100 - 5
assert(not roomAt(first - 1), "old rooms were never culled")
local backSeal = roomAt(first):FindFirstChild("The corridor closes behind you")
assert(backSeal and math.abs(backSeal.Position.Y - NocturneLayout.EntranceY(first) - 5.4) < 0.01,
    "the rear doorway is open or sealed at the wrong height")
return world:GetAttribute("DoorsOpened")
`;
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const status = lauxlib.luaL_dostring(state, to_luastring(mock));
if (status !== lua.LUA_OK) {
  throw new Error(`Server generator smoke test failed: ${to_jsstring(lua.lua_tostring(state, -1))}`);
}
console.log(`Server smoke test OK: ${lua.lua_tointeger(state, -1)} doors, 17 sealed stairwells, wardrobe entry/exit and fall rescue`);
