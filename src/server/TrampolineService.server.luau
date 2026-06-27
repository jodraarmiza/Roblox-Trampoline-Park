local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

-- ─── RemoteEvents ─────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name = "TrampolineRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local styleRequest   = makeRemote("StyleRequest")
local styleApproved  = makeRemote("StyleApproved")
local bounceReward   = makeRemote("BounceReward")
local currencyUpdate = makeRemote("CurrencyUpdate")
local buyStyleEvent  = makeRemote("BuyStyle")
local stylesUpdate   = makeRemote("StylesUpdate")
local gateBlocked    = makeRemote("GateBlocked")
local statsUpdate    = makeRemote("StatsUpdate")
local allocateStat   = makeRemote("AllocateStat")

-- ─── Style catalog ────────────────────────────────────────────────────────────
-- minStyles = jumlah styles yang harus dimiliki sebelum bisa beli
local STYLES = {
	{ id = "Backflip",  name = "Backflip",   price = 100,  minStyles = 0 },
	{ id = "FrontFlip", name = "Front Flip", price = 500,  minStyles = 0 },
	{ id = "SideFlip",  name = "Side Flip",  price = 1000, minStyles = 0 },
	{ id = "StarJump",  name = "Star Jump",  price = 1500, minStyles = 0 },
	{ id = "CanonBall", name = "Canon Ball", price = 2000, minStyles = 0 },
	{ id = "Spin360",    name = "360 Spin",    price = 2500, minStyles = 5 },
	{ id = "Double360",    name = "Double 360",      price = 3000, minStyles = 5 },
	{ id = "Backflip360",  name = "Backflip 360 Spin", price = 3500, minStyles = 5 },
	{ id = "FlatBackflip",  name = "Flat Backflip",  price = 4000, minStyles = 5 },
	{ id = "FlatFrontflip", name = "Flat Frontflip", price = 4500, minStyles = 5 },
	{ id = "Superman",       name = "Superman",        price = 5000, minStyles = 5 },
	{ id = "DoubleBackflip",  name = "Double Backflip",  price = 5500, minStyles = 5 },
	{ id = "DoubleFrontflip", name = "Double Frontflip", price = 6000, minStyles = 5  },
	{ id = "LazyBoy",  name = "Lazy Boy",  price = 6500, minStyles = 10 },
	{ id = "LazyGuy",     name = "Lazy Guy",     price = 7000, minStyles = 10 },
	{ id = "SpinningBump", name = "Spinning Bump", price = 7500, minStyles = 10 },
	{ id = "AtomicDrop", name = "Atomic Drop", price = 8000, minStyles = 10 },
	{ id = "HeadSpin",    name = "Head Spin",    price = 8500, minStyles = 10 },
	{ id = "BodyDismiss", name = "Body Dismiss", price = 9000,  minStyles = 10 },
	{ id = "TheWheel",    name = "The Wheel",    price = 9500,  minStyles = 10 },
}

local STYLE_REWARDS: { [string]: number } = {
	Backflip  = 10, FrontFlip = 15, SideFlip = 20, StarJump = 25, CanonBall = 30, Spin360 = 35, Double360 = 40, Backflip360 = 45, FlatBackflip = 50, FlatFrontflip = 55, Superman = 60, DoubleBackflip = 65, DoubleFrontflip = 70, LazyBoy = 75, LazyGuy = 80, SpinningBump = 85, AtomicDrop = 90, HeadSpin = 95, BodyDismiss = 100, TheWheel = 105,
}

local STYLE_XP: { [string]: number } = {
	Backflip  = 10, FrontFlip = 15, SideFlip = 20, StarJump = 25, CanonBall = 30, Spin360 = 35, Double360 = 40, Backflip360 = 45, FlatBackflip = 50, FlatFrontflip = 55, Superman = 60, DoubleBackflip = 65, DoubleFrontflip = 70, LazyBoy = 75, LazyGuy = 80, SpinningBump = 85, AtomicDrop = 90, HeadSpin = 95, BodyDismiss = 100, TheWheel = 105,
}

-- ─── Gate requirements ────────────────────────────────────────────────────────
local GATE_REQ: { [string]: number } = {
	["Gate kids"]       = 0,
	["Gate teen"]       = 5,
	["Gate Adult"]      = 10,
	["Gate Pro"]        = 15,
	["Gate Playground"] = 999,
}

local GATE_ZONE_NAME: { [string]: string } = {
	["Gate teen"]       = "Teenager",
	["Gate Adult"]      = "Adult",
	["Gate Pro"]        = "Pro",
	["Gate Playground"] = "Playground (Coming Soon)",
}

-- ─── Player data ──────────────────────────────────────────────────────────────
local BOUNCE_REWARD = 10
local BOUNCE_XP     = 2
local MAX_STAT_PTS    = 10  -- max skill points per stat
local HP_BASE         = 3   -- base HP before health stat
local HP_PER_HEALTH   = 2   -- +HP per health point allocated

type StatAlloc = { jumpHeight: number, jumpSpeed: number, styleBonus: number, health: number }

local playerCurrency:   { [number]: number }               = {}
local playerStyles:     { [number]: { [string]: true } }   = {}
local playerXP:         { [number]: number }               = {}
local playerLevel:      { [number]: number }               = {}
local playerSkillPts:   { [number]: number }               = {}
local playerStats:      { [number]: StatAlloc }            = {}
local bounceCooldowns:  { [number]: number }               = {}
local styleCooldowns:   { [number]: { [string]: number } } = {}
local gateCooldowns:    { [number]: number }               = {}

local function xpNeeded(level: number): number
	return level * 100
end

local function styleCount(uid: number): number
	local n = 0
	for _ in playerStyles[uid] or {} do n += 1 end
	return n
end

local function fireStats(player: Player)
	local uid = player.UserId
	statsUpdate:FireClient(player, {
		xp         = playerXP[uid],
		xpNeeded   = xpNeeded(playerLevel[uid]),
		level      = playerLevel[uid],
		skillPts   = playerSkillPts[uid],
		stats      = playerStats[uid],
	})
end

local function addCurrency(player: Player, amount: number)
	local uid = player.UserId
	playerCurrency[uid] = (playerCurrency[uid] or 0) + amount
	currencyUpdate:FireClient(player, playerCurrency[uid])
end

-- ─── Cross-script currency awards (e.g. minigame wins) ───────────────────────
local awardCurrency = Instance.new("BindableEvent")
awardCurrency.Name   = "AwardCurrency"
awardCurrency.Parent = ServerStorage

awardCurrency.Event:Connect(function(player: Player, amount: number)
	if not (playerCurrency[player.UserId]) then return end
	addCurrency(player, amount)
end)

-- ─── Cross-script currency spend (e.g. item shop purchases) ─────────────────
local spendCurrency = Instance.new("BindableFunction")
spendCurrency.Name   = "SpendCurrency"
spendCurrency.Parent = ServerStorage

spendCurrency.OnInvoke = function(player: Player, amount: number): boolean
	local uid = player.UserId
	if (playerCurrency[uid] or 0) < amount then return false end
	playerCurrency[uid] -= amount
	currencyUpdate:FireClient(player, playerCurrency[uid])
	return true
end

-- ─── Cross-script max-HP query (used by PillowFightService) ──────────────────
local getPlayerMaxHp = Instance.new("BindableFunction")
getPlayerMaxHp.Name   = "GetPlayerMaxHp"
getPlayerMaxHp.Parent = ServerStorage

getPlayerMaxHp.OnInvoke = function(player: Player): number
	local stats = playerStats[player.UserId]
	return HP_BASE + ((stats and stats.health) or 0) * HP_PER_HEALTH
end

local function addXP(player: Player, amount: number)
	local uid = player.UserId
	playerXP[uid] += amount
	-- level up loop
	while playerXP[uid] >= xpNeeded(playerLevel[uid]) do
		playerXP[uid]       -= xpNeeded(playerLevel[uid])
		playerLevel[uid]    += 1
		playerSkillPts[uid] += 1
	end
	fireStats(player)
end

local function initPlayer(player: Player)
	local uid = player.UserId
	playerCurrency[uid]  = 100000  -- DEV: start dengan 100k untuk testing
	playerStyles[uid]    = {}
	playerXP[uid]        = 0
	playerLevel[uid]     = 1
	playerSkillPts[uid]  = 0
	playerStats[uid]     = { jumpHeight = 0, jumpSpeed = 0, styleBonus = 0, health = 0 }
	currencyUpdate:FireClient(player, playerCurrency[uid])
	stylesUpdate:FireClient(player, {})
	fireStats(player)
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	playerCurrency[uid]  = nil
	playerStyles[uid]    = nil
	playerXP[uid]        = nil
	playerLevel[uid]     = nil
	playerSkillPts[uid]  = nil
	playerStats[uid]     = nil
	bounceCooldowns[uid] = nil
	styleCooldowns[uid]  = nil
	gateCooldowns[uid]   = nil
end)
for _, p in Players:GetPlayers() do initPlayer(p) end

-- ─── Bounce reward ────────────────────────────────────────────────────────────
bounceReward.OnServerEvent:Connect(function(player: Player)
	local now = tick()
	local uid = player.UserId
	if bounceCooldowns[uid] and now - bounceCooldowns[uid] < 0.3 then return end
	bounceCooldowns[uid] = now
	addCurrency(player, BOUNCE_REWARD)
	addXP(player, BOUNCE_XP)
end)

-- ─── Style trigger ────────────────────────────────────────────────────────────
styleRequest.OnServerEvent:Connect(function(player: Player, styleId: string)
	local now = tick()
	local uid = player.UserId

	if not styleCooldowns[uid] then styleCooldowns[uid] = {} end
	if styleCooldowns[uid][styleId] and now - styleCooldowns[uid][styleId] < 0.8 then return end

	local character = player.Character
	if not character then return end
	local root     = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	if humanoid.Health <= 0 then return end
	if root.AssemblyLinearVelocity.Y < -10 then return end
	if not (playerStyles[uid] and playerStyles[uid][styleId]) then return end

	styleCooldowns[uid][styleId] = now

	-- Style bonus multiplier dari stats
	local bonus = 1 + (playerStats[uid].styleBonus * 0.1)
	local reward = math.round((STYLE_REWARDS[styleId] or 10) * bonus)

	styleApproved:FireClient(player, styleId)
	addCurrency(player, reward)
	addXP(player, STYLE_XP[styleId] or 10)
end)

-- ─── Buy style ────────────────────────────────────────────────────────────────
buyStyleEvent.OnServerEvent:Connect(function(player: Player, styleId: string)
	local uid = player.UserId
	local style = nil
	for _, s in STYLES do
		if s.id == styleId then style = s break end
	end
	if not style then return end
	if playerStyles[uid][styleId] then return end
	if (playerCurrency[uid] or 0) < style.price then return end
	if styleCount(uid) < (style.minStyles or 0) then return end  -- zone requirement

	playerCurrency[uid] -= style.price
	playerStyles[uid][styleId] = true
	currencyUpdate:FireClient(player, playerCurrency[uid])
	stylesUpdate:FireClient(player, playerStyles[uid])
end)

-- ─── Allocate skill point ─────────────────────────────────────────────────────
allocateStat.OnServerEvent:Connect(function(player: Player, statName: string)
	local uid = player.UserId
	if playerSkillPts[uid] <= 0 then return end
	local stats = playerStats[uid]
	if stats[statName] == nil then return end
	if stats[statName] >= MAX_STAT_PTS then return end

	playerSkillPts[uid] -= 1
	stats[statName]     += 1
	fireStats(player)
end)

-- ─── Gate system ──────────────────────────────────────────────────────────────
local function setupGate(gate: BasePart)
	local req = GATE_REQ[gate.Name]
	if req == nil or req == 0 then return end

	gate.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local uid   = player.UserId
		local owned = styleCount(uid)
		if owned >= req then return end

		local now = tick()
		if gateCooldowns[uid] and now - gateCooldowns[uid] < 1 then return end
		gateCooldowns[uid] = now

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end

		local pushDir = Vector3.new(
			root.Position.X - gate.Position.X, 0,
			root.Position.Z - gate.Position.Z
		).Unit
		root.CFrame = CFrame.new(root.Position + pushDir * 6)
		root.AssemblyLinearVelocity = Vector3.new(pushDir.X * 25, 5, pushDir.Z * 25)

		local zoneName = GATE_ZONE_NAME[gate.Name] or gate.Name
		gateBlocked:FireClient(player, zoneName, req, owned)
	end)
end

for _, obj in workspace:GetDescendants() do
	if obj:IsA("BasePart") and GATE_REQ[obj.Name] then setupGate(obj) end
end
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and GATE_REQ[obj.Name] then setupGate(obj) end
end)
