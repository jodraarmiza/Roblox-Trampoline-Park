local CS = game:GetService("CollectionService")
local TAG = "Z3Trampoline"
local cooldown = {}

local function bounce(pad, hit)
	local char = hit and hit.Parent
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then return end
	if cooldown[char] and (os.clock() - cooldown[char]) < 0.25 then return end
	cooldown[char] = os.clock()
	local power = pad:GetAttribute("BouncePower") or 100
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
end

local function setup(pad)
	if not pad:IsA("BasePart") then return end
	pad.Touched:Connect(function(hit) bounce(pad, hit) end)
end

for _, pad in ipairs(CS:GetTagged(TAG)) do setup(pad) end
CS:GetInstanceAddedSignal(TAG):Connect(setup)
print("[Z3] Trampoline system online: "..#CS:GetTagged(TAG).." pads")
