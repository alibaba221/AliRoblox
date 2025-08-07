-- Enemy AI System
-- This script handles the complete enemy AI behavior including spawning, detection, chasing, and damage

local EnemyAI = {}
EnemyAI.__index = EnemyAI

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Configuration
local CONFIG = {
    DETECTION_RANGE = 50, -- Studs
    CHASE_SPEED = 16, -- Studs per second
    DAMAGE_PER_SECOND = 10,
    DAMAGE_INTERVAL = 1, -- Seconds
    SPAWN_INTERVAL = 10, -- Seconds between spawns
    MAX_ENEMIES = 5, -- Maximum enemies at once
    HITBOX_RANGE = 3, -- Studs for damage hitbox
    HITBOX_COLOR = Color3.fromRGB(255, 0, 0), -- Red
    HITBOX_TRANSPARENCY = 0.5
}

-- Variables
local enemies = {}
local spawnPoints = {}
local isSpawning = false

-- Utility Functions
local function createHitbox(parent)
    local hitbox = Instance.new("Part")
    hitbox.Name = "DamageHitbox"
    hitbox.Shape = Enum.PartType.Ball
    hitbox.Size = Vector3.new(CONFIG.HITBOX_RANGE * 2, CONFIG.HITBOX_RANGE * 2, CONFIG.HITBOX_RANGE * 2)
    hitbox.Transparency = CONFIG.HITBOX_TRANSPARENCY
    hitbox.CanCollide = false
    hitbox.Anchored = true
    
    -- Create hitbox material
    local hitboxMaterial = Instance.new("SurfaceAppearance")
    hitboxMaterial.Color3 = CONFIG.HITBOX_COLOR
    hitboxMaterial.Transparency = CONFIG.HITBOX_TRANSPARENCY
    hitboxMaterial.Parent = hitbox
    
    hitbox.Parent = parent
    return hitbox
end

local function getClosestPlayer(enemyPosition)
    local closestPlayer = nil
    local closestDistance = math.huge
    
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (enemyPosition - player.Character.HumanoidRootPart.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestPlayer = player
            end
        end
    end
    
    return closestPlayer, closestDistance
end

local function damagePlayer(player, damage)
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        local humanoid = player.Character.Humanoid
        humanoid.Health = humanoid.Health - damage
        
        -- Create damage indicator
        local damageGui = Instance.new("ScreenGui")
        local damageLabel = Instance.new("TextLabel")
        damageLabel.Text = "-" .. tostring(damage)
        damageLabel.Size = UDim2.new(0, 100, 0, 30)
        damageLabel.Position = UDim2.new(0.5, -50, 0.5, -15)
        damageLabel.BackgroundTransparency = 1
        damageLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        damageLabel.TextScaled = true
        damageLabel.Font = Enum.Font.GothamBold
        damageLabel.Parent = damageGui
        damageGui.Parent = player.PlayerGui
        
        -- Animate damage text
        local tween = TweenService:Create(damageLabel, TweenInfo.new(1), {
            Position = UDim2.new(0.5, -50, 0.4, -15),
            TextTransparency = 1
        })
        tween:Play()
        
        Debris:AddItem(damageGui, 1)
    end
end

-- Enemy AI Class
function EnemyAI.new(enemyModel)
    local self = setmetatable({}, EnemyAI)
    
    self.model = enemyModel
    self.humanoid = enemyModel:FindFirstChild("Humanoid")
    self.rootPart = enemyModel:FindFirstChild("HumanoidRootPart")
    self.hitbox = createHitbox(enemyModel)
    self.target = nil
    self.isChasing = false
    self.lastDamageTime = 0
    self.health = 100
    
    if not self.humanoid or not self.rootPart then
        warn("Enemy model missing Humanoid or HumanoidRootPart!")
        return nil
    end
    
    -- Set up humanoid properties
    self.humanoid.WalkSpeed = CONFIG.CHASE_SPEED
    self.humanoid.MaxHealth = self.health
    self.humanoid.Health = self.health
    
    -- Connect events
    self.humanoid.Died:Connect(function()
        self:destroy()
    end)
    
    return self
end

function EnemyAI:update()
    if not self.model or not self.humanoid or self.humanoid.Health <= 0 then
        return
    end
    
    local currentTime = tick()
    local enemyPosition = self.rootPart.Position
    
    -- Check for nearby players
    local closestPlayer, distance = getClosestPlayer(enemyPosition)
    
    if distance <= CONFIG.DETECTION_RANGE then
        if not self.isChasing then
            self.isChasing = true
            print("Enemy started chasing player!")
        end
        
        self.target = closestPlayer
        
        -- Move towards player
        if self.target and self.target.Character and self.target.Character:FindFirstChild("HumanoidRootPart") then
            local targetPosition = self.target.Character.HumanoidRootPart.Position
            self.humanoid:MoveTo(targetPosition)
            
            -- Check if close enough to damage
            if distance <= CONFIG.HITBOX_RANGE then
                if currentTime - self.lastDamageTime >= CONFIG.DAMAGE_INTERVAL then
                    damagePlayer(self.target, CONFIG.DAMAGE_PER_SECOND)
                    self.lastDamageTime = currentTime
                end
            end
        end
    else
        if self.isChasing then
            self.isChasing = false
            self.target = nil
            print("Enemy stopped chasing player!")
        end
    end
end

function EnemyAI:destroy()
    if self.hitbox then
        self.hitbox:Destroy()
    end
    
    if self.model then
        self.model:Destroy()
    end
    
    -- Remove from enemies table
    for i, enemy in pairs(enemies) do
        if enemy == self then
            table.remove(enemies, i)
            break
        end
    end
end

-- Spawning System
local function findSpawnPoints()
    local npcsFolder = workspace:FindFirstChild("NPCs")
    if not npcsFolder then
        warn("NPCs folder not found in workspace!")
        return {}
    end
    
    local spawnPoints = {}
    for _, child in pairs(npcsFolder:GetChildren()) do
        if child:IsA("Model") then
            table.insert(spawnPoints, child)
        end
    end
    
    return spawnPoints
end

local function spawnEnemy()
    if #enemies >= CONFIG.MAX_ENEMIES then
        return
    end
    
    local spawnPoints = findSpawnPoints()
    if #spawnPoints == 0 then
        warn("No spawn points found in NPCs folder!")
        return
    end
    
    -- Select random spawn point
    local spawnPoint = spawnPoints[math.random(1, #spawnPoints)]
    
    -- Clone the enemy model
    local enemyClone = spawnPoint:Clone()
    enemyClone.Parent = workspace
    
    -- Position the enemy at a random location near the spawn point
    local spawnPosition = spawnPoint:GetPrimaryPartCFrame().Position
    local randomOffset = Vector3.new(
        math.random(-20, 20),
        0,
        math.random(-20, 20)
    )
    
    if enemyClone:FindFirstChild("HumanoidRootPart") then
        enemyClone.HumanoidRootPart.CFrame = CFrame.new(spawnPosition + randomOffset)
    end
    
    -- Create enemy AI instance
    local enemyAI = EnemyAI.new(enemyClone)
    if enemyAI then
        table.insert(enemies, enemyAI)
        print("Enemy spawned! Total enemies: " .. #enemies)
    end
end

-- Main update loop
local function updateEnemies()
    for _, enemy in pairs(enemies) do
        enemy:update()
    end
end

-- Spawning loop
local function startSpawning()
    if isSpawning then return end
    isSpawning = true
    
    while isSpawning do
        spawnEnemy()
        wait(CONFIG.SPAWN_INTERVAL)
    end
end

-- Initialize the system
local function init()
    print("Enemy AI System initialized!")
    
    -- Start the update loop
    RunService.Heartbeat:Connect(updateEnemies)
    
    -- Start spawning
    spawnEnemy() -- Spawn initial enemy
    startSpawning()
end

-- Start the system
init()

return EnemyAI