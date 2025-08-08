-- TestSystemSetup.lua
-- Run this script in Roblox Studio Command Bar to test the entire system
-- This will help diagnose why NPCs aren't spawning

print("=== NPC Follow System Diagnostic Test ===")

-- Step 1: Check if ReplicatedStorage setup exists
print("\n1. Checking ReplicatedStorage setup...")
local replicatedStorage = game:GetService("ReplicatedStorage")
local npcFollowModules = replicatedStorage:FindFirstChild("NPCFollowModules")

if not npcFollowModules then
    warn("❌ NPCFollowModules folder missing in ReplicatedStorage!")
    print("Creating NPCFollowModules folder...")
    npcFollowModules = Instance.new("Folder")
    npcFollowModules.Name = "NPCFollowModules"
    npcFollowModules.Parent = replicatedStorage
end

local config = npcFollowModules:FindFirstChild("NPCFollowConfig")
if not config then
    warn("❌ NPCFollowConfig missing in NPCFollowModules!")
    return
else
    print("✅ NPCFollowConfig found")
end

-- Step 2: Test loading the config
print("\n2. Testing config loading...")
local success, configModule = pcall(function()
    return require(config)
end)

if not success then
    warn("❌ Failed to load NPCFollowConfig:", configModule)
    return
else
    print("✅ NPCFollowConfig loaded successfully")
    print("   - Debug mode:", configModule.DEBUG_MODE)
    print("   - NPC folder name:", configModule.NPC_FOLDER_NAME)
    print("   - Damage system enabled:", configModule.ENABLE_DAMAGE_SYSTEM)
end

-- Step 3: Check ServerScriptService
print("\n3. Checking ServerScriptService...")
local serverScriptService = game:GetService("ServerScriptService")
local npcFollowServer = serverScriptService:FindFirstChild("NPCFollowServer")

if not npcFollowServer then
    warn("❌ NPCFollowServer script missing in ServerScriptService!")
    return
else
    print("✅ NPCFollowServer script found")
    print("   - Script enabled:", npcFollowServer.Enabled)
    print("   - Script class:", npcFollowServer.ClassName)
end

-- Step 4: Check workspace NPCS folder
print("\n4. Checking workspace NPCS folder...")
local workspace = game:GetService("Workspace")
local npcsFolder = workspace:FindFirstChild(configModule.NPC_FOLDER_NAME)

if not npcsFolder then
    warn("❌ NPCS folder missing in workspace!")
    print("Creating NPCS folder...")
    npcsFolder = Instance.new("Folder")
    npcsFolder.Name = configModule.NPC_FOLDER_NAME
    npcsFolder.Parent = workspace
    print("✅ NPCS folder created")
else
    print("✅ NPCS folder found")
    print("   - Children count:", #npcsFolder:GetChildren())
    
    for i, child in pairs(npcsFolder:GetChildren()) do
        print("   - Child " .. i .. ":", child.Name, "(" .. child.ClassName .. ")")
        if child:IsA("Model") then
            local humanoid = child:FindFirstChildOfClass("Humanoid")
            local rootPart = child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Torso")
            print("     - Has Humanoid:", humanoid ~= nil)
            print("     - Has RootPart:", rootPart ~= nil)
        end
    end
end

-- Step 5: Create test NPCs if none exist
if #npcsFolder:GetChildren() == 0 then
    print("\n5. Creating test NPCs...")
    
    local function createTestNPC(name, position)
        local npcModel = Instance.new("Model")
        npcModel.Name = name
        npcModel.Parent = npcsFolder
        
        -- Create HumanoidRootPart
        local rootPart = Instance.new("Part")
        rootPart.Name = "HumanoidRootPart"
        rootPart.Size = Vector3.new(2, 5, 1)
        rootPart.Position = position
        rootPart.Anchored = false
        rootPart.CanCollide = true
        rootPart.BrickColor = BrickColor.new("Bright blue")
        rootPart.Material = Enum.Material.Plastic
        rootPart.Parent = npcModel
        
        -- Create Humanoid
        local humanoid = Instance.new("Humanoid")
        humanoid.Parent = npcModel
        humanoid.Health = 100
        humanoid.MaxHealth = 100
        humanoid.WalkSpeed = 16
        
        -- Create simple torso for visibility
        local torso = Instance.new("Part")
        torso.Name = "Torso"
        torso.Size = Vector3.new(2, 2, 1)
        torso.Position = position
        torso.Anchored = false
        torso.CanCollide = false
        torso.BrickColor = BrickColor.new("Bright red")
        torso.Parent = npcModel
        
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = rootPart
        weld.Part1 = torso
        weld.Parent = rootPart
        
        -- Create head
        local head = Instance.new("Part")
        head.Name = "Head"
        head.Size = Vector3.new(2, 1, 1)
        head.Position = position + Vector3.new(0, 3, 0)
        head.Anchored = false
        head.CanCollide = false
        head.BrickColor = BrickColor.new("Light orange")
        head.Shape = Enum.PartType.Ball
        head.Parent = npcModel
        
        local headWeld = Instance.new("WeldConstraint")
        headWeld.Part0 = rootPart
        headWeld.Part1 = head
        headWeld.Parent = rootPart
        
        print("✅ Created NPC:", name, "at", position)
        return npcModel
    end
    
    createTestNPC("DiagnosticNPC1", Vector3.new(0, 5, 0))
    createTestNPC("DiagnosticNPC2", Vector3.new(15, 5, 0))
    createTestNPC("DiagnosticNPC3", Vector3.new(-15, 5, 0))
    
    print("✅ Test NPCs created!")
end

-- Step 6: Force reload the server script (if in Studio)
print("\n6. Checking server script execution...")
if game:GetService("RunService"):IsStudio() then
    print("Running in Studio - you may need to restart the script")
    print("Try disabling and re-enabling the NPCFollowServer script")
else
    print("Running in game - script should auto-execute")
end

-- Step 7: Check for common issues
print("\n7. Common issue checklist:")
print("✅ ReplicatedStorage/NPCFollowModules/NPCFollowConfig exists")
print("✅ ServerScriptService/NPCFollowServer exists")
print("✅ Workspace/NPCS folder exists")
print("✅ Test NPCs have been created")

print("\n=== Next Steps ===")
print("1. Check the Output window for '[NPCFollow]' messages")
print("2. If no messages appear, try:")
print("   - Disable and re-enable the NPCFollowServer script")
print("   - Stop and restart the game")
print("3. Walk near the blue NPCs (within 30 studs) to test following")
print("4. Look for red damage hitboxes around NPCs")

-- Step 8: Try to manually trigger the system
print("\n8. Attempting to manually trigger system...")
wait(1)

-- Check if the system is running
if _G.NPCFollowSystemLoaded then
    print("✅ NPC Follow System appears to be running!")
else
    print("❌ NPC Follow System not detected - check for script errors")
end

print("\n=== Diagnostic Complete ===")
print("Check the Output window for detailed messages!")