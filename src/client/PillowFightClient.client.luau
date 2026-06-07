local Players               = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local UserInputService      = game:GetService("UserInputService")
local ContextActionService  = game:GetService("ContextActionService")
local TweenService          = game:GetService("TweenService")
local RunService            = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes     = ReplicatedStorage:WaitForChild("PillowFightRemotes")
local queueUpdate = remotes:WaitForChild("QueueUpdate")
local gameStart   = remotes:WaitForChild("GameStart")
local pillowHit   = remotes:WaitForChild("PillowHit")
local pillowDodge = remotes:WaitForChild("PillowDodge")
local hitResult   = remotes:WaitForChild("HitResult")
local gameEnd     = remotes:WaitForChild("GameEnd")
local leaveQueue  = remotes:WaitForChild("LeaveQueue")

local HIT_CD   = 0.75
local DODGE_CD = 2.5

-- ─── Animation IDs — replace with your own from Animation Editor or catalog ──
local ANIM_HIT   = "rbxassetid://135446390129712"        -- pillow swing hit 5
local ANIM_BLOCK = "rbxassetid://REPLACE_BLOCK_ANIM_ID" -- raise pillow to block/dodge

local hitTrack:   AnimationTrack? = nil
local blockTrack: AnimationTrack? = nil

local function loadAnims(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local function load(id: string): AnimationTrack?
		if id:find("REPLACE") then return nil end  -- skip placeholder IDs
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = humanoid:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		return track
	end

	hitTrack   = load(ANIM_HIT)
	blockTrack = load(ANIM_BLOCK)
end

player.CharacterAdded:Connect(loadAnims)
if player.Character then loadAnims(player.Character) end

local bridgeAxis: Vector3 = Vector3.new(0, 0, 1)  -- updated on game start

local function sinkInput(_name: string, _state: Enum.UserInputState, _input: InputObject)
	return Enum.ContextActionResult.Sink
end

local function lockControls()
	-- Sink all movement keys so the default character module does nothing
	ContextActionService:BindAction("PFLock", sinkInput, false,
		Enum.KeyCode.A, Enum.KeyCode.D,
		Enum.KeyCode.W, Enum.KeyCode.S,
		Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.Up, Enum.KeyCode.Down)

	-- Override AFTER the character module (priority 200) so our call wins
	RunService:BindToRenderStep("PFMove", Enum.RenderPriority.Character.Value + 1, function()
		local char = player.Character
		if not char then return end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local fwd = UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0
		local bwd = UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0
		humanoid:Move(bridgeAxis * (fwd - bwd), false)
	end)
end

local function unlockControls()
	ContextActionService:UnbindAction("PFLock")
	RunService:UnbindFromRenderStep("PFMove")
end

local inGame   = false
local myHp     = 3
local oppHp    = 3
local maxHp    = 3
local hitCd    = 0
local dodgeCd  = 0

-- ─── Root GUI ────────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "PillowFightGui"
screenGui.ResetOnSpawn    = false
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.Parent          = playerGui

-- ─── Queue panel ─────────────────────────────────────────────────────────────
local queuePanel = Instance.new("Frame")
queuePanel.Name                  = "QueuePanel"
queuePanel.AnchorPoint           = Vector2.new(0.5, 0.5)
queuePanel.Position              = UDim2.new(0.5, 0, 0.5, 0)
queuePanel.Size                  = UDim2.new(0, 320, 0, 145)
queuePanel.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
queuePanel.BackgroundTransparency = 0.08
queuePanel.BorderSizePixel       = 0
queuePanel.Visible               = false
queuePanel.Parent                = screenGui
local qc = Instance.new("UICorner", queuePanel); qc.CornerRadius = UDim.new(0, 14)
local qs = Instance.new("UIStroke", queuePanel)
qs.Color = Color3.fromRGB(180, 110, 255); qs.Thickness = 2

local queueTitle = Instance.new("TextLabel")
queueTitle.Size               = UDim2.new(1, 0, 0, 44)
queueTitle.Position           = UDim2.new(0, 0, 0, 6)
queueTitle.BackgroundTransparency = 1
queueTitle.Text               = "PILLOW FIGHT"
queueTitle.TextColor3         = Color3.fromRGB(210, 150, 255)
queueTitle.Font               = Enum.Font.GothamBold
queueTitle.TextSize           = 24
queueTitle.Parent             = queuePanel

local queueStatus = Instance.new("TextLabel")
queueStatus.Size              = UDim2.new(1, -20, 0, 30)
queueStatus.Position          = UDim2.new(0, 10, 0, 52)
queueStatus.BackgroundTransparency = 1
queueStatus.Text              = "Waiting for opponent..."
queueStatus.TextColor3        = Color3.fromRGB(200, 200, 200)
queueStatus.Font              = Enum.Font.Gotham
queueStatus.TextSize          = 15
queueStatus.Parent            = queuePanel

local leaveBtn = Instance.new("TextButton")
leaveBtn.Size              = UDim2.new(0, 140, 0, 36)
leaveBtn.AnchorPoint       = Vector2.new(0.5, 1)
leaveBtn.Position          = UDim2.new(0.5, 0, 1, -10)
leaveBtn.BackgroundColor3  = Color3.fromRGB(170, 45, 45)
leaveBtn.Text              = "Leave Queue"
leaveBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
leaveBtn.Font              = Enum.Font.GothamBold
leaveBtn.TextSize          = 14
leaveBtn.BorderSizePixel   = 0
leaveBtn.Parent            = queuePanel
local lb = Instance.new("UICorner", leaveBtn); lb.CornerRadius = UDim.new(0, 8)

leaveBtn.MouseButton1Click:Connect(function()
	leaveQueue:FireServer()
end)

-- ─── Game HUD ────────────────────────────────────────────────────────────────
local hud = Instance.new("Frame")
hud.Name                 = "PillowHUD"
hud.Size                 = UDim2.new(1, 0, 1, 0)
hud.BackgroundTransparency = 1
hud.Visible              = false
hud.Parent               = screenGui

-- HP panel builder
local myHearts:  { TextLabel } = {}
local oppHearts: { TextLabel } = {}

local function makeHpPanel(side: string, hearts: { TextLabel }): Frame
	local panel = Instance.new("Frame")
	panel.Size                  = UDim2.new(0, 170, 0, 54)
	panel.AnchorPoint           = side == "left" and Vector2.new(0, 0) or Vector2.new(1, 0)
	panel.Position              = side == "left" and UDim2.new(0, 14, 0, 14) or UDim2.new(1, -14, 0, 14)
	panel.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel       = 0
	panel.Parent                = hud
	local pc = Instance.new("UICorner", panel); pc.CornerRadius = UDim.new(0, 10)
	local ps = Instance.new("UIStroke", panel)
	ps.Color     = side == "left" and Color3.fromRGB(80, 210, 120) or Color3.fromRGB(220, 80, 80)
	ps.Thickness = 1.5

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                = "NameLabel"
	nameLabel.Size                = UDim2.new(1, 0, 0, 22)
	nameLabel.Position            = UDim2.new(0, 0, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                = side == "left" and "YOU" or "OPPONENT"
	nameLabel.TextColor3          = Color3.fromRGB(255, 255, 255)
	nameLabel.Font                = Enum.Font.GothamBold
	nameLabel.TextSize            = 13
	nameLabel.Parent              = panel

	local heartRow = Instance.new("Frame")
	heartRow.Size               = UDim2.new(1, -14, 0, 24)
	heartRow.Position           = UDim2.new(0, 7, 0, 26)
	heartRow.BackgroundTransparency = 1
	heartRow.Parent             = panel
	local hl = Instance.new("UIListLayout", heartRow)
	hl.FillDirection      = Enum.FillDirection.Horizontal
	hl.Padding            = UDim.new(0, 5)
	hl.VerticalAlignment  = Enum.VerticalAlignment.Center

	for _ = 1, 3 do
		local h = Instance.new("TextLabel")
		h.Size                = UDim2.new(0, 22, 0, 22)
		h.BackgroundTransparency = 1
		h.Text                = "♥"
		h.TextColor3          = Color3.fromRGB(255, 55, 75)
		h.Font                = Enum.Font.GothamBold
		h.TextSize            = 20
		h.Parent              = heartRow
		table.insert(hearts, h)
	end

	return panel
end

local myPanel  = makeHpPanel("left",  myHearts)
local oppPanel = makeHpPanel("right", oppHearts)

-- Controls hint bar
local hintBar = Instance.new("TextLabel")
hintBar.Size                  = UDim2.new(0, 310, 0, 34)
hintBar.AnchorPoint           = Vector2.new(0.5, 1)
hintBar.Position              = UDim2.new(0.5, 0, 1, -18)
hintBar.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
hintBar.BackgroundTransparency = 0.25
hintBar.BorderSizePixel       = 0
hintBar.Text                  = "[E] Hit    [Q] Dodge    [W] Forward  [S] Back"
hintBar.TextColor3            = Color3.fromRGB(190, 190, 190)
hintBar.Font                  = Enum.Font.Gotham
hintBar.TextSize              = 14
hintBar.Parent                = hud
local hc = Instance.new("UICorner", hintBar); hc.CornerRadius = UDim.new(0, 8)

-- Dodge status label (above hint bar)
local dodgeLabel = Instance.new("TextLabel")
dodgeLabel.Size                  = UDim2.new(0, 200, 0, 28)
dodgeLabel.AnchorPoint           = Vector2.new(0.5, 1)
dodgeLabel.Position              = UDim2.new(0.5, 0, 1, -56)
dodgeLabel.BackgroundTransparency = 1
dodgeLabel.Text                  = ""
dodgeLabel.TextColor3            = Color3.fromRGB(180, 120, 255)
dodgeLabel.Font                  = Enum.Font.GothamBold
dodgeLabel.TextSize              = 15
dodgeLabel.Parent                = hud

-- ─── Result panel ─────────────────────────────────────────────────────────────
local resultPanel = Instance.new("Frame")
resultPanel.Name                  = "ResultPanel"
resultPanel.AnchorPoint           = Vector2.new(0.5, 0.5)
resultPanel.Position              = UDim2.new(0.5, 0, 0.5, 0)
resultPanel.Size                  = UDim2.new(0, 340, 0, 160)
resultPanel.BackgroundColor3      = Color3.fromRGB(10, 10, 22)
resultPanel.BackgroundTransparency = 0.08
resultPanel.BorderSizePixel       = 0
resultPanel.Visible               = false
resultPanel.Parent                = screenGui
local rc = Instance.new("UICorner", resultPanel); rc.CornerRadius = UDim.new(0, 14)

local resultTitle = Instance.new("TextLabel")
resultTitle.Size              = UDim2.new(1, 0, 0, 70)
resultTitle.Position          = UDim2.new(0, 0, 0, 16)
resultTitle.BackgroundTransparency = 1
resultTitle.Font              = Enum.Font.GothamBold
resultTitle.TextSize          = 42
resultTitle.Text              = ""
resultTitle.Parent            = resultPanel

local resultSub = Instance.new("TextLabel")
resultSub.Size                = UDim2.new(1, -20, 0, 30)
resultSub.Position            = UDim2.new(0, 10, 0, 90)
resultSub.BackgroundTransparency = 1
resultSub.Font                = Enum.Font.Gotham
resultSub.TextSize            = 15
resultSub.TextColor3          = Color3.fromRGB(175, 175, 175)
resultSub.Text                = ""
resultSub.Parent              = resultPanel

-- ─── HP update ───────────────────────────────────────────────────────────────
local function updateHearts(hearts: { TextLabel }, hp: number)
	for i, h in hearts do
		h.TextColor3 = i <= hp
			and Color3.fromRGB(255, 55, 75)
			or  Color3.fromRGB(55, 55, 55)
	end
end

local function flashPanel(panel: Frame, color: Color3)
	TweenService:Create(panel, TweenInfo.new(0.08), { BackgroundColor3 = color }):Play()
	task.delay(0.12, function()
		TweenService:Create(panel, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(10, 10, 22) }):Play()
	end)
end

-- ─── Remote listeners ────────────────────────────────────────────────────────
queueUpdate.OnClientEvent:Connect(function(status: string, extra: any)
	if status == "waiting" then
		queuePanel.Visible = true
		queueStatus.Text   = "Waiting for opponent... (" .. tostring(extra) .. "/2)"
	elseif status == "starting" then
		queueStatus.Text   = "Match found!  vs " .. tostring(extra) .. "  ..."
		task.delay(1.5, function() queuePanel.Visible = false end)
	elseif status == "left" then
		queuePanel.Visible = false
	end
end)

gameStart.OnClientEvent:Connect(function(oppName: string, hp: number)
	inGame   = true
	myHp     = hp
	oppHp    = hp
	maxHp    = hp
	hitCd    = 0
	dodgeCd  = 0

	local oppNameLabel = oppPanel:FindFirstChild("NameLabel") :: TextLabel?
	if oppNameLabel then oppNameLabel.Text = oppName end

	updateHearts(myHearts, myHp)
	updateHearts(oppHearts, oppHp)

	hud.Visible         = true
	queuePanel.Visible  = false
	resultPanel.Visible = false

	-- Capture bridge axis from character's facing direction at spawn
	task.delay(0.15, function()
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local look = root.CFrame.LookVector
			bridgeAxis = Vector3.new(look.X, 0, look.Z).Unit
		end
		lockControls()
	end)
end)

hitResult.OnClientEvent:Connect(function(outcome: string, newMyHp: number, newOppHp: number)
	myHp  = newMyHp
	oppHp = newOppHp
	updateHearts(myHearts, myHp)
	updateHearts(oppHearts, oppHp)

	if outcome == "hit" then
		flashPanel(oppPanel, Color3.fromRGB(180, 35, 35))
	elseif outcome == "taken" then
		flashPanel(myPanel, Color3.fromRGB(180, 35, 35))
	elseif outcome == "dodged" then
		dodgeLabel.Text      = "DODGED!"
		dodgeLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
		task.delay(0.8, function() dodgeLabel.Text = "" end)
	end
end)

gameEnd.OnClientEvent:Connect(function(won: boolean, otherName: string, reason: string)
	inGame             = false
	hud.Visible        = false
	unlockControls()

	resultTitle.Text       = won and "YOU WIN!" or "YOU LOSE"
	resultTitle.TextColor3 = won and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(220, 55, 55)
	resultSub.Text         = (won and "Defeated " or "Lost to ") .. otherName .. "  —  " .. reason
	resultPanel.Visible    = true

	task.delay(4.5, function()
		resultPanel.Visible = false
	end)
end)

-- ─── Input ───────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not inGame then return end
	local now = tick()

	if input.KeyCode == Enum.KeyCode.E then
		if now - hitCd < HIT_CD then return end
		hitCd = now
		pillowHit:FireServer()
		if hitTrack then
			hitTrack:Stop()
			hitTrack:Play()
		end

	elseif input.KeyCode == Enum.KeyCode.Q then
		if now - dodgeCd < DODGE_CD then return end
		dodgeCd = now
		pillowDodge:FireServer()
		dodgeLabel.Text       = "DODGING!"
		dodgeLabel.TextColor3 = Color3.fromRGB(180, 120, 255)
		if blockTrack then
			blockTrack:Stop()
			blockTrack:Play()
		end
		task.delay(0.65, function()
			if dodgeLabel.Text == "DODGING!" then dodgeLabel.Text = "" end
		end)
	end
end)

-- Dodge cooldown display
RunService.Heartbeat:Connect(function()
	if not inGame then return end

	local remaining = DODGE_CD - (tick() - dodgeCd)
	if remaining > 0.1 then
		dodgeLabel.Text       = string.format("Dodge: %.1fs", remaining)
		dodgeLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	elseif dodgeLabel.Text ~= "DODGING!" then
		dodgeLabel.Text       = "[Q] Dodge  READY"
		dodgeLabel.TextColor3 = Color3.fromRGB(180, 120, 255)
	end
end)
