--[[
	The marina: seawall with fishermen's arches, the Lungomare with its belvedere and double
	staircase, the quay, the pier and lighthouse, colourful gozzo boats and the beach.
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plan = require(script.Parent.Plan)
local Props = require(script.Parent.Props)

local Harbour = {}

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local STONE = Palette.rgb(206, 190, 156)
local STONE_DARK = Palette.rgb(176, 160, 128)
local QUAY = Palette.rgb(190, 180, 158)

local HULLS = {
	{ Palette.rgb(240, 240, 234), Palette.rgb(40, 90, 170), Palette.rgb(200, 40, 40) },
	{ Palette.rgb(60, 120, 180), Palette.rgb(244, 244, 238), Palette.rgb(236, 190, 40) },
	{ Palette.rgb(236, 232, 220), Palette.rgb(40, 130, 90), Palette.rgb(200, 60, 40) },
	{ Palette.rgb(200, 60, 44), Palette.rgb(244, 240, 230), Palette.rgb(40, 80, 150) },
	{ Palette.rgb(244, 244, 238), Palette.rgb(236, 170, 40), Palette.rgb(40, 100, 160) },
}

-- Sicilian "gozzo": pointed at both ends, bright bands, a tall stem post. cf = keel centre, -Z bow.
function Harbour.Boat(kit, cf: CFrame, rng, length: number?)
	local k = kit:Group("Gozzo")
	local L = length or rng:Range(12, 16)
	local W = L * 0.3
	local H = 1.9
	local tip = W * 1.05
	local colors = rng:Pick(HULLS)
	local mid = L - 2 * tip
	local y = H / 2
	k:Box(cf * CFrame.new(0, y, 0), Vector3.new(W, H, mid), colors[1], M.SmoothPlastic)
	for _, dir in { -1, 1 } do
		local endCF = cf * CFrame.new(0, 0, dir * (mid / 2 + tip / 2)) * CFrame.Angles(0, if dir < 0 then 0 else math.pi, 0)
		k:Wedge(endCF * CFrame.new(W / 4, y, 0) * CFrame.Angles(0, 0, -math.pi / 2), Vector3.new(H, W / 2, tip), colors[1], M.SmoothPlastic)
		k:Wedge(endCF * CFrame.new(-W / 4, y, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(H, W / 2, tip), colors[1], M.SmoothPlastic)
		-- stem post
		k:Box(endCF * CFrame.new(0, H + 0.2, -tip / 2 + 0.15), Vector3.new(0.3, 1.6, 0.3), colors[3], M.Wood, Kit.DECO)
	end
	-- bands and deck
	for _, sx in { -1, 1 } do
		k:Box(cf * CFrame.new(sx * (W / 2 + 0.02), H - 0.35, 0), Vector3.new(0.08, 0.5, mid), colors[2], M.SmoothPlastic, Kit.DETAIL)
		k:Box(cf * CFrame.new(sx * (W / 2 + 0.02), H - 0.72, 0), Vector3.new(0.08, 0.16, mid), colors[3], M.SmoothPlastic, Kit.DETAIL)
	end
	k:Box(cf * CFrame.new(0, H - 0.05, 0), Vector3.new(W - 0.5, 0.12, mid + tip * 0.8), Palette.WoodPale, M.WoodPlanks, Kit.DETAIL)
	for _, z in { -mid / 4, mid / 4 } do
		k:Box(cf * CFrame.new(0, H + 0.2, z), Vector3.new(W - 0.3, 0.25, 0.8), Palette.Wood, M.Wood, Kit.DECO)
	end
	for _, sx in { -1, 1 } do
		k:Box(cf * CFrame.new(sx * 0.6, H + 0.45, 0) * CFrame.Angles(0, sx * 0.05, 0), Vector3.new(0.18, 0.18, L * 0.62), Palette.WoodPale, M.Wood, Kit.DETAIL)
	end
	if rng:Chance(0.6) then
		k:Blob(cf * CFrame.new(0, H + 0.4, mid / 3), Vector3.new(W * 0.6, 0.8, 2), Palette.rgb(96, 110, 70), M.Fabric, Kit.DETAIL)
	end
	return k
end

local function seawall(ctx, kit)
	local G = ctx.G
	local h = Plan.Harbour
	local z0, z1 = h.SeawallZ, h.SeawallZ + 3
	local x0, x1 = Plan.Harbour.QuayX0, 200
	kit:Box(CFrame.new((x0 + x1) / 2, (G - 6) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, G + 6, z1 - z0), STONE, M.Limestone)
	-- masonry courses
	for _, y in { 5.4, 8.2 } do
		kit:Box(CFrame.new((x0 + x1) / 2, y, z1 + 0.05), Vector3.new(x1 - x0, 0.25, 0.12), STONE_DARK, M.Limestone, Kit.DETAIL)
	end
	-- fishermen's arches (boat stores) along the quay stretch
	local rng = ctx.Rng:Fork(401)
	local x = -140
	while x < 30 do
		if math.abs(x) > 28 then
			local frame = CFrame.fromMatrix(Vector3.new(x, Plan.Quay + 3.4, z1), Vector3.new(1, 0, 0), UP)
			kit:Box(frame * CFrame.new(0, -1.7, -0.9), Vector3.new(4.6, 3.4, 0.2), Palette.Window, M.SmoothPlastic, Kit.DETAIL)
			kit:Box(frame * CFrame.new(0, 0.7, -0.9), Vector3.new(4.6, 1.4, 0.2), Palette.Window, M.SmoothPlastic, Kit.DETAIL)
			kit:Arch(frame, 2.3, 0.6, 0.7, STONE, M.Limestone, {
				HalfWidth = 3.2,
				Top = 3,
				RingColor = Palette.Stone,
				ZCenter = -0.2,
				Flags = Kit.DECO,
				FillFlags = Kit.DECO,
			})
			if rng:Chance(0.5) then
				local door = rng:Pick(Palette.Doors)
				kit:Box(frame * CFrame.new(0, -1.5, -0.7), Vector3.new(4.4, 3.8, 0.2), door, M.WoodPlanks, Kit.DECO)
			end
		end
		x += 14
	end
end

local function promenade(ctx, kit)
	local G = ctx.G
	local rng = ctx.Rng:Fork(402)
	local z = Plan.Harbour.SeawallZ - 0.6
	local x0, x1 = -150, 200
	local opening = 5
	-- solid parapet except the central belvedere (balustrade) and the stair opening
	for _, seg in { { x0, -26 }, { 26, x1 } } do
		local a, b = seg[1], seg[2]
		kit:Box(CFrame.new((a + b) / 2, G + 1.3, z), Vector3.new(b - a, 2.6, 0.9), STONE, M.Limestone)
		kit:Box(CFrame.new((a + b) / 2, G + 2.8, z), Vector3.new(b - a, 0.4, 1.3), Palette.Stone, M.Limestone, Kit.DECO)
	end
	for _, seg in { { -26, -opening }, { opening, 26 } } do
		local a, b = seg[1], seg[2]
		kit:Box(CFrame.new((a + b) / 2, G + 0.35, z), Vector3.new(b - a, 0.7, 1), Palette.Stone, M.Limestone)
		kit:Box(CFrame.new((a + b) / 2, G + 2.8, z), Vector3.new(b - a, 0.4, 1.2), Palette.Stone, M.Limestone)
		local posts = math.floor((b - a) / 0.8)
		for i = 0, posts do
			local px = a + 0.4 + i * (b - a - 0.8) / posts
			kit:Cyl(CFrame.new(px, G + 1.65, z) * CFrame.Angles(0, 0, math.pi / 2), 2, 0.5, Palette.Stone, M.Limestone, Kit.DETAIL)
		end
		kit:Box(CFrame.new(a + 0.5, G + 1.6, z), Vector3.new(1.2, 3.2, 1.3), STONE, M.Limestone)
		kit:Box(CFrame.new(b - 0.5, G + 1.6, z), Vector3.new(1.2, 3.2, 1.3), STONE, M.Limestone)
	end
	-- lamps, benches and palms along the promenade
	local x = x0 + 12
	local i = 0
	while x < x1 - 8 do
		if math.abs(x) > 30 then
			i += 1
			if i % 2 == 1 then
				Props.LampPost(ctx, kit, Vector3.new(x, G, z - 2.2), 1)
			else
				local seats = Props.Bench(kit, CFrame.lookAt(Vector3.new(x, G, z - 2.6), Vector3.new(x, G, z - 10)))
				for _, seat in seats do
					if rng:Chance(0.3) then
						table.insert(ctx.Info.Seats, seat)
					end
				end
				if x < -104 or x > 104 then
					Props.Palm(kit, Vector3.new(x + 6, Plan.Land, z - 9), rng)
				end
			end
			ctx:Block(Vector3.new(x, G, z - 2.4), 3)
		end
		x += 18
	end
	-- belvedere flower pots
	for _, px in { -18, -10, 10, 18 } do
		Props.Pot(kit, Vector3.new(px, G, z - 1.8), rng, "Geranium")
	end
end

local function stairs(ctx, kit)
	local G, Q = ctx.G, Plan.Quay
	local zs0, zs1 = Plan.Harbour.SeawallZ + 3, Plan.Harbour.SeawallZ + 8
	local zc = (zs0 + zs1) / 2
	-- landing in front of the belvedere opening
	kit:Box(CFrame.new(0, (Q + G) / 2, (Plan.Harbour.SeawallZ + zs1) / 2), Vector3.new(10, G - Q, zs1 - Plan.Harbour.SeawallZ), STONE, M.Limestone)
	local steps = G - Q - 1
	for _, dir in { -1, 1 } do
		for i = 1, steps do
			local xa = dir * (5 + (i - 1) * 2)
			local xb = dir * (5 + i * 2)
			local top = G - i
			kit:Box(CFrame.new((xa + xb) / 2, (Q + top) / 2, zc), Vector3.new(2, top - Q, zs1 - zs0), Palette.Stone, M.Limestone)
		end
		-- stepped parapet on the sea side
		for i = 0, steps do
			local xa = dir * (5 + (i - 1) * 2)
			local xb = dir * (5 + i * 2)
			local top = G - math.max(i, 0) + 2.4
			if i == 0 then
				xa, xb = dir * 0, dir * 5
			end
			kit:Box(CFrame.new((xa + xb) / 2, top - 1.2, zs1 - 0.4), Vector3.new(math.abs(xb - xa), 2.4, 0.8), STONE, M.Limestone)
		end
	end
	-- a small fountain niche under the landing
	local frame = CFrame.fromMatrix(Vector3.new(0, Q + 3.2, zs1), Vector3.new(1, 0, 0), UP)
	kit:Box(frame * CFrame.new(0, -1.6, -0.5), Vector3.new(3.6, 3.2, 0.2), Palette.rgb(70, 110, 118), M.Slate, Kit.DETAIL)
	kit:Arch(frame, 1.8, 0.6, 0.6, STONE, M.Limestone, {
		HalfWidth = 2.6,
		Top = 2.4,
		RingColor = Palette.Stone,
		ZCenter = 0.1,
		Flags = Kit.DECO,
		FillFlags = Kit.DECO,
	})
	kit:Box(frame * CFrame.new(0, -2.7, 0.9), Vector3.new(4.2, 1, 1.8), Palette.Stone, M.Limestone)
end

local function quayAndPier(ctx, kit, rng)
	local Q = Plan.Quay
	local h = Plan.Harbour
	local qz0, qz1 = h.SeawallZ + 3, h.QuayZ1
	kit:Box(CFrame.new((h.QuayX0 + h.QuayX1) / 2, Q - 0.75, (qz0 + qz1) / 2), Vector3.new(h.QuayX1 - h.QuayX0, 1.5, qz1 - qz0), QUAY, M.Pavement)
	kit:Box(CFrame.new((h.QuayX0 + h.QuayX1) / 2, Q - 0.7, qz1 - 0.6), Vector3.new(h.QuayX1 - h.QuayX0, 1.5, 1.2), Palette.Stone, M.Limestone)
	-- quay face down to the water
	kit:Box(CFrame.new((h.QuayX0 + h.QuayX1) / 2, (Q - 1.5 - 8) / 2, qz1 - 0.6), Vector3.new(h.QuayX1 - h.QuayX0, Q - 1.5 + 8, 1.2), STONE_DARK, M.Limestone)
	local p = h.Pier
	kit:Box(CFrame.new((p.X0 + p.X1) / 2, Q - 0.75, (qz1 + p.Z1) / 2), Vector3.new(p.X1 - p.X0, 1.5, p.Z1 - qz1), QUAY, M.Pavement)
	kit:Box(CFrame.new((p.X0 + p.X1) / 2, (Q - 1.5 - 12) / 2, (qz1 + p.Z1) / 2), Vector3.new(p.X1 - p.X0 - 0.4, Q - 1.5 + 12, p.Z1 - qz1), STONE_DARK, M.Limestone)
	for _, x in { p.X0 + 0.5, p.X1 - 0.5 } do
		kit:Box(CFrame.new(x, Q - 0.65, (qz1 + p.Z1) / 2), Vector3.new(1, 1.5, p.Z1 - qz1), Palette.Stone, M.Limestone)
	end
	-- bollards
	local x = h.QuayX0 + 6
	while x < h.QuayX1 - 3 do
		if not (x > p.X0 - 3 and x < p.X1 + 3) then
			kit:Post(Vector3.new(x, Q, qz1 - 1), 1.2, 1, Palette.Iron, M.Metal, Kit.SOLID)
		end
		x += 12
	end
	local z = qz1 + 8
	while z < p.Z1 - 12 do
		kit:Post(Vector3.new(p.X0 + 0.9, Q, z), 1.2, 1, Palette.Iron, M.Metal, Kit.SOLID)
		kit:Post(Vector3.new(p.X1 - 0.9, Q, z + 6), 1.2, 1, Palette.Iron, M.Metal, Kit.SOLID)
		-- fishermen sitting on the pier edge, legs over the water
		if rng:Chance(0.4) then
			local side = if rng:Chance(0.5) then -1 else 1
			local edgeX = if side < 0 then p.X0 else p.X1
			local pos = Vector3.new(edgeX + side * 0.3, Q + 1.5, z + 3)
			table.insert(ctx.Info.Fish, CFrame.lookAt(pos, pos + Vector3.new(side, 0, 0)))
		end
		z += 16
	end
	-- lighthouse
	local lk, light = kit:Group("Faro")
	ctx:Tag(light, "SicilyLamp")
	local base = Vector3.new((p.X0 + p.X1) / 2, Q, p.Z1 - 6)
	lk:Post(base, 2, 9, STONE, M.Limestone)
	lk:Post(base + Vector3.new(0, 2, 0), 17, 5.2, Palette.rgb(244, 242, 236), M.Plaster)
	for _, y in { 6, 12 } do
		lk:Post(base + Vector3.new(0, y, 0), 2.2, 5.3, Palette.rgb(196, 44, 40), M.Plaster, Kit.DECO)
	end
	lk:Post(base + Vector3.new(0, 19, 0), 0.5, 7, Palette.Iron, M.Metal, Kit.DECO)
	local lamp = lk:Post(base + Vector3.new(0, 19.5, 0), 2.6, 3.4, Palette.rgb(255, 236, 170), M.Neon, Kit.GLOW)
	lk:PointLight(lamp, Palette.rgb(255, 230, 170), 30, 1.4, false)
	lk:Post(base + Vector3.new(0, 22.1, 0), 0.4, 4, Palette.rgb(196, 44, 40), M.Metal, Kit.DECO)
	lk:Ball(base + Vector3.new(0, 22.6, 0), 3.6, Palette.rgb(196, 44, 40), M.Metal, Kit.DECO)
	ctx:Block(base, 6)

	-- boats moored along the quay and the pier
	for i = 1, 6 do
		local bx = h.QuayX0 + 18 + (i - 1) * 25 + rng:Range(-3, 3)
		if not (bx > p.X0 - 10 and bx < p.X1 + 10) then
			Harbour.Boat(kit, CFrame.new(bx, -0.6, qz1 + 3.4) * CFrame.Angles(0, math.pi / 2 + rng:Range(-0.08, 0.08), 0), rng)
		end
	end
	for i = 1, 4 do
		local side = if i % 2 == 0 then -1 else 1
		local bx = (if side < 0 then p.X0 else p.X1) + side * 3.4
		Harbour.Boat(kit, CFrame.new(bx, -0.6, qz1 + 20 + i * 18) * CFrame.Angles(0, rng:Range(-0.06, 0.06), 0), rng)
	end
	-- nets, crates and barrels on the quay
	local qx = h.QuayX0 + 10
	while qx < h.QuayX1 - 10 do
		if rng:Chance(0.55) and not (qx > -12 and qx < 12) and not (qx > p.X0 - 6 and qx < p.X1 + 6) then
			local spot = Vector3.new(qx + rng:Range(-3, 3), Q, qz0 + rng:Range(2.5, 6))
			local roll = rng:Next()
			if roll < 0.35 then
				kit:Blob(CFrame.new(spot + Vector3.new(0, 0.5, 0)), Vector3.new(4, 1, 3), Palette.rgb(100, 116, 76), M.Fabric, Kit.DECO)
				kit:Blob(CFrame.new(spot + Vector3.new(0.6, 0.9, 0.3)), Vector3.new(2.4, 0.8, 1.8), Palette.rgb(170, 70, 50), M.Fabric, Kit.DECO)
			elseif roll < 0.7 then
				Props.Crate(kit, CFrame.new(spot + Vector3.new(0, 0.4, 0)), rng, nil)
				Props.Crate(kit, CFrame.new(spot + Vector3.new(0.2, 1.2, 0)) * CFrame.Angles(0, 0.4, 0), rng, nil)
			else
				kit:Post(spot, 2.4, 1.8, Palette.Wood, M.WoodPlanks, Kit.SOLID)
				kit:Post(spot + Vector3.new(2, 0, 0.6), 2.4, 1.8, Palette.Wood, M.WoodPlanks, Kit.SOLID)
			end
			ctx:Block(spot, 3)
		end
		qx += 12
	end
end

local function beach(_ctx, kit, rng)
	local b = Plan.Harbour.Beach
	-- boats pulled up on the sand, bows towards the town
	for i = 1, 5 do
		local x = b.X0 + 18 + i * 22 + rng:Range(-4, 4)
		local z = b.Z0 + 16 + rng:Range(-3, 5)
		local y = Plan.HeightAt(x, z)
		local cf = CFrame.new(x, y - 0.15, z) * CFrame.Angles(0, rng:Range(-0.25, 0.25), 0) * CFrame.Angles(math.rad(-8), 0, math.rad(rng:Range(-6, 6)))
		Harbour.Boat(kit, cf, rng)
	end
	-- a few beach umbrellas
	for i = 1, 5 do
		local x = b.X0 + 30 + i * 24
		local z = b.Z0 + 6 + rng:Range(0, 4)
		local y = Plan.HeightAt(x, z)
		local base = Vector3.new(x, y, z)
		kit:Post(base - Vector3.new(0, 0.8, 0), 7.2, 0.18, Palette.WoodPale, M.Wood, Kit.DECO)
		kit:Blob(CFrame.new(base + Vector3.new(0, 6.3, 0)) * CFrame.Angles(rng:Range(-0.1, 0.1), 0, rng:Range(-0.1, 0.1)), Vector3.new(7, 1.2, 7), rng:Pick({
			Palette.rgb(40, 90, 160),
			Palette.rgb(236, 230, 214),
			Palette.rgb(200, 60, 44),
		}), M.Fabric, Kit.DECO)
		kit:Box(CFrame.new(base + Vector3.new(2.2, 0.6, 1)) * CFrame.Angles(0, 0.3, 0), Vector3.new(2, 0.3, 5), Palette.rgb(240, 236, 226), M.Fabric, Kit.DECO)
	end
end

function Harbour.Build(ctx, parentKit)
	local kit = parentKit:Group("Marina")
	local rng = ctx.Rng:Fork(400)
	seawall(ctx, kit)
	promenade(ctx, kit)
	stairs(ctx, kit)
	quayAndPier(ctx, kit, rng)
	beach(ctx, kit, rng)

	-- Opening shot: from the sea towards the town and the cathedral domes.
	ctx.Info.ShotsByName.Harbour = {
		CFrame.lookAt(Vector3.new(-120, 16, 380), Vector3.new(-20, 22, 160)),
		CFrame.lookAt(Vector3.new(-40, 13, 300), Vector3.new(0, 20, 170)),
	}
end

return Harbour
