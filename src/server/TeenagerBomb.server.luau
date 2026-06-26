local Players = game:GetService("Players")

-- ─── Tuning ────────────────────────────────────────────────────────────────────
local TOUCH_DEBOUNCE = 1 -- seconds; stops the bomb bouncing straight back to whoever just passed it

-- ─── State ─────────────────────────────────────────────────────────────────────
-- Weak keys so destroyed Bomb clones (one gets made per minigame round) don't
-- pile up in these tables for the lifetime of the server.
local hookedTools  = setmetatable({}, { __mode = "k" }) :: { [Tool]: boolean }
local lastPassTime = setmetatable({}, { __mode = "k" }) :: { [Tool]: number }

-- ─── Helpers ───────────────────────────────────────────────────────────────────
local function getHolderCharacter(tool: Tool): Model?
	local parent = tool.Parent
	if parent and parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
		return parent
	end
	return nil
end

local function onHandleTouched(tool: Tool, hit: BasePart)
	local now = tick()
	if now - (lastPassTime[tool] or 0) < TOUCH_DEBOUNCE then return end

	local holderCharacter = getHolderCharacter(tool)
	if not holderCharacter then return end -- bomb isn't currently equipped by anyone

	local victimCharacter = hit.Parent
	if not victimCharacter or victimCharacter == holderCharacter then return end

	local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
	if not victimPlayer then return end -- only pass to real players, not props/NPCs

	local victimHumanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
	if not victimHumanoid or victimHumanoid.Health <= 0 then return end

	lastPassTime[tool] = now
	tool.Parent = victimCharacter -- direct Parent assignment auto-equips the Tool on its new holder
end

local function setupBombTool(tool: Tool)
	if hookedTools[tool] then return end
	hookedTools[tool] = true

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		warn("[TeenagerBomb] '" .. tool:GetFullName() .. "' is missing a BasePart named 'Handle'")
		return
	end

	handle.Touched:Connect(function(hit: BasePart)
		onHandleTouched(tool, hit)
	end)
end

local function isBombTool(obj: Instance): boolean
	return obj:IsA("Tool") and obj.Name == "Bomb"
end

-- ─── Hook every Bomb clone the minigame loop hands out ───────────────────────
for _, obj in workspace:GetDescendants() do
	if isBombTool(obj) then setupBombTool(obj :: Tool) end
end

workspace.DescendantAdded:Connect(function(obj)
	if isBombTool(obj) then setupBombTool(obj :: Tool) end
end)
