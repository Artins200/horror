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
math.clamp = function(x, lo, hi) return math.min(hi, math.max(lo, x)) end
NumberRange = {new = function(...) return {...} end}
NumberSequence = {new = function(...) return {...} end}
ColorSequence = {new = function(...) return {...} end}
local deferred = {}
local function drainTasks()
    while #deferred > 0 do
        local current = table.remove(deferred, 1)
        current()
    end
end
local observed = {events = {}, monsterPositions = {}, monsterLooks = {},
    wingFrames = 0, maskFrames = 0, limbFrames = 0, clawFrames = 0,
    jawFrames = 0, graceElapsed = 0, sconceChanges = 0}
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
Color3 = {new = function(r, g, b) return {R=r, G=g, B=b} end,
    fromRGB = function(r, g, b) return {R=r / 255, G=g / 255, B=b / 255} end}
UDim = {new = function() return {} end}
UDim2 = {fromScale = function() return {} end}
TweenInfo = {new = function() return {} end}
Enum = setmetatable({}, {__index = function(t, k)
    local values = setmetatable({}, {__index = function(_, v) return v end})
    rawset(t, k, values)
    return values
end})
local entropy = 21451
Random = {new = function(seed)
    if not seed then entropy = (entropy * 313 + 257) % 2147483647; seed = entropy end
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
function methods:FindFirstAncestorOfClass(class)
    local parent = self.Parent
    while parent do
        if parent._class == class then return parent end
        parent = parent.Parent
    end
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
function methods:Clone()
    local copies = {}
    local function duplicate(source)
        local copy = Instance.new(source._class)
        copies[source] = copy
        for property, value in pairs(source) do
            if property ~= "_class" and property ~= "_parent" and property ~= "_children"
                and property ~= "_attributes" and property ~= "Touched" and property ~= "Changed"
                and property ~= "Triggered" and property ~= "Died" and property ~= "Completed"
                and property ~= "CharacterAdded" and property ~= "OnServerEvent" then
                copy[property] = value
            end
        end
        if source._cf then copy.CFrame = source.CFrame end
        for property, value in pairs(source._attributes) do copy:SetAttribute(property, value) end
        for _, child in ipairs(source:GetChildren()) do duplicate(child).Parent = copy end
        return copy
    end
    local copy = duplicate(self)
    for source, replica in pairs(copies) do
        if source.PrimaryPart then replica.PrimaryPart = copies[source.PrimaryPart] end
    end
    return copy
end
function methods:PivotTo(cf)
    if self.Name == "HeldKey" then
        local previous = self.PrimaryPart.CFrame
        local shift = cf.Position - previous.Position
        for _, descendant in ipairs(self:GetDescendants()) do
            if descendant:IsA("BasePart") then descendant.CFrame = CFrame.new(descendant.Position + shift) end
        end
    end
    self.WorldPivot = cf
    if self.Name == "TheRush" or self.Name == "TheBlindGuest" or self.Name == "ThePaleMoth" then
        table.insert(observed.monsterPositions, {name=self.Name, x=cf.Position.X, z=cf.Position.Z})
        if not observed.monsterLooks[self.Name] then
            local look = {parts = 0, names = {}, mist = 0, halos = 0, wings = 0, blocks = 0}
            for _, piece in ipairs(self:GetDescendants()) do
                if piece:IsA("BasePart") then
                    look.parts = look.parts + 1
                    look.names[piece.Name] = (look.names[piece.Name] or 0) + 1
                    if piece.Shape == Enum.PartType.Block then look.blocks = look.blocks + 1 end
                    assert(piece.Anchored and piece.CanCollide == false and piece.CanTouch == false,
                        self.Name .. " has physical phantom limbs")
                elseif piece._class == "ParticleEmitter" then
                    look.mist = look.mist + 1
                elseif piece._class == "Highlight" then
                    look.halos = look.halos + 1
                    assert(piece.DepthMode == Enum.HighlightDepthMode.Occluded,
                        "monster must not be visible through hotel walls")
                elseif piece._class == "Model" and (piece.Name == "Veiled left wing"
                    or piece.Name == "Veiled right wing") then
                    look.wings = look.wings + 1
                end
            end
            observed.monsterLooks[self.Name] = look
        end
    elseif self.Name == "Veiled left wing" or self.Name == "Veiled right wing" then
        observed.wingFrames = observed.wingFrames + 1
    elseif self.Name == "Searching mask and neck" then
        observed.maskFrames = observed.maskFrames + 1
    elseif self.Name == "Left hooked arm" or self.Name == "Right hooked arm" then
        observed.clawFrames = observed.clawFrames + 1
    elseif self.Name == "Hinged split mandible" then
        observed.jawFrames = observed.jawFrames + 1
    elseif self.Name == "Left walking leg" or self.Name == "Right walking leg"
        or self.Name == "Left articulated sleeve" or self.Name == "Right articulated sleeve"
        or self.Name == "Left swaying coat hem" or self.Name == "Right swaying coat hem" then
        observed.limbFrames = observed.limbFrames + 1
    end
end
local instMeta = {
    __index = function(t, k)
        if k == "Parent" then return rawget(t, "_parent") end
        if k == "CFrame" then return rawget(t, "_cf") end
        if k == "Enabled" and t._class == "PointLight" then return rawget(t, "_enabled") end
        if k == "Position" then return (rawget(t, "_cf") or CFrame.new()).Position end
        return methods[k]
    end,
    __newindex = function(t, k, v)
        if k == "Parent" then
            rawset(t, "_parent", v)
            if v then table.insert(v._children, t) end
        elseif k == "CFrame" then
            rawset(t, "_cf", v)
        elseif k == "Enabled" and t._class == "PointLight" then
            rawset(t, "_enabled", v)
            observed.sconceChanges = observed.sconceChanges + 1
        else rawset(t, k, v) end
    end,
}
Instance = {new = function(class)
    local obj = setmetatable({_class=class, _children={}, _attributes={}, Name=class,
        Touched=signal(), Changed=signal(), Triggered=signal(), Died=signal(),
        CharacterAdded=signal(), OnServerEvent=signal(), Completed=signal()}, instMeta)
    if class == "ProximityPrompt" or class == "PointLight" then obj.Enabled = true end
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
task = {spawn = function(f) table.insert(deferred, f) end,
    defer = function(f) table.insert(deferred, f) end,
    delay = function(_, f) f() end,
    wait = function(seconds)
        if seconds == 0.5 then
            observed.graceElapsed = observed.graceElapsed + seconds
            if observed.graceCheck then observed.graceCheck() end
        end
        return seconds or 0.1
    end}
function services.ReplicatedStorage:FireClient() end
function services.ReplicatedStorage:FireAllClients() end
local oldNew = Instance.new
Instance.new = function(class)
    local object = oldNew(class)
    if class == "RemoteEvent" then
        function object:FireClient(player, event, a, b)
            table.insert(observed.events, {kind="client", player=player, event=event, a=a, b=b})
        end
        function object:FireAllClients(event, a, b)
            table.insert(observed.events, {kind="all", event=event, a=a, b=b})
        end
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
-- Different runs must rearrange ACTUAL room types; the same seed is replayable.
local a, b, repeated = planRooms(154511), planRooms(984451), planRooms(154511)
local differences, threatDifferences, shapeDifferences, darkCount, lastKind = 0, 0, 0, 0, nil
local kinds = {}
for index = 0, 99 do
    local roomA, roomB = a[index], b[index]
    if roomA.kind ~= roomB.kind then differences = differences + 1 end
    if roomA.threat ~= roomB.threat then threatDifferences = threatDifferences + 1 end
    if roomA.shape ~= roomB.shape then shapeDifferences = shapeDifferences + 1 end
    if roomA.dark then darkCount = darkCount + 1 end
    assert(roomA.kind == repeated[index].kind and roomA.threat == repeated[index].threat
        and roomA.locked == repeated[index].locked and roomA.dark == repeated[index].dark
        and roomA.shape == repeated[index].shape and roomA.decorSeed == repeated[index].decorSeed,
        "room plan changed for the same seed")
    if not NocturneLayout.IsStair(index) and not NocturneLayout.IsTurn(index, 154511) then
        assert(roomA.kind ~= lastKind or index == 0, "consecutive rooms repeated")
        lastKind = roomA.kind
        kinds[roomA.kind] = true
    end
end
local total = 0
for _ in pairs(kinds) do total = total + 1 end
assert(differences > 38 and threatDifferences > 8 and shapeDifferences > 35
    and darkCount >= 10 and total >= 11,
    "seed did not independently regenerate interiors, geometry, threats and unlit rooms")
local ordinary = {}
for index = 2, 99 do
    if a[index].kind ~= "STAIRWELL" and a[index].kind ~= "TURN" then
        table.insert(ordinary, a[index].kind)
    end
end
local repeatsWithinTwelve = 0
for block = 0, 3 do
    local seen = {}
    for i = block * 12 + 1, block * 12 + 12 do
        if seen[ordinary[i]] then repeatsWithinTwelve = repeatsWithinTwelve + 1 end
        seen[ordinary[i]] = true
    end
end
assert(repeatsWithinTwelve >= 2,
    "interiors still arrive in fixed bags containing each of the 12 types once")
end)()
services.Players._players = {}
local function addPlayer(name)
    local player = Instance.new("Player")
    player.Name = name
    player.CharacterAdded = signal()
    function player:LoadCharacter()
        local character = Instance.new("Model")
        character.Name = self.Name
        local root = Instance.new("Part")
        root.Name = "HumanoidRootPart"
        local spawn = self.RespawnLocation
        root.CFrame = spawn and CFrame.new(spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
            or CFrame.new(0, 3, 0)
        root.AssemblyLinearVelocity = Vector3.new()
        root.Parent = character
        local hand = Instance.new("Part")
        hand.Name = "RightHand"
        hand.Size = Vector3.new(0.6, 0.5, 0.6)
        hand.CFrame = root.CFrame * CFrame.new(0.7, 1.1, 0)
        hand.Anchored = false
        hand.Parent = character
        local human = Instance.new("Humanoid")
        human.Name = "Humanoid"
        human.Health = 100
        human.Died = signal()
        human.Parent = character
        self.Character = character
        self.CharacterAdded:Fire(character)
    end
    table.insert(services.Players._players, player)
    services.Players.PlayerAdded:Fire(player)
    return player
end
local function removePlayer(player)
    services.Players.PlayerRemoving:Fire(player)
    for i, other in ipairs(services.Players._players) do
        if other == player then table.remove(services.Players._players, i); break end
    end
end
local player = addPlayer("SmokeTester")
local world = services.Workspace:FindFirstChild("NocturneWorld")
assert(world and world:GetAttribute("DoorsOpened") == 0)
assert(world:GetAttribute("CameraBuild") == "NativeFirstPerson-v6", "old place was loaded")
assert(services.Workspace.Gravity == 196.2, "zero gravity leaves the player floating")
local spawn = world:FindFirstChild("CheckpointSpawn")
assert(spawn and spawn.Anchored and spawn.CanCollide and spawn.Transparency == 1
    and math.abs(spawn.Position.Y + spawn.Size.Y / 2 - NocturneLayout.EntranceY(0)) < 0.01
    and spawn.Position.Z == 10 and player.RespawnLocation == spawn,
    "native spawn pad must meet the walkable floor and own the avatar spawn")
local spawnedRoot = player.Character:FindFirstChild("HumanoidRootPart")
local spawnedHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
assert(spawnedRoot and spawnedRoot.Anchored == false and spawnedHumanoid.AutoRotate == true
    and math.abs(spawnedRoot.Position.Y - 3) < 0.01 and spawnedRoot.Position.Z == 10,
    "native spawn must place the playable avatar on the first room's floor")
local function roomAt(index)
    for _, child in ipairs(world:GetChildren()) do
        if child:GetAttribute("RoomIndex") == index then return child end
    end
end
local remote = services.ReplicatedStorage:FindFirstChild("NocturneRemote")
local L = NocturneLayout.RoomLength
local lockCount, turnCount, rushCount, blindCount, mothCount = 0, 0, 0, 0, 0
local darkCount, physicalShapes = 0, {}
local variants, signatures, structures = {}, {}, {}
local function rootOf(p) return p.Character:FindFirstChild("HumanoidRootPart") end
local function healthOf(p) return p.Character:FindFirstChildOfClass("Humanoid").Health end
local function countEvent(name, kind)
    local count = 0
    for _, ev in ipairs(observed.events) do
        if ev.event == name and (not kind or ev.a == kind) then count = count + 1 end
    end
    return count
end
-- The crouch flag is server-owned and caps WalkSpeed even when Sprint is sent.
remote.OnServerEvent:Fire(player, "Crouch", true)
remote.OnServerEvent:Fire(player, "Sprint", true)
services.RunService.Heartbeat:Fire(0.2)
assert(player:GetAttribute("Crouching") and player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 7)
remote.OnServerEvent:Fire(player, "Crouch", false)
services.RunService.Heartbeat:Fire(0.2)
assert(not player:GetAttribute("Crouching") and player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 12)
for index = 0, 99 do
    local room = roomAt(index)
    assert(room, "missing generated room " .. index)
    assert(room:GetAttribute("EntryY") == NocturneLayout.EntranceY(index))
    assert(room:GetAttribute("ExitY") == NocturneLayout.ExitY(index))
    variants[room:GetAttribute("Variant")] = true
    local shape, dark = room:GetAttribute("Shape"), room:GetAttribute("Dark")
    physicalShapes[shape] = true
    if dark then darkCount = darkCount + 1 end
    structures[index] = room:GetAttribute("Variant") .. ":" .. tostring(shape)
        .. ":" .. tostring(dark)
    signatures[index] = structures[index] .. ":" .. tostring(room:GetAttribute("DecorSeed"))
    local wardrobes, treads, solidFlanks, partitions, arches, drawers, walls = 0, 0, 0, 0, 0, 0, 0
    local crossWalls, columns, vaults, lamps = 0, 0, 0, 0
    -- Collision belongs to the real structural parts, not to the decorative
    -- non-colliding carpet. Test EACH streamed room so a missing floor in a
    -- later storey cannot pass a foyer-only check.
    local loadBearing = {
        ["Continuous wooden subfloor"] = true, ["Load-bearing corridor wall"] = true,
        ["Solid enclosed stair flank"] = true, ["Lower stair landing"] = true,
        ["Upper stair landing"] = true, ["Solid stair tread"] = true,
        ["Doorway threshold"] = true, ["Vestibule cross-wall"] = true,
        ["Freestanding marble arcade column"] = true,
    }
    for _, child in ipairs(room:GetDescendants()) do
        if child.Name == "Wardrobe_A" or child.Name == "Wardrobe_B" then wardrobes = wardrobes + 1 end
        if child.Name == "Solid stair tread" then treads = treads + 1 end
        if child.Name == "Solid enclosed stair flank" then solidFlanks = solidFlanks + 1 end
        if child.Name == "Load-bearing corridor wall" then walls = walls + 1 end
        if child.Name == "Dogleg masonry partition" then partitions = partitions + 1 end
        if child.Name == "Dogleg arch lintel" then arches = arches + 1 end
        if child.Name == "Vestibule cross-wall" then
            crossWalls = crossWalls + 1
            assert(math.abs(child.Position.X) - child.Size.X / 2 >= 6.39,
                "generated wall blocks the door-to-door passage")
        end
        if child.Name == "Freestanding marble arcade column" then
            columns = columns + 1
            assert(math.abs(child.Position.X) > 8.6, "column blocks the main route")
        end
        if child.Name == "Deep coffered cross-vault" then vaults = vaults + 1 end
        if child._class == "PointLight" and child.Parent.Name == "Warm filament" then
            lamps = lamps + 1
            assert(child.Enabled == (not dark), "dark rooms must have OFF physical lamps")
            assert(child.Parent.Material == (dark and Enum.Material.Glass or Enum.Material.Neon),
                "a Neon GUI-like bulb is shining in an unlit room")
        end
        if child.Name == "OpenDrawer" then drawers = drawers + 1 end
        if loadBearing[child.Name] then
            assert(child.Anchored == true and child.CanCollide == true,
                "non-colliding " .. child.Name .. " in room " .. index)
        end
    end
    assert(wardrobes == 2 and lamps > 0, "room without two wardrobes or physical fixtures at " .. index)
    assert(crossWalls == (shape == "VESTIBULE" and 4 or 0)
        and columns == (shape == "ARCADE" and 4 or 0)
        and vaults == (shape == "COFFERED" and 4 or 0),
        "room shape attribute did not produce DIFFERENT traversable masonry")
    for _, name in ipairs({"Wardrobe_A", "Wardrobe_B"}) do
        local wardrobe = room:FindFirstChild(name)
        assert(wardrobe:FindFirstChild("Left hinged leaf") and wardrobe:FindFirstChild("Right hinged leaf"),
            "wardrobe doors must be separate swinging leaves")
    end
    if NocturneLayout.IsStair(index) then
        assert(treads == 16 and solidFlanks == 2, "unclosed stairwell at " .. index)
        assert(drawers == 0, "drawers must not be placed on the stair flight")
        for _, pair in ipairs({{"Lower stair landing", NocturneLayout.EntranceY(index)},
            {"Upper stair landing", NocturneLayout.ExitY(index)}}) do
            local landing = room:FindFirstChild(pair[1])
            assert(landing and landing.Anchored and landing.CanCollide
                and math.abs(landing.Position.Y + landing.Size.Y / 2 - pair[2]) < 0.01,
                "missing walkable " .. pair[1] .. " at room " .. index)
        end
    else
        assert(treads == 0 and drawers == 3 and walls == 2,
            "flat corridor lost its floor, wall or searchable dresser")
        local floor = room:FindFirstChild("Continuous wooden subfloor")
        assert(floor and floor.Anchored and floor.CanCollide
            and floor.Size.X >= NocturneLayout.RoomWidth and floor.Size.Z >= L
            and math.abs(floor.Position.Y + floor.Size.Y / 2 - NocturneLayout.EntranceY(index)) < 0.01,
            "missing walkable subfloor at room " .. index)
    end
    if NocturneLayout.IsTurn(index, world:GetAttribute("Seed")) then
        turnCount = turnCount + 1
        assert(room:GetAttribute("Variant") == "TURN")
        assert(partitions == 4 and arches == 2, "offset arches are not solid masonry")
        local side = NocturneLayout.TurnSide(index, world:GetAttribute("Seed"))
        for _, gate in ipairs({{17, side * 8}, {28, -side * 8}}) do
            local segments = {}
            for _, piece in ipairs(room:GetDescendants()) do
                if piece.Name == "Dogleg masonry partition"
                    and math.abs(piece.Position.Z - (index * L + gate[1])) < 0.01 then
                    table.insert(segments, piece)
                end
            end
            assert(#segments == 2)
            table.sort(segments, function(a, b) return a.Position.X < b.Position.X end)
            local left, right = segments[1], segments[2]
            local openingLeft = left.Position.X + left.Size.X / 2
            local openingRight = right.Position.X - right.Size.X / 2
            assert(math.abs(openingRight - openingLeft - 8.6) < 0.02)
            assert(math.abs((openingLeft + openingRight) / 2 - gate[2]) < 0.02)
            assert(left.Position.X - left.Size.X / 2 <= -NocturneLayout.RoomWidth / 2)
            assert(right.Position.X + right.Size.X / 2 >= NocturneLayout.RoomWidth / 2)
        end
    else
        assert(partitions == 0 and arches == 0)
    end
    -- Enter AND leave both physical wardrobe leaves on each real stair
    -- landing, in the foyer, and after the first dogleg turn.
    if index == 0 or NocturneLayout.IsStair(index) or index == 6 then
        for _, name in ipairs({"Wardrobe_A", "Wardrobe_B"}) do
            local wardrobe = room:FindFirstChild(name)
            local hidePrompt = wardrobe:FindFirstChild("HideInside", true)
            local closePrompt = wardrobe:FindFirstChild("CloseWardrobe", true)
            local root = rootOf(player)
            root.CFrame = CFrame.new(hidePrompt.Parent.Position)
            hidePrompt.Triggered:Fire(player)
            assert(not player:GetAttribute("Hidden") and wardrobe:GetAttribute("Open")
                and hidePrompt.Enabled and hidePrompt.ActionText == "" and hidePrompt.ObjectText == "",
                "opening the wardrobe must not teleport or show a textual hint")
            assert(closePrompt.Enabled, "an open wardrobe should have a close interaction")
            hidePrompt.Triggered:Fire(player)
            assert(player:GetAttribute("Hidden") and root.Anchored, "wardrobe did not hide player")
            assert(not wardrobe:GetAttribute("Open") and hidePrompt.ActionText == "",
                "leaves did not swing shut with a real viewing gap")
            local left = wardrobe:FindFirstChild("Left hinged leaf"):FindFirstChild("Lower oak wardrobe panel")
            local right = wardrobe:FindFirstChild("Right hinged leaf"):FindFirstChild("Lower oak wardrobe panel")
            assert(left and right and right.Position.X - right.Size.X / 2
                - (left.Position.X + left.Size.X / 2) >= 0.9,
                "closed leaves block the player's sightline to the monster")
            remote.OnServerEvent:Fire(player, "Exit")
            assert(not player:GetAttribute("Hidden") and root.Anchored == false
                and player.Character:FindFirstChildOfClass("Humanoid").AutoRotate == true,
                "wardrobe exit did not restore physical movement")
            local landingY = name == "Wardrobe_B" and NocturneLayout.ExitY(index)
                or NocturneLayout.EntranceY(index)
            assert(math.abs(root.Position.Y - landingY - 3) < 0.01, "wardrobe exit is under a floor")
        end
    end
    if NocturneLayout.IsStair(index) then
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) - 10, index * L + 40)
        root.AssemblyLinearVelocity = Vector3.new(0, -100, 0)
        services.RunService.Heartbeat:Fire(0.2)
        assert(root.Position.Y >= NocturneLayout.EntranceY(index) + 3
            and root.AssemblyLinearVelocity.Magnitude == 0,
            "falling underneath a landing did not trigger a safe, stationary return")
    end
    if index == 0 then
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 14, index * L + 19)
        services.RunService.Heartbeat:Fire(0.2)
        assert(root.Position.Y == NocturneLayout.EntranceY(index) + 3,
            "floating above the corridor did not trigger safe return")
    end
    local door = room:FindFirstChild(string.format("Door_%03d", index + 1))
    assert(door, "missing numbered door " .. index + 1)
    local prompt = door:FindFirstChild("OpenDoor", true)
    assert(prompt and prompt.Enabled, "door not enterable from room " .. index)
    local leaf = prompt.Parent
    assert(leaf.Anchored and leaf.CanCollide and
        math.abs(leaf.Position.Y - (NocturneLayout.ExitY(index) + 5.1)) < 0.01,
        "closed door has no solid collision")
    if index == 0 then
        rootOf(player).CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 5)
        prompt.Triggered:Fire(player)
        assert(world:GetAttribute("DoorsOpened") == 0, "distant prompt bypassed the server")
    end
    rootOf(player).CFrame = CFrame.new(0, NocturneLayout.ExitY(index) + 3, (index + 1) * L - 5)
    assert(prompt.ActionText == "" and prompt.ObjectText == "", "door displayed text hints")
    if room:GetAttribute("Locked") then
        lockCount = lockCount + 1
        local dresser = room:FindFirstChild("Three-drawer dresser")
        local concealedKey = dresser:FindFirstChild("TakeKey", true)
        assert(concealedKey and not concealedKey.Enabled, "key should start concealed in a closed drawer")
        rootOf(player).CFrame = CFrame.new(concealedKey.Parent.Position)
        concealedKey.Triggered:Fire(player) -- deliberately bypass the UI as a hostile caller
        assert(not room:GetAttribute("KeyFound") and not player:GetAttribute("HeldKey"),
            "unopened drawer allowed key collection")
        rootOf(player).CFrame = CFrame.new(0, NocturneLayout.ExitY(index) + 3, (index + 1) * L - 5)
        prompt.Triggered:Fire(player)
        assert(world:GetAttribute("DoorsOpened") == index and not door:GetAttribute("Open")
            and countEvent("Locked") == 0, "locked door opened or displayed instructions")
        local firstDrawer = dresser:FindFirstChild("Drawer_1"):FindFirstChild("OpenDrawer", true)
        firstDrawer.Triggered:Fire(player)
        assert(firstDrawer.Enabled, "remote drawer interaction ignored server-side distance")
        local foundKey = false
        for _, drawer in ipairs(dresser:GetChildren()) do
            local openPrompt = drawer:FindFirstChild("OpenDrawer", true)
            if openPrompt then
                rootOf(player).CFrame = CFrame.new(openPrompt.Parent.Position)
                openPrompt.Triggered:Fire(player)
                assert(not openPrompt.Enabled, "drawer was not pulled out")
                local keyPrompt = drawer:FindFirstChild("TakeKey", true)
                if keyPrompt then
                    assert(keyPrompt.Enabled, "the key was not revealed by opening its drawer")
                    rootOf(player).CFrame = CFrame.new(keyPrompt.Parent.Position)
                    keyPrompt.Triggered:Fire(player)
                    foundKey = true
                end
            end
        end
        local held = player.Character:FindFirstChild("HeldKey")
        assert(foundKey and room:GetAttribute("KeyFound") and room:GetAttribute("Locked")
            and held and player:GetAttribute("HeldKey") == index + 1
            and held:FindFirstChild("Key grip in Roblox hand", true)
            and held:FindFirstChild("Key grip in Roblox hand", true).Part0
                == player.Character:FindFirstChild("RightHand"),
            "key was spent on pickup rather than held in a normal Roblox hand")
        if index == 4 then
            -- Dying with a key leaves it in the revealed drawer for a teammate.
            local keyPrompt = dresser:FindFirstChild("TakeKey", true)
            player.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
            assert(not player:GetAttribute("HeldKey") and not player.Character:FindFirstChild("HeldKey")
                and keyPrompt.Enabled and not room:GetAttribute("KeyFound")
                and room:GetAttribute("Locked"), "death permanently lost the only key")
            local teammate = addPlayer("KeyCarrierWhoDisconnected")
            rootOf(teammate).CFrame = CFrame.new(keyPrompt.Parent.Position)
            keyPrompt.Triggered:Fire(teammate)
            assert(teammate:GetAttribute("HeldKey") == 5 and not keyPrompt.Enabled,
                "teammate cannot pick up the returned key")
            removePlayer(teammate)
            assert(keyPrompt.Enabled and not room:GetAttribute("KeyFound"),
                "disconnect permanently lost the team's only key")
            rootOf(player).CFrame = CFrame.new(keyPrompt.Parent.Position)
            keyPrompt.Triggered:Fire(player)
            assert(player:GetAttribute("HeldKey") == 5 and room:GetAttribute("KeyFound"),
                "a returned key cannot be recovered")
        end
        rootOf(player).CFrame = CFrame.new(0, NocturneLayout.ExitY(index) + 3, (index + 1) * L - 5)
    end
    prompt.Triggered:Fire(player)
    assert(world:GetAttribute("DoorsOpened") == index + 1, "player trapped by door " .. index + 1)
    assert(prompt.Enabled and door:GetAttribute("Open") and leaf.CanCollide,
        "hinged door did not restore collision after opening")
    if room:GetAttribute("KeyFound") then
        assert(not room:GetAttribute("Locked") and not player:GetAttribute("HeldKey")
            and not player.Character:FindFirstChild("HeldKey"), "used key remains in hand after unlocking")
    end
    if index == 0 or NocturneLayout.IsTurn(index, world:GetAttribute("Seed")) then
        prompt.Triggered:Fire(player)
        assert(world:GetAttribute("DoorsOpened") == index + 1 and not door:GetAttribute("Open"),
            "visited door cannot close")
        prompt.Triggered:Fire(player)
        assert(world:GetAttribute("DoorsOpened") == index + 1 and door:GetAttribute("Open"),
            "visited door cannot reopen")
    end
    if index < 99 then
        assert(roomAt(index + 1), "door opens into a void at " .. index + 1)
    else
        assert(world:FindFirstChild("Exit"), "door 100 has no finale")
    end
    if room:GetAttribute("Threat") == "RUSH" then rushCount = rushCount + 1 end
    if room:GetAttribute("Threat") == "BLIND" then blindCount = blindCount + 1 end
    if room:GetAttribute("Threat") == "MOTH" then mothCount = mothCount + 1 end
    if index == 5 then
        -- Seed the room-entry trigger, then hide before the scheduled warning.
        -- The runner is already BEYOND the next door, on the side of a turn.
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        assert(#deferred == 1, "flicker did not schedule the Rush")
        local hidePrompt = room:FindFirstChild("Wardrobe_A"):FindFirstChild("HideInside", true)
        root.CFrame = CFrame.new(hidePrompt.Parent.Position)
        hidePrompt.Triggered:Fire(player)
        hidePrompt.Triggered:Fire(player)
        local runner = addPlayer("RunnerBeyondOneDoor")
        rootOf(runner).CFrame = CFrame.new(10, NocturneLayout.EntranceY(6) + 3, 6 * L + 21)
        local lampChanges = observed.sconceChanges
        drainTasks()
        assert(healthOf(player) == 100 and player:GetAttribute("Hidden"), "a wardrobe did not shield from the Rush")
        assert(healthOf(runner) == 0, "a single next door or side alcove stopped the Rush")
        assert(observed.sconceChanges > lampChanges + 20
            and countEvent("Warning") == 0 and countEvent("Safe") == 0,
            "Rush cue must blink the actual bulbs without GUI or textual events")
        local furthest = 0
        for _, m in ipairs(observed.monsterPositions) do
            if m.name == "TheRush" then furthest = math.max(furthest, m.z) end
        end
        assert(furthest > 6 * L + 22, "Rush did not run from behind THROUGH the next room")
        remote.OnServerEvent:Fire(player, "Exit")
        removePlayer(runner)
    end
    if index == 9 then
        -- Three contrasting outcomes in one patrol: standing, touching while
        -- crouched and hiding in a closet all die; distant crouching survives.
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        assert(#deferred == 1, "entering the room did not summon the Blind Guest")
        remote.OnServerEvent:Fire(player, "Crouch", true)
        root.CFrame = CFrame.new(-11, NocturneLayout.EntranceY(index) + 3, index * L + 5)
        local loud = addPlayer("StandingPlayer")
        rootOf(loud).CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 27)
        local contact = addPlayer("CrouchedAtSpawn")
        remote.OnServerEvent:Fire(contact, "Crouch", true)
        rootOf(contact).CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 35)
        local hidden = addPlayer("WardrobeIsNotSafe")
        local hidePrompt = room:FindFirstChild("Wardrobe_B"):FindFirstChild("HideInside", true)
        rootOf(hidden).CFrame = CFrame.new(hidePrompt.Parent.Position)
        hidePrompt.Triggered:Fire(hidden)
        hidePrompt.Triggered:Fire(hidden)
        assert(hidden:GetAttribute("Hidden"))
        -- Flee BACK through a shut visited door. The Guest must reopen it,
        -- follow the stair and turn entrances instead of orbiting room 9.
        local previousDoor = roomAt(8):FindFirstChild("Door_009"):FindFirstChild("OpenDoor", true)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 3)
        previousDoor.Triggered:Fire(player)
        assert(not previousDoor.Parent.Parent:GetAttribute("Open"), "failed to shut the visited door")
        root.CFrame = CFrame.new(-11, NocturneLayout.EntranceY(index) + 3, index * L + 5)
        local retreater = addPlayer("RetreatedIntoRoomEight")
        rootOf(retreater).CFrame = CFrame.new(0, NocturneLayout.EntranceY(8) + 3, 8 * L + 22)
        local turnRunner = addPlayer("RetreatedAcrossTheTurn")
        rootOf(turnRunner).CFrame = CFrame.new(0, NocturneLayout.EntranceY(6) + 3, 6 * L + 24)
        drainTasks()
        assert(healthOf(player) == 100 and player:GetAttribute("Crouching"),
            "a silent croucher away from the creature was detected")
        assert(healthOf(loud) == 0, "standing player was not pursued")
        assert(healthOf(contact) == 0, "crouching allowed walking THROUGH the monster")
        assert(healthOf(hidden) == 0, "the Blind Guest did not inspect the occupied wardrobe")
        assert(previousDoor.Parent.Parent:GetAttribute("Open"), "a shut old door shielded the fleeing player")
        assert(healthOf(retreater) == 0 and healthOf(turnRunner) == 0,
            "Guest stopped at the first doorway or failed to descend to the earlier turn")
        local furthestBack = math.huge
        local crossedTurnGate = false
        for _, m in ipairs(observed.monsterPositions) do
            if m.name == "TheBlindGuest" then
                furthestBack = math.min(furthestBack, m.z)
                if math.abs(m.z - (6 * L + 28)) < 1.5 then
                    crossedTurnGate = crossedTurnGate
                        or math.abs(m.x - NocturneLayout.TurnSide(6, world:GetAttribute("Seed")) * -8) < 2
                end
            end
        end
        assert(furthestBack < 7 * L and crossedTurnGate,
            "Guest cut across masonry or never physically entered the earlier turn")
        assert(countEvent("Warning") == 0 and countEvent("Safe") == 0,
            "Blind Guest gave textual warnings or survival advice")
        remote.OnServerEvent:Fire(player, "Crouch", false)
        removePlayer(loud)
        removePlayer(contact)
        removePlayer(hidden)
        removePlayer(retreater)
        removePlayer(turnRunner)
    end
    if index == 15 then
        -- A switched-off torch beats this creature even when standing close;
        -- merely crouching while shining a light does not.
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        assert(#deferred == 1, "entering the room did not summon the Pale Moth")
        remote.OnServerEvent:Fire(player, "Torch", false)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 30)
        local bright = addPlayer("CrouchedWithTorchOn")
        remote.OnServerEvent:Fire(bright, "Crouch", true)
        rootOf(bright).CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 30)
        local previousBright = addPlayer("FledBackWithLightOn")
        rootOf(previousBright).CFrame = CFrame.new(0, NocturneLayout.EntranceY(14) + 3, 14 * L + 26)
        observed.graceElapsed = 0
        observed.graceCheck = function()
            assert(world:FindFirstChild("ThePaleMoth") and healthOf(bright) == 100,
                "Moth was invisible or killed a torch user DURING its four-second grace")
            local paleFixture = false
            for _, piece in ipairs(room:GetDescendants()) do
                if piece._class == "PointLight" and piece.Parent.Name == "Warm filament"
                    and piece.Enabled and piece.Color.G > piece.Color.R then paleFixture = true end
            end
            assert(paleFixture, "cue is a GUI overlay instead of the room's real cold-coloured lamp")
        end
        drainTasks()
        observed.graceCheck = nil
        assert(observed.graceElapsed >= 4 and countEvent("Warning") == 0,
            "Moth did not give a visible four-second textless warning")
        if room:GetAttribute("Dark") then
            for _, piece in ipairs(room:GetDescendants()) do
                if piece._class == "PointLight" and piece.Parent.Name == "Warm filament" then
                    assert(not piece.Enabled, "Moth left a naturally dark room permanently illuminated")
                end
            end
        end
        assert(healthOf(player) == 100, "unlit player was killed by the light-seeker")
        assert(healthOf(bright) == 0, "crouching protected a player shining a torch")
        assert(healthOf(previousBright) == 0,
            "light-seeking Moth would not follow the torch back into the prior room")
        local mothBack = math.huge
        for _, m in ipairs(observed.monsterPositions) do
            if m.name == "ThePaleMoth" then mothBack = math.min(mothBack, m.z) end
        end
        assert(mothBack < 15 * L - 1, "Moth never crossed the previous doorway")
        assert(countEvent("Warning") == 0 and countEvent("Safe") == 0,
            "Moth encounter still transmitted on-screen survival hints")
        remote.OnServerEvent:Fire(player, "Torch", true)
        removePlayer(bright)
        removePlayer(previousBright)
    end
end
assert(lockCount >= 8 and turnCount == 10, "insufficient locked rooms or turns")
assert(darkCount >= 10 and physicalShapes.ARCADE and physicalShapes.COFFERED
    and physicalShapes.VESTIBULE and physicalShapes.OPEN,
    "new runs need multiple actual room structures and fully unlit rooms")
assert(rushCount >= 4 and blindCount >= 4 and mothCount >= 4
    and rushCount + blindCount + mothCount >= 15,
    "seeded threat spacing omitted one of the three survival mechanics")
local kinds = 0
for _ in pairs(variants) do kinds = kinds + 1 end
assert(kinds >= 11, "room interiors do not vary")
local scareEvents = 0
for _, ev in ipairs(observed.events) do
    if ev.event == "Jumpscare" then
        scareEvents = scareEvents + 1
        local name = ev.a == "RUSH" and "TheRush" or ev.a == "BLIND" and "TheBlindGuest"
            or ev.a == "MOTH" and "ThePaleMoth"
        assert(name and ev.b and ev.b.Name == name and ev.b:GetAttribute("RecentKill"),
            "death did not send the REAL attacking creature for the close-up")
    end
end
assert(scareEvents >= 6, "threats no longer trigger their own death scenes")
local rushLook = observed.monsterLooks.TheRush
local blindLook = observed.monsterLooks.TheBlindGuest
local mothLook = observed.monsterLooks.ThePaleMoth
assert(rushLook and rushLook.parts >= 32 and rushLook.mist >= 5 and rushLook.halos == 1
    and rushLook.names["Cracked funeral mask"] == 1
    and rushLook.names["Three hooked talons"] == 6 and observed.clawFrames > 3
    and rushLook.names["Mandible tendon"] == 2 and observed.jawFrames > 3,
    "Rush lost its face, moving claws or corridor-wide ash wake")
assert(blindLook and blindLook.parts >= 65 and blindLook.blocks == 0 and blindLook.halos == 1
    and blindLook.names["Sculpted ivory eyeless face"] == 1
    and blindLook.names["Overlapping hanging coat fold"] == 5
    and blindLook.names["Hand-sewn eyelid stitch"] == 8
    and blindLook.names["Uneven trailing wool coat tail"] == 2
    and observed.maskFrames > 2 and observed.limbFrames > 8,
    "Blind Guest lost its smooth sculpted face, tailored silhouette or walking gait")
assert(mothLook and mothLook.parts >= 45 and mothLook.wings == 2 and mothLook.halos == 1
    and mothLook.names["Soft layered wing"] == 4
    and mothLook.names["Dark eye on the wing"] == 4
    and mothLook.names["Translucent scalloped wing fringe"] == 16
    and observed.wingFrames > 3,
    "Pale Moth lost its layered, animated wings")
local first = 100 - 8
assert(not roomAt(first - 1), "old rooms were never culled")
local backSeal = roomAt(first):FindFirstChild("The corridor closes behind you")
assert(backSeal and math.abs(backSeal.Position.Y - NocturneLayout.EntranceY(first) - 5.4) < 0.01,
    "the rear doorway is open or sealed at the wrong height")
-- A solo Retry must use FRESH entropy. Inspect actual newly built parts, not
-- merely a different seed label, so cosmetic/dresser details really change.
local oldSeed = world:GetAttribute("Seed")
player.Character:FindFirstChildOfClass("Humanoid").Health = 0
remote.OnServerEvent:Fire(player, "Retry")
local nextWorld = services.Workspace:FindFirstChild("NocturneWorld")
assert(nextWorld ~= world and nextWorld:GetAttribute("Seed") ~= oldSeed,
    "solo replay reused the previous run's random seed")
local nextFirst = nextWorld:FindFirstChild("Room_000_HALL")
local nextDoor = nextFirst:FindFirstChild("Door_001"):FindFirstChild("OpenDoor", true)
rootOf(player).CFrame = CFrame.new(0, 3, L - 5)
nextDoor.Triggered:Fire(player)
local nextStair = nextWorld:FindFirstChild("Room_001_STAIRWELL")
local stairDoor = nextStair:FindFirstChild("Door_002"):FindFirstChild("OpenDoor", true)
rootOf(player).CFrame = CFrame.new(0, NocturneLayout.ExitY(1) + 3, 2 * L - 5)
stairDoor.Triggered:Fire(player)
local changed, structuralChanged = false, false
for _, child in ipairs(nextWorld:GetChildren()) do
    local index = child:GetAttribute("RoomIndex")
    if index and index >= 2 and index <= 3 then
        local structure = child:GetAttribute("Variant") .. ":"
            .. tostring(child:GetAttribute("Shape")) .. ":" .. tostring(child:GetAttribute("Dark"))
        local signature = structure .. ":" .. tostring(child:GetAttribute("DecorSeed"))
        if signature ~= signatures[index] then changed = true end
        if structure ~= structures[index] then structuralChanged = true end
    end
end
assert(changed and structuralChanged,
    "Retry changed only a seed label; the first new rooms kept the same physical form")
return world:GetAttribute("DoorsOpened")
`;
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const status = lauxlib.luaL_dostring(state, to_luastring(mock));
if (status !== lua.LUA_OK) {
  const message = to_jsstring(lua.lua_tostring(state, -1));
  const line = Number(message.match(/:(\d+):/)?.[1] ?? 0);
  const nearby = mock.split("\n").slice(Math.max(0, line - 4), line + 2)
    .map((text, offset) => `${Math.max(1, line - 3) + offset}: ${text}`).join("\n");
  throw new Error(`Server generator smoke test failed: ${message}\n${nearby}`);
}
console.log(`Server smoke test OK: ${lua.lua_tointeger(state, -1)} doors, 17 stairs, 10 turns, keys and hinged leaves; Rush, Blind Guest and flashlight-sensitive Moth`);
