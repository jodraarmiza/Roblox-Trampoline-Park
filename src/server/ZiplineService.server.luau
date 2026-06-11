local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local ziplinesFolder = workspace:WaitForChild("Ziplines")

local ZIPLINE_ANIM_ID = "rbxassetid://72117247448455"

local function getValue(parent: Instance, name: string, default: any): any
	local obj = parent:FindFirstChild(name)
	if obj and (obj:IsA("NumberValue") or obj:IsA("BoolValue")) then
		return obj.Value
	end
	return default
end

type Endpoint = { promptParent: BasePart, position: Vector3 }

-- Resolves "Start"/"Finish" whether it's a BasePart, Attachment, or Model
local function findEndpoint(model: Instance, name: string): Endpoint?
	local found = model:FindFirstChild(name, true)
	if not found then return nil end

	if found:IsA("BasePart") then
		return { promptParent = found, position = found.Position }
	elseif found:IsA("Attachment") then
		local parent = found.Parent
		if parent and parent:IsA("BasePart") then
			return { promptParent = parent, position = found.WorldPosition }
		end
	elseif found:IsA("Model") then
		local primary = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			return { promptParent = primary, position = found:GetPivot().Position }
		end
	end

	return nil
end

local function ride(player: Player, fromPos: Vector3, toPos: Vector3, speed: number)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root      = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then return end
	if humanoid:GetAttribute("OnZipline") then return end

	humanoid:SetAttribute("OnZipline", true)
	humanoid.PlatformStand = true
	root.Anchored          = true

	local animTrack: AnimationTrack? = nil
	local anim = Instance.new("Animation")
	anim.AnimationId = ZIPLINE_ANIM_ID
	local ok, loaded = pcall(function() return humanoid:LoadAnimation(anim) end)
	if ok and loaded then
		animTrack = loaded
		animTrack.Looped = true
		animTrack:Play()
	end

	local startPos  = fromPos
	local endPos    = toPos
	local direction = (endPos - startPos)
	local distance  = direction.Magnitude
	local dir       = direction.Unit
	local duration  = math.max(distance / math.max(speed, 1), 0.1)
	local startTime = tick()

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not char.Parent or not root.Parent then
			conn:Disconnect()
			if animTrack then animTrack:Stop() end
			return
		end

		local alpha = math.min((tick() - startTime) / duration, 1)
		local pos   = startPos:Lerp(endPos, alpha)
		root.CFrame = CFrame.lookAt(pos, pos + dir)

		if alpha >= 1 then
			conn:Disconnect()
			if animTrack then animTrack:Stop() end
			root.Anchored          = false
			humanoid.PlatformStand = false
			humanoid:SetAttribute("OnZipline", nil)
		end
	end)
end

local function setupPrompt(promptParent: BasePart, fromPos: Vector3, toPos: Vector3, speed: number)
	local existing = promptParent:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Ride Zipline"
	prompt.ObjectText             = "Zipline"
	prompt.HoldDuration           = 0
	prompt.MaxActivationDistance  = 8
	prompt.Parent                 = promptParent

	prompt.Triggered:Connect(function(player: Player)
		ride(player, fromPos, toPos, speed)
	end)
end

local function setupLine(line: Instance)
	local startModel  = line:FindFirstChild("StartModel")
	local finishModel = line:FindFirstChild("FinishModel")
	if not startModel or not finishModel then return end

	local startEnd  = findEndpoint(startModel, "Start")
	local finishEnd = findEndpoint(finishModel, "Finish")
	if not startEnd or not finishEnd then
		warn("[Zipline] Missing Start/Finish endpoint in", line:GetFullName())
		return
	end

	local speed    = getValue(line, "Speed", 30)
	local bothWays = getValue(line, "BothWays", false)

	setupPrompt(startEnd.promptParent, startEnd.position, finishEnd.position, speed)
	if bothWays then
		setupPrompt(finishEnd.promptParent, finishEnd.position, startEnd.position, speed)
	end
end

for _, line in ziplinesFolder:GetChildren() do
	if line:IsA("Folder") or line:IsA("Model") then
		setupLine(line)
	end
end
