--[[
	Piazza del Duomo: the baroque cathedral with twin bell towers and a majolica dome, the
	fountain, Garibaldi's statue, the market, the arcaded Palazzo di Città (town hall, east) and
	the café arcade (west), plus benches, lamps, palms, spawn points and NPC spots.
]]

local Facade = require(script.Parent.Facade)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plan = require(script.Parent.Plan)
local Props = require(script.Parent.Props)

local Landmarks = {}

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local box = Facade.Box

local GOLD = Palette.rgb(226, 196, 146) -- sunlit Noto limestone
local GOLD_TRIM = Palette.rgb(240, 222, 186)
local GOLD_SHADOW = Palette.rgb(204, 172, 124)
local BRONZE = Palette.rgb(150, 110, 58)
local MAJOLICA = Palette.rgb(58, 118, 104)

-- Church ------------------------------------------------------------------------------------

local function bell(kit, position: Vector3)
	kit:Post(position - Vector3.new(0, 1.3, 0), 1.6, 2, BRONZE, M.Metal, Kit.DECO)
	kit:Ball(position + Vector3.new(0, 0.3, 0), 2, BRONZE, M.Metal, Kit.DECO)
	kit:Box(CFrame.new(position + Vector3.new(0, 1.5, 0)), Vector3.new(0.3, 1, 3), Palette.WoodDark, M.Wood, Kit.DETAIL)
end

local function cross(kit, base: Vector3, size: number)
	kit:Box(CFrame.new(base + Vector3.new(0, size / 2, 0)), Vector3.new(0.3, size, 0.3), Palette.Iron, M.Metal, Kit.DETAIL)
	kit:Box(CFrame.new(base + Vector3.new(0, size * 0.68, 0)), Vector3.new(size * 0.62, 0.3, 0.3), Palette.Iron, M.Metal, Kit.DETAIL)
end

-- A tower belfry: four corner piers with arches on every side and a bell inside.
local function belfry(kit, center: Vector3, width: number, height: number)
	local pier = 2.8
	local half = width / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			kit:Box(
				CFrame.new(center + Vector3.new(sx * (half - pier / 2), height / 2, sz * (half - pier / 2))),
				Vector3.new(pier, height, pier),
				GOLD,
				M.Limestone
			)
		end
	end
	local span = width - 2 * pier
	local radius = span / 2
	local springing = height - radius - 1.6
	for i = 0, 3 do
		local yaw = i * math.pi / 2
		local face = CFrame.new(center) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, springing, -half + 0.7)
		kit:Arch(face * CFrame.Angles(0, math.pi, 0), radius, 1.4, 0.9, GOLD, M.Limestone, {
			HalfWidth = radius,
			Top = height - springing,
			RingColor = GOLD_TRIM,
			ZCenter = 0,
		})
		-- balustrade across the opening
		kit:Box(face * CFrame.new(0, -springing + 1.6, 0), Vector3.new(span, 0.4, 1), GOLD_TRIM, M.Limestone, Kit.DECO)
	end
	bell(kit, center + Vector3.new(0, springing - 0.5, 0))
end

local function tower(kit, frame: CFrame, x0: number, width: number, depth: number, height: number)
	local cx = x0 + width / 2
	-- body
	box(kit, frame, x0, x0 + width, 0, height, -depth, 0, GOLD, M.Limestone)
	-- corner pilasters and cornices
	for _, x in { x0 + 0.6, x0 + width - 0.6 } do
		box(kit, frame, x - 0.7, x + 0.7, 0, height, 0, 0.5, GOLD_TRIM, M.Limestone, Kit.DECO)
	end
	for _, y in { 20.5, height - 1 } do
		box(kit, frame, x0 - 0.4, x0 + width + 0.4, y, y + 1.1, -depth - 0.4, 0.9, GOLD_TRIM, M.Limestone, Kit.DECO)
	end
	-- small arched window
	local wf = frame * CFrame.new(cx, 27, 0.02)
	box(kit, frame, cx - 1.1, cx + 1.1, 23.5, 27, -0.6, 0.01, Palette.Window, M.SmoothPlastic, Kit.DETAIL)
	kit:Arch(wf, 1.1, 0.5, 0.5, GOLD_TRIM, M.Limestone, { HalfWidth = 1.6, Top = 1.6, ZCenter = 0.1, Segments = 6, Flags = Kit.DETAIL, FillFlags = Kit.DETAIL })
	box(kit, frame, cx - 1.1, cx + 1.1, 27, 28.1, -0.61, -0.4, Palette.Window, M.SmoothPlastic, Kit.DETAIL)
	-- belfry, drum, dome, lantern, cross
	local top = frame * CFrame.new(cx, height, -depth / 2)
	belfry(kit, top.Position, width, 12)
	local y = top.Position.Y + 12
	kit:Box(CFrame.new(top.Position.X, y + 0.5, top.Position.Z), Vector3.new(width + 0.8, 1, depth + 0.8), GOLD_TRIM, M.Limestone, Kit.DECO)
	kit:Post(Vector3.new(top.Position.X, y + 1, top.Position.Z), 4.5, width * 0.72, GOLD, M.Limestone)
	kit:Ball(Vector3.new(top.Position.X, y + 5.5, top.Position.Z), width * 0.72, MAJOLICA, M.CeramicTiles, Kit.SOLID)
	kit:Post(Vector3.new(top.Position.X, y + 5.5 + width * 0.3, top.Position.Z), 2.2, 1.6, GOLD_TRIM, M.Limestone, Kit.DECO)
	kit:Ball(Vector3.new(top.Position.X, y + 8.3 + width * 0.3, top.Position.Z), 1.9, MAJOLICA, M.CeramicTiles, Kit.DECO)
	cross(kit, Vector3.new(top.Position.X, y + 9.1 + width * 0.3, top.Position.Z), 3)
end

local function statueFigure(kit, base: CFrame, scale: number, color: Color3, material, pose: string?)
	local s = scale
	kit:Box(base * CFrame.new(-0.5 * s, 1 * s, 0), Vector3.new(1 * s, 2 * s, 1 * s), color, material, Kit.DECO)
	kit:Box(base * CFrame.new(0.5 * s, 1 * s, 0), Vector3.new(1 * s, 2 * s, 1 * s), color, material, Kit.DECO)
	kit:Box(base * CFrame.new(0, 3 * s, 0), Vector3.new(2 * s, 2 * s, 1 * s), color, material, Kit.DECO)
	kit:Box(base * CFrame.new(0, 4.5 * s, 0), Vector3.new(1.2 * s, 1.2 * s, 1.2 * s), color, material, Kit.DECO)
	kit:Box(base * CFrame.new(-1.5 * s, 3 * s, 0), Vector3.new(1 * s, 2 * s, 1 * s), color, material, Kit.DECO)
	if pose == "Point" then
		kit:Box(
			base * CFrame.new(1.5 * s, 4 * s, -0.6 * s) * CFrame.Angles(math.rad(70), 0, math.rad(-20)),
			Vector3.new(1 * s, 2 * s, 1 * s),
			color,
			material,
			Kit.DECO
		)
		kit:Box(base * CFrame.new(0, 3 * s, 0.6 * s), Vector3.new(2.3 * s, 3.6 * s, 0.3 * s), color, material, Kit.DETAIL) -- cloak
	else
		kit:Box(base * CFrame.new(1.5 * s, 3 * s, 0), Vector3.new(1 * s, 2 * s, 1 * s), color, material, Kit.DECO)
	end
end

function Landmarks.Church(ctx, parentKit)
	local kit = parentKit:Group("Duomo")
	local c = Plan.Church
	local G = ctx.G
	local base = G + c.Rise
	local hw = c.HalfWidth
	-- stairs and sagrato
	for i = 1, c.Rise do
		local z1 = c.StairsZ1 - (i - 1) * 2
		local z0 = if i == c.Rise then c.FacadeZ else z1 - 2
		kit:Box(CFrame.new(0, G + i / 2, (z0 + z1) / 2), Vector3.new(hw * 2, i, z1 - z0), Palette.Vary(GOLD_TRIM, ctx.Rng, 0.01), M.Limestone)
	end
	kit:Box(CFrame.new(0, G + c.Rise / 2, (c.FacadeZ + c.BackZ) / 2), Vector3.new(hw * 2 - 2, c.Rise, c.FacadeZ - c.BackZ), GOLD_SHADOW, M.Limestone)

	-- Facade frame: origin at the facade's west end, +X east, +Z towards the piazza.
	local frame = CFrame.fromMatrix(Vector3.new(-hw, base, c.FacadeZ), Vector3.new(1, 0, 0), UP)
	local towerW = hw - c.NaveHalfWidth
	local centerX0, centerX1 = towerW, 2 * hw - towerW
	local mid = hw
	local tier1, tier2 = 20.5, 34

	-- tier 1 wall with portal
	local portalW, portalR = 7, 3.5
	local portalSpring = 10
	box(kit, frame, centerX0, mid - portalW / 2, 0, tier1, -2.2, 0, GOLD, M.Limestone)
	box(kit, frame, mid + portalW / 2, centerX1, 0, tier1, -2.2, 0, GOLD, M.Limestone)
	kit:Arch(frame * CFrame.new(mid, portalSpring, 0), portalR, 2.2, 1.3, GOLD, M.Limestone, {
		HalfWidth = portalW / 2,
		Top = tier1 - portalSpring,
		RingColor = GOLD_TRIM,
		ZCenter = -1.1,
	})
	box(kit, frame, mid - portalW / 2, mid - 0.04, 0, portalSpring, -1.8, -1.5, Palette.rgb(70, 42, 28), M.WoodPlanks)
	box(kit, frame, mid + 0.04, mid + portalW / 2, 0, portalSpring, -1.8, -1.5, Palette.rgb(70, 42, 28), M.WoodPlanks)
	box(kit, frame, mid - portalR, mid + portalR, portalSpring, portalSpring + portalR, -2.1, -1.8, Palette.rgb(60, 36, 24), M.WoodPlanks, Kit.DECO)
	-- columns flanking the portal
	for _, x in { mid - 5.4, mid + 5.4, centerX0 + 1.4, centerX1 - 1.4 } do
		box(kit, frame, x - 1.1, x + 1.1, 0, 1.4, 0, 1.6, GOLD_TRIM, M.Limestone)
		kit:Cyl(frame * CFrame.new(x, 1.4 + 8.2, 0.8) * CFrame.Angles(0, 0, math.pi / 2), 16.4, 1.5, GOLD_TRIM, M.Limestone, Kit.SOLID)
		box(kit, frame, x - 1.1, x + 1.1, 17.8, 18.8, -0.2, 1.7, GOLD_TRIM, M.Limestone, Kit.DECO)
	end
	-- niches with saints
	for _, x in { mid - 9, mid + 9 } do
		box(kit, frame, x - 1.3, x + 1.3, 4, 12, -1.6, -0.05, GOLD_SHADOW, M.Limestone, Kit.DECO)
		box(kit, frame, x - 1.6, x + 1.6, 12, 12.6, 0, 0.5, GOLD_TRIM, M.Limestone, Kit.DETAIL)
		statueFigure(kit, frame * CFrame.new(x, 4.3, -0.8), 1.2, Palette.Marble, M.Marble)
	end
	-- entablature
	box(kit, frame, centerX0 - 0.3, centerX1 + 0.3, tier1 - 1.7, tier1 - 0.6, -0.5, 1.9, GOLD_TRIM, M.Limestone, Kit.DECO)
	box(kit, frame, centerX0 - 0.8, centerX1 + 0.8, tier1 - 0.6, tier1, -0.5, 2.4, GOLD_TRIM, M.Limestone, Kit.DECO)

	-- tier 2 (narrower) with a big arched window and volutes
	local t2x0, t2x1 = mid - 10, mid + 10
	local winR = 2.6
	local winSpring = tier1 + 7
	box(kit, frame, t2x0, mid - winR, tier1, tier2, -2, 0, GOLD, M.Limestone)
	box(kit, frame, mid + winR, t2x1, tier1, tier2, -2, 0, GOLD, M.Limestone)
	box(kit, frame, mid - winR, mid + winR, tier1, tier1 + 2, -2, 0, GOLD, M.Limestone)
	kit:Arch(frame * CFrame.new(mid, winSpring, 0), winR, 2, 0.9, GOLD, M.Limestone, {
		HalfWidth = winR,
		Top = tier2 - winSpring,
		RingColor = GOLD_TRIM,
		ZCenter = -1,
	})
	box(kit, frame, mid - winR, mid + winR, tier1 + 2, winSpring + winR, -1.9, -1.7, Palette.Glass, M.Glass, { Collide = true, Reflectance = 0.15 })
	for _, x in { t2x0 + 0.8, t2x1 - 0.8, mid - winR - 1.4, mid + winR + 1.4 } do
		box(kit, frame, x - 0.8, x + 0.8, tier1, tier2 - 1, 0, 0.6, GOLD_TRIM, M.Limestone, Kit.DECO)
	end
	-- volutes (scrolls) stepping down to the towers
	for _, side in { -1, 1 } do
		local x = if side < 0 then t2x0 - 2 else t2x1 + 2
		kit:Wedge(
			frame * CFrame.new(x, tier1 + 3.2, -1) * CFrame.Angles(0, side * -math.pi / 2, 0),
			Vector3.new(2, 6.4, 4),
			GOLD_TRIM,
			M.Limestone,
			Kit.DECO
		)
		kit:Cyl(frame * CFrame.new(x + side * 1.6, tier1 + 1, -1) * CFrame.Angles(0, math.pi / 2, 0), 2.2, 2.2, GOLD_TRIM, M.Limestone, Kit.DECO)
	end
	box(kit, frame, t2x0 - 0.5, t2x1 + 0.5, tier2 - 1, tier2, -0.5, 1.4, GOLD_TRIM, M.Limestone, Kit.DECO)
	-- pediment with the clock
	local pedHalf = 11
	for _, side in { -1, 1 } do
		kit:Wedge(
			frame * CFrame.new(mid + side * pedHalf / 2, tier2 + 2.9, -0.5) * CFrame.Angles(0, side * -math.pi / 2, 0),
			Vector3.new(2, 5.8, pedHalf),
			GOLD_TRIM,
			M.Limestone
		)
	end
	local clock = kit:Cyl(frame * CFrame.new(mid, tier2 + 2.2, 0.55) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 3.2, Palette.rgb(246, 242, 230), M.Marble, Kit.DECO)
	kit:Cyl(frame * CFrame.new(mid, tier2 + 2.2, 0.45) * CFrame.Angles(0, math.pi / 2, 0), 0.2, 3.6, BRONZE, M.Metal, Kit.DETAIL)
	-- hands at twenty past five (matches the golden-hour sky)
	kit:Box(frame * CFrame.new(mid + 0.35, tier2 + 2.2 - 0.45, 0.75) * CFrame.Angles(0, 0, math.rad(35)), Vector3.new(0.14, 1.1, 0.08), Palette.Iron, M.Metal, Kit.DETAIL)
	kit:Box(frame * CFrame.new(mid + 0.5, tier2 + 2.2 - 0.1, 0.75) * CFrame.Angles(0, 0, math.rad(-60)), Vector3.new(0.12, 1.4, 0.08), Palette.Iron, M.Metal, Kit.DETAIL)
	local _ = clock
	cross(kit, (frame * CFrame.new(mid, tier2 + 5.8, -0.5)).Position, 3.4)

	-- towers
	tower(kit, frame, 0, towerW, 12, tier2)
	tower(kit, frame, 2 * hw - towerW, towerW, 12, tier2)

	-- nave, transept and dome
	local naveTop = base + 30
	local nz0, nz1 = c.BackZ, c.FacadeZ - 2
	local nhw = c.NaveHalfWidth
	kit:Box(CFrame.new(0, (base + naveTop) / 2, (nz0 + nz1) / 2), Vector3.new(nhw * 2, naveTop - base, nz1 - nz0), GOLD_SHADOW, M.Limestone)
	local rise = 6
	for _, sx in { -1, 1 } do
		kit:Wedge(
			CFrame.new(sx * nhw / 2 + sx * 0.3, naveTop + rise / 2, (nz0 + nz1) / 2) * CFrame.Angles(0, sx * -math.pi / 2, 0),
			Vector3.new(nz1 - nz0, rise, nhw + 0.6),
			Palette.Roofs[1],
			M.ClayRoofTiles
		)
	end
	-- side windows and buttresses
	for i = 0, 3 do
		local z = nz0 + 6 + i * ((nz1 - nz0 - 12) / 3)
		for _, sx in { -1, 1 } do
			kit:Box(CFrame.new(sx * (nhw + 0.05), base + 19, z), Vector3.new(0.4, 8, 3), Palette.Window, M.SmoothPlastic, Kit.DETAIL)
			kit:Box(CFrame.new(sx * (nhw + 0.5), base + 14, z + 5), Vector3.new(1.2, 28, 1.6), GOLD_TRIM, M.Limestone, Kit.DECO)
		end
	end
	local tz0, tz1 = -156, -140
	kit:Box(CFrame.new(0, (base + naveTop - 2) / 2, (tz0 + tz1) / 2), Vector3.new(44, naveTop - 2 - base, tz1 - tz0), GOLD_SHADOW, M.Limestone)
	for _, sz in { -1, 1 } do
		kit:Wedge(
			CFrame.new(0, naveTop - 2 + 2.6, (tz0 + tz1) / 2 + sz * 4.2) * CFrame.Angles(0, if sz < 0 then 0 else math.pi, 0),
			Vector3.new(44.4, 5.2, 8.4),
			Palette.Roofs[1],
			M.ClayRoofTiles
		)
	end
	local domeCenter = Vector3.new(0, naveTop + rise, -148)
	kit:Box(CFrame.new(domeCenter + Vector3.new(0, 1, 0)), Vector3.new(19, 2, 19), GOLD_TRIM, M.Limestone)
	kit:Post(domeCenter + Vector3.new(0, 2, 0), 7, 16, GOLD, M.Limestone)
	for i = 0, 7 do
		local a = i * math.pi / 4
		kit:Box(
			CFrame.new(domeCenter + Vector3.new(math.cos(a) * 8, 5.5, math.sin(a) * 8)) * CFrame.Angles(0, -a, 0),
			Vector3.new(0.3, 3.4, 1.6),
			Palette.Window,
			M.SmoothPlastic,
			Kit.DETAIL
		)
	end
	kit:Box(CFrame.new(domeCenter + Vector3.new(0, 9.2, 0)), Vector3.new(17.4, 0.6, 17.4), GOLD_TRIM, M.Limestone, Kit.DECO)
	kit:Ball(domeCenter + Vector3.new(0, 9, 0), 16, MAJOLICA, M.CeramicTiles)
	kit:Post(domeCenter + Vector3.new(0, 16.6, 0), 3, 2.6, GOLD_TRIM, M.Limestone, Kit.DECO)
	kit:Ball(domeCenter + Vector3.new(0, 19.8, 0), 2.8, MAJOLICA, M.CeramicTiles, Kit.DECO)
	cross(kit, domeCenter + Vector3.new(0, 20.8, 0), 3.2)

	return frame
end

-- Piazza furniture -------------------------------------------------------------------------------

function Landmarks.Fountain(ctx, parentKit)
	local kit = parentKit:Group("Fontana")
	local G = ctx.G
	local c = Vector3.new(Plan.Fountain.X, G, Plan.Fountain.Z)
	local apothem = 7.5
	local side = 2 * apothem * math.tan(math.pi / 8)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local cf = CFrame.new(c) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.9, -(apothem + 0.55))
		kit:Box(cf, Vector3.new(side + 0.9, 1.8, 1.1), GOLD_TRIM, M.Marble)
		kit:Box(cf * CFrame.new(0, 0.95, -0.1), Vector3.new(side + 1.2, 0.2, 1.5), Palette.Marble, M.Marble, Kit.DECO)
	end
	kit:Cyl(CFrame.new(c + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.2, 16.4, GOLD_SHADOW, M.Limestone, Kit.DECO)
	local water = Palette.rgb(96, 160, 168)
	kit:Cyl(CFrame.new(c + Vector3.new(0, 1.35, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.2, 15.9, water, M.Glass, {
		Collide = false,
		Transparency = 0.3,
		Reflectance = 0.25,
		Shadow = false,
	})
	kit:Post(c, 3.4, 2.6, GOLD_TRIM, M.Marble)
	kit:Cyl(CFrame.new(c + Vector3.new(0, 3.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.9, 7, Palette.Marble, M.Marble, Kit.SOLID)
	kit:Cyl(CFrame.new(c + Vector3.new(0, 4.27, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.1, 6.4, water, M.Glass, {
		Collide = false,
		Transparency = 0.3,
		Reflectance = 0.25,
		Shadow = false,
	})
	kit:Post(c + Vector3.new(0, 4.2, 0), 2.4, 1.1, Palette.Marble, M.Marble, Kit.DECO)
	kit:Ball(c + Vector3.new(0, 7.2, 0), 1.9, Palette.Marble, M.Marble, Kit.DECO)
	-- spouts
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		kit:Beam(c + dir * 3.4 + Vector3.new(0, 4.1, 0), c + dir * 5.4 + Vector3.new(0, 1.5, 0), 0.35, Palette.rgb(200, 230, 236), M.Glass, {
			Collide = false,
			Transparency = 0.45,
			Shadow = false,
		})
	end
	ctx:Block(c, apothem + 2)
end

function Landmarks.Statue(ctx, parentKit, position: Vector3, facing: Vector3)
	local kit = parentKit:Group("Garibaldi")
	local cf = CFrame.lookAt(position, position + facing)
	kit:Box(cf * CFrame.new(0, 0.5, 0), Vector3.new(5, 1, 5), GOLD_TRIM, M.Limestone)
	kit:Box(cf * CFrame.new(0, 3.5, 0), Vector3.new(3.8, 5, 3.8), GOLD, M.Marble)
	kit:Box(cf * CFrame.new(0, 6.3, 0), Vector3.new(4.4, 0.6, 4.4), GOLD_TRIM, M.Marble)
	local plaque = kit:Box(cf * CFrame.new(0, 3.6, -1.95), Vector3.new(2.8, 1.6, 0.1), BRONZE, M.Metal, Kit.DETAIL)
	kit:Sign(plaque, Enum.NormalId.Front, "GIUSEPPE GARIBALDI", { Color = Palette.rgb(240, 220, 170), Font = Enum.Font.Garamond })
	statueFigure(kit, cf * CFrame.new(0, 6.6, 0), 1.6, Palette.rgb(74, 104, 90), M.Metal, "Point")
	ctx:Block(position, 4)
end

function Landmarks.Market(ctx, parentKit, rng)
	local kit = parentKit:Group("Mercato")
	local G = ctx.G
	local produce = {
		{ Palette.Orange, Palette.Lemon },
		{ Palette.rgb(200, 40, 36), Palette.rgb(96, 150, 56) },
		{ Palette.rgb(120, 60, 110), Palette.rgb(236, 200, 80) },
		{ Palette.rgb(150, 190, 90), Palette.Orange },
		{ Palette.rgb(210, 70, 50), Palette.rgb(240, 220, 170) },
		{ Palette.Lemon, Palette.rgb(80, 120, 60) },
	}
	local stalls = {
		{ -50, -44, 0 },
		{ -38, -44, 0 },
		{ -26, -44, 0 },
		{ -50, -78, math.pi },
		{ -38, -78, math.pi },
		{ -26, -78, math.pi },
	}
	for i, s in stalls do
		-- stall faces +Z (south) unless rotated; vendor stands behind it.
		local cf = CFrame.new(s[1], G, s[2]) * CFrame.Angles(0, s[3], 0)
		local k = kit:Group("Bancarella")
		local canvas = if i % 2 == 0 then Palette.Canvas else rng:Pick(Palette.Awnings)
		for _, x in { -4.2, 4.2 } do
			for _, z in { -2, 2 } do
				k:Post((cf * CFrame.new(x, 0, z)).Position, if z < 0 then 8 else 7.2, 0.3, Palette.WoodDark, M.Wood, Kit.SOLID)
			end
		end
		k:Box(cf * CFrame.new(0, 3.2, 0.6), Vector3.new(8.6, 0.35, 3.2), Palette.WoodPale, M.WoodPlanks)
		k:Box(cf * CFrame.new(0, 1.6, 2.2), Vector3.new(8.6, 3, 0.1), Palette.Vary(canvas, rng, 0.03), M.Fabric, Kit.DECO)
		k:Box(cf * CFrame.new(0, 7.8, 0) * CFrame.Angles(math.rad(-9), 0, 0), Vector3.new(9.6, 0.12, 5.6), canvas, M.Fabric, Kit.DECO)
		local fruit = produce[(i - 1) % #produce + 1]
		for j = -1, 1 do
			Props.Crate(k, cf * CFrame.new(j * 2.7, 3.8, 0.8) * CFrame.Angles(math.rad(-10), 0, 0), rng, fruit[(j + 2) % 2 + 1])
		end
		Props.Crate(k, cf * CFrame.new(-3.3, 0.4, 3.4), rng, fruit[1])
		Props.Crate(k, cf * CFrame.new(3.3, 0.4, 3.4) * CFrame.Angles(0, 0.3, 0), rng, fruit[2])
		-- vendor stands behind (at -Z of the stall) facing the customers (+Z)
		table.insert(ctx.Info.Vendors, cf * CFrame.new(0, 3, -2) * CFrame.Angles(0, math.pi, 0))
		ctx:Block((cf * CFrame.new(0, 0, 0.6)).Position, 5.2)
	end
end

-- Arcaded palazzo --------------------------------------------------------------------------------

--[[
	Builds a palazzo whose ground floor is an open arcade (portico).
	frame: facade frame (origin bottom-left from the street, X along, Z out), width, depth
	(into the block), floors above the arcade, style.
]]
local function arcadedPalazzo(ctx, kit, frame: CFrame, width: number, depth: number, spec)
	local rng = spec.Rng
	local style = spec.Style
	local bays = spec.Bays
	local bay = width / bays
	local porticoDepth = 8
	local groundH = 13
	local radius = math.min(3.6, bay / 2 - 1.3)
	local springing = groundH - radius - 2
	local trim = style.Trim

	-- arcade front
	for i = 0, bays do
		local x = i * bay
		local pw = bay - radius * 2
		local x0 = math.max(0, x - pw / 2)
		local x1 = math.min(width, x + pw / 2)
		box(kit, frame, x0, x1, 0, springing, -1.4, 0, style.GroundWall, M.Limestone)
		box(kit, frame, x0 - 0.1, x1 + 0.1, springing - 0.6, springing, -1.5, 0.15, trim, M.Limestone, Kit.DECO)
		box(kit, frame, x0 - 0.1, x1 + 0.1, 0, 1.2, -1.5, 0.15, trim, M.Limestone, Kit.DECO)
	end
	for i = 1, bays do
		local cx = (i - 0.5) * bay
		kit:Arch(frame * CFrame.new(cx, springing, 0), radius, 1.4, 0.9, style.GroundWall, M.Limestone, {
			HalfWidth = bay / 2,
			Top = groundH - springing,
			RingColor = trim,
			ZCenter = -0.7,
		})
	end
	-- portico ceiling, floor and back wall with doors/shops
	box(kit, frame, 0, width, groundH - 0.8, groundH, -porticoDepth, -1.4, Palette.Darken(style.GroundWall, 0.08), M.Plaster, Kit.DECO)
	box(kit, frame, 0, width, -0.6, 0.02, -porticoDepth, 0, Palette.PavingLight, M.Limestone)
	local backFrame = frame * CFrame.new(0, 0, -porticoDepth)
	local info = Facade.Build(kit, backFrame, {
		Width = width,
		Height = groundH,
		FloorLines = { 0 },
		Kind = spec.BackKind or "Piazza",
		Style = style,
		ShopChance = spec.ShopChance or 0.6,
		Rng = rng,
		Ctx = ctx,
		BayWidth = bay,
	})
	-- lanterns hanging in each arch
	for i = 1, bays do
		local cx = (i - 0.5) * bay
		local lampKit, lamp = kit:Group("ArcadeLamp")
		ctx:Tag(lamp, "SicilyLamp")
		local p = frame * CFrame.new(cx, groundH - 2.4, -4.5)
		lampKit:Beam((p * CFrame.new(0, 1.6, 0)).Position, (p * CFrame.new(0, 0.5, 0)).Position, 0.08, Palette.Iron, M.Metal)
		local bulb = lampKit:Box(p, Vector3.new(0.7, 1, 0.7), Palette.Bulb, M.Neon, Kit.GLOW)
		lampKit:Box(p * CFrame.new(0, 0.6, 0), Vector3.new(0.9, 0.15, 0.9), Palette.Iron, M.Metal, Kit.DETAIL)
		if i % 2 == 1 then
			lampKit:PointLight(bulb, Palette.LampLight, 16, 1.1, false)
		end
	end
	-- upper floors
	local lines = { 0 }
	local floorH = spec.FloorHeight or 12
	for f = 1, spec.Floors do
		lines[f + 1] = groundH + (f - 1) * floorH
	end
	local height = groundH + spec.Floors * floorH
	Facade.Build(kit, frame, {
		Width = width,
		Height = height,
		FloorLines = lines,
		Kind = "Piazza",
		Style = style,
		NoGround = true,
		Rng = rng,
		Ctx = ctx,
		BayWidth = bay,
	})
	-- building mass behind the facade
	box(kit, frame, 0.2, width - 0.2, groundH, height, -depth, -1.3, style.Wall, style.WallMat)
	box(kit, frame, 0.2, width - 0.2, 0, groundH, -depth, -porticoDepth - 1.3, style.Wall, style.WallMat)
	box(kit, frame, 0, width, height, height + 0.6, -depth, 0, Palette.Darken(style.Wall, 0.12), M.Concrete)
	-- balustrade parapet with urns
	local posts = math.floor(width / 3)
	box(kit, frame, 0, width, height + 0.6, height + 1.1, 0.1, 1, trim, M.Limestone, Kit.DECO)
	box(kit, frame, 0, width, height + 3.1, height + 3.5, 0.1, 1, trim, M.Limestone, Kit.DECO)
	for i = 0, posts do
		local x = math.min(width - 0.3, 0.3 + i * (width - 0.6) / posts)
		box(kit, frame, x - 0.25, x + 0.25, height + 1.1, height + 3.1, 0.3, 0.8, trim, M.Limestone, Kit.DETAIL)
		if i % 4 == 0 then
			kit:Ball((frame * CFrame.new(x, height + 4.3, 0.55)).Position, 1.2, trim, M.Limestone, Kit.DETAIL)
			box(kit, frame, x - 0.35, x + 0.35, height + 3.5, height + 3.9, 0.2, 0.9, trim, M.Limestone, Kit.DETAIL)
		end
	end
	return info, height
end

local function flag(kit, pole0: Vector3, pole1: Vector3, colors: { Color3 }, diagonal: boolean?)
	kit:Beam(pole0, pole1, 0.18, Palette.rgb(220, 206, 150), M.Metal, Kit.DETAIL)
	local dir = (pole1 - pole0).Unit
	local hang = CFrame.lookAt(pole1, pole1 + Vector3.new(0, -1, 0), dir)
	local length, h = 5, 3.4
	if diagonal then
		-- Sicily: red and yellow halves split diagonally
		kit:Wedge(hang * CFrame.new(0, -length / 2, -h / 2) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.06, length, h), colors[1], M.Fabric, Kit.DETAIL)
		kit:Wedge(hang * CFrame.new(0, -length / 2, -h / 2) * CFrame.Angles(0, -math.pi / 2, math.pi), Vector3.new(0.06, length, h), colors[2], M.Fabric, Kit.DETAIL)
		return
	end
	local n = #colors
	for i, color in colors do
		kit:Box(
			hang * CFrame.new(0, -length * (i - 0.5) / n, -h / 2),
			Vector3.new(0.06, length / n, h),
			color,
			M.Fabric,
			Kit.DETAIL
		)
	end
end

function Landmarks.Palazzo(ctx, parentKit)
	local kit = parentKit:Group("PalazzoDiCitta")
	local rng = ctx.Rng:Fork(301)
	local r = Plan.Palazzo
	local frame = CFrame.fromMatrix(Vector3.new(r.X0, ctx.G, r.Z0), Vector3.new(0, 0, 1), UP)
	local width = r.Z1 - r.Z0
	local style = {
		Wall = Palette.rgb(236, 206, 164),
		WallMat = M.Plaster,
		GroundWall = GOLD,
		GroundMat = M.Limestone,
		Trim = GOLD_TRIM,
		Plinth = Palette.Lava,
		Shutter = Palette.rgb(58, 84, 62),
		Door = Palette.rgb(72, 46, 32),
		Frame = Palette.rgb(238, 234, 224),
		Ornate = true,
		Quoins = false,
		BalconyChance = 0.45,
	}
	local _, height = arcadedPalazzo(ctx, kit, frame, width, r.X1 - r.X0, {
		Rng = rng,
		Style = style,
		Bays = 7,
		Floors = 2,
		FloorHeight = 12.5,
		BackKind = "Side",
		ShopChance = 0,
	})
	-- clock attic and bell cot
	local mid = width / 2
	box(kit, frame, mid - 8, mid + 8, height + 0.6, height + 8, -3, 0.2, GOLD, M.Limestone)
	box(kit, frame, mid - 8.6, mid + 8.6, height + 8, height + 8.8, -3.4, 0.8, GOLD_TRIM, M.Limestone, Kit.DECO)
	for _, side in { -1, 1 } do
		kit:Wedge(
			frame * CFrame.new(mid + side * 4, height + 10.3, -1.3) * CFrame.Angles(0, side * -math.pi / 2, 0),
			Vector3.new(2.6, 3, 8),
			GOLD_TRIM,
			M.Limestone,
			Kit.DECO
		)
	end
	kit:Cyl(frame * CFrame.new(mid, height + 4.4, 0.35) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 5, Palette.rgb(246, 242, 230), M.Marble, Kit.DECO)
	kit:Cyl(frame * CFrame.new(mid, height + 4.4, 0.25) * CFrame.Angles(0, math.pi / 2, 0), 0.2, 5.6, BRONZE, M.Metal, Kit.DETAIL)
	kit:Box(frame * CFrame.new(mid + 0.45, height + 4.4 - 0.6, 0.55) * CFrame.Angles(0, 0, math.rad(35)), Vector3.new(0.18, 1.5, 0.08), Palette.Iron, M.Metal, Kit.DETAIL)
	kit:Box(frame * CFrame.new(mid + 0.7, height + 4.4 - 0.15, 0.55) * CFrame.Angles(0, 0, math.rad(-60)), Vector3.new(0.14, 2, 0.08), Palette.Iron, M.Metal, Kit.DETAIL)
	local cot = frame * CFrame.new(mid, height + 8.8, -1.3)
	for _, side in { -1, 1 } do
		box(kit, cot, side * 2 - 0.5, side * 2 + 0.5, 0, 5, -0.5, 0.5, GOLD, M.Limestone)
	end
	box(kit, cot, -2.6, 2.6, 5, 5.8, -0.6, 0.6, GOLD_TRIM, M.Limestone, Kit.DECO)
	bell(kit, (cot * CFrame.new(0, 3, 0)).Position)
	-- flags over the central balcony
	local balcony = frame * CFrame.new(mid, 13.6, 1.4)
	flag(kit, (balcony * CFrame.new(-2.4, 0, 0)).Position, (balcony * CFrame.new(-3.8, 5.5, 2.6)).Position, {
		Palette.rgb(0, 140, 70),
		Palette.rgb(244, 244, 240),
		Palette.rgb(206, 40, 44),
	})
	flag(kit, (balcony * CFrame.new(0, 0, 0)).Position, (balcony * CFrame.new(0, 6, 2.8)).Position, {
		Palette.rgb(0, 51, 153),
	})
	flag(kit, (balcony * CFrame.new(2.4, 0, 0)).Position, (balcony * CFrame.new(3.8, 5.5, 2.6)).Position, {
		Palette.rgb(200, 36, 36),
		Palette.rgb(244, 196, 40),
	}, true)
	-- side and back walls, roof
	box(kit, frame, 0, width, 0, height, -(r.X1 - r.X0), -(r.X1 - r.X0) + 1, style.Wall, style.WallMat)
	return height
end

function Landmarks.CafeArcade(ctx, parentKit)
	local kit = parentKit:Group("PorticoDeiCaffe")
	local rng = ctx.Rng:Fork(302)
	local r = Plan.Arcade
	local frame = CFrame.fromMatrix(Vector3.new(r.X1, ctx.G, r.Z1), Vector3.new(0, 0, -1), UP)
	local width = r.Z1 - r.Z0
	local style = {
		Wall = Palette.rgb(232, 176, 150),
		WallMat = M.Plaster,
		GroundWall = Palette.rgb(222, 196, 156),
		GroundMat = M.Limestone,
		Trim = Palette.Stone,
		Plinth = Palette.Lava,
		Shutter = Palette.rgb(70, 96, 70),
		Door = Palette.rgb(90, 40, 34),
		Frame = Palette.WoodDark,
		Ornate = true,
		Quoins = true,
		BalconyChance = 0.35,
	}
	arcadedPalazzo(ctx, kit, frame, width, r.X1 - r.X0, {
		Rng = rng,
		Style = style,
		Bays = 6,
		Floors = 3,
		FloorHeight = 11,
		BackKind = "Piazza",
		ShopChance = 0.9,
	})
	box(kit, frame, 0, width, 0, 13 + 33, -(r.X1 - r.X0), -(r.X1 - r.X0) + 1, style.Wall, style.WallMat)
	-- café tables under and in front of the arcade
	local tables = 0
	for i = 1, 6 do
		local along = (i - 0.5) * width / 6
		for _, out in { -4.4, 5.5 } do
			if not (out > 0 and i % 2 == 0) then
				local p = (frame * CFrame.new(along, 0, out)).Position
				local seats = Props.CafeTable(kit, p, rng, out > 0, if out < 0 then Palette.rgb(236, 230, 214) else nil)
				for _, seat in seats do
					if rng:Chance(0.45) then
						table.insert(ctx.Info.Seats, seat)
					end
				end
				tables += 1
				ctx:Block(p, 3)
			end
		end
	end
end

function Landmarks.Build(ctx, parentKit)
	local kit = parentKit:Group("PiazzaDelDuomo")
	local rng = ctx.Rng:Fork(300)
	local G = ctx.G
	local p = Plan.Piazza

	Landmarks.Church(ctx, kit)
	Landmarks.Fountain(ctx, kit)
	Landmarks.Statue(ctx, kit, Vector3.new(54, G, -62), Vector3.new(-1, 0, 0))
	Landmarks.Market(ctx, kit, rng)
	Landmarks.Palazzo(ctx, kit)
	Landmarks.CafeArcade(ctx, kit)

	-- palms around the fountain, lamp posts on the corners, benches
	for _, offset in { Vector3.new(-17, 0, -17), Vector3.new(17, 0, -17), Vector3.new(-17, 0, 17), Vector3.new(17, 0, 17) } do
		local base = Vector3.new(Plan.Fountain.X, G, Plan.Fountain.Z) + offset
		kit:Box(CFrame.new(base + Vector3.new(0, 0.5, 0)), Vector3.new(4.4, 1, 4.4), GOLD_TRIM, M.Limestone)
		Props.Palm(kit, base + Vector3.new(0, 1, 0), rng)
		ctx:Block(base, 3)
	end
	for _, corner in { { p.X0 + 6, p.Z0 + 6 }, { p.X1 - 6, p.Z0 + 6 }, { p.X0 + 6, p.Z1 - 6 }, { p.X1 - 6, p.Z1 - 6 } } do
		Props.LampPost(ctx, kit, Vector3.new(corner[1], G, corner[2]), 4)
		ctx:Block(Vector3.new(corner[1], G, corner[2]), 1.5)
	end
	for _, b in {
		{ Vector3.new(-20, G, -26), 0 },
		{ Vector3.new(20, G, -26), 0 },
		{ Vector3.new(24, G, -58), math.pi / 2 },
		{ Vector3.new(-12, G, -92), math.pi },
		{ Vector3.new(12, G, -92), math.pi },
	} do
		local cf = CFrame.new(b[1]) * CFrame.Angles(0, b[2], 0)
		local seats = Props.Bench(kit, cf)
		for _, seat in seats do
			if rng:Chance(0.5) then
				table.insert(ctx.Info.Seats, seat)
			end
		end
		ctx:Block(b[1], 3.4)
	end

	-- Spawns: south end of the piazza, looking at the cathedral.
	for _, x in { -12, -4, 4, 12 } do
		local pos = Vector3.new(x, G, -30 + math.abs(x) * 0.2)
		local cf = CFrame.lookAt(pos, Vector3.new(0, G, -118))
		table.insert(ctx.Info.SpawnCFrames, cf)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "TownSpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(5, 0.2, 5)
		spawn.CFrame = cf * CFrame.new(0, 0.1, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.CanTouch = false
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = kit.Parent
	end

	-- Townsfolk chatting in pairs, and people leaning by the arcade.
	for _, spot in { Vector3.new(-8, G, -40), Vector3.new(30, G, -78), Vector3.new(40, G, -36), Vector3.new(-2, G, -86) } do
		local a = spot + Vector3.new(-1.6, 3, 0)
		local b = spot + Vector3.new(1.6, 3, 0.3)
		table.insert(ctx.Info.Chats, { CFrame.lookAt(a, b), CFrame.lookAt(b, a) })
		ctx:Block(spot, 2.5)
	end

	-- Intro shot: a slow sweep across the piazza towards the cathedral.
	ctx.Info.ShotsByName.Piazza = {
		CFrame.lookAt(Vector3.new(-34, G + 16, -22), Vector3.new(0, G + 26, -118)),
		CFrame.lookAt(Vector3.new(24, G + 11, -30), Vector3.new(0, G + 24, -118)),
	}
end

return Landmarks
