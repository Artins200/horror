// Exercise the minimal first-person bootstrap with NO HUD, RemoteEvent or
// PlayerGui present. Previously an unrelated HUD error could strand the camera
// in third person; these checks also prove copied hands are within the FOV.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const perspective = fs.readFileSync(path.join(root,
  "src/StarterPlayer/StarterPlayerScripts/NocturnePerspective.client.luau"), "utf8");
const mock = `
math.clamp = function(v, low, high) return math.max(low, math.min(high, v)) end
local vectorMeta = {
    __add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end,
    __sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end,
    __mul=function(a,b)
        if type(a)=="number" then return Vector3.new(a*b.X,a*b.Y,a*b.Z) end
        return Vector3.new(b*a.X,b*a.Y,b*a.Z)
    end,
    __index=function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end,
}
Vector3={new=function(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vectorMeta) end}
local cfMeta={__mul=function(a,b) return CFrame.new(a.Position+b.Position) end}
CFrame={new=function(x,y,z)
    return setmetatable({Position=type(x)=="table" and x or Vector3.new(x,y,z)}, cfMeta)
end, Angles=function() return CFrame.new() end}
Enum=setmetatable({}, {__index=function(t,k)
    local values=setmetatable({}, {__index=function(v,key)
        local item={Name=key,Value=200}; rawset(v,key,item); return item end})
    rawset(t,k,values); return values end})
local function signal()
    local s={callbacks={}}
    function s:Connect(f) table.insert(self.callbacks,f) end
    function s:Fire(...) for _,f in ipairs(self.callbacks) do f(...) end end
    return s
end
local methods={}
function methods:GetChildren()
    local result={}
    for _,child in ipairs(self._children) do if child.Parent==self then table.insert(result,child) end end
    return result
end
function methods:GetDescendants()
    local result={}
    for _,child in ipairs(self:GetChildren()) do
        table.insert(result,child)
        for _,nested in ipairs(child:GetDescendants()) do table.insert(result,nested) end
    end
    return result
end
function methods:FindFirstChild(name)
    for _,child in ipairs(self:GetChildren()) do if child.Name==name then return child end end
end
function methods:FindFirstChildOfClass(class)
    for _,child in ipairs(self:GetChildren()) do if child._class==class then return child end end
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:IsA(class)
    return self._class==class or (class=="BasePart" and self._class=="Part")
        or (class=="JointInstance" and self._class=="Motor6D")
end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:SetAttribute(name,value) self._attributes[name]=value end
function methods:Destroy() self.Parent=nil end
function methods:Clone()
    local result=Instance.new(self._class)
    for k,v in pairs(self) do
        if k~="_class" and k~="_children" and k~="_attributes" and k~="_parent" then result[k]=v end
    end
    for _,child in ipairs(self:GetChildren()) do child:Clone().Parent=result end
    return result
end
local meta={
    __index=function(t,k)
        if k=="Parent" then return rawget(t,"_parent") end
        if k=="Position" then return (rawget(t,"CFrame") or CFrame.new()).Position end
        return methods[k]
    end,
    __newindex=function(t,k,v)
        if k=="Parent" then
            rawset(t,"_parent",v)
            if v then table.insert(v._children,t) end
        else rawset(t,k,v) end
    end,
}
Instance={new=function(class)
    return setmetatable({_class=class,_children={},_attributes={},Name=class,
        CharacterAdded=signal(),CharacterAppearanceLoaded=signal()},meta)
end}
local player=Instance.new("Player")
local camera=Instance.new("Camera")
camera.CFrame=CFrame.new(0,3,0)
camera.FieldOfView=73
camera.ViewportSize={X=1920,Y=1080}
camera.CameraType=Enum.CameraType.Fixed
local workspace=Instance.new("Workspace")
camera.Parent=workspace
workspace.CurrentCamera=camera
local runService=Instance.new("RunService")
function runService:BindToRenderStep(_,_,callback) self.render=callback end
local services={Players=Instance.new("Players"), RunService=runService, Workspace=workspace}
services.Players.LocalPlayer=player
game={GetService=function(_,name) return services[name] end}
task={spawn=function(callback,...) callback(...) end}
(function()
${perspective}
end)()
assert(player.CameraMode==Enum.CameraMode.LockFirstPerson
    and player.CameraMinZoomDistance==0.5 and player.CameraMaxZoomDistance==0.5,
    "native first-person mode waited for the broken HUD or missing remote")
local function avatar(rig)
    local character=Instance.new("Model")
    character.Name=rig .. " character"
    local root=Instance.new("Part")
    root.Name="HumanoidRootPart"
    root.CFrame=CFrame.new(0,3,10)
    root.AssemblyLinearVelocity=Vector3.new()
    root.Anchored=false
    root.Parent=character
    local human=Instance.new("Humanoid")
    human.Name="Humanoid"
    human.Health=100
    human.RigType=rig=="R15" and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6
    human.Parent=character
    local names=rig=="R15" and {"LeftUpperArm","LeftLowerArm","LeftHand",
        "RightUpperArm","RightLowerArm","RightHand"} or {"Left Arm","Right Arm"}
    local first
    for _,name in ipairs(names) do
        local arm=Instance.new("Part")
        arm.Name=name
        arm.Archivable=false
        arm.Transparency=0
        arm.LocalTransparencyModifier=1 -- Roblox fades REAL limbs in first person
        arm.Parent=character
        first=first or arm
    end
    local weld=Instance.new("Motor6D")
    weld.Parent=first
    character.Parent=workspace
    return character,human,root,first
end
local character,human,root,realArm=avatar("R15")
player.Character=character
player.CharacterAdded:Fire(character)
assert(camera.CameraType==Enum.CameraType.Custom and camera.CameraSubject==human,
    "camera bootstrap not attached to the real Humanoid")
local display=camera:FindFirstChild("AvatarArmsFirstPerson")
assert(display and #display:GetChildren()==6 and not realArm.Archivable,
    "copies of a real R15 avatar were not made or original flags were changed")
local original=root.CFrame
runService.render(0.016)
assert(root.CFrame==original and not root.Anchored and realArm.LocalTransparencyModifier==1,
    "bootstrap moved or faded the PHYSICAL character")
local visible,inFrame=0,0
local vertical=math.tan(math.rad(camera.FieldOfView/2))
for _,part in ipairs(display:GetChildren()) do
    assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery
        and part.LocalTransparencyModifier==0 and not part:FindFirstChildOfClass("Motor6D"),
        "camera copies must stay visible and nonphysical, without cloned joints")
    if part.Transparency==0 then visible=visible+1 end
    local relative=part.Position-camera.CFrame.Position
    if relative.Z< -0.2 and math.abs(relative.Y)< -relative.Z*vertical then inFrame=inFrame+1 end
end
assert(visible==6 and inFrame>=2,
    "hands exist but were BELOW the first-person viewport")
camera.ViewportSize={X=380,Y=780}
runService.render(0.016)
local portraitHands=0
local horizontal=vertical*(camera.ViewportSize.X/camera.ViewportSize.Y)
for _,part in ipairs(display:GetChildren()) do
    local relative=part.Position-camera.CFrame.Position
    if part.Name=="LeftHand" or part.Name=="RightHand" then
        if math.abs(relative.X)< -relative.Z*horizontal then portraitHands=portraitHands+1 end
    end
end
assert(portraitHands==2, "phone portrait viewport cropped both avatar hands")
camera.ViewportSize={X=1920,Y=1080}
player.CameraMode=Enum.CameraMode.Classic
camera.CameraType=Enum.CameraType.Fixed
camera.CameraSubject=nil
runService.render(0.016)
assert(player.CameraMode==Enum.CameraMode.LockFirstPerson and camera.CameraType==Enum.CameraType.Custom
    and camera.CameraSubject==human, "a changed camera did not return to real first person")
player:SetAttribute("Hidden",true)
camera.CameraType=Enum.CameraType.Scriptable
runService.render(0.016)
assert(camera.CameraType==Enum.CameraType.Scriptable and display:FindFirstChild("LeftHand").Transparency==1,
    "first-person bootstrap overrode the wardrobe peek")
player:SetAttribute("Hidden",false)
runService.render(0.016)
assert(camera.CameraType==Enum.CameraType.Custom and display:FindFirstChild("LeftHand").Transparency==0,
    "native camera/hands did not recover after leaving the wardrobe")
local nextAvatar,nextHuman,nextRoot=avatar("R6")
player.Character=nextAvatar
player.CharacterAdded:Fire(nextAvatar)
player.CharacterAppearanceLoaded:Fire(nextAvatar)
runService.render(0.016)
assert(camera.CameraSubject==nextHuman and #display:GetChildren()==2
    and display:FindFirstChild("Left Arm") and not nextRoot.Anchored,
    "R6 respawn left the player without visible Roblox arms")
local replacement=Instance.new("Camera")
replacement.CFrame=CFrame.new(0,3,0)
replacement.FieldOfView=73
replacement.CameraType=Enum.CameraType.Fixed
replacement.Parent=workspace
workspace.CurrentCamera=replacement
runService.render(0.016)
assert(display.Parent==replacement and replacement.CameraSubject==nextHuman
    and replacement.CameraType==Enum.CameraType.Custom,
    "camera replacement detached the camera-local hands")
return true
`;
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const status = lauxlib.luaL_dostring(state, to_luastring(mock));
if (status !== lua.LUA_OK) {
  const message = to_jsstring(lua.lua_tostring(state, -1));
  const line = Number(message.match(/:(\d+):/)?.[1] ?? 0);
  const nearby = mock.split("\n").slice(Math.max(0, line - 4), line + 2)
    .map((text, offset) => `${Math.max(1, line - 3) + offset}: ${text}`).join("\n");
  throw new Error(`Independent first-person test failed: ${message}\n${nearby}`);
}
console.log("Perspective smoke test OK without HUD/remote: native Humanoid camera, R15/R6 limbs within FOV, wardrobe and respawn");
