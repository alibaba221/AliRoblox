# NPC Follow System with Damage

This is an enhanced version of the NPC Follow System that includes a damage system where AI NPCs can deal damage to players within their damage hitbox.

## Features

### Original NPC Follow System
- AI detects players within a set range and follows them
- Stops chasing when players move outside the range
- Pathfinding and formation support
- Visual and audio feedback

### New Damage System
- **Red Damage Hitbox**: Visible red hitbox attached to each NPC
- **10 Damage Per Second**: Configurable damage dealt to players in the hitbox
- **Visual Effects**: Damage particles appear when damage is dealt
- **Development Toggle**: Easily switch hitbox visibility for testing/production

## File Structure

```
Workspace
└── NPCS (Folder)
    ├── NPC1 (Model)
    ├── NPC2 (Model)
    └── ... (More NPC Models)

ServerScriptService
└── NPCFollowServer.lua (Script)

StarterPlayer
└── StarterPlayerScripts
    └── NPCFollowClient.lua (LocalScript) [OPTIONAL]

ReplicatedStorage
└── NPCFollowModules (Folder)
    └── NPCFollowConfig.lua (ModuleScript)
```

## Damage System Configuration

The damage system can be configured in `NPCFollowConfig.lua`:

```lua
-- DAMAGE SYSTEM SETTINGS
NPCFollowConfig.ENABLE_DAMAGE_SYSTEM = true -- Enable/disable entire damage system
NPCFollowConfig.DAMAGE_PER_SECOND = 10 -- Damage dealt per second
NPCFollowConfig.DAMAGE_HITBOX_SIZE = Vector3.new(6, 6, 6) -- Hitbox size
NPCFollowConfig.DAMAGE_HITBOX_OFFSET = Vector3.new(0, 0, 0) -- Offset from NPC center
NPCFollowConfig.DAMAGE_HITBOX_VISIBLE = true -- Show/hide hitbox for development
NPCFollowConfig.DAMAGE_HITBOX_COLOR = Color3.new(1, 0, 0) -- Red color
NPCFollowConfig.DAMAGE_HITBOX_TRANSPARENCY = 0.5 -- Hitbox transparency
NPCFollowConfig.DAMAGE_CHECK_INTERVAL = 0.1 -- How often to check for damage
```

## How to Use

### For Development (Testing)
1. Set `DAMAGE_HITBOX_VISIBLE = true` to see the red damage hitboxes
2. Adjust `DAMAGE_HITBOX_SIZE` to change the damage area
3. Modify `DAMAGE_PER_SECOND` to test different damage values
4. Use `DEBUG_MODE = true` to see damage debug messages

### For Production
1. Set `DAMAGE_HITBOX_VISIBLE = false` to hide hitboxes from players
2. Keep `ENABLE_DAMAGE_SYSTEM = true` to maintain damage functionality
3. Fine-tune damage values based on testing

### Setup Instructions

1. **Place the ModuleScript**: Put `NPCFollowConfig.lua` in `ReplicatedStorage > NPCFollowModules`
2. **Place the Server Script**: Put `NPCFollowServer.lua` in `ServerScriptService`
3. **Place the Client Script** (Optional): Put `NPCFollowClient.lua` in `StarterPlayer > StarterPlayerScripts`
4. **Create NPC Folder**: Make sure you have a folder named "NPCS" in Workspace with your NPC models
5. **NPC Requirements**: Each NPC must have a Humanoid and HumanoidRootPart

## Damage System Features

### Smart Damage Tracking
- Prevents multiple damage instances per frame
- Accumulates fractional damage over time
- Only applies integer damage to player health

### Visual Effects
- Red particle effects appear when damage is dealt
- Animated effects that fade out over time
- Configurable effect appearance

### Performance Optimized
- Damage checks run at configurable intervals (default: 0.1 seconds)
- Efficient distance calculations using hitbox radius
- Automatic cleanup of tracking data

### Player Safety
- Damage only applies to players with valid characters
- Automatic removal of dead/invalid players from tracking
- Health never goes below 0

## Customization Options

### Hitbox Appearance
```lua
NPCFollowConfig.DAMAGE_HITBOX_COLOR = Color3.new(1, 0, 0) -- Red
NPCFollowConfig.DAMAGE_HITBOX_MATERIAL = Enum.Material.ForceField
NPCFollowConfig.DAMAGE_HITBOX_TRANSPARENCY = 0.5
```

### Damage Behavior
```lua
NPCFollowConfig.DAMAGE_PER_SECOND = 10 -- 10 HP per second
NPCFollowConfig.DAMAGE_CHECK_INTERVAL = 0.1 -- Check every 0.1 seconds
```

### Hitbox Size and Position
```lua
NPCFollowConfig.DAMAGE_HITBOX_SIZE = Vector3.new(6, 6, 6) -- 6x6x6 studs
NPCFollowConfig.DAMAGE_HITBOX_OFFSET = Vector3.new(0, 0, 0) -- No offset
```

## Debug Features

Enable debug mode to see detailed information:
```lua
NPCFollowConfig.DEBUG_MODE = true
```

This will show:
- When players enter/leave damage range
- Damage amounts being dealt
- Player health updates
- NPC system status messages

## Toggle Between Development and Production

**Development Mode:**
```lua
NPCFollowConfig.DAMAGE_HITBOX_VISIBLE = true
NPCFollowConfig.DEBUG_MODE = true
```

**Production Mode:**
```lua
NPCFollowConfig.DAMAGE_HITBOX_VISIBLE = false
NPCFollowConfig.DEBUG_MODE = false
```

The damage system will continue to work in production mode, but the hitboxes will be invisible to players.