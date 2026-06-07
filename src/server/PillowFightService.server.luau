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
local DODGE_COOLDOWN = 2.5
local KNOCKBACK      = 55
local FALL_THRESHOLD = 12
local BOT_WAIT_TIME  = 5   -- seconds alone in queue before bot fills in

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
	spawnCFrame: CFrame,
	hitCd:       number,
	dodgeCd:     number,
}

local queue:      { Player }              = {}
local games:      { [Player]: GameData }  = {}
local botGames:   { [Player]: BotGame }   = {}
local botTimers:  { [Player]: thread }    = {}  -- pending bot countdown per player

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function getSpawns(): (CFrame, CFrame)
	local s1 = workspace:FindFirstChild("PFspawn1", true) :: BasePart?
	local s2 = workspace:FindFirstChild("PFspawn2", true) :: BasePart?
	if s1 and s2 then
		local p1 = s1.Position + Vector3.new(0, 3, 0)
		local p2 = s2.Position + Vector3.new(0, 3, 0)
		return CFrame.lookAt(p1, p2), CFrame.lookAt(p2, p1)
	end
	return CFrame.lookAt(Vector3.new(0, 10, -8), Vector3.new(0, 10, 8)),
	       CFrame.lookAt(Vector3.new(0, 10,  8), Vector3.new(0, 10, -8))
end

local function removeFromQueue(player: Player)
	for i, p in queue do
		if p == player then table.remove(queue, i) return end
	end
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

-- ─── PvP game ─────────────────────────────────────────────────────────────────
local function endGame(winner: Player, loser: Player, reason: string)
	games[winner] = nil
	games[loser]  = nil
	removePillow(winner)
	removePillow(loser)
	gameEnd:FireClient(winner, true,  loser.Name,  reason)
	gameEnd:FireClient(loser,  false, winner.Name, reason)
	teleportBack(winner)
	teleportBack(loser)
end

local function startGame(p1: Player, p2: Player)
	local cf1, cf2 = getSpawns()

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
	botGames[player] = nil
	removePillow(player)
	gameEnd:FireClient(player, won, "BOT", reason)
	teleportBack(player)
end

local function startBotGame(player: Player)
	local cf1, cf2 = getSpawns()
	local char = player.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then root.CFrame = cf1 end
	end
	botGames[player] = {
		myHp        = MAX_HP,
		botHp       = MAX_HP,
		botPos      = cf2.Position,
		spawnCFrame = cf1,
		hitCd       = 0,
		dodgeCd     = 0,
	}
	queueUpdate:FireClient(player, "starting", "BOT")
	task.delay(0.8, function()
		gameStart:FireClient(player, "BOT", MAX_HP)
		givePillow(player)
	end)
end

-- ─── Matchmaking ──────────────────────────────────────────────────────────────
local function tryMatch()
	if #queue < 2 then return end
	local p1 = table.remove(queue, 1)
	local p2 = table.remove(queue, 1)
	cancelBotTimer(p1)
	cancelBotTimer(p2)
	queueUpdate:FireClient(p1, "starting", p2.Name)
	queueUpdate:FireClient(p2, "starting", p1.Name)
	task.delay(0.8, function() startGame(p1, p2) end)
end

local function joinQueue(player: Player)
	if games[player] or botGames[player] then return end
	for _, p in queue do if p == player then return end end
	table.insert(queue, player)
	queueUpdate:FireClient(player, "waiting", #queue)

	if #queue >= 2 then
		tryMatch()
	else
		-- Start bot countdown — fires if no second player shows up in time
		botTimers[player] = task.delay(BOT_WAIT_TIME, function()
			botTimers[player] = nil
			removeFromQueue(player)
			startBotGame(player)
		end)
	end
end

-- ─── Matchmaking triggers ─────────────────────────────────────────────────────
local function setupTrigger(part: BasePart)
	-- Remove any existing prompt first
	local existing = part:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText    = "Join Queue"
	prompt.ObjectText    = "Pillow Fight"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration  = 0
	prompt.MaxActivationDistance = 10
	prompt.Parent        = part

	prompt.Triggered:Connect(function(player: Player)
		joinQueue(player)
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
	local now  = tick()
	local data = games[player]
	if not data then return end
	if now - data.dodgeCd < DODGE_COOLDOWN then return end
	data.dodgeCd   = now
	data.isDodging = true
	task.delay(DODGE_DURATION, function()
		if games[player] then games[player].isDodging = false end
	end)
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
