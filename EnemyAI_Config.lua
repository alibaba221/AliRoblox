-- Enemy AI Configuration
-- Modify these values to customize the enemy AI behavior

local EnemyAIConfig = {
    -- Detection and Movement
    DETECTION_RANGE = 50, -- How far the enemy can detect players (in studs)
    CHASE_SPEED = 16, -- How fast the enemy moves when chasing (studs per second)
    WANDER_SPEED = 8, -- How fast the enemy moves when wandering (studs per second)
    
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
    ENABLE_DAMAGE_INDICATORS = true, -- Whether to show damage numbers when hitting players
}

return EnemyAIConfig