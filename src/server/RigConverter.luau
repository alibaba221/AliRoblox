--[[
	Converts existing humanoid NPCs to blocky R6 *in place*.

	The NPC keeps its Model, Humanoid, HumanoidRootPart, scripts, attributes, tags, clothing and
	accessories, so scripts that reference the NPC / its Humanoid / its HumanoidRootPart keep
	working. Only the body parts and joints are swapped. (Scripts that look for R15-only parts such
	as "UpperTorso" need updating to "Torso".)

	Tag an NPC with Config.Characters.KeepRigTag ("KeepRig") to leave it untouched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local R6 = require(Shared:WaitForChild("R6"))

local RigConverter = {}

local BODY_PARTS = {
	Head = true,
	Torso = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

local SCALE_VALUES = {
	BodyDepthScale = true,
	BodyHeightScale = true,
	BodyWidthScale = true,
	HeadScale = true,
	BodyProportionScale = true,
	BodyTypeScale = true,
}

local function partColor(model: Model, ...: string): Color3?
	for _, name in { ... } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part.Color
		end
	end
	return nil
end

local function readBodyColors(model: Model)
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		return {
			Head = bodyColors.HeadColor3,
			Torso = bodyColors.TorsoColor3,
			LeftArm = bodyColors.LeftArmColor3,
			RightArm = bodyColors.RightArmColor3,
			LeftLeg = bodyColors.LeftLegColor3,
			RightLeg = bodyColors.RightLegColor3,
		}
	end
	return {
		Head = partColor(model, "Head"),
		Torso = partColor(model, "Torso", "UpperTorso"),
		LeftArm = partColor(model, "Left Arm", "LeftUpperArm"),
		RightArm = partColor(model, "Right Arm", "RightUpperArm"),
		LeftLeg = partColor(model, "Left Leg", "LeftUpperLeg"),
		RightLeg = partColor(model, "Right Leg", "RightUpperLeg"),
	}
end

function RigConverter.IsCandidate(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	if model:HasTag(Config.Characters.KeepRigTag) or model:HasTag(R6.Tag) then
		return false
	end
	if Players:GetPlayerFromCharacter(model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil and root:IsA("BasePart") and humanoid.Health > 0
end

local function silenceOldAnimation(model: Model, humanoid: Humanoid)
	for _, child in model:GetChildren() do
		if child.Name == "Animate" and (child:IsA("Script") or child:IsA("LocalScript")) then
			child.Enabled = false
		end
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

function RigConverter.Convert(model: Model): boolean
	if not RigConverter.IsCandidate(model) then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart

	silenceOldAnimation(model, humanoid)

	-- Already R6: just make it blocky.
	if humanoid.RigType == Enum.HumanoidRigType.R6 and model:FindFirstChild("Torso") then
		for _, child in model:GetChildren() do
			if child:IsA("CharacterMesh") then
				child:Destroy()
			end
		end
		model:AddTag(R6.Tag)
		return true
	end

	local colors = readBodyColors(model)
	local oldHead = model:FindFirstChild("Head")
	local oldFace = oldHead and oldHead:FindFirstChild("face")
	local faceTexture = if oldFace and oldFace:IsA("Decal") and oldFace.Texture ~= "" then oldFace.Texture else R6.DefaultFace

	-- Stand the new body on the same floor, facing the same way.
	local rootCFrame = root.CFrame
	local floorY = rootCFrame.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local _, yaw, _ = rootCFrame:ToEulerAnglesYXZ()
	local newRootCFrame = CFrame.new(rootCFrame.Position.X, floorY + 3, rootCFrame.Position.Z) * CFrame.Angles(0, yaw, 0)

	-- Rigid accessories are re-attached to the new body; layered clothing can't fit R6.
	local accessories = {}
	for _, child in model:GetChildren() do
		if child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:FindFirstChildOfClass("WrapLayer") then
				child:Destroy()
			else
				table.insert(accessories, child)
				child.Parent = nil
			end
		end
	end

	local requiresNeck = humanoid.RequiresNeck
	humanoid.RequiresNeck = false -- don't die while the neck is being swapped
	local wasAnchored = root.Anchored
	root.Anchored = true

	for _, child in model:GetChildren() do
		local isOldLimb = child:IsA("BasePart") and child ~= root and BODY_PARTS[child.Name] ~= nil
		if isOldLimb or child:IsA("BodyColors") or child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end
	for _, child in root:GetChildren() do
		if child:IsA("JointInstance") then
			child:Destroy()
		end
	end
	for _, child in humanoid:GetChildren() do
		if (child:IsA("NumberValue") and SCALE_VALUES[child.Name]) or child:IsA("HumanoidDescription") then
			child:Destroy()
		end
	end

	root.Size = R6.Sizes.HumanoidRootPart
	root.CFrame = newRootCFrame
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0

	local template = R6.Build({ CFrame = newRootCFrame, BodyColors = colors, Face = faceTexture })
	for _, name in R6.BodyParts do
		local part = template:FindFirstChild(name)
		if part then
			part.Parent = model
		end
	end
	local templateRoot = template:FindFirstChild("HumanoidRootPart") :: BasePart
	local rootJoint = templateRoot:FindFirstChild("RootJoint") :: Motor6D
	rootJoint.Part0 = root
	rootJoint.Parent = root
	if not root:FindFirstChild("RootAttachment") then
		local attachment = templateRoot:FindFirstChild("RootAttachment")
		if attachment then
			attachment.Parent = root
		end
	end
	local bodyColors = template:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.Parent = model
	end
	template:Destroy()

	root.Anchored = wasAnchored
	humanoid.RequiresNeck = requiresNeck

	for _, accessory in accessories do
		local handle = accessory:FindFirstChild("Handle")
		if handle then
			for _, joint in handle:GetChildren() do
				if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
					joint:Destroy()
				end
			end
		end
		local ok = pcall(function()
			humanoid:AddAccessory(accessory)
		end)
		if not ok then
			accessory:Destroy()
		end
	end

	model:AddTag(R6.Tag)
	return true
end

return RigConverter
