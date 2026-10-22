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
local observed = {events = {}, monsterPositions = {}, monsterLooks = {}, sounds = {},
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
    function s:Wait()
        if observed.onWait then observed.onWait() end
        self:Fire(0.1) -- mimic the Heartbeat callbacks that run while :Wait() resumes
        return 0.1
    end
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
function methods:Play()
    assert(self._class == "Sound" and self.SoundId:match("^rbxasset://sounds/"),
        "invalid or external sound asset")
    self.IsPlaying = true
    table.insert(observed.sounds, {name = self.Name, parent = self.Parent,
        id = self.SoundId, source = self})
end
function methods:Stop() if self._class == "Sound" then self.IsPlaying = false end end
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
function methods:GetPivot() return self.WorldPivot or (self.PrimaryPart and self.PrimaryPart.CFrame) or CFrame.new() end
function methods:PivotTo(cf)
    if self.Name == "HeldKey" or self.Name == "HeldItem" then
        local previous = self.PrimaryPart.CFrame
        local shift = cf.Position - previous.Position
        for _, descendant in ipairs(self:GetDescendants()) do
            if descendant:IsA("BasePart") then descendant.CFrame = CFrame.new(descendant.Position + shift) end
        end
    end
    self.WorldPivot = cf
    if self.Name == "TheRush" or self.Name == "TheEcho" or self.Name == "TheBlindGuest"
        or self.Name == "ThePaleMoth" then
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
        or self.Name == "Left searching arm" or self.Name == "Right searching arm" then
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
        CharacterAdded=signal(), CharacterAppearanceLoaded=signal(),
        OnServerEvent=signal(), Completed=signal()}, instMeta)
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
        seconds = seconds or 0.1
        if seconds == 0.2 and observed.warningCheck then observed.warningCheck() end
        if seconds == 0.5 then
            observed.graceElapsed = observed.graceElapsed + seconds
            if observed.graceCheck then observed.graceCheck() end
        end
        services.RunService.Heartbeat:Fire(seconds)
        return seconds
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
local kinds, shapesSeen, combinedLayouts, recentShapes = {}, {}, {}, {}
local lastEncounter, shops, locks, types = nil, 0, 0, {}
for index = 0, 99 do
    local roomA, roomB = a[index], b[index]
    if roomA.kind ~= roomB.kind then differences = differences + 1 end
    if roomA.threat ~= roomB.threat then threatDifferences = threatDifferences + 1 end
    if roomA.locked then locks = locks + 1 end
    if roomA.shop then
        shops = shops + 1
        assert(index > 50 and index <= 95 and not roomA.threat and not roomA.locked
            and roomA.kind == "MARKET", "shop can appear before door 50 or inside a hazard")
    end
    if roomA.threat then
        types[roomA.threat] = true
        if lastEncounter then
            assert(index - lastEncounter >= 5 and index - lastEncounter <= 15,
                "an encounter occurred before four quiet rooms or after fourteen")
        end
        lastEncounter = index
    end
    if roomA.shape ~= roomB.shape then shapeDifferences = shapeDifferences + 1 end
    if roomA.dark then darkCount = darkCount + 1 end
    if roomA.shape ~= "FIXED" then
        assert(roomA.shape ~= recentShapes[1] and roomA.shape ~= recentShapes[2],
            "recognisable architecture repeats after one door")
        table.insert(recentShapes, roomA.shape)
        if #recentShapes > 2 then table.remove(recentShapes, 1) end
        shapesSeen[roomA.shape] = true
        combinedLayouts[roomA.kind .. ":" .. roomA.shape] = true
    end
    assert(roomA.kind == repeated[index].kind and roomA.threat == repeated[index].threat
        and roomA.locked == repeated[index].locked and roomA.dark == repeated[index].dark
        and roomA.shape == repeated[index].shape and roomA.decorSeed == repeated[index].decorSeed
        and roomA.lightPower == repeated[index].lightPower,
        "room plan changed for the same seed")
    if not NocturneLayout.IsStair(index) and not NocturneLayout.IsTurn(index, 154511) then
        assert(roomA.kind ~= lastKind or index == 0, "consecutive rooms repeated")
        lastKind = roomA.kind
        kinds[roomA.kind] = true
    end
end
local total, forms, combinations = 0, 0, 0
for _ in pairs(kinds) do total = total + 1 end
for _ in pairs(shapesSeen) do forms = forms + 1 end
for _ in pairs(combinedLayouts) do combinations = combinations + 1 end
assert(differences > 38 and threatDifferences > 6 and shapeDifferences > 35
    and darkCount >= 10 and total >= 11 and forms == 8 and combinations > 40,
    "seed did not vary the actual eight geometries and furniture combinations")
assert(shops == 1 and locks >= 7 and types.RUSH and types.BLIND and types.MOTH and types.ECHO,
    "a run must have one late shop, random locks and all four encounter types")
for seedIndex = 1, 40 do
    local trial = planRooms(seedIndex * 19093 + 319)
    local last, store, variety = nil, 0, {}
    for index = 0, 99 do
        local room = trial[index]
        if room.shop then
            store = store + 1
            assert(index > 50 and not room.locked and not room.threat and room.kind == "MARKET")
        end
        if room.threat then
            if last then assert(index - last >= 5,
                "cooldown broken for seed " .. seedIndex) end
            variety[room.threat] = true
            last = index
        end
    end
    assert(store == 1 and variety.ECHO and variety.BLIND and variety.RUSH and variety.MOTH,
        "seed " .. seedIndex .. " omitted the after-fifty shop or a monster type")
end
assert(a[0].kind ~= "HALL" or b[0].kind ~= "HALL" or a[0].shape ~= b[0].shape,
    "the starting lobby is always the same static room")
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
-- An AISLE is a real wall, not just a label. Follow a target around its
-- lateral doorway; the roaming enemy must NEVER cross x=6.2 at z7.
local first = state.rooms[0]
local originalShape = first.shape
first.shape = "AISLE"
for _, points in ipairs({{{0, 6.5}, {9, 6.5}}, {{9, 6.5}, {0, 6.5}}}) do
    local from, goal = points[1], points[2]
    local current = Vector3.new(from[1], 4.7, from[2])
    local destination = Vector3.new(goal[1], 4.7, goal[2])
    local crossed = false
    for _ = 1, 120 do
        local nextPosition = walkRoute(current, destination, 9, 0.1, 4.7)
        if (current.X < 6.2 and nextPosition.X >= 6.2)
            or (current.X > 6.2 and nextPosition.X <= 6.2) then
            crossed = true
            assert(nextPosition.Z > 8.35 and nextPosition.Z < 11.65,
                "a monster crossed THROUGH the aisle wall instead of the side opening")
        end
        current = nextPosition
    end
    assert(crossed and math.abs(current.X - goal[1]) < 1.5
        and math.abs(current.Z - goal[2]) < 1.5,
        "a real aisle left the player unreachable from the main passage")
end
first.shape = originalShape
observed.state = state
observed.award = award
observed.rollLoot = rollLoot
observed.maybeSpider = maybeSpider
observed.recordNoise = recordNoise
observed.damagePlayer = damagePlayer
observed.replayEcho = function(index) startEcho(state.rooms[index], session) end
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
        local leftHand = Instance.new("Part")
        leftHand.Name = "LeftHand"
        leftHand.Size = hand.Size
        leftHand.CFrame = root.CFrame * CFrame.new(-0.7, 1.1, 0)
        leftHand.Anchored = false
        leftHand.Parent = character
        local human = Instance.new("Humanoid")
        human.Name = "Humanoid"
        human.Health = 100
        human.Died = signal()
        human.Parent = character
        self.Character = character
        self.CharacterAdded:Fire(character)
        self.CharacterAppearanceLoaded:Fire(character)
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
assert(world:GetAttribute("CameraBuild") == "NativeFirstPerson-v10"
    and world:GetAttribute("GenerationBuild") == "SharedLootHeldItemsAudio-v10", "old place was loaded")
assert(services.Workspace.Gravity == 196.2, "zero gravity leaves the player floating")
assert(services.SoundService.AmbientReverb == Enum.ReverbType.Hallway,
    "hotel walls no longer have physical audio reverb")
assert(services.Lighting.Ambient.R > 0.13 and services.Lighting.Ambient.B > 0.17
    and services.Lighting.ExposureCompensation > 0
    and services.Lighting:FindFirstChild("CorridorHaze").Density < 0.25
    and services.Lighting:FindFirstChild("ColdShadowsWarmLights").Contrast >= 0.16,
    "v9 material contrast or legible blackout lighting was lost")
local spawn = world:FindFirstChild("CheckpointSpawn")
assert(spawn and spawn.Anchored and spawn.CanCollide and spawn.Transparency == 1
    and math.abs(spawn.Position.Y + spawn.Size.Y / 2 - NocturneLayout.EntranceY(0)) < 0.01
    and spawn.Position.Z == 10 and player.RespawnLocation == spawn,
    "native spawn pad must meet the walkable floor and own the avatar spawn")
local spawnedRoot = player.Character:FindFirstChild("HumanoidRootPart")
local spawnedHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
assert(player:GetAttribute("HasFlashlight") == false and player:GetAttribute("TorchOn") == false
    and player:GetAttribute("TorchCharge") == 0, "player started with a free flashlight")
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
local lockCount, turnCount, rushCount, blindCount, mothCount, echoCount = 0, 0, 0, 0, 0, 0
local shopCount, lootCount, keyRecoveryTested = 0, 0, false
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
local function inventoryOf(p)
    for i = #observed.events, 1, -1 do
        local ev = observed.events[i]
        if ev.event == "Inventory" and ev.player == p then return ev.a end
    end
end
local function walletValue(bag)
    return bag.coins + bag.notes * 10 + bag.gold * 60
end
-- Mock randomness exercises the server's sparse, seeded loot table across
-- many rolls without relying on the particular starting room of this run.
local empty, cash, equipmentDrops, torches, bars = 0, 0, 0, 0, 0
local rng = Random.new(88219)
for _ = 1, 10000 do
    local kind = observed.rollLoot(rng)
    if not kind then empty = empty + 1
    elseif kind == "COIN" or kind == "NOTE" or kind == "GOLD" then
        cash = cash + 1
        if kind == "GOLD" then bars = bars + 1 end
    else
        equipmentDrops = equipmentDrops + 1
        if kind == "FLASHLIGHT" then torches = torches + 1 end
    end
end
assert(empty > 5000 and cash > 2900 and cash < 3850
    and equipmentDrops > 950 and equipmentDrops < 1750
    and torches > 40 and torches < 210 and bars < 180,
    "drawer loot is no longer sparse or flashlight/gold are too common")
-- One copy of each different type is allowed; repeat rewards are refused by
-- the server, and consumption makes that type obtainable again.
local collector = addPlayer("SingleCopyCollector")
assert(inventoryOf(collector).items.PILL == 0 and inventoryOf(collector).selected == 1)
assert(observed.award(collector, "PILL", 1) and inventoryOf(collector).selected == 2)
local pill = collector.Character:FindFirstChild("HeldItem")
local pillGrip = pill and pill:FindFirstChild("Item grip in Roblox hand", true)
assert(pill and pill:GetAttribute("ItemKind") == "PILL"
    and pill:FindFirstChild("Amber apothecary vial", true)
    and pill:FindFirstChild("Hand-printed medicine label", true)
    and pillGrip and pillGrip.Part0 == collector.Character:FindFirstChild("RightHand")
    and not pillGrip.Part1.Anchored and not pillGrip.Part1.CanCollide,
    "selected medicine is not modelled and welded to the actual hand")
pill:Destroy()
collector.CharacterAppearanceLoaded:Fire(collector.Character)
pill = collector.Character:FindFirstChild("HeldItem")
assert(pill and pill:GetAttribute("ItemKind") == "PILL",
    "late native hand/appearance failed to reattach the selected item")
assert(observed.award(collector, "MEDKIT", 1)
    and not observed.award(collector, "PILL", 1)
    and inventoryOf(collector).items.PILL == 1
    and inventoryOf(collector).items.MEDKIT == 1,
    "duplicate equipment stacked instead of allowing only different item types")
remote.OnServerEvent:Fire(collector, "Select", 4)
assert(inventoryOf(collector).selected == 2, "empty item slot can be selected")
remote.OnServerEvent:Fire(collector, "Use", "PILL")
assert(inventoryOf(collector).items.PILL == 0 and inventoryOf(collector).selected == 5
    and not pill.Parent and collector.Character:FindFirstChild("HeldItem")
        :FindFirstChild("Ivory enamel cross", true)
    and countEvent("ItemUsed", "PILL") >= 1,
    "pill use did not replace its held model, emit feedback and select the next item")
assert(observed.award(collector, "PILL", 1)
    and inventoryOf(collector).items.PILL == 1,
    "consumed item type cannot be picked up again")
removePlayer(collector)
local torchOwner = addPlayer("HandTorchActuallyWorks")
assert(observed.award(torchOwner, "FLASHLIGHT", 1))
local handheld = torchOwner.Character:FindFirstChild("HeldItem")
local lens = handheld and handheld:FindFirstChild("Torch lens", true)
local light = lens and lens:FindFirstChild("Selected torch beam")
assert(handheld and handheld:GetAttribute("ItemKind") == "FLASHLIGHT"
    and handheld:FindFirstChild("Machined torch barrel", true)
    and handheld:FindFirstChild("Crosshatched grip ring", true)
    and handheld:FindFirstChild("Item grip in Roblox hand", true).Part0
        == torchOwner.Character:FindFirstChild("RightHand")
    and light and not light.Enabled and torchOwner:GetAttribute("EquippedItem") == "FLASHLIGHT",
    "the physical, detailed flashlight is not in the player's real hand")
remote.OnServerEvent:Fire(torchOwner, "Torch", true)
assert(torchOwner:GetAttribute("TorchOn") and light.Enabled,
    "switching the actual selected hand torch on did not create a visible beam")
assert(observed.award(torchOwner, "PILL", 1))
remote.OnServerEvent:Fire(torchOwner, "Select", 2)
assert(not handheld.Parent and not torchOwner:GetAttribute("TorchOn")
    and torchOwner.Character:FindFirstChild("HeldItem"):GetAttribute("ItemKind") == "PILL",
    "switching items left the flashlight visibly lit in the wrong hand")
remote.OnServerEvent:Fire(torchOwner, "Use", "PILL")
assert(torchOwner.Character:FindFirstChild("HeldItem"):GetAttribute("ItemKind") == "FLASHLIGHT"
    and not torchOwner:GetAttribute("TorchOn"), "consumed item did not re-equip the torch")
removePlayer(torchOwner)
-- Even forced successful spider rolls must leave a 12-room gap per player.
local startled = addPlayer("RareSpiderCooldown")
local spiderPos = CFrame.new(0, 4, 20 * L + 14)
local beforeSpider = countEvent("Spider")
observed.maybeSpider(startled, 20, true, spiderPos)
observed.maybeSpider(startled, 20, true, spiderPos)
observed.maybeSpider(startled, 31, true, spiderPos)
assert(countEvent("Spider") == beforeSpider + 1, "spiders repeated before the room cooldown")
observed.maybeSpider(startled, 32, true, spiderPos)
assert(countEvent("Spider") == beforeSpider + 2, "rare spider could never reappear later")
removePlayer(startled)
-- The crouch flag is server-owned and caps WalkSpeed even when Sprint is sent.
remote.OnServerEvent:Fire(player, "Crouch", true)
remote.OnServerEvent:Fire(player, "Sprint", true)
services.RunService.Heartbeat:Fire(0.2)
assert(player:GetAttribute("Crouching") and player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 7)
remote.OnServerEvent:Fire(player, "Crouch", false)
services.RunService.Heartbeat:Fire(0.2)
assert(not player:GetAttribute("Crouching") and player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 12)
remote.OnServerEvent:Fire(player, "Torch", true)
assert(not player:GetAttribute("TorchOn"), "server accepted a free/exploited flashlight")
for index = 0, 99 do
    local room = roomAt(index)
    assert(room, "missing generated room " .. index)
    assert(room:GetAttribute("EntryY") == NocturneLayout.EntranceY(index))
    assert(room:GetAttribute("ExitY") == NocturneLayout.ExitY(index))
    local air = room:FindFirstChild("Low draught in the masonry", true)
    assert(air and air.IsPlaying and air.Looped
        and air:FindFirstChild("Short corridor reflection")
        and air:FindFirstChild("Hotel masonry tail")
        and room:FindFirstChild("Old door hinges", true),
        "generated room has no echoing ambient bed or physical door sound")
    variants[room:GetAttribute("Variant")] = true
    local shape, dark = room:GetAttribute("Shape"), room:GetAttribute("Dark")
    physicalShapes[shape] = true
    if dark then darkCount = darkCount + 1 end
    structures[index] = room:GetAttribute("Variant") .. ":" .. tostring(shape)
        .. ":" .. tostring(dark)
    signatures[index] = structures[index] .. ":" .. tostring(room:GetAttribute("DecorSeed"))
    local wardrobes, treads, solidFlanks, partitions, arches, drawers, walls = 0, 0, 0, 0, 0, 0, 0
    local crossWalls, columns, vaults, lamps = 0, 0, 0, 0
    local aisleScreens, rotunda, nave, crypt, guides, mosaic = 0, 0, 0, 0, 0, 0
    local inlays, rosettes, shades, dust, borders = 0, 0, 0, 0, 0
    -- Collision belongs to the real structural parts, not to the decorative
    -- non-colliding carpet. Test EACH streamed room so a missing floor in a
    -- later storey cannot pass a foyer-only check.
    local loadBearing = {
        ["Continuous wooden subfloor"] = true, ["Load-bearing corridor wall"] = true,
        ["Solid enclosed stair flank"] = true, ["Lower stair landing"] = true,
        ["Upper stair landing"] = true, ["Solid stair tread"] = true,
        ["Doorway threshold"] = true, ["Vestibule cross-wall"] = true,
        ["Freestanding marble arcade column"] = true,
        ["Side aisle masonry screen"] = true, ["Rotunda monolithic column"] = true,
        ["Nave transept masonry"] = true, ["Crypt sealed plinth"] = true,
        ["Solid wall behind the final light"] = true,
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
        if child.Name == "Side aisle masonry screen" then
            aisleScreens = aisleScreens + 1
            assert(math.abs(child.Position.X) - child.Size.X / 2 > 5.9,
                "an aisle wall blocks the route down the middle")
        end
        if child.Name == "Rotunda monolithic column" then
            rotunda = rotunda + 1
            assert(math.abs(child.Position.X) >= 8.9, "rotunda obstructs the door")
        end
        if child.Name == "Nave transept masonry" then
            nave = nave + 1
            assert(math.abs(child.Position.X) - child.Size.X / 2 >= 6.79,
                "a transept seals its central arch")
        end
        if child.Name == "Crypt sealed plinth" then crypt = crypt + 1 end
        if child.Name == "Rotunda circular floor mosaic" then
            mosaic = mosaic + 1
            assert(not child.CanCollide, "the mosaic raised an impassable step")
        end
        if child._class == "PointLight" and child.Name == "Blackout floor glow" then
            guides = guides + 1
            assert(child.Enabled and child.Brightness > 0.25 and child.Brightness < 0.55
                and child.Range >= 19 and child.Parent.Name == "Emergency glass"
                and not child.Parent.CanCollide,
                "a dark room has no gentle PHYSICAL light at the floor")
        end
        if child._class == "PointLight" and child.Parent.Name == "Warm filament" then
            lamps = lamps + 1
            assert(child.Enabled == (not dark), "dark rooms must have OFF physical lamps")
            assert(child.Parent.Material == (dark and Enum.Material.Glass or Enum.Material.Neon),
                "a Neon GUI-like bulb is shining in an unlit room")
        end
        if child._class == "ParticleEmitter" and child.Name == "Dust in the lamplight" then
            dust = dust + 1
            assert(child.Parent.Name == "Warm filament" and child.Rate < 0.2
                and child.Enabled == (not dark), "dust should follow physical lights, not obscure rooms")
        end
        if child.Name == "Smoked glass lamp shade" then
            shades = shades + 1
            assert(not child.CanCollide and child.CanQuery == false and not child.CastShadow,
                "lamp detail steals light or blocks the native avatar")
        end
        if child.Name == "Inlaid floorboard joint" then
            inlays = inlays + 1
            assert(not child.CanCollide and child.CanQuery == false,
                "decorative floor joint adds a new step or blocks interaction")
        end
        if child.Name == "Pressed metal ceiling rosette" then
            rosettes = rosettes + 1
            assert(not child.CanCollide and child.CanQuery == false)
        end
        if child.Name == "Engraved panel edge" then
            borders = borders + 1
            assert(not child.CanCollide and child.CanQuery == false)
        end
        if child.Name == "OpenDrawer" then drawers = drawers + 1 end
        if loadBearing[child.Name] then
            assert(child.Anchored == true and child.CanCollide == true,
                "non-colliding " .. child.Name .. " in room " .. index)
        end
    end
    assert(wardrobes == 2 and lamps > 0 and shades == lamps and dust == lamps,
        "room is missing ornate, gently lit physical lamps at " .. index)
    assert(inlays == (NocturneLayout.IsStair(index) and 0 or 6)
        and rosettes == (NocturneLayout.IsStair(index) and 0 or 1)
        and borders == (NocturneLayout.IsStair(index) and 0 or 16),
        "non-colliding floor, ceiling or wall material details disappeared")
    assert(crossWalls == (shape == "VESTIBULE" and 4 or 0)
        and columns == (shape == "ARCADE" and 4 or 0)
        and vaults == (shape == "COFFERED" and 4 or 0)
        and aisleScreens == (shape == "AISLE" and 8 or 0)
        and rotunda == (shape == "ROTUNDA" and 4 or 0)
        and mosaic == (shape == "ROTUNDA" and 1 or 0)
        and nave == (shape == "NAVE" and 4 or 0)
        and crypt == (shape == "CRYPT" and 2 or 0),
        "shape label did not construct eight DISTINCT, connected interiors")
    assert(guides == (dark and not NocturneLayout.IsStair(index) and 3 or 0),
        "dark interiors must stay navigable with or WITHOUT the torch")
    if room:GetAttribute("Shop") then
        shopCount = shopCount + 1
        assert(index > 50 and room:FindFirstChild("After-fifty apothecary")
            and not room:GetAttribute("Locked") and room:GetAttribute("Threat") == "NONE",
            "shop is missing or blocks a threat/lock room")
        for _, id in ipairs({"FLASHLIGHT", "PILL", "CRUCIFIX", "BANDAGE", "MEDKIT"}) do
            assert(room:FindFirstChild("Buy_" .. id, true), "shop missing " .. id)
        end
    end
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
            if index == 0 and name == "Wardrobe_A" then
                local victim = addPlayer("StayedHiddenTooLong")
                rootOf(victim).CFrame = CFrame.new(hidePrompt.Parent.Position)
                hidePrompt.Triggered:Fire(victim)
                hidePrompt.Triggered:Fire(victim)
                assert(victim:GetAttribute("Hidden"), "second teammate cannot use the wardrobe")
                for tick = 1, 37 do
                    services.RunService.Heartbeat:Fire(0.4)
                    if tick == 25 then assert(victim:GetAttribute("ClosetPressure") > 0,
                        "a prolonged wardrobe stay never blurred the view") end
                end
                assert(not victim:GetAttribute("Hidden") and healthOf(victim) == 81
                    and victim:GetAttribute("ClosetPressure") == 0,
                    "hiding forever did not cloud vision, eject and inflict lasting damage")
                rootOf(victim).CFrame = CFrame.new(hidePrompt.Parent.Position)
                hidePrompt.Triggered:Fire(victim)
                hidePrompt.Triggered:Fire(victim)
                assert(not victim:GetAttribute("Hidden"), "exhausted player can instantly rehide")
                removePlayer(victim)
            end
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
        if not keyRecoveryTested then
            keyRecoveryTested = true
            -- Dying with a key leaves it in the revealed drawer for a teammate.
            local keyPrompt = dresser:FindFirstChild("TakeKey", true)
            player.Character:FindFirstChildOfClass("Humanoid").Died:Fire()
            assert(not player:GetAttribute("HeldKey") and not player.Character:FindFirstChild("HeldKey")
                and keyPrompt.Enabled and not room:GetAttribute("KeyFound")
                and room:GetAttribute("Locked"), "death permanently lost the only key")
            local teammate = addPlayer("KeyCarrierWhoDisconnected")
            assert(observed.award(teammate, "PILL", 1))
            rootOf(teammate).CFrame = CFrame.new(keyPrompt.Parent.Position)
            keyPrompt.Triggered:Fire(teammate)
            local otherItem = teammate.Character:FindFirstChild("HeldItem")
            local leftGrip = otherItem and otherItem:FindFirstChild("Item grip in Roblox hand", true)
            assert(teammate:GetAttribute("HeldKey") == index + 1 and not keyPrompt.Enabled
                and otherItem:GetAttribute("GripHand") == "Left"
                and leftGrip.Part0 == teammate.Character:FindFirstChild("LeftHand")
                and teammate.Character:FindFirstChild("HeldKey"),
                "key must remain in the right hand while a selected item uses the real left hand")
            removePlayer(teammate)
            assert(keyPrompt.Enabled and not room:GetAttribute("KeyFound"),
                "disconnect permanently lost the team's only key")
            player:LoadCharacter()
            rootOf(player).CFrame = CFrame.new(keyPrompt.Parent.Position)
            keyPrompt.Triggered:Fire(player)
            assert(player:GetAttribute("HeldKey") == index + 1 and room:GetAttribute("KeyFound"),
                "a returned key cannot be recovered")
        end
        rootOf(player).CFrame = CFrame.new(0, NocturneLayout.ExitY(index) + 3, (index + 1) * L - 5)
    end
    local dresser = room:FindFirstChild("Three-drawer dresser")
    if dresser then
        for slot = 1, 3 do
            local drawer = dresser:FindFirstChild("Drawer_" .. slot)
            local open = drawer:FindFirstChild("OpenDrawer", true)
            if open.Enabled then
                rootOf(player).CFrame = CFrame.new(open.Parent.Position)
                open.Triggered:Fire(player)
            end
            local prize = drawer:FindFirstChild("TakeLoot", true)
            if prize and prize.Enabled then
                lootCount = lootCount + 1
                local item = prize.Parent.Parent
                local id = item:GetAttribute("LootKind")
                local position = prize.Parent.Position
                local before = inventoryOf(player)
                rootOf(player).CFrame = CFrame.new(position)
                if not observed.duplicateDrawerTested and id == "PILL" then
                    observed.duplicateDrawerTested = true
                    local teammate = addPlayer("FullInventoryCannotReserveLoot")
                    rootOf(teammate).CFrame = CFrame.new(position)
                    assert(observed.award(teammate, "PILL", 1))
                    local owned = inventoryOf(teammate)
                    prize.Triggered:Fire(teammate)
                    assert(inventoryOf(teammate) == owned and item.Parent == drawer
                        and prize.Enabled and not drawer:GetAttribute("LootClaimed"),
                        "failed duplicate pickup removed the team's physical prize")
                    remote.OnServerEvent:Fire(teammate, "Use", "PILL")
                    assert(inventoryOf(teammate).items.PILL == 0)
                    prize.Triggered:Fire(teammate)
                    assert(inventoryOf(teammate).items.PILL == 1 and not item.Parent
                        and not prize.Enabled and drawer:GetAttribute("LootClaimed"),
                        "first eligible teammate did not consume the shared cache")
                    prize.Triggered:Fire(player)
                    assert(inventoryOf(player) == before, "other player farmed consumed loot")
                    removePlayer(teammate)
                else
                    local teammate
                    if not observed.lootTeamTested and id == "COIN" then
                        observed.lootTeamTested = true
                        teammate = addPlayer("LateToSharedWallet")
                        rootOf(teammate).CFrame = CFrame.new(position)
                    end
                    local priorValue = walletValue(before)
                    prize.Triggered:Fire(player)
                    local after = inventoryOf(player)
                    local duplicate = before.items[id] and before.items[id] > 0
                    if duplicate then
                        assert(after == before and item.Parent == drawer and prize.Enabled
                            and not drawer:GetAttribute("LootClaimed"),
                            "full personal slot destroyed the prize before anybody could take it")
                    else
                        assert(item.Parent == nil and not prize.Enabled
                            and drawer:GetAttribute("LootClaimed") and not drawer:FindFirstChild("Loot_" .. id),
                            "taking a prize did not remove its visible model for everyone")
                        if id == "COIN" or id == "NOTE" or id == "GOLD" then
                            assert(walletValue(after) > priorValue, "cash went into the wrong wallet")
                        else
                            assert(after.items[id] == 1, "picked item was not equipped")
                        end
                        prize.Triggered:Fire(player)
                        assert(inventoryOf(player) == after, "same player farmed a cleared drawer")
                    end
                    if teammate then
                        prize.Triggered:Fire(teammate)
                        assert(walletValue(inventoryOf(teammate)) == 0
                            and inventoryOf(player) == after and item.Parent == nil,
                            "two clients both claimed one physical cache")
                        removePlayer(teammate)
                    end
                end
            end
        end
    end
    if room:GetAttribute("Shop") then
        assert(walletValue(inventoryOf(player)) >= 100, "drawer economy cannot afford the late shop")
        local offer = room:FindFirstChild("Buy_FLASHLIGHT", true)
        local previous = inventoryOf(player)
        rootOf(player).CFrame = CFrame.new(11, NocturneLayout.EntranceY(index) + 3, index * L + 6)
        offer.Triggered:Fire(player)
        assert(inventoryOf(player) == previous, "bought from outside the shop")
        -- Finance repeated-purchase assertions AFTER proving the natural run
        -- can afford a visit; this does not alter the seeded loot distribution.
        observed.award(player, "GOLD", 2)
        if previous.items.FLASHLIGHT > 0 then
            remote.OnServerEvent:Fire(player, "Select", 1)
            remote.OnServerEvent:Fire(player, "Torch", true)
            for _ = 1, 100 do services.RunService.Heartbeat:Fire(0.4) end
            local heldAfterDrain = player.Character:FindFirstChild("HeldItem")
            assert(not player:GetAttribute("HasFlashlight") and not player:GetAttribute("TorchOn")
                and player:GetAttribute("TorchCharge") == 0
                and (not heldAfterDrain or heldAfterDrain:GetAttribute("ItemKind") ~= "FLASHLIGHT"),
                "dead battery did not remove the held flashlight or kill the beam")
        end
        rootOf(player).CFrame = CFrame.new(offer.Parent.Position)
        local cash = walletValue(inventoryOf(player))
        offer.Triggered:Fire(player)
        assert(player:GetAttribute("HasFlashlight") and player:GetAttribute("TorchCharge") == 100
            and walletValue(inventoryOf(player)) == cash - 25,
            "late shop did not sell a fully charged flashlight for wallet currency")
        local bought = inventoryOf(player)
        offer.Triggered:Fire(player)
        assert(inventoryOf(player) == bought,
            "a second flashlight stacked in the bag or charged the wallet")
        remote.OnServerEvent:Fire(player, "Select", 1)
        remote.OnServerEvent:Fire(player, "Torch", true)
        for _ = 1, 100 do services.RunService.Heartbeat:Fire(0.4) end
        local discharged = player.Character:FindFirstChild("HeldItem")
        assert(not player:GetAttribute("HasFlashlight") and not player:GetAttribute("TorchOn")
            and player:GetAttribute("TorchCharge") == 0
            and (not discharged or discharged:GetAttribute("ItemKind") ~= "FLASHLIGHT"))
        rootOf(player).CFrame = CFrame.new(offer.Parent.Position)
        local rechargeCash = walletValue(inventoryOf(player))
        offer.Triggered:Fire(player)
        assert(player:GetAttribute("HasFlashlight") and player:GetAttribute("TorchCharge") == 100
            and walletValue(inventoryOf(player)) == rechargeCash - 25,
            "spent flashlight cannot be purchased again")
        local medkit = room:FindFirstChild("Buy_MEDKIT", true)
        rootOf(player).CFrame = CFrame.new(medkit.Parent.Position)
        local medical = inventoryOf(player)
        medkit.Triggered:Fire(player)
        if medical.items.MEDKIT == 1 then
            assert(inventoryOf(player) == medical, "duplicate medkit was purchased despite a full slot")
        else
            assert(inventoryOf(player).items.MEDKIT == 1
                and walletValue(inventoryOf(player)) == walletValue(medical) - 32,
                "shop medical purchase failed or invented change")
        end
        local heldMedical = inventoryOf(player)
        medkit.Triggered:Fire(player)
        assert(inventoryOf(player) == heldMedical, "shop charged for a duplicate medkit")
        observed.damagePlayer(player, 40)
        remote.OnServerEvent:Fire(player, "Select", 5)
        remote.OnServerEvent:Fire(player, "Use", "MEDKIT")
        assert(healthOf(player) == 100 and inventoryOf(player).items.MEDKIT == 0,
            "medkit did not disappear after use")
        local replacementCash = walletValue(inventoryOf(player))
        medkit.Triggered:Fire(player)
        assert(inventoryOf(player).items.MEDKIT == 1
            and walletValue(inventoryOf(player)) == replacementCash - 32,
            "shop refused a medkit after the old one was used")
    end
    rootOf(player).CFrame = CFrame.new(0, NocturneLayout.ExitY(index) + 3, (index + 1) * L - 5)
    local behindDoor = roomAt(index + 1)
    local dueThreat = behindDoor and behindDoor:GetAttribute("Threat")
    if dueThreat == "BLIND" then
        assert(not observed.state.blind or observed.state.blind.index ~= index + 1,
            "Guest spawned before its room was opened")
    elseif dueThreat == "MOTH" then
        assert(not observed.state.moth or observed.state.moth.index ~= index + 1,
            "swarm spawned before its room was opened")
    end
    prompt.Triggered:Fire(player)
    assert(world:GetAttribute("DoorsOpened") == index + 1, "player trapped by door " .. index + 1)
    if dueThreat == "BLIND" or dueThreat == "MOTH" then
        local guard = dueThreat == "BLIND" and observed.state.blind or observed.state.moth
        local name = dueThreat == "BLIND" and "TheBlindGuest" or "ThePaleMoth"
        assert(guard and guard.index == index + 1 and world:FindFirstChild(name) == guard.entity
            and countEvent("MonsterSpawn", dueThreat) >= 1,
            "door finished opening before its resident appeared")
    end
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
        if room:GetAttribute("Shop") then
            local lagger = addPlayer("CoopLagger")
            local lead = rootOf(player)
            lead.CFrame = CFrame.new(0, NocturneLayout.WalkwayY(index + 1, 30) + 3,
                (index + 1) * L + 30)
            local function behind(rooms)
                local z = lead.Position.Z - rooms * L
                local j = NocturneLayout.RoomIndexAt(z)
                rootOf(lagger).CFrame = CFrame.new(0,
                    NocturneLayout.WalkwayY(j, z - j * L) + 3, z)
            end
            behind(3)
            services.RunService.Heartbeat:Fire(0.2)
            assert(healthOf(lagger) == 100 and lagger.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 15,
                "first catch-up stage is not a SMALL boost")
            behind(6)
            services.RunService.Heartbeat:Fire(0.2)
            assert(lagger.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 19,
                "second catch-up stage did not boost the straggler")
            behind(7.3)
            services.RunService.Heartbeat:Fire(0.2)
            assert(healthOf(lagger) == 64 and math.abs(rootOf(lagger).Position.Z - lead.Position.Z) < L,
                "very distant teammate was not reunited with 36 non-regenerating damage")
            lagger.Character:FindFirstChildOfClass("Humanoid").Health = 98 -- emulate Roblox default Health script
            services.RunService.Heartbeat:Fire(0.2)
            assert(healthOf(lagger) == 64, "damage healed by itself after teleport")
            observed.award(lagger, "MEDKIT", 1)
            remote.OnServerEvent:Fire(lagger, "Select", 5)
            remote.OnServerEvent:Fire(lagger, "Use", "MEDKIT")
            assert(healthOf(lagger) == 100 and inventoryOf(lagger).items.MEDKIT == 0,
                "medical kit did not deliberately heal and disappear")
            observed.damagePlayer(lagger, 18)
            observed.award(lagger, "BANDAGE", 1)
            remote.OnServerEvent:Fire(lagger, "Select", 4)
            remote.OnServerEvent:Fire(lagger, "Use", "BANDAGE")
            assert(healthOf(lagger) == 100 and inventoryOf(lagger).items.BANDAGE == 0,
                "bandage did not heal 25 points")
            observed.award(lagger, "PILL", 1)
            remote.OnServerEvent:Fire(lagger, "Select", 2)
            remote.OnServerEvent:Fire(lagger, "Use", "PILL")
            services.RunService.Heartbeat:Fire(0.2)
            assert(lagger.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 21,
                "pill did not briefly make the player faster")
            for _ = 1, 25 do services.RunService.Heartbeat:Fire(0.4) end
            assert(lagger.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 12,
                "speed pill never expired")
            removePlayer(lagger)
        end
    else
        local exit = world:FindFirstChild("Exit")
        assert(exit, "door 100 has no finale")
        local wall = exit:FindFirstChild("Solid wall behind the final light")
        local floor = exit:FindFirstChild("Last floor")
        local witness = exit:FindFirstChild("TheLastWitness")
        assert(wall and wall.Anchored and wall.CanCollide and floor and floor.CanCollide
            and witness and witness.PrimaryPart and witness:FindFirstChild("The face behind the dawn", true),
            "final chamber has an open edge or no physical apparition")
        local rings = 0
        for _, piece in ipairs(witness:GetDescendants()) do
            if piece.Name == "Chalk orbital ring" then rings = rings + 1 end
        end
        assert(rings == 28, "last encounter has no recognizable face")
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(100) + 3, 100 * L + 25)
        local trigger = exit:FindFirstChild("End of the nightmare")
        trigger.Touched:Fire(root)
        assert(player:GetAttribute("Finished") and healthOf(player) == 100
            and player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == 0
            and countEvent("Finale") == 1 and countEvent("Victory") == 0,
            "last door skipped the model-driven finale before the victory card")
        local lastEvent = observed.events[#observed.events]
        assert(lastEvent.event == "Finale" and lastEvent.a == witness,
            "finale sent the wrong model to the client")
        trigger.Touched:Fire(root)
        assert(countEvent("Finale") == 1, "touching the end twice replayed the scare")
        assert(healthOf(player) == 100, "completed player died during the victory scene")
    end
    if room:GetAttribute("Threat") == "RUSH" then rushCount = rushCount + 1 end
    if room:GetAttribute("Threat") == "BLIND" then blindCount = blindCount + 1 end
    if room:GetAttribute("Threat") == "MOTH" then mothCount = mothCount + 1 end
    if room:GetAttribute("Threat") == "ECHO" then echoCount = echoCount + 1 end
    local kind = room:GetAttribute("Threat")
    if kind == "RUSH" and not observed.rushTested and index < 98 then
        observed.rushTested = true
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        assert(#deferred == 1, "seeded Rush did not schedule its physical warning")
        local closet = room:FindFirstChild("Wardrobe_A"):FindFirstChild("HideInside", true)
        root.CFrame = CFrame.new(closet.Parent.Position)
        closet.Triggered:Fire(player)
        closet.Triggered:Fire(player)
        local runner = addPlayer("RunnerPastOneDoor")
        rootOf(runner).CFrame = CFrame.new(0, NocturneLayout.WalkwayY(index + 1, 19) + 3,
            (index + 1) * L + 19)
        local flickers = observed.sconceChanges
        local soundCount = #observed.sounds
        observed.warningCheck = function()
            assert(#observed.sounds == soundCount and countEvent("MonsterSpawn", "RUSH") == 0,
                "the light flicker made a noise BEFORE the monster itself appeared")
        end
        drainTasks()
        observed.warningCheck = nil
        assert(countEvent("MonsterSpawn", "RUSH") >= 1
            and world:FindFirstChild("TheRush") == nil,
            "arrival was silent or a Rush stayed after the pass")
        assert(healthOf(player) == 100 and player:GetAttribute("Hidden"),
            "a real wardrobe did not shield the runner")
        assert(healthOf(runner) == 0 and observed.sconceChanges > flickers + 12,
            "Rush stopped at the first door or did not blink real lamps")
        local far = 0
        for _, pos in ipairs(observed.monsterPositions) do
            if pos.name == "TheRush" then far = math.max(far, pos.z) end
        end
        assert(far > (index + 1) * L + 20, "Rush never ran through the NEXT room")
        remote.OnServerEvent:Fire(player, "Exit")
        removePlayer(runner)
    elseif kind == "BLIND" and not observed.blindTested then
        observed.blindTested = true
        local root = rootOf(player)
        local waiting = observed.state.blind
        assert(waiting and waiting.index == index and waiting.entity and waiting.entity.Parent
            and world:FindFirstChild("TheBlindGuest") == waiting.entity
            and countEvent("MonsterSpawn", "BLIND") >= 1,
            "opening the door did not reveal the Guest BEFORE crossing its threshold")
        local arrivals = countEvent("MonsterSpawn", "BLIND")
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        assert(observed.state.blind == waiting and countEvent("MonsterSpawn", "BLIND") == arrivals,
            "entry sensor spawned a second delayed Guest")
        waiting.lastSound = nil
        waiting.lastSerial = observed.state.noiseSerial -- discard sounds of earlier test drawer interactions
        root.CFrame = CFrame.new(-10.5, NocturneLayout.EntranceY(index) + 3, index * L + 5)
        local ticks = 0
        observed.onWait = function()
            ticks = ticks + 1
            local blind = observed.state.blind
            if ticks == 5 then
                assert(blind and blind.entity and blind.entity.Parent and not blind.lastSound,
                    "standing still is being treated as a sound or the Guest vanished")
                observed.recordNoise(Vector3.new(0, NocturneLayout.EntranceY(index) + 3,
                    index * L + 8), 140)
            elseif ticks == 6 then
                assert(blind.lastSound and blind.lastSound.Z == index * L + 8,
                    "Blind Guest failed to follow the FIRST heard location")
            elseif ticks == 10 then
                observed.recordNoise(Vector3.new(0, NocturneLayout.EntranceY(index) + 3,
                    index * L + 37), 140)
            elseif ticks == 11 then
                assert(blind.lastSound and blind.lastSound.Z == index * L + 37,
                    "a NEW sound did not immediately redirect the Blind Guest")
            elseif ticks == 12 then
                local old = index - 1
                root.CFrame = CFrame.new(-10.5, NocturneLayout.WalkwayY(old, 30) + 3,
                    old * L + 30)
            elseif ticks == 21 then
                root.CFrame = CFrame.new(-10.5, NocturneLayout.EntranceY(index) + 3,
                    index * L + 5)
            elseif ticks == 22 then
                assert(blind.entity.Parent and room.Parent and observed.state.blind == blind,
                    "Blind Guest despawned because the player left and re-entered")
            elseif ticks == 42 then
                blind.banished = true -- stop the offline patrol, not the real-game lifecycle
            end
        end
        drainTasks()
        observed.onWait = nil
        assert(ticks >= 42 and healthOf(player) == 100,
            "still and quiet player was chased by the allegedly blind creature")
    elseif kind == "MOTH" and not observed.mothTested then
        observed.mothTested = true
        local root = rootOf(player)
        local waiting = observed.state.moth
        assert(waiting and waiting.index == index and waiting.entity and waiting.entity.Parent
            and world:FindFirstChild("ThePaleMoth") == waiting.entity
            and countEvent("MonsterSpawn", "MOTH") >= 1,
            "the swarm did not exist on the OTHER side when the door opened")
        remote.OnServerEvent:Fire(player, "Torch", false)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        assert(observed.state.moth == waiting, "entering spawned a replacement swarm")
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 30)
        local bright = addPlayer("LongExposureToTheMoths")
        observed.award(bright, "FLASHLIGHT", 1)
        remote.OnServerEvent:Fire(bright, "Select", 1)
        remote.OnServerEvent:Fire(bright, "Torch", true)
        rootOf(bright).CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3,
            index * L + 30)
        observed.graceElapsed = 0
        observed.graceCheck = function()
            assert(world:FindFirstChild("ThePaleMoth") and healthOf(bright) == 100,
                "tiny moths killed during the four-second visual cue")
        end
        observed.onWait = function()
            if healthOf(bright) < 100 and not observed.firstBite then
                observed.firstBite = healthOf(bright)
                assert(observed.firstBite > 0 and observed.firstBite >= 93,
                    "one moth contact killed the player instead of gradual bites")
            end
        end
        drainTasks()
        observed.graceCheck, observed.onWait = nil, nil
        assert(observed.graceElapsed >= 4 and observed.firstBite
            and healthOf(bright) == 0 and healthOf(player) == 100,
            "the swarm did not pursue a lit torch or killed a dark player")
        removePlayer(bright)
    elseif kind == "BLIND" then
        local guard = observed.state.blind
        if guard then guard.banished = true; drainTasks() end -- fast-forward later mock patrols
    elseif kind == "MOTH" then
        local guard = observed.state.moth
        if guard then guard.banished = true; drainTasks() end
    elseif kind == "ECHO" and not observed.echoTested and index < 98 then
        observed.echoTested = true
        local root = rootOf(player)
        root.CFrame = CFrame.new(0, NocturneLayout.EntranceY(index) + 3, index * L + 9)
        room:FindFirstChild("Room entry sensor").Touched:Fire(root)
        root.CFrame = CFrame.new(0, NocturneLayout.WalkwayY(index + 1, 10) + 3,
            (index + 1) * L + 10)
        drainTasks()
        local reversals, last, sign = 0, nil, nil
        for _, pos in ipairs(observed.monsterPositions) do
            if pos.name == "TheEcho" then
                if last then
                    local delta = pos.z - last
                    if math.abs(delta) > 0.5 then
                        local nextSign = delta > 0 and 1 or -1
                        if sign and sign ~= nextSign then reversals = reversals + 1 end
                        sign = nextSign
                    end
                end
                last = pos.z
            end
        end
        assert(reversals >= 4 and healthOf(player) == 100,
            "Echo did not make FIVE alternating physical passes")
        local defender = addPlayer("CrucifixStopsContact")
        observed.award(defender, "CRUCIFIX", 1)
        remote.OnServerEvent:Fire(defender, "Select", 3)
        rootOf(defender).CFrame = CFrame.new(0, NocturneLayout.WalkwayY(index - 1, 20) + 3,
            (index - 1) * L + 20)
        observed.replayEcho(index)
        assert(healthOf(defender) == 100 and inventoryOf(defender).items.CRUCIFIX == 0,
            "equipped cross did not consume and sink the touching monster")
        removePlayer(defender)
    end

end
assert(lockCount >= 7 and turnCount == 10 and shopCount == 1
    and lootCount > 65 and lootCount < 155
    and observed.lootTeamTested and observed.duplicateDrawerTested and keyRecoveryTested
    and countEvent("Spider") >= 2 and countEvent("Spider") < 12,
    "sparse seeded loot, rare spiders, shop or key recovery did not survive")
assert(darkCount >= 10 and physicalShapes.ARCADE and physicalShapes.COFFERED
    and physicalShapes.VESTIBULE and physicalShapes.OPEN and physicalShapes.AISLE
    and physicalShapes.ROTUNDA and physicalShapes.NAVE and physicalShapes.CRYPT,
    "new runs need ALL eight tangible room plans and readable blackouts")
assert(rushCount >= 1 and blindCount >= 1 and mothCount >= 1 and echoCount >= 1
    and observed.rushTested and observed.blindTested and observed.mothTested and observed.echoTested,
    "seeded encounter bag skipped one of the four physical hazards")
local kinds = 0
for _ in pairs(variants) do kinds = kinds + 1 end
assert(kinds >= 11, "room interiors do not vary")
local scareEvents = 0
for _, ev in ipairs(observed.events) do
    if ev.event == "Jumpscare" then
        scareEvents = scareEvents + 1
        local name = ev.a == "RUSH" and "TheRush" or ev.a == "BLIND" and "TheBlindGuest"
            or ev.a == "MOTH" and "ThePaleMoth" or ev.a == "ECHO" and "TheEcho"
        assert(name and ev.b and ev.b.Name == name and ev.b:GetAttribute("RecentKill"),
            "death did not send the REAL attacking creature for the close-up")
    end
end
assert(scareEvents >= 2, "threats no longer trigger their own death scenes")
local rushLook = observed.monsterLooks.TheRush
local blindLook = observed.monsterLooks.TheBlindGuest
local mothLook = observed.monsterLooks.ThePaleMoth
assert(rushLook and rushLook.parts >= 60 and rushLook.mist >= 5 and rushLook.halos == 1
    and rushLook.names["Cracked funeral mask"] == 1
    and rushLook.names["Chalk orbital ring"] == 28
    and not rushLook.names["Dim ember behind bone"]
    and rushLook.names["Three hooked talons"] == 6 and observed.clawFrames > 3
    and rushLook.names["Mandible tendon"] == 2 and observed.jawFrames > 3,
    "Rush lost its hollow face, moving claws or corridor-wide ash wake")
assert(blindLook and blindLook.parts >= 65 and blindLook.blocks == 0 and blindLook.halos == 1
    and blindLook.names["Oval ashen face"] == 1
    and blindLook.names["Hunched hollow thorax"] == 1
    and blindLook.names["Chalk orbital ring"] == 28
    and blindLook.names["Threadlike feeling finger"] == 10
    and blindLook.names["Ribs under stretched skin"] == 10
    and not blindLook.names["Overlapping hanging coat fold"]
    and observed.maskFrames > 2 and observed.limbFrames > 8,
    "Blind Guest no longer matches the emaciated, ring-eyed humanoid reference")
assert(mothLook and mothLook.parts >= 100 and mothLook.halos == 1
    and mothLook.names["Tiny moth thorax"] == 18
    and mothLook.names["Pale moth head"] == 18
    and mothLook.names["Fine veined moth wing"] == 36
    and not mothLook.names["Chalk orbital ring"],
    "Moth was not replaced by a swarm of very small individual insects")
local echoLook = observed.monsterLooks.TheEcho
assert(echoLook and echoLook.names["Cracked funeral mask"] == 1
    and echoLook.names["Joined hip socket"] == 2
    and rushLook.names["Joined hip socket"] == 2
    and rushLook.names["Long shin fixed to knee"] == 2
    and blindLook.names["Knifelike shin"] == 2
    and blindLook.names["Connected hip joint"] == 2,
    "humanoid legs/torso no longer meet at visible walking joints")
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
local nextFirst
for _, child in ipairs(nextWorld:GetChildren()) do
    if child:GetAttribute("RoomIndex") == 0 then nextFirst = child end
end
assert(nextFirst, "randomly themed first room did not build")
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
console.log(`Server smoke test OK: ${lua.lua_tointeger(state, -1)} doors; first-taker shared loot, held models, atmospheric audio and four threats`);
