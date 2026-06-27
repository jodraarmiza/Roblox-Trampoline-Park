local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes        = ReplicatedStorage:WaitForChild("ItemShopRemotes")
local buyItemEvent    = remotes:WaitForChild("BuyItem")
local itemPurchased   = remotes:WaitForChild("ItemPurchased")

-- ─── Catalog (subset — harus sinkron dengan ItemShopService) ─────────────────
local CURRENCY_ITEMS = {
	{ id = "TrampolineSocks", name = "Trampoline Socks", desc = "+5% jump power selama 5 menit", price = 2000 },
	{ id = "EnergyDrink",     name = "Energy Drink",     desc = "+8 walk speed selama 60 detik",  price = 800  },
}

local GAMEPASS_ITEMS = {
	{ id = "SuperSpringShoes", name = "Super Spring Shoes", desc = "+25% jump power, permanen", gamepassId = 0 },
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

local function makeItemCard(name: string, desc: string, order: number)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1,0,0,68)
	card.BackgroundColor3 = Color3.fromRGB(24,24,32)
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = contentFrame
	corner(card, 10)

	label(card, { text = name, pos = UDim2.new(0,10,0,8), size = UDim2.new(1,-110,0,22),
		fs = 15, font = Enum.Font.GothamBold })
	label(card, { text = desc, pos = UDim2.new(0,10,0,32), size = UDim2.new(1,-110,0,18),
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
		local btn = makeItemCard(item.name, item.desc, order)
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
		local btn = makeItemCard(item.name, item.desc, order)
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

-- ─── 3D Shop Trigger ─────────────────────────────────────────────────────────
local function findFirstBasePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function setupItemShopTrigger()
	local trigger = workspace:FindFirstChild("itemshopring", true)
	if not trigger then
		workspace.ChildAdded:Connect(function(c)
			if c.Name == "itemshopring" then setupItemShopTrigger() end
		end)
		return
	end

	local part = findFirstBasePart(trigger)
	if not part then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Item Shop"
	prompt.ActionText = "Open"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.Parent = part
	prompt.Triggered:Connect(function(p)
		if p ~= player then return end
		panel.Visible = not panel.Visible
		if panel.Visible then buildPanel() end
	end)
end
setupItemShopTrigger()
