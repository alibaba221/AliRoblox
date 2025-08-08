-- CreateTestNPCs.lua
-- Run this script in the Command Bar or as a ServerScript to create test NPCs
-- This is a temporary script just for testing - you can delete it after creating NPCs

local function createTestNPC(name, position)
	-- Create the main model
	local npcModel = Instance.new("Model")
	npcModel.Name = name
	npcModel.Parent = workspace:FindFirstChild("NPCS") or workspace
	
	-- Create HumanoidRootPart
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 5, 1)
	rootPart.Position = position
	rootPart.Anchored = false
	rootPart.CanCollide = true
	rootPart.BrickColor = BrickColor.new("Bright blue")
	rootPart.Parent = npcModel
	
	-- Create Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = npcModel
	humanoid.PlatformStand = false
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	
	-- Create a simple body (torso)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Position = position
	torso.Anchored = false
	torso.CanCollide = false
	torso.BrickColor = BrickColor.new("Bright red")
	torso.Parent = npcModel
	
	-- Weld torso to root part
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = torso
	weld.Parent = rootPart
	
	-- Create a simple head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Position = position + Vector3.new(0, 3, 0)
	head.Anchored = false
	head.CanCollide = false
	head.BrickColor = BrickColor.new("Light orange")
	head.Shape = Enum.PartType.Ball
	head.Parent = npcModel
	
	-- Weld head to root part
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = rootPart
	headWeld.Part1 = head
	headWeld.Parent = rootPart
	
	-- Add a simple face
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	
	print("Created test NPC:", name, "at position", position)
	return npcModel
end

-- Make sure NPCS folder exists
local npcsFolder = workspace:FindFirstChild("NPCS")
if not npcsFolder then
	npcsFolder = Instance.new("Folder")
	npcsFolder.Name = "NPCS"
	npcsFolder.Parent = workspace
	print("Created NPCS folder in workspace")
end

-- Create some test NPCs
createTestNPC("TestNPC1", Vector3.new(0, 5, 0))
createTestNPC("TestNPC2", Vector3.new(10, 5, 0))
createTestNPC("TestNPC3", Vector3.new(-10, 5, 0))

print("=== Test NPCs Created! ===")
print("You should now see 3 test NPCs in the NPCS folder")
print("The NPC Follow system should detect and initialize them")
print("Walk near them to test the following behavior")
print("You can delete this script after testing")