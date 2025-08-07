-- Enemy AI Client Script
-- This script handles client-side effects like damage indicators and UI

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local CONFIG = {
    DAMAGE_INDICATOR_DURATION = 1,
    DAMAGE_INDICATOR_FADE_TIME = 0.5,
    DAMAGE_INDICATOR_OFFSET = Vector2.new(0, -50),
    DAMAGE_INDICATOR_COLOR = Color3.fromRGB(255, 0, 0),
    DAMAGE_INDICATOR_FONT = Enum.Font.GothamBold,
    DAMAGE_INDICATOR_SIZE = UDim2.new(0, 100, 0, 30)
}

-- Create damage indicator
local function createDamageIndicator(damage, position)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DamageIndicator"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui
    
    local damageLabel = Instance.new("TextLabel")
    damageLabel.Text = "-" .. tostring(damage)
    damageLabel.Size = CONFIG.DAMAGE_INDICATOR_SIZE
    damageLabel.BackgroundTransparency = 1
    damageLabel.TextColor3 = CONFIG.DAMAGE_INDICATOR_COLOR
    damageLabel.TextScaled = true
    damageLabel.Font = CONFIG.DAMAGE_INDICATOR_FONT
    damageLabel.Parent = screenGui
    
    -- Position the damage indicator at the player's screen position
    local camera = workspace.CurrentCamera
    if camera then
        local screenPosition, onScreen = camera:WorldToScreenPoint(position)
        if onScreen then
            damageLabel.Position = UDim2.new(0, screenPosition.X, 0, screenPosition.Y)
        else
            damageLabel.Position = UDim2.new(0.5, -50, 0.5, -15)
        end
    end
    
    -- Animate the damage indicator
    local tweenInfo = TweenInfo.new(
        CONFIG.DAMAGE_INDICATOR_DURATION,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tween = TweenService:Create(damageLabel, tweenInfo, {
        Position = damageLabel.Position + CONFIG.DAMAGE_INDICATOR_OFFSET,
        TextTransparency = 1
    })
    
    tween:Play()
    
    -- Clean up
    tween.Completed:Connect(function()
        screenGui:Destroy()
    end)
end

-- Handle damage events from server
local function onDamageReceived(damage, position)
    createDamageIndicator(damage, position or player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or Vector3.new(0, 0, 0))
end

-- Connect to server events (if using RemoteEvents)
-- This would be implemented if you want to use RemoteEvents for damage communication
-- For now, the damage is handled directly in the server script

-- Optional: Create a debug UI to show enemy information
local function createDebugUI()
    if not CONFIG.ENABLE_DEBUG_MESSAGES then return end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EnemyAIDebug"
    screenGui.Parent = playerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 100)
    frame.Position = UDim2.new(1, -220, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    
    local title = Instance.new("TextLabel")
    title.Text = "Enemy AI Debug"
    title.Size = UDim2.new(1, 0, 0, 20)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.Gotham
    title.Parent = frame
    
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Text = "Enemies: 0"
    infoLabel.Size = UDim2.new(1, 0, 0, 20)
    infoLabel.Position = UDim2.new(0, 0, 0, 25)
    infoLabel.BackgroundTransparency = 1
    infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    infoLabel.TextScaled = true
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.Parent = frame
    
    -- Update debug info
    RunService.Heartbeat:Connect(function()
        local enemies = workspace:GetChildren()
        local enemyCount = 0
        
        for _, child in pairs(enemies) do
            if child:FindFirstChild("Humanoid") and child:FindFirstChild("DamageHitbox") then
                enemyCount = enemyCount + 1
            end
        end
        
        infoLabel.Text = "Enemies: " .. enemyCount
    end)
end

-- Initialize client
local function init()
    -- Create debug UI if enabled
    createDebugUI()
    
    print("Enemy AI Client initialized!")
end

init()