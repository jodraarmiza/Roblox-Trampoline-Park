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

local styleRequest     = makeRemote("StyleRequest")    -- client minta trigger style
local styleApproved    = makeRemote("StyleApproved")   -- server approve + kirim styleId
local bounceReward     = makeRemote("BounceReward")
local currencyUpdate   = makeRemote("CurrencyUpdate")
local buyStyleEvent    = makeRemote("BuyStyle")
local stylesUpdate     = makeRemote("StylesUpdate")
local gateBlocked      = makeRemote("GateBlocked")

-- ─── Style catalog ────────────────────────────────────────────────────────────
local STYLES = {
	{ id = "Backflip",  name = "Backflip",   price = 100  },
	{ id = "FrontFlip", name = "Front Flip", price = 500  },
	{ id = "SideFlip",  name = "Side Flip",  price = 1000 },
}

-- ─── Gate requirements (jumlah styles yang harus dimiliki) ───────────────────
local GATE_REQ: { [string]: number } = {
	["Gate kids"]       = 0,    -- gratis, semua bisa masuk
	["Gate teen"]       = 5,    -- butuh 5 styles
	["Gate Adult"]      = 10,
	["Gate Pro"]        = 15,
	["Gate Playground"] = 999,  -- locked for now
}

local GATE_ZONE_NAME: { [string]: string } = {
	["Gate teen"]       = "Teenager",
	["Gate Adult"]      = "Adult",
	["Gate Pro"]        = "Pro",
	["Gate Playground"] = "Playground (Coming Soon)",
}

-- ─── Player data ──────────────────────────────────────────────────────────────
local BOUNCE_REWARD = 10
local STYLE_REWARDS: { [string]: number } = {
	Backflip  = 10,
	FrontFlip = 15,
	SideFlip  = 20,
}

local playerCurrency:  { [number]: number }            = {}
local playerStyles:    { [number]: { [string]: true } } = {}
local bounceCooldowns: { [number]: number }            = {}
local styleCooldowns:  { [number]: { [string]: number } } = {}
local gateCooldowns:   { [number]: number }               = {}

local function styleCount(uid: number): number
	local n = 0
	for _ in playerStyles[uid] or {} do n += 1 end
	return n
end

local function addCurrency(player: Player, amount: number)
	local uid = player.UserId
	playerCurrency[uid] = (playerCurrency[uid] or 0) + amount
	currencyUpdate:FireClient(player, playerCurrency[uid])
end

local function initPlayer(player: Player)
	local uid = player.UserId
	playerCurrency[uid] = 0
	playerStyles[uid]   = {}
	currencyUpdate:FireClient(player, 0)
	stylesUpdate:FireClient(player, {})
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	playerCurrency[uid]  = nil
	playerStyles[uid]    = nil
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
end)

-- ─── Generic style trigger ────────────────────────────────────────────────────
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
	styleApproved:FireClient(player, styleId)
	addCurrency(player, STYLE_REWARDS[styleId] or 10)
end)

-- ─── Style purchase ────────────────────────────────────────────────────────────
buyStyleEvent.OnServerEvent:Connect(function(player: Player, styleId: string)
	local uid = player.UserId
	local style = nil
	for _, s in STYLES do
		if s.id == styleId then style = s break end
	end
	if not style then return end
	if playerStyles[uid][styleId] then return end  -- sudah punya
	if (playerCurrency[uid] or 0) < style.price then return end  -- ga cukup duit

	playerCurrency[uid] -= style.price
	playerStyles[uid][styleId] = true
	currencyUpdate:FireClient(player, playerCurrency[uid])
	stylesUpdate:FireClient(player, playerStyles[uid])
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

		local uid  = player.UserId
		local owned = styleCount(uid)
		if owned >= req then return end  -- boleh masuk

		-- Cooldown biar tidak spam push
		local now = tick()
		if gateCooldowns[uid] and now - gateCooldowns[uid] < 1 then return end
		gateCooldowns[uid] = now

		-- Push player balik
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end

		local pushDir = Vector3.new(
			root.Position.X - gate.Position.X,
			0,
			root.Position.Z - gate.Position.Z
		).Unit
		root.CFrame = CFrame.new(root.Position + pushDir * 6)
		root.AssemblyLinearVelocity = Vector3.new(pushDir.X * 25, 5, pushDir.Z * 25)

		-- Notif ke client
		local zoneName = GATE_ZONE_NAME[gate.Name] or gate.Name
		gateBlocked:FireClient(player, zoneName, req, owned)
	end)
end

for _, obj in workspace:GetDescendants() do
	if obj:IsA("BasePart") and GATE_REQ[obj.Name] then
		setupGate(obj)
	end
end
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and GATE_REQ[obj.Name] then
		setupGate(obj)
	end
end)
