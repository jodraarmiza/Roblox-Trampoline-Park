local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- ─── RemoteEvents ─────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name = "ItemShopRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local buyItemEvent    = makeRemote("BuyItem")
local itemBuffsUpdate = makeRemote("ItemBuffsUpdate")
local itemPurchased   = makeRemote("ItemPurchased")

-- ─── Catalog (subset — tambah item lain di sini nanti) ───────────────────────
-- Currency items: dibeli pakai in-game coins, efeknya sementara (buff + durasi)
local CURRENCY_ITEMS = {
	{ id = "TrampolineSocks", name = "Trampoline Socks", price = 2000,
	  buffType = "jumpPower", value = 0.05, duration = 300 },
	{ id = "EnergyDrink", name = "Energy Drink", price = 800,
	  buffType = "speed", value = 8, duration = 60 },
}

-- Robux items: gamepass, efeknya permanen begitu dimiliki.
-- gamepassId = 0 artinya belum dikonfigurasi di Roblox website — ganti nanti.
local GAMEPASS_ITEMS = {
	{ id = "SuperSpringShoes", name = "Super Spring Shoes", gamepassId = 0,
	  buffType = "jumpPower", value = 0.25 },
}

local spendCurrency = ServerStorage:WaitForChild("SpendCurrency") :: BindableFunction

-- ─── Player state ─────────────────────────────────────────────────────────────
type ActiveBuff = { buffType: string, value: number, expiresAt: number }

local activeBuffs:     { [number]: { ActiveBuff } }        = {}
local ownedGamepasses: { [number]: { [string]: true } }    = {}

local function pruneExpired(uid: number)
	local list = activeBuffs[uid]
	if not list then return end
	local now = tick()
	for i = #list, 1, -1 do
		if list[i].expiresAt <= now then table.remove(list, i) end
	end
end

local function computeMultipliers(uid: number): (number, number)
	local jumpPowerMult = 1
	local speedBonus = 0

	for _, buff in activeBuffs[uid] or {} do
		if buff.buffType == "jumpPower" then jumpPowerMult += buff.value
		elseif buff.buffType == "speed" then speedBonus += buff.value end
	end
	for _, item in GAMEPASS_ITEMS do
		if ownedGamepasses[uid] and ownedGamepasses[uid][item.id] then
			if item.buffType == "jumpPower" then jumpPowerMult += item.value
			elseif item.buffType == "speed" then speedBonus += item.value end
		end
	end

	return jumpPowerMult, speedBonus
end

local function fireBuffsUpdate(player: Player)
	local uid = player.UserId
	pruneExpired(uid)
	local jumpPowerMult, speedBonus = computeMultipliers(uid)
	itemBuffsUpdate:FireClient(player, jumpPowerMult, speedBonus)
end

local function addTimedBuff(player: Player, item)
	local uid = player.UserId
	activeBuffs[uid] = activeBuffs[uid] or {}
	pruneExpired(uid)
	table.insert(activeBuffs[uid], {
		buffType  = item.buffType,
		value     = item.value,
		expiresAt = tick() + item.duration,
	})
	fireBuffsUpdate(player)

	task.delay(item.duration, function()
		local p = Players:GetPlayerByUserId(uid)
		if p then fireBuffsUpdate(p) end
	end)
end

Players.PlayerAdded:Connect(function(player: Player)
	local uid = player.UserId
	activeBuffs[uid] = {}
	ownedGamepasses[uid] = {}

	for _, item in GAMEPASS_ITEMS do
		if item.gamepassId and item.gamepassId > 0 then
			task.spawn(function()
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, uid, item.gamepassId)
				if ok and owns then
					ownedGamepasses[uid][item.id] = true
					fireBuffsUpdate(player)
				end
			end)
		end
	end

	fireBuffsUpdate(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local uid = player.UserId
	activeBuffs[uid] = nil
	ownedGamepasses[uid] = nil
end)

-- ─── Buy currency item ────────────────────────────────────────────────────────
buyItemEvent.OnServerEvent:Connect(function(player: Player, itemId: string)
	local item = nil
	for _, it in CURRENCY_ITEMS do
		if it.id == itemId then item = it break end
	end
	if not item then return end

	local ok = spendCurrency:Invoke(player, item.price)
	if not ok then return end

	addTimedBuff(player, item)
	itemPurchased:FireClient(player, item.id, item.name)
end)

-- ─── Gamepass purchase ────────────────────────────────────────────────────────
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamepassId: number, wasPurchased: boolean)
	if not wasPurchased then return end
	for _, item in GAMEPASS_ITEMS do
		if item.gamepassId == gamepassId then
			ownedGamepasses[player.UserId] = ownedGamepasses[player.UserId] or {}
			ownedGamepasses[player.UserId][item.id] = true
			fireBuffsUpdate(player)
			itemPurchased:FireClient(player, item.id, item.name)
		end
	end
end)
