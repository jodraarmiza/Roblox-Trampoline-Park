local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes        = ReplicatedStorage:WaitForChild("TrampolineRemotes")
local styleRequest   = remotes:WaitForChild("StyleRequest")
local styleApproved  = remotes:WaitForChild("StyleApproved")
local bounceReward   = remotes:WaitForChild("BounceReward")
local currencyUpdate = remotes:WaitForChild("CurrencyUpdate")
local stylesUpdate   = remotes:WaitForChild("StylesUpdate")

-- ─── Animation IDs per style ──────────────────────────────────────────────────
local STYLE_ANIM_IDS = {
	Backflip  = "rbxassetid://87380725109308",
	FrontFlip = "rbxassetid://127455590041801",
	SideFlip  = "rbxassetid://138690053556375",
}

-- ─── Bounce parameters ───────────────────────────────────────────────────────
local GRAVITY     = workspace.Gravity
local MIN_HEIGHT  = 2
local MAX_HEIGHT  = 36
local HEIGHT_STEP = 2
local BOUNCE_CD   = 0.35

-- Delay setelah bounce sebelum backflip di-trigger (biarkan karakter naik dulu)
local BACKFLIP_TRIGGER_DELAY = 0.3
-- Backflip hanya mulai setelah bounce height cukup tinggi
local MIN_BACKFLIP_HEIGHT = 16

local bounceHeight      = MIN_HEIGHT
local lastBounce        = 0
local trampolineY       = 0
local offTrampolineTime: number? = nil

local function launchVelocity(h: number): number
	return math.sqrt(2 * GRAVITY * h)
end

-- ─── Item catalog (semua style yang mungkin ada) ─────────────────────────────
local ITEM_CATALOG = {
	{
		id   = "Backflip",
		name = "Backflip",
		key  = Enum.KeyCode.One,
		onTrigger = function() styleRequest:FireServer("Backflip") end,
	},
	{
		id   = "FrontFlip",
		name = "Front Flip",
		key  = Enum.KeyCode.Two,
		onTrigger = function() styleRequest:FireServer("FrontFlip") end,
	},
	{
		id   = "SideFlip",
		name = "Side Flip",
		key  = Enum.KeyCode.Three,
		onTrigger = function() styleRequest:FireServer("SideFlip") end,
	},
}

-- ITEMS yang aktif = hanya yang sudah dibeli, diupdate oleh stylesUpdate event
local ITEMS: { any } = {}
local ownedStyles: { [string]: true } = {}

-- ─── Hotbar UI ───────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FreestyleHotbar"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local hotbarFrame = Instance.new("Frame")
hotbarFrame.Name = "Hotbar"
hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
hotbarFrame.Position = UDim2.new(0.5, 0, 1, -24)
hotbarFrame.Size = UDim2.new(0, 0, 0, 68)
hotbarFrame.AutomaticSize = Enum.AutomaticSize.X
hotbarFrame.BackgroundTransparency = 1
hotbarFrame.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 10)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Parent = hotbarFrame

local selectedIndex = 0
local slots: { Frame } = {}

local function updateSlotVisuals()
	for i, slot in slots do
		if i == selectedIndex then
			slot.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
			slot.BackgroundTransparency = 0.05
		else
			slot.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
			slot.BackgroundTransparency = 0.3
		end
	end
end

local function rebuildHotbar()
	-- Hapus slot lama
	for _, slot in slots do slot:Destroy() end
	slots = {}
	selectedIndex = 0

	-- Rebuild hanya dari styles yang sudah dibeli
	ITEMS = {}
	for _, catalog in ITEM_CATALOG do
		if ownedStyles[catalog.id] then
			table.insert(ITEMS, catalog)
		end
	end

	for i, item in ITEMS do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, 90, 0, 68)
		slot.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		slot.BackgroundTransparency = 0.3
		slot.BorderSizePixel = 0
		slot.Parent = hotbarFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = slot

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(80, 80, 80)
		stroke.Thickness = 1.5
		stroke.Parent = slot

		local numLabel = Instance.new("TextLabel")
		numLabel.Size = UDim2.new(1, 0, 0, 22)
		numLabel.Position = UDim2.new(0, 0, 0, 5)
		numLabel.BackgroundTransparency = 1
		numLabel.Text = tostring(i)
		numLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		numLabel.Font = Enum.Font.GothamBold
		numLabel.TextSize = 14
		numLabel.Parent = slot

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -8, 0, 22)
		nameLabel.Position = UDim2.new(0, 4, 1, -28)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = item.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.Parent = slot

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Parent = slot

		local idx = i
		btn.MouseButton1Click:Connect(function()
			selectedIndex = if selectedIndex == idx then 0 else idx
			updateSlotVisuals()
		end)

		slots[i] = slot
	end
end

-- Update hotbar saat dapat styles dari server
stylesUpdate.OnClientEvent:Connect(function(owned: { [string]: true })
	ownedStyles = owned
	rebuildHotbar()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	for i, item in ITEMS do
		if input.KeyCode == item.key then
			selectedIndex = if selectedIndex == i then 0 else i
			updateSlotVisuals()
			break
		end
	end
end)

-- ─── Raycast params (dibuat saat character spawn) ────────────────────────────
local rayParams: RaycastParams

local function setupCharacter(character: Model)
	bounceHeight = MIN_HEIGHT
	lastBounce   = 0
	trampolineY  = 0
	offTrampolineTime = nil

	-- Exclude karakter sendiri supaya raycast tidak kena body parts-nya
	rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
end

-- ─── Backflip state ───────────────────────────────────────────────────────────
local isDoingBackflip         = false
local wantsBackflipAfterAnim  = false  -- queue jika animasi masih jalan saat bounce

local function tryTriggerBackflip()
	if selectedIndex == 0 then return end
	if isDoingBackflip then
		wantsBackflipAfterAnim = true
		return
	end
	local item = ITEMS[selectedIndex]
	if item then
		item.onTrigger()
	end
end

-- ─── Client-side bounce physics (raycast-based, tidak bisa false positive) ───
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not rayParams then return end

	-- Raycast dari HRP ke bawah 6 studs (covers R15 & R6, plus landing buffer)
	local result = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), rayParams)
	local onTrampoline = result ~= nil
		and result.Instance ~= nil
		and result.Instance.Name == "Trampoline"

	if not onTrampoline then
		if offTrampolineTime == nil then
			offTrampolineTime = tick()
		end
		return
	end

	-- Karakter di atas trampoline
	trampolineY = result.Instance.Position.Y + result.Instance.Size.Y / 2

	-- Reset height jika kembali setelah > 2 detik pergi
	if offTrampolineTime and tick() - offTrampolineTime > 2 then
		bounceHeight = MIN_HEIGHT
		lastBounce   = 0
	end
	offTrampolineTime = nil

	local now = tick()
	if now - lastBounce < BOUNCE_CD then return end
	if root.AssemblyLinearVelocity.Y > 1 then return end

	lastBounce = now
	local heightThisBounce = bounceHeight
	root.AssemblyLinearVelocity = Vector3.new(
		root.AssemblyLinearVelocity.X,
		launchVelocity(bounceHeight),
		root.AssemblyLinearVelocity.Z
	)
	bounceHeight = math.min(bounceHeight + HEIGHT_STEP, MAX_HEIGHT)

	bounceReward:FireServer()

	if selectedIndex > 0 and heightThisBounce >= MIN_BACKFLIP_HEIGHT then
		task.delay(BACKFLIP_TRIGGER_DELAY, tryTriggerBackflip)
	end
end)

-- ─── Style animation ──────────────────────────────────────────────────────────
styleApproved.OnClientEvent:Connect(function(styleId: string)
	if isDoingBackflip then return end

	local animId = STYLE_ANIM_IDS[styleId]
	if not animId then return end

	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	isDoingBackflip        = true
	wantsBackflipAfterAnim = false

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local track = humanoid:LoadAnimation(anim)
	track:Play()

	track.Stopped:Connect(function()
		isDoingBackflip = false
		if wantsBackflipAfterAnim and selectedIndex > 0 then
			wantsBackflipAfterAnim = false
			task.delay(0.05, tryTriggerBackflip)
		end
	end)
end)

-- ─── Currency GUI ─────────────────────────────────────────────────────────────
local currencyGui = Instance.new("ScreenGui")
currencyGui.Name = "CurrencyGui"
currencyGui.ResetOnSpawn = false
currencyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
currencyGui.Parent = playerGui

local currencyFrame = Instance.new("Frame")
currencyFrame.Name = "CurrencyFrame"
currencyFrame.AnchorPoint = Vector2.new(1, 0)
currencyFrame.Position = UDim2.new(1, -20, 0, 20)
currencyFrame.Size = UDim2.new(0, 180, 0, 52)
currencyFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
currencyFrame.BackgroundTransparency = 0.25
currencyFrame.BorderSizePixel = 0
currencyFrame.Parent = currencyGui

local currencyCorner = Instance.new("UICorner")
currencyCorner.CornerRadius = UDim.new(0, 12)
currencyCorner.Parent = currencyFrame

local currencyStroke = Instance.new("UIStroke")
currencyStroke.Color = Color3.fromRGB(255, 200, 0)
currencyStroke.Thickness = 1.5
currencyStroke.Parent = currencyFrame

local iconLabel = Instance.new("TextLabel")
iconLabel.Size = UDim2.new(0, 40, 1, 0)
iconLabel.Position = UDim2.new(0, 8, 0, 0)
iconLabel.BackgroundTransparency = 1
iconLabel.Text = "$"
iconLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
iconLabel.Font = Enum.Font.GothamBold
iconLabel.TextSize = 26
iconLabel.TextXAlignment = Enum.TextXAlignment.Center
iconLabel.Parent = currencyFrame

local amountLabel = Instance.new("TextLabel")
amountLabel.Name = "Amount"
amountLabel.Size = UDim2.new(1, -52, 1, 0)
amountLabel.Position = UDim2.new(0, 44, 0, 0)
amountLabel.BackgroundTransparency = 1
amountLabel.Text = "0"
amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
amountLabel.Font = Enum.Font.GothamBold
amountLabel.TextSize = 22
amountLabel.TextXAlignment = Enum.TextXAlignment.Left
amountLabel.TextYAlignment = Enum.TextYAlignment.Center
amountLabel.Parent = currencyFrame

-- Animasi pop saat duit bertambah
local TweenService = game:GetService("TweenService")
local function popAnimation()
	local info = TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(amountLabel, info, { TextSize = 27 }):Play()
	task.delay(0.1, function()
		TweenService:Create(amountLabel, TweenInfo.new(0.15), { TextSize = 22 }):Play()
	end)
end

local function formatCurrency(amount: number): string
	-- Format ribuan: 1000 → 1,000
	local s = tostring(math.floor(amount))
	local result = ""
	local len = #s
	for i = 1, len do
		if i > 1 and (len - i + 1) % 3 == 0 then
			result = result .. ","
		end
		result = result .. s:sub(i, i)
	end
	return result
end

currencyUpdate.OnClientEvent:Connect(function(amount: number)
	amountLabel.Text = formatCurrency(amount)
	popAnimation()
end)

-- ─── Character setup ──────────────────────────────────────────────────────────
player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end
