--[[
	Beyond the walls: the old stone bridge over the river valley, a roadside shrine with candles,
	a masseria (farmhouse), olive groves and dry-stone walls, cypresses and prickly pears along
	the road up to the Norman castle.
]]

local Kit = require(script.Parent.Kit)
local Landscape = require(script.Parent.Landscape)
local Palette = require(script.Parent.Palette)
local Plan = require(script.Parent.Plan)
local Props = require(script.Parent.Props)

local Countryside = {}

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local OLD_STONE = Palette.rgb(196, 180, 148)
local OLD_STONE_DARK = Palette.rgb(168, 152, 122)

local function ground(x: number, z: number): number
	return Plan.HeightAt(x, z)
end

function Countryside.Bridge(ctx, parentKit)
	local kit = parentKit:Group("PonteVecchio")
	local b = Plan.Bridge
	local G = ctx.G
	local zc = (b.Z0 + b.Z1) / 2
	local width = b.Z1 - b.Z0
	local deckTop = G
	-- barrel arch + spandrels (frame: X along the bridge, Z across it)
	local frame = CFrame.fromMatrix(Vector3.new(b.X, b.Springing, zc), Vector3.new(1, 0, 0), UP)
	kit:Arch(frame, b.ArchRadius, width, 2.2, OLD_STONE, M.Limestone, {
		HalfWidth = b.HalfLength,
		Top = deckTop - 1.2 - b.Springing,
		RingColor = Palette.rgb(214, 198, 166),
		ZCenter = 0,
		RingDepth = width + 0.6,
	})
	-- deck and parapets
	kit:Box(CFrame.new(b.X, deckTop - 0.6, zc), Vector3.new(b.HalfLength * 2, 1.2, width), Palette.rgb(150, 138, 118), M.Cobblestone)
	for _, side in { -1, 1 } do
		local z = zc + side * (width / 2 - 0.5)
		kit:Box(CFrame.new(b.X, deckTop + 1.2, z), Vector3.new(b.HalfLength * 2, 2.4, 1), OLD_STONE, M.Limestone)
		kit:Box(CFrame.new(b.X, deckTop + 2.55, z), Vector3.new(b.HalfLength * 2 + 0.4, 0.3, 1.4), OLD_STONE_DARK, M.Limestone, Kit.DECO)
		for _, ex in { -1, 1 } do
			kit:Box(CFrame.new(b.X + ex * (b.HalfLength - 0.8), deckTop + 1.8, z), Vector3.new(1.8, 3.6, 1.8), OLD_STONE_DARK, M.Limestone)
		end
	end
end

function Countryside.Shrine(ctx, parentKit)
	local kit, model = parentKit:Group("Edicola")
	ctx:Tag(model, "SicilyLamp")
	local p = Plan.Shrine
	local y = ground(p.X, p.Z)
	local cf = CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z + 10))
	local white = Palette.rgb(236, 230, 214)
	kit:Box(cf * CFrame.new(0, 0.4, 0), Vector3.new(3.4, 1.6, 2.6), OLD_STONE, M.Limestone)
	kit:Box(cf * CFrame.new(0, 2.6, 0), Vector3.new(2.4, 3, 1.8), white, M.Plaster)
	kit:Box(cf * CFrame.new(0, 5.6, 0.1), Vector3.new(3, 3.4, 2.2), white, M.Plaster)
	kit:Box(cf * CFrame.new(0, 5.6, -0.95), Vector3.new(2.2, 2.6, 0.4), Palette.rgb(36, 64, 136), M.SmoothPlastic, Kit.DECO)
	kit:Box(cf * CFrame.new(0, 5.4, -1.25), Vector3.new(0.7, 1.6, 0.3), Palette.rgb(246, 244, 240), M.Marble, Kit.DETAIL)
	kit:Ball((cf * CFrame.new(0, 6.5, -1.25)).Position, 0.6, Palette.rgb(246, 244, 240), M.Marble, Kit.DETAIL)
	kit:Box(cf * CFrame.new(0, 6.8, -1.3), Vector3.new(1.2, 0.12, 0.12), Palette.rgb(230, 190, 80), M.Metal, Kit.DETAIL)
	for _, side in { -1, 1 } do
		kit:Wedge(cf * CFrame.new(side * 0.85, 7.9, 0) * CFrame.Angles(0, side * -math.pi / 2, 0), Vector3.new(2.8, 1.2, 1.7), Palette.Terracotta, M.ClayRoofTiles)
	end
	-- candles and flowers on the ledge
	for i = -1, 1 do
		local candle = kit:Post((cf * CFrame.new(i * 0.6, 4.1, -0.6)).Position, 0.5, 0.18, Palette.rgb(250, 246, 236), M.SmoothPlastic, Kit.DETAIL)
		local flame = kit:Ball((cf * CFrame.new(i * 0.6, 4.7, -0.6)).Position, 0.16, Palette.rgb(255, 196, 90), M.Neon, Kit.GLOW)
		if i == 0 then
			kit:PointLight(flame, Palette.rgb(255, 170, 80), 10, 1.2, false)
		end
		local _ = candle
	end
	for i = -1, 1, 2 do
		kit:Ball((cf * CFrame.new(i * 1.1, 4.3, -0.6)).Position, 0.5, Palette.rgb(210, 40, 46), M.SmoothPlastic, Kit.DETAIL)
	end
	Props.PricklyPear(parentKit, Vector3.new(p.X - 5, ground(p.X - 5, p.Z - 1), p.Z - 1), ctx.Rng:Fork(501))
	Props.Agave(parentKit, Vector3.new(p.X + 4, ground(p.X + 4, p.Z - 2) + 0.2, p.Z - 2), ctx.Rng:Fork(502))
end

function Countryside.Farm(_ctx, parentKit, rng)
	local kit = parentKit:Group("Masseria")
	local f = Plan.Farm
	local y = ground(f.X, f.Z)
	local white = Palette.rgb(238, 230, 212)
	local roof = Palette.Roofs[2]
	local function house(cx, cz, sx, sz, h, ridgeAlongX)
		kit:Box(CFrame.new(cx, y + h / 2 - 1, cz), Vector3.new(sx, h + 2, sz), white, M.Plaster)
		local rise = 3
		for _, s in { -1, 1 } do
			if ridgeAlongX then
				kit:Wedge(CFrame.new(cx, y + h + rise / 2, cz + s * (sz / 4 + 0.4)) * CFrame.Angles(0, if s < 0 then 0 else math.pi, 0), Vector3.new(sx + 0.8, rise, sz / 2 + 0.8), roof, M.ClayRoofTiles)
			else
				kit:Wedge(CFrame.new(cx + s * (sx / 4 + 0.4), y + h + rise / 2, cz) * CFrame.Angles(0, if s < 0 then math.pi / 2 else -math.pi / 2, 0), Vector3.new(sz + 0.8, rise, sx / 2 + 0.8), roof, M.ClayRoofTiles)
			end
		end
		-- a few small windows and a door on the courtyard side (+Z)
		for i = -1, 1 do
			kit:Box(CFrame.new(cx + i * sx / 3.2, y + h * 0.62, cz + sz / 2 + 0.05), Vector3.new(1.8, 2.4, 0.2), Palette.rgb(58, 84, 62), M.WoodPlanks, Kit.DECO)
		end
		kit:Box(CFrame.new(cx, y + 3.3, cz + sz / 2 + 0.05), Vector3.new(3.4, 6.6, 0.2), Palette.Doors[1], M.WoodPlanks, Kit.DECO)
	end
	house(f.X, f.Z - 10, 26, 12, 11, true)
	house(f.X + 16, f.Z + 4, 10, 16, 8, false)
	-- courtyard wall with a gate
	local wall = OLD_STONE
	local x0, x1, z0, z1 = f.X - 18, f.X + 22, f.Z - 4, f.Z + 22
	kit:Box(CFrame.new((x0 + x1) / 2 - 12, y + 1.2, z1), Vector3.new(x1 - x0 - 24, 3.4, 1.2), wall, M.Limestone)
	kit:Box(CFrame.new((x0 + x1) / 2 + 14, y + 1.2, z1), Vector3.new(x1 - x0 - 28, 3.4, 1.2), wall, M.Limestone)
	kit:Box(CFrame.new(x0, y + 1.2, (z0 + z1) / 2), Vector3.new(1.2, 3.4, z1 - z0), wall, M.Limestone)
	for _, gx in { (x0 + x1) / 2 - 3.2, (x0 + x1) / 2 + 3.2 } do
		kit:Box(CFrame.new(gx, y + 2.6, z1), Vector3.new(1.6, 6, 1.6), wall, M.Limestone)
	end
	-- well, haystacks, a cart
	local well = Vector3.new(f.X + 2, y, f.Z + 10)
	kit:Post(well - Vector3.new(0, 0.5, 0), 2.4, 4, OLD_STONE, M.Limestone)
	for _, s in { -1, 1 } do
		kit:Box(CFrame.new(well + Vector3.new(s * 1.8, 3.2, 0)), Vector3.new(0.4, 4.4, 0.4), Palette.Wood, M.Wood, Kit.DECO)
	end
	kit:Box(CFrame.new(well + Vector3.new(0, 5.4, 0)), Vector3.new(4.4, 0.4, 0.4), Palette.Wood, M.Wood, Kit.DECO)
	for i = 1, 3 do
		kit:Blob(CFrame.new(f.X - 10 + i * 3.5, y + 1.4, f.Z + 14 + (i % 2) * 2), Vector3.new(3.6, 3.2, 3.6), Palette.rgb(214, 180, 96), M.Grass, Kit.SOLID)
	end
	kit:Box(CFrame.new(f.X + 12, y + 1.8, f.Z + 16) * CFrame.Angles(0, 0.4, 0), Vector3.new(3.2, 0.3, 6), Palette.Wood, M.WoodPlanks, Kit.DECO)
	for _, s in { -1, 1 } do
		kit:Cyl(CFrame.new(f.X + 12, y + 1.4, f.Z + 16) * CFrame.Angles(0, 0.4, 0) * CFrame.new(s * 1.9, 0, 0), 0.3, 2.8, Palette.WoodDark, M.Wood, Kit.DECO)
	end
	local _ = rng
end

-- Post-and-rail fence between two points (two rails), following the ground.
local function railFence(kit, a: Vector2, b: Vector2)
	local length = (b - a).Magnitude
	local posts = math.max(1, math.ceil(length / 4))
	for i = 0, posts do
		local p = a:Lerp(b, i / posts)
		kit:Post(Vector3.new(p.X, ground(p.X, p.Y) - 0.4, p.Y), 4, 0.45, Palette.WoodDark, M.Wood)
	end
	for _, h in { 1.3, 2.9 } do
		local y0 = ground(a.X, a.Y) + h
		local y1 = ground(b.X, b.Y) + h
		kit:Beam(Vector3.new(a.X, y0, a.Y), Vector3.new(b.X, y1, b.Y), 0.3, Palette.Wood, M.WoodPlanks, Kit.SOLID)
	end
end

--[[
	La stalla: a paddock by the west gate with an open-sided shelter, hay, a water trough and a
	hitching rail. Saddled horses wait here for anyone to ride (Info.StableSlots).
]]
function Countryside.Stable(ctx, parentKit)
	local kit, model = parentKit:Group("Stalla")
	model:SetAttribute("SicilyStable", true)
	local s = Plan.Stable
	local y = ground((s.X0 + s.X1) / 2, (s.Z0 + s.Z1) / 2)
	-- paddock fence with a wide opening towards the road (north side)
	railFence(kit, Vector2.new(s.X0, s.Z0), Vector2.new(s.X0 + 9, s.Z0))
	railFence(kit, Vector2.new(s.X1 - 9, s.Z0), Vector2.new(s.X1, s.Z0))
	railFence(kit, Vector2.new(s.X0, s.Z0), Vector2.new(s.X0, s.Z1))
	railFence(kit, Vector2.new(s.X1, s.Z0), Vector2.new(s.X1, s.Z1))
	-- shelter against a stone back wall
	local wallZ = s.Z1 - 0.6
	kit:Box(CFrame.new((s.X0 + s.X1) / 2, y + 4, wallZ), Vector3.new(s.X1 - s.X0, 8.4, 1.2), OLD_STONE, M.Limestone)
	local roofZ0, roofZ1 = s.Z1 - 12, s.Z1
	for _, x in { s.X0 + 1, (s.X0 + s.X1) / 2, s.X1 - 1 } do
		kit:Post(Vector3.new(x, y - 0.3, roofZ0 + 0.6), 8.2, 0.7, Palette.WoodDark, M.Wood)
	end
	kit:Box(CFrame.new((s.X0 + s.X1) / 2, y + 8, roofZ0 + 0.6), Vector3.new(s.X1 - s.X0, 0.5, 0.6), Palette.WoodDark, M.Wood)
	local roofLength = math.sqrt((roofZ1 - roofZ0) ^ 2 + 1.6 ^ 2)
	local roofCF = CFrame.lookAt(Vector3.new((s.X0 + s.X1) / 2, y + 8.9, (roofZ0 + roofZ1) / 2), Vector3.new((s.X0 + s.X1) / 2, y + 9.7, roofZ1))
	kit:Box(roofCF, Vector3.new(s.X1 - s.X0 + 1.4, 0.45, roofLength + 1), Palette.Roofs[1], M.ClayRoofTiles)
	-- hay rack, bales, water trough, feed buckets
	kit:Box(CFrame.new((s.X0 + s.X1) / 2, y + 4.3, wallZ - 1), Vector3.new(14, 0.3, 1.6), Palette.Wood, M.WoodPlanks, Kit.DECO)
	kit:Blob(CFrame.new((s.X0 + s.X1) / 2, y + 4.9, wallZ - 1), Vector3.new(13, 1.2, 1.5), Palette.rgb(214, 186, 104), M.Grass)
	for i, offset in { -11, -8.2, 10.6 } do
		kit:Box(CFrame.new((s.X0 + s.X1) / 2 + offset, y + 0.9 + (if i == 2 then 1.8 else 0), wallZ - 2.4), Vector3.new(2.6, 1.8, 1.8), Palette.rgb(212, 180, 98), M.Grass)
	end
	local troughCF = CFrame.new(s.X1 - 5, y + 0.9, s.Z0 + 8)
	kit:Box(troughCF, Vector3.new(1.8, 1.8, 5.6), OLD_STONE_DARK, M.Limestone)
	kit:Box(troughCF * CFrame.new(0, 0.82, 0), Vector3.new(1.3, 0.1, 5.1), Palette.Water, M.Glass, Kit.DETAIL)
	-- hitching rail by the opening
	local railZ = s.Z0 + 5
	for _, x in { s.X0 + 6, s.X0 + 15, s.X0 + 24 } do
		kit:Post(Vector3.new(x, y - 0.3, railZ), 3.6, 0.45, Palette.WoodDark, M.Wood)
	end
	kit:Beam(Vector3.new(s.X0 + 6, y + 3, railZ), Vector3.new(s.X0 + 24, y + 3, railZ), 0.35, Palette.Wood, M.Wood, Kit.DECO)
	-- sign on the back wall
	local sign = kit:Box(CFrame.new((s.X0 + s.X1) / 2, y + 6.6, wallZ - 0.7), Vector3.new(6, 1.4, 0.2), Palette.WoodDark, M.WoodPlanks, Kit.DECO)
	kit:Sign(sign, Enum.NormalId.Front, "STALLA", { Color = Palette.rgb(236, 220, 180) })
	-- where the saddled horses stand (facing the opening)
	for _, x in { s.X0 + 10, s.X1 - 10 } do
		table.insert(ctx.Info.StableSlots, CFrame.lookAt(Vector3.new(x, y, s.Z1 - 7), Vector3.new(x, y, s.Z0)))
	end
	ctx:Block(Vector3.new((s.X0 + s.X1) / 2, y, (s.Z0 + s.Z1) / 2), 14)
end

--[[
	Tiro a segno: a shooting range across the road from the stable. Bottles on the fence posts,
	tin cans on crates and two target boards in front of a hay backstop; a table with an ammo
	crate on the firing line. Breakable targets are spawned by the combat system at runtime.
]]
function Countryside.Range(ctx, parentKit)
	local kit, model = parentKit:Group("TiroASegno")
	model:SetAttribute("SicilyRange", true)
	local r = Plan.Range
	local y = ground((r.X0 + r.X1) / 2, (r.Z0 + r.Z1) / 2)
	local cx = (r.X0 + r.X1) / 2
	-- hay backstop and an earth bank behind the targets
	kit:Box(CFrame.new(cx, y + 1.6, r.Z0 + 0.5), Vector3.new(r.X1 - r.X0 + 4, 3.8, 3), Palette.rgb(132, 108, 80), M.Ground)
	for i = 0, 8 do
		kit:Box(CFrame.new(r.X0 + 1.8 + i * 3.4, y + 4.2, r.Z0 + 0.6), Vector3.new(3.2, 1.6, 2.2), Palette.rgb(214, 182, 100), M.Grass)
	end
	-- target fence with bottles on the posts
	local fenceZ = r.Z0 + 6
	for i = 0, 7 do
		local x = r.X0 + 2 + i * 3.7
		kit:Post(Vector3.new(x, y - 0.4, fenceZ), 3.7, 0.55, Palette.WoodDark, M.Wood)
		table.insert(ctx.Info.RangeBottles, CFrame.new(x, y + 3.3, fenceZ))
	end
	kit:Beam(Vector3.new(r.X0 + 2, y + 2.4, fenceZ), Vector3.new(r.X0 + 2 + 7 * 3.7, y + 2.4, fenceZ), 0.3, Palette.Wood, M.WoodPlanks, Kit.SOLID)
	-- crates with tin cans
	for i, x in { r.X0 + 5, cx, r.X1 - 5 } do
		local crate = CFrame.new(x, y + 1.1, fenceZ + 5 + (i % 2) * 2)
		kit:Box(crate, Vector3.new(2.4, 2.2, 2.2), Palette.WoodPale, M.WoodPlanks)
		for j = -1, 1, 2 do
			table.insert(ctx.Info.RangeCans, CFrame.new(x + j * 0.6, y + 2.6, crate.Position.Z))
		end
	end
	-- two target boards (painted rings) on easels
	for _, x in { r.X0 + 9.5, r.X1 - 9.5 } do
		local board = CFrame.new(x, y + 3.2, r.Z0 + 3.4)
		kit:Box(board * CFrame.new(0, -1.5, 0.4) * CFrame.Angles(-0.2, 0, 0), Vector3.new(0.3, 4, 0.3), Palette.WoodDark, M.Wood)
		kit:Box(board, Vector3.new(3.6, 3.6, 0.3), Palette.WoodPale, M.WoodPlanks)
		local rings = { { 3.1, Palette.rgb(240, 236, 226) }, { 2.3, Palette.rgb(200, 44, 40) }, { 1.5, Palette.rgb(240, 236, 226) }, { 0.7, Palette.rgb(200, 44, 40) } }
		for k, ring in rings do
			kit:Cyl(board * CFrame.new(0, 0, -0.16 - k * 0.02) * CFrame.Angles(0, math.pi / 2, 0), 0.04, ring[1], ring[2], M.SmoothPlastic, Kit.DETAIL)
		end
	end
	-- firing line: a table with an ammo crate, a bench, a rail to lean on
	local lineZ = r.Z1 - 5
	local tableCF = CFrame.new(r.X0 + 6, y + 1.7, lineZ + 1.5)
	kit:Box(tableCF, Vector3.new(6, 0.35, 2.4), Palette.Wood, M.WoodPlanks)
	for _, dx in { -2.6, 2.6 } do
		for _, dz in { -0.9, 0.9 } do
			kit:Box(tableCF * CFrame.new(dx, -0.95, dz), Vector3.new(0.35, 1.7, 0.35), Palette.WoodDark, M.Wood, Kit.DECO)
		end
	end
	local crate = kit:Box(tableCF * CFrame.new(1, 0.72, 0), Vector3.new(2.2, 1.1, 1.4), Palette.rgb(96, 110, 62), M.WoodPlanks)
	kit:Sign(crate, Enum.NormalId.Front, "MUNIZIONI", { Color = Palette.rgb(236, 226, 196) })
	table.insert(ctx.Info.AmmoCrates, crate.CFrame)
	kit:Beam(Vector3.new(r.X0 + 11, y + 2.8, lineZ), Vector3.new(r.X1 - 1, y + 2.8, lineZ), 0.3, Palette.Wood, M.Wood, Kit.DECO)
	for x = r.X0 + 11, r.X1 - 1, 5 do
		kit:Post(Vector3.new(x, y - 0.3, lineZ), 3.3, 0.4, Palette.WoodDark, M.Wood, Kit.DECO)
	end
	local sign = kit:Box(CFrame.new(r.X1 - 3, y + 3.6, r.Z1 - 1) * CFrame.Angles(0, math.pi, 0), Vector3.new(5, 1.3, 0.2), Palette.WoodDark, M.WoodPlanks, Kit.DECO)
	kit:Sign(sign, Enum.NormalId.Front, "TIRO A SEGNO", { Color = Palette.rgb(236, 220, 180) })
	kit:Post(Vector3.new(r.X1 - 3, y - 0.3, r.Z1 - 1), 3, 0.3, Palette.WoodDark, M.Wood, Kit.DECO)
end

-- Dry-stone wall following the ground between two points.
local function dryWall(kit, a: Vector2, b: Vector2, rng)
	local length = (b - a).Magnitude
	local segments = math.max(1, math.ceil(length / 10))
	for i = 0, segments - 1 do
		local p0 = a:Lerp(b, i / segments)
		local p1 = a:Lerp(b, (i + 1) / segments)
		local mid = (p0 + p1) / 2
		local y = ground(mid.X, mid.Y)
		local dir = p1 - p0
		local cf = CFrame.lookAt(Vector3.new(mid.X, y + 0.6, mid.Y), Vector3.new(p1.X, y + 0.6, p1.Y))
		kit:Box(cf, Vector3.new(1, 2.2 + rng:Range(-0.2, 0.3), dir.Magnitude + 0.3), Palette.Vary(OLD_STONE_DARK, rng, 0.04), M.Slate)
	end
end

function Countryside.Castle(ctx, parentKit)
	local kit = parentKit:Group("Castello")
	local c = Plan.Castle
	local center = c.Center
	local floorY = center.Y - 2
	local stone = Palette.rgb(200, 184, 150)
	local stoneDark = Palette.rgb(170, 156, 126)
	local baseY = floorY - 14
	local wallTop = floorY + 12
	local thick = 3
	local x0, x1 = center.X - c.HalfX, center.X + c.HalfX
	local z0, z1 = center.Z - c.HalfZ, center.Z + c.HalfZ
	-- courtyard floor (packed earth)
	kit:Box(CFrame.new(center.X, floorY - 0.5, center.Z), Vector3.new(x1 - x0, 1, z1 - z0), Palette.rgb(150, 128, 98), M.Ground)
	local gateX = center.X - 12
	local function merlons(a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		local count = math.floor(length / 3.4)
		for i = 0, count - 1 do
			local p = a:Lerp(b, (i + 0.5) / count)
			kit:Box(
				CFrame.lookAt(Vector3.new(p.X, wallTop + 0.9, p.Z), Vector3.new(b.X, wallTop + 0.9, b.Z)),
				Vector3.new(thick, 1.8, 1.8),
				stoneDark,
				M.Limestone,
				Kit.DECO
			)
		end
	end
	local function wall(a: Vector3, b: Vector3)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(Vector3.new(mid.X, (baseY + wallTop) / 2, mid.Z), Vector3.new(b.X, (baseY + wallTop) / 2, b.Z))
		kit:Box(cf, Vector3.new(thick, wallTop - baseY, (b - a).Magnitude), stone, M.Limestone)
		merlons(a, b)
	end
	-- Gatehouse: piers, an arched gateway and battlements. Frame X runs along the wall.
	local function gatehouse(a: Vector3, b: Vector3)
		local span = (b - a).Magnitude
		local mid = (a + b) / 2
		local frame = CFrame.fromMatrix(Vector3.new(mid.X, floorY, mid.Z), (b - a).Unit, UP)
		local radius, springing = 3, 5
		local depth = thick + 1.2
		for _, side in { -1, 1 } do
			local xa, xb = side * radius, side * span / 2
			kit:Box(
				frame * CFrame.new((xa + xb) / 2, (baseY - floorY + springing) / 2, 0),
				Vector3.new(math.abs(xb - xa), springing - (baseY - floorY), depth),
				stone,
				M.Limestone
			)
		end
		kit:Box(frame * CFrame.new(0, (baseY - floorY) / 2, 0), Vector3.new(radius * 2, floorY - baseY, depth), stone, M.Limestone)
		kit:Arch(frame * CFrame.new(0, springing, 0), radius, depth, 1.2, stone, M.Limestone, {
			HalfWidth = span / 2,
			Top = wallTop + 2 - floorY - springing,
			RingColor = stoneDark,
			ZCenter = 0,
		})
		local up = Vector3.new(0, 2, 0)
		merlons(a + up, b + up)
	end
	-- south wall has the gate at gateX
	local sw = Vector3.new(x0, 0, z1)
	local se = Vector3.new(x1, 0, z1)
	local gateT = (gateX - x0) / (x1 - x0)
	local gateA = sw:Lerp(se, math.max(0, gateT - 0.12))
	local gateB = sw:Lerp(se, math.min(1, gateT + 0.12))
	wall(sw, gateA)
	gatehouse(gateA, gateB)
	wall(gateB, se)
	wall(Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0))
	wall(Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	wall(Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1))
	-- corner towers
	for _, corner in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } } do
		local base = Vector3.new(corner[1], baseY, corner[2])
		kit:Post(base, wallTop + 6 - baseY, 10, stone, M.Limestone)
		for i = 0, 7 do
			local a = i * math.pi / 4
			kit:Box(
				CFrame.new(corner[1] + math.cos(a) * 4.4, wallTop + 6.9, corner[2] + math.sin(a) * 4.4) * CFrame.Angles(0, -a, 0),
				Vector3.new(1.4, 1.8, 2),
				stoneDark,
				M.Limestone,
				Kit.DECO
			)
		end
	end
	-- keep (donjon)
	local keep = Vector3.new(center.X + 12, baseY, center.Z - 8)
	local keepTop = floorY + 34
	kit:Box(CFrame.new(keep.X, (baseY + keepTop) / 2, keep.Z), Vector3.new(16, keepTop - baseY, 16), stone, M.Limestone)
	for i = 0, 3 do
		for j = 0, 3 do
			local along = -6 + j * 4
			local offsets = { Vector3.new(along, 0, -7.3), Vector3.new(along, 0, 7.3), Vector3.new(-7.3, 0, along), Vector3.new(7.3, 0, along) }
			local o = offsets[i + 1]
			kit:Box(CFrame.new(keep.X + o.X, keepTop + 0.9, keep.Z + o.Z), Vector3.new(1.6, 1.8, 1.6), stoneDark, M.Limestone, Kit.DECO)
		end
	end
	for _, y in { floorY + 14, floorY + 22, floorY + 29 } do
		kit:Box(CFrame.new(keep.X, y, keep.Z + 8.05), Vector3.new(0.6, 2.4, 0.2), Palette.Window, M.SmoothPlastic, Kit.DETAIL)
		kit:Box(CFrame.new(keep.X - 8.05, y, keep.Z), Vector3.new(0.2, 2.4, 0.6), Palette.Window, M.SmoothPlastic, Kit.DETAIL)
	end
	kit:Box(CFrame.new(keep.X, floorY + 3.2, keep.Z + 8.1), Vector3.new(3.2, 6.4, 0.3), Palette.WoodDark, M.WoodPlanks, Kit.DECO)
	-- Sicilian flag on the keep
	kit:Post(Vector3.new(keep.X, keepTop, keep.Z), 8, 0.25, Palette.Iron, M.Metal, Kit.DETAIL)
	kit:Wedge(CFrame.new(keep.X, keepTop + 6.6, keep.Z + 2.6) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.08, 2.4, 4.6), Palette.rgb(200, 36, 36), M.Fabric, Kit.DETAIL)
	kit:Wedge(CFrame.new(keep.X, keepTop + 6.6, keep.Z + 2.6) * CFrame.Angles(0, -math.pi / 2, math.pi), Vector3.new(0.08, 2.4, 4.6), Palette.rgb(244, 196, 40), M.Fabric, Kit.DETAIL)
	-- ruined well and rubble in the courtyard
	kit:Post(Vector3.new(center.X - 14, floorY - 0.5, center.Z + 4), 2, 4, stoneDark, M.Limestone)
	for i = 1, 5 do
		kit:Box(CFrame.new(center.X - 22 + i * 3, floorY + 0.3, center.Z - 16 + (i % 2) * 3) * CFrame.Angles(0, i, 0.2), Vector3.new(2, 1, 1.4), stoneDark, M.Limestone, Kit.SOLID)
	end
	table.insert(ctx.Info.Leans, CFrame.lookAt(Vector3.new(gateX + 3.2, floorY + 3, z1 + 3), Vector3.new(gateX + 3.2, floorY + 3, z1 + 10)))
end

function Countryside.Build(ctx, parentKit)
	local kit = parentKit:Group("Campagna")
	local rng = ctx.Rng:Fork(500)

	Countryside.Bridge(ctx, kit)
	Countryside.Shrine(ctx, kit)
	Countryside.Farm(ctx, kit, rng)
	Countryside.Castle(ctx, kit)
	Countryside.Stable(ctx, kit)
	Countryside.Range(ctx, kit)

	-- Olive groves in rows around the farm and west of the valley.
	local planted = 0
	for gx = -335, -222, 13 do
		for gz = -130, 170, 13 do
			local x = gx + rng:Range(-2.5, 2.5)
			local z = gz + rng:Range(-2.5, 2.5)
			local nearFarm = math.abs(x - Plan.Farm.X) < 32 and math.abs(z - Plan.Farm.Z) < 30
			local nearShrine = math.abs(x - Plan.Shrine.X) < 10 and math.abs(z - Plan.Shrine.Z) < 10
			if not nearFarm and not nearShrine and Landscape.IsBuildable(x, z) and rng:Chance(0.62) then
				local y = ground(x, z)
				if y > 5 and y < 40 then
					Props.Olive(kit, Vector3.new(x, y - 0.3, z), rng)
					planted += 1
				end
			end
		end
	end
	-- Scattered olives and carob trees east of the valley and on the lower hills.
	local tries = 0
	while tries < 220 and planted < 150 do
		tries += 1
		local x = rng:Range(-150, 250)
		local z = rng:Range(-330, 180)
		if Landscape.IsBuildable(x, z) and not Plan.InTown(x, z, 14) then
			local y = ground(x, z)
			if y > 5 and y < 55 then
				Props.Olive(kit, Vector3.new(x, y - 0.3, z), rng, rng:Range(0.8, 1.3))
				planted += 1
			end
		end
	end

	-- Dry-stone walls along the country road.
	local road = Plan.CountryRoad
	local valleyWest = Plan.Bridge.X - Plan.Bridge.HalfLength
	-- (between the bridge and the town gate the road opens onto the stable and the shooting range)
	for _, z in { road.Z0 - 1.5, road.Z1 + 1.5 } do
		dryWall(kit, Vector2.new(road.X0, z), Vector2.new(valleyWest - 4, z), rng)
	end

	-- Cypresses and prickly pears along the castle road.
	local path = Plan.CastlePath
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local dir = (b - a).Unit
		local normal = Vector2.new(-dir.Y, dir.X)
		local length = (b - a).Magnitude
		local d = 6
		while d < length do
			local p = a + dir * d
			for _, side in { -1, 1 } do
				local q = p + normal * side * 6.5
				local y = ground(q.X, q.Y)
				if rng:Chance(0.55) then
					Props.Cypress(kit, Vector3.new(q.X, y - 0.5, q.Y), rng)
				elseif rng:Chance(0.35) then
					Props.PricklyPear(kit, Vector3.new(q.X, y - 0.2, q.Y), rng)
				end
			end
			d += 15
		end
	end
	-- Prickly pears and agaves near the town edges.
	for _ = 1, 16 do
		local x = rng:Range(-150, 200)
		local z = rng:Range(-230, 170)
		if Landscape.IsBuildable(x, z) and not Plan.InTown(x, z, 4) then
			local y = ground(x, z)
			if rng:Chance(0.6) then
				Props.PricklyPear(kit, Vector3.new(x, y - 0.2, z), rng)
			else
				Props.Agave(kit, Vector3.new(x, y + 0.1, z), rng)
			end
		end
	end

	-- A vineyard and a lemon grove east of town.
	local vines = kit:Group("Vigneto")
	for row = 0, 12 do
		local x = 160 + row * 5.5
		for seg = 0, 4 do
			local z0 = -120 + seg * 26
			local zc = z0 + 12
			if Landscape.IsBuildable(x, zc) then
				local y = ground(x, zc)
				vines:Box(CFrame.new(x, y + 0.5, zc), Vector3.new(1, 1.6, 24), Palette.Vary(Palette.rgb(96, 122, 58), rng, 0.05), M.Grass, Kit.DECO)
			end
		end
	end
	local grove = kit:Group("Agrumeto")
	for gx = 0, 4 do
		for gz = 0, 3 do
			local x = 128 + gx * 11 + rng:Range(-1.5, 1.5)
			local z = 128 + gz * 12 + rng:Range(-1.5, 1.5)
			local y = ground(x, z)
			if y > 5 and not Plan.InTown(x, z, 4) then
				grove:Box(CFrame.new(x, y + 1.2, z), Vector3.new(0.7, 2.6, 0.7), Palette.Bark, M.Wood, Kit.DECO)
				grove:Blob(CFrame.new(x, y + 4, z), Vector3.new(5, 4.2, 5), Palette.Vary(Palette.rgb(58, 96, 44), rng, 0.04), M.Grass, Kit.DECO)
				for _ = 1, 3 do
					grove:Ball(Vector3.new(x + rng:Range(-2, 2), y + rng:Range(3, 5.4), z + rng:Range(-2, 2)), 0.55, Palette.Lemon, M.SmoothPlastic, Kit.DETAIL)
				end
			end
		end
	end

	-- Invisible walls at the edge of the playable area.
	local b = Plan.Bounds
	local walls = kit:Group("Boundary", "Folder")
	local invisible = { Collide = true, Transparency = 1, Shadow = false }
	local cx, cz = (b.X0 + b.X1) / 2, (b.Z0 + b.Z1) / 2
	walls:Box(CFrame.new(b.X0, 150, cz), Vector3.new(4, 400, b.Z1 - b.Z0), Color3.new(), M.SmoothPlastic, invisible)
	walls:Box(CFrame.new(b.X1, 150, cz), Vector3.new(4, 400, b.Z1 - b.Z0), Color3.new(), M.SmoothPlastic, invisible)
	walls:Box(CFrame.new(cx, 150, b.Z0), Vector3.new(b.X1 - b.X0, 400, 4), Color3.new(), M.SmoothPlastic, invisible)
	walls:Box(CFrame.new(cx, 150, b.Z1), Vector3.new(b.X1 - b.X0, 400, 4), Color3.new(), M.SmoothPlastic, invisible)

	-- Closing shot: from above the castle, over the town to the sea.
	local c = Plan.Castle.Center
	ctx.Info.ShotsByName.Castle = {
		CFrame.lookAt(c + Vector3.new(-30, 40, 40), Vector3.new(0, 20, 60)),
		CFrame.lookAt(c + Vector3.new(10, 30, 70), Vector3.new(0, 16, 90)),
	}
end

return Countryside
