local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes       = ReplicatedStorage:WaitForChild("TrampolineRemotes")
local buyStyleEvent = remotes:WaitForChild("BuyStyle")
local stylesUpdate  = remotes:WaitForChild("StylesUpdate")
local gateBlocked   = remotes:WaitForChild("GateBlocked")
local statsUpdate   = remotes:WaitForChild("StatsUpdate")
local allocateStat  = remotes:WaitForChild("AllocateStat")

-- BindableEvent → sinyal ke TrampolineClient saat equipped berubah
local equipChanged = Instance.new("BindableEvent")
equipChanged.Name = "EquipChanged"
equipChanged.Parent = playerGui

local STYLE_CATALOG = {
	{ id = "Backflip",  name = "Backflip",   price = 100,  minStyles = 0, reward = 10 },
	{ id = "FrontFlip", name = "Front Flip", price = 500,  minStyles = 0, reward = 15 },
	{ id = "SideFlip",  name = "Side Flip",  price = 1000, minStyles = 0, reward = 20 },
	{ id = "StarJump",  name = "Star Jump",  price = 1500, minStyles = 0, reward = 25 },
	{ id = "CanonBall", name = "Canon Ball", price = 2000, minStyles = 0, reward = 30 },
	{ id = "Spin360",   name = "360 Spin",   price = 2500, minStyles = 5, reward = 35 },
	{ id = "Double360",   name = "Double 360",       price = 3000, minStyles = 5, reward = 40 },
	{ id = "Backflip360",  name = "Backflip 360 Spin", price = 3500, minStyles = 5, reward = 45 },
	{ id = "FlatBackflip",  name = "Flat Backflip",  price = 4000, minStyles = 5, reward = 50 },
	{ id = "FlatFrontflip", name = "Flat Frontflip", price = 4500, minStyles = 5, reward = 55 },
	{ id = "Superman",       name = "Superman",        price = 5000, minStyles = 5, reward = 60 },
	{ id = "DoubleBackflip",  name = "Double Backflip",  price = 5500, minStyles = 5, reward = 65 },
	{ id = "DoubleFrontflip", name = "Double Frontflip", price = 6000, minStyles = 5,  reward = 70 },
	{ id = "LazyBoy",         name = "Lazy Boy",         price = 6500, minStyles = 10, reward = 75 },  -- Adult zone
}

local STAT_CONFIG = {
	{ id = "jumpHeight", name = "Jump Height", desc = "+4 max altitude per point" },
	{ id = "jumpSpeed",  name = "Jump Speed",  desc = "Faster height buildup"     },
	{ id = "styleBonus", name = "Style Bonus", desc = "+10% $ per style per point" },
}

local MAX_EQUIPPED = 4

local ownedStyles: { [string]: true } = {}
local ownedCount   = 0
local equippedIds: { string }         = {}
local currentData  = {
	xp = 0, xpNeeded = 100, level = 1, skillPts = 0,
	stats = { jumpHeight = 0, jumpSpeed = 0, styleBonus = 0 },
}

-- ─── ScreenGui ───────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "StyleShopGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

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
	l.LayoutOrder        = props.order or 0
	if props.auto then l.AutomaticSize = Enum.AutomaticSize.Y end
	l.Parent             = parent
	return l
end

-- ─── Right-side nav buttons ──────────────────────────────────────────────────
-- 2 buttons × 48px + 8px gap = 104px total height
local navFrame = Instance.new("Frame")
navFrame.Size = UDim2.new(0, 48, 0, 104)
navFrame.Position = UDim2.new(1, -64, 0, 84)  -- di bawah currency, tidak overlap
navFrame.BackgroundTransparency = 1
navFrame.Parent = gui

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 8)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = navFrame

local NAV_TABS = {
	{ id = "inv",   icon = "🎒", label = "Inventory" },
	{ id = "stats", icon = "📊", label = "Stats"     },
}
local navBtns: { [string]: TextButton } = {}

for i, tab in NAV_TABS do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	btn.BackgroundTransparency = 0
	btn.BorderSizePixel = 0
	btn.Text = tab.icon
	btn.TextSize = 22
	btn.Font = Enum.Font.Gotham
	btn.AutoButtonColor = true
	btn.LayoutOrder = i
	btn.Parent = navFrame
	corner(btn, 12)
	stroke(btn, Color3.fromRGB(70,70,90))
	navBtns[tab.id] = btn
end

-- ─── Main center panel ───────────────────────────────────────────────────────
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 360, 0, 480)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 16)
stroke(panel, Color3.fromRGB(60,60,80), 1.5)

-- Panel header
local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1,0,0,48)
headerFrame.BackgroundColor3 = Color3.fromRGB(20,20,28)
headerFrame.BackgroundTransparency = 0
headerFrame.BorderSizePixel = 0
headerFrame.Parent = panel
corner(headerFrame, 16)

-- fix top corners only via a bottom overlay
local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1,0,0,16)
headerFix.Position = UDim2.new(0,0,1,-16)
headerFix.BackgroundColor3 = Color3.fromRGB(20,20,28)
headerFix.BackgroundTransparency = 0
headerFix.BorderSizePixel = 0
headerFix.Parent = headerFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1,-50,1,0)
titleLabel.Position = UDim2.new(0,16,0,0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Style Shop"
titleLabel.TextSize = 18
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextColor3 = Color3.fromRGB(255,200,0)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = headerFrame

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

-- Content area (scrollable)
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

-- ─── Tab content builders ─────────────────────────────────────────────────────
local activeTab = ""
local shopCards:    { [string]: TextButton }     = {}
local invRows:      { [string]: Frame }          = {}
local statRows:     { [string]: TextLabel }      = {}
local xpBar:        Frame
local xpLabel:      TextLabel
local lvlLabel:     TextLabel
local skillLabel:   TextLabel

local function clearContent()
	for _, c in contentFrame:GetChildren() do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	shopCards = {}
	invRows   = {}
	statRows  = {}
end

-- ── Shop tab ──────────────────────────────────────────────────────────────────
local function buildShopTab()
	clearContent()
	titleLabel.Text = "🛍  Style Shop"
	for i, style in STYLE_CATALOG do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1,0,0,68)
		card.BackgroundColor3 = Color3.fromRGB(24,24,32)
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = contentFrame
		corner(card, 10)

		label(card, { text = style.name, pos = UDim2.new(0,10,0,8), size = UDim2.new(1,-90,0,22),
			fs = 15, font = Enum.Font.GothamBold })
		label(card, { text = "+ $" .. style.reward .. " per perform",
			pos = UDim2.new(0,10,0,32), size = UDim2.new(1,-90,0,18),
			fs = 12, color = Color3.fromRGB(150,150,160) })

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0,80,0,34)
		buyBtn.Position = UDim2.new(1,-90,0.5,-17)
		buyBtn.BackgroundColor3 = Color3.fromRGB(255,200,0)
		buyBtn.BorderSizePixel = 0
		buyBtn.Text = "$ " .. style.price
		buyBtn.TextSize = 13
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.TextColor3 = Color3.fromRGB(0,0,0)
		buyBtn.Parent = card
		corner(buyBtn, 8)
		shopCards[style.id] = buyBtn

		local sid = style.id
		buyBtn.MouseButton1Click:Connect(function()
			if not ownedStyles[sid] and (style.minStyles or 0) <= ownedCount then
				buyStyleEvent:FireServer(sid)
			end
		end)
	end
	-- refresh visuals
	for _, style in STYLE_CATALOG do
		local btn = shopCards[style.id]
		if not btn then continue end
		local locked = (style.minStyles or 0) > ownedCount
		if ownedStyles[style.id] then
			btn.Text = "✓ Owned"; btn.BackgroundColor3 = Color3.fromRGB(50,180,80)
			btn.TextColor3 = Color3.fromRGB(255,255,255)
		elseif locked then
			btn.Text = "🔒 Locked"; btn.BackgroundColor3 = Color3.fromRGB(50,50,60)
			btn.TextColor3 = Color3.fromRGB(120,120,140)
		else
			btn.Text = "$ " .. style.price; btn.BackgroundColor3 = Color3.fromRGB(255,200,0)
			btn.TextColor3 = Color3.fromRGB(0,0,0)
		end
	end
end

-- ── Inventory tab ─────────────────────────────────────────────────────────────
local function isEquipped(id: string): (boolean, number)
	for i, eid in equippedIds do
		if eid == id then return true, i end
	end
	return false, 0
end

local function refreshInvRows()
	for _, style in STYLE_CATALOG do
		local row = invRows[style.id]
		if not row then continue end
		local equipped, slot = isEquipped(style.id)
		local btn = row:FindFirstChild("ActionBtn") :: TextButton?
		if not btn then continue end
		if equipped then
			btn.Text = "Slot " .. slot .. " ✕"
			btn.BackgroundColor3 = Color3.fromRGB(180,60,60)
			btn.TextColor3 = Color3.fromRGB(255,255,255)
		elseif #equippedIds >= MAX_EQUIPPED then
			btn.Text = "Full"
			btn.BackgroundColor3 = Color3.fromRGB(50,50,60)
			btn.TextColor3 = Color3.fromRGB(120,120,140)
		else
			btn.Text = "Equip"
			btn.BackgroundColor3 = Color3.fromRGB(60,130,220)
			btn.TextColor3 = Color3.fromRGB(255,255,255)
		end
	end
end

local function buildInvTab()
	clearContent()
	titleLabel.Text = "🎒  Inventory (max " .. MAX_EQUIPPED .. " slots)"

	label(contentFrame, {
		text = "Equipped: " .. #equippedIds .. "/" .. MAX_EQUIPPED,
		size = UDim2.new(1,0,0,20), pos = UDim2.new(0,0,0,0),
		fs = 13, font = Enum.Font.GothamBold, color = Color3.fromRGB(180,220,255),
		order = 0
	})

	for i, style in STYLE_CATALOG do
		if not ownedStyles[style.id] then continue end
		local row = Instance.new("Frame")
		row.Name = style.id
		row.Size = UDim2.new(1,0,0,52)
		row.BackgroundColor3 = Color3.fromRGB(24,24,32)
		row.BackgroundTransparency = 0
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = contentFrame
		corner(row, 10)
		invRows[style.id] = row

		label(row, { text = style.name, pos = UDim2.new(0,10,0,8), size = UDim2.new(1,-100,0,20),
			fs = 14, font = Enum.Font.GothamBold })
		label(row, { text = "+ $" .. style.reward, pos = UDim2.new(0,10,0,30), size = UDim2.new(1,-100,0,16),
			fs = 12, color = Color3.fromRGB(150,150,160) })

		local actionBtn = Instance.new("TextButton")
		actionBtn.Name = "ActionBtn"
		actionBtn.Size = UDim2.new(0,80,0,32)
		actionBtn.Position = UDim2.new(1,-90,0.5,-16)
		actionBtn.BorderSizePixel = 0
		actionBtn.Text = "Equip"
		actionBtn.TextSize = 13
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.Parent = row
		corner(actionBtn, 8)

		local sid = style.id
		actionBtn.MouseButton1Click:Connect(function()
			local eq, _ = isEquipped(sid)
			if eq then
				-- Unequip
				local newList = {}
				for _, eid in equippedIds do
					if eid ~= sid then table.insert(newList, eid) end
				end
				equippedIds = newList
			else
				if #equippedIds < MAX_EQUIPPED then
					table.insert(equippedIds, sid)
				end
			end
			equipChanged:Fire(equippedIds)
			refreshInvRows()
		end)
	end

	refreshInvRows()

	if ownedCount == 0 then
		label(contentFrame, {
			text = "Belum punya style. Beli di tab Shop!", order = 99,
			size = UDim2.new(1,0,0,40), fs = 13, color = Color3.fromRGB(140,140,160),
			align = Enum.TextXAlignment.Center
		})
	end
end

-- ── Stats tab ─────────────────────────────────────────────────────────────────
local function refreshStats()
	if not lvlLabel then return end
	lvlLabel.Text  = "Level " .. currentData.level
	xpLabel.Text   = "XP  " .. currentData.xp .. " / " .. currentData.xpNeeded
	local pct = math.clamp(currentData.xp / math.max(currentData.xpNeeded,1), 0, 1)
	TweenService:Create(xpBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(pct, 0, 1, 0) }):Play()
	local pts = currentData.skillPts
	skillLabel.Text = "Skill Points: " .. pts
	skillLabel.TextColor3 = if pts > 0 then Color3.fromRGB(100,220,100) else Color3.fromRGB(120,120,130)
	for _, stat in STAT_CONFIG do
		local val = (currentData.stats and currentData.stats[stat.id]) or 0
		if statRows[stat.id] then statRows[stat.id].Text = val .. " / 10" end
	end
end

local function buildStatsTab()
	clearContent()
	titleLabel.Text = "📊  Stats & Level"

	-- Level/XP section
	local xpSection = Instance.new("Frame")
	xpSection.Size = UDim2.new(1,0,0,90)
	xpSection.BackgroundColor3 = Color3.fromRGB(20,20,30)
	xpSection.BackgroundTransparency = 0
	xpSection.BorderSizePixel = 0
	xpSection.LayoutOrder = 0
	xpSection.Parent = contentFrame
	corner(xpSection, 10)

	lvlLabel = label(xpSection, { text = "Level 1", pos = UDim2.new(0,12,0,10),
		size = UDim2.new(0.5,0,0,24), fs = 18, font = Enum.Font.GothamBold,
		color = Color3.fromRGB(255,200,0) })
	skillLabel = label(xpSection, { text = "Skill Points: 0",
		pos = UDim2.new(0.5,0,0,12), size = UDim2.new(0.5,-12,0,20),
		fs = 14, font = Enum.Font.GothamBold, color = Color3.fromRGB(100,220,100),
		align = Enum.TextXAlignment.Right })
	xpLabel = label(xpSection, { text = "XP  0 / 100", pos = UDim2.new(0,12,0,38),
		size = UDim2.new(1,-24,0,16), fs = 12, color = Color3.fromRGB(160,160,180) })

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1,-24,0,8)
	barBg.Position = UDim2.new(0,12,0,60)
	barBg.BackgroundColor3 = Color3.fromRGB(40,40,50)
	barBg.BorderSizePixel = 0
	barBg.Parent = xpSection
	corner(barBg, 4)

	xpBar = Instance.new("Frame")
	xpBar.Size = UDim2.new(0,0,1,0)
	xpBar.BackgroundColor3 = Color3.fromRGB(255,200,0)
	xpBar.BorderSizePixel = 0
	xpBar.Parent = barBg
	corner(xpBar, 4)

	-- Stat rows
	for i, stat in STAT_CONFIG do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,64)
		row.BackgroundColor3 = Color3.fromRGB(22,22,32)
		row.BackgroundTransparency = 0
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = contentFrame
		corner(row, 10)

		label(row, { text = stat.name, pos = UDim2.new(0,12,0,8), size = UDim2.new(1,-120,0,22),
			fs = 14, font = Enum.Font.GothamBold })
		label(row, { text = stat.desc, pos = UDim2.new(0,12,0,32), size = UDim2.new(1,-120,0,18),
			fs = 11, color = Color3.fromRGB(130,130,150) })

		local valLbl = label(row, { text = "0 / 10", pos = UDim2.new(1,-108,0.5,-12),
			size = UDim2.new(0,50,0,24), fs = 13, font = Enum.Font.GothamBold,
			color = Color3.fromRGB(255,200,0), align = Enum.TextXAlignment.Center })
		statRows[stat.id] = valLbl

		local addBtn = Instance.new("TextButton")
		addBtn.Size = UDim2.new(0,36,0,36)
		addBtn.Position = UDim2.new(1,-46,0.5,-18)
		addBtn.BackgroundColor3 = Color3.fromRGB(60,160,60)
		addBtn.BorderSizePixel = 0
		addBtn.Text = "+"
		addBtn.TextSize = 20
		addBtn.Font = Enum.Font.GothamBold
		addBtn.TextColor3 = Color3.fromRGB(255,255,255)
		addBtn.Parent = row
		corner(addBtn, 8)

		local sid = stat.id
		addBtn.MouseButton1Click:Connect(function()
			allocateStat:FireServer(sid)
		end)
	end

	refreshStats()
end

-- ─── Tab switching ────────────────────────────────────────────────────────────
local function switchTab(tabId: string)
	if panel.Visible and activeTab == tabId then
		panel.Visible = false
		return
	end
	panel.Visible = true
	activeTab = tabId

	for id, btn in navBtns do
		btn.BackgroundColor3 = if id == tabId
			then Color3.fromRGB(50,50,80)
			else Color3.fromRGB(20,20,20)
	end

	if tabId == "shop" then
		buildShopTab()
	elseif tabId == "inv" then
		buildInvTab()
	elseif tabId == "stats" then
		buildStatsTab()
	end
end

navBtns["inv"].MouseButton1Click:Connect(function()   switchTab("inv")   end)
navBtns["stats"].MouseButton1Click:Connect(function() switchTab("stats") end)

-- ─── Persistent XP bar (bottom left) — HARUS sebelum remote listeners ────────
local xpWidget = Instance.new("Frame")
xpWidget.Size = UDim2.new(0, 220, 0, 44)
xpWidget.Position = UDim2.new(0, 16, 1, -60)
xpWidget.AnchorPoint = Vector2.new(0, 1)
xpWidget.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
xpWidget.BackgroundTransparency = 0.1
xpWidget.BorderSizePixel = 0
xpWidget.Parent = gui
corner(xpWidget, 10)
stroke(xpWidget, Color3.fromRGB(60, 60, 80))

local wLvl = Instance.new("TextLabel")
wLvl.Size = UDim2.new(0, 60, 0, 18)
wLvl.Position = UDim2.new(0, 10, 0, 6)
wLvl.BackgroundTransparency = 1
wLvl.Text = "Lv. 1"
wLvl.TextSize = 13
wLvl.Font = Enum.Font.GothamBold
wLvl.TextColor3 = Color3.fromRGB(255, 200, 0)
wLvl.TextXAlignment = Enum.TextXAlignment.Left
wLvl.Parent = xpWidget

local wXPLabel = Instance.new("TextLabel")
wXPLabel.Size = UDim2.new(1, -70, 0, 16)
wXPLabel.Position = UDim2.new(0, 70, 0, 7)
wXPLabel.BackgroundTransparency = 1
wXPLabel.Text = "0 / 100 XP"
wXPLabel.TextSize = 11
wXPLabel.Font = Enum.Font.Gotham
wXPLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
wXPLabel.TextXAlignment = Enum.TextXAlignment.Right
wXPLabel.Parent = xpWidget

local wBarBg = Instance.new("Frame")
wBarBg.Size = UDim2.new(1, -20, 0, 7)
wBarBg.Position = UDim2.new(0, 10, 1, -16)
wBarBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
wBarBg.BorderSizePixel = 0
wBarBg.Parent = xpWidget
corner(wBarBg, 4)

local wBar = Instance.new("Frame")
wBar.Size = UDim2.new(0, 0, 1, 0)
wBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
wBar.BorderSizePixel = 0
wBar.Parent = wBarBg
corner(wBar, 4)

local function updateXPWidget()
	wLvl.Text = "Lv. " .. currentData.level
	wXPLabel.Text = currentData.xp .. " / " .. currentData.xpNeeded .. " XP"
	local pct = math.clamp(currentData.xp / math.max(currentData.xpNeeded, 1), 0, 1)
	TweenService:Create(wBar, TweenInfo.new(0.4, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(pct, 0, 1, 0) }):Play()
end

-- ─── Remote listeners ─────────────────────────────────────────────────────────
stylesUpdate.OnClientEvent:Connect(function(owned)
	ownedStyles = owned
	ownedCount  = 0
	for _ in owned do ownedCount += 1 end
	if activeTab == "shop" then buildShopTab()
	elseif activeTab == "inv" then buildInvTab() end
end)

statsUpdate.OnClientEvent:Connect(function(data)
	currentData = data
	updateXPWidget()
	if activeTab == "stats" then refreshStats() end
end)

-- ─── 3D Shop Trigger ─────────────────────────────────────────────────────────
local function setupShopTrigger()
	local trigger = workspace:FindFirstChild("shop trigger")
	if not trigger then
		workspace.ChildAdded:Connect(function(c)
			if c.Name == "shop trigger" then setupShopTrigger() end
		end)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Style Shop"
	prompt.ActionText = "Open"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.Parent = trigger
	prompt.Triggered:Connect(function(p)
		if p ~= player then return end
		switchTab("shop")
	end)
end
setupShopTrigger()

-- ─── Gate blocked notification ────────────────────────────────────────────────
local notif = Instance.new("Frame")
notif.Size = UDim2.new(0,380,0,72)
notif.AnchorPoint = Vector2.new(0.5,0)
notif.Position = UDim2.new(0.5,0,0,16)
notif.BackgroundColor3 = Color3.fromRGB(18,18,22)
notif.BackgroundTransparency = 0.05
notif.Visible = false
notif.BorderSizePixel = 0
notif.Parent = gui
corner(notif, 12)
stroke(notif, Color3.fromRGB(200,50,50), 2)

label(notif, { text = "🔒  Zone Locked", pos = UDim2.new(0,12,0,8),
	size = UDim2.new(1,-24,0,26), fs = 15, font = Enum.Font.GothamBold,
	color = Color3.fromRGB(220,80,80) })
local notifDesc = label(notif, { text = "", pos = UDim2.new(0,12,0,36),
	size = UDim2.new(1,-24,0,26), fs = 13, color = Color3.fromRGB(190,190,200) })

local notifShowing = false
gateBlocked.OnClientEvent:Connect(function(zoneName, required, owned)
	notifDesc.Text = string.format("Butuh %d styles untuk masuk %s  (%d/%d)", required, zoneName, owned, required)
	notifShowing = true
	notif.Visible = true
	notif.BackgroundTransparency = 0.05
	task.delay(3.5, function()
		if not notifShowing then return end
		notifShowing = false
		TweenService:Create(notif, TweenInfo.new(0.25),
			{ BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function() notif.Visible = false end)
	end)
end)
