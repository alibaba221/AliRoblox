--[[
	lune run tools/lune/build-town.luau <place.rbxl> <out-dir>

	Generates the town offline with the real generator code, prints stats, and writes:
	  <out-dir>/town.json       parts, lights and a terrain heightmap for the preview renderer
	  <out-dir>/SicilianTown.rbxm  the generated parts as a model file
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = require("./harness")

local placePath = process.args[1] or "build/place.rbxl"
local outDir = process.args[2] or "tools/preview/out"
fs.writeDir(outDir)

local game, requireModule = Harness.load(placePath)
local Town = requireModule(game:GetService("ServerScriptService").SicilyServer.Town)
local Plan = requireModule(game:GetService("ServerScriptService").SicilyServer.Town.Plan)

local started = os.clock()
local terrainOps = {}
local model, info = Town.Build({ Terrain = false, TerrainRecorder = terrainOps, YieldEvery = 0 })
print(("Built in %.2fs"):format(os.clock() - started))

local classes, materials, parts, lights, surfaceGuis = {}, {}, {}, {}, 0
local instances = 0
for _, d in model:GetDescendants() do
	instances += 1
	if d:IsA("BasePart") then
		local key = d.ClassName
		if d.ClassName == "Part" then
			key = d.Shape.Name
		end
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			key = "Mesh" .. mesh.MeshType.Name
		end
		classes[key] = (classes[key] or 0) + 1
		materials[d.Material.Name] = (materials[d.Material.Name] or 0) + 1
		local c = d.Color
		table.insert(parts, {
			k = key,
			s = { d.Size.X, d.Size.Y, d.Size.Z },
			cf = { d.CFrame:GetComponents() },
			c = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) },
			m = d.Material.Name,
			t = d.Transparency,
			r = d.Reflectance,
			cc = d.CanCollide,
		})
	elseif d:IsA("PointLight") or d:IsA("SpotLight") then
		local p = d.Parent
		if p and p:IsA("BasePart") then
			local pos = p.CFrame.Position
			table.insert(lights, { p = { pos.X, pos.Y, pos.Z }, r = d.Range, b = d.Brightness, c = { d.Color.R, d.Color.G, d.Color.B } })
		end
	elseif d:IsA("SurfaceGui") then
		surfaceGuis += 1
	end
end

-- Terrain heightmap from the same recipe the generator uses.
local step = 4
local x0, x1, z0, z1 = -560, 480, -600, 700
local heights = {}
local nx, nz = math.floor((x1 - x0) / step) + 1, math.floor((z1 - z0) / step) + 1
for iz = 0, nz - 1 do
	for ix = 0, nx - 1 do
		table.insert(heights, math.floor(Plan.HeightAt(x0 + ix * step, z0 + iz * step) * 10 + 0.5) / 10)
	end
end

local balls = {}
for _, op in terrainOps do
	if op.Kind == "Ball" and op.Material.Name ~= "Air" and op.Radius < 20 then
		table.insert(balls, { op.Center.X, op.Center.Y, op.Center.Z, op.Radius, op.Material.Name })
	end
end

local function sortedCounts(t)
	local list = {}
	for k, v in t do
		table.insert(list, { k, v })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local out = {}
	for _, e in list do
		table.insert(out, e[1] .. "=" .. e[2])
	end
	return table.concat(out, "  ")
end

print(("Parts: %d   Instances: %d   Lights: %d   SurfaceGuis: %d   Terrain ops: %d"):format(#parts, instances, #lights, surfaceGuis, #terrainOps))
print("Shapes:    " .. sortedCounts(classes))
print("Materials: " .. sortedCounts(materials))
print(("Spawns: %d  Nav nodes: %d  Vendors: %d  Seats: %d  Chats: %d  Leans: %d  Fish: %d  Shots: %d  Shops: %d"):format(
	#info.SpawnCFrames, #info.Nav.Nodes, #info.Vendors, #info.Seats, #info.Chats, #info.Leans, #info.Fish, #info.Shots, #info.Shops
))

-- A baked town must reproduce the same data when read back (spawns, NPC spots, routes, shots).
local readBack = Town.ReadData(model)
local function same(key)
	local a, b = #info[key], #readBack[key]
	assert(a == b, ("baked data mismatch for %s: %d vs %d"):format(key, a, b))
end
for _, key in { "SpawnCFrames", "Vendors", "Seats", "Leans", "Fish", "Shots", "Chats", "StableSlots", "HitchSlots", "RangeBottles", "AmmoCrates" } do
	same(key)
end
assert(#readBack.Nav.Nodes == #info.Nav.Nodes, "nav nodes round-trip")
local edgesA, edgesB = 0, 0
for i in info.Nav.Edges do
	edgesA += #info.Nav.Edges[i]
	edgesB += #(readBack.Nav.Edges[i] or {})
end
assert(edgesA == edgesB, "nav edges round-trip")
Town.Publish(info)
local shotsFolder = game:GetService("ReplicatedStorage").SicilyTownData.Shots
assert(#shotsFolder:GetChildren() == #info.Shots, "published intro shots")
assert(shotsFolder:FindFirstChild("01_A") and shotsFolder:FindFirstChild("04_B"), "shot naming")
print(("Baked-town round trip OK (%d nav edges, %d shots published)"):format(edgesA / 2, #info.Shots))

local navNodes = {}
for _, n in info.Nav.Nodes do
	table.insert(navNodes, { n.X, n.Y, n.Z })
end
local navEdges = {}
for i, list in info.Nav.Edges do
	for _, j in list do
		if j > i then
			table.insert(navEdges, { i, j })
		end
	end
end
local shots = {}
for _, cf in info.Shots do
	table.insert(shots, { cf:GetComponents() })
end

fs.writeFile(outDir .. "/town.json", serde.encode("json", {
	parts = parts,
	lights = lights,
	terrain = { x0 = x0, z0 = z0, step = step, nx = nx, nz = nz, h = heights, balls = balls },
	nav = { nodes = navNodes, edges = navEdges },
	shots = shots,
}))
fs.writeFile(outDir .. "/SicilianTown.rbxm", roblox.serializeModel({ model }))
print("Wrote " .. outDir .. "/town.json and SicilianTown.rbxm")
