--[[
	Street life: vegetation, lights, vehicles and furniture, plus Props.Build which dresses the
	streets (string lights over Via Roma, café tables, pots, scooters, laundry, bougainvillea).
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plan = require(script.Parent.Plan)

local Props = {}

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local TAU = math.pi * 2

-- Vegetation -------------------------------------------------------------------------------

function Props.Palm(kit, base: Vector3, rng, height: number?)
	local k = kit:Group("Palm")
	local h = height or rng:Range(12, 17)
	local lean = CFrame.Angles(rng:Range(-0.06, 0.06), 0, rng:Range(-0.06, 0.06))
	local segments = 3
	local top = CFrame.new(base) * lean
	for i = 1, segments do
		local seg = h / segments
		local d = 1.9 - i * 0.15
		local cf = top * CFrame.new(0, seg / 2, 0)
		k:Cyl(cf * CFrame.Angles(0, 0, math.pi / 2), seg + 0.1, d, Palette.Vary(Palette.PalmBark, rng, 0.03), M.Wood, Kit.SOLID)
		top = top * CFrame.new(0, seg, 0)
	end
	local crown = top.Position
	k:Ball(crown, 2.2, Palette.rgb(120, 104, 60), M.Grass, Kit.DECO)
	local fronds = rng:Int(13, 16)
	for i = 1, fronds do
		local yaw = TAU * i / fronds + rng:Range(-0.15, 0.15)
		local layer = i % 2
		local pitch = if layer == 0 then rng:Range(0.15, 0.45) else rng:Range(-0.55, -0.2)
		local length = rng:Range(6.5, 8.5)
		local cf = CFrame.new(crown) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, -length / 2)
		k:Box(cf, Vector3.new(rng:Range(0.8, 1.1), 0.12, length), rng:Pick(Palette.PalmFrond), M.Grass, Kit.DECO)
	end
	return k
end

function Props.Olive(kit, base: Vector3, rng, scale: number?)
	local k = kit:Group("Olive")
	local s = scale or rng:Range(0.8, 1.2)
	local trunkH = 4.2 * s
	local tilt = CFrame.Angles(rng:Range(-0.25, 0.25), rng:Range(0, TAU), rng:Range(-0.25, 0.25))
	local trunk = CFrame.new(base) * tilt
	k:Box(trunk * CFrame.new(0, trunkH / 2, 0), Vector3.new(1.3 * s, trunkH, 1.1 * s), Palette.rgb(96, 84, 70), M.Wood, Kit.SOLID)
	local top = (trunk * CFrame.new(0, trunkH, 0)).Position
	k:Box(
		CFrame.new(top) * CFrame.Angles(rng:Range(-0.6, 0.6), 0, rng:Range(0.4, 0.8)) * CFrame.new(0, 1.2 * s, 0),
		Vector3.new(0.8 * s, 2.6 * s, 0.8 * s),
		Palette.rgb(100, 88, 72),
		M.Wood,
		Kit.DECO
	)
	for _ = 1, rng:Int(5, 7) do
		local offset = Vector3.new(rng:Range(-2.6, 2.6), rng:Range(0.6, 3), rng:Range(-2.6, 2.6)) * s
		local size = Vector3.new(rng:Range(4.5, 6.5), rng:Range(2.6, 3.6), rng:Range(4.5, 6.5)) * s
		k:Blob(CFrame.new(top + offset) * CFrame.Angles(0, rng:Range(0, TAU), 0), size, rng:Pick(Palette.Olive), M.Grass, Kit.DECO)
	end
	return k
end

function Props.Cypress(kit, base: Vector3, rng, height: number?)
	local k = kit:Group("Cypress")
	local h = height or rng:Range(14, 20)
	local d = h * rng:Range(0.17, 0.21)
	k:Box(CFrame.new(base + Vector3.new(0, 1, 0)), Vector3.new(0.8, 2, 0.8), Palette.Bark, M.Wood, Kit.SOLID)
	k:Blob(CFrame.new(base + Vector3.new(0, 1 + h / 2, 0)), Vector3.new(d, h, d), Palette.Vary(Palette.Cypress, rng, 0.03), M.Grass, Kit.SOLID)
	return k
end

function Props.PricklyPear(kit, base: Vector3, rng)
	local k = kit:Group("PricklyPear")
	local green = Palette.rgb(98, 130, 72)
	local pads = { { CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, rng:Range(0, TAU), 0), 1 } }
	local count = 0
	while #pads > 0 and count < 11 do
		local item = table.remove(pads, 1)
		local cf, level = item[1], item[2]
		count += 1
		k:Blob(cf, Vector3.new(2, 2.6, 0.55), Palette.Vary(green, rng, 0.04), M.Grass, Kit.DECO)
		if rng:Chance(0.35) then
			k:Ball((cf * CFrame.new(rng:Range(-0.6, 0.6), 1.3, 0)).Position, 0.45, Palette.rgb(200, 60, 70), M.SmoothPlastic, Kit.DETAIL)
		end
		if level < 3 then
			for _ = 1, rng:Int(1, 2) do
				local child = cf
					* CFrame.new(rng:Range(-0.7, 0.7), 1.9, 0)
					* CFrame.Angles(0, rng:Range(-0.9, 0.9), rng:Range(-0.6, 0.6))
					* CFrame.new(0, 0.8, 0)
				table.insert(pads, { child, level + 1 })
			end
		end
	end
	return k
end

function Props.Agave(kit, base: Vector3, rng)
	local k = kit:Group("Agave")
	local color = Palette.rgb(118, 146, 132)
	for i = 1, 9 do
		local yaw = TAU * i / 9 + rng:Range(-0.2, 0.2)
		local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rng:Range(0.5, 0.9), 0, 0) * CFrame.new(0, 0, -1.4)
		k:Box(cf, Vector3.new(0.5, 0.15, 3), Palette.Vary(color, rng, 0.03), M.Grass, Kit.DETAIL)
	end
	return k
end

function Props.Pot(kit, base: Vector3, rng, kind: string?)
	local k = kit:Group("Pot")
	local size = rng:Range(1.4, 2.2)
	k:Cyl(CFrame.new(base + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), size, size * 0.9, Palette.Vary(Palette.Terracotta, rng, 0.04), M.Slate, Kit.SOLID)
	local plant = kind or rng:Pick({ "Geranium", "Shrub", "Lemon", "Agave" })
	local top = base + Vector3.new(0, size, 0)
	if plant == "Geranium" then
		k:Blob(CFrame.new(top + Vector3.new(0, 0.5, 0)), Vector3.new(size * 1.1, 1.1, size * 1.1), rng:Pick(Palette.Foliage), M.Grass, Kit.DECO)
		for _ = 1, 4 do
			k:Ball(top + Vector3.new(rng:Range(-0.5, 0.5), rng:Range(0.8, 1.2), rng:Range(-0.5, 0.5)) * size * 0.6, 0.5, rng:Pick(Palette.Geranium), M.SmoothPlastic, Kit.DETAIL)
		end
	elseif plant == "Lemon" then
		k:Box(CFrame.new(top + Vector3.new(0, 1.2, 0)), Vector3.new(0.3, 2.4, 0.3), Palette.Bark, M.Wood, Kit.DECO)
		k:Blob(CFrame.new(top + Vector3.new(0, 3.2, 0)), Vector3.new(3, 2.6, 3), rng:Pick(Palette.Foliage), M.Grass, Kit.DECO)
		for _ = 1, 5 do
			k:Ball(top + Vector3.new(rng:Range(-1.3, 1.3), rng:Range(2.4, 4), rng:Range(-1.3, 1.3)), 0.45, Palette.Lemon, M.SmoothPlastic, Kit.DETAIL)
		end
	elseif plant == "Agave" then
		Props.Agave(k, top + Vector3.new(0, 0.2, 0), rng)
	else
		k:Blob(CFrame.new(top + Vector3.new(0, 1, 0)), Vector3.new(size * 1.3, 2.2, size * 1.3), rng:Pick(Palette.Foliage), M.Grass, Kit.DECO)
	end
	return k
end

-- Cascading bougainvillea on a wall. frame: facade-style CFrame at the vine's base (X along
-- the wall, Z out of the wall), spreading over width x height.
function Props.Bougainvillea(kit, frame: CFrame, width: number, height: number, rng)
	local k = kit:Group("Bougainvillea")
	-- trunk
	k:Box(frame * CFrame.new(0, height * 0.35, 0.25), Vector3.new(0.35, height * 0.7, 0.35), Palette.Bark, M.Wood, Kit.DETAIL)
	local clusters = math.floor(width * height / 5)
	for _ = 1, math.clamp(clusters, 12, 38) do
		local x = rng:Range(-width / 2, width / 2)
		local y = height * (0.35 + 0.65 * rng:Next() ^ 0.6)
		local droop = (1 - math.abs(x) / (width / 2 + 0.01)) * 0.2
		local size = Vector3.new(rng:Range(1.2, 2.6), rng:Range(1, 2.2), rng:Range(0.8, 1.4))
		local color = if rng:Chance(0.72) then rng:Pick(Palette.Bougainvillea) else rng:Pick(Palette.Foliage)
		k:Blob(frame * CFrame.new(x, y - droop * height, size.Z / 2 + rng:Range(0, 0.4)), size, color, M.Grass, Kit.DETAIL)
	end
	return k
end

-- Lights ------------------------------------------------------------------------------------

function Props.StringLights(ctx, kit, p0: Vector3, p1: Vector3, sag: number, rng)
	local k, model = kit:Group("StringLights")
	ctx:Tag(model, "SicilyLamp")
	local span = (p1 - p0).Magnitude
	local count = math.max(3, math.floor(span / 1.9))
	local points = {}
	for i = 0, count do
		local t = i / count
		local p = p0:Lerp(p1, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		points[i] = p
	end
	for i = 1, count do
		k:Beam(points[i - 1], points[i], 0.06, Palette.Iron, M.Metal, Kit.DETAIL)
		if i < count then
			local bulb = k:Ball(points[i] - Vector3.new(0, 0.28, 0), 0.38, Palette.Bulb, M.Neon, Kit.GLOW)
			if i % 4 == 2 then
				k:PointLight(bulb, Palette.LampLight, 9, 0.55, false)
			end
		end
	end
	local _ = rng
	return k
end

function Props.LampPost(ctx, kit, base: Vector3, arms: number)
	local k, model = kit:Group("LampPost")
	ctx:Tag(model, "SicilyLamp")
	local iron = Palette.Iron
	local h = if arms > 1 then 11 else 9
	k:Box(CFrame.new(base + Vector3.new(0, 0.6, 0)), Vector3.new(1.4, 1.2, 1.4), iron, M.Metal)
	k:Post(base + Vector3.new(0, 1.2, 0), h - 1.2, 0.45, iron, M.Metal, Kit.SOLID)
	local top = base + Vector3.new(0, h, 0)
	local heads = {}
	if arms > 1 then
		for i = 1, arms do
			local yaw = TAU * i / arms
			local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
			local tip = top + dir * 1.7 + Vector3.new(0, 0.3, 0)
			k:Beam(top - Vector3.new(0, 0.6, 0), tip, 0.16, iron, M.Metal, Kit.DETAIL)
			table.insert(heads, tip)
		end
		table.insert(heads, top + Vector3.new(0, 1.1, 0))
	else
		table.insert(heads, top + Vector3.new(0, 0.7, 0))
	end
	for i, head in heads do
		k:Box(CFrame.new(head + Vector3.new(0, 0.85, 0)), Vector3.new(0.9, 0.18, 0.9), iron, M.Metal, Kit.DETAIL)
		local bulb = k:Box(CFrame.new(head + Vector3.new(0, 0.2, 0)), Vector3.new(0.6, 1.1, 0.6), Palette.Bulb, M.Neon, Kit.GLOW)
		k:Box(CFrame.new(head - Vector3.new(0, 0.42, 0)), Vector3.new(0.5, 0.15, 0.5), iron, M.Metal, Kit.DETAIL)
		if i == 1 or i == #heads then
			k:PointLight(bulb, Palette.LampLight, 20, 1.2, i == #heads)
		end
	end
	return k
end

-- Vehicles -----------------------------------------------------------------------------------

-- The iconic Fiat 500. cf: ground-level centre, facing -Z (front).
function Props.Fiat500(kit, cf: CFrame, color: Color3)
	local k = kit:Group("Fiat500")
	local chrome = Palette.rgb(210, 212, 214)
	local tyre = Palette.rgb(28, 28, 30)
	local glass = Palette.rgb(70, 88, 96)
	local function box(x, y, z, sx, sy, sz, c, mat, flags)
		return k:Box(cf * CFrame.new(x, y, z), Vector3.new(sx, sy, sz), c, mat or M.SmoothPlastic, flags)
	end
	box(0, 1.85, 0, 4.4, 1.9, 9.2, color, M.SmoothPlastic)
	-- rounded nose and tail
	k:Cyl(cf * CFrame.new(0, 1.9, -4.55), 4.4, 1.9, color, M.SmoothPlastic, Kit.DECO)
	k:Cyl(cf * CFrame.new(0, 1.9, 4.55), 4.4, 1.9, color, M.SmoothPlastic, Kit.DECO)
	k:Wedge(cf * CFrame.new(0, 3.1, -3.1) * CFrame.Angles(0, 0, 0), Vector3.new(4.2, 0.6, 2.4), color, M.SmoothPlastic, Kit.DECO)
	k:Wedge(cf * CFrame.new(0, 3.1, 3.2) * CFrame.Angles(0, math.pi, 0), Vector3.new(4.2, 0.6, 2.6), color, M.SmoothPlastic, Kit.DECO)
	-- cabin
	box(0, 3.95, 0.2, 4.0, 2.2, 4.6, color, M.SmoothPlastic)
	box(0, 4, 0.2, 4.08, 1.35, 3.8, glass, M.Glass, { Collide = false, Reflectance = 0.2 })
	box(0, 4, -2.02, 3.5, 1.35, 0.2, glass, M.Glass, { Collide = false, Reflectance = 0.2 })
	box(0, 4, 2.42, 3.5, 1.25, 0.2, glass, M.Glass, { Collide = false, Reflectance = 0.2 })
	box(0, 5.1, 0.3, 3.6, 0.1, 3.4, Palette.rgb(40, 38, 36), M.Fabric, Kit.DETAIL)
	-- wheels
	for _, x in { -2.05, 2.05 } do
		for _, z in { -3, 3.1 } do
			k:Cyl(cf * CFrame.new(x, 0.95, z), 0.9, 1.9, tyre, M.Rubber, Kit.SOLID)
			k:Cyl(cf * CFrame.new(x * 1.03, 0.95, z), 0.95, 0.9, chrome, M.Metal, Kit.DETAIL)
		end
	end
	-- lights and chrome
	for _, x in { -1.4, 1.4 } do
		k:Cyl(cf * CFrame.new(x, 2.4, -4.55) * CFrame.Angles(0, math.pi / 2, 0), 0.4, 0.9, chrome, M.Metal, Kit.DETAIL)
		k:Cyl(cf * CFrame.new(x, 2.4, -4.7) * CFrame.Angles(0, math.pi / 2, 0), 0.2, 0.7, Palette.rgb(250, 246, 230), M.Glass, Kit.DETAIL)
		box(x, 2.3, 5.45, 0.5, 0.7, 0.12, Palette.rgb(170, 30, 30), M.Glass, Kit.DETAIL)
	end
	box(0, 1.0, -4.9, 4.2, 0.25, 0.35, chrome, M.Metal, Kit.DETAIL)
	box(0, 1.0, 5.3, 4.2, 0.25, 0.35, chrome, M.Metal, Kit.DETAIL)
	return k
end

function Props.Vespa(kit, cf: CFrame, color: Color3)
	local k = kit:Group("Vespa")
	local tyre = Palette.rgb(28, 28, 30)
	k:Cyl(cf * CFrame.new(0, 0.65, -1.7), 0.5, 1.3, tyre, M.Rubber, Kit.SOLID)
	k:Cyl(cf * CFrame.new(0, 0.65, 1.6), 0.5, 1.3, tyre, M.Rubber, Kit.SOLID)
	k:Box(cf * CFrame.new(0, 0.9, 0), Vector3.new(1, 0.25, 2.2), Palette.rgb(60, 60, 60), M.Rubber, Kit.SOLID)
	k:Blob(cf * CFrame.new(0, 1.55, 1.25), Vector3.new(1.6, 1.5, 2.3), color, M.SmoothPlastic, Kit.SOLID)
	k:Blob(cf * CFrame.new(0, 2.35, 1.1), Vector3.new(0.9, 0.35, 1.6), Palette.rgb(40, 34, 30), M.Leather, Kit.DECO)
	k:Box(cf * CFrame.new(0, 2, -1.45) * CFrame.Angles(-0.25, 0, 0), Vector3.new(1.3, 2.6, 0.25), color, M.SmoothPlastic, Kit.SOLID)
	k:Box(cf * CFrame.new(0, 1.35, -1.7), Vector3.new(0.45, 0.9, 0.9), color, M.SmoothPlastic, Kit.DECO)
	k:Box(cf * CFrame.new(0, 3.35, -1.75), Vector3.new(1.8, 0.18, 0.2), Palette.rgb(200, 200, 204), M.Metal, Kit.DETAIL)
	k:Ball((cf * CFrame.new(0, 3.3, -1.95)).Position, 0.45, Palette.rgb(250, 246, 228), M.Glass, Kit.DETAIL)
	return k
end

-- Piaggio Ape three-wheeler loaded with lemons.
function Props.Ape(kit, cf: CFrame, color: Color3, rng)
	local k = kit:Group("ApeCar")
	local tyre = Palette.rgb(28, 28, 30)
	k:Box(cf * CFrame.new(0, 2.6, -2.4), Vector3.new(3.4, 3.6, 2.6), color, M.SmoothPlastic)
	k:Box(cf * CFrame.new(0, 3.4, -3.72), Vector3.new(2.9, 1.5, 0.12), Palette.rgb(70, 88, 96), M.Glass, { Collide = false, Reflectance = 0.2 })
	k:Box(cf * CFrame.new(0, 4.5, -2.4), Vector3.new(3.5, 0.2, 2.7), Palette.Darken(color, 0.1), M.SmoothPlastic, Kit.DECO)
	k:Box(cf * CFrame.new(0, 1.9, 1.4), Vector3.new(3.8, 0.4, 5), Palette.rgb(80, 84, 86), M.Metal)
	for _, x in { -1.8, 1.8 } do
		k:Box(cf * CFrame.new(x, 2.6, 1.4), Vector3.new(0.2, 1.2, 5), color, M.SmoothPlastic, Kit.DECO)
	end
	k:Box(cf * CFrame.new(0, 2.6, 3.8), Vector3.new(3.8, 1.2, 0.2), color, M.SmoothPlastic, Kit.DECO)
	k:Cyl(cf * CFrame.new(0, 0.8, -3.2), 0.6, 1.6, tyre, M.Rubber)
	k:Cyl(cf * CFrame.new(-1.7, 0.8, 2.4), 0.6, 1.6, tyre, M.Rubber)
	k:Cyl(cf * CFrame.new(1.7, 0.8, 2.4), 0.6, 1.6, tyre, M.Rubber)
	for i = 1, 14 do
		k:Ball((cf * CFrame.new(rng:Range(-1.4, 1.4), 2.45 + rng:Range(0, 0.6), rng:Range(-0.8, 3.5))).Position, 0.62, Palette.Lemon, M.SmoothPlastic, Kit.DETAIL)
		local _ = i
	end
	return k
end

-- Furniture ----------------------------------------------------------------------------------

-- Bistro table with chairs. Returns seat CFrames (hip position, facing the table).
function Props.CafeTable(kit, base: Vector3, rng, umbrella: boolean, clothColor: Color3?)
	local k = kit:Group("CafeTable")
	local iron = Palette.Iron
	k:Post(base, 2.4, 0.2, iron, M.Metal, Kit.DECO)
	k:Cyl(CFrame.new(base + Vector3.new(0, 2.45, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.15, 2.6, clothColor or Palette.rgb(240, 236, 226), M.Fabric, Kit.SOLID)
	k:Cyl(CFrame.new(base + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.16, 1.2, iron, M.Metal, Kit.DETAIL)
	local seats = {}
	local chairs = rng:Int(2, 4)
	local start = rng:Range(0, TAU)
	for i = 1, chairs do
		local yaw = start + TAU * i / chairs
		local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local seatPos = base + dir * 2.2
		local facing = CFrame.lookAt(seatPos, seatPos - dir)
		k:Box(facing * CFrame.new(0, 2.1, 0), Vector3.new(1.4, 0.2, 1.4), Palette.WoodDark, M.Wood, Kit.SOLID)
		k:Box(facing * CFrame.new(0, 3.1, 0.65), Vector3.new(1.4, 1.8, 0.14), Palette.WoodDark, M.Wood, Kit.DECO)
		k:Box(facing * CFrame.new(0, 1, 0), Vector3.new(0.2, 2, 0.2), iron, M.Metal, Kit.DETAIL)
		table.insert(seats, facing * CFrame.new(0, 2.2 + 1.5, 0))
	end
	if umbrella then
		local color = rng:Pick({ Palette.rgb(170, 36, 40), Palette.rgb(236, 228, 208), Palette.rgb(44, 84, 64) })
		k:Post(base + Vector3.new(0, 2.5, 0), 5, 0.14, Palette.WoodPale, M.Wood, Kit.DETAIL)
		k:Blob(CFrame.new(base + Vector3.new(0, 7.3, 0)), Vector3.new(7.2, 1.3, 7.2), color, M.Fabric, Kit.DECO)
	end
	return seats
end

function Props.Bench(kit, cf: CFrame)
	local k = kit:Group("Bench")
	local stone = Palette.StoneWarm
	k:Box(cf * CFrame.new(0, 1.7, 0), Vector3.new(6, 0.5, 1.8), stone, M.Limestone)
	k:Box(cf * CFrame.new(-2.4, 0.75, 0), Vector3.new(0.7, 1.5, 1.4), Palette.StoneShadow, M.Limestone)
	k:Box(cf * CFrame.new(2.4, 0.75, 0), Vector3.new(0.7, 1.5, 1.4), Palette.StoneShadow, M.Limestone)
	-- seat CFrames (hips above the seat, facing the bench's -Z)
	return { cf * CFrame.new(-1.3, 1.95 + 1.5, 0.1), cf * CFrame.new(1.3, 1.95 + 1.5, 0.1) }
end

function Props.Crate(kit, cf: CFrame, rng, fruit: Color3?)
	kit:Box(cf, Vector3.new(1.9, 0.8, 1.4), Palette.Vary(Palette.WoodPale, rng, 0.05), M.WoodPlanks, Kit.SOLID)
	if fruit then
		for i = 0, 3 do
			local x = (i % 2) * 0.9 - 0.45
			local z = math.floor(i / 2) * 0.6 - 0.3
			kit:Ball((cf * CFrame.new(x, 0.45, z)).Position, 0.62, Palette.Vary(fruit, rng, 0.05), M.SmoothPlastic, Kit.DETAIL)
		end
	end
end

function Props.Laundry(kit, p0: Vector3, p1: Vector3, rng)
	local k = kit:Group("Laundry")
	k:Beam(p0, p1, 0.05, Palette.rgb(220, 220, 214), M.Plastic, Kit.DETAIL)
	local span = (p1 - p0).Magnitude
	local count = math.max(2, math.floor(span / 2.6))
	local colors = {
		Palette.rgb(244, 244, 238),
		Palette.rgb(170, 200, 226),
		Palette.rgb(236, 180, 186),
		Palette.rgb(238, 220, 150),
		Palette.rgb(160, 196, 160),
		Palette.rgb(210, 86, 70),
	}
	local right = (p1 - p0).Unit
	local facing = CFrame.lookAt(Vector3.zero, right:Cross(UP))
	for i = 1, count do
		local t = (i - 0.5) / count + rng:Range(-0.05, 0.05)
		local p = p0:Lerp(p1, t)
		local w, h = rng:Range(1.2, 2), rng:Range(1.2, 2.6)
		k:Box(CFrame.new(p - Vector3.new(0, h / 2, 0)) * facing.Rotation, Vector3.new(w, h, 0.06), rng:Pick(colors), M.Fabric, Kit.DETAIL)
	end
	return k
end

-- Street dressing -------------------------------------------------------------------------------

local function streetByName(name: string)
	for _, s in Plan.Streets do
		if s.Name == name then
			return s
		end
	end
	return nil
end

local function awayFromDoors(info, position: Vector3, radius: number): boolean
	for _, door in info.Doors do
		if (door.Position - position).Magnitude < radius then
			return false
		end
	end
	return true
end

function Props.Courtyard(ctx, kit, courtyard)
	local rng = ctx.Rng:Fork(math.floor(courtyard.Center.X * 7 + courtyard.Center.Z))
	local k = kit:Group("Cortile")
	local c = courtyard.Center
	if rng:Chance(0.6) then
		Props.Olive(k, c + Vector3.new(rng:Range(-3, 3), 0, rng:Range(-3, 3)), rng, 0.8)
	else
		Props.Pot(k, c, rng, "Lemon")
	end
	local height = ctx.G + rng:Range(15, 22)
	if courtyard.X1 - courtyard.X0 > 6 then
		Props.Laundry(k, Vector3.new(courtyard.X0 + 0.5, height, c.Z + 2), Vector3.new(courtyard.X1 - 0.5, height - 0.6, c.Z + 3), rng)
	end
end

function Props.Build(ctx, parentKit)
	local kit = parentKit:Group("StreetLife")
	local rng = ctx.Rng:Fork(77)
	local info = ctx.Info
	local G = ctx.G

	-- String lights over Via Roma and the side streets.
	local roma = streetByName("Via Roma")
	if roma then
		ctx.Info.ShotsByName.ViaRoma = {
			CFrame.lookAt(Vector3.new(0, G + 7, roma.Z1 - 4), Vector3.new(0, G + 12, roma.Z0)),
			CFrame.lookAt(Vector3.new(0, G + 6, roma.Z1 - 40), Vector3.new(0, G + 12, roma.Z0)),
		}
		local z = roma.Z0 + 10
		while z < roma.Z1 - 6 do
			if not (z > 54 and z < 74) and not (z > 114 and z < 134) then
				local y = G + rng:Range(10.5, 12)
				Props.StringLights(ctx, kit, Vector3.new(roma.X0 + 0.6, y, z), Vector3.new(roma.X1 - 0.6, y + rng:Range(-0.6, 0.6), z + rng:Range(-4, 4)), 1.6, rng)
			end
			z += 14
		end
	end
	for _, name in { "Via Maqueda", "Via Etnea" } do
		local s = streetByName(name)
		if s then
			local z = s.Z0 + 30
			while z < s.Z1 - 20 do
				if rng:Chance(0.6) then
					local y = G + rng:Range(13, 17)
					Props.Laundry(kit, Vector3.new(s.X0 + 0.8, y, z), Vector3.new(s.X1 - 0.8, y - 0.4, z + rng:Range(-3, 3)), rng)
				elseif rng:Chance(0.5) then
					local y = G + rng:Range(10.5, 11.5)
					Props.StringLights(ctx, kit, Vector3.new(s.X0 + 0.6, y, z), Vector3.new(s.X1 - 0.6, y, z + rng:Range(-3, 3)), 1.3, rng)
				end
				z += 22
			end
		end
	end

	-- Café tables outside bars and restaurants on the busy streets.
	local tables = 0
	for _, shop in info.Shops do
		local busy = shop.Street == "Main" or shop.Street == "Piazza" or shop.Street == "Sea"
		local food = shop.Kind == "Bar" or shop.Kind == "Food" or shop.Kind == "Gelato" or shop.Kind == "Sweets"
		if busy and food and tables < 22 then
			local out = if shop.Street == "Main" then 5.2 else 6
			for i = -1, 1, 2 do
				local p = shop.Position + shop.Normal * out + shop.Right * (i * 2.8)
				if awayFromDoors(info, p, 3.2) then
					local seats = Props.CafeTable(kit, p, rng, shop.Street ~= "Main" and rng:Chance(0.6))
					for _, seat in seats do
						if rng:Chance(0.35) then
							table.insert(info.Seats, seat)
						end
					end
					ctx:Block(p, 3)
					tables += 1
				end
			end
		elseif shop.Kind == "Grocer" or shop.Kind == "Deli" then
			-- produce crates outside the grocer
			for i = -1, 1, 2 do
				local p = shop.Position + shop.Normal * 1.2 + shop.Right * (i * 2)
				Props.Crate(kit, CFrame.lookAt(p + Vector3.new(0, 0.4, 0), p + Vector3.new(0, 0.4, 0) - shop.Normal), rng, if i < 0 then Palette.Orange else Palette.Lemon)
			end
		end
	end

	-- Pots and plants beside doors; bougainvillea on some facades.
	local vines = 0
	for index, door in info.Doors do
		local right = door.Normal:Cross(UP)
		if rng:Chance(0.45) then
			local side = rng:Sign()
			local p = door.Position + door.Normal * 0.9 + right * side * rng:Range(2.6, 3.4)
			Props.Pot(kit, p, rng)
		end
		if door.Street ~= "Back" and vines < 16 and index % 5 == 2 then
			local side = rng:Sign()
			local base = door.Position + right * side * 4.2
			local frame = CFrame.fromMatrix(base, -right * side, UP)
			local frameOut = CFrame.fromMatrix(base, right, UP)
			if frameOut.ZVector:Dot(door.Normal) < 0 then
				frameOut = CFrame.fromMatrix(base, -right, UP)
			end
			local _ = frame
			Props.Bougainvillea(kit, frameOut, rng:Range(4, 7), rng:Range(10, 18), rng)
			vines += 1
		end
	end

	-- Parked vehicles.
	local vehicles = {
		{ Props.Fiat500, CFrame.new(-6, G, 100) * CFrame.Angles(0, math.pi, 0), Palette.rgb(236, 170, 40) },
		{ Props.Fiat500, CFrame.new(71.5, G, 30) * CFrame.Angles(0, 0, 0), Palette.rgb(150, 178, 190) },
		{ Props.Fiat500, CFrame.new(-60, G, 185) * CFrame.Angles(0, math.pi / 2, 0), Palette.rgb(232, 224, 200) },
		{ Props.Fiat500, CFrame.new(95, G, 64) * CFrame.Angles(0, -math.pi / 2, 0), Palette.rgb(170, 40, 36) },
	}
	for _, v in vehicles do
		v[1](kit, v[2], v[3])
		ctx:Block(v[2].Position, 6)
	end
	for _, spot in {
		{ CFrame.new(6.4, G, 36) * CFrame.Angles(0, 0.3, 0), Palette.rgb(170, 214, 196) },
		{ CFrame.new(-73, G, 150) * CFrame.Angles(0, -0.2, 0), Palette.rgb(236, 232, 220) },
		{ CFrame.new(31, G, 180) * CFrame.Angles(0, 1.2, 0), Palette.rgb(120, 160, 196) },
		{ CFrame.new(-30, G, 64) * CFrame.Angles(0, 1.6, 0), Palette.rgb(200, 60, 50) },
	} do
		Props.Vespa(kit, spot[1], spot[2])
		ctx:Block(spot[1].Position, 2.5)
	end
	Props.Ape(kit, CFrame.new(72, G, 140) * CFrame.Angles(0, math.pi, 0), Palette.rgb(90, 130, 170), rng)
	ctx:Block(Vector3.new(72, G, 140), 5)
end

return Props
