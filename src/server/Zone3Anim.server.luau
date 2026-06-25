local zone3=workspace:WaitForChild("Zone 3 Adult",10)
if not zone3 then return end
local TS=game:GetService("TweenService")
local colors={Color3.fromRGB(0,220,255),Color3.fromRGB(255,0,200),Color3.fromRGB(150,0,255),Color3.fromRGB(255,50,150),Color3.fromRGB(0,255,200)}
local truss=zone3:FindFirstChild("TrussCeiling")
local spots={}
if truss then for _,p in ipairs(truss:GetDescendants()) do if p:IsA("SpotLight") then table.insert(spots,p) end end end
local disco=zone3:FindFirstChild("DiscoBall")
local ball=disco and disco:FindFirstChild("Ball")
if ball then
  TS:Create(ball,TweenInfo.new(4,Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,-1),{CFrame=ball.CFrame*CFrame.Angles(0,math.pi*2,0)}):Play()
end
local hub=zone3:FindFirstChild("MainVortexHub")
local orb=hub and hub:FindFirstChild("CenterOrb")
if orb then
  local pl=orb:FindFirstChildWhichIsA("PointLight")
  if pl then TS:Create(pl,TweenInfo.new(1.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Brightness=pl.Brightness*0.3}):Play() end
end
local hex=zone3:FindFirstChild("HexGlowPlatform")
local hexOrb=hex and hex:FindFirstChild("HexOrb")
if hexOrb then
  local pl=hexOrb:FindFirstChildWhichIsA("PointLight")
  if pl then TS:Create(pl,TweenInfo.new(2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Brightness=pl.Brightness*0.2}):Play() end
end
task.spawn(function()
  local idx=1
  while true do
    task.wait(0.7)
    for i,sl in ipairs(spots) do
      local ci=((i+idx)%#colors)+1
      TS:Create(sl,TweenInfo.new(0.6),{Color=colors[ci]}):Play()
    end
    idx=(idx%#colors)+1
  end
end)
print("[Zone3 Sky Vortex] Active!")
