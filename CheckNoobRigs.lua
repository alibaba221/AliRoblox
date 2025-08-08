-- CheckNoobRigs.lua
-- Run this in Command Bar to check your existing Noob rigs

print("=== Checking Noob Rigs in NPCs Folder ===")

local workspace = game:GetService("Workspace")
local npcsFolder = workspace:FindFirstChild("NPCs")

if not npcsFolder then
    warn("❌ No 'NPCs' folder found in workspace")
    print("Available folders in workspace:")
    for _, child in pairs(workspace:GetChildren()) do
        if child:IsA("Folder") then
            print("  - " .. child.Name)
        end
    end
    return
end

print("✅ Found NPCs folder with", #npcsFolder:GetChildren(), "children")

-- Check each child in the NPCs folder
for i, child in pairs(npcsFolder:GetChildren()) do
    print("\n--- Checking Child " .. i .. ": " .. child.Name .. " (" .. child.ClassName .. ") ---")
    
    if child:IsA("Model") then
        print("✅ Is a Model - Good!")
        
        -- Check for Humanoid
        local humanoid = child:FindFirstChildOfClass("Humanoid")
        if humanoid then
            print("✅ Has Humanoid - Good!")
            print("   - Health:", humanoid.Health)
            print("   - MaxHealth:", humanoid.MaxHealth)
            print("   - WalkSpeed:", humanoid.WalkSpeed)
        else
            print("❌ Missing Humanoid - This is required!")
        end
        
        -- Check for RootPart
        local rootPart = child:FindFirstChild("HumanoidRootPart")
        local torso = child:FindFirstChild("Torso")
        
        if rootPart then
            print("✅ Has HumanoidRootPart - Good!")
            print("   - Position:", rootPart.Position)
            print("   - Size:", rootPart.Size)
        elseif torso then
            print("✅ Has Torso - Good!")
            print("   - Position:", torso.Position)
            print("   - Size:", torso.Size)
        else
            print("❌ Missing HumanoidRootPart/Torso - This is required!")
        end
        
        -- List all parts in the rig
        print("   Parts in this rig:")
        for _, part in pairs(child:GetChildren()) do
            if part:IsA("BasePart") then
                print("     - " .. part.Name .. " (" .. part.ClassName .. ")")
            elseif part:IsA("Humanoid") then
                print("     - " .. part.Name .. " (Humanoid)")
            else
                print("     - " .. part.Name .. " (" .. part.ClassName .. ")")
            end
        end
        
    else
        print("❌ Not a Model - NPCs must be Models!")
        print("   This is a: " .. child.ClassName)
    end
end

print("\n=== Summary ===")
print("The NPC Follow system will only work with:")
print("1. Models (not individual parts)")
print("2. Each model must have a Humanoid")
print("3. Each model must have HumanoidRootPart or Torso")

print("\n=== Next Steps ===")
print("1. Make sure your Noob rigs are proper R15/R6 character models")
print("2. If they're just parts, they need to be converted to proper rigs")
print("3. After fixing, the system should automatically detect them")