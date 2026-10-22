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
    __div=function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end,
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
end, Angles=function() return CFrame.new() end,
lookAt=function(a) return CFrame.new(a) end}
Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
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
function methods:GetAttributeChangedSignal(name)
    self._attributeSignals[name]=self._attributeSignals[name] or signal()
    return self._attributeSignals[name]
end
function methods:SetAttribute(name,value)
    self._attributes[name]=value
    if self._attributeSignals[name] then self._attributeSignals[name]:Fire() end
end
function methods:Destroy() self.Parent=nil end
function methods:PivotTo(cf)
    local previous=self.PrimaryPart and self.PrimaryPart.CFrame or self.WorldPivot or CFrame.new()
    local shift=cf.Position-previous.Position
    for _,piece in ipairs(self:GetDescendants()) do
        if piece:IsA("BasePart") then piece.CFrame=CFrame.new(piece.Position+shift) end
    end
    self.WorldPivot=cf
end
function methods:Clone()
    local result=Instance.new(self._class)
    for k,v in pairs(self) do
        if k~="_class" and k~="_children" and k~="_attributes" and k~="_attributeSignals"
            and k~="_parent" and k~="CharacterAdded" and k~="CharacterAppearanceLoaded" then result[k]=v end
    end
    for _,child in ipairs(self:GetChildren()) do child:Clone().Parent=result end
    if self.PrimaryPart then result.PrimaryPart=result:FindFirstChild(self.PrimaryPart.Name) end
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
    return setmetatable({_class=class,_children={},_attributes={},_attributeSignals={},Name=class,
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
        arm.Size=rig=="R6" and Vector3.new(1,2,1)
            or name:find("Hand") and Vector3.new(0.59,0.53,0.64)
            or name:find("Upper") and Vector3.new(0.86,1.42,0.81)
            or Vector3.new(0.67,1.13,0.66)
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
assert(display and #display:GetChildren()==3 and not realArm.Archivable
    and not display:FindFirstChild("LeftHand") and display:FindFirstChild("RightHand"),
    "one native R15 arm was not copied from the avatar")
local original=root.CFrame
runService.render(0.016)
assert(root.CFrame==original and not root.Anchored and realArm.LocalTransparencyModifier==1,
    "bootstrap moved or faded the PHYSICAL character")
for _,part in ipairs(display:GetChildren()) do
    assert(part.Transparency==1, "avatar hands appeared BEFORE taking a key")
end
assert(not display:FindFirstChild("Key in avatar hand"), "key appeared before pickup")
player:SetAttribute("HeldKey",5) -- attribute can replicate BEFORE the key Model
runService.render(0.016)
local temporary=display:FindFirstChild("Key in avatar hand")
assert(temporary and #temporary:GetDescendants()==13 and temporary:FindFirstChild("Key stem"),
    "no correctly shaped temporary key while the physical key replicates")
local realKey=Instance.new("Model")
realKey.Name="HeldKey"
realKey.Parent=character
local realBow=Instance.new("Part")
realBow.Name="Brass key bow"
realBow.CFrame=CFrame.new(0,4,10)
realBow.LocalTransparencyModifier=0
realBow.Parent=realKey
realKey.PrimaryPart=realBow
local realStem=Instance.new("Part")
realStem.Name="Key stem"
realStem.CFrame=CFrame.new(0,4,10.46)
realStem.Parent=realKey
local realCast=Instance.new("Part")
realCast.Name="Unique real key casting"
realCast.CFrame=CFrame.new(0.1,4,10.86)
realCast.Parent=realKey
runService.render(0.016)
local key=display:FindFirstChild("Key in avatar hand")
assert(key and key~=temporary and key:FindFirstChild("Unique real key casting")
    and key:FindFirstChild("Brass key bow") and realBow.LocalTransparencyModifier==1
    and not temporary.Parent,
    "display did not switch to a clone of the ACTUAL held key")
local vertical=math.tan(math.rad(camera.FieldOfView/2))
local visible,inFrame=0,0
for _,part in ipairs(display:GetChildren()) do
    if part:IsA("BasePart") then
        assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery
            and part.LocalTransparencyModifier==0 and not part:FindFirstChildOfClass("Motor6D"),
            "copied Roblox limbs became physical or lost their mesh")
        if part.Transparency==0 then visible=visible+1 end
        local v=part.Position-camera.CFrame.Position
        if v.Z< -0.2 and math.abs(v.Y)< -v.Z*vertical then inFrame=inFrame+1 end
    end
end
assert(visible==3 and inFrame>=2, "the ordinary gripping arm is out of frame")
local right=display:FindFirstChild("RightHand")
local lower=display:FindFirstChild("RightLowerArm")
local upper=display:FindFirstChild("RightUpperArm")
assert(math.abs((lower.Position-right.Position).Magnitude-(lower.Size.Y+right.Size.Y)/2)<0.18
    and math.abs((upper.Position-lower.Position).Magnitude-(upper.Size.Y+lower.Size.Y)/2)<0.18,
    "R15 wrist/elbow pieces are separated or inverted instead of joined")
local firstY, firstKeyY=right.Position.Y, key.WorldPivot.Position.Y
runService.render(0.30)
assert(right.Position.Y>firstY+0.15 and key.WorldPivot.Position.Y>firstKeyY+0.15,
    "key pickup did not raise the same Roblox hand AND its real key copy")
player:SetAttribute("KeyTurning",true)
local beforeTurn=right.Position.Y
runService.render(0.3)
assert(right.Position.Y>beforeTurn+0.15 and key.WorldPivot.Position.Y>camera.CFrame.Position.Y-0.6,
    "key was not lifted in the hand when turning the door lock")
player:SetAttribute("KeyTurning",false)
camera.ViewportSize={X=380,Y=780}
runService.render(0.016)
local horizontal=vertical*(camera.ViewportSize.X/camera.ViewportSize.Y)
local portrait=0
for _,name in ipairs({"RightHand","RightLowerArm"}) do
    local part=display:FindFirstChild(name)
    local v=part.Position-camera.CFrame.Position
    if v.Z<0 and math.abs(v.X)< -v.Z*horizontal then portrait=portrait+1 end
end
assert(portrait>=1, "phone portrait cropped the normal gripping hand")
camera.ViewportSize={X=1920,Y=1080}
player.CameraMode=Enum.CameraMode.Classic
camera.CameraType=Enum.CameraType.Fixed
camera.CameraSubject=nil
runService.render(0.016)
assert(player.CameraMode==Enum.CameraMode.LockFirstPerson and camera.CameraType==Enum.CameraType.Custom
    and camera.CameraSubject==human, "native camera no longer follows real Humanoid")
player:SetAttribute("Hidden",true)
camera.CameraType=Enum.CameraType.Scriptable
runService.render(0.016)
assert(camera.CameraType==Enum.CameraType.Scriptable and right.Transparency==1
    and key:FindFirstChild("Key stem").Transparency==1,
    "wardrobe camera did not hide the arms and key")
player:SetAttribute("Hidden",false)
runService.render(0.016)
assert(camera.CameraType==Enum.CameraType.Custom and right.Transparency==0,
    "native camera/hands did not recover after wardrobe")
player:SetAttribute("HeldKey",nil)
runService.render(0.016)
assert(not display:FindFirstChild("Key in avatar hand") and right.Transparency==1,
    "key or hands remain onscreen after using the key")
local nextAvatar,nextHuman,nextRoot=avatar("R6")
player.Character=nextAvatar
player.CharacterAdded:Fire(nextAvatar)
player.CharacterAppearanceLoaded:Fire(nextAvatar)
runService.render(0.016)
assert(camera.CameraSubject==nextHuman and #display:GetChildren()==1
    and not display:FindFirstChild("Left Arm") and not nextRoot.Anchored
    and display:FindFirstChild("Right Arm").Transparency==1,
    "R6 respawn has floating arms before the next key")
player:SetAttribute("HeldKey",9)
runService.render(0.016)
assert(display:FindFirstChild("Key in avatar hand")
    and display:FindFirstChild("Right Arm").Transparency==0,
    "R6 cannot lift a found key using its real Roblox arm")
local replacement=Instance.new("Camera")
replacement.CFrame=CFrame.new(0,3,0)
replacement.FieldOfView=73
replacement.CameraType=Enum.CameraType.Fixed
replacement.Parent=workspace
workspace.CurrentCamera=replacement
runService.render(0.016)
assert(display.Parent==replacement and replacement.CameraSubject==nextHuman
    and replacement.CameraType==Enum.CameraType.Custom,
    "camera replacement detached key-only avatar arms")
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
console.log("Perspective smoke test OK: connected R6/R15 right arm, exact held-key replica, raise/turn poses, wardrobe and respawn");
