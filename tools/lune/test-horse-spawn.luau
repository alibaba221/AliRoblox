--[[
	lune run tools/lune/test-horse-spawn.luau <place.rbxl>

	Generates the town, then starts the real server horse module (ServerScriptService.SicilyServer
	.Horses) on it. Physics is stubbed: downward raycasts hit the terrain (from the same recipe the
	generator uses), water surfaces and the town's colliding parts. Checks that every herd and
	stable slot really puts a horse in the world, on dry ground, not on a roof or a tree, and
	reports how far each group is from where players spawn. The saddled horses in the piazza must
	be a few steps from the spawn, and a herd close enough to see from town.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Harness = require("./harness")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Enum = roblox.Enum

local placePath = process.args[1] or "build/SicilyDemo.rbxl"

-- Stubs ---------------------------------------------------------------------------------------------------
local function inertSignal()
	local signal = {}
	function signal:Connect()
		return { Connected = true, Disconnect = function() end }
	end
	signal.Once = signal.Connect
	return signal
end
for className, events in {
	RemoteEvent = { "OnServerEvent" },
	UnreliableRemoteEvent = { "OnServerEvent" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	RunService = { "Heartbeat" },
	ProximityPrompt = { "Triggered" },
} do
	for _, event in events do
		roblox.implementProperty(className, event, function()
			return inertSignal()
		end)
	end
end
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.clock()
end)
roblox.implementMethod("Players", "GetPlayers", function()
	return {}
end)
roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("PhysicsService", "IsCollisionGroupRegistered", function()
	return true
end)
roblox.implementMethod("PhysicsService", "GetRegisteredCollisionGroups", function()
	return { { name = "Default" } }
end)
for _, method in { "RegisterCollisionGroup", "CollisionGroupSetCollidable" } do
	roblox.implementMethod("PhysicsService", method, function() end)
end

-- The AI's first tick reads live part positions, which only exist in the engine: skip that warning.
Harness.OnWarn = function(...)
	local message = table.concat({ ... }, " ")
	if not (string.find(message, "Horse AI failed", 1, true) and string.find(message, "missing default value", 1, true)) then
		print("[warn]", ...)
	end
end

-- Setup: the real town ------------------------------------------------------------------------------------
local game, requireModule = Harness.load(placePath)
local server = game:GetService("ServerScriptService").SicilyServer
local Town = requireModule(server.Town)
local Plan = requireModule(server.Town.Plan)
local Config = requireModule(game:GetService("ReplicatedStorage").SicilyShared.Config)
local HorseRig = requireModule(game:GetService("ReplicatedStorage").SicilyShared.HorseRig)
local Workspace = game:GetService("Workspace")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local townModel, info = Town.Build({ Terrain = false, TerrainRecorder = {}, YieldEvery = 0 })
townModel.Parent = Workspace

-- Colliding parts, bucketed by 16-stud columns, for the downward raycasts.
local CELL = 16
local columns = {}
local function cellKey(x: number, z: number): string
	return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end
for _, part in townModel:GetDescendants() do
	if part:IsA("BasePart") and part.CanCollide then
		local cf, size = part.CFrame, part.Size
		-- the part's footprint (its bounding box on the ground)
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = cf:PointToWorldSpace(Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2))
					minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
					minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
				end
			end
		end
		for cx = math.floor(minX / CELL), math.floor(maxX / CELL) do
			for cz = math.floor(minZ / CELL), math.floor(maxZ / CELL) do
				local key = cx .. ":" .. cz
				columns[key] = columns[key] or {}
				table.insert(columns[key], part)
			end
		end
	end
end

-- Where a vertical line at (x, z) enters and leaves a part (world Y), or nil.
local function verticalSpan(part, x: number, z: number): (number?, number?)
	local cf, half = part.CFrame, part.Size / 2
	local origin = cf:PointToObjectSpace(Vector3.new(x, 0, z))
	local direction = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local t0, t1 = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local o, d, h = origin[axis], direction[axis], half[axis]
		if math.abs(d) < 1e-9 then
			if o < -h or o > h then
				return nil, nil
			end
		else
			local a, b = (-h - o) / d, (h - o) / d
			t0, t1 = math.max(t0, math.min(a, b)), math.min(t1, math.max(a, b))
		end
	end
	if t0 > t1 then
		return nil, nil
	end
	return t0, t1
end

local function waterSurface(x: number, z: number): number?
	if z >= 196 and math.abs(x) <= 900 then
		return 0
	end
	if x >= -197 and x <= -173 and z >= -140 and z <= 214 then
		return -12
	end
	return nil
end

local terrain = Workspace.Terrain
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
	if direction.Y > -0.9 * direction.Magnitude then
		return nil -- only straight-down rays are modelled
	end
	local x, z, top = origin.X, origin.Z, origin.Y
	local bottom = top + direction.Y
	local best, bestY, material = terrain, Plan.HeightAt(x, z), Enum.Material.Grass
	local water = waterSurface(x, z)
	if water and water > bestY and not (params and params.IgnoreWater) then
		bestY, material = water, Enum.Material.Water
	end
	local excluded = params and params.FilterDescendantsInstances or {}
	for _, part in columns[cellKey(x, z)] or {} do
		local enter, leave = verticalSpan(part, x, z)
		if leave and leave < top and leave > bestY then
			local skip = enter < top and leave > top -- rays don't hit a part they start inside
			for _, ancestor in excluded do
				if part:IsDescendantOf(ancestor) then
					skip = true
				end
			end
			if not skip then
				best, bestY, material = part, leave, part.Material
			end
		end
	end
	if bestY < bottom then
		return nil
	end
	return { Instance = best, Position = Vector3.new(x, bestY, z), Normal = Vector3.new(0, 1, 0), Material = material, Distance = top - bestY }
end)

-- Start the horses exactly like the server does ------------------------------------------------------------
local Horses = requireModule(server.Horses)
Horses.Start(info)

local folder = Workspace:FindFirstChild("SicilyHorses")
check(folder ~= nil, "horse folder created")
local horses = if folder then folder:GetChildren() else {}

local expectedWild = 0
for _, herd in Config.Horses.Herds do
	expectedWild += herd.Count
end
local wild, stable, hitched = 0, 0, 0
local spawns = info.SpawnCFrames
local spawnPoint = if spawns and spawns[1] then spawns[1].Position else Vector3.new(0, 0, -30)
local byGroup = {}
for _, horse in horses do
	local root = horse.PrimaryPart
	local position = root.CFrame.Position
	local isWild = horse:GetAttribute("Wild") == true
	local isHitched = horse:GetAttribute("Hitched") == true
	if isWild then
		wild += 1
	elseif isHitched then
		hitched += 1
	else
		stable += 1
	end
	-- standing on the ground, not in water, not on something tall
	local groundY = Plan.HeightAt(position.X, position.Z)
	local water = waterSurface(position.X, position.Z)
	check(not water or groundY > water, horse.Name .. " isn't standing in water")
	local standing = position.Y - HorseRig.Layout.RootHeight - 0.3
	local onTerrain = math.abs(standing - groundY) < 0.5
	local onPart = false
	for _, part in columns[cellKey(position.X, position.Z)] or {} do
		local _, leave = verticalSpan(part, position.X, position.Z)
		if leave and math.abs(leave - standing) < 0.5 and part.Size.Y < 3 then
			onPart = true -- a floor (stable boards, paving)
		end
	end
	check(onTerrain or onPart, ("%s stands on the ground (%.1f vs terrain %.1f)"):format(horse.Name, standing, groundY))
	check(horse:FindFirstChild("MountPrompt", true) ~= nil, horse.Name .. " has a mount prompt")
	local group = if isWild then "wild" elseif isHitched then "piazza" else "stable"
	local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(spawnPoint.X, 0, spawnPoint.Z)).Magnitude
	byGroup[group] = byGroup[group] or {}
	table.insert(byGroup[group], distance)
end
check(wild == expectedWild, ("every wild horse spawned (%d of %d)"):format(wild, expectedWild))
check(stable == Config.Horses.StableHorses, ("stable horses spawned (%d of %d)"):format(stable, Config.Horses.StableHorses))
check(hitched == Config.Horses.PiazzaHorses, ("piazza horses spawned (%d of %d)"):format(hitched, Config.Horses.PiazzaHorses))
table.sort(byGroup.piazza or {})
table.sort(byGroup.wild or {})
check(byGroup.piazza ~= nil and byGroup.piazza[#byGroup.piazza] < 60, "the piazza horses are a few steps from the spawn")
check(byGroup.wild ~= nil and byGroup.wild[1] < 175, "a wild herd grazes within sight of town")

for group, distances in byGroup do
	table.sort(distances)
	local list = {}
	for _, d in distances do
		table.insert(list, ("%.0f"):format(d))
	end
	print(("  %-6s horses, studs from the spawn: %s"):format(group, table.concat(list, ", ")))
end

-- Optional: <out-dir> gets a preview scene (the town plus every horse where it spawned).
local outDir = process.args[2]
if outDir then
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	fs.writeDir(outDir)
	local parts = {}
	for _, root in { townModel, folder } do
		for _, d in (root :: Instance):GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				local key = if d.ClassName == "Part" then d.Shape.Name else d.ClassName
				local mesh = d:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					key = "Mesh" .. mesh.MeshType.Name
				end
				local c = d.Color
				table.insert(parts, {
					k = key,
					s = { d.Size.X, d.Size.Y, d.Size.Z },
					cf = { d.CFrame:GetComponents() },
					c = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) },
					m = d.Material.Name,
					t = d.Transparency,
				})
			end
		end
	end
	local step, x0, x1, z0, z1 = 4, -560, 480, -600, 700
	local heights = {}
	local nx, nz = math.floor((x1 - x0) / step) + 1, math.floor((z1 - z0) / step) + 1
	for iz = 0, nz - 1 do
		for ix = 0, nx - 1 do
			table.insert(heights, math.floor(Plan.HeightAt(x0 + ix * step, z0 + iz * step) * 10 + 0.5) / 10)
		end
	end
	local json = serde.encode("json", {
		parts = parts,
		lights = {},
		terrain = { x0 = x0, z0 = z0, step = step, nx = nx, nz = nz, h = heights, balls = {} },
	})
	-- empty Lua tables encode as objects; the viewer wants arrays
	json = string.gsub(json, '"lights":{}', '"lights":[]')
	json = string.gsub(json, '"balls":{}', '"balls":[]')
	fs.writeFile(outDir .. "/town.json", json)
	print("Wrote " .. outDir .. "/town.json")
end

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
