local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local remotes  = ReplicatedStorage:WaitForChild("TomahawkRemotes")
local thStart  = remotes:WaitForChild("THStart")
local thResult = remotes:WaitForChild("THResult")
local thEnd    = remotes:WaitForChild("THEnd")
local thFly    = remotes:WaitForChild("THFly")

-- ─── Animation ────────────────────────────────────────────────────────────────
-- Replace with your tomahawk throw animation ID
local THROW_ANIM_ID = "rbxassetid://97492992621880"

-- ─── Power bar settings ───────────────────────────────────────────────────────
local POWER_SPEED  = 1.4   -- oscillations per second (higher = faster)
local IDEAL_WIDTH  = 0.20  -- width of the green zone (fraction of bar)
local IDEAL_MIN    = 0.35  -- randomized each power phase
local IDEAL_MAX    = 0.60

-- ─── State ────────────────────────────────────────────────────────────────────
local phase        = "idle"  -- "idle" | "aim" | "power" | "throw"
local powerValue   = 0       -- 0–1, from sine wave
local powerTick    = 0       -- offset so bar starts at 0
local aimDirection: Vector3? = nil
local aimOrigin:   Vector3? = nil
local inputConn:   RBXScriptConnection? = nil
local throwTrack:  AnimationTrack? = nil

-- ─── Root GUI ─────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "TomahawkGui"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = false
gui.Parent         = playerGui

-- ─── Crosshair ────────────────────────────────────────────────────────────────
local crosshair = Instance.new("Frame")
crosshair.Name                 = "Crosshair"
crosshair.AnchorPoint          = Vector2.new(0.5, 0.5)
crosshair.Position             = UDim2.new(0.5, 0, 0.5, 0)
crosshair.Size                 = UDim2.new(0, 36, 0, 36)
crosshair.BackgroundTransparency = 1
crosshair.Parent               = gui

local function makeLine(w: number, h: number, ox: number, oy: number)
	local f = Instance.new("Frame")
	f.AnchorPoint           = Vector2.new(0.5, 0.5)
	f.Position              = UDim2.new(0.5, ox, 0.5, oy)
	f.Size                  = UDim2.new(0, w, 0, h)
	f.BackgroundColor3      = Color3.fromRGB(255, 255, 255)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel       = 0
	f.Parent                = crosshair
end
makeLine(16, 2,  0, 0)   -- horizontal
makeLine(2,  16, 0, 0)   -- vertical
-- center dot
local dot = Instance.new("Frame")
dot.AnchorPoint           = Vector2.new(0.5, 0.5)
dot.Position              = UDim2.new(0.5, 0, 0.5, 0)
dot.Size                  = UDim2.new(0, 4, 0, 4)
dot.BackgroundColor3      = Color3.fromRGB(255, 80, 80)
dot.BackgroundTransparency = 0
dot.BorderSizePixel       = 0
dot.Parent                = crosshair
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

-- ─── Phase hint label ─────────────────────────────────────────────────────────
local hintLabel = Instance.new("TextLabel")
hintLabel.AnchorPoint           = Vector2.new(0.5, 0)
hintLabel.Position              = UDim2.new(0.5, 0, 0.5, 28)
hintLabel.Size                  = UDim2.new(0, 260, 0, 28)
hintLabel.BackgroundTransparency = 1
hintLabel.Text                  = "[LMB] Aim"
hintLabel.TextColor3            = Color3.fromRGB(255, 255, 255)
hintLabel.Font                  = Enum.Font.GothamBold
hintLabel.TextSize              = 16
hintLabel.Parent                = gui

-- ─── Power bar panel ──────────────────────────────────────────────────────────
local powerPanel = Instance.new("Frame")
powerPanel.AnchorPoint           = Vector2.new(0.5, 1)
powerPanel.Position              = UDim2.new(0.5, 0, 1, -80)
powerPanel.Size                  = UDim2.new(0, 300, 0, 60)
powerPanel.BackgroundColor3      = Color3.fromRGB(10, 10, 20)
powerPanel.BackgroundTransparency = 0.2
powerPanel.BorderSizePixel       = 0
powerPanel.Visible               = false
powerPanel.Parent                = gui
Instance.new("UICorner", powerPanel).CornerRadius = UDim.new(0, 10)
local pStroke = Instance.new("UIStroke", powerPanel)
pStroke.Color = Color3.fromRGB(180, 140, 60); pStroke.Thickness = 1.5

local powerTitle = Instance.new("TextLabel")
powerTitle.Size                  = UDim2.new(1, 0, 0, 20)
powerTitle.Position              = UDim2.new(0, 0, 0, 4)
powerTitle.BackgroundTransparency = 1
powerTitle.Text                  = "POWER"
powerTitle.TextColor3            = Color3.fromRGB(220, 180, 80)
powerTitle.Font                  = Enum.Font.GothamBold
powerTitle.TextSize              = 13
powerTitle.Parent                = powerPanel

local barBg = Instance.new("Frame")
barBg.Size              = UDim2.new(1, -20, 0, 18)
barBg.Position          = UDim2.new(0, 10, 0, 30)
barBg.BackgroundColor3  = Color3.fromRGB(30, 30, 40)
barBg.BorderSizePixel   = 0
barBg.Parent            = powerPanel
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 6)

-- Green "ideal" zone overlay inside bar track
local idealZone = Instance.new("Frame")
idealZone.Position          = UDim2.new(IDEAL_MIN, 0, 0, 0)
idealZone.Size              = UDim2.new(IDEAL_MAX - IDEAL_MIN, 0, 1, 0)
idealZone.BackgroundColor3  = Color3.fromRGB(60, 200, 80)
idealZone.BackgroundTransparency = 0.55
idealZone.BorderSizePixel   = 0
idealZone.ZIndex            = 2
idealZone.Parent            = barBg
Instance.new("UICorner", idealZone).CornerRadius = UDim.new(0, 6)

local powerFill = Instance.new("Frame")
powerFill.Size              = UDim2.new(0, 0, 1, 0)
powerFill.BackgroundColor3  = Color3.fromRGB(220, 180, 60)
powerFill.BorderSizePixel   = 0
powerFill.ZIndex            = 3
powerFill.Parent            = barBg
Instance.new("UICorner", powerFill).CornerRadius = UDim.new(0, 6)

-- ─── Result panel ─────────────────────────────────────────────────────────────
local resultPanel = Instance.new("Frame")
resultPanel.AnchorPoint           = Vector2.new(0.5, 0.5)
resultPanel.Position              = UDim2.new(0.5, 0, 0.45, 0)
resultPanel.Size                  = UDim2.new(0, 300, 0, 130)
resultPanel.BackgroundColor3      = Color3.fromRGB(10, 10, 20)
resultPanel.BackgroundTransparency = 0.1
resultPanel.BorderSizePixel       = 0
resultPanel.Visible               = false
resultPanel.Parent                = gui
Instance.new("UICorner", resultPanel).CornerRadius = UDim.new(0, 14)

local resultTitle = Instance.new("TextLabel")
resultTitle.Size                = UDim2.new(1, 0, 0, 60)
resultTitle.Position            = UDim2.new(0, 0, 0, 14)
resultTitle.BackgroundTransparency = 1
resultTitle.Font                = Enum.Font.GothamBold
resultTitle.TextSize            = 40
resultTitle.Text                = ""
resultTitle.Parent              = resultPanel

local resultSub = Instance.new("TextLabel")
resultSub.Size                = UDim2.new(1, -20, 0, 30)
resultSub.Position            = UDim2.new(0, 10, 0, 80)
resultSub.BackgroundTransparency = 1
resultSub.Font                = Enum.Font.Gotham
resultSub.TextSize            = 15
resultSub.TextColor3          = Color3.fromRGB(200, 200, 200)
resultSub.Text                = ""
resultSub.Parent              = resultPanel

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function sinkInput(_n, _s, _i) return Enum.ContextActionResult.Sink end

local function lockMovement()
	ContextActionService:BindAction("THLock", sinkInput, false,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Space, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.Up, Enum.KeyCode.Down)
end

local function unlockMovement()
	ContextActionService:UnbindAction("THLock")
end

local function setFirstPerson()
	-- CameraMaxZoomDistance = 0 forces the engine into first-person
	player.CameraMaxZoomDistance = 0
	player.CameraMinZoomDistance = 0
end

local function restoreCamera()
	-- Briefly raise CameraMinZoomDistance so the engine is forced to
	-- push the camera out to third-person, then release the constraint.
	player.CameraMaxZoomDistance = 400
	player.CameraMinZoomDistance = 12
	task.delay(0.15, function()
		player.CameraMinZoomDistance = 0.5  -- Roblox default
	end)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function flashCrosshair(color: Color3)
	dot.BackgroundColor3 = color
	task.delay(0.25, function() dot.BackgroundColor3 = Color3.fromRGB(255, 80, 80) end)
end

local function playThrowAnimation()
	local char     = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if THROW_ANIM_ID == "rbxassetid://0" then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = THROW_ANIM_ID
	local track = humanoid:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	throwTrack = track
end

-- ─── Phase transitions ────────────────────────────────────────────────────────
local function endSession()
	phase = "idle"
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if throwTrack then throwTrack:Stop(); throwTrack = nil end
	unlockMovement()
	restoreCamera()
	gui.Enabled        = false
	powerPanel.Visible = false
	resultPanel.Visible = false
end

local function showResult(hit: boolean, cash: number, label: string)
	powerPanel.Visible   = false
	crosshair.Visible    = false
	hintLabel.Visible    = false

	resultTitle.Text       = label
	resultTitle.TextColor3 = hit
		and Color3.fromRGB(255, 200, 50)
		or  Color3.fromRGB(180, 80, 80)
	resultSub.Text = hit
		and ("+" .. cash .. " $  earned!")
		or  "Better luck next time!"
	resultPanel.Visible = true

	task.delay(2.5, function()
		endSession()
	end)
end

local function startPowerPhase()
	phase     = "power"
	powerTick = tick()

	-- Randomise green zone position within the bar
	IDEAL_MIN = math.random() * (1 - IDEAL_WIDTH)
	IDEAL_MAX = IDEAL_MIN + IDEAL_WIDTH
	idealZone.Position = UDim2.new(IDEAL_MIN, 0, 0, 0)
	idealZone.Size     = UDim2.new(IDEAL_WIDTH, 0, 1, 0)

	powerPanel.Visible = true
	crosshair.Visible  = false
	hintLabel.Text     = "[LMB] Release"
	hintLabel.Visible  = true

	if inputConn then inputConn:Disconnect() end
	inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or phase ~= "power" then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

		phase = "throw"
		if inputConn then inputConn:Disconnect(); inputConn = nil end
		powerPanel.Visible = false
		hintLabel.Visible  = false

		local lockedPower = powerValue

		-- Send to server
		if aimOrigin and aimDirection then
			thResult:FireServer(aimOrigin, aimDirection, lockedPower)
		end

		-- playThrowAnimation()  -- re-enable once animation is fixed
	end)
end

local function startAimPhase()
	phase             = "aim"
	crosshair.Visible = true
	hintLabel.Text    = "[LMB] Lock Aim"
	hintLabel.Visible = true

	if inputConn then inputConn:Disconnect() end
	inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or phase ~= "aim" then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

		-- Capture aim from camera centre
		local cf = camera.CFrame
		aimOrigin    = cf.Position
		aimDirection = cf.LookVector

		flashCrosshair(Color3.fromRGB(80, 220, 255))
		if inputConn then inputConn:Disconnect(); inputConn = nil end

		task.delay(0.2, startPowerPhase)
	end)
end

-- ─── Power bar animation (RunService loop) ────────────────────────────────────
RunService.Heartbeat:Connect(function()
	if phase ~= "power" then return end

	local elapsed = tick() - powerTick
	powerValue = (math.sin(elapsed * POWER_SPEED * math.pi * 2 - math.pi / 2) + 1) / 2

	powerFill.Size = UDim2.new(powerValue, 0, 1, 0)

	local inIdeal = powerValue >= IDEAL_MIN and powerValue <= IDEAL_MAX
	powerFill.BackgroundColor3 = inIdeal
		and Color3.fromRGB(80, 220, 80)
		or  Color3.fromRGB(220, 140, 40)
end)

-- ─── Flying tomahawk visual ───────────────────────────────────────────────────
local function flyTomahawk(origin: Vector3, dest: Vector3)
	local template = ReplicatedStorage:FindFirstChild("Tomahawk")

	-- Clone the template (Model or BasePart) or fall back to a plain part
	local flyModel: Model?    = nil
	local flyPart:  BasePart? = nil

	if template and template:IsA("Model") then
		flyModel = (template :: Model):Clone()
		for _, p in flyModel:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.Anchored   = true
				p.CastShadow = false
			end
		end
		flyModel.Parent = workspace
	elseif template and template:IsA("BasePart") then
		flyPart             = (template :: BasePart):Clone()
		flyPart.Anchored    = true
		flyPart.CanCollide  = false
		flyPart.CastShadow  = false
		flyPart.Parent      = workspace
	else
		local p             = Instance.new("Part")
		p.Size              = Vector3.new(0.15, 0.5, 1.8)
		p.Color             = Color3.fromRGB(100, 60, 20)
		p.Material          = Enum.Material.SmoothPlastic
		p.Anchored          = true
		p.CanCollide        = false
		p.CastShadow        = false
		p.Parent            = workspace
		flyPart             = p
	end

	local dir         = (dest - origin).Unit
	local dist        = (dest - origin).Magnitude
	local FLIGHT_TIME = math.clamp(dist / 120, 0.25, 0.6)
	local startT      = tick()

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local t   = math.min((tick() - startT) / FLIGHT_TIME, 1)
		local pos = origin:Lerp(dest, t)
		local spin = (tick() - startT) * math.pi * 9
		local cf   = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(spin, 0, 0)

		if flyModel then
			flyModel:PivotTo(cf)
		elseif flyPart then
			flyPart.CFrame = cf
		end

		if t >= 1 then
			conn:Disconnect()
			task.delay(0.8, function()
				if flyModel then flyModel:Destroy() end
				if flyPart  then flyPart:Destroy()  end
			end)
		end
	end)
end

-- ─── Server events ────────────────────────────────────────────────────────────
thStart.OnClientEvent:Connect(function(_stationNum: number, _targetPos: Vector3, _targetSize: Vector3)
	-- Short delay so the teleport settles before locking camera
	task.delay(0.4, function()
		setFirstPerson()
		lockMovement()
		gui.Enabled = true
		startAimPhase()
	end)
end)

thEnd.OnClientEvent:Connect(function(hit: boolean, cash: number, label: string, _hitPos: any)
	task.delay(3, function()
		showResult(hit, cash, label)
	end)
end)

thFly.OnClientEvent:Connect(function(origin: Vector3, dest: Vector3)
	flyTomahawk(origin, dest)
end)
