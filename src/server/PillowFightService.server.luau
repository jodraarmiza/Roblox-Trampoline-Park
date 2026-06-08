local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")

-- ─── RemoteEvents ─────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name  = "PillowFightRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = remotes
	return r
end

local queueUpdate = makeRemote("QueueUpdate")  -- server → client
local gameStart   = makeRemote("GameStart")    -- server → client
local pillowHit   = makeRemote("PillowHit")    -- client → server
local pillowDodge = makeRemote("PillowDodge")  -- client → server
local hitResult   = makeRemote("HitResult")    -- server → client
local gameEnd     = makeRemote("GameEnd")      -- server → client
local leaveQueue  = makeRemote("LeaveQueue")   -- client → server

-- ─── Constants ────────────────────────────────────────────────────────────────
local MAX_HP         = 3
local HIT_RANGE      = 13
local HIT_COOLDOWN   = 0.7
local DODGE_DURATION = 0.65
local DODGE_COOLDOWN = 1
local KNOCKBACK      = 55
local FALL_THRESHOLD = 12
local BOT_WAIT_TIME  = 5   -- seconds alone in queue before bot fills in
local BOT_WIN_REWARD    = 100
local PLAYER_WIN_REWARD = 250

-- Bot AI tuning
local BOT_MOVE_SPEED      = 10   -- studs/sec while approaching
local BOT_MIN_DISTANCE    = 4    -- stops closing the gap once this near (avoids overlap)
local BOT_ATTACK_COOLDOWN = 1.1
local BOT_HIT_ANIM        = "rbxassetid://135446390129712"
local BOT_WALK_ANIM       = "rbxassetid://913402848" -- default R15 walk

local awardCurrency = ServerStorage:WaitForChild("AwardCurrency") :: BindableEvent

-- ─── State ────────────────────────────────────────────────────────────────────
type GameData = {
	opponent:    Player,
	myHp:        number,
	isDodging:   boolean,
	dodgeCd:     number,
	hitCd:       number,
	spawnCFrame: CFrame,
}

type BotGame = {
	myHp:        number,
	botHp:       number,
	botPos:      Vector3,
	botRig:      Model?,
	spawnCFrame: CFrame,
	hitCd:       number,
	dodgeCd:     number,
	isDodging:   boolean,
	botAttackCd: number,
	botHitTrack: AnimationTrack?,
	botWalkTrack: AnimationTrack?,
}

local queues:     { [number]: { Player } } = { [1] = {}, [2] = {}, [3] = {} }
local playerBridge: { [Player]: number }  = {}  -- which bridge a queued/waiting player picked
local games:      { [Player]: GameData }  = {}
local botGames:   { [Player]: BotGame }   = {}
local botTimers:  { [Player]: thread }    = {}  -- pending bot countdown per player

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function getSpawns(bridge: number): (CFrame, CFrame)
	local n1 = "PFspawn" .. tostring(bridge * 2 - 1)
	local n2 = "PFspawn" .. tostring(bridge * 2)
	local s1 = workspace:FindFirstChild(n1, true) :: BasePart?
	local s2 = workspace:FindFirstChild(n2, true) :: BasePart?
	if s1 and s2 then
		local p1 = s1.Position + Vector3.new(0, 3, 0)
		local p2 = s2.Position + Vector3.new(0, 3, 0)
		return CFrame.lookAt(p1, p2), CFrame.lookAt(p2, p1)
	end
	return CFrame.lookAt(Vector3.new(0, 10, -8), Vector3.new(0, 10, 8)),
	       CFrame.lookAt(Vector3.new(0, 10,  8), Vector3.new(0, 10, -8))
end

local function removeFromQueue(player: Player)
	local bridge = playerBridge[player]
	if not bridge then return end
	local q = queues[bridge]
	if q then
		for i, p in q do
			if p == player then table.remove(q, i) break end
		end
	end
	playerBridge[player] = nil
end

local function cancelBotTimer(player: Player)
	if botTimers[player] then
		task.cancel(botTimers[player])
		botTimers[player] = nil
	end
end

local function getMainSpawn(): CFrame
	local sp = workspace:FindFirstChild("spawnplace", true) :: BasePart?
		or workspace:FindFirstChildOfClass("SpawnLocation") :: BasePart?
	return sp and sp.CFrame or CFrame.new(0, 5, 0)
end

local function teleportBack(player: Player)
	task.delay(1.5, function()
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end
		local offset = Vector3.new(math.random(-5, 5), 3, math.random(-5, 5))
		root.CFrame = getMainSpawn() + offset
	end)
end

-- ─── Pillow tool ──────────────────────────────────────────────────────────────
local function givePillow(player: Player)
	local template = ServerStorage:FindFirstChild("Pillow")
	if not template then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	-- Clear any leftover pillow first
	for _, obj in { char, player.Backpack } do
		local old = obj:FindFirstChild("Pillow")
		if old then old:Destroy() end
	end
	local pillow = template:Clone()
	pillow.Parent = player.Backpack
	humanoid:EquipTool(pillow)
end

local function removePillow(player: Player)
	for _, obj in { player.Character or {}, player.Backpack } do
		local tool = obj:FindFirstChild("Pillow")
		if tool then tool:Destroy() end
	end
end

-- ─── Bot rig ──────────────────────────────────────────────────────────────────
-- Live player characters can have Archivable = false (common on official
-- avatar bundles/items), which makes Clone() silently return nil. Instead we
-- clone the "Rig" template used for authoring animations — same proportions
-- as the player's character (so the Pillow grip and hit/block animations look
-- correct), and guaranteed to be archivable since it's editable in Studio.
-- RBX_ANIMSAVES (under ServerStorage) holds internal animation-save data —
-- folders that mimic a rig's joint hierarchy but contain no real geometry.
-- A genuine animation-reference rig has a Humanoid AND actual visible
-- BaseParts (non-zero size). Use that to tell them apart.
local function isVisibleRig(model: Instance): boolean
	if not model:IsA("Model") then return false end
	if not model:FindFirstChildOfClass("Humanoid") then return false end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Size.Magnitude > 0 then
			return true
		end
	end
	return false
end

local RIG_TEMPLATE_NAMES = { "PFRIG", "Rig" }

local function findRigTemplate(): Model?
	for _, name in RIG_TEMPLATE_NAMES do
		local inWorkspace = workspace:FindFirstChild(name)
		if inWorkspace and isVisibleRig(inWorkspace) then
			return inWorkspace :: Model
		end
		local inStorage = ServerStorage:FindFirstChild(name)
		if inStorage and isVisibleRig(inStorage) then
			return inStorage :: Model
		end
	end
	return nil
end

local function spawnBotRig(cf: CFrame): Model?
	local sourceRig = findRigTemplate()
	if not sourceRig then
		warn("[PFBot] spawnBotRig: no 'Rig' template found in ServerStorage or Workspace")
		return nil
	end

	local ok, rig = pcall(function()
		return sourceRig:Clone()
	end)
	if not ok or not rig then
		warn("[PFBot] spawnBotRig: clone failed —", rig)
		return nil
	end
	print("[PFBot] spawnBotRig: cloned", rig.Name, "at", tostring(cf.Position))

	rig.Name = "PillowFightBot"

	for _, obj in rig:GetChildren() do
		if obj:IsA("Tool") then obj:Destroy() end
	end

	-- The Animate script tries to load the rig's default walk/idle/run
	-- animations, which can fail with a permission error for a
	-- server-spawned NPC (no player context). The bot doesn't move via
	-- Humanoid animations anyway (WalkSpeed = 0, controlled via PivotTo),
	-- so it can be safely removed.
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed  = 0
		humanoid.JumpPower  = 0
		humanoid.AutoRotate = false
		humanoid.DisplayName = "BOT"
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.Health     = humanoid.MaxHealth
	end

	-- Anchoring individual parts of a jointed rig makes it render as
	-- invisible/broken client-side, so instead we just disable collision —
	-- gravity bounce is countered every frame in the Heartbeat loop by
	-- zeroing the root's velocity right after PivotTo.
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			-- The "Rig" template is likely kept hidden (Transparency = 1) as
			-- an animation-reference dummy; force the clone visible, except
			-- HumanoidRootPart which is *meant* to stay invisible.
			if part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
				part.LocalTransparencyModifier = 0
			end
		elseif part:IsA("Decal") then
			part.Transparency = 0
		end
	end

	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			print(("[PFBot] part %s (%s) size=%s transparency=%.2f canCollide=%s parent=%s"):format(
				part.Name, part.ClassName, tostring(part.Size), part.Transparency, tostring(part.CanCollide), tostring(part.Parent)))
		end
	end

	-- Neutralize any baked-in PivotOffset (the animation-reference rig
	-- likely has one, e.g. (0, -3, 0)) so PivotTo places the visible mesh
	-- exactly at `cf` instead of shifting it underground/off to a side.
	if rig.PrimaryPart then
		print(("[PFBot] PrimaryPart=%s PivotOffset=%s"):format(rig.PrimaryPart.Name, tostring(rig.PrimaryPart.PivotOffset)))
		rig.PrimaryPart.PivotOffset = CFrame.new()
	end

	rig.Parent = workspace
	rig:PivotTo(cf)
	print("[PFBot] after PivotTo, root at", tostring(rig:GetPivot().Position), "humanoidRootPart at", tostring(rig.PrimaryPart and rig.PrimaryPart.Position))

	local template = ServerStorage:FindFirstChild("Pillow")
	if template and humanoid then
		local pillow = template:Clone()
		pillow.Parent = rig
		humanoid:EquipTool(pillow)
	end

	return rig
end

local function destroyBotRig(rig: Model?)
	if rig then rig:Destroy() end
end

-- ─── PvP game ─────────────────────────────────────────────────────────────────
local function endGame(winner: Player, loser: Player, reason: string)
	games[winner] = nil
	games[loser]  = nil
	removePillow(winner)
	removePillow(loser)
	awardCurrency:Fire(winner, PLAYER_WIN_REWARD)
	gameEnd:FireClient(winner, true,  loser.Name,  reason)
	gameEnd:FireClient(loser,  false, winner.Name, reason)
	teleportBack(winner)
	teleportBack(loser)
end

local function startGame(p1: Player, p2: Player, bridge: number)
	local cf1, cf2 = getSpawns(bridge)

	local function tp(player: Player, cf: CFrame)
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then root.CFrame = cf end
	end

	tp(p1, cf1)
	tp(p2, cf2)

	games[p1] = { opponent = p2, myHp = MAX_HP, isDodging = false, dodgeCd = 0, hitCd = 0, spawnCFrame = cf1 }
	games[p2] = { opponent = p1, myHp = MAX_HP, isDodging = false, dodgeCd = 0, hitCd = 0, spawnCFrame = cf2 }

	gameStart:FireClient(p1, p2.Name, MAX_HP)
	gameStart:FireClient(p2, p1.Name, MAX_HP)
	givePillow(p1)
	givePillow(p2)
end

-- ─── Bot game ─────────────────────────────────────────────────────────────────
local function endBotGame(player: Player, won: boolean, reason: string)
	local bData = botGames[player]
	botGames[player] = nil
	removePillow(player)
	if bData then destroyBotRig(bData.botRig) end
	if won then
		awardCurrency:Fire(player, BOT_WIN_REWARD)
	end
	gameEnd:FireClient(player, won, "BOT", reason)
	teleportBack(player)
end

local function startBotGame(player: Player, bridge: number)
	local cf1, cf2 = getSpawns(bridge)
	local char = player.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then root.CFrame = cf1 end
	end

	local botCFrame = CFrame.lookAt(cf2.Position, cf1.Position)
	local botRig = spawnBotRig(botCFrame)
	print("[PFBot] startBotGame: char=", tostring(char), "botRig=", tostring(botRig))

	botGames[player] = {
		myHp        = MAX_HP,
		botHp       = MAX_HP,
		botPos      = cf2.Position,
		botRig      = botRig,
		spawnCFrame = cf1,
		hitCd       = 0,
		dodgeCd     = 0,
		isDodging   = false,
		botAttackCd = 0,
		botHitTrack = nil,
		botWalkTrack = nil,
	}
	queueUpdate:FireClient(player, "starting", "BOT")
	task.delay(0.8, function()
		gameStart:FireClient(player, "BOT", MAX_HP)
		givePillow(player)
	end)
end

-- ─── Matchmaking ──────────────────────────────────────────────────────────────
local function tryMatch(bridge: number)
	local q = queues[bridge]
	if #q < 2 then return end
	local p1 = table.remove(q, 1)
	local p2 = table.remove(q, 1)
	playerBridge[p1] = nil
	playerBridge[p2] = nil
	cancelBotTimer(p1)
	cancelBotTimer(p2)
	queueUpdate:FireClient(p1, "starting", p2.Name)
	queueUpdate:FireClient(p2, "starting", p1.Name)
	task.delay(0.8, function() startGame(p1, p2, bridge) end)
end

local function joinQueue(player: Player, bridge: number)
	if games[player] or botGames[player] then return end
	if playerBridge[player] then return end

	local q = queues[bridge]
	playerBridge[player] = bridge
	table.insert(q, player)
	queueUpdate:FireClient(player, "waiting", #q)

	if #q >= 2 then
		tryMatch(bridge)
	else
		-- Start bot countdown — fires if no second player shows up in time
		botTimers[player] = task.delay(BOT_WAIT_TIME, function()
			botTimers[player] = nil
			removeFromQueue(player)
			startBotGame(player, bridge)
		end)
	end
end

-- ─── Matchmaking triggers ─────────────────────────────────────────────────────
local function getBridgeNumber(name: string): number
	local digit = name:match("(%d+)%s*$")
	local n = digit and tonumber(digit) or 1
	if n < 1 or n > 3 then n = 1 end
	return n
end

local function setupTrigger(part: BasePart)
	-- Remove any existing prompt first
	local existing = part:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local bridge = getBridgeNumber(part.Name)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText    = "Join Queue"
	prompt.ObjectText    = "Pillow Fight"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration  = 0
	prompt.MaxActivationDistance = 10
	prompt.Parent        = part

	prompt.Triggered:Connect(function(player: Player)
		joinQueue(player, bridge)
	end)
end

local function isPillowTrigger(obj: Instance): boolean
	return obj:IsA("BasePart") and obj.Name:lower():sub(1, 24) == "pillow fight matchmaking"
end

for _, obj in workspace:GetDescendants() do
	if isPillowTrigger(obj) then setupTrigger(obj) end
end
workspace.DescendantAdded:Connect(function(obj)
	if isPillowTrigger(obj) then setupTrigger(obj) end
end)

-- ─── Leave queue ──────────────────────────────────────────────────────────────
leaveQueue.OnServerEvent:Connect(function(player: Player)
	cancelBotTimer(player)
	removeFromQueue(player)
	queueUpdate:FireClient(player, "left")
end)

-- ─── Pillow hit ───────────────────────────────────────────────────────────────
pillowHit.OnServerEvent:Connect(function(player: Player)
	local now = tick()

	-- Bot game hit
	local bData = botGames[player]
	if bData then
		if now - bData.hitCd < HIT_COOLDOWN then return end
		bData.hitCd = now
		local pChar = player.Character
		if not pChar then return end
		local pRoot = pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pRoot then return end
		if (pRoot.Position - bData.botPos).Magnitude > HIT_RANGE then
			hitResult:FireClient(player, "miss", bData.myHp, bData.botHp)
			return
		end
		bData.botHp -= 1
		hitResult:FireClient(player, "hit", bData.myHp, bData.botHp)
		if bData.botHp <= 0 then
			endBotGame(player, true, "knockout")
		end
		return
	end

	-- PvP hit
	local data = games[player]
	if not data then return end
	if now - data.hitCd < HIT_COOLDOWN then return end
	data.hitCd = now

	local opp     = data.opponent
	local oppData = games[opp]
	if not oppData then return end

	local pChar = player.Character
	local oChar = opp.Character
	if not pChar or not oChar then return end

	local pRoot = pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local oRoot = oChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pRoot or not oRoot then return end

	if (pRoot.Position - oRoot.Position).Magnitude > HIT_RANGE then
		hitResult:FireClient(player, "miss", data.myHp, oppData.myHp)
		return
	end

	if oppData.isDodging then
		hitResult:FireClient(player, "dodged", data.myHp, oppData.myHp)
		return
	end

	oppData.myHp -= 1
	local pushDir = (oRoot.Position - pRoot.Position).Unit
	oRoot.AssemblyLinearVelocity = Vector3.new(pushDir.X * KNOCKBACK, 22, pushDir.Z * KNOCKBACK)

	hitResult:FireClient(player, "hit",   data.myHp,  oppData.myHp)
	hitResult:FireClient(opp,    "taken", oppData.myHp, data.myHp)

	if oppData.myHp <= 0 then
		endGame(player, opp, "knockout")
	end
end)

-- ─── Pillow dodge ─────────────────────────────────────────────────────────────
pillowDodge.OnServerEvent:Connect(function(player: Player)
	local now = tick()

	local bData = botGames[player]
	if bData then
		if now - bData.dodgeCd < DODGE_COOLDOWN then return end
		bData.dodgeCd   = now
		bData.isDodging = true
		task.delay(DODGE_DURATION, function()
			if botGames[player] then botGames[player].isDodging = false end
		end)
		return
	end

	local data = games[player]
	if not data then return end
	if now - data.dodgeCd < DODGE_COOLDOWN then return end
	data.dodgeCd   = now
	data.isDodging = true
	task.delay(DODGE_DURATION, function()
		if games[player] then games[player].isDodging = false end
	end)
end)

-- ─── Bot AI: approach + attack ────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt: number)
	for player, bData in botGames do
		local rig = bData.botRig
		if not rig then continue end
		local botRoot = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
		local char    = player.Character
		local pRoot   = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not botRoot or not pRoot then continue end

		local toPlayer       = pRoot.Position - botRoot.Position
		local horizontalDist = Vector3.new(toPlayer.X, 0, toPlayer.Z).Magnitude
		local facing         = CFrame.lookAt(botRoot.Position, Vector3.new(pRoot.Position.X, botRoot.Position.Y, pRoot.Position.Z))

		-- Always close the gap (without overlapping the player)
		local targetPos = botRoot.Position
		local isMoving  = false
		if horizontalDist > BOT_MIN_DISTANCE then
			isMoving = true
			local dir      = Vector3.new(toPlayer.X, 0, toPlayer.Z).Unit
			local moveDist = math.min(BOT_MOVE_SPEED * dt, horizontalDist - BOT_MIN_DISTANCE)
			targetPos = botRoot.Position + dir * moveDist
		end
		rig:PivotTo(CFrame.new(targetPos) * (facing - facing.Position))
		botRoot.AssemblyLinearVelocity = Vector3.zero
		botRoot.AssemblyAngularVelocity = Vector3.zero

		-- Play/stop the walk animation in sync with actual movement
		local humanoidForWalk = rig:FindFirstChildOfClass("Humanoid")
		if humanoidForWalk then
			local walkTrack = bData.botWalkTrack
			if not walkTrack then
				local anim = Instance.new("Animation")
				anim.AnimationId = BOT_WALK_ANIM
				local ok, loaded = pcall(function() return humanoidForWalk:LoadAnimation(anim) end)
				if ok and loaded then
					walkTrack = loaded
					walkTrack.Looped = true
					bData.botWalkTrack = walkTrack
				end
			end
			if walkTrack then
				if isMoving and not walkTrack.IsPlaying then
					walkTrack:Play()
				elseif not isMoving and walkTrack.IsPlaying then
					walkTrack:Stop()
				end
			end
		end

		-- Attack independently of movement, any time the player is within hit range
		if math.floor(tick() * 2) % 10 == 0 then
			print(("[PFBot] dist=%.1f range=%d rig=%s humanoid=%s"):format(
				horizontalDist, HIT_RANGE, tostring(rig and rig.Name),
				tostring(rig and rig:FindFirstChildOfClass("Humanoid") ~= nil)))
		end
		if horizontalDist <= HIT_RANGE then
			local now = tick()
			if now - bData.botAttackCd >= BOT_ATTACK_COOLDOWN then
				print("[PFBot] ATTACKING — dodging:", bData.isDodging)
				bData.botAttackCd = now

				local humanoid = rig:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local track = bData.botHitTrack
					if not track then
						local anim = Instance.new("Animation")
						anim.AnimationId = BOT_HIT_ANIM
						local ok, loaded = pcall(function() return humanoid:LoadAnimation(anim) end)
						if ok and loaded then
							track = loaded
							bData.botHitTrack = track
						end
					end
					if track then
						track:Stop()
						track:Play()
					end
				end

				if bData.isDodging then
					hitResult:FireClient(player, "dodged", bData.myHp, bData.botHp)
				else
					bData.myHp -= 1
					local pushDir = (pRoot.Position - botRoot.Position).Unit
					pRoot.AssemblyLinearVelocity = Vector3.new(pushDir.X * KNOCKBACK, 22, pushDir.Z * KNOCKBACK)
					hitResult:FireClient(player, "taken", bData.myHp, bData.botHp)
					if bData.myHp <= 0 then
						endBotGame(player, false, "knockout")
					end
				end
			end
		end

		bData.botPos = botRoot.Position
	end
end)

-- ─── Fall detection ───────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
	for player, data in games do
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end
		if root.Position.Y < data.spawnCFrame.Position.Y - FALL_THRESHOLD then
			local opp = data.opponent
			if games[opp] then endGame(opp, player, "fell off the bridge") end
		end
	end

	for player, bData in botGames do
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end
		if root.Position.Y < bData.spawnCFrame.Position.Y - FALL_THRESHOLD then
			endBotGame(player, false, "fell off the bridge")
		end
	end
end)

-- ─── Cleanup on disconnect ────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player: Player)
	cancelBotTimer(player)
	removeFromQueue(player)
	local bData = botGames[player]
	if bData then destroyBotRig(bData.botRig) end
	botGames[player] = nil

	local data = games[player]
	if not data then return end
	local opp = data.opponent
	games[player] = nil
	if games[opp] then
		games[opp] = nil
		gameEnd:FireClient(opp, true, player.Name, "opponent disconnected")
		teleportBack(opp)
	end
end)
