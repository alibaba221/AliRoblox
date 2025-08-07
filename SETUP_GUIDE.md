# Enemy AI System Setup Guide

## Overview
This guide will walk you through setting up a complete enemy AI system in Roblox Studio with R6 rigs. The system includes spawning, detection, chasing, and damage mechanics.

## Prerequisites
- Roblox Studio installed
- Basic knowledge of Roblox Studio interface
- R6 rig models ready to use

## Step-by-Step Setup

### 1. Workspace Structure Setup

First, set up the proper folder structure in your workspace:

```
Workspace
├── NPCs (Folder)
│   ├── Enemy1 (Model - Your R6 Rig)
│   ├── Enemy2 (Model - Your R6 Rig)
│   └── ... (More enemy models)
├── EnemyAI_System (Script)
├── EnemyAI_Config (Script)
└── EnemyAI_Client (LocalScript)
```

### 2. Creating the NPCs Folder

1. In Roblox Studio, open the Explorer window
2. Right-click on "Workspace"
3. Select "Insert Object" → "Folder"
4. Name the folder "NPCs"

### 3. Adding Your R6 Rigs

1. In the NPCs folder, insert your R6 rig models
2. Make sure each model has:
   - A Humanoid
   - A HumanoidRootPart
   - All necessary body parts (Head, Torso, Arms, Legs)
3. Set the PrimaryPart of each model to the HumanoidRootPart

### 4. Script Placement

#### Server Scripts (Place in ServerScriptService)
1. Create a new Script in ServerScriptService
2. Name it "EnemyAI_System"
3. Copy the contents of `EnemyAI_System.lua` into this script

#### Configuration Script (Place in ServerScriptService)
1. Create another Script in ServerScriptService
2. Name it "EnemyAI_Config"
3. Copy the contents of `EnemyAI_Config.lua` into this script

#### Client Script (Place in StarterPlayerScripts)
1. Create a new LocalScript in StarterPlayerScripts
2. Name it "EnemyAI_Client"
3. Copy the contents of `EnemyAI_Client.lua` into this script

### 5. Configuration

Open the `EnemyAI_Config` script and modify these key values:

```lua
-- Detection and Movement
DETECTION_RANGE = 50, -- How far enemies can detect players
CHASE_SPEED = 16, -- How fast enemies move when chasing
DAMAGE_PER_SECOND = 10, -- Damage dealt per second
HITBOX_RANGE = 3, -- Range of damage hitbox

-- Spawning
SPAWN_INTERVAL = 10, -- Time between spawns
MAX_ENEMIES = 5, -- Maximum enemies at once
```

### 6. Testing the System

1. Press F5 to test the game
2. You should see enemies spawning from the NPCs folder
3. Walk near enemies to test detection and chasing
4. Get close to enemies to test damage system

## Complete Explorer Hierarchy

```
Game
├── ServerScriptService
│   ├── EnemyAI_System (Script)
│   └── EnemyAI_Config (Script)
├── StarterPlayer
│   └── StarterPlayerScripts
│       └── EnemyAI_Client (LocalScript)
├── Workspace
│   ├── NPCs (Folder)
│   │   ├── Enemy1 (Model)
│   │   │   ├── Humanoid
│   │   │   ├── HumanoidRootPart (PrimaryPart)
│   │   │   ├── Head
│   │   │   ├── Torso
│   │   │   ├── Left Arm
│   │   │   ├── Right Arm
│   │   │   ├── Left Leg
│   │   │   └── Right Leg
│   │   └── Enemy2 (Model)
│   │       └── ... (Same structure as Enemy1)
│   └── ... (Other workspace objects)
├── Players
├── Lighting
├── SoundService
├── StarterGui
└── ... (Other game services)
```

## Features Implemented

### ✅ Spawning System
- Automatically spawns enemies from NPCs folder
- Configurable spawn interval and maximum enemies
- Random positioning around spawn points

### ✅ Detection & Chasing
- Detects players within configurable range
- Smooth chasing behavior with configurable speed
- Stops chasing when players move out of range

### ✅ Damage System
- Deals 10 damage per second when in range
- Visual red hitbox indicator
- Damage numbers appear on screen
- Configurable damage interval

### ✅ Visual Indicators
- Red spherical hitbox around enemies
- Damage indicators on screen
- Debug UI showing enemy count

### ✅ Optimization
- Efficient update loops
- Proper cleanup when enemies die
- Memory management for UI elements

## Troubleshooting

### Common Issues

1. **Enemies not spawning**
   - Check if NPCs folder exists in workspace
   - Ensure models have Humanoid and HumanoidRootPart
   - Check output for error messages

2. **Enemies not detecting players**
   - Verify DETECTION_RANGE in config
   - Check if players have characters spawned
   - Ensure scripts are running

3. **Damage not working**
   - Check HITBOX_RANGE in config
   - Verify damage interval settings
   - Check if player has Humanoid

4. **Performance issues**
   - Reduce MAX_ENEMIES
   - Increase SPAWN_INTERVAL
   - Check for script errors in output

## Customization

### Adding New Enemy Types
1. Add new R6 rig models to NPCs folder
2. Each model will automatically be used as a spawn point
3. All enemies use the same AI behavior (can be extended)

### Modifying AI Behavior
1. Edit the `EnemyAI_System.lua` script
2. Modify the `update()` function for custom behavior
3. Add new states or behaviors as needed

### Visual Customization
1. Modify hitbox appearance in `createHitbox()` function
2. Change damage indicator style in client script
3. Adjust colors and transparency in config

## Performance Tips

1. Keep MAX_ENEMIES reasonable (5-10 for most games)
2. Use appropriate detection ranges
3. Clean up dead enemies properly
4. Monitor script performance in output

## Support

If you encounter issues:
1. Check the output window for error messages
2. Verify all scripts are in correct locations
3. Ensure R6 rigs have proper structure
4. Test with default settings first

This system provides a solid foundation for enemy AI that you can build upon and customize for your specific needs!