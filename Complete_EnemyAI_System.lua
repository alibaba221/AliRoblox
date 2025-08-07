-- Complete Enemy AI System for Roblox Studio
-- This script handles spawning, detection, chasing, and damage for R6 rig enemies

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Configuration (Easy to modify)
local CONFIG = {
    -- Detection and Movement
    DETECTION_RANGE = 50, -- How far enemies can detect players (studs)
    CHASE_SPEED = 16, -- How fast enemies move when chasing (studs per second)
    WANDER_SPEED = 8, -- How fast enemies move when wandering (studs per second)
    
    -- Combat
    DAMAGE_PER_SECOND = 10, -- Damage dealt per second when in range
    DAMAGE_INTERVAL = 1, -- Time between damage ticks (seconds)
    HITBOX_RANGE = 3, -- Range of the damage hitbox (studs)
    
    -- Spawning
    SPAWN_INTERVAL = 10, -- Time between enemy spawns (seconds)
    MAX_ENEMIES = 5, -- Maximum number of enemies at once
    SPAWN_RADIUS = 20, -- Random spawn radius around spawn points (studs)
    
    -- Visual
    HITBOX_COLOR = Color3.fromRGB(255, 0, 0), -- Red hitbox color
    HITBOX_TRANSPARENCY = 0.5, -- Hitbox transparency (0 = opaque, 1 = invisible)
    
    -- Enemy Stats
    ENEMY_HEALTH = 100, -- Starting health for enemies
    ENEMY_MAX_HEALTH = 100, -- Maximum health for enemies
    
    -- Advanced Settings
    ENABLE_WANDERING = true, -- Whether enemies wander when not chasing
    WANDER_RADIUS = 30, -- How far enemies wander from spawn point
    ENABLE_DEBUG_MESSAGES = true, -- Whether to print debug messages to output
    ENABLE_DAMAGE_INDICATORS = true -- Whether to show damage numbers when hitting players
}

-- Variables
local enemies = {}
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
        if CONFIG.ENABLE_DAMAGE_INDICATORS then
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
end

-- Enemy AI Class
local EnemyAI = {}
EnemyAI.__index = EnemyAI

function EnemyAI.new(enemyModel)
    local self = setmetatable({}, EnemyAI)
    
    self.model = enemyModel
    self.humanoid = enemyModel:FindFirstChild("Humanoid")
    self.rootPart = enemyModel:FindFirstChild("HumanoidRootPart")
    self.hitbox = createHitbox(enemyModel)
    self.target = nil
    self.isChasing = false
    self.lastDamageTime = 0
    self.health = CONFIG.ENEMY_HEALTH
    self.spawnPosition = self.rootPart and self.rootPart.Position or Vector3.new(0, 0, 0)
    self.wanderTarget = nil
    self.lastWanderTime = 0
    
    if not self.humanoid or not self.rootPart then
        warn("Enemy model missing Humanoid or HumanoidRootPart!")
        return nil
    end
    
    -- Set up humanoid properties
    self.humanoid.WalkSpeed = CONFIG.CHASE_SPEED
    self.humanoid.MaxHealth = CONFIG.ENEMY_MAX_HEALTH
    self.humanoid.Health = self.health
    
    -- Connect events
    self.humanoid.Died:Connect(function()
        self:destroy()
    end)
    
    if CONFIG.ENABLE_DEBUG_MESSAGES then
        print("Enemy AI created for: " .. enemyModel.Name)
    end
    
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
            if CONFIG.ENABLE_DEBUG_MESSAGES then
                print("Enemy started chasing player!")
            end
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
            if CONFIG.ENABLE_DEBUG_MESSAGES then
                print("Enemy stopped chasing player!")
            end
        end
        
        -- Wandering behavior when not chasing
        if CONFIG.ENABLE_WANDERING then
            self:wander(currentTime)
        end
    end
end

function EnemyAI:wander(currentTime)
    -- Set new wander target if needed
    if not self.wanderTarget or currentTime - self.lastWanderTime > 5 then
        local randomAngle = math.random() * 2 * math.pi
        local randomDistance = math.random(5, CONFIG.WANDER_RADIUS)
        local offset = Vector3.new(
            math.cos(randomAngle) * randomDistance,
            0,
            math.sin(randomAngle) * randomDistance
        )
        
        self.wanderTarget = self.spawnPosition + offset
        self.lastWanderTime = currentTime
        self.humanoid.WalkSpeed = CONFIG.WANDER_SPEED
    end
    
    -- Move towards wander target
    if self.wanderTarget then
        self.humanoid:MoveTo(self.wanderTarget)
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
    
    if CONFIG.ENABLE_DEBUG_MESSAGES then
        print("Enemy destroyed. Total enemies: " .. #enemies)
    end
end

-- Spawning System
local function findSpawnPoints()
    local npcsFolder = workspace:FindFirstChild("NPCs")
    if not npcsFolder then
        warn("NPCs folder not found in workspace! Please create a folder named 'NPCs' and add your R6 rig models.")
        return {}
    end
    
    local spawnPoints = {}
    for _, child in pairs(npcsFolder:GetChildren()) do
        if child:IsA("Model") then
            table.insert(spawnPoints, child)
        end
    end
    
    if #spawnPoints == 0 then
        warn("No models found in NPCs folder! Please add R6 rig models to the NPCs folder.")
    end
    
    return spawnPoints
end

local function spawnEnemy()
    if #enemies >= CONFIG.MAX_ENEMIES then
        return
    end
    
    local spawnPoints = findSpawnPoints()
    if #spawnPoints == 0 then
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
        math.random(-CONFIG.SPAWN_RADIUS, CONFIG.SPAWN_RADIUS),
        0,
        math.random(-CONFIG.SPAWN_RADIUS, CONFIG.SPAWN_RADIUS)
    )
    
    if enemyClone:FindFirstChild("HumanoidRootPart") then
        enemyClone.HumanoidRootPart.CFrame = CFrame.new(spawnPosition + randomOffset)
    end
    
    -- Create enemy AI instance
    local enemyAI = EnemyAI.new(enemyClone)
    if enemyAI then
        table.insert(enemies, enemyAI)
        if CONFIG.ENABLE_DEBUG_MESSAGES then
            print("Enemy spawned! Total enemies: " .. #enemies)
        end
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
    if CONFIG.ENABLE_DEBUG_MESSAGES then
        print("=== Enemy AI System Initialized ===")
        print("Detection Range: " .. CONFIG.DETECTION_RANGE .. " studs")
        print("Chase Speed: " .. CONFIG.CHASE_SPEED .. " studs/sec")
        print("Damage: " .. CONFIG.DAMAGE_PER_SECOND .. " per second")
        print("Max Enemies: " .. CONFIG.MAX_ENEMIES)
        print("Spawn Interval: " .. CONFIG.SPAWN_INTERVAL .. " seconds")
        print("==================================")
    end
    
    -- Start the update loop
    RunService.Heartbeat:Connect(updateEnemies)
    
    -- Start spawning
    spawnEnemy() -- Spawn initial enemy
    startSpawning()
end

-- Start the system
init()

return EnemyAI