--[[
	Builds one street facade of a Sicilian townhouse.

	Facade space: origin at the bottom-left corner as seen from the street, +X along the facade
	(to the viewer's right), +Y up, +Z out of the wall towards the street. The wall surface is z = 0.

	The wall is a 1.2-stud "skin" with real openings, so windows and doors have depth and cast
	shadows. A dark panel behind the skin reads as glass / dark interiors.
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Facade = {}

local M = Enum.Material
local SKIN = 1.2
local BACKING = 0.3

local SHOPS = {
	{ "PANIFICIO", "Bread" },
	{ "SALUMERIA", "Deli" },
	{ "TABACCHI", "Tabacchi" },
	{ "FARMACIA", "Farmacia" },
	{ "PASTICCERIA", "Sweets" },
	{ "TRATTORIA", "Food" },
	{ "BAR SPORT", "Bar" },
	{ "ALIMENTARI", "Grocer" },
	{ "MACELLERIA", "Butcher" },
	{ "GELATERIA", "Gelato" },
	{ "OSTERIA", "Food" },
	{ "FERRAMENTA", "Hardware" },
	{ "BARBIERE", "Barber" },
	{ "CAFFÈ", "Bar" },
	{ "PESCHERIA", "Fish" },
	{ "CARTOLERIA", "Paper" },
	{ "VINI E OLI", "Wine" },
	{ "PIZZERIA", "Food" },
}
Facade.ShopNames = SHOPS

local SIGN_BOARDS = {
	Color3.fromRGB(40, 62, 46),
	Color3.fromRGB(96, 30, 32),
	Color3.fromRGB(28, 40, 70),
	Color3.fromRGB(30, 28, 28),
	Color3.fromRGB(120, 86, 40),
}

-- Axis-aligned box in facade space.
local function box(kit, frame: CFrame, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material, flags)
	if x1 - x0 < 0.01 or y1 - y0 < 0.01 or z1 - z0 < 0.01 then
		return nil
	end
	return kit:Box(
		frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		color,
		material,
		flags
	)
end
Facade.Box = box

-- Wall skin for one horizontal band, with rectangular openings cut out.
local function skinBand(kit, frame, width, y0, y1, openings, color, material)
	table.sort(openings, function(a, b)
		return a.X0 < b.X0
	end)
	local z0, z1 = -SKIN, 0
	if #openings == 0 then
		box(kit, frame, 0, width, y0, y1, z0, z1, color, material)
		return
	end
	local uniform = true
	for i = 2, #openings do
		if math.abs(openings[i].Y0 - openings[1].Y0) > 1e-3 or math.abs(openings[i].Y1 - openings[1].Y1) > 1e-3 then
			uniform = false
		end
	end
	local x = 0
	if uniform then
		local oy0, oy1 = openings[1].Y0, openings[1].Y1
		box(kit, frame, 0, width, y0, oy0, z0, z1, color, material)
		box(kit, frame, 0, width, oy1, y1, z0, z1, color, material)
		for _, o in openings do
			box(kit, frame, x, o.X0, oy0, oy1, z0, z1, color, material)
			x = o.X1
		end
		box(kit, frame, x, width, oy0, oy1, z0, z1, color, material)
	else
		for _, o in openings do
			box(kit, frame, x, o.X0, y0, y1, z0, z1, color, material)
			box(kit, frame, o.X0, o.X1, y0, o.Y0, z0, z1, color, material)
			box(kit, frame, o.X0, o.X1, o.Y1, y1, z0, z1, color, material)
			x = o.X1
		end
		box(kit, frame, x, width, y0, y1, z0, z1, color, material)
	end
end

local function shutters(kit, frame, o, style, rng, forceClosed: boolean?)
	local w = o.X1 - o.X0
	local color = Palette.Vary(style.Shutter, rng, 0.03)
	local leaf = w / 2
	local mode = if forceClosed then 2 else rng:Int(1, 10)
	local flags = Kit.DECO
	-- 1-5 open against the wall, 6-8 closed, 9-10 half open
	if mode <= 5 then
		box(kit, frame, o.X0 - leaf - 0.05, o.X0 - 0.05, o.Y0, o.Y1, 0, 0.12, color, M.WoodPlanks, flags)
		box(kit, frame, o.X1 + 0.05, o.X1 + leaf + 0.05, o.Y0, o.Y1, 0, 0.12, color, M.WoodPlanks, flags)
		return "Open"
	elseif mode <= 8 then
		box(kit, frame, o.X0, o.X0 + leaf - 0.03, o.Y0, o.Y1, -0.42, -0.3, color, M.WoodPlanks, flags)
		box(kit, frame, o.X0 + leaf + 0.03, o.X1, o.Y0, o.Y1, -0.42, -0.3, color, M.WoodPlanks, flags)
		return "Closed"
	else
		box(kit, frame, o.X0 - leaf - 0.05, o.X0 - 0.05, o.Y0, o.Y1, 0, 0.12, color, M.WoodPlanks, flags)
		box(kit, frame, o.X0 + leaf + 0.03, o.X1, o.Y0, o.Y1, -0.42, -0.3, color, M.WoodPlanks, flags)
		return "Half"
	end
end

local function windowFrame(kit, frame, o, style, ornate: boolean, pediment: boolean)
	local w = o.X1 - o.X0
	local trim = style.Trim
	-- sill
	box(kit, frame, o.X0 - 0.45, o.X1 + 0.45, o.Y0 - 0.32, o.Y0, 0, 0.48, trim, M.Limestone, Kit.DECO)
	-- lintel
	box(kit, frame, o.X0 - 0.4, o.X1 + 0.4, o.Y1, o.Y1 + 0.5, 0, 0.26, trim, M.Limestone, Kit.DECO)
	if ornate then
		box(kit, frame, o.X0 - 0.42, o.X0, o.Y0, o.Y1, 0, 0.16, trim, M.Limestone, Kit.DETAIL)
		box(kit, frame, o.X1, o.X1 + 0.42, o.Y0, o.Y1, 0, 0.16, trim, M.Limestone, Kit.DETAIL)
		box(kit, frame, o.X0 - 0.7, o.X1 + 0.7, o.Y1 + 0.5, o.Y1 + 0.85, 0, 0.5, trim, M.Limestone, Kit.DECO)
		if pediment then
			local half = w / 2 + 0.7
			local cx = (o.X0 + o.X1) / 2
			local y = o.Y1 + 0.85 + 0.45
			kit:Wedge(
				frame * CFrame.new(cx - half / 2, y, 0.2) * CFrame.Angles(0, math.pi / 2, 0),
				Vector3.new(0.4, 0.9, half),
				trim,
				M.Limestone,
				Kit.DETAIL
			)
			kit:Wedge(
				frame * CFrame.new(cx + half / 2, y, 0.2) * CFrame.Angles(0, -math.pi / 2, 0),
				Vector3.new(0.4, 0.9, half),
				trim,
				M.Limestone,
				Kit.DETAIL
			)
		end
	end
	-- mullion (glazing bar)
	local cx = (o.X0 + o.X1) / 2
	box(kit, frame, cx - 0.07, cx + 0.07, o.Y0, o.Y1, -1.05, -0.93, style.Frame, M.Wood, Kit.DETAIL)
end

local function balcony(kit, frame, x0: number, x1: number, floorY: number, style, rng, corbelXs: { number })
	local trim = style.Trim
	local depth = 1.9
	local slabTop = floorY + 0.1
	box(kit, frame, x0, x1, slabTop - 0.45, slabTop, 0, depth, trim, M.Limestone, Kit.SOLID)
	for _, cx in corbelXs do
		kit:Wedge(
			frame * CFrame.new(cx, slabTop - 0.45 - 0.65, 0.8) * CFrame.Angles(math.pi, 0, 0),
			Vector3.new(0.45, 1.3, 1.6),
			trim,
			M.Limestone,
			Kit.DECO
		)
	end
	-- wrought-iron railing
	local iron = Palette.Iron
	local railTop = slabTop + 2.7
	local front = depth - 0.12
	box(kit, frame, x0 + 0.05, x1 - 0.05, railTop - 0.16, railTop, front - 0.08, front + 0.08, iron, M.Metal, Kit.DETAIL)
	box(kit, frame, x0 + 0.05, x1 - 0.05, slabTop + 0.2, slabTop + 0.34, front - 0.06, front + 0.06, iron, M.Metal, Kit.DETAIL)
	for _, side in { x0 + 0.12, x1 - 0.12 } do
		box(kit, frame, side - 0.08, side + 0.08, slabTop, railTop, front - 0.08, front + 0.08, iron, M.Metal, Kit.DETAIL)
		box(kit, frame, side - 0.06, side + 0.06, railTop - 0.14, railTop, 0, front, iron, M.Metal, Kit.DETAIL)
	end
	local span = x1 - x0 - 0.3
	local count = math.max(2, math.floor(span / 0.62))
	for i = 1, count - 1 do
		local x = x0 + 0.15 + span * i / count
		box(kit, frame, x - 0.045, x + 0.045, slabTop + 0.2, railTop - 0.1, front - 0.045, front + 0.045, iron, M.Metal, Kit.DETAIL)
	end
	-- geraniums
	if rng:Chance(0.55) then
		for _, px in { x0 + 0.55, x1 - 0.55 } do
			if rng:Chance(0.8) then
				local base = frame * CFrame.new(px, slabTop + 0.3, depth - 0.55)
				kit:Box(base, Vector3.new(0.6, 0.6, 0.6), Palette.Terracotta, M.Slate, Kit.DETAIL)
				kit:Ball(
					(base * CFrame.new(0, 0.6, 0)).Position,
					0.9,
					rng:Pick(Palette.Geranium),
					M.Grass,
					Kit.DETAIL
				)
			end
		end
	end
end

local function wallLamp(ctx, kit, frame, x: number, y: number)
	local lampKit, lamp = kit:Group("WallLamp")
	ctx:Tag(lamp, "SicilyLamp")
	local iron = Palette.Iron
	box(lampKit, frame, x - 0.08, x + 0.08, y + 0.85, y + 1.0, 0, 1.05, iron, M.Metal, Kit.DETAIL)
	box(lampKit, frame, x - 0.3, x + 0.3, y + 0.62, y + 0.78, 0.66, 1.26, iron, M.Metal, Kit.DETAIL)
	local bulb = box(lampKit, frame, x - 0.22, x + 0.22, y - 0.1, y + 0.62, 0.74, 1.18, Palette.Bulb, M.Neon, Kit.GLOW)
	box(lampKit, frame, x - 0.14, x + 0.14, y - 0.26, y - 0.1, 0.82, 1.1, iron, M.Metal, Kit.DETAIL)
	if bulb then
		lampKit:PointLight(bulb, Palette.LampLight, 18, 1.35, false)
	end
end

local function awning(kit, frame, x0: number, x1: number, top: number, rng)
	local depth = 3.1
	local tilt = math.rad(22)
	local run = depth * math.cos(tilt)
	local drop = depth * math.sin(tilt)
	local color = rng:Pick(Palette.Awnings)
	local striped = rng:Chance(0.45)
	local width = x1 - x0
	local strips = if striped then math.max(3, math.floor(width / 0.9)) else 1
	for i = 0, strips - 1 do
		local sx0 = x0 + width * i / strips
		local sx1 = x0 + width * (i + 1) / strips
		local c = if striped and i % 2 == 1 then Palette.Canvas else color
		kit:Box(
			frame * CFrame.new((sx0 + sx1) / 2, top - drop / 2, run / 2) * CFrame.Angles(tilt, 0, 0),
			Vector3.new(sx1 - sx0, 0.08, depth),
			c,
			M.Fabric,
			Kit.DECO
		)
		box(kit, frame, sx0, sx1, top - drop - 0.7, top - drop, run - 0.04, run + 0.04, c, M.Fabric, Kit.DECO)
	end
	-- iron arms
	for _, x in { x0 + 0.1, x1 - 0.1 } do
		kit:Beam(
			(frame * CFrame.new(x, top - 1.4, 0)).Position,
			(frame * CFrame.new(x, top - drop - 0.05, run)).Position,
			0.08,
			Palette.Iron,
			M.Metal
		)
	end
end

--[[
	spec = {
		Width, Height, FloorLines = {0, 12, 23, ...} (floor bottoms, facade space),
		Kind = "Main" | "Side" | "Piazza" | "Alley" | "Sea" | "Back",
		Style = { Wall, WallMat, GroundWall, GroundMat, Trim, Plinth, Shutter, Door, Frame, Ornate, BalconyChance },
		LeftCorner, RightCorner (exposed corners -> quoins), Rng, Ctx,
		NoGround = true to skip the ground floor (arcades build their own),
	}
	Returns { Shops = { {X, Name, Kind} }, Doors = { X } }
]]
function Facade.Build(kit, frame: CFrame, spec)
	local rng = spec.Rng
	local ctx = spec.Ctx
	local style = spec.Style
	local width = spec.Width
	local height = spec.Height
	local lines = spec.FloorLines
	local kind = spec.Kind
	local back = kind == "Back"
	local busy = kind == "Main" or kind == "Piazza" or kind == "Sea"
	local info = { Shops = {}, Doors = {} }

	-- Dark interior seen through every opening.
	box(kit, frame, 0.02, width - 0.02, 0.02, height - 0.02, -SKIN - BACKING, -SKIN, Palette.Window, M.SmoothPlastic, {
		Collide = true,
		Shadow = false,
		Reflectance = 0.06,
	})

	-- Bays
	local margin = if width > 12 then 2 else 1.3
	local bayTarget = if back then 9 else (spec.BayWidth or 7.4)
	local bays = math.max(1, math.floor((width - 2 * margin) / bayTarget + 0.3))
	local bayWidth = (width - 2 * margin) / bays
	local centers = {}
	for i = 1, bays do
		centers[i] = margin + (i - 0.5) * bayWidth
	end
	local winW = math.clamp(bayWidth - 2.6, 1.6, 3.3)
	local floorsCount = #lines

	-- Ground floor ---------------------------------------------------------------------------
	local groundTop = lines[2] or height
	local groundOpenings = {}
	if not spec.NoGround then
		local doorBay = rng:Int(1, bays)
		for i = 1, bays do
			local cx = centers[i]
			local t
			if back then
				t = if i == doorBay and rng:Chance(0.6) then "Door" elseif rng:Chance(0.55) then "SmallWindow" else "Blank"
			elseif i == doorBay then
				t = "Door"
			elseif rng:Chance(if busy then spec.ShopChance or 0.55 else 0.18) then
				t = "Shop"
			elseif rng:Chance(0.3) then
				t = "Garage"
			else
				t = "Window"
			end
			local o
			if t == "Door" then
				local w = math.min(3.8, bayWidth - 1.6)
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = 0, Y1 = math.min(8.4, groundTop - 2.6), Type = t }
			elseif t == "Shop" then
				local w = math.min(6.2, bayWidth - 1.2)
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = 0, Y1 = math.min(8.6, groundTop - 2.8), Type = t }
			elseif t == "Garage" then
				local w = math.min(5, bayWidth - 1.4)
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = 0, Y1 = math.min(7.8, groundTop - 3), Type = t }
			elseif t == "Window" then
				local w = math.min(3, bayWidth - 2.2)
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = 3.4, Y1 = math.min(8.2, groundTop - 2.8), Type = t }
			elseif t == "SmallWindow" then
				local w = math.min(2.2, bayWidth - 2.2)
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = 4.4, Y1 = 7.4, Type = t }
			end
			if o then
				table.insert(groundOpenings, o)
			end
		end
		local groundOpeningsCopy = table.clone(groundOpenings)
		skinBand(kit, frame, width, 0, groundTop, groundOpeningsCopy, style.GroundWall, style.GroundMat)

		for _, o in groundOpenings do
			local w = o.X1 - o.X0
			local cx = (o.X0 + o.X1) / 2
			if o.Type == "Door" then
				local door = Palette.Vary(style.Door, rng, 0.03)
				box(kit, frame, o.X0, cx - 0.03, 0, o.Y1, -0.82, -0.62, door, M.WoodPlanks)
				box(kit, frame, cx + 0.03, o.X1, 0, o.Y1, -0.82, -0.62, door, M.WoodPlanks)
				box(kit, frame, o.X0 - 0.5, o.X0, 0, o.Y1, 0, 0.2, style.Trim, M.Limestone, Kit.DECO)
				box(kit, frame, o.X1, o.X1 + 0.5, 0, o.Y1, 0, 0.2, style.Trim, M.Limestone, Kit.DECO)
				box(kit, frame, o.X0 - 0.6, o.X1 + 0.6, o.Y1, o.Y1 + 0.65, 0, 0.3, style.Trim, M.Limestone, Kit.DECO)
				if style.Ornate then
					box(kit, frame, cx - 0.35, cx + 0.35, o.Y1 - 0.2, o.Y1 + 0.9, 0, 0.42, style.Trim, M.Limestone, Kit.DETAIL)
				end
				box(kit, frame, o.X0 - 0.4, o.X1 + 0.4, 0, 0.22, 0, 0.7, Palette.StoneShadow, M.Limestone)
				table.insert(info.Doors, cx)
			elseif o.Type == "Shop" then
				local shop = rng:Pick(SHOPS)
				local warm = Palette.rgb(118, 88, 62)
				box(kit, frame, o.X0, o.X1, 0, o.Y1, -1.25, -1.15, warm, M.SmoothPlastic, Kit.DECO)
				local glass = box(kit, frame, o.X0 + 0.15, o.X1 - 0.15, 0.9, o.Y1 - 0.15, -0.62, -0.55, Palette.Glass, M.Glass, {
					Collide = true,
					Transparency = 0.55,
					Reflectance = 0.15,
				})
				local frameColor = style.Frame
				box(kit, frame, o.X0, o.X1, 0, 0.9, -0.7, -0.5, frameColor, M.Wood)
				box(kit, frame, o.X0, o.X1, o.Y1 - 0.15, o.Y1, -0.7, -0.5, frameColor, M.Wood, Kit.DETAIL)
				box(kit, frame, cx - 0.08, cx + 0.08, 0.9, o.Y1, -0.68, -0.52, frameColor, M.Wood, Kit.DETAIL)
				-- counter silhouette and goods
				box(kit, frame, o.X0 + 0.4, o.X1 - 0.4, 0, 2.4, -1.15, -0.95, Palette.WoodDark, M.Wood, Kit.DETAIL)
				if glass then
					kit:PointLight(glass, Palette.LampLight, 12, 0.9, false)
				end
				-- sign board
				local boardColor = rng:Pick(SIGN_BOARDS)
				local board = box(kit, frame, o.X0 - 0.3, o.X1 + 0.3, o.Y1 + 0.55, o.Y1 + 1.85, 0, 0.18, boardColor, M.Wood, Kit.DECO)
				if board then
					kit:Sign(board, Enum.NormalId.Back, shop[1], { Font = Enum.Font.Bodoni })
				end
				if rng:Chance(0.6) and o.Y1 + 2.4 < groundTop then
					awning(kit, frame, o.X0 - 0.2, o.X1 + 0.2, o.Y1 + 0.45, rng)
				end
				table.insert(info.Shops, { X = cx, Name = shop[1], Kind = shop[2], Width = w })
			elseif o.Type == "Garage" then
				local door = Palette.Vary(style.Door, rng, 0.05)
				box(kit, frame, o.X0, cx - 0.03, 0, o.Y1, -0.9, -0.7, door, M.WoodPlanks)
				box(kit, frame, cx + 0.03, o.X1, 0, o.Y1, -0.9, -0.7, door, M.WoodPlanks)
				box(kit, frame, o.X0 - 0.45, o.X1 + 0.45, o.Y1, o.Y1 + 0.55, 0, 0.28, style.Trim, M.Limestone, Kit.DECO)
			elseif o.Type == "Window" or o.Type == "SmallWindow" then
				windowFrame(kit, frame, o, style, false, false)
				-- iron grille
				local bars = math.max(2, math.floor(w / 0.7))
				for b = 1, bars - 1 do
					local x = o.X0 + w * b / bars
					box(kit, frame, x - 0.05, x + 0.05, o.Y0, o.Y1, -0.3, -0.2, Palette.Iron, M.Metal, Kit.DETAIL)
				end
				box(kit, frame, o.X0, o.X1, (o.Y0 + o.Y1) / 2 - 0.05, (o.Y0 + o.Y1) / 2 + 0.05, -0.3, -0.2, Palette.Iron, M.Metal, Kit.DETAIL)
			end
		end
		-- plinth (lava-stone base)
		box(kit, frame, 0, width, 0, 1.3, 0, 0.26, style.Plinth, M.Slate, Kit.DECO)
	end

	-- Upper floors ---------------------------------------------------------------------------
	local longBalconyFloor = if style.Ornate and bays >= 3 and rng:Chance(0.45) and floorsCount >= 3 then 2 else nil
	for f = 2, floorsCount do
		local y0 = lines[f]
		local y1 = if f < floorsCount then lines[f + 1] else height
		local floorH = y1 - y0
		local openings = {}
		local balconies = {}
		local nobile = f == 2
		for i = 1, bays do
			local cx = centers[i]
			if back and rng:Chance(0.25) then
				continue
			end
			local w = if back then math.min(winW, 2.4) else winW
			local hasBalcony = not back
				and (longBalconyFloor == f or rng:Chance((style.BalconyChance or 0.3) * (if nobile then 1.4 else 0.8)))
			local o
			if hasBalcony then
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = y0 + 0.15, Y1 = y0 + math.min(8.2, floorH - 2.3), Balcony = true }
				table.insert(balconies, o)
			elseif back then
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = y0 + 3.2, Y1 = y0 + math.min(6.8, floorH - 3) }
			else
				o = { X0 = cx - w / 2, X1 = cx + w / 2, Y0 = y0 + 2.3, Y1 = y0 + math.min(8.2, floorH - 2.3) }
			end
			table.insert(openings, o)
		end
		skinBand(kit, frame, width, y0, y1, table.clone(openings), style.Wall, style.WallMat)

		for _, o in openings do
			windowFrame(kit, frame, o, style, style.Ornate and nobile and not back, style.Ornate and nobile and rng:Chance(0.5))
			shutters(kit, frame, o, style, rng)
		end

		if longBalconyFloor == f and #balconies >= 2 then
			local first, last = balconies[1], balconies[#balconies]
			local corbels = {}
			for _, o in balconies do
				table.insert(corbels, o.X0 - 0.2)
				table.insert(corbels, o.X1 + 0.2)
			end
			balcony(kit, frame, first.X0 - 1.2, last.X1 + 1.2, y0, style, rng, corbels)
		else
			for _, o in balconies do
				balcony(kit, frame, o.X0 - 1.2, o.X1 + 1.2, y0, style, rng, { o.X0 - 0.5, o.X1 + 0.5 })
			end
		end

		-- string course at the floor line
		if not back then
			box(kit, frame, 0, width, y0 - 0.35, y0 + 0.05, 0, 0.28, style.Trim, M.Limestone, Kit.DECO)
		end
	end

	-- Crowning cornice
	local extendLeft = if spec.LeftCorner then 1.1 else 0
	local extendRight = if spec.RightCorner then 1.1 else 0
	box(kit, frame, -extendLeft * 0.6, width + extendRight * 0.6, height - 0.8, height, 0, 0.62, style.Trim, M.Limestone, Kit.DECO)
	if not back then
		box(kit, frame, -extendLeft, width + extendRight, height, height + 0.38, 0, 1.05, style.Trim, M.Limestone, Kit.DECO)
	end

	-- Quoins (rusticated corner stones)
	if style.Quoins and not back then
		for _, corner in { { spec.LeftCorner, 0, 1 }, { spec.RightCorner, width, -1 } } do
			if corner[1] then
				local x = corner[2]
				local dir = corner[3]
				local y = 1.3
				local i = if dir == 1 then 0 else 1
				while y + 1.9 < height - 0.9 do
					local len = if i % 2 == 0 then 1.9 else 1.1
					local xa = x - dir * 0.3
					local xb = x + dir * len
					box(kit, frame, math.min(xa, xb), math.max(xa, xb), y + 0.06, y + 1.9, 0, 0.3, style.Trim, M.Limestone, Kit.DETAIL)
					y += 1.96
					i += 1
				end
			end
		end
	elseif style.Ornate and not back then
		-- corner pilaster strips
		for _, x in { 0.5, width - 0.5 } do
			box(kit, frame, x - 0.5, x + 0.5, 1.3, height - 0.8, 0, 0.22, style.Trim, M.Limestone, Kit.DETAIL)
		end
	end

	-- Wall lanterns between bays on busy streets
	if not back and ctx and kind ~= "Alley" then
		local spacing = if busy then 17 else 26
		local lamps = math.floor(width / spacing + rng:Range(0, 0.8))
		for l = 1, lamps do
			local idx = math.clamp(math.floor(bays * l / (lamps + 1) + 0.5), 0, bays)
			local x = if idx <= 0 then margin * 0.5 elseif idx >= bays then width - margin * 0.5 else (centers[idx] + centers[idx + 1]) / 2
			wallLamp(ctx, kit, frame, x, math.min(9.3, groundTop - 2.2))
		end
	end

	return info
end

return Facade
