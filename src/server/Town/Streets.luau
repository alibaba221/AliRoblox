--[[
	Paving for streets, alleys, the piazza and the seafront. Rectangles are clipped against each
	other in priority order so no two paving slabs overlap (no z-fighting at intersections).
]]

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plan = require(script.Parent.Plan)

local Streets = {}

local M = Enum.Material

local STYLES = {
	Piazza = { Color = Palette.rgb(212, 198, 170), Material = M.Limestone },
	Main = { Color = Palette.rgb(200, 188, 164), Material = M.Pavement },
	Promenade = { Color = Palette.rgb(214, 202, 176), Material = M.Pavement },
	Side = { Color = Palette.rgb(136, 126, 114), Material = M.Cobblestone },
	Alley = { Color = Palette.rgb(118, 110, 100), Material = M.Cobblestone },
}
local PRIORITY = { Piazza = 1, Main = 2, Promenade = 3, Side = 4, Alley = 5 }

local function subtract(a, b)
	if a.X1 <= b.X0 or a.X0 >= b.X1 or a.Z1 <= b.Z0 or a.Z0 >= b.Z1 then
		return { a }
	end
	local out = {}
	if a.X0 < b.X0 then
		table.insert(out, { X0 = a.X0, X1 = b.X0, Z0 = a.Z0, Z1 = a.Z1 })
	end
	if a.X1 > b.X1 then
		table.insert(out, { X0 = b.X1, X1 = a.X1, Z0 = a.Z0, Z1 = a.Z1 })
	end
	local x0, x1 = math.max(a.X0, b.X0), math.min(a.X1, b.X1)
	if a.Z0 < b.Z0 then
		table.insert(out, { X0 = x0, X1 = x1, Z0 = a.Z0, Z1 = b.Z0 })
	end
	if a.Z1 > b.Z1 then
		table.insert(out, { X0 = x0, X1 = x1, Z0 = b.Z1, Z1 = a.Z1 })
	end
	return out
end

-- All paved rectangles, non-overlapping, each tagged with its style kind.
function Streets.Pieces()
	local sources = { { Rect = Plan.Piazza, Kind = "Piazza", Name = "Piazza del Duomo" } }
	for _, street in Plan.Streets do
		table.insert(sources, { Rect = street, Kind = street.Kind, Name = street.Name })
	end
	table.sort(sources, function(a, b)
		return PRIORITY[a.Kind] < PRIORITY[b.Kind]
	end)
	local placed = {}
	local pieces = {}
	for _, source in sources do
		local fragments = { { X0 = source.Rect.X0, X1 = source.Rect.X1, Z0 = source.Rect.Z0, Z1 = source.Rect.Z1 } }
		for _, other in placed do
			local next = {}
			for _, fragment in fragments do
				for _, rest in subtract(fragment, other) do
					if rest.X1 - rest.X0 > 0.05 and rest.Z1 - rest.Z0 > 0.05 then
						table.insert(next, rest)
					end
				end
			end
			fragments = next
		end
		for _, fragment in fragments do
			fragment.Kind = source.Kind
			fragment.Name = source.Name
			table.insert(pieces, fragment)
		end
		table.insert(placed, source.Rect)
	end
	return pieces
end

local function slab(kit, x0, x1, z0, z1, top, style, rng)
	kit:Box(
		CFrame.new((x0 + x1) / 2, top - 0.6, (z0 + z1) / 2),
		Vector3.new(x1 - x0, 1.2, z1 - z0),
		Palette.Vary(style.Color, rng, 0.015),
		style.Material
	)
end

local function stripe(kit, x0, x1, z0, z1, top, color)
	if x1 - x0 < 0.05 or z1 - z0 < 0.05 then
		return
	end
	kit:Box(CFrame.new((x0 + x1) / 2, top - 0.05, (z0 + z1) / 2), Vector3.new(x1 - x0, 0.2, z1 - z0), color, M.Slate, Kit.DETAIL)
end

function Streets.Build(ctx, parentKit)
	local kit = parentKit:Group("Streets")
	local rng = ctx.Rng:Fork(21)
	local G = ctx.G
	local lava = Palette.rgb(112, 106, 100)

	for _, piece in Streets.Pieces() do
		slab(kit, piece.X0, piece.X1, piece.Z0, piece.Z1, G, STYLES[piece.Kind], rng)
		ctx:Tick()
	end

	-- Lava-stone bands along the main street (like the old centres of Catania / Taormina).
	local roma
	for _, street in Plan.Streets do
		if street.Kind == "Main" then
			roma = street
		end
	end
	if roma then
		local inset = 2.4
		local skip = { { 58, 70 }, { 118, 130 } } -- don't paint across the side-street crossings
		local cuts = { roma.Z0 }
		for _, s in skip do
			table.insert(cuts, s[1])
			table.insert(cuts, s[2])
		end
		table.insert(cuts, roma.Z1)
		for i = 1, #cuts - 1, 2 do
			local z0, z1 = cuts[i], cuts[i + 1]
			stripe(kit, roma.X0 + inset, roma.X0 + inset + 0.9, z0, z1, G + 0.08, lava)
			stripe(kit, roma.X1 - inset - 0.9, roma.X1 - inset, z0, z1, G + 0.08, lava)
			stripe(kit, -0.35, 0.35, z0, z1, G + 0.08, lava)
		end
	end

	-- Piazza: a grid of lava bands framing large limestone fields.
	local p = Plan.Piazza
	local step = 16
	local x = p.X0 + 2
	while x <= p.X1 - 2 do
		stripe(kit, x - 0.28, x + 0.28, p.Z0 + 2, p.Z1 - 2, G + 0.08, lava)
		x += step
	end
	local z = p.Z0 + 2
	while z <= p.Z1 - 2 do
		stripe(kit, p.X0 + 2, p.X1 - 2, z - 0.28, z + 0.28, G + 0.08, lava)
		z += step
	end
	-- border
	stripe(kit, p.X0 + 1, p.X1 - 1, p.Z0 + 1, p.Z0 + 1.9, G + 0.08, lava)
	stripe(kit, p.X0 + 1, p.X1 - 1, p.Z1 - 1.9, p.Z1 - 1, G + 0.08, lava)
end

return Streets
