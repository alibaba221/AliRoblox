--[[
	SicilyShared.WeaponModels
	Blocky gun models built from parts (nothing to upload), sized for R6 hands.

	Every model has an invisible "Handle" part at the grip: -Z points down the barrel, +Y is the
	top of the gun. Attachments on the Handle:
	  Muzzle   end of the barrel (flash, smoke, where bullets start)
	  Support  where the left hand holds (fore-end on long guns)
	  Eject    ejection port (spent casings)
	Moving parts are Motor6Ds animated by the client: Hammer, Cylinder, Lever, Bolt, Barrels.
]]

local Weapons = require(script.Parent.Weapons)

local WeaponModels = {}

local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood
local LEATHER = Enum.Material.Leather

local function newPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = size.X * size.Y * size.Z > 0.02
	part.Parent = model
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

--[[
	Builder bound to one model: positions are in Handle space.
	b:Box(name, size, localCFrame, color, material, parentPart?)
	b:Barrel(name, length, diameter, localCFrame (axis along -Z), color, material, parentPart?)
	b:Mover(name, pivot (handle space)) -> a part that moves with a Motor6D pivoting at `pivot`
]]
local function builder(model: Model, handle: BasePart)
	local b = {}
	function b:Box(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, parent: BasePart?)
		local part = newPart(model, name, size, handle.CFrame * localCF, color, material)
		weld(parent or handle, part)
		return part
	end
	function b:Barrel(name: string, length: number, diameter: number, localCF: CFrame, color: Color3, material: Enum.Material, parent: BasePart?)
		local part = newPart(model, name, Vector3.new(length, diameter, diameter), handle.CFrame * localCF * CFrame.Angles(0, math.pi / 2, 0), color, material, Enum.PartType.Cylinder)
		weld(parent or handle, part)
		return part
	end
	function b:Mover(name: string, pivot: Vector3): BasePart
		-- an invisible hub the moving pieces weld to; the Motor6D rotates/slides it about `pivot`
		local hub = newPart(model, name, Vector3.new(0.05, 0.05, 0.05), handle.CFrame * CFrame.new(pivot), Color3.new(), METAL)
		hub.Transparency = 1
		hub.CastShadow = false
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = handle
		motor.Part1 = hub
		motor.C0 = CFrame.new(pivot)
		motor.C1 = CFrame.new()
		motor.Parent = handle
		return hub
	end
	function b:Attach(name: string, position: Vector3)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = position
		a.Parent = handle
		return a
	end
	return b
end

local V = Vector3.new
local function rx(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end

local BUILDERS = {}

function BUILDERS.Revolver(b, c)
	b:Box("Grip", V(0.26, 0.72, 0.34), CFrame.new(0, -0.3, 0.1) * rx(-18), c.Grip, WOOD)
	b:Box("GripCap", V(0.28, 0.08, 0.34), CFrame.new(0, -0.64, 0.21) * rx(-18), c.Metal, METAL)
	b:Box("Frame", V(0.24, 0.4, 0.66), CFrame.new(0, 0.14, -0.2), c.Metal, METAL)
	b:Box("Barrel", V(0.14, 0.15, 0.95), CFrame.new(0, 0.24, -1.0), c.Metal, METAL)
	b:Box("Ejector", V(0.07, 0.07, 0.55), CFrame.new(0, 0.12, -0.85), c.Metal, METAL)
	b:Box("GuardBottom", V(0.06, 0.05, 0.3), CFrame.new(0, -0.14, -0.14), c.Accent, METAL)
	b:Box("GuardFront", V(0.06, 0.2, 0.05), CFrame.new(0, -0.05, -0.29), c.Accent, METAL)
	b:Box("Trigger", V(0.04, 0.12, 0.04), CFrame.new(0, -0.06, -0.1), c.Metal, METAL)
	b:Box("Sight", V(0.04, 0.07, 0.07), CFrame.new(0, 0.345, -1.42), c.Metal, METAL)
	local cylinder = b:Mover("Cylinder", V(0, 0.16, -0.3))
	b:Barrel("Drum", 0.46, 0.44, CFrame.new(0, 0.16, -0.3), c.Metal, METAL, cylinder)
	for i = 0, 5 do
		local a = i * math.pi / 3
		b:Box("Flute", V(0.05, 0.05, 0.47), CFrame.new(math.cos(a) * 0.21, 0.16 + math.sin(a) * 0.21, -0.3), c.Accent, METAL, cylinder)
	end
	local hammer = b:Mover("Hammer", V(0, 0.28, 0.06))
	b:Box("HammerSpur", V(0.08, 0.2, 0.1), CFrame.new(0, 0.37, 0.1) * rx(-20), c.Metal, METAL, hammer)
	b:Attach("Muzzle", V(0, 0.24, -1.5))
	b:Attach("Support", V(-0.12, -0.3, 0.02))
	b:Attach("Eject", V(0.13, 0.16, -0.3))
end

function BUILDERS.Pistol(b, c)
	b:Box("Grip", V(0.26, 0.74, 0.3), CFrame.new(0, -0.32, 0.12) * rx(-12), c.Grip, WOOD)
	b:Box("Receiver", V(0.26, 0.38, 0.9), CFrame.new(0, 0.14, -0.32), c.Metal, METAL)
	b:Box("Magazine", V(0.24, 0.42, 0.34), CFrame.new(0, -0.12, -0.52), c.Metal, METAL)
	b:Box("Barrel", V(0.13, 0.14, 0.72), CFrame.new(0, 0.22, -1.12), c.Metal, METAL)
	b:Box("Guard", V(0.06, 0.05, 0.26), CFrame.new(0, -0.14, -0.2), c.Accent, METAL)
	b:Box("Trigger", V(0.04, 0.12, 0.04), CFrame.new(0, -0.06, -0.16), c.Accent, METAL)
	b:Box("Hammer", V(0.07, 0.15, 0.15), CFrame.new(0, 0.3, 0.17), c.Accent, METAL)
	b:Box("Sight", V(0.04, 0.06, 0.06), CFrame.new(0, 0.32, -1.44), c.Metal, METAL)
	local bolt = b:Mover("Bolt", V(0, 0.36, 0.05))
	b:Box("BoltBody", V(0.14, 0.14, 0.34), CFrame.new(0, 0.36, 0.05), c.Accent, METAL, bolt)
	b:Attach("Muzzle", V(0, 0.22, -1.52))
	b:Attach("Support", V(-0.12, -0.32, 0.04))
	b:Attach("Eject", V(0.14, 0.36, -0.1))
end

function BUILDERS.Repeater(b, c)
	b:Box("Stock", V(0.28, 0.55, 1.2), CFrame.new(0, -0.18, 0.95) * rx(10), c.Grip, WOOD)
	b:Box("ButtPlate", V(0.3, 0.6, 0.08), CFrame.new(0, -0.28, 1.56) * rx(10), c.Metal, METAL)
	b:Box("Wrist", V(0.24, 0.3, 0.5), CFrame.new(0, 0.02, 0.15), c.Grip, WOOD)
	b:Box("Receiver", V(0.28, 0.44, 0.75), CFrame.new(0, 0.12, -0.42), c.Accent, METAL)
	b:Box("Barrel", V(0.12, 0.12, 2.0), CFrame.new(0, 0.27, -1.8), c.Metal, METAL)
	b:Box("Tube", V(0.1, 0.1, 1.55), CFrame.new(0, 0.13, -1.55), c.Metal, METAL)
	b:Box("Forend", V(0.24, 0.22, 0.8), CFrame.new(0, 0.15, -1.2), c.Grip, WOOD)
	b:Box("Band", V(0.26, 0.26, 0.08), CFrame.new(0, 0.2, -2.3), c.Metal, METAL)
	b:Box("Sight", V(0.04, 0.07, 0.07), CFrame.new(0, 0.365, -2.72), c.Metal, METAL)
	b:Box("Hammer", V(0.07, 0.16, 0.1), CFrame.new(0, 0.36, -0.02) * rx(-25), c.Metal, METAL)
	local lever = b:Mover("Lever", V(0, -0.08, -0.3))
	b:Box("LeverBar", V(0.06, 0.08, 0.52), CFrame.new(0, -0.12, -0.05), c.Metal, METAL, lever)
	b:Box("LoopBack", V(0.06, 0.32, 0.08), CFrame.new(0, -0.26, 0.2), c.Metal, METAL, lever)
	b:Box("LoopBottom", V(0.06, 0.08, 0.3), CFrame.new(0, -0.4, 0.05), c.Metal, METAL, lever)
	b:Attach("Muzzle", V(0, 0.27, -2.82))
	b:Attach("Support", V(0, 0.06, -1.15))
	b:Attach("Eject", V(0, 0.38, -0.42))
end

function BUILDERS.Rifle(b, c)
	b:Box("Stock", V(0.28, 0.52, 1.35), CFrame.new(0, -0.12, 1.05) * rx(8), c.Grip, WOOD)
	b:Box("ButtPlate", V(0.3, 0.56, 0.08), CFrame.new(0, -0.22, 1.72) * rx(8), c.Metal, METAL)
	b:Box("Wrist", V(0.24, 0.3, 0.5), CFrame.new(0, 0.03, 0.12), c.Grip, WOOD)
	b:Box("Receiver", V(0.26, 0.32, 0.85), CFrame.new(0, 0.16, -0.42), c.Metal, METAL)
	b:Box("Fore", V(0.26, 0.26, 1.75), CFrame.new(0, 0.12, -1.7), c.Grip, WOOD)
	b:Box("Handguard", V(0.2, 0.1, 1.2), CFrame.new(0, 0.3, -1.5), c.Grip, WOOD)
	b:Box("Barrel", V(0.1, 0.1, 0.55), CFrame.new(0, 0.25, -2.8), c.Metal, METAL)
	b:Box("BandFront", V(0.28, 0.3, 0.08), CFrame.new(0, 0.18, -2.5), c.Metal, METAL)
	b:Box("BandMid", V(0.28, 0.3, 0.08), CFrame.new(0, 0.18, -1.6), c.Metal, METAL)
	b:Box("Sight", V(0.04, 0.07, 0.07), CFrame.new(0, 0.33, -3.0), c.Metal, METAL)
	b:Box("Sling", V(0.05, 0.04, 2.9), CFrame.new(-0.16, -0.26, -0.2) * rx(-5), Color3.fromRGB(96, 70, 44), LEATHER)
	local bolt = b:Mover("Bolt", V(0, 0.26, -0.1))
	b:Box("BoltBody", V(0.12, 0.12, 0.4), CFrame.new(0, 0.28, -0.15), c.Metal, METAL, bolt)
	b:Box("BoltHandle", V(0.36, 0.07, 0.07), CFrame.new(0.2, 0.26, 0.02), c.Metal, METAL, bolt)
	b:Box("BoltKnob", V(0.12, 0.12, 0.12), CFrame.new(0.38, 0.24, 0.02), c.Metal, METAL, bolt)
	b:Attach("Muzzle", V(0, 0.25, -3.1))
	b:Attach("Support", V(0, 0.0, -1.25))
	b:Attach("Eject", V(0.12, 0.34, -0.3))
end

function BUILDERS.Shotgun(b, c)
	b:Box("Stock", V(0.28, 0.5, 0.95), CFrame.new(0, -0.16, 0.6) * rx(12), c.Grip, WOOD)
	b:Box("Action", V(0.3, 0.34, 0.42), CFrame.new(0, 0.1, -0.12), c.Metal, METAL)
	b:Box("Guard", V(0.06, 0.05, 0.28), CFrame.new(0, -0.1, -0.02), c.Accent, METAL)
	for _, x in { -0.08, 0.08 } do
		b:Box("Hammer", V(0.06, 0.14, 0.1), CFrame.new(x, 0.3, 0.05) * rx(-25), c.Metal, METAL)
	end
	local barrels = b:Mover("Barrels", V(0, 0.0, -0.32))
	for _, x in { -0.1, 0.1 } do
		b:Barrel("Barrel", 1.3, 0.2, CFrame.new(x, 0.17, -1.0), c.Metal, METAL, barrels)
	end
	b:Box("Rib", V(0.08, 0.05, 1.3), CFrame.new(0, 0.28, -1.0), c.Metal, METAL, barrels)
	b:Box("Forend", V(0.28, 0.18, 0.55), CFrame.new(0, 0.0, -0.62), c.Grip, WOOD, barrels)
	b:Attach("Muzzle", V(0, 0.17, -1.66))
	b:Attach("Support", V(0, -0.08, -0.62))
	b:Attach("Eject", V(0, 0.2, -0.36))
end

--[[
	WeaponModels.Build(id, handleCFrame?) -> Model with PrimaryPart "Handle".
]]
function WeaponModels.Build(id: string, handleCFrame: CFrame?): Model?
	local def = Weapons.Get(id)
	if not def then
		return nil
	end
	local build = BUILDERS[def.Model]
	if not build then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	local handle = newPart(model, "Handle", Vector3.new(0.2, 0.2, 0.2), handleCFrame or CFrame.new(), Color3.new(), METAL)
	handle.Transparency = 1
	handle.CastShadow = false
	model.PrimaryPart = handle
	build(builder(model, handle), def.Colors)
	model:SetAttribute("WeaponId", id)
	return model
end

-- Joint name for the Motor6D that holds a weapon on the torso.
WeaponModels.JointName = "SicilyWeaponJoint"
WeaponModels.FolderName = "SicilyWeapons"

-- Moving part joints of a weapon model: { Hammer=, Cylinder=, Lever=, Bolt=, Barrels= }.
function WeaponModels.GetMovers(model: Model): { [string]: Motor6D }
	local movers = {}
	local handle = model:FindFirstChild("Handle")
	if handle then
		for _, child in handle:GetChildren() do
			if child:IsA("Motor6D") then
				movers[child.Name] = child
			end
		end
	end
	return movers
end

return WeaponModels
