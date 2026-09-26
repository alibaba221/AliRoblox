--[[
	Terrain: land, the Mediterranean, beach, hills, the castle hill, the river valley, paths,
	rocky outcrops and sun-dried Sicilian colours.
]]

local Plan = require(script.Parent.Plan)

local Landscape = {}

local M = Enum.Material

local MATERIAL_COLORS = {
	[M.Grass] = Color3.fromRGB(150, 150, 88), -- sun-dried summer grass
	[M.LeafyGrass] = Color3.fromRGB(112, 128, 70),
	[M.Ground] = Color3.fromRGB(150, 118, 86),
	[M.Rock] = Color3.fromRGB(164, 150, 128),
	[M.Sand] = Color3.fromRGB(222, 202, 160),
	[M.Pavement] = Color3.fromRGB(170, 154, 128),
	[M.Mud] = Color3.fromRGB(110, 90, 70),
	[M.Limestone] = Color3.fromRGB(206, 190, 158),
	[M.Pebble] = Color3.fromRGB(170, 160, 144),
}

local function buildRecipe(terrain)
	for _, f in Plan.Terrain do
		local material = if f.Material then (M :: any)[f.Material] else nil
		if f.Kind == "Block" then
			terrain:Block(CFrame.new((f.Min + f.Max) / 2), f.Max - f.Min, material)
		elseif f.Kind == "Ball" then
			terrain:Ball(f.Center, f.Radius, material)
		elseif f.Kind == "Slope" then
			local high = math.max(f.Y0, f.Y1)
			local low = math.min(f.Y0, f.Y1)
			local width, depth = f.X1 - f.X0, f.Z1 - f.Z0
			local cx, cz = (f.X0 + f.X1) / 2, (f.Z0 + f.Z1) / 2
			terrain:Block(CFrame.new(cx, (f.Bottom + low) / 2, cz), Vector3.new(width, low - f.Bottom, depth), material)
			-- WedgePart convention: high side at local +Z. Flip when the high end is at Z0.
			local flip = if f.Y0 > f.Y1 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
			terrain:Wedge(CFrame.new(cx, (high + low) / 2, cz) * flip, Vector3.new(width, high - low, depth), material)
		elseif f.Kind == "Valley" then
			local z = f.Z0
			while z <= f.Z1 do
				terrain:Ball(Vector3.new(f.X, f.CenterY, z), f.Radius, M.Air)
				z += f.Step
			end
		end
	end
end

local function nearPath(x: number, z: number, distance: number): boolean
	local path = Plan.CastlePath
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local ab = b - a
		local t = math.clamp(((x - a.X) * ab.X + (z - a.Y) * ab.Y) / (ab.X * ab.X + ab.Y * ab.Y), 0, 1)
		local px, pz = a.X + ab.X * t, a.Y + ab.Y * t
		if (x - px) ^ 2 + (z - pz) ^ 2 < distance * distance then
			return true
		end
	end
	return false
end
Landscape.NearPath = nearPath

local function isBuildable(x: number, z: number): boolean
	if Plan.InTown(x, z, 6) then
		return false
	end
	if z > 190 then
		return false
	end
	if math.abs(x - Plan.Bridge.X) < 40 and z > -150 then
		return false -- river valley
	end
	if z > Plan.CountryRoad.Z0 - 8 and z < Plan.CountryRoad.Z1 + 8 and x < -100 then
		return false
	end
	if nearPath(x, z, 8) then
		return false
	end
	local c = Plan.Castle
	if math.abs(x - c.Center.X) < c.HalfX + 10 and math.abs(z - c.Center.Z) < c.HalfZ + 10 then
		return false
	end
	return true
end
Landscape.IsBuildable = isBuildable

local function paintPath(terrain)
	local path = Plan.CastlePath
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local length = (b - a).Magnitude
		local steps = math.max(1, math.ceil(length / 4))
		for s = 0, steps - 1 do
			local t0, t1 = s / steps, (s + 1) / steps
			local p0 = a:Lerp(b, t0)
			local p1 = a:Lerp(b, t1)
			local h0 = Plan.HeightAt(p0.X, p0.Y)
			local h1 = Plan.HeightAt(p1.X, p1.Y)
			local from = Vector3.new(p0.X, h0, p0.Y)
			local to = Vector3.new(p1.X, h1, p1.Y)
			local mid = (from + to) / 2
			local cf = CFrame.lookAt(mid, to) * CFrame.new(0, -1.6, 0)
			terrain:Block(cf, Vector3.new(7, 3, (to - from).Magnitude + 1.5), M.Ground)
		end
	end
end

local function paintCountryRoad(terrain)
	local road = Plan.CountryRoad
	local valley0 = Plan.Bridge.X - Plan.Bridge.HalfLength
	local valley1 = Plan.Bridge.X + Plan.Bridge.HalfLength
	local zc = (road.Z0 + road.Z1) / 2
	local width = road.Z1 - road.Z0
	-- east of the valley (town side) and west of it
	terrain:Block(CFrame.new((valley1 + road.X1) / 2, Plan.Land - 1.4, zc), Vector3.new(road.X1 - valley1, 3, width), M.Pavement)
	terrain:Block(CFrame.new((road.X0 + valley0) / 2, Plan.Land - 1.4, zc), Vector3.new(valley0 - road.X0, 3, width), M.Pavement)
end

local function scatter(terrain, rng)
	-- Rocky outcrops and dry-earth patches on the hills.
	local placed = 0
	local tries = 0
	while placed < 90 and tries < 1500 do
		tries += 1
		local x = rng:Range(-470, 420)
		local z = rng:Range(-520, 180)
		if isBuildable(x, z) then
			local h = Plan.HeightAt(x, z)
			if h > Plan.Land + 3 then
				local r = rng:Range(3.5, 9)
				local material = if rng:Chance(0.6) then M.Rock elseif rng:Chance(0.5) then M.Ground else M.LeafyGrass
				terrain:Ball(Vector3.new(x, h - r * 0.55, z), r, material)
				placed += 1
			end
		end
	end
	-- Flat-land texture: dry earth and greener patches around the town.
	for _ = 1, 70 do
		local x = rng:Range(-460, 380)
		local z = rng:Range(-420, 180)
		if isBuildable(x, z) then
			local h = Plan.HeightAt(x, z)
			local r = rng:Range(6, 14)
			local material = if rng:Chance(0.5) then M.Ground else M.LeafyGrass
			terrain:Ball(Vector3.new(x, h - r * 0.9, z), r, material)
		end
	end
	-- Sea rocks by the capes.
	for _ = 1, 26 do
		local side = rng:Sign()
		local x = if side > 0 then rng:Range(160, 330) else rng:Range(-400, -220)
		local z = rng:Range(210, 330)
		local r = rng:Range(3, 8)
		terrain:Ball(Vector3.new(x, rng:Range(-3, 0), z), r, M.Rock)
	end
end

function Landscape.Build(ctx)
	local terrain = ctx.Terrain
	local rng = ctx.Rng:Fork(11)

	for material, color in MATERIAL_COLORS do
		terrain:SetMaterialColor(material, color)
	end
	terrain:SetWater({
		WaterColor = Color3.fromRGB(34, 110, 124),
		WaterTransparency = 0.4,
		WaterReflectance = 0.85,
		WaterWaveSize = 0.12,
		WaterWaveSpeed = 7,
	})

	buildRecipe(terrain)
	ctx:Tick(40)
	paintPath(terrain)
	paintCountryRoad(terrain)
	scatter(terrain, rng)
	ctx:Tick(40)
end

return Landscape
