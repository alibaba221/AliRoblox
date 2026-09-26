--[[
	Row houses: splits each block edge into buildings of varied width, height, colour and
	ornament, builds their street facades, side walls and tiled or terrace roofs, and fills the
	inner courtyards.
]]

local Facade = require(script.Parent.Facade)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Buildings = {}

local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local DEPTH = 16

local SHOP_CHANCE = { Main = 0.6, Piazza = 0.55, Sea = 0.55, Side = 0.2, Alley = 0.08, Back = 0 }
local ORNATE_CHANCE = { Main = 0.55, Piazza = 0.8, Sea = 0.45, Side = 0.3, Alley = 0.15, Back = 0 }

function Buildings.MakeStyle(rng, ornateChance: number)
	local wall = Palette.Vary(rng:Pick(Palette.Walls), rng, 0.03)
	local stoneGround = rng:Chance(0.5)
	return {
		Wall = wall,
		WallMat = rng:Pick(Palette.WallMaterials),
		GroundWall = if stoneGround then Palette.Vary(Palette.StoneWarm, rng, 0.03) else Palette.Darken(wall, 0.05),
		GroundMat = if stoneGround then M.Limestone else M.Plaster,
		Trim = Palette.Vary(Palette.Stone, rng, 0.02),
		Plinth = if rng:Chance(0.6) then Palette.Lava else Palette.StoneShadow,
		Shutter = rng:Pick(Palette.Shutters),
		Door = rng:Pick(Palette.Doors),
		Frame = if rng:Chance(0.5) then Palette.rgb(238, 234, 224) else Palette.WoodDark,
		Ornate = rng:Chance(ornateChance),
		Quoins = rng:Chance(0.55),
		BalconyChance = rng:Range(0.15, 0.42),
		Roof = rng:Pick(Palette.Roofs),
	}
end

-- Facade frame for one side of an axis-aligned footprint.
local function sideFrame(b, side: string): (CFrame, number)
	local G = b.Base
	if side == "N" then
		return CFrame.fromMatrix(Vector3.new(b.X1, G, b.Z0), Vector3.new(-1, 0, 0), UP), b.X1 - b.X0
	elseif side == "S" then
		return CFrame.fromMatrix(Vector3.new(b.X0, G, b.Z1), Vector3.new(1, 0, 0), UP), b.X1 - b.X0
	elseif side == "E" then
		return CFrame.fromMatrix(Vector3.new(b.X1, G, b.Z1), Vector3.new(0, 0, -1), UP), b.Z1 - b.Z0
	else
		return CFrame.fromMatrix(Vector3.new(b.X0, G, b.Z0), Vector3.new(0, 0, 1), UP), b.Z1 - b.Z0
	end
end
Buildings.SideFrame = sideFrame

-- Which neighbouring sides meet each facade's left/right end.
local ENDS = {
	N = { Left = "E", Right = "W" },
	S = { Left = "W", Right = "E" },
	E = { Left = "S", Right = "N" },
	W = { Left = "N", Right = "S" },
}

local function roof(kit, b, height: number, style, rng)
	local G = b.Base
	local top = G + height
	local cx, cz = (b.X0 + b.X1) / 2, (b.Z0 + b.Z1) / 2
	local sx, sz = b.X1 - b.X0, b.Z1 - b.Z0

	if b.Roof == "Terrace" then
		kit:Box(CFrame.new(cx, top - 0.3, cz), Vector3.new(sx - 0.2, 0.6, sz - 0.2), Palette.Darken(style.Wall, 0.12), M.Concrete)
		local parapet = Palette.Darken(style.Wall, 0.02)
		local h = 1.5
		kit:Box(CFrame.new(cx, top + h / 2, b.Z0 + 0.3), Vector3.new(sx, h, 0.6), parapet, style.WallMat)
		kit:Box(CFrame.new(cx, top + h / 2, b.Z1 - 0.3), Vector3.new(sx, h, 0.6), parapet, style.WallMat)
		kit:Box(CFrame.new(b.X0 + 0.3, top + h / 2, cz), Vector3.new(0.6, h, sz - 1.2), parapet, style.WallMat)
		kit:Box(CFrame.new(b.X1 - 0.3, top + h / 2, cz), Vector3.new(0.6, h, sz - 1.2), parapet, style.WallMat)
		-- rooftop life: a stair hut, water tank or laundry
		if rng:Chance(0.45) and sx > 10 and sz > 10 then
			local hx, hz = cx + rng:Range(-sx / 5, sx / 5), cz + rng:Range(-sz / 5, sz / 5)
			kit:Box(CFrame.new(hx, top + 2.2, hz), Vector3.new(5, 4.4, 5), style.Wall, style.WallMat)
			kit:Box(CFrame.new(hx, top + 4.55, hz), Vector3.new(5.6, 0.3, 5.6), Palette.StoneShadow, M.Concrete, Kit.DECO)
		elseif rng:Chance(0.4) then
			kit:Cyl(CFrame.new(cx, top + 1, cz) * CFrame.Angles(0, 0, math.pi / 2), 2, 2.4, Palette.rgb(210, 210, 204), M.Plastic, Kit.DECO)
		end
		return
	end

	-- Low-pitched terracotta roof, ridge parallel to the main facade.
	local alongX = b.RidgeAxis == "X"
	local depth = if alongX then sz else sx
	local length = if alongX then sx else sz
	local rise = math.min(4.4, depth / 2 * 0.42)
	local overhang = 0.9
	local halfDepth = depth / 2 + overhang
	local color = Palette.Vary(style.Roof, rng, 0.03)
	for _, sign in { -1, 1 } do
		-- the half on the -X/-Z side slopes down towards -X/-Z; high edge at the ridge.
		local rotation
		local center
		if alongX then
			rotation = if sign < 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0)
			center = Vector3.new(cx, top + rise / 2, cz + sign * halfDepth / 2)
		else
			rotation = if sign < 0 then CFrame.Angles(0, math.pi / 2, 0) else CFrame.Angles(0, -math.pi / 2, 0)
			center = Vector3.new(cx + sign * halfDepth / 2, top + rise / 2, cz)
		end
		kit:Wedge(CFrame.new(center) * rotation, Vector3.new(length + 0.2, rise, halfDepth), color, M.ClayRoofTiles)
		-- gable end plates in wall colour
		for _, e in { -1, 1 } do
			local inward = sign * (halfDepth - overhang) / 2
			local plateCenter = if alongX
				then Vector3.new(cx + e * (length / 2 + 0.12), top + rise / 2, cz + inward)
				else Vector3.new(cx + inward, top + rise / 2, cz + e * (length / 2 + 0.12))
			kit:Wedge(CFrame.new(plateCenter) * rotation, Vector3.new(0.12, rise, halfDepth - overhang), style.Wall, style.WallMat, Kit.DECO)
		end
	end
	-- ridge tiles
	local ridgeSize = if alongX then Vector3.new(length + 0.3, 0.4, 0.7) else Vector3.new(0.7, 0.4, length + 0.3)
	kit:Box(CFrame.new(cx, top + rise + 0.1, cz), ridgeSize, Palette.Darken(color, 0.06), M.ClayRoofTiles, Kit.DECO)
	if rng:Chance(0.35) then
		local ox = if alongX then rng:Range(-length / 3, length / 3) else rng:Range(-1.5, 1.5)
		local oz = if alongX then rng:Range(-1.5, 1.5) else rng:Range(-length / 3, length / 3)
		kit:Box(CFrame.new(cx + ox, top + rise + 0.6, cz + oz), Vector3.new(1.4, 3.2, 1.4), style.Wall, style.WallMat, Kit.DECO)
		kit:Box(CFrame.new(cx + ox, top + rise + 2.3, cz + oz), Vector3.new(1.9, 0.3, 1.9), Palette.StoneShadow, M.Limestone, Kit.DECO)
	end
end

--[[
	b = { X0, X1, Z0, Z1, Base, Floors, Facades = { N = kind, ... }, RidgeAxis, Roof, Style, Rng, Name }
	Returns info { Shops = { {Position, Normal, Name, Kind} }, Doors = { {Position, Normal} } }
]]
function Buildings.Build(ctx, parentKit, b)
	local rng = b.Rng
	local style = b.Style
	local kit = parentKit:Group(b.Name or "Casa")
	local groundH = rng:Range(11.6, 12.8)
	local floorH = rng:Range(10.4, 11.4)
	local lines = { 0 }
	for f = 2, b.Floors do
		lines[f] = groundH + (f - 2) * floorH
	end
	local height = groundH + (b.Floors - 1) * floorH
	local G = b.Base
	local info = { Shops = {}, Doors = {} }

	for _, side in { "N", "S", "E", "W" } do
		local kind = b.Facades[side]
		local frame, width = sideFrame(b, side)
		if kind then
			local ends = ENDS[side]
			local facadeInfo = Facade.Build(kit, frame, {
				Width = width,
				Height = height,
				FloorLines = lines,
				Kind = kind,
				Style = style,
				ShopChance = SHOP_CHANCE[kind] or 0.2,
				LeftCorner = b.Facades[ends.Left] ~= nil,
				RightCorner = b.Facades[ends.Right] ~= nil,
				Rng = rng,
				Ctx = ctx,
			})
			for _, shop in facadeInfo.Shops do
				table.insert(info.Shops, {
					Position = (frame * CFrame.new(shop.X, 0, 0)).Position,
					Normal = frame.ZVector,
					Right = frame.XVector,
					Name = shop.Name,
					Kind = shop.Kind,
					Width = shop.Width,
					Street = kind,
				})
			end
			for _, x in facadeInfo.Doors do
				table.insert(info.Doors, { Position = (frame * CFrame.new(x, 0, 0)).Position, Normal = frame.ZVector, Street = kind })
			end
		else
			-- plain party/back wall
			kit:Box(frame * CFrame.new(width / 2, height / 2, -0.5), Vector3.new(width, height, 1), style.Wall, style.WallMat)
		end
	end

	roof(kit, b, height, style, rng)
	info.Height = height
	info.Top = G + height
	return info
end

-- Splits `length` into building widths between minWidth and maxWidth (ends at least endMin).
local function split(length: number, rng, minWidth: number, maxWidth: number, endMin: number): { number }
	local widths = {}
	local remaining = length
	local first = true
	while remaining > 1e-3 do
		local low = if first then math.max(minWidth, endMin) else minWidth
		local w = rng:Range(low, maxWidth)
		if remaining - w < math.max(minWidth, endMin) then
			if remaining <= maxWidth * 1.3 then
				w = remaining
			else
				w = remaining / 2
			end
		end
		table.insert(widths, w)
		remaining -= w
		first = false
	end
	return widths
end

local function floorsFor(block, rng, kind): number
	local low, high = block.Floors[1], block.Floors[2]
	if kind == "Piazza" or kind == "Main" then
		low = math.max(low, high - 1)
	end
	return rng:Int(low, high)
end

--[[
	Builds every building of a block. Returns aggregated info (shops, doors, courtyards).
]]
function Buildings.Block(ctx, parentKit, block, rng)
	local kit = parentKit:Group("Block_" .. block.Name)
	local sides = block.Sides
	local G = ctx.G
	local info = { Shops = {}, Doors = {}, Buildings = 0 }
	local width = block.X1 - block.X0
	local depth = block.Z1 - block.Z0

	local function add(result)
		for _, s in result.Shops do
			table.insert(info.Shops, s)
		end
		for _, d in result.Doors do
			table.insert(info.Doors, d)
		end
		info.Buildings += 1
	end

	local function build(footprint, facades, ridge, mainKind)
		local bRng = rng:Fork(info.Buildings + 1)
		local ornate = ORNATE_CHANCE[mainKind] or 0.3
		local style = Buildings.MakeStyle(bRng, ornate)
		local floors = floorsFor(block, bRng, mainKind)
		local cornerCount = 0
		for _ in facades do
			cornerCount += 1
		end
		add(Buildings.Build(ctx, kit, {
			Name = block.Name .. "_" .. (info.Buildings + 1),
			X0 = footprint[1],
			X1 = footprint[2],
			Z0 = footprint[3],
			Z1 = footprint[4],
			Base = G,
			Floors = floors,
			Facades = facades,
			RidgeAxis = ridge,
			Roof = if cornerCount >= 2 or bRng:Chance(0.35) then "Terrace" else "Tile",
			Style = style,
			Rng = bRng,
		}))
	end

	if width <= 30 then
		-- single row running north-south (outer blocks)
		local widths = split(depth, rng, 13, 22, 13)
		local z = block.Z0
		for i, w in widths do
			local facades = { E = sides.E, W = sides.W }
			if i == 1 then
				facades.N = sides.N
			end
			if i == #widths then
				facades.S = sides.S
			end
			build({ block.X0, block.X1, z, z + w }, facades, "Z", sides.E or sides.W)
			z += w
		end
		return info
	end

	local hasCourtyard = depth > DEPTH * 2 + 6
	-- North and south rows run the full width (corner buildings included).
	for _, rowSide in { "N", "S" } do
		local kind = sides[rowSide]
		if kind or hasCourtyard then
			local z0 = if rowSide == "N" then block.Z0 else block.Z1 - DEPTH
			local z1 = if rowSide == "N" then block.Z0 + DEPTH else block.Z1
			if not hasCourtyard then
				z0, z1 = block.Z0, block.Z1
			end
			local widths = split(width, rng, 12, 24, DEPTH + 2)
			local x = block.X0
			for i, w in widths do
				local facades = { [rowSide] = kind }
				if not hasCourtyard then
					facades.N, facades.S = sides.N, sides.S
				end
				if i == 1 then
					facades.W = sides.W
				end
				if i == #widths then
					facades.E = sides.E
				end
				build({ x, x + w, z0, z1 }, facades, "X", kind or "Side")
				x += w
			end
			if not hasCourtyard then
				break
			end
		end
	end

	if hasCourtyard then
		local z0, z1 = block.Z0 + DEPTH, block.Z1 - DEPTH
		for _, rowSide in { "W", "E" } do
			local kind = sides[rowSide]
			local x0 = if rowSide == "W" then block.X0 else block.X1 - DEPTH
			local widths = split(z1 - z0, rng, 12, 22, 12)
			local z = z0
			for _, w in widths do
				build({ x0, x0 + DEPTH, z, z + w }, { [rowSide] = kind }, "Z", kind or "Side")
				z += w
			end
		end
		-- courtyard: paving, a lemon tree, laundry
		local cx0, cx1 = block.X0 + DEPTH, block.X1 - DEPTH
		local center = Vector3.new((cx0 + cx1) / 2, G, (z0 + z1) / 2)
		kit:Box(
			CFrame.new(center - Vector3.new(0, 0.5, 0)),
			Vector3.new(cx1 - cx0, 1, z1 - z0),
			Palette.Vary(Palette.PavingLight, rng, 0.03),
			M.Pavement
		)
		info.Courtyard = { Center = center, X0 = cx0, X1 = cx1, Z0 = z0, Z1 = z1 }
	end
	return info
end

return Buildings
