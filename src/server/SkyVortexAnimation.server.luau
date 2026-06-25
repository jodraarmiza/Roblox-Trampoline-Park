-- Sky Vortex - Adults Zone Animation Script
-- Pulsing neon, color cycling vortex rings, spotlight sweeps, and beam flickering

local zone = game.Workspace:FindFirstChild("Zone 3 Adult")
if not zone then return end

local neonCyan = Color3.fromRGB(0, 255, 255)
local neonPink = Color3.fromRGB(255, 0, 255)
local neonPurple = Color3.fromRGB(180, 0, 255)

-- Collect all neon parts and point lights
local neonParts = {}
local pointLights = {}

local function collectNeonElements()
    table.clear(neonParts)
    table.clear(pointLights)
    for _, desc in zone:GetDescendants() do
        if desc:IsA("BasePart") and desc.Material == Enum.Material.Neon then
            table.insert(neonParts, desc)
        end
        if desc:IsA("PointLight") then
            table.insert(pointLights, desc)
        end
    end
end
collectNeonElements()

zone.DescendantAdded:Connect(function(desc)
    if desc:IsA("BasePart") and desc.Material == Enum.Material.Neon then
        table.insert(neonParts, desc)
    end
    if desc:IsA("PointLight") then
        table.insert(pointLights, desc)
    end
end)

-- 1. Gentle pulse on all neon PointLights (sine wave based on position)
local function pulseNeonLights()
    local t = 0
    while true do
        t = t + 0.03
        for _, light in pointLights do
            if light and light.Parent then
                local part = light.Parent
                if part:IsA("BasePart") then
                    local phase = part.Position.X * 0.04 + part.Position.Z * 0.03
                    local pulse = math.sin(t * 2 + phase) * 0.3 + 0.7
                    light.Brightness = math.max(0.5, light.Brightness * 0.9 + pulse * 0.1)
                end
            end
        end
        task.wait(0.05)
    end
end

-- 2. Color cycling on vortex ring edges (cyan -> pink -> purple -> cyan)
local vortexEdges = {}
local function collectVortexEdges()
    local vortexFolder = zone:FindFirstChild("MainVortexHub")
    if not vortexFolder then return end
    for _, desc in vortexFolder:GetDescendants() do
        if desc:IsA("BasePart") and desc.Name == "VortexNeonEdge" then
            table.insert(vortexEdges, desc)
        end
    end
end
collectVortexEdges()

local function cycleVortexColors()
    local t = 0
    while true do
        t = t + 0.015
        for i, edge in vortexEdges do
            if edge and edge.Parent then
                local phase = (t + i * 0.15) % 3
                local color
                if phase < 1 then
                    color = neonCyan:Lerp(neonPink, phase)
                elseif phase < 2 then
                    color = neonPink:Lerp(neonPurple, phase - 1)
                else
                    color = neonPurple:Lerp(neonCyan, phase - 2)
                end
                edge.Color = color
                local light = edge:FindFirstChildOfClass("PointLight")
                if light then light.Color = color end
            end
        end
        task.wait(0.08)
    end
end

-- 3. Spotlight brightness sweep (outer ring spotlights pulse in sequence)
local spotlights = {}
local function collectSpotlights()
    local spotFolder = zone:FindFirstChild("SpotlightBeams")
    if not spotFolder then return end
    for _, desc in spotFolder:GetDescendants() do
        if desc:IsA("SpotLight") then
            table.insert(spotlights, desc)
        end
    end
end
collectSpotlights()

local function sweepSpotlights()
    local t = 0
    while true do
        t = t + 0.02
        for i, spot in spotlights do
            if spot and spot.Parent then
                local phase = math.sin(t * 1.5 + i * 0.5) * 0.5 + 0.5
                spot.Brightness = 3 + phase * 7
            end
        end
        task.wait(0.05)
    end
end

-- 4. Light beam transparency flicker (subtle)
local lightBeams = {}
local function collectBeams()
    local spotFolder = zone:FindFirstChild("SpotlightBeams")
    if not spotFolder then return end
    for _, desc in spotFolder:GetDescendants() do
        if desc:IsA("BasePart") and (desc.Name == "LightBeam" or desc.Name == "InnerLightBeam" or desc.Name == "CenterBeam") then
            table.insert(lightBeams, desc)
        end
    end
end
collectBeams()

local function flickerBeams()
    local t = 0
    while true do
        t = t + 0.04
        for i, beam in lightBeams do
            if beam and beam.Parent then
                local flicker = math.sin(t * 3 + i * 1.2) * 0.05
                beam.Transparency = math.clamp(0.85 + flicker, 0.8, 0.95)
            end
        end
        task.wait(0.06)
    end
end

-- 5. Heart outline pulse (pink glow intensifies periodically)
local heartEdges = {}
local function collectHeartEdges()
    local heartFolder = zone:FindFirstChild("HeartPlatform")
    if not heartFolder then return end
    for _, desc in heartFolder:GetDescendants() do
        if desc:IsA("BasePart") and desc.Name == "HeartOutline" then
            table.insert(heartEdges, desc)
        end
    end
end
collectHeartEdges()

local function pulseHeart()
    local t = 0
    while true do
        t = t + 0.03
        -- Heartbeat-like pulse: quick bright then slow dim
        local beat = math.abs(math.sin(t * 1.8))
        local pulse = beat * beat  -- Sharper pulse
        for _, edge in heartEdges do
            if edge and edge.Parent then
                edge.Transparency = 0.1 + (1 - pulse) * 0.4
            end
        end
        task.wait(0.04)
    end
end

-- Launch all animation loops
task.spawn(pulseNeonLights)
task.spawn(cycleVortexColors)
task.spawn(sweepSpotlights)
task.spawn(flickerBeams)
task.spawn(pulseHeart)
