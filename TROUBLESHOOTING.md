# Troubleshooting NPCs Not Spawning

If your NPCs aren't spawning or working properly, follow these steps to diagnose the issue:

## 1. Check Debug Output

First, make sure debug mode is enabled in `NPCFollowConfig.lua`:
```lua
NPCFollowConfig.DEBUG_MODE = true
```

Then check the output window for debug messages. You should see:
```
[NPCFollow] Initializing NPC Follow System...
[NPCFollow] Looking for NPC folder: NPCS
[NPCFollow] Found NPC folder: NPCS
[NPCFollow] NPC folder contains X children
```

## 2. Verify Folder Structure

Make sure you have this exact structure:
```
Workspace
└── NPCS (Folder) <- Must be exactly "NPCS"
    ├── NPC1 (Model)
    ├── NPC2 (Model)
    └── ... (More NPC Models)
```

## 3. Check NPC Model Requirements

Each NPC model MUST have:
- ✅ A `Humanoid` object
- ✅ Either `HumanoidRootPart` OR `Torso` part

If missing, you'll see warnings like:
```
[NPCFollow] NPC missing Humanoid: NPCName
[NPCFollow] NPC missing HumanoidRootPart/Torso: NPCName
```

## 4. Create Test NPCs

If you don't have NPCs yet, use the `CreateTestNPCs.lua` script:

1. Copy the contents of `CreateTestNPCs.lua`
2. In Roblox Studio, go to View > Output (to see messages)
3. Open the Command Bar (View > Command Bar)
4. Paste the script and press Enter
5. You should see test NPCs appear in workspace

## 5. Common Issues and Solutions

### Issue: "Could not find NPC folder"
**Solution:** Create a folder named exactly "NPCS" in Workspace

### Issue: NPCs exist but no debug messages
**Solution:** 
- Make sure `NPCFollowServer.lua` is in `ServerScriptService`
- Make sure `NPCFollowConfig.lua` is in `ReplicatedStorage/NPCFollowModules`
- Check for script errors in the output window

### Issue: "NPC missing Humanoid" error
**Solution:** Add a Humanoid object to your NPC model:
```lua
local humanoid = Instance.new("Humanoid")
humanoid.Parent = yourNPCModel
```

### Issue: "NPC missing HumanoidRootPart" error
**Solution:** Add a HumanoidRootPart to your NPC model:
```lua
local rootPart = Instance.new("Part")
rootPart.Name = "HumanoidRootPart"
rootPart.Parent = yourNPCModel
```

### Issue: NPCs spawn but don't follow
**Possible causes:**
- Player is outside detection radius (default: 30 studs)
- Player is outside field of view (default: 120 degrees)
- Obstacle detection is blocking line of sight
- NPCs are in different states (check debug output)

## 6. Step-by-Step Debugging

1. **Enable debug mode** in config
2. **Check output window** for error messages
3. **Verify folder structure** exactly matches requirements
4. **Test with simple NPCs** using the CreateTestNPCs script
5. **Walk near NPCs** within 30 studs to trigger detection
6. **Check debug output** for detection and following messages

## 7. Expected Debug Output

When everything works, you should see:
```
[NPCFollow] Initializing NPC Follow System...
[NPCFollow] Looking for NPC folder: NPCS
[NPCFollow] Found NPC folder: NPCS
[NPCFollow] NPC folder contains 3 children
[NPCFollow] Child 1: TestNPC1 (Model)
[NPCFollow] Child 2: TestNPC2 (Model)
[NPCFollow] Child 3: TestNPC3 (Model)
[NPCFollow] Attempting to setup NPC: TestNPC1
[NPCFollow] Creating controller for NPC: TestNPC1
[NPCFollow] Damage hitbox created for: TestNPC1
[NPCFollow] NPC Controller created for: TestNPC1
[NPCFollow] ✓ Successfully setup NPC: TestNPC1
[NPCFollow] Successfully set up 3 NPCs
[NPCFollow] Server system loaded successfully!
```

## 8. If Still Not Working

1. **Share the exact error messages** from the output window
2. **Check script placement**:
   - `NPCFollowServer.lua` → `ServerScriptService`
   - `NPCFollowConfig.lua` → `ReplicatedStorage/NPCFollowModules`
   - `NPCFollowClient.lua` → `StarterPlayer/StarterPlayerScripts` (optional)
3. **Make sure scripts are enabled** (not disabled)
4. **Try creating test NPCs** with the provided script

The debug output will tell you exactly where the problem is!