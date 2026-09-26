--[[
	Master plan of Castelmare. Axes: +X = east, +Z = south (towards the sea), +Y = up.

	              castle hill (N)
	         ┌── Via Nord ───────────────┐
	         │  N1   ⛪ Duomo    N2       │
	  arcade ├──── Piazza del Duomo ─────┤ palazzo
	         │  A1   │Via│   A2          │
	         ├─ Via Garibaldi ───────────┤──── road → bridge → shrine → farm (W)
	         │  B1   │Roma│  B2          │
	         ├─ Corso Umberto ───────────┤
	         │  C1   │    │  C2          │
	         └──── Lungomare / belvedere ┘
	              harbour, pier, beach (S)
]]

local Plan = {}

local V = Vector3.new

Plan.G = 12 -- street level of the town
Plan.Land = 11.6 -- terrain surface around the town
Plan.Quay = 4 -- harbour quay level
Plan.SeaLevel = 0

-- Walkable paved areas (axis-aligned rectangles). Kind decides the paving style.
Plan.Streets = {
	{ Name = "Via Roma", X0 = -9, X1 = 9, Z0 = -20, Z1 = 176, Kind = "Main" },
	{ Name = "Via Maqueda", X0 = -78, X1 = -66, Z0 = -186, Z1 = 176, Kind = "Side" },
	{ Name = "Via Etnea", X0 = 66, X1 = 78, Z0 = -186, Z1 = 176, Kind = "Side" },
	{ Name = "Via Garibaldi", X0 = -112, X1 = 112, Z0 = 58, Z1 = 70, Kind = "Side" },
	{ Name = "Corso Umberto", X0 = -112, X1 = 112, Z0 = 118, Z1 = 130, Kind = "Side" },
	{ Name = "Via del Duomo", X0 = -112, X1 = -78, Z0 = -32, Z1 = -20, Kind = "Side" },
	{ Name = "Via dei Mille", X0 = 78, X1 = 112, Z0 = -32, Z1 = -20, Kind = "Side" },
	{ Name = "Via Nord", X0 = -78, X1 = 78, Z0 = -186, Z1 = -174, Kind = "Side" },
	{ Name = "Vicolo San Pietro", X0 = -34, X1 = -26, Z0 = -174, Z1 = -100, Kind = "Alley" },
	{ Name = "Vicolo San Paolo", X0 = 26, X1 = 34, Z0 = -174, Z1 = -100, Kind = "Alley" },
	{ Name = "Lungomare", X0 = -150, X1 = 200, Z0 = 176, Z1 = 194, Kind = "Promenade" },
}

Plan.Piazza = { X0 = -66, X1 = 66, Z0 = -100, Z1 = -20 }

-- Church (facade faces south onto the piazza).
Plan.Church = {
	FacadeZ = -118,
	StairsZ0 = -110, -- top of the stairs
	StairsZ1 = -100, -- bottom (piazza edge)
	Rise = 5,
	HalfWidth = 26, -- including towers
	NaveHalfWidth = 14,
	BackZ = -166,
}

-- Blocks of row houses. Sides = which sides are street facades (N = -Z, S = +Z, E = +X, W = -X).
-- Floors = {min, max}. Shops = chance of a ground-floor shop per bay on "Main"/piazza facades.
Plan.Blocks = {
	{ Name = "A1", X0 = -66, X1 = -9, Z0 = -20, Z1 = 58, Sides = { N = "Piazza", S = "Side", E = "Main", W = "Side" }, Floors = { 3, 4 } },
	{ Name = "A2", X0 = 9, X1 = 66, Z0 = -20, Z1 = 58, Sides = { N = "Piazza", S = "Side", E = "Side", W = "Main" }, Floors = { 3, 4 } },
	{ Name = "B1", X0 = -66, X1 = -9, Z0 = 70, Z1 = 118, Sides = { N = "Side", S = "Side", E = "Main", W = "Side" }, Floors = { 3, 4 } },
	{ Name = "B2", X0 = 9, X1 = 66, Z0 = 70, Z1 = 118, Sides = { N = "Side", S = "Side", E = "Side", W = "Main" }, Floors = { 3, 4 } },
	{ Name = "C1", X0 = -66, X1 = -9, Z0 = 130, Z1 = 176, Sides = { N = "Side", S = "Sea", E = "Main", W = "Side" }, Floors = { 3, 4 } },
	{ Name = "C2", X0 = 9, X1 = 66, Z0 = 130, Z1 = 176, Sides = { N = "Side", S = "Sea", E = "Side", W = "Main" }, Floors = { 3, 4 } },
	{ Name = "N1", X0 = -66, X1 = -34, Z0 = -174, Z1 = -100, Sides = { N = "Side", S = "Piazza", E = "Alley", W = "Side" }, Floors = { 3, 4 } },
	{ Name = "N2", X0 = 34, X1 = 66, Z0 = -174, Z1 = -100, Sides = { N = "Side", S = "Piazza", E = "Side", W = "Alley" }, Floors = { 3, 4 } },
	{ Name = "OW1", X0 = -104, X1 = -78, Z0 = -186, Z1 = -100, Sides = { E = "Side", N = "Back", W = "Back" }, Floors = { 3, 3 } },
	{ Name = "OW2", X0 = -104, X1 = -78, Z0 = -20, Z1 = 58, Sides = { E = "Side", N = "Side", S = "Side", W = "Back" }, Floors = { 3, 4 } },
	{ Name = "OW3", X0 = -104, X1 = -78, Z0 = 70, Z1 = 118, Sides = { E = "Side", N = "Side", S = "Side", W = "Back" }, Floors = { 2, 3 } },
	{ Name = "OW4", X0 = -104, X1 = -78, Z0 = 130, Z1 = 176, Sides = { E = "Side", N = "Side", S = "Sea", W = "Back" }, Floors = { 2, 3 } },
	{ Name = "OE1", X0 = 78, X1 = 104, Z0 = -186, Z1 = -100, Sides = { W = "Side", N = "Back", E = "Back" }, Floors = { 3, 3 } },
	{ Name = "OE2", X0 = 78, X1 = 104, Z0 = -20, Z1 = 58, Sides = { W = "Side", N = "Side", S = "Side", E = "Back" }, Floors = { 3, 4 } },
	{ Name = "OE3", X0 = 78, X1 = 104, Z0 = 70, Z1 = 118, Sides = { W = "Side", N = "Side", S = "Side", E = "Back" }, Floors = { 2, 3 } },
	{ Name = "OE4", X0 = 78, X1 = 104, Z0 = 130, Z1 = 176, Sides = { W = "Side", N = "Side", S = "Sea", E = "Back" }, Floors = { 2, 3 } },
}

-- Arcaded palazzo on the west side of the piazza (portico with cafés).
Plan.Arcade = { X0 = -104, X1 = -78, Z0 = -100, Z1 = -32 }
-- Town hall on the east side.
Plan.Palazzo = { X0 = 78, X1 = 120, Z0 = -100, Z1 = -32 }

Plan.Fountain = V(0, 0, -58)

Plan.Harbour = {
	SeawallZ = 194,
	QuayZ1 = 216,
	QuayX0 = -150,
	QuayX1 = 44,
	Pier = { X0 = -96, X1 = -84, Z1 = 330 },
	Beach = { X0 = 44, X1 = 206, Z0 = 196, Z1 = 266 },
}

Plan.Bridge = { X = -185, Z0 = 59, Z1 = 69, ArchRadius = 18, Springing = -12, HalfLength = 36 }
Plan.CountryRoad = { Z0 = 60, Z1 = 68, X0 = -300, X1 = -112 }
Plan.Shrine = V(-224, 0, 54)
Plan.Farm = V(-280, 0, 10)
-- Stable (saddled horses anyone can ride) and shooting range, either side of the road by the west gate.
Plan.Stable = { X0 = -146, X1 = -116, Z0 = 74, Z1 = 100 }
Plan.Range = { X0 = -146, X1 = -116, Z0 = 14, Z1 = 52 }
Plan.Castle = { Center = V(-140, 70, -330), HalfX = 34, HalfZ = 28 } -- courtyard floor at Center.Y - 2
Plan.Bounds = { X0 = -470, X1 = 430, Z0 = -540, Z1 = 600 }

-- The road up to the castle (x, z) — heights come from the terrain.
Plan.CastlePath = {
	Vector2.new(-72, -186),
	Vector2.new(-78, -204),
	Vector2.new(-98, -222),
	Vector2.new(-126, -234),
	Vector2.new(-156, -246),
	Vector2.new(-182, -266),
	Vector2.new(-188, -286),
	Vector2.new(-176, -298),
	Vector2.new(-158, -302),
}

--[[
	Terrain recipe, applied in order. Kinds:
	  Block {Min, Max}, Ball {Center, Radius}, Slope {X0,X1,Z0,Z1,Y0 (at Z0),Y1 (at Z1),Bottom}
	Material names map to Enum.Material; "Air" carves.
]]
Plan.Terrain = {
	{ Kind = "Block", Min = V(-520, -40, -560), Max = V(460, Plan.Land, 196), Material = "Grass" },
	-- the sea
	{ Kind = "Block", Min = V(-900, -80, 196), Max = V(900, 90, 1100), Material = "Air" },
	{ Kind = "Block", Min = V(-900, -80, 196), Max = V(900, -44, 1100), Material = "Sand" },
	{ Kind = "Block", Min = V(-900, -44, 196), Max = V(900, 0, 1100), Material = "Water" },
	{ Kind = "Slope", X0 = -900, X1 = 900, Z0 = 214, Z1 = 340, Y0 = -9, Y1 = -44, Bottom = -80, Material = "Sand" },
	{ Kind = "Block", Min = V(-900, -44, 196), Max = V(900, -9, 214), Material = "Sand" },
	-- rock under the quay and the pier
	{ Kind = "Block", Min = V(-162, -44, 194), Max = V(46, 2, 215), Material = "Rock" },
	-- beach
	{ Kind = "Slope", X0 = 44, X1 = 206, Z0 = 194, Z1 = 268, Y0 = 4, Y1 = -7, Bottom = -44, Material = "Sand" },
	-- hills and capes
	{ Kind = "Ball", Center = V(-140, -95, -330), Radius = 165, Material = "Grass" }, -- castle hill
	{ Kind = "Ball", Center = V(120, -130, -330), Radius = 170, Material = "Grass" },
	{ Kind = "Ball", Center = V(275, -150, -40), Radius = 200, Material = "Grass" },
	{ Kind = "Ball", Center = V(-430, -120, -20), Radius = 175, Material = "Grass" },
	{ Kind = "Ball", Center = V(270, -60, 262), Radius = 112, Material = "Rock" }, -- east cape
	{ Kind = "Ball", Center = V(-330, -85, 272), Radius = 112, Material = "Rock" }, -- west cape
	{ Kind = "Ball", Center = V(-20, -250, -560), Radius = 330, Material = "Rock" }, -- far mountains
	-- edge mountains so the map is enclosed by hills
	{ Kind = "Ball", Center = V(-640, -150, -120), Radius = 270, Material = "Grass" },
	{ Kind = "Ball", Center = V(-620, -150, 170), Radius = 250, Material = "Rock" },
	{ Kind = "Ball", Center = V(620, -150, -100), Radius = 270, Material = "Grass" },
	{ Kind = "Ball", Center = V(580, -130, 170), Radius = 230, Material = "Rock" },
	{ Kind = "Ball", Center = V(-420, -160, -640), Radius = 300, Material = "Grass" },
	{ Kind = "Ball", Center = V(380, -160, -640), Radius = 300, Material = "Grass" },
	-- castle courtyard: level the hilltop inside the walls
	{ Kind = "Block", Min = V(-174, 40, -358), Max = V(-106, 68, -302), Material = "Ground" },
	{ Kind = "Block", Min = V(-174, 68, -358), Max = V(-106, 100, -302), Material = "Air" },
	-- river valley west of town, crossed by the bridge
	{ Kind = "Valley", X = -185, Z0 = -140, Z1 = 196, CenterY = 22, Radius = 36, Step = 10 },
	{ Kind = "Block", Min = V(-197, -16, -140), Max = V(-173, -12, 214), Material = "Water" },
}

-- Surface height of the terrain at (x, z), mirroring Plan.Terrain. Water isn't solid.
function Plan.HeightAt(x: number, z: number): number
	local h = -80
	for _, f in Plan.Terrain do
		local kind = f.Kind
		if kind == "Block" then
			if x >= f.Min.X and x <= f.Max.X and z >= f.Min.Z and z <= f.Max.Z then
				if f.Material == "Air" then
					if h > f.Min.Y and h <= f.Max.Y + 1e-3 then
						h = f.Min.Y
					end
				elseif f.Material ~= "Water" then
					h = math.max(h, f.Max.Y)
				end
			end
		elseif kind == "Ball" then
			local dx, dz = x - f.Center.X, z - f.Center.Z
			local d2 = dx * dx + dz * dz
			local r2 = f.Radius * f.Radius
			if d2 < r2 then
				h = math.max(h, f.Center.Y + math.sqrt(r2 - d2))
			end
		elseif kind == "Slope" then
			if x >= f.X0 and x <= f.X1 and z >= f.Z0 and z <= f.Z1 then
				local t = (z - f.Z0) / (f.Z1 - f.Z0)
				h = math.max(h, f.Y0 + (f.Y1 - f.Y0) * t)
			end
		elseif kind == "Valley" then
			if z >= f.Z0 and z <= f.Z1 then
				local dx = math.abs(x - f.X)
				if dx < f.Radius then
					local bottom = f.CenterY - math.sqrt(f.Radius * f.Radius - dx * dx)
					h = math.min(h, bottom)
				end
			end
		end
	end
	return h
end

function Plan.InRect(rect, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x >= rect.X0 - m and x <= rect.X1 + m and z >= rect.Z0 - m and z <= rect.Z1 + m
end

-- True if (x, z) is inside the built-up town footprint (streets, blocks, piazza, church).
function Plan.InTown(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x >= -112 - m and x <= 122 + m and z >= -190 - m and z <= 196 + m
end

return Plan
