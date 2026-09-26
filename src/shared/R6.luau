--[[
	SicilyShared.R6
	Classic blocky R6 rig: joint layout, attachments and a synchronous rig builder.

	The builder doesn't need any web requests, so it's used for:
	  * the StarterCharacter every player spawns as (their clothes/accessories are applied after),
	  * townsfolk NPCs,
	  * converting existing R15 NPCs in place.
]]

local R6 = {}

-- CollectionService tag on every R6 rig the client-side animator should drive.
R6.Tag = "SicilyR6"

R6.BodyParts = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

R6.Sizes = {
	HumanoidRootPart = Vector3.new(2, 2, 1),
	Torso = Vector3.new(2, 2, 1),
	Head = Vector3.new(2, 1, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
}

-- Rest-pose offsets of each part relative to the HumanoidRootPart.
R6.Offsets = {
	HumanoidRootPart = CFrame.new(),
	Torso = CFrame.new(),
	Head = CFrame.new(0, 1.5, 0),
	["Left Arm"] = CFrame.new(-1.5, 0, 0),
	["Right Arm"] = CFrame.new(1.5, 0, 0),
	["Left Leg"] = CFrame.new(-0.5, -2, 0),
	["Right Leg"] = CFrame.new(0.5, -2, 0),
}

-- The standard R6 Motor6D layout (identical to Roblox's default R6 character).
R6.Joints = {
	{
		Name = "RootJoint",
		Parent = "HumanoidRootPart",
		Part0 = "HumanoidRootPart",
		Part1 = "Torso",
		C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	},
	{
		Name = "Neck",
		Parent = "Torso",
		Part0 = "Torso",
		Part1 = "Head",
		C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	},
	{
		Name = "Right Shoulder",
		Parent = "Torso",
		Part0 = "Torso",
		Part1 = "Right Arm",
		C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	{
		Name = "Left Shoulder",
		Parent = "Torso",
		Part0 = "Torso",
		Part1 = "Left Arm",
		C0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		C1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
	{
		Name = "Right Hip",
		Parent = "Torso",
		Part0 = "Torso",
		Part1 = "Right Leg",
		C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	{
		Name = "Left Hip",
		Parent = "Torso",
		Part0 = "Torso",
		Part1 = "Left Leg",
		C0 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		C1 = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
}

-- Standard attachment names/positions so hats, hair and tools fit like on a default rig.
R6.Attachments = {
	HumanoidRootPart = {
		RootAttachment = CFrame.new(),
	},
	Head = {
		FaceCenterAttachment = CFrame.new(0, 0, 0),
		FaceFrontAttachment = CFrame.new(0, 0, -0.6),
		HairAttachment = CFrame.new(0, 0.6, 0),
		HatAttachment = CFrame.new(0, 0.6, 0),
	},
	Torso = {
		BodyBackAttachment = CFrame.new(0, 0, 0.5),
		BodyFrontAttachment = CFrame.new(0, 0, -0.5),
		LeftCollarAttachment = CFrame.new(-1, 1, 0),
		NeckAttachment = CFrame.new(0, 1, 0),
		RightCollarAttachment = CFrame.new(1, 1, 0),
		WaistBackAttachment = CFrame.new(0, -1, 0.5),
		WaistCenterAttachment = CFrame.new(0, -1, 0),
		WaistFrontAttachment = CFrame.new(0, -1, -0.5),
	},
	["Left Arm"] = {
		LeftShoulderAttachment = CFrame.new(0, 1, 0),
		LeftGripAttachment = CFrame.new(0, -1, 0),
	},
	["Right Arm"] = {
		RightShoulderAttachment = CFrame.new(0, 1, 0),
		RightGripAttachment = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0),
	},
	["Left Leg"] = {
		LeftFootAttachment = CFrame.new(0, -1, 0),
	},
	["Right Leg"] = {
		RightFootAttachment = CFrame.new(0, -1, 0),
	},
}

R6.DefaultFace = "rbxasset://textures/face.png"

local DEFAULT_COLORS = {
	Head = Color3.fromRGB(234, 184, 146),
	Torso = Color3.fromRGB(239, 233, 222),
	Arms = Color3.fromRGB(234, 184, 146),
	Legs = Color3.fromRGB(62, 58, 64),
}

local function newBodyPart(name: string, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.CanTouch = true
	part.CanQuery = true
	part.Anchored = false
	return part
end

--[[
	R6.Build({
		Name = "Townsfolk",
		CFrame = CFrame.new(0, 3, 0),     -- HumanoidRootPart placement
		BodyColors = { Head=, Torso=, Arms=, Legs= } | per-limb { LeftArm=, RightArm=, LeftLeg=, RightLeg= },
		Face = "rbxasset://textures/face.png",
		Anchored = false,
	}) -> Model
]]
function R6.Build(options: { [string]: any }?): Model
	local opts = options or {}
	local model = Instance.new("Model")
	model.Name = opts.Name or "R6Rig"

	local rootCFrame = opts.CFrame or CFrame.new(0, 3, 0)
	local parts = {}

	local root = newBodyPart("HumanoidRootPart", R6.Sizes.HumanoidRootPart)
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = rootCFrame
	root.Anchored = opts.Anchored == true
	parts.HumanoidRootPart = root

	for _, name in R6.BodyParts do
		local part = newBodyPart(name, R6.Sizes[name])
		part.CFrame = rootCFrame * R6.Offsets[name]
		part.CanCollide = (name == "Torso" or name == "Head")
		parts[name] = part
	end

	-- Classic round head + default face.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = parts.Head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = opts.Face or R6.DefaultFace
	face.Parent = parts.Head

	for partName, list in R6.Attachments do
		for attachmentName, offset in list do
			local attachment = Instance.new("Attachment")
			attachment.Name = attachmentName
			attachment.CFrame = offset
			attachment.Parent = parts[partName]
		end
	end

	for _, joint in R6.Joints do
		local motor = Instance.new("Motor6D")
		motor.Name = joint.Name
		motor.Part0 = parts[joint.Part0]
		motor.Part1 = parts[joint.Part1]
		motor.C0 = joint.C0
		motor.C1 = joint.C1
		motor.Parent = parts[joint.Parent]
	end

	local colors = opts.BodyColors or DEFAULT_COLORS
	local bodyColors = Instance.new("BodyColors")
	bodyColors.HeadColor3 = colors.Head or DEFAULT_COLORS.Head
	bodyColors.TorsoColor3 = colors.Torso or DEFAULT_COLORS.Torso
	bodyColors.LeftArmColor3 = colors.LeftArm or colors.Arms or DEFAULT_COLORS.Arms
	bodyColors.RightArmColor3 = colors.RightArm or colors.Arms or DEFAULT_COLORS.Arms
	bodyColors.LeftLegColor3 = colors.LeftLeg or colors.Legs or DEFAULT_COLORS.Legs
	bodyColors.RightLegColor3 = colors.RightLeg or colors.Legs or DEFAULT_COLORS.Legs
	bodyColors.Parent = model

	-- BodyColors applies at runtime; also paint the parts so edit-mode / previews look right.
	parts.Head.Color = bodyColors.HeadColor3
	parts.Torso.Color = bodyColors.TorsoColor3
	parts["Left Arm"].Color = bodyColors.LeftArmColor3
	parts["Right Arm"].Color = bodyColors.RightArmColor3
	parts["Left Leg"].Color = bodyColors.LeftLegColor3
	parts["Right Leg"].Color = bodyColors.RightLegColor3

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	root.Parent = model
	for _, name in R6.BodyParts do
		parts[name].Parent = model
	end
	humanoid.Parent = model
	model.PrimaryPart = root

	return model
end

-- Returns { RootJoint=, Neck=, ["Right Shoulder"]=, ... } for an R6 model (missing entries are nil).
function R6.GetMotors(model: Model): { [string]: Motor6D }
	local motors = {}
	local root = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	for _, joint in R6.Joints do
		local holder = if joint.Parent == "HumanoidRootPart" then root else torso
		local motor = holder and holder:FindFirstChild(joint.Name)
		if motor and motor:IsA("Motor6D") then
			motors[joint.Name] = motor
		end
	end
	return motors
end

function R6.IsR6(model: Instance): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil
		and humanoid.RigType == Enum.HumanoidRigType.R6
		and model:FindFirstChild("Torso") ~= nil
		and model:FindFirstChild("HumanoidRootPart") ~= nil
end

--[[
	Welds a decorative part (hat, apron, moustache...) to a body part.
	`offset` is relative to the body part's CFrame.
]]
function R6.AttachProp(model: Model, bodyPartName: string, offset: CFrame, props: { [string]: any }): BasePart?
	local bodyPart = model:FindFirstChild(bodyPartName)
	if not bodyPart or not bodyPart:IsA("BasePart") then
		return nil
	end
	local part = Instance.new(props.ClassName or "Part")
	part.Name = props.Name or "Prop"
	part.Size = props.Size or Vector3.new(1, 1, 1)
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Color = props.Color or Color3.new(1, 1, 1)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = props.CastShadow ~= false
	part.CFrame = bodyPart.CFrame * offset

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

return R6
