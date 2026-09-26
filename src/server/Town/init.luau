--[[
	Castelmare — procedural Sicilian town generator.

	Runtime: SicilyServer calls Town.EnsureBuilt() at server start. If Workspace already contains
	a baked "SicilianTown" it is reused; otherwise the town is generated (deterministic per seed).

	Bake into your place (so you can see and hand-edit it in Studio). Command bar:
		require(game.ServerScriptService.SicilyServer.Town).Bake()
	then File > Save. Re-run to regenerate (it replaces the previous bake).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("SicilyShared"):WaitForChild("Config"))

local Buildings = require(script.Buildings)
local Kit = require(script.Kit)
local Landmarks = require(script.Landmarks)
local Landscape = require(script.Landscape)
local Harbour = require(script.Harbour)
local Countryside = require(script.Countryside)
local Nav = require(script.Nav)
local Plan = require(script.Plan)
local Props = require(script.Props)
local Rng = require(script.Rng)
local Streets = require(script.Streets)
local TerrainOps = require(script.TerrainOps)

local Town = {}
Town.ModelName = "SicilianTown"

local Context = {}
Context.__index = Context

function Context.new(options)
	local self = setmetatable({}, Context)
	self.G = Plan.G
	self.Seed = options.Seed
	self.Rng = Rng.new(options.Seed)
	self.Terrain = TerrainOps.new(options.Terrain, options.TerrainRecorder)
	self.Parts = 0
	self.LastYield = 0
	self.YieldEvery = options.YieldEvery or 350
	self.Info = {
		SpawnCFrames = {},
		Nav = { Nodes = {}, Edges = {} },
		Vendors = {},
		Seats = {},
		Chats = {},
		Leans = {},
		Fish = {},
		Shots = {},
		ShotsByName = {},
		Blocked = {}, -- { {Center = Vector3, Radius = number} } areas NPCs shouldn't path through
		Shops = {},
		Doors = {},
	}
	return self
end

function Context:Tick(weight: number?)
	self.Parts += weight or 1
	if self.YieldEvery > 0 and self.Parts - self.LastYield >= self.YieldEvery then
		self.LastYield = self.Parts
		task.wait()
	end
end

function Context:Tag(instance: Instance, tag: string)
	instance:AddTag(tag)
end

function Context:Block(center: Vector3, radius: number)
	table.insert(self.Info.Blocked, { Center = center, Radius = radius })
end

function Town.GetBuilt(): Model?
	local model = Workspace:FindFirstChild(Town.ModelName)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- Info <-> instances (so a baked town still knows its spawns, NPC routes and camera shots).
local LIST_KEYS = { "SpawnCFrames", "Vendors", "Seats", "Leans", "Fish", "Shots" }

function Town.WriteData(model: Model, info)
	local data = Instance.new("Configuration")
	data.Name = "TownData"
	for _, key in LIST_KEYS do
		local folder = Instance.new("Folder")
		folder.Name = key
		for i, cf in info[key] do
			local value = Instance.new("CFrameValue")
			value.Name = string.format("%03d", i)
			value.Value = cf
			value.Parent = folder
		end
		folder.Parent = data
	end
	local chats = Instance.new("Folder")
	chats.Name = "Chats"
	for i, pair in info.Chats do
		for j, cf in pair do
			local value = Instance.new("CFrameValue")
			value.Name = string.format("%03d_%d", i, j)
			value.Value = cf
			value.Parent = chats
		end
	end
	chats.Parent = data
	local nav = Instance.new("StringValue")
	nav.Name = "Nav"
	nav.Value = Nav.Encode(info.Nav)
	nav.Parent = data
	data.Parent = model
end

function Town.ReadData(model: Model)
	local info = {
		SpawnCFrames = {},
		Vendors = {},
		Seats = {},
		Leans = {},
		Fish = {},
		Shots = {},
		Chats = {},
		Nav = { Nodes = {}, Edges = {} },
	}
	local data = model:FindFirstChild("TownData")
	if not data then
		return info
	end
	for _, key in LIST_KEYS do
		local folder = data:FindFirstChild(key)
		if folder then
			local values = folder:GetChildren()
			table.sort(values, function(a, b)
				return a.Name < b.Name
			end)
			for _, value in values do
				if value:IsA("CFrameValue") then
					table.insert(info[key], value.Value)
				end
			end
		end
	end
	local chats = data:FindFirstChild("Chats")
	if chats then
		local pairsByIndex = {}
		for _, value in chats:GetChildren() do
			local index, which = string.match(value.Name, "^(%d+)_(%d)$")
			if index and value:IsA("CFrameValue") then
				local i = tonumber(index) :: number
				pairsByIndex[i] = pairsByIndex[i] or {}
				pairsByIndex[i][tonumber(which) :: number] = value.Value
			end
		end
		for _, pair in pairsByIndex do
			if pair[1] and pair[2] then
				table.insert(info.Chats, pair)
			end
		end
	end
	local nav = data:FindFirstChild("Nav")
	if nav and nav:IsA("StringValue") then
		info.Nav = Nav.Decode(nav.Value)
	end
	return info
end

--[[
	Town.Build({ Seed, Parent, Terrain = Terrain | false, TerrainRecorder, YieldEvery })
	Returns (model, info).
]]
function Town.Build(options: { [string]: any }?)
	local opts = options or {}
	local seed = opts.Seed or Config.Town.Seed
	local parent = opts.Parent or Workspace

	local existing = parent:FindFirstChild(Town.ModelName)
	if existing then
		existing:Destroy()
	end

	local terrain = nil
	if opts.Terrain ~= false then
		terrain = opts.Terrain or Workspace:FindFirstChildOfClass("Terrain")
	end
	local ctx = Context.new({
		Seed = seed,
		Terrain = terrain,
		TerrainRecorder = opts.TerrainRecorder,
		YieldEvery = opts.YieldEvery,
	})

	local model = Instance.new("Model")
	model.Name = Town.ModelName
	model:SetAttribute("SicilyTown", true)
	model:SetAttribute("Seed", seed)
	model.Parent = parent
	local kit = Kit.new(ctx, model)

	if Config.Town.ClearTerrain and terrain then
		ctx.Terrain:Clear()
	end
	Landscape.Build(ctx)
	Streets.Build(ctx, kit)
	for index, block in Plan.Blocks do
		local result = Buildings.Block(ctx, kit, block, ctx.Rng:Fork(100 + index))
		for _, shop in result.Shops do
			table.insert(ctx.Info.Shops, shop)
		end
		for _, door in result.Doors do
			table.insert(ctx.Info.Doors, door)
		end
		if result.Courtyard then
			Props.Courtyard(ctx, kit, result.Courtyard)
		end
	end
	Landmarks.Build(ctx, kit)
	Harbour.Build(ctx, kit)
	Countryside.Build(ctx, kit)
	Props.Build(ctx, kit)
	Nav.Build(ctx)

	-- Intro flyover order.
	for _, name in { "Harbour", "ViaRoma", "Piazza", "Castle" } do
		local shot = ctx.Info.ShotsByName[name]
		if shot then
			table.insert(ctx.Info.Shots, shot[1])
			table.insert(ctx.Info.Shots, shot[2])
		end
	end

	Town.WriteData(model, ctx.Info)
	model:SetAttribute("Parts", ctx.Parts)
	return model, ctx.Info
end

-- Publishes what clients need (intro camera shots) and flags the town as ready.
function Town.Publish(info)
	local folder = ReplicatedStorage:FindFirstChild("SicilyTownData")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SicilyTownData"
		folder.Parent = ReplicatedStorage
	end
	local shots = folder:FindFirstChild("Shots")
	if shots then
		shots:Destroy()
	end
	shots = Instance.new("Folder")
	shots.Name = "Shots"
	for i = 1, #info.Shots, 2 do
		local index = (i + 1) / 2
		for j, suffix in { "A", "B" } do
			local cf = info.Shots[i + j - 1]
			if cf then
				local value = Instance.new("CFrameValue")
				value.Name = string.format("%02d_%s", index, suffix)
				value.Value = cf
				value.Parent = shots
			end
		end
	end
	shots.Parent = folder
	folder:SetAttribute("Ready", true)
end

local function hideLegacyMap()
	local names = Config.Town.HideOnBuild
	if #names == 0 then
		return
	end
	local stash = ServerStorage:FindFirstChild("SicilyHiddenMap") or Instance.new("Folder")
	stash.Name = "SicilyHiddenMap"
	stash.Parent = ServerStorage
	for _, name in names do
		local old = Workspace:FindFirstChild(name)
		if old then
			old.Parent = stash
		end
	end
end

-- Server entry: reuse a baked town or generate one. Returns info (with .Model).
function Town.EnsureBuilt()
	local model = Town.GetBuilt()
	local info
	if model then
		info = Town.ReadData(model)
	else
		hideLegacyMap()
		model, info = Town.Build()
	end
	info.Model = model
	Town.Publish(info)
	return info
end

-- Edit-mode bake from the command bar.
function Town.Bake(options: { [string]: any }?)
	local startedAt = os.clock()
	local model = Town.Build(options)
	local ok, err = pcall(function()
		local lighting = require(script.Parent.LightingPreset)
		lighting.Apply(Config.Lighting.Preset)
	end)
	if not ok then
		warn("[Sicily] Lighting not applied during bake: " .. tostring(err))
	end
	print(
		("[Sicily] Baked %s: %d parts in %.1fs. Save the place to keep it."):format(
			Config.Town.Name,
			model:GetAttribute("Parts") or 0,
			os.clock() - startedAt
		)
	)
	return model
end

return Town
