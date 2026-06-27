local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local InsertService      = game:GetService("InsertService")

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

local buyItemEvent      = makeRemote("BuyItem")
local itemBuffsUpdate   = makeRemote("ItemBuffsUpdate")
local itemPurchased     = makeRemote("ItemPurchased")
local activeBuffsUpdate = makeRemote("ActiveBuffsUpdate")

-- ─── Catalog (subset — tambah item lain di sini nanti) ───────────────────────
-- accessoryId = 0 artinya belum ada accessory asset — ganti nanti supaya item
-- kelihatan kepasang di karakter (Humanoid:AddAccessory), bukan cuma buff stat.
-- Kalau assetnya bukan Accessory (cuma Model/MeshPart mentah), dia di-weld
-- manual ke attachTo (default "RightFoot") pakai offset — tweak offset per
-- item sampai posisinya pas.
-- Currency items: dibeli pakai in-game coins, efeknya sementara (buff + durasi)
local CURRENCY_ITEMS = {
	{ id = "TrampolineSocks", name = "Trampoline Socks", price = 2000,
	  buffType = "jumpPower", value = 0.05, duration = 300, accessoryId = 8439707254,
	  attachTo = "RightFoot", offset = CFrame.new(0, 0, 0) },
	{ id = "EnergyDrink", name = "Energy Drink", price = 800,
	  buffType = "speed", value = 8, duration = 60, accessoryId = 0 },
}

-- Robux items: gamepass, efeknya permanen begitu dimiliki.
-- gamepassId = 0 artinya belum dikonfigurasi di Roblox website — ganti nanti.
local GAMEPASS_ITEMS = {
	{ id = "SuperSpringShoes", name = "Super Spring Shoes", gamepassId = 0,
	  buffType = "jumpPower", value = 0.25, accessoryId = 0 },
}

local spendCurrency = ServerStorage:WaitForChild("SpendCurrency") :: BindableFunction

-- ─── Player state ─────────────────────────────────────────────────────────────
type ActiveBuff = { id: string, name: string, buffType: string, value: number, expiresAt: number }

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

-- ─── Fallback: weld manual kalau asset bukan Accessory class ────────────────
-- Dipakai saat asset cuma Model/MeshPart mentah (belum dirigging jadi
-- Accessory). Tempel ke attachTo (default RightFoot) pakai offset dari item.
local function weldRawModel(character: Model, model: Model, item, tagName: string)
	local attachPartName = item.attachTo or "RightFoot"
	local targetPart = character:FindFirstChild(attachPartName) :: BasePart?
	if not targetPart then
		warn(("[ItemShop] Body part \"%s\" tidak ada di karakter, gagal weld %s"):format(attachPartName, item.id))
		model:Destroy()
		return
	end

	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then
		warn(("[ItemShop] Asset %s tidak punya BasePart sama sekali"):format(item.id))
		model:Destroy()
		return
	end

	local container = Instance.new("Model")
	container.Name = tagName
	for _, p in parts do
		p.Anchored    = false
		p.CanCollide  = false
		p.CanQuery    = false
		p.Massless    = true
		p.Parent      = container
	end
	container.PrimaryPart = parts[1]
	container.Parent = character
	container:PivotTo(targetPart.CFrame * (item.offset or CFrame.new()))

	for _, p in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = targetPart
		weld.Part1 = p
		weld.Parent = p
	end

	print(("[ItemShop] %s di-weld manual ke %s (bukan Accessory asli — tweak offset di catalog kalau posisinya kurang pas)"):format(item.id, attachPartName))
end

-- ─── Visual equip (Accessory) ─────────────────────────────────────────────────
-- Item yang punya accessoryId valid akan kepasang ke karakter (server-side,
-- jadi kelihatan juga di player lain), dilepas lagi saat buff habis/respawn.
local function equipItemAccessory(player: Player, item)
	if not item.accessoryId or item.accessoryId <= 0 then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local tagName = "ItemBuff_" .. item.id
	if character:FindFirstChild(tagName) then return end

	task.spawn(function()
		local ok, model = pcall(function()
			return InsertService:LoadAsset(item.accessoryId)
		end)
		if not ok then
			warn(("[ItemShop] LoadAsset gagal untuk %s (id %d): %s"):format(item.id, item.accessoryId, tostring(model)))
			return
		end
		if not model then
			warn(("[ItemShop] LoadAsset tidak mengembalikan model untuk %s (id %d)"):format(item.id, item.accessoryId))
			return
		end

		local accessory = model:FindFirstChildOfClass("Accessory")
		if not accessory then
			weldRawModel(character, model, item, tagName)
			return
		end

		if character.Parent and humanoid.Parent then
			accessory.Name = tagName
			humanoid:AddAccessory(accessory)
			print(("[ItemShop] %s berhasil dipasang ke %s"):format(item.id, player.Name))
		end
		model:Destroy()
	end)
end

local function unequipItemAccessory(player: Player, item)
	local character = player.Character
	if not character then return end
	local existing = character:FindFirstChild("ItemBuff_" .. item.id)
	if existing then existing:Destroy() end
end

local function applyAllActiveVisuals(player: Player)
	local uid = player.UserId
	for _, buff in activeBuffs[uid] or {} do
		for _, item in CURRENCY_ITEMS do
			if item.id == buff.id then equipItemAccessory(player, item) end
		end
	end
	for _, item in GAMEPASS_ITEMS do
		if ownedGamepasses[uid] and ownedGamepasses[uid][item.id] then
			equipItemAccessory(player, item)
		end
	end
end

local function fireActiveBuffsList(player: Player)
	local uid = player.UserId
	pruneExpired(uid)
	local list = {}
	for _, buff in activeBuffs[uid] or {} do
		table.insert(list, { id = buff.id, name = buff.name, expiresAt = buff.expiresAt })
	end
	activeBuffsUpdate:FireClient(player, list)
end

local function addTimedBuff(player: Player, item)
	local uid = player.UserId
	activeBuffs[uid] = activeBuffs[uid] or {}
	pruneExpired(uid)
	table.insert(activeBuffs[uid], {
		id        = item.id,
		name      = item.name,
		buffType  = item.buffType,
		value     = item.value,
		expiresAt = tick() + item.duration,
	})
	fireBuffsUpdate(player)
	fireActiveBuffsList(player)
	equipItemAccessory(player, item)

	task.delay(item.duration, function()
		local p = Players:GetPlayerByUserId(uid)
		if p then
			fireBuffsUpdate(p)
			fireActiveBuffsList(p)
			unequipItemAccessory(p, item)
		end
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
	fireActiveBuffsList(player)

	player.CharacterAdded:Connect(function()
		task.wait(0.2)  -- biarkan Humanoid ter-load dulu
		applyAllActiveVisuals(player)
	end)
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
			equipItemAccessory(player, item)
			itemPurchased:FireClient(player, item.id, item.name)
		end
	end
end)
