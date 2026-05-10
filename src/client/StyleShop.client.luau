local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes       = ReplicatedStorage:WaitForChild("TrampolineRemotes")
local buyStyleEvent = remotes:WaitForChild("BuyStyle")
local stylesUpdate  = remotes:WaitForChild("StylesUpdate")
local gateBlocked   = remotes:WaitForChild("GateBlocked")

-- ─── Style catalog (harus sama dengan server) ─────────────────────────────────
local STYLE_CATALOG = {
	{ id = "Backflip",  name = "Backflip",   price = 100,  desc = "Lakukan backflip di udara!" },
	{ id = "FrontFlip", name = "Front Flip", price = 500,  desc = "Lakukan frontflip di udara!" },
	{ id = "SideFlip",  name = "Side Flip",  price = 1000, desc = "Lakukan sideflip di udara!" },
}

local ownedStyles: { [string]: true } = {}
local currentCurrency = 0

-- ─── Main ScreenGui ───────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "StyleShopGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ─── Shop Button (buka/tutup shop) ───────────────────────────────────────────
local shopBtn = Instance.new("TextButton")
shopBtn.Name = "ShopButton"
shopBtn.Size = UDim2.new(0, 110, 0, 40)
shopBtn.Position = UDim2.new(1, -130, 0, 70)
shopBtn.AnchorPoint = Vector2.new(0, 0)
shopBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
shopBtn.BackgroundTransparency = 0.2
shopBtn.BorderSizePixel = 0
shopBtn.Text = "🛍  Shop"
shopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
shopBtn.Font = Enum.Font.GothamBold
shopBtn.TextSize = 15
shopBtn.Parent = gui

local shopBtnCorner = Instance.new("UICorner")
shopBtnCorner.CornerRadius = UDim.new(0, 10)
shopBtnCorner.Parent = shopBtn

local shopBtnStroke = Instance.new("UIStroke")
shopBtnStroke.Color = Color3.fromRGB(255, 200, 0)
shopBtnStroke.Thickness = 1.5
shopBtnStroke.Parent = shopBtn

-- ─── Shop Panel ───────────────────────────────────────────────────────────────
local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.AnchorPoint = Vector2.new(1, 0)
shopPanel.Position = UDim2.new(1, -20, 0, 120)
shopPanel.Size = UDim2.new(0, 280, 0, 0)
shopPanel.AutomaticSize = Enum.AutomaticSize.Y
shopPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
shopPanel.BackgroundTransparency = 0.1
shopPanel.BorderSizePixel = 0
shopPanel.Visible = false
shopPanel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = shopPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 60, 60)
panelStroke.Thickness = 1.5
panelStroke.Parent = shopPanel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop    = UDim.new(0, 12)
panelPadding.PaddingBottom = UDim.new(0, 12)
panelPadding.PaddingLeft   = UDim.new(0, 14)
panelPadding.PaddingRight  = UDim.new(0, 14)
panelPadding.Parent = shopPanel

local panelLayout = Instance.new("UIListLayout")
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, 10)
panelLayout.Parent = shopPanel

local panelTitle = Instance.new("TextLabel")
panelTitle.Size = UDim2.new(1, 0, 0, 28)
panelTitle.BackgroundTransparency = 1
panelTitle.Text = "Style Shop"
panelTitle.TextColor3 = Color3.fromRGB(255, 200, 0)
panelTitle.Font = Enum.Font.GothamBold
panelTitle.TextSize = 18
panelTitle.TextXAlignment = Enum.TextXAlignment.Left
panelTitle.LayoutOrder = 0
panelTitle.Parent = shopPanel

-- ─── Style cards ─────────────────────────────────────────────────────────────
local styleCards: { [string]: { btn: TextButton, label: TextLabel } } = {}

local function makeStyleCard(style: { id: string, name: string, price: number, desc: string }, order: number)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 70)
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	card.BackgroundTransparency = 0.3
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = shopPanel

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -90, 0, 24)
	nameLabel.Position = UDim2.new(0, 10, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = style.name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -90, 0, 18)
	descLabel.Position = UDim2.new(0, 10, 0, 34)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = style.desc
	descLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = card

	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0, 75, 0, 34)
	buyBtn.Position = UDim2.new(1, -85, 0.5, -17)
	buyBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	buyBtn.BorderSizePixel = 0
	buyBtn.Text = "$ " .. style.price
	buyBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 14
	buyBtn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = buyBtn

	styleCards[style.id] = { btn = buyBtn, label = nameLabel }

	buyBtn.MouseButton1Click:Connect(function()
		if ownedStyles[style.id] then return end
		buyStyleEvent:FireServer(style.id)
	end)
end

for i, style in STYLE_CATALOG do
	makeStyleCard(style, i)
end

local function updateCards()
	for _, style in STYLE_CATALOG do
		local card = styleCards[style.id]
		if not card then continue end
		if ownedStyles[style.id] then
			card.btn.Text = "✓ Owned"
			card.btn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
			card.btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			card.btn.Active = false
		else
			card.btn.Text = "$ " .. style.price
			card.btn.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
			card.btn.TextColor3 = Color3.fromRGB(0, 0, 0)
			card.btn.Active = true
		end
	end
end

stylesUpdate.OnClientEvent:Connect(function(owned: { [string]: true })
	ownedStyles = owned
	updateCards()
end)

-- Toggle shop panel
local shopOpen = false
shopBtn.MouseButton1Click:Connect(function()
	shopOpen = not shopOpen
	shopPanel.Visible = shopOpen
end)

-- ─── Gate blocked notification ────────────────────────────────────────────────
local notif = Instance.new("Frame")
notif.Name = "GateNotif"
notif.AnchorPoint = Vector2.new(0.5, 0)
notif.Position = UDim2.new(0.5, 0, 0, -100)
notif.Size = UDim2.new(0, 360, 0, 72)
notif.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
notif.BackgroundTransparency = 0.1
notif.BorderSizePixel = 0
notif.Parent = gui

local notifCorner = Instance.new("UICorner")
notifCorner.CornerRadius = UDim.new(0, 12)
notifCorner.Parent = notif

local notifStroke = Instance.new("UIStroke")
notifStroke.Color = Color3.fromRGB(220, 50, 50)
notifStroke.Thickness = 2
notifStroke.Parent = notif

local notifTitle = Instance.new("TextLabel")
notifTitle.Size = UDim2.new(1, -16, 0, 30)
notifTitle.Position = UDim2.new(0, 8, 0, 6)
notifTitle.BackgroundTransparency = 1
notifTitle.Text = "🔒  Zone Locked"
notifTitle.TextColor3 = Color3.fromRGB(220, 80, 80)
notifTitle.Font = Enum.Font.GothamBold
notifTitle.TextSize = 16
notifTitle.TextXAlignment = Enum.TextXAlignment.Left
notifTitle.Parent = notif

local notifDesc = Instance.new("TextLabel")
notifDesc.Size = UDim2.new(1, -16, 0, 26)
notifDesc.Position = UDim2.new(0, 8, 0, 36)
notifDesc.BackgroundTransparency = 1
notifDesc.Text = ""
notifDesc.TextColor3 = Color3.fromRGB(200, 200, 200)
notifDesc.Font = Enum.Font.Gotham
notifDesc.TextSize = 14
notifDesc.TextXAlignment = Enum.TextXAlignment.Left
notifDesc.Parent = notif

local notifShowing = false
local function showNotif(zoneName: string, required: number, owned: number)
	notifDesc.Text = string.format(
		"Butuh %d styles untuk masuk %s  (kamu punya %d/%d)",
		required, zoneName, owned, required
	)

	notifShowing = true
	-- Slide in dari atas
	TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 20)
	}):Play()

	task.delay(3, function()
		if not notifShowing then return end
		notifShowing = false
		TweenService:Create(notif, TweenInfo.new(0.25), {
			Position = UDim2.new(0.5, 0, 0, -100)
		}):Play()
	end)
end

gateBlocked.OnClientEvent:Connect(function(zoneName: string, required: number, owned: number)
	showNotif(zoneName, required, owned)
end)
