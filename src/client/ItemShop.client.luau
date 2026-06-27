local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes           = ReplicatedStorage:WaitForChild("ItemShopRemotes")
local buyItemEvent       = remotes:WaitForChild("BuyItem")
local itemPurchased      = remotes:WaitForChild("ItemPurchased")
local activeBuffsUpdate  = remotes:WaitForChild("ActiveBuffsUpdate")

-- ─── Catalog (subset — harus sinkron dengan ItemShopService) ─────────────────
local CURRENCY_ITEMS = {
	{ id = "TrampolineSocks", name = "Trampoline Socks", desc = "+5% jump power selama 5 menit", price = 2000, icon = "rbxassetid://0" },
	{ id = "EnergyDrink",     name = "Energy Drink",     desc = "+8 walk speed selama 60 detik",  price = 800,  icon = "rbxassetid://0" },
}

local GAMEPASS_ITEMS = {
	{ id = "SuperSpringShoes", name = "Super Spring Shoes", desc = "+25% jump power, permanen", gamepassId = 0, icon = "rbxassetid://0" },
}

-- ─── Util ────────────────────────────────────────────────────────────────────
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(80,80,80)
	s.Thickness = thickness or 1.5
	s.Parent = parent
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.Size               = props.size or UDim2.new(1,0,0,20)
	l.Position           = props.pos  or UDim2.new(0,0,0,0)
	l.BackgroundTransparency = 1
	l.Text               = props.text or ""
	l.TextSize           = props.fs   or 14
	l.Font               = props.font or Enum.Font.Gotham
	l.TextColor3         = props.color or Color3.fromRGB(255,255,255)
	l.TextXAlignment     = props.align or Enum.TextXAlignment.Left
	l.TextWrapped        = props.wrap  or false
	l.Parent             = parent
	return l
end

-- ─── ScreenGui ───────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "ItemShopGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 360, 0, 420)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 16)
stroke(panel, Color3.fromRGB(60,60,80), 1.5)

local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1,0,0,48)
headerFrame.BackgroundColor3 = Color3.fromRGB(20,20,28)
headerFrame.BorderSizePixel = 0
headerFrame.Parent = panel
corner(headerFrame, 16)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1,0,0,16)
headerFix.Position = UDim2.new(0,0,1,-16)
headerFix.BackgroundColor3 = Color3.fromRGB(20,20,28)
headerFix.BorderSizePixel = 0
headerFix.Parent = headerFrame

label(headerFrame, { text = "🛒  Item Shop", pos = UDim2.new(0,16,0,0), size = UDim2.new(1,-50,1,0),
	fs = 18, font = Enum.Font.GothamBold, color = Color3.fromRGB(80,200,255) })

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0,32,0,32)
closeBtn.Position = UDim2.new(1,-40,0.5,-16)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(160,160,160)
closeBtn.Parent = headerFrame
closeBtn.MouseButton1Click:Connect(function() panel.Visible = false end)

local contentFrame = Instance.new("ScrollingFrame")
contentFrame.Size = UDim2.new(1,-24,1,-56)
contentFrame.Position = UDim2.new(0,12,0,52)
contentFrame.BackgroundTransparency = 1
contentFrame.BorderSizePixel = 0
contentFrame.ScrollBarThickness = 4
contentFrame.ScrollBarImageColor3 = Color3.fromRGB(80,80,100)
contentFrame.CanvasSize = UDim2.new(0,0,0,0)
contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrame.Parent = panel

local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0,10)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Parent = contentFrame

local function makeSectionHeader(text: string, color: Color3, order: number)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1,0,0,30)
	header.BackgroundColor3 = Color3.fromRGB(18,18,26)
	header.BorderSizePixel = 0
	header.LayoutOrder = order
	header.Parent = contentFrame
	corner(header, 8)

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0,4,1,-8)
	accent.Position = UDim2.new(0,0,0,4)
	accent.BackgroundColor3 = color
	accent.BorderSizePixel = 0
	accent.Parent = header
	corner(accent, 2)

	label(header, { text = text, pos = UDim2.new(0,10,0,0), size = UDim2.new(1,-14,1,0),
		fs = 13, font = Enum.Font.GothamBold, color = color })
end

local function makeItemCard(name: string, desc: string, order: number, iconId: string?)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1,0,0,68)
	card.BackgroundColor3 = Color3.fromRGB(24,24,32)
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = contentFrame
	corner(card, 10)

	-- Icon box — placeholder "?" sampai iconId asli dipasang
	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.new(0,48,0,48)
	iconBox.Position = UDim2.new(0,10,0.5,-24)
	iconBox.BackgroundColor3 = Color3.fromRGB(40,40,52)
	iconBox.BorderSizePixel = 0
	iconBox.Parent = card
	corner(iconBox, 8)

	if iconId and iconId ~= "" and iconId ~= "rbxassetid://0" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1,0,1,0)
		img.BackgroundTransparency = 1
		img.Image = iconId
		img.Parent = iconBox
		corner(img, 8)
	else
		label(iconBox, { text = "?", pos = UDim2.new(0,0,0,0), size = UDim2.new(1,0,1,0),
			fs = 20, font = Enum.Font.GothamBold, color = Color3.fromRGB(110,110,130),
			align = Enum.TextXAlignment.Center })
	end

	label(card, { text = name, pos = UDim2.new(0,68,0,8), size = UDim2.new(1,-168,0,22),
		fs = 15, font = Enum.Font.GothamBold })
	label(card, { text = desc, pos = UDim2.new(0,68,0,32), size = UDim2.new(1,-168,0,18),
		fs = 12, color = Color3.fromRGB(150,150,160) })

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0,90,0,34)
	btn.Position = UDim2.new(1,-100,0.5,-17)
	btn.BorderSizePixel = 0
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.Parent = card
	corner(btn, 8)

	return btn
end

local function buildPanel()
	for _, c in contentFrame:GetChildren() do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end

	local order = 0

	order += 1
	makeSectionHeader("💰  Coin Items", Color3.fromRGB(255,200,0), order)
	for _, item in CURRENCY_ITEMS do
		order += 1
		local btn = makeItemCard(item.name, item.desc, order, item.icon)
		btn.Text = "$ " .. item.price
		btn.BackgroundColor3 = Color3.fromRGB(255,200,0)
		btn.TextColor3 = Color3.fromRGB(0,0,0)

		local iid = item.id
		btn.MouseButton1Click:Connect(function()
			buyItemEvent:FireServer(iid)
		end)
	end

	order += 1
	makeSectionHeader("💎  Robux Items", Color3.fromRGB(80,200,255), order)
	for _, item in GAMEPASS_ITEMS do
		order += 1
		local btn = makeItemCard(item.name, item.desc, order, item.icon)
		if item.gamepassId and item.gamepassId > 0 then
			btn.Text = "Robux"
			btn.BackgroundColor3 = Color3.fromRGB(60,200,120)
			btn.TextColor3 = Color3.fromRGB(255,255,255)
			local gpId = item.gamepassId
			btn.MouseButton1Click:Connect(function()
				MarketplaceService:PromptGamePassPurchase(player, gpId)
			end)
		else
			btn.Text = "Coming Soon"
			btn.BackgroundColor3 = Color3.fromRGB(50,50,60)
			btn.TextColor3 = Color3.fromRGB(120,120,140)
			btn.Active = false
		end
	end
end

-- ─── Toast notification on purchase ───────────────────────────────────────────
local toast = Instance.new("Frame")
toast.Size = UDim2.new(0,300,0,52)
toast.AnchorPoint = Vector2.new(0.5,0)
toast.Position = UDim2.new(0.5,0,0,16)
toast.BackgroundColor3 = Color3.fromRGB(18,18,22)
toast.BackgroundTransparency = 1
toast.Visible = false
toast.BorderSizePixel = 0
toast.Parent = gui
corner(toast, 12)
stroke(toast, Color3.fromRGB(80,200,255), 2)

local toastLabel = label(toast, { text = "", pos = UDim2.new(0,12,0,0), size = UDim2.new(1,-24,1,0),
	fs = 14, font = Enum.Font.GothamBold, color = Color3.fromRGB(220,240,255),
	align = Enum.TextXAlignment.Center })

itemPurchased.OnClientEvent:Connect(function(_, itemName: string)
	toastLabel.Text = "✓ Bought " .. itemName .. "!"
	toast.Visible = true
	toast.BackgroundTransparency = 0.05
	task.delay(2.5, function()
		TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function() toast.Visible = false end)
	end)
end)

-- ─── Active buff timers (bottom-right) ───────────────────────────────────────
local buffContainer = Instance.new("Frame")
buffContainer.Name = "ActiveBuffsContainer"
buffContainer.AnchorPoint = Vector2.new(1, 1)
buffContainer.Position = UDim2.new(1, -16, 1, -16)
buffContainer.Size = UDim2.new(0, 220, 0, 0)
buffContainer.AutomaticSize = Enum.AutomaticSize.Y
buffContainer.BackgroundTransparency = 1
buffContainer.Parent = gui

local buffLayout = Instance.new("UIListLayout")
buffLayout.SortOrder = Enum.SortOrder.LayoutOrder
buffLayout.Padding = UDim.new(0, 6)
buffLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
buffLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
buffLayout.Parent = buffContainer

local function formatRemaining(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function makeBuffRow(name: string): (Frame, TextLabel)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.Parent = buffContainer
	corner(row, 8)
	stroke(row, Color3.fromRGB(80,200,255))

	label(row, { text = "⚡", pos = UDim2.new(0,8,0,0), size = UDim2.new(0,22,1,0),
		fs = 16, align = Enum.TextXAlignment.Center })
	label(row, { text = name, pos = UDim2.new(0,32,0,5), size = UDim2.new(1,-90,0,16),
		fs = 12, font = Enum.Font.GothamBold })

	local timeLabel = label(row, { text = "0:00", pos = UDim2.new(1,-56,0,0), size = UDim2.new(0,48,1,0),
		fs = 14, font = Enum.Font.GothamBold, color = Color3.fromRGB(80,200,255),
		align = Enum.TextXAlignment.Right })

	return row, timeLabel
end

local buffRows: { [string]: { frame: Frame, label: TextLabel, expiresAt: number } } = {}

activeBuffsUpdate.OnClientEvent:Connect(function(list: { { id: string, name: string, expiresAt: number } })
	local seen: { [string]: true } = {}
	for _, b in list do
		seen[b.id] = true
		local entry = buffRows[b.id]
		if entry then
			entry.expiresAt = b.expiresAt
		else
			local row, timeLabel = makeBuffRow(b.name)
			buffRows[b.id] = { frame = row, label = timeLabel, expiresAt = b.expiresAt }
		end
	end
	for id, entry in buffRows do
		if not seen[id] then
			entry.frame:Destroy()
			buffRows[id] = nil
		end
	end
end)

RunService.Heartbeat:Connect(function()
	for id, entry in buffRows do
		local remaining = entry.expiresAt - tick()
		if remaining <= 0 then
			entry.frame:Destroy()
			buffRows[id] = nil
		else
			entry.label.Text = formatRemaining(remaining)
		end
	end
end)

-- ─── 3D Shop Trigger (native ProximityPrompt, sama seperti Style Shop) ───────
-- Ring/hoop berbentuk lubang di tengah — karakter berdiri di lubangnya dan
-- tidak pernah benar-benar Touched ke tube ring itu sendiri. ProximityPrompt
-- dipasang di anchor tak terlihat di tengah ring (bukan di tube-nya) supaya
-- jangkauan aktivasinya menutupi seluruh area ring.
local function setupItemShopTrigger()
	local trigger = workspace:FindFirstChild("itemshopring", true)
	if not trigger then
		workspace.ChildAdded:Connect(function(c)
			if c.Name == "itemshopring" then setupItemShopTrigger() end
		end)
		return
	end

	local cf: CFrame, size: Vector3
	if trigger:IsA("Model") then
		cf, size = trigger:GetBoundingBox()
	elseif trigger:IsA("BasePart") then
		cf, size = trigger.CFrame, trigger.Size
	else
		return
	end

	local radius = math.max(size.X, size.Z) / 2

	local anchor = Instance.new("Part")
	anchor.Name = "ItemShopPromptAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = cf
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Parent = trigger

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Item Shop"
	prompt.ActionText = "Open"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = radius + 6
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(p)
		if p ~= player then return end
		panel.Visible = not panel.Visible
		if panel.Visible then buildPanel() end
	end)
end
setupItemShopTrigger()
