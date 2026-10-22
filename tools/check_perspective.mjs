// Execute the bootstrap without a HUD, PlayerGui or RemoteEvent. Assert the
// real Motor6D-connected avatar arm/key is posed; no duplicate viewmodel exists.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const perspective = fs.readFileSync(path.join(root,
  "src/StarterPlayer/StarterPlayerScripts/NocturnePerspective.client.luau"), "utf8");
const mock = `
local vectorMeta = {
    __add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end,
    __sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end,
}
Vector3={new=function(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vectorMeta) end}
local cfMeta
cfMeta={
    __mul=function(a,b)
        return setmetatable({Position=a.Position+b.Position,
            pitch=(a.pitch or 0)+(b.pitch or 0),roll=(a.roll or 0)+(b.roll or 0)},cfMeta)
    end,
    __index=function(cf,k)
        if k=="Rotation" then
            return setmetatable({Position=Vector3.new(),pitch=cf.pitch,roll=cf.roll},cfMeta)
        end
    end,
}
CFrame={new=function(x,y,z)
    return setmetatable({Position=type(x)=="table" and x or Vector3.new(x,y,z),
        pitch=0,roll=0},cfMeta)
end, Angles=function(x,_,z)
    return setmetatable({Position=Vector3.new(),pitch=x or 0,roll=z or 0},cfMeta)
end}
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
    local list={}
    for _,child in ipairs(self._children) do if child.Parent==self then table.insert(list,child) end end
    return list
end
function methods:GetDescendants()
    local list={}
    for _,child in ipairs(self:GetChildren()) do
        table.insert(list,child)
        for _,descendant in ipairs(child:GetDescendants()) do table.insert(list,descendant) end
    end
    return list
end
function methods:FindFirstChild(name,recursive)
    for _,child in ipairs(self:GetChildren()) do
        if child.Name==name then return child end
        if recursive then
            local found=child:FindFirstChild(name,true)
            if found then return found end
        end
    end
end
function methods:FindFirstChildOfClass(class)
    for _,child in ipairs(self:GetChildren()) do if child._class==class then return child end end
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:IsA(class)
    return self._class==class or (class=="BasePart" and self._class=="Part")
end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:SetAttribute(name,value) self._attributes[name]=value end
function methods:Destroy() self.Parent=nil end
local meta={
    __index=function(t,k)
        if k=="Parent" then return rawget(t,"_parent") end
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
camera.CameraType=Enum.CameraType.Fixed
local workspace=Instance.new("Workspace")
camera.Parent=workspace
workspace.CurrentCamera=camera
local runService=Instance.new("RunService")
function runService:BindToRenderStep(_,_,callback) self.render=callback end
local services={Players=Instance.new("Players"),RunService=runService,Workspace=workspace}
services.Players.LocalPlayer=player
game={GetService=function(_,name) return services[name] end}
task={spawn=function(callback,...) callback(...) end}
(function()
${perspective}
end)()
assert(player.CameraMode==Enum.CameraMode.LockFirstPerson
    and player.CameraMinZoomDistance==0.5 and player.CameraMaxZoomDistance==0.5,
    "camera bootstrap waited for an unrelated HUD or remotes")
local function avatar(rig)
    local character=Instance.new("Model")
    local torso=Instance.new("Part")
    torso.Name=rig=="R15" and "UpperTorso" or "Torso"
    torso.Parent=character
    local root=Instance.new("Part")
    root.Name="HumanoidRootPart"
    root.CFrame=CFrame.new(0,3,10)
    root.Anchored=false
    root.Parent=character
    local human=Instance.new("Humanoid")
    human.Name="Humanoid"
    human.Health=100
    human.RigType=rig=="R15" and Enum.HumanoidRigType.R15 or Enum.HumanoidRigType.R6
    human.Parent=character
    local names=rig=="R15" and {"RightUpperArm","RightLowerArm","RightHand",
        "LeftUpperArm","LeftLowerArm","LeftHand"} or {"Right Arm","Left Arm"}
    local parts={}
    for _,name in ipairs(names) do
        local part=Instance.new("Part")
        part.Name=name
        part.Transparency=0
        part.LocalTransparencyModifier=1 -- CameraModule fades real arms
        part.CanCollide=false
        part.Parent=character
        parts[name]=part
    end
    local function joint(name,parent,a,b)
        local motor=Instance.new("Motor6D")
        motor.Name=name
        motor.C0=CFrame.new(0.8,0.4,0)
        motor.Part0=a
        motor.Part1=b
        motor.Parent=parent
        return motor
    end
    local arm=parts[rig=="R15" and "RightUpperArm" or "Right Arm"]
    local shoulder=joint(rig=="R15" and "RightShoulder" or "Right Shoulder",torso,torso,arm)
    local elbow,wrist
    local leftArm=parts[rig=="R15" and "LeftUpperArm" or "Left Arm"]
    local leftShoulder=joint(rig=="R15" and "LeftShoulder" or "Left Shoulder",
        torso,torso,leftArm)
    if rig=="R15" then
        elbow=joint("RightElbow",arm,arm,parts.RightLowerArm)
        wrist=joint("RightWrist",parts.RightLowerArm,parts.RightLowerArm,parts.RightHand)
        joint("LeftElbow",leftArm,leftArm,parts.LeftLowerArm)
        joint("LeftWrist",parts.LeftLowerArm,parts.LeftLowerArm,parts.LeftHand)
    end
    character.Parent=workspace
    return character,human,root,parts,shoulder,elbow,wrist,leftShoulder
end
local avatar15,human15,root15,arms15,shoulder,elbow,wrist=avatar("R15")
player.Character=avatar15
player.CharacterAdded:Fire(avatar15)
assert(camera.CameraType==Enum.CameraType.Custom and camera.CameraSubject==human15,
    "native camera did not follow the physical Humanoid")
local physicalRoot=root15.CFrame
runService.render(0.016)
assert(root15.CFrame==physicalRoot and not root15.Anchored
    and arms15.RightHand.LocalTransparencyModifier==1
    and not camera:FindFirstChild("AvatarArmsFirstPerson"),
    "created detached copy or exposed hands before finding a key")
player:SetAttribute("HeldKey",12)
runService.render(0.016)
local pickupPitch=shoulder.C0.pitch
assert(pickupPitch>0 and arms15.RightHand.LocalTransparencyModifier==0
    and arms15.RightUpperArm.LocalTransparencyModifier==0
    and arms15.RightLowerArm.LocalTransparencyModifier==0
    and arms15.LeftHand.LocalTransparencyModifier==1,
    "the actual connected avatar arm was not raised when the key arrived")
for _=1,8 do runService.render(0.07) end
assert(shoulder.C0.pitch>pickupPitch+0.25 and elbow.C0.pitch< -0.5
    and wrist.C0.roll<0 and shoulder.Part1==arms15.RightUpperArm
    and elbow.Part1==arms15.RightLowerArm and wrist.Part1==arms15.RightHand,
    "native R15 shoulder, elbow or wrist disconnected during key pickup")
local key=Instance.new("Model")
key.Name="HeldKey"
key.Parent=avatar15
local bow=Instance.new("Part")
bow.Name="Brass key bow"
bow.LocalTransparencyModifier=1
bow.Parent=key
local grip=Instance.new("WeldConstraint")
grip.Name="Key grip in Roblox hand"
grip.Part0=arms15.RightHand
 grip.Part1=bow
 grip.Parent=bow
runService.render(0.016)
assert(bow.LocalTransparencyModifier==0 and grip.Part0==arms15.RightHand
    and not camera:FindFirstChild("Key in avatar hand"),
    "copy replaced the real welded key in the owner's normal Roblox hand")
local restingPitch=shoulder.C0.pitch
player:SetAttribute("KeyTurning",true)
for _=1,7 do runService.render(0.06) end
assert(shoulder.C0.pitch>restingPitch+0.20 and elbow.C0.pitch< -0.8,
    "native arm did not lift into the lock when turning the actual key")
player:SetAttribute("Hidden",true)
camera.CameraType=Enum.CameraType.Scriptable
runService.render(0.016)
assert(camera.CameraType==Enum.CameraType.Scriptable
    and shoulder.C0.pitch==0 and bow.LocalTransparencyModifier==1
    and arms15.RightHand.LocalTransparencyModifier==1,
    "wardrobe did not hide or reset the arm without stealing its camera")
player:SetAttribute("Hidden",false)
player:SetAttribute("KeyTurning",false)
runService.render(0.016)
assert(camera.CameraType==Enum.CameraType.Custom and camera.CameraSubject==human15
    and bow.LocalTransparencyModifier==0,
    "ordinary first person did not recover after leaving wardrobe")
player:SetAttribute("HeldKey",nil)
runService.render(0.016)
assert(shoulder.C0.pitch==0 and elbow.C0.pitch==0
    and arms15.RightHand.LocalTransparencyModifier==1 and bow.LocalTransparencyModifier==1,
    "right arm/key stayed in front of camera after consuming the key")
local heldItem=Instance.new("Model")
heldItem.Name="HeldItem"
heldItem:SetAttribute("ItemKind","PILL")
heldItem:SetAttribute("GripHand","Right")
heldItem.Parent=avatar15
local vial=Instance.new("Part")
vial.Name="Amber apothecary vial"
vial.LocalTransparencyModifier=1
vial.Parent=heldItem
local itemGrip=Instance.new("WeldConstraint")
itemGrip.Name="Item grip in Roblox hand"
itemGrip.Part0=arms15.RightHand
itemGrip.Part1=vial
itemGrip.Parent=vial
for _=1,7 do runService.render(0.07) end
assert(shoulder.C0.pitch>0.6 and arms15.RightHand.LocalTransparencyModifier==0
    and vial.LocalTransparencyModifier==0 and arms15.LeftHand.LocalTransparencyModifier==1
    and itemGrip.Part0==arms15.RightHand,
    "selected detailed consumable is not shown in the actual R15 right hand")
local leftShoulder=avatar15:FindFirstChild("LeftShoulder",true)
heldItem:SetAttribute("GripHand","Left")
itemGrip.Part0=arms15.LeftHand
player:SetAttribute("HeldKey",12)
for _=1,8 do runService.render(0.07) end
assert(leftShoulder.C0.pitch>0.5 and arms15.LeftHand.LocalTransparencyModifier==0
    and arms15.RightHand.LocalTransparencyModifier==0 and vial.LocalTransparencyModifier==0
    and bow.LocalTransparencyModifier==0 and itemGrip.Part0==arms15.LeftHand,
    "the key hid or displaced the selected item instead of using the real left hand")
player:SetAttribute("Hidden",true)
runService.render(0.016)
assert(leftShoulder.C0.pitch==0 and arms15.LeftHand.LocalTransparencyModifier==1
    and vial.LocalTransparencyModifier==1 and bow.LocalTransparencyModifier==1,
    "hiding left the item visible in the wardrobe")
player:SetAttribute("Hidden",false)
player:SetAttribute("HeldKey",nil)
heldItem.Parent=nil
runService.render(0.016)
assert(leftShoulder.C0.pitch==0 and arms15.LeftHand.LocalTransparencyModifier==1
    and arms15.RightHand.LocalTransparencyModifier==1,
    "using/losing an item left both arms hovering in first person")
local physical15 = root15.CFrame
player:SetAttribute("VoidWalk", true)
for _=1,9 do runService.render(0.07) end
assert(leftShoulder.C0.pitch>1.25 and arms15.LeftHand.LocalTransparencyModifier==0
    and arms15.LeftUpperArm.LocalTransparencyModifier==0
    and arms15.LeftLowerArm.LocalTransparencyModifier==0
    and arms15.RightHand.LocalTransparencyModifier==1
    and root15.CFrame==physical15 and not root15.Anchored
    and camera.CameraType==Enum.CameraType.Custom and camera.CameraSubject==human15,
    "white void did not raise the genuine R15 forearm without creating a detached camera")
player:SetAttribute("VoidWalk", false)
for _=1,7 do runService.render(0.07) end
assert(leftShoulder.C0.pitch==0 and arms15.LeftHand.LocalTransparencyModifier==1,
    "left R15 arm stayed in front of the face after leaving the white void")
local avatar6,human6,root6,arms6,shoulder6=avatar("R6")
player.Character=avatar6
player.CharacterAdded:Fire(avatar6)
player.CharacterAppearanceLoaded:Fire(avatar6)
runService.render(0.016)
assert(camera.CameraSubject==human6 and not root6.Anchored
    and arms6["Right Arm"].LocalTransparencyModifier==1,
    "R6 respawn left an ungrounded avatar or always-visible hands")
player:SetAttribute("HeldKey",13)
for _=1,7 do runService.render(0.07) end
assert(shoulder6.C0.pitch>0.45 and arms6["Right Arm"].LocalTransparencyModifier==0
    and arms6["Left Arm"].LocalTransparencyModifier==1,
    "normal-size R6 right arm cannot hold its actual key")
local kit=Instance.new("Model")
kit.Name="HeldItem"
kit:SetAttribute("ItemKind","MEDKIT")
kit:SetAttribute("GripHand","Left")
kit.Parent=avatar6
local tin=Instance.new("Part")
tin.Name="Enamelled medical tin"
tin.LocalTransparencyModifier=1
tin.Parent=kit
for _=1,8 do runService.render(0.07) end
assert(arms6["Left Arm"].LocalTransparencyModifier==0
    and arms6["Right Arm"].LocalTransparencyModifier==0
    and tin.LocalTransparencyModifier==0 and avatar6:FindFirstChild("Left Shoulder",true).C0.pitch>0.5,
    "R6 medical tin was not held by the real left arm while a key uses the right")
player:SetAttribute("HeldKey",nil)
heldItem.Parent=nil
kit.Parent=nil
player:SetAttribute("VoidWalk",true)
for _=1,9 do runService.render(0.07) end
assert(avatar6:FindFirstChild("Left Shoulder",true).C0.pitch>1.25
    and arms6["Left Arm"].LocalTransparencyModifier==0
    and arms6["Right Arm"].LocalTransparencyModifier==1
    and not root6.Anchored,
    "an empty R6 hand did not shield the eyes in the final white chamber")
player:SetAttribute("VoidWalk",false)
for _=1,7 do runService.render(0.07) end
assert(arms6["Left Arm"].LocalTransparencyModifier==1
    and avatar6:FindFirstChild("Left Shoulder",true).C0.pitch==0,
    "R6 eye-covering pose leaked into the normal hotel")
local replacement=Instance.new("Camera")
replacement.CameraType=Enum.CameraType.Fixed
replacement.Parent=workspace
workspace.CurrentCamera=replacement
runService.render(0.016)
assert(replacement.CameraType==Enum.CameraType.Custom and replacement.CameraSubject==human6
    and #replacement:GetChildren()==0 and not root6.Anchored,
    "camera replacement made a disconnected arm/viewpoint")
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
console.log("Perspective smoke test OK: native R6/R15 key/items/wardrobe and real eye-shield arm, no viewmodel");
