--[[
	SicilyShared.Ballistics
	Shared shot maths: spread cones, damage by body part and distance, and the checks the server
	runs on every hit a client reports. Pure functions (tested offline in test-weapons.luau).
]]

local Weapons = require(script.Parent.Weapons)

local Ballistics = {}

local HEAD = { Head = true }
local TORSO = { Torso = true, HumanoidRootPart = true, UpperTorso = true, LowerTorso = true }

-- "Head" | "Torso" | "Limb" for a body part name (anything else on a character counts as limb).
function Ballistics.Region(partName: string): string
	if HEAD[partName] then
		return "Head"
	elseif TORSO[partName] then
		return "Torso"
	end
	return "Limb"
end

function Ballistics.Damage(def, region: string, distance: number): number
	local multiplier = 1
	if region == "Head" then
		multiplier = def.HeadMultiplier
	elseif region == "Limb" then
		multiplier = def.LimbMultiplier
	end
	return def.Damage * multiplier * Weapons.Falloff(def, distance)
end

-- What a bullet struck, for impact effects: "Flesh", "Dirt", "Grass", "Sand", "Stone", "Wood",
-- "Metal", "Glass", "Fabric" or "Water" (by material name, so it also works on names sent over
-- the network).
local SURFACES = {
	Wood = "Wood",
	WoodPlanks = "Wood",
	Metal = "Metal",
	CorrodedMetal = "Metal",
	DiamondPlate = "Metal",
	Foil = "Metal",
	Glass = "Glass",
	Ice = "Glass",
	Glacier = "Glass",
	Neon = "Glass",
	ForceField = "Glass",
	Grass = "Grass",
	LeafyGrass = "Grass",
	Ground = "Dirt",
	Mud = "Dirt",
	Snow = "Dirt",
	Salt = "Dirt",
	Sand = "Sand",
	Fabric = "Fabric",
	Carpet = "Fabric",
	Leather = "Fabric",
	Cardboard = "Fabric",
	Rubber = "Fabric",
	Water = "Water",
}
function Ballistics.Surface(materialName: string?, isCharacter: boolean?): string
	if isCharacter then
		return "Flesh"
	end
	return SURFACES[materialName or ""] or "Stone"
end

-- A direction inside a cone of `degrees` (half-angle) around `direction`, uniform over the disc.
function Ballistics.Spread(direction: Vector3, degrees: number, rng: Random): Vector3
	if degrees <= 0 then
		return direction.Unit
	end
	local d = direction.Unit
	local helper = if math.abs(d.Y) < 0.95 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local right = d:Cross(helper).Unit
	local up = right:Cross(d)
	local radius = math.tan(math.rad(degrees)) * math.sqrt(rng:NextNumber())
	local angle = rng:NextNumber() * math.pi * 2
	return (d + right * math.cos(angle) * radius + up * math.sin(angle) * radius).Unit
end

function Ballistics.Angle(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- Largest angle (degrees) a pellet may deviate from the shot's centre direction.
function Ballistics.MaxDeviation(def): number
	local s = def.Spread
	local base = s.Hip + s.Moving + s.Mounted + s.BloomMax
	return base + (s.Pellet or 0) + 2
end

--[[
	Checks one reported hit against what the server knows. Returns ok, reason.
	shot = { Origin, Direction }         (direction of this pellet, unit)
	hit  = { Position }                  (where the client says the bullet struck)
	part = { CFrame, Size, Velocity }    (the struck part on the server)
	options = { Range, Tolerance, Latency }
]]
function Ballistics.ValidateHit(shot, hit, part, options): (boolean, string?)
	local toHit = hit.Position - shot.Origin
	local along = toHit:Dot(shot.Direction)
	if along < -1 then
		return false, "behind the muzzle"
	end
	if along > options.Range + 2 then
		return false, "out of range"
	end
	local offRay = (toHit - shot.Direction * along).Magnitude
	if offRay > 1.2 then
		return false, "not on the bullet's path"
	end
	-- the hit must be on (or near) the part, allowing for movement during the player's latency
	local movement = part.Velocity.Magnitude * math.clamp(options.Latency, 0, 0.6)
	local slack = options.Tolerance + movement
	local localPoint = part.CFrame:PointToObjectSpace(hit.Position)
	local half = part.Size / 2
	local outside = Vector3.new(
		math.max(math.abs(localPoint.X) - half.X, 0),
		math.max(math.abs(localPoint.Y) - half.Y, 0),
		math.max(math.abs(localPoint.Z) - half.Z, 0)
	)
	if outside.Magnitude > slack then
		return false, "too far from the target"
	end
	return true, nil
end

-- Shots must leave from near the shooter (their head), allowing for how fast they're moving.
function Ballistics.ValidOrigin(origin: Vector3, head: Vector3, speed: number, latency: number, maxDistance: number): boolean
	return (origin - head).Magnitude <= maxDistance + speed * math.clamp(latency, 0, 0.6)
end

return Ballistics
