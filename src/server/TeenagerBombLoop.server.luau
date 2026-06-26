local Players       = game:GetService("Players")
local ServerStorage  = game:GetService("ServerStorage")

-- ─── Workspace assets ──────────────────────────────────────────────────────────
local arenaSpawner = workspace:WaitForChild("ArenaDragonSpawner") :: Folder
local waitingArea  = workspace:WaitForChild("AreaWaitingSpawn")   :: BasePart
local dragonWall   = workspace:WaitForChild("DragonWall")         :: BasePart
local surfaceGui   = dragonWall:WaitForChild("SurfaceGui")        :: SurfaceGui
local statusText   = surfaceGui:WaitForChild("StatusText")        :: TextLabel
local bombTemplate = ServerStorage:WaitForChild("Bomb")           :: Tool

-- ─── Tuning ────────────────────────────────────────────────────────────────────
local INTERMISSION_TIME   = 15
local ROUND_TIME          = 20
local ELIMINATION_DISPLAY = 3
local WINNER_DISPLAY      = 5
local MIN_PLAYERS         = 2

-- ─── State ─────────────────────────────────────────────────────────────────────
local alivePlayers:   { Player } = {}
local currentBombTool: Tool?     = nil
local roundCancelled              = false

-- ─── Helpers ───────────────────────────────────────────────────────────────────
local function setStatus(text: string)
	statusText.Text = text
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isAlivePlayer(player: Player): boolean
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Only players whose character is physically overlapping AreaWaitingSpawn count.
local function getValidWaitingPlayers(): { Player }
	local found: { Player } = {}
	local seen:  { [Player]: boolean } = {}
	for _, part in workspace:GetPartsInPart(waitingArea) do
		local character = part.Parent
		if not character then continue end
		local player = Players:GetPlayerFromCharacter(character)
		if player and not seen[player] and isAlivePlayer(player) then
			seen[player] = true
			table.insert(found, player)
		end
	end
	return found
end

local function teleportToWaitingArea(player: Player)
	local root = getCharacterRoot(player)
	if not root then return end
	local offset = Vector3.new(math.random(-4, 4), 3, math.random(-4, 4))
	root.CFrame = CFrame.new(waitingArea.Position + offset)
end

local function getArenaSpawnPoints(): { BasePart }
	local points: { BasePart } = {}
	for _, child in arenaSpawner:GetChildren() do
		if child:IsA("BasePart") then table.insert(points, child) end
	end
	return points
end

local function teleportToArena(player: Player)
	local points = getArenaSpawnPoints()
	if #points == 0 then return end
	local point = points[math.random(1, #points)]
	local root  = getCharacterRoot(player)
	if not root then return end
	root.CFrame = CFrame.new(point.Position + Vector3.new(0, 3, 0))
end

local function removeFromAlive(player: Player)
	local idx = table.find(alivePlayers, player)
	if idx then table.remove(alivePlayers, idx) end
end

-- The single live Bomb clone gets reparented directly whenever it's passed
-- (see TeenagerBomb.server.luau), so the current holder must be looked up
-- fresh — it is never the same fixed player for the whole 20s round.
local function getBombHolder(): Player?
	local tool = currentBombTool
	if not tool then return nil end
	local parent = tool.Parent
	if not parent then return nil end
	if parent:IsA("Backpack") then
		local owner = parent.Parent
		if owner and owner:IsA("Player") then return owner end
		return nil
	end
	if parent:IsA("Model") then
		return Players:GetPlayerFromCharacter(parent)
	end
	return nil
end

local function clearBomb()
	if currentBombTool then
		currentBombTool:Destroy()
		currentBombTool = nil
	end
end

local function giveBomb(player: Player): boolean
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return false end

	clearBomb()
	local bomb = bombTemplate:Clone()
	currentBombTool = bomb
	bomb.Parent = character -- direct Parent assignment auto-equips, same mechanic as TeenagerBomb.server.luau
	return true
end

-- Tries random players from the current AlivePlayers pool until one with a
-- valid character actually receives the bomb.
local function chooseAndGiveBomb(): Player?
	local pool = table.clone(alivePlayers)
	while #pool > 0 do
		local idx = math.random(1, #pool)
		local candidate = pool[idx]
		if giveBomb(candidate) then return candidate end
		table.remove(pool, idx)
	end
	return nil
end

local function explodeAt(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 14
	explosion.BlastPressure = 0 -- visual/audio only — no physics force, so nobody gets knocked off the arena
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
end

-- ─── Phase: Intermission ───────────────────────────────────────────────────────
local function runIntermission(): { Player }
	while true do
		local timeLeft = INTERMISSION_TIME
		while timeLeft > 0 do
			setStatus("Menunggu: " .. timeLeft)
			task.wait(1)
			timeLeft -= 1
		end

		local valid = getValidWaitingPlayers()
		if #valid >= MIN_PLAYERS then
			return valid
		end
	end
end

-- ─── Phase: Teleport ───────────────────────────────────────────────────────────
local function startRound(valid: { Player })
	alivePlayers = {}
	for _, player in valid do
		teleportToArena(player)
		table.insert(alivePlayers, player)
	end
end

-- ─── Phase: Round loop ─────────────────────────────────────────────────────────
local function eliminate(player: Player)
	removeFromAlive(player)
	teleportToWaitingArea(player)
	setStatus(player.Name .. " Tereliminasi!")
	task.wait(ELIMINATION_DISPLAY)
end

local function runRoundLoop()
	roundCancelled = false

	while #alivePlayers > 1 and not roundCancelled do
		if not chooseAndGiveBomb() then break end

		local timeLeft = ROUND_TIME
		while timeLeft > 0 do
			if roundCancelled or #alivePlayers <= 1 then break end
			setStatus("Bom meledak: " .. timeLeft)
			task.wait(1)
			timeLeft -= 1
		end

		if roundCancelled or #alivePlayers <= 1 then
			clearBomb()
			break
		end

		local victim     = getBombHolder()
		local victimRoot  = victim and getCharacterRoot(victim)
		if victimRoot then
			explodeAt(victimRoot.Position)
		else
			local handle = currentBombTool and currentBombTool:FindFirstChild("Handle") :: BasePart?
			if handle then explodeAt(handle.Position) end
		end
		clearBomb()

		if victim and table.find(alivePlayers, victim) then
			eliminate(victim)
		end
	end
end

-- ─── Phase: Winner ─────────────────────────────────────────────────────────────
local function finishRound()
	clearBomb()
	if #alivePlayers == 1 then
		local winner = alivePlayers[1]
		setStatus(winner.Name .. " Menang!")
		teleportToWaitingArea(winner)
		task.wait(WINNER_DISPLAY)
	else
		for _, player in alivePlayers do
			teleportToWaitingArea(player)
		end
	end
	alivePlayers = {}
end

-- ─── Edge case: player disconnects mid-round ─────────────────────────────────
Players.PlayerRemoving:Connect(function(player: Player)
	if not table.find(alivePlayers, player) then return end

	local wasHolder = getBombHolder() == player
	removeFromAlive(player)

	if #alivePlayers <= 1 then
		roundCancelled = true
		return
	end

	if wasHolder then
		chooseAndGiveBomb()
	end
end)

-- ─── Main state machine loop ──────────────────────────────────────────────────
while true do
	local valid = runIntermission()
	startRound(valid)
	runRoundLoop()
	finishRound()
end
