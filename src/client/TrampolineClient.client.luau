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
local statsUpdate    = remotes:WaitForChild("StatsUpdate")
local allocateStat   = remotes:WaitForChild("AllocateStat")

-- ─── Animation IDs per style ──────────────────────────────────────────────────
local STYLE_ANIM_IDS = {
	Backflip  = "rbxassetid://87380725109308",
	FrontFlip = "rbxassetid://127455590041801",
	SideFlip  = "rbxassetid://138690053556375",
	StarJump  = "rbxassetid://130044428921240",
	CanonBall = "rbxassetid://111071318265188",
	Spin360   = "rbxassetid://120272455020042",
	Double360   = "rbxassetid://112865783046386",
	Backflip360  = "rbxassetid://140263521639075",
	FlatBackflip  = "rbxassetid://122274246065853",
	FlatFrontflip = "rbxassetid://109560729203557",
	Superman       = "rbxassetid://98253651217655",
	DoubleBackflip  = "rbxassetid://105678898467513",
	DoubleFrontflip = "rbxassetid://91583020089351",
	LazyBoy  = "rbxassetid://84682000343737",
	LazyGuy      = "rbxassetid://94142891789027",
	SpinningBump = "rbxassetid://87857869106584",
	AtomicDrop = "rbxassetid://73358166751212",
	HeadSpin    = "rbxassetid://95557628143728",
	BodyDismiss = "rbxassetid://86596700228945",
	TheWheel    = "rbxassetid://82242552193665",
}

-- ─── Bounce parameters (base values, diupdate oleh stats) ────────────────────
local GRAVITY     = workspace.Gravity
local MIN_HEIGHT  = 2
local MAX_HEIGHT  = 36   -- +4 per jumpHeight point
local HEIGHT_STEP = 2    -- +0.3 per jumpSpeed point
local BOUNCE_CD   = 0.35

-- Apply stats dari server ke bounce parameters
statsUpdate.OnClientEvent:Connect(function(data)
	local stats = data.stats or {}
	MAX_HEIGHT  = 36 + (stats.jumpHeight or 0) * 4
	HEIGHT_STEP = 2  + (stats.jumpSpeed  or 0) * 0.3
end)

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
local ITEM_CATALOG: { { id: string, name: string } } = {
	{ id = "Backflip",  name = "Backflip"   },
	{ id = "FrontFlip", name = "Front Flip" },
	{ id = "SideFlip",  name = "Side Flip"  },
	{ id = "StarJump",  name = "Star Jump"  },
	{ id = "CanonBall", name = "Canon Ball" },
	{ id = "Spin360",   name = "360 Spin"   },
	{ id = "Double360",   name = "Double 360"       },
	{ id = "Backflip360",  name = "Backflip 360 Spin" },
	{ id = "FlatBackflip",  name = "Flat Backflip"  },
	{ id = "FlatFrontflip", name = "Flat Frontflip" },
	{ id = "Superman",       name = "Superman"        },
	{ id = "DoubleBackflip",  name = "Double Backflip"  },
	{ id = "DoubleFrontflip", name = "Double Frontflip" },
	{ id = "LazyBoy", name = "Lazy Boy" },
	{ id = "LazyGuy",     name = "Lazy Guy"     },
	{ id = "SpinningBump", name = "Spinning Bump" },
	{ id = "AtomicDrop", name = "Atomic Drop" },
	{ id = "HeadSpin",   name = "Head Spin"    },
	{ id = "BodyDismiss", name = "Body Dismiss" },
	{ id = "TheWheel",    name = "The Wheel"    },
}

local SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

-- ITEMS aktif = styles yang di-equip (max 4), diupdate oleh EquipChanged event dari StyleShop
local ITEMS: { any }                = {}
local ownedStyles: { [string]: true } = {}
local equippedIds: { string }       = {}  -- ordered list dari equipped style IDs

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
	for _, slot in slots do slot:Destroy() end
	slots = {}
	selectedIndex = 0
	ITEMS = {}

	-- Build dari equippedIds (ordered, max 4), key dinamis sesuai slot
	for i, styleId in equippedIds do
		local catalog = nil
		for _, c in ITEM_CATALOG do
			if c.id == styleId then catalog = c break end
		end
		if not catalog then continue end

		local slotKey = SLOT_KEYS[i]
		local item = {
			id        = catalog.id,
			name      = catalog.name,
			key       = slotKey,
			onTrigger = function() styleRequest:FireServer(catalog.id) end,
		}
		table.insert(ITEMS, item)

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

-- stylesUpdate hanya update ownedStyles, hotbar dikontrol oleh EquipChanged
stylesUpdate.OnClientEvent:Connect(function(owned: { [string]: true })
	ownedStyles = owned
end)

-- EquipChanged dari StyleShop → rebuild hotbar
task.spawn(function()
	local ev = playerGui:WaitForChild("EquipChanged", 10) :: BindableEvent?
	if not ev then return end
	ev.Event:Connect(function(newEquipped: { string })
		equippedIds = newEquipped
		rebuildHotbar()
	end)
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
	track.Priority = Enum.AnimationPriority.Action4  -- override semua animasi default (fall, idle, dll)
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

-- ─── Sprint (Shift to run) ────────────────────────────────────────────────────
local WALK_SPEED   = 16
local SPRINT_SPEED = 26

local function setSprint(humanoid: Humanoid, sprinting: boolean)
	humanoid.WalkSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode ~= Enum.KeyCode.LeftShift and input.KeyCode ~= Enum.KeyCode.RightShift then return end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then setSprint(humanoid, true) end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.KeyCode ~= Enum.KeyCode.LeftShift and input.KeyCode ~= Enum.KeyCode.RightShift then return end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then setSprint(humanoid, false) end
end)

-- ─── Character setup ──────────────────────────────────────────────────────────
player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end
