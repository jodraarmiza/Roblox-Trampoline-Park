local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- ─── RemoteEvents ─────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name   = "TomahawkRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = remotes
	return r
end

local thStart  = makeRemote("THStart")   -- server → client: start game
local thResult = makeRemote("THResult")  -- client → server: aim+power result
local thEnd    = makeRemote("THEnd")     -- server → client: show result
local thFly    = makeRemote("THFly")     -- server → all clients: fly visual

-- ─── Constants ────────────────────────────────────────────────────────────────
local TELEPORT_OFFSET   = Vector3.new(0, 3, 0)
local MAX_POWER_ANGLE   = 25  -- max angular deviation (degrees) at 0% or 100% power
local SPAWN_BACK_OFFSET = Vector3.new(0, 3, 10)  -- where to return player after throw

-- Score zones: {maxFraction of target radius → currency}
local SCORE_ZONES = {
	{ frac = 0.15, cash = 200, label = "BULLSEYE!" },
	{ frac = 0.40, cash = 100, label = "GREAT!"    },
	{ frac = 0.75, cash = 50,  label = "GOOD"      },
	{ frac = 1.00, cash = 15,  label = "HIT"       },
}
local MISS_CASH = 0

-- Currency bridge (same BindableEvent used by PillowFightService)
local awardCurrency = ServerStorage:WaitForChild("AwardCurrency") :: BindableEvent

-- ─── Active sessions: player → spawnNum ───────────────────────────────────────
local activeSessions: { [Player]: number } = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function getSpawnPart(n: number): BasePart?
	return workspace:FindFirstChild("THspawn" .. n, true) :: BasePart?
end

local function getTarget(n: number): Instance?
	return workspace:FindFirstChild("tomahawktarget" .. n, true)
end

-- Works for both BasePart and Model targets
local function targetCFrame(t: Instance): CFrame
	if t:IsA("BasePart") then return t.CFrame end
	return (t :: Model):GetPivot()
end
local function targetSize(t: Instance): Vector3
	if t:IsA("BasePart") then return t.Size end
	return (t :: Model):GetExtentsSize()
end
local function targetPosition(t: Instance): Vector3
	return targetCFrame(t).Position
end

local function anchorPlayer(player: Player, anchored: boolean)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then root.Anchored = anchored end
end

local function teleportBack(player: Player, spawnNum: number)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local spawn = getSpawnPart(spawnNum)
	if spawn then
		-- Step 8 studs behind the spawn in world space, start high
		local candidate = spawn.CFrame * CFrame.new(0, 6, 8)
		local origin    = candidate.Position

		-- Raycast down to find actual floor so the character lands properly
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }
		local hit = workspace:Raycast(origin, Vector3.new(0, -30, 0), rp)
		local groundY = hit and (hit.Position.Y + 3) or origin.Y

		-- Set CFrame while still anchored, THEN release so physics starts at correct position
		root.CFrame   = CFrame.new(origin.X, groundY, origin.Z)
			* CFrame.fromEulerAnglesYXZ(0, select(2, candidate:ToEulerAnglesYXZ()), 0)
	end

	root.Anchored = false
end

-- ─── Spawn proximity prompts ──────────────────────────────────────────────────
local function setupSpawn(part: BasePart)
	local digit = part.Name:match("(%d+)%s*$")
	local n = digit and tonumber(digit) or 1

	local existing = part:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText    = "Throw Tomahawk"
	prompt.ObjectText    = "Station " .. n
	prompt.HoldDuration  = 0
	prompt.MaxActivationDistance = 8
	prompt.Parent        = part

	prompt.Triggered:Connect(function(player: Player)
		if activeSessions[player] then return end

		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end

		local target = getTarget(n)
		if not target then
			warn("[TH] No tomahawktarget" .. n .. " found")
			return
		end

		activeSessions[player] = n

		-- Face toward target and lock in place so the character doesn't slide
		local spawnPos = part.Position + TELEPORT_OFFSET
		local tPos     = targetPosition(target)
		local lookPos  = Vector3.new(tPos.X, spawnPos.Y, tPos.Z)
		root.CFrame    = CFrame.lookAt(spawnPos, lookPos)
		root.Anchored  = true

		-- Equip tomahawk to right hand (works for both BasePart and Model)
		local thTemplate = ReplicatedStorage:FindFirstChild("Tomahawk")
		if thTemplate then
			local held = thTemplate:Clone()
			held.Name = "TomahawkHeld"
			-- Disable collisions on every part inside
			for _, p in held:GetDescendants() do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
			if held:IsA("BasePart") then
				for _, p in held:GetDescendants() do
					if p:IsA("BasePart") then p.CanCollide = false end
				end
			end
			local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
			if hand then
				-- Get the part to weld: PrimaryPart for Models, or the part itself
				local anchor: BasePart? = nil
				if held:IsA("Model") then
					anchor = held.PrimaryPart or held:FindFirstChildOfClass("BasePart")
					held.Parent = char
					if anchor then
						anchor.CFrame = (hand :: BasePart).CFrame
					end
				elseif held:IsA("BasePart") then
					anchor = held :: BasePart
					anchor.CFrame = (hand :: BasePart).CFrame
					held.Parent = char
				end
				if anchor then
					local weld = Instance.new("WeldConstraint")
					weld.Part0  = hand :: BasePart
					weld.Part1  = anchor
					weld.Parent = anchor
				end
			end
		end

		thStart:FireClient(player, n, tPos, targetSize(target))
	end)
end

-- Set up all THspawn parts present now and any added later
local function scanSpawns()
	for _, obj in workspace:GetDescendants() do
		if obj:IsA("BasePart") and obj.Name:match("^THspawn%d+$") then
			setupSpawn(obj)
		end
	end
end

scanSpawns()
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and obj.Name:match("^THspawn%d+$") then
		task.defer(function() setupSpawn(obj) end)
	end
end)

-- ─── Throw result handler ─────────────────────────────────────────────────────
-- Client sends: aimOrigin (Vector3), aimDirection (Vector3 unit), power (0–1)
thResult.OnServerEvent:Connect(function(player: Player, aimOrigin: Vector3, aimDir: Vector3, power: number)
	local n = activeSessions[player]
	if not n then return end
	activeSessions[player] = nil

	-- Remove held tomahawk and broadcast flight to all clients
	local char2 = player.Character
	if char2 then
		local held = char2:FindFirstChild("TomahawkHeld")
		if held then held:Destroy() end
	end

	local target = getTarget(n)
	if not target then
		thEnd:FireClient(player, false, 0, "MISS", "No target")
		task.delay(0.5, function() teleportBack(player, n) end)
		return
	end

	-- Sanitise inputs
	power    = math.clamp(tonumber(power) or 0.5, 0, 1)
	aimDir   = if typeof(aimDir) == "Vector3" then aimDir.Unit else Vector3.new(0, 0, -1)
	aimOrigin = if typeof(aimOrigin) == "Vector3" then aimOrigin else Vector3.new(0, 5, 0)

	-- Apply power deviation: ideal = 0.5, deviation grows toward 0 or 1
	local deviation = math.abs(power - 0.5) * 2   -- 0 at 50%, 1 at 0% or 100%
	local angleRad  = math.rad(MAX_POWER_ANGLE) * deviation * deviation  -- quadratic feel

	-- Random perpendicular axis for the angular error
	local perp1 = aimDir:Cross(Vector3.new(0, 1, 0))
	if perp1.Magnitude < 0.01 then perp1 = aimDir:Cross(Vector3.new(1, 0, 0)) end
	perp1 = perp1.Unit
	local perp2 = aimDir:Cross(perp1).Unit
	local randAngle = math.random() * math.pi * 2
	local perpAxis  = perp1 * math.cos(randAngle) + perp2 * math.sin(randAngle)

	-- Rotate aim direction by error angle around perpendicular axis
	local cosA, sinA = math.cos(angleRad), math.sin(angleRad)
	local finalDir = aimDir * cosA + perpAxis:Cross(aimDir) * sinA
		+ perpAxis * (perpAxis:Dot(aimDir)) * (1 - cosA)
	finalDir = finalDir.Unit

	-- Raycast from origin toward target face plane
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { target }

	local RAY_LENGTH = 500
	local result = workspace:Raycast(aimOrigin, finalDir * RAY_LENGTH, rayParams)

	if not result then
		-- Still fly the tomahawk off into the distance on a miss
		local handPos2 = (char2 and char2:FindFirstChild("RightHand") or char2 and char2:FindFirstChild("Right Arm"))
		local flyOrigin2 = handPos2 and (handPos2 :: BasePart).Position or aimOrigin
		thFly:FireAllClients(flyOrigin2, flyOrigin2 + finalDir * 80)
		thEnd:FireClient(player, false, MISS_CASH, "MISS", "Missed the target")
		task.delay(5.5, function() teleportBack(player, n) end)
		return
	end

	-- Calculate distance from target centre in local 2D space (ignore depth axis)
	local hitLocal   = targetCFrame(target):PointToObjectSpace(result.Position)
	local targetFace = Vector2.new(hitLocal.X, hitLocal.Y)   -- target front face is XY plane
	local tSize      = targetSize(target)
	local halfX      = tSize.X / 2
	local halfY      = tSize.Y / 2
	local maxRadius  = math.min(halfX, halfY)
	local dist       = targetFace.Magnitude

	local cash  = MISS_CASH
	local label = "MISS"
	for _, zone in SCORE_ZONES do
		if dist <= zone.frac * maxRadius then
			cash  = zone.cash
			label = zone.label
			break
		end
	end

	if cash > 0 then
		awardCurrency:Fire(player, cash)
	end

	-- Tell all clients to animate the flight (origin = player hand area, dest = hit point)
	local handPos = (char2 and char2:FindFirstChild("RightHand") or char2 and char2:FindFirstChild("Right Arm"))
	local flyOrigin = handPos and (handPos :: BasePart).Position or aimOrigin
	thFly:FireAllClients(flyOrigin, result.Position)

	thEnd:FireClient(player, true, cash, label, result.Position)
	task.delay(6, function() teleportBack(player, n) end)
end)

-- ─── Cleanup on leave ─────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player: Player)
	if activeSessions[player] then
		anchorPlayer(player, false)
		activeSessions[player] = nil
	end
end)
