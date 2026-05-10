local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local backflipEvent    = makeRemote("BackflipRequest")
local backflipApproved = makeRemote("BackflipApproved")
local bounceReward     = makeRemote("BounceReward")
local currencyUpdate   = makeRemote("CurrencyUpdate")

-- ─── Currency ─────────────────────────────────────────────────────────────────
local BOUNCE_REWARD   = 10
local BACKFLIP_REWARD = 10

local playerCurrency: { [number]: number } = {}
local bounceCooldowns: { [number]: number } = {}
local backflipCooldowns: { [number]: number } = {}

local function addCurrency(player: Player, amount: number)
	local uid = player.UserId
	playerCurrency[uid] = (playerCurrency[uid] or 0) + amount
	currencyUpdate:FireClient(player, playerCurrency[uid])
end

local function initPlayer(player: Player)
	playerCurrency[player.UserId] = 0
	currencyUpdate:FireClient(player, 0)
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	playerCurrency[player.UserId]     = nil
	bounceCooldowns[player.UserId]    = nil
	backflipCooldowns[player.UserId]  = nil
end)
for _, player in Players:GetPlayers() do
	initPlayer(player)
end

-- ─── Bounce reward ────────────────────────────────────────────────────────────
bounceReward.OnServerEvent:Connect(function(player: Player)
	local now = tick()
	local uid = player.UserId
	-- Cooldown 0.3s mencegah spam dari client
	if bounceCooldowns[uid] and now - bounceCooldowns[uid] < 0.3 then return end
	bounceCooldowns[uid] = now
	addCurrency(player, BOUNCE_REWARD)
end)

-- ─── Backflip ─────────────────────────────────────────────────────────────────
backflipEvent.OnServerEvent:Connect(function(player: Player)
	local now = tick()
	local uid = player.UserId
	if backflipCooldowns[uid] and now - backflipCooldowns[uid] < 0.8 then return end

	local character = player.Character
	if not character then return end
	local root     = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	if humanoid.Health <= 0 then return end
	if root.AssemblyLinearVelocity.Y < -10 then return end

	backflipCooldowns[uid] = now
	backflipApproved:FireClient(player)
	addCurrency(player, BACKFLIP_REWARD)
end)
