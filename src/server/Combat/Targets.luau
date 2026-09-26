--[[
	Shooting-range targets and ammo crates (server).

	* Bottles on the range fence shatter when hit; tin cans get knocked off their crates.
	  Both come back after a few seconds.
	* Ammo crates ("Take ammo" prompt) refill every gun's reserve ammo.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Targets = {}

local TAG = "SicilyTarget"
local BOTTLE_COLORS = { Color3.fromRGB(56, 110, 62), Color3.fromRGB(108, 70, 36), Color3.fromRGB(70, 118, 120) }
local RESPAWN = 6

local folder: Folder
local lastRefill = {} -- [Player] = clock

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	return p
end

local function spawnBottle(spot: CFrame, index: number)
	local color = BOTTLE_COLORS[(index - 1) % #BOTTLE_COLORS + 1]
	local model = Instance.new("Model")
	model.Name = "Bottle"
	local body = part("Body", Vector3.new(0.95, 0.42, 0.42), spot * CFrame.new(0, 0.48, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Glass, Enum.PartType.Cylinder)
	body.Transparency = 0.25
	body.Parent = model
	local neck = part("Neck", Vector3.new(0.45, 0.18, 0.18), spot * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Glass, Enum.PartType.Cylinder)
	neck.Transparency = 0.25
	neck.Parent = model
	model:SetAttribute("Kind", "Bottle")
	model:SetAttribute("Index", index)
	model:AddTag(TAG)
	model.Parent = folder
	return model
end

local function spawnCan(spot: CFrame, index: number)
	local model = Instance.new("Model")
	model.Name = "Can"
	local can = part("Can", Vector3.new(0.62, 0.42, 0.42), spot * CFrame.new(0, 0.31, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(176, 176, 172), Enum.Material.Metal, Enum.PartType.Cylinder)
	can.Parent = model
	local label = part("Label", Vector3.new(0.34, 0.44, 0.44), spot * CFrame.new(0, 0.31, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(196, 50, 44), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	label.CanQuery = false
	label.Parent = model
	model.PrimaryPart = can
	model:SetAttribute("Kind", "Can")
	model:SetAttribute("Index", index)
	model:AddTag(TAG)
	model.Parent = folder
	return model
end

local spots = { Bottle = {}, Can = {} }

local function respawn(kind: string, index: number)
	task.delay(RESPAWN, function()
		local spot = spots[kind][index]
		if spot then
			if kind == "Bottle" then
				spawnBottle(spot, index)
			else
				spawnCan(spot, index)
			end
		end
	end)
end

local function shatter(model: Model, from: Vector3)
	local body = model:FindFirstChild("Body") :: BasePart?
	local center = if body then body.Position else model:GetPivot().Position
	local color = if body then body.Color else Color3.new(0.3, 0.5, 0.3)
	local away = (center - from)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, -1)
	for i = 1, 7 do
		local shard = Instance.new("Part")
		shard.Name = "Shard"
		shard.Size = Vector3.new(0.12 + math.random() * 0.2, 0.05, 0.12 + math.random() * 0.2)
		shard.Color = color
		shard.Material = Enum.Material.Glass
		shard.Transparency = 0.2
		shard.CanCollide = true
		shard.CanQuery = false
		shard.CanTouch = false
		shard.Massless = false
		shard.CFrame = CFrame.new(center + Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5) * 0.5)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		shard.Parent = folder
		shard.AssemblyLinearVelocity = away * (8 + math.random() * 10) + Vector3.new((math.random() - 0.5) * 10, 6 + math.random() * 8, (math.random() - 0.5) * 10)
		shard.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
		Debris:AddItem(shard, 2.5 + i * 0.05)
	end
	model:Destroy()
end

local function knock(model: Model, from: Vector3)
	local can = model.PrimaryPart
	if not can then
		model:Destroy()
		return
	end
	local away = (can.Position - from)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, -1)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = p == can
			if p ~= can then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = can
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model:RemoveTag(TAG)
	can.AssemblyLinearVelocity = away * 26 + Vector3.new(0, 16, 0)
	can.AssemblyAngularVelocity = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))
	Debris:AddItem(model, 5)
end

function Targets.OnHit(instance: Instance, from: Vector3): boolean
	local model = instance:FindFirstAncestorOfClass("Model")
	if not model or not model:HasTag(TAG) then
		return false
	end
	local kind = model:GetAttribute("Kind")
	local index = model:GetAttribute("Index")
	if kind == "Bottle" then
		shatter(model, from)
	elseif kind == "Can" then
		knock(model, from)
	end
	if type(kind) == "string" and type(index) == "number" then
		respawn(kind, index)
	end
	return true
end

local function makeCrate(cf: CFrame, combat)
	local anchor = Instance.new("Part")
	anchor.Name = "AmmoCrate"
	anchor.Size = Vector3.new(2.2, 1.1, 1.4)
	anchor.CFrame = cf
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = folder
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take ammo"
	prompt.ObjectText = "Munizioni"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if os.clock() - (lastRefill[player] or 0) < 3 then
			return
		end
		lastRefill[player] = os.clock()
		combat.Refill(player)
	end)
end

function Targets.Start(townInfo, combat)
	folder = Instance.new("Folder")
	folder.Name = "SicilyRange"
	folder.Parent = Workspace
	if townInfo then
		for i, spot in townInfo.RangeBottles or {} do
			spots.Bottle[i] = spot
			spawnBottle(spot, i)
		end
		for i, spot in townInfo.RangeCans or {} do
			spots.Can[i] = spot
			spawnCan(spot, i)
		end
		for _, cf in townInfo.AmmoCrates or {} do
			makeCrate(cf, combat)
		end
	end
	combat.OnHit(function(instance, from)
		Targets.OnHit(instance, from)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRefill[player] = nil
	end)
end

Targets.Tag = TAG

return Targets
