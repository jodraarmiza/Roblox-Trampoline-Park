local Players       = game:GetService("Players")
local ServerStorage  = game:GetService("ServerStorage")

-- ─── Workspace assets ──────────────────────────────────────────────────────────
-- ArenaDragonSpawner directly contains many BaseParts that are ALL named
-- "DragonArenaSpawn" (duplicated, never renamed) — GetChildren() returns every
-- one of them regardless of the shared name; one gets picked at random below.
local arenaSpawner = workspace:WaitForChild("ArenaDragonSpawner")
local waitingArea   = workspace:WaitForChild("AreaWaitingSpawn") :: BasePart
-- Exact-name match — does NOT match the decorative "DragonWalls" (plural) props.
local dragonWall         = workspace:WaitForChild("DragonWall") :: BasePart
local timerGui           = dragonWall:WaitForChild("TeenagerTimerGui") :: SurfaceGui
local statusText         = timerGui:WaitForChild("StatusText") :: TextLabel
local bombTemplate       = ServerStorage:WaitForChild("Bomb") :: Tool

-- ─── Tuning ────────────────────────────────────────────────────────────────────
local INTERMISSION_TIME   = 15
local ROUND_TIME          = 20
local ELIMINATION_DISPLAY = 3
local WINNER_DISPLAY      = 5
local MIN_PLAYERS         = 2

local BLINK_FLASH_DURATION = 0.12 -- how long the red/neon flash itself stays on
local BLINK_MAX_INTERVAL   = 0.6  -- gap between blinks when the round just started (calm)
local BLINK_MIN_INTERVAL   = 0.1  -- gap between blinks right before it explodes (panic)

-- ─── State ─────────────────────────────────────────────────────────────────────
local alivePlayers:   { Player } = {}
local currentBombTool: Tool?     = nil
local roundCancelled              = false
local bombTimeLeft                = 0 -- seconds left in the current round, read by the blink task for pacing
local blinkGeneration             = 0 -- bumped on every start/stop so stale blink tasks self-terminate

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
	local randomSpawn = points[math.random(1, #points)]
	local character = player.Character
	if not character then return end
	character:PivotTo(randomSpawn.CFrame + Vector3.new(0, 5, 0))
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

-- ─── Bomb blink effect ─────────────────────────────────────────────────────────
-- The Handle lives inside the Tool, so it travels along automatically no
-- matter who currently holds the bomb (or whether it just got passed via
-- TeenagerBomb.server.luau's Touched hand-off) — no need to resolve the
-- holder's character, just read the live Tool reference each cycle.
local function blinkInterval(): number
	local progress = math.clamp(bombTimeLeft / ROUND_TIME, 0, 1) -- 1 = round just started, 0 = about to explode
	return BLINK_MIN_INTERVAL + (BLINK_MAX_INTERVAL - BLINK_MIN_INTERVAL) * progress
end

local function startBombBlink()
	blinkGeneration += 1
	local myGeneration = blinkGeneration

	task.spawn(function()
		while blinkGeneration == myGeneration do
			local tool   = currentBombTool
			local handle = tool and tool:FindFirstChild("Handle") :: BasePart?

			if handle and handle.Parent then
				local originalColor    = handle.Color
				local originalMaterial = handle.Material

				handle.Color    = Color3.new(1, 0, 0)
				handle.Material = Enum.Material.Neon
				task.wait(BLINK_FLASH_DURATION)

				-- Re-check — the round may have ended or the bomb been swapped mid-flash.
				if handle.Parent then
					handle.Color    = originalColor
					handle.Material = originalMaterial
				end
			else
				task.wait(0.1) -- bomb not handed off yet — retry shortly
			end

			if blinkGeneration == myGeneration then
				task.wait(blinkInterval())
			end
		end
	end)
end

-- Bumping the generation makes any in-flight blink task notice and stop on
-- its own next check, restoring the Handle's appearance before it exits.
local function stopBombBlink()
	blinkGeneration += 1
end

-- ─── Phase: Intermission ───────────────────────────────────────────────────────
local function runIntermission(): { Player }
	while true do
		local timeLeft = INTERMISSION_TIME
		while timeLeft > 0 do
			setStatus("Waiting: " .. timeLeft)
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
		bombTimeLeft = timeLeft
		startBombBlink()

		while timeLeft > 0 do
			if roundCancelled or #alivePlayers <= 1 then break end
			setStatus("Bom Explode: " .. timeLeft)
			task.wait(1)
			timeLeft -= 1
			bombTimeLeft = timeLeft
		end

		stopBombBlink() -- always stop before the bomb can explode or the round can end

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
