--[[
	SicilyShared.HorseRig
	Blocky horse model, built from parts in code (nothing to upload).

	  HumanoidRootPart   invisible collider driven by a Humanoid (terrain, slopes, steps, jumping)
	   └ Body (Motor6D) ─ Barrel ─┬ Neck ─ Head
	                              ├ Tail1 ─ Tail2 ─ Tail3
	                              └ <Leg>Hip ─ <Leg>Upper ─ <Leg>Knee ─ <Leg>Lower ─ <Leg>Fetlock ─ <Leg>Hoof

	Every joint is a Motor6D animated by HorseGait on each client (legs by inverse kinematics, so
	hooves stay planted on the ground). The horse faces -Z like every Roblox model.
]]

local HorseTypes = require(script.Parent.HorseTypes)

local HorseRig = {}

HorseRig.Tag = "SicilyHorse"

local V = Vector3.new

-- All positions are relative to the HumanoidRootPart (== the Barrel at rest), in studs.
HorseRig.Layout = {
	RootHeight = 3.85, -- HumanoidRootPart centre above the ground when standing
	RootSize = V(2.2, 2.2, 5.6),
	BarrelSize = V(2.05, 1.95, 3.5),
	HoofHeight = 0.34,
	Legs = {
		FL = { Front = true, Side = -1, Hip = V(-0.62, -0.55, -1.95), Upper = 1.6, Lower = 1.45 },
		FR = { Front = true, Side = 1, Hip = V(0.62, -0.55, -1.95), Upper = 1.6, Lower = 1.45 },
		HL = { Front = false, Side = -1, Hip = V(-0.66, -0.45, 2.1), Upper = 1.75, Lower = 1.42 },
		HR = { Front = false, Side = 1, Hip = V(0.66, -0.45, 2.1), Upper = 1.75, Lower = 1.42 },
	},
	LegOrder = { "FL", "FR", "HL", "HR" },
	NeckBase = V(0, 0.95, -2.45),
	NeckTilt = math.rad(40), -- from vertical, towards the front
	NeckLength = 2.5,
	HeadPitch = math.rad(-40), -- the face points 40° below horizontal at rest
	TailRoot = V(0, 0.95, 2.95),
	TailTilt = math.rad(-22),
	TailLengths = { 1.05, 1.0, 0.95 },
	-- Seat surface (top of the saddle) and where a rider's HumanoidRootPart sits.
	SeatHeight = 1.32,
	SeatZ = -0.3,
	-- Ground points beside the horse for mounting/dismounting (rider HumanoidRootPart height).
	MountLeft = V(-2.45, 3 - 3.85, -0.3),
	MountRight = V(2.45, 3 - 3.85, -0.3),
}

local L = HorseRig.Layout
HorseRig.RiderOffset = CFrame.new(0, L.SeatHeight + 1.02, L.SeatZ)

HorseRig.JointNames = { "Body", "Neck", "Head", "Tail1", "Tail2", "Tail3" }
for _, leg in L.LegOrder do
	table.insert(HorseRig.JointNames, leg .. "Hip")
	table.insert(HorseRig.JointNames, leg .. "Knee")
	table.insert(HorseRig.JointNames, leg .. "Fetlock")
end

local SMOOTH = Enum.Material.SmoothPlastic
local FABRIC = Enum.Material.Fabric
local LEATHER = Enum.Material.Leather
local METAL = Enum.Material.Metal

local function newPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, className: string?): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Massless = true
	part.Parent = model
	return part
end

local function weld(part0: BasePart, part1: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part1
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	return m
end

-- Decoration welded to `base`, placed with a CFrame relative to `base`.
local function deco(model: Model, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, className: string?): BasePart
	local part = newPart(model, name, size, base.CFrame * offset, color, material or SMOOTH, className)
	part.CanQuery = false
	if size.X * size.Y * size.Z < 0.1 then
		part.CastShadow = false
	end
	weld(base, part)
	return part
end

--[[
	HorseRig.Build({ CFrame = root CFrame, Coat = "Bay", Name = "Horse" }) -> Model
	The root CFrame is the HumanoidRootPart; stand it at ground + Layout.RootHeight.
]]
function HorseRig.Build(options: { [string]: any }?): Model
	local opts = options or {}
	local coat = HorseTypes.GetCoat(opts.Coat)
	local rootCF: CFrame = opts.CFrame or CFrame.new(0, L.RootHeight, 0)

	local model = Instance.new("Model")
	model.Name = opts.Name or "Horse"

	local root = newPart(model, "HumanoidRootPart", L.RootSize, rootCF, Color3.new(1, 1, 1), SMOOTH)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	root.Massless = false
	root.RootPriority = 127
	root.CustomPhysicalProperties = PhysicalProperties.new(1.4, 0.4, 0.2, 1, 1)

	-- Body -----------------------------------------------------------------------------------
	local barrel = newPart(model, "Barrel", L.BarrelSize, rootCF, coat.Body, SMOOTH)
	motor("Body", root, barrel, CFrame.new(), CFrame.new())
	local function onBody(name, size, pos, color, material, className)
		return deco(model, barrel, name, size, CFrame.new(pos), color, material, className)
	end
	onBody("Chest", V(2.15, 2.25, 1.45), V(0, 0.12, -2.05), coat.Body)
	onBody("Withers", V(1.45, 0.42, 1.2), V(0, 1.4, -1.5), coat.Body)
	onBody("Rump", V(2.25, 2.2, 1.55), V(0, 0.1, 2.2), coat.Body)
	onBody("Back", V(1.7, 0.3, 3.4), V(0, 1.05, 0.35), coat.Body)
	onBody("Belly", V(1.7, 0.3, 3.0), V(0, -1.05, 0.05), coat.Body)
	onBody("Dock", V(1.5, 0.5, 0.5), V(0, 0.95, 3.0), coat.Body)
	if coat.Patches then
		local white = coat.Points
		onBody("PatchL", V(0.08, 1.3, 1.6), V(-1.05, -0.1, 0.9), white)
		onBody("PatchR", V(0.08, 1.1, 1.3), V(1.05, 0.15, -0.6), white)
		onBody("PatchRump", V(2.3, 0.9, 0.9), V(0, 0.75, 2.45), white)
		onBody("PatchChest", V(1.2, 1.2, 0.08), V(0.35, -0.35, -2.8), white)
	end

	-- Neck + head ------------------------------------------------------------------------------
	local neckFrame = CFrame.new(L.NeckBase) * CFrame.Angles(-L.NeckTilt, 0, 0)
	local neck = newPart(model, "Neck", V(1.12, L.NeckLength, 1.42), rootCF * neckFrame * CFrame.new(0, L.NeckLength / 2, 0), coat.Body, SMOOTH)
	motor("Neck", barrel, neck, neckFrame, CFrame.new(0, -L.NeckLength / 2, 0))
	-- throat (fills the gap under the neck) and mane along the crest (+Z in neck space)
	deco(model, neck, "Throat", V(1.0, 1.6, 0.9), CFrame.new(0, -0.55, -0.45), coat.Body)
	for i = 0, 4 do
		local y = -L.NeckLength / 2 + 0.3 + i * 0.55
		local mane = deco(model, neck, "Mane", V(0.34, 0.62, 0.42), CFrame.new(0, y, 0.84) * CFrame.Angles(math.rad(-10), 0, 0), coat.Mane, FABRIC)
		mane.CastShadow = true
	end

	local pollOffset = CFrame.new(0, L.NeckLength / 2, 0)
	local headTilt = L.HeadPitch + L.NeckTilt
	local headOffset = V(0, -0.12, -0.55) -- head block centre relative to the poll
	local headFrame = neck.CFrame * pollOffset * CFrame.Angles(headTilt, 0, 0)
	local head = newPart(model, "Head", V(0.98, 1.0, 1.35), headFrame * CFrame.new(headOffset), coat.Body, SMOOTH)
	motor("Head", neck, head, pollOffset * CFrame.Angles(headTilt, 0, 0), CFrame.new(-headOffset))
	local function onHead(name, size, pos, color, material, className, angles)
		return deco(model, head, name, size, CFrame.new(pos - headOffset) * (angles or CFrame.new()), color, material, className)
	end
	onHead("Muzzle", V(0.84, 0.8, 1.05), V(0, -0.2, -1.55), coat.Muzzle)
	onHead("Jaw", V(0.8, 0.45, 1.1), V(0, -0.52, -0.9), coat.Body)
	for _, side in { -1, 1 } do
		onHead("Ear", V(0.22, 0.58, 0.26), V(side * 0.3, 0.72, 0.02), coat.Body, SMOOTH, "WedgePart", CFrame.Angles(0, 0, -side * 0.14))
		onHead("Eye", V(0.1, 0.2, 0.2), V(side * 0.5, 0.12, -0.45), Color3.fromRGB(18, 14, 12))
		onHead("Nostril", V(0.14, 0.12, 0.06), V(side * 0.24, -0.22, -2.09), Color3.fromRGB(26, 20, 18))
	end
	onHead("Forelock", V(0.52, 0.34, 0.5), V(0, 0.55, -0.3), coat.Mane, FABRIC)
	if coat.Blaze then
		-- white stripe down the face: along the top of the head, then over the muzzle
		local white = Color3.fromRGB(242, 238, 230)
		onHead("Blaze", V(0.3, 0.05, 1.05), V(0, 0.4, -0.72), white)
		onHead("Blaze", V(0.26, 0.05, 0.95), V(0, 0.22, -1.6), white)
	end

	-- Tail -----------------------------------------------------------------------------------------
	local tailParent = barrel
	local tailC0 = CFrame.new(L.TailRoot) * CFrame.Angles(L.TailTilt, 0, 0)
	local tailFrame = barrel.CFrame * tailC0
	for i, length in L.TailLengths do
		local width = 0.42 + i * 0.07
		local seg = newPart(model, "Tail" .. i, V(width, length, width * 0.9), tailFrame * CFrame.new(0, -length / 2, 0), coat.Mane, FABRIC)
		motor("Tail" .. i, tailParent, seg, tailC0, CFrame.new(0, length / 2, 0))
		tailParent = seg
		tailC0 = CFrame.new(0, -length / 2, 0)
		tailFrame = seg.CFrame * tailC0
	end

	-- Legs -------------------------------------------------------------------------------------------
	local socks = {}
	for _, name in coat.Socks or {} do
		socks[name] = true
	end
	for _, name in L.LegOrder do
		local leg = L.Legs[name]
		local hipFrame = rootCF * CFrame.new(leg.Hip)
		local upperSize = if leg.Front then V(0.6, leg.Upper, 0.72) else V(0.68, leg.Upper, 0.92)
		local upper = newPart(model, name .. "Upper", upperSize, hipFrame * CFrame.new(0, -leg.Upper / 2, 0), coat.Body, SMOOTH)
		motor(name .. "Hip", barrel, upper, CFrame.new(leg.Hip), CFrame.new(0, leg.Upper / 2, 0))
		local lowerColor = if socks[name] then Color3.fromRGB(240, 236, 228) else coat.Points
		local lower = newPart(model, name .. "Lower", V(0.44, leg.Lower, 0.5), upper.CFrame * CFrame.new(0, -leg.Upper / 2 - leg.Lower / 2, 0), lowerColor, SMOOTH)
		motor(name .. "Knee", upper, lower, CFrame.new(0, -leg.Upper / 2, 0), CFrame.new(0, leg.Lower / 2, 0))
		local hoof = newPart(model, name .. "Hoof", V(0.56, L.HoofHeight, 0.66), lower.CFrame * CFrame.new(0, -leg.Lower / 2 - L.HoofHeight / 2, -0.04), coat.Hoof, SMOOTH)
		motor(name .. "Fetlock", lower, hoof, CFrame.new(0, -leg.Lower / 2, 0), CFrame.new(0, L.HoofHeight / 2, 0.04))
		-- knee / hock bump so the joint reads at a glance
		deco(model, upper, "Joint", V(0.5, 0.4, 0.6), CFrame.new(0, -leg.Upper / 2 + 0.05, if leg.Front then -0.04 else 0.1), lowerColor)
	end

	-- Attachments used by riding, prompts and effects.
	local function attach(parent: BasePart, name: string, cf: CFrame)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = cf
		a.Parent = parent
		return a
	end
	attach(root, "SeatAttachment", HorseRig.RiderOffset)
	attach(root, "MountLeft", CFrame.new(L.MountLeft))
	attach(root, "MountRight", CFrame.new(L.MountRight))
	attach(barrel, "PromptAttachment", CFrame.new(0, 0.9, -0.4))
	attach(head, "HeadCenter", CFrame.new(0, 0.3, -0.2))
	attach(head, "BitLeft", CFrame.new(V(-0.44, -0.38, -1.55) - headOffset))
	attach(head, "BitRight", CFrame.new(V(0.44, -0.38, -1.55) - headOffset))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = L.RootHeight - L.RootSize.Y / 2
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxSlopeAngle = 52
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid.AutoJumpEnabled = false
	humanoid.Parent = model

	model.PrimaryPart = root
	model:SetAttribute("Coat", coat.Id)
	return model
end

-- Saddle, blanket and bridle, added when a horse is tamed.
function HorseRig.AddTack(model: Model)
	if model:FindFirstChild("Saddle") then
		return
	end
	local barrel = model:FindFirstChild("Barrel") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not barrel or not head then
		return
	end
	local tack = HorseTypes.Tack
	local seatY = L.SeatHeight
	local z = L.SeatZ
	local function onBarrel(name, size, pos, color, material, angles, className)
		local p = deco(model, barrel, name, size, CFrame.new(pos) * (angles or CFrame.new()), color, material, className)
		p.CanQuery = false
		return p
	end
	onBarrel("Blanket", V(2.25, 0.12, 2.3), V(0, 1.1, z + 0.05), tack.Blanket, FABRIC)
	for _, side in { -1, 1 } do
		onBarrel("BlanketSide", V(0.1, 0.9, 2.3), V(side * 1.1, 0.7, z + 0.05), tack.Blanket, FABRIC)
		onBarrel("BlanketStripe", V(0.12, 0.14, 2.32), V(side * 1.11, 0.45, z + 0.05), tack.BlanketStripe, FABRIC)
		onBarrel("Fender", V(0.1, 1.25, 0.95), V(side * 1.14, 0.35, z + 0.1), tack.Leather, LEATHER)
		onBarrel("StirrupStrap", V(0.08, 0.9, 0.2), V(side * 1.2, -0.45, z + 0.12), tack.LeatherDark, LEATHER)
		onBarrel("Stirrup", V(0.14, 0.18, 0.5), V(side * 1.22, -0.95, z + 0.12), tack.Metal, METAL)
		onBarrel("Saddlebag", V(0.45, 0.7, 0.8), V(side * 1.12, 0.55, z + 1.55), tack.LeatherDark, LEATHER)
	end
	onBarrel("Saddle", V(1.55, 0.3, 1.9), V(0, seatY - 0.15, z), tack.Leather, LEATHER)
	onBarrel("Cantle", V(1.4, 0.4, 0.25), V(0, seatY + 0.05, z + 0.95), tack.Leather, LEATHER)
	onBarrel("Pommel", V(1.0, 0.35, 0.3), V(0, seatY + 0.02, z - 0.95), tack.Leather, LEATHER)
	onBarrel("Horn", V(0.22, 0.4, 0.22), V(0, seatY + 0.3, z - 1.02), tack.LeatherDark, LEATHER)
	onBarrel("Girth", V(2.12, 0.22, 0.3), V(0, -0.2, z - 0.6), tack.LeatherDark, LEATHER, CFrame.Angles(0, 0, 0))

	local headOffset = V(0, -0.12, -0.55)
	local function onHead(name, size, pos, color, material)
		local p = deco(model, head, name, size, CFrame.new(pos - headOffset), color, material)
		p.CanQuery = false
		return p
	end
	onHead("Noseband", V(0.9, 0.16, 0.86), V(0, -0.05, -1.4), tack.LeatherDark, LEATHER)
	onHead("Browband", V(1.02, 0.14, 0.2), V(0, 0.45, -0.2), tack.LeatherDark, LEATHER)
	for _, side in { -1, 1 } do
		onHead("Cheekpiece", V(0.06, 1.1, 0.14), V(side * 0.5, 0.0, -0.75), tack.LeatherDark, LEATHER)
		onHead("BitRing", V(0.06, 0.22, 0.22), V(side * 0.44, -0.38, -1.55), tack.Metal, METAL)
	end

	-- Reins: a beam from each bit ring to the saddle horn (the rider's hands hold them there).
	local horn = Instance.new("Attachment")
	horn.Name = "ReinsHand"
	horn.CFrame = CFrame.new(0, seatY + 0.35, z - 1.15)
	horn.Parent = barrel
	for _, side in { "BitLeft", "BitRight" } do
		local bit = head:FindFirstChild(side)
		if bit and bit:IsA("Attachment") then
			local beam = Instance.new("Beam")
			beam.Name = "Rein"
			beam.Attachment0 = bit
			beam.Attachment1 = horn
			beam.Width0 = 0.08
			beam.Width1 = 0.08
			beam.Segments = 8
			beam.CurveSize0 = -0.5
			beam.CurveSize1 = 0.3
			beam.FaceCamera = true
			beam.LightInfluence = 1
			beam.Color = ColorSequence.new(tack.LeatherDark)
			beam.Transparency = NumberSequence.new(0)
			beam.Parent = head
		end
	end
	model:SetAttribute("Tack", true)
end

-- Returns { [jointName] = Motor6D } for a horse model.
function HorseRig.GetJoints(model: Model): { [string]: Motor6D }
	local joints = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and table.find(HorseRig.JointNames, descendant.Name) then
			joints[descendant.Name] = descendant
		end
	end
	return joints
end

return HorseRig
