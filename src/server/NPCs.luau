--[[
	Townsfolk and NPC conversion.

	* Every existing humanoid NPC in Workspace (and any spawned later) is rebuilt as a blocky R6
	  in place (see RigConverter). Tag an NPC "KeepRig" to skip it.
	* Spawns Castelmare's townsfolk: people strolling the streets, market vendors, café regulars,
	  neighbours chatting, fishermen on the pier. All blocky R6 with Sicilian outfits built from
	  parts (flat caps, fedoras, headscarves, aprons), animated by the client-side animator.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local R6 = require(Shared:WaitForChild("R6"))
local Ragdoll = require(script.Parent.Ragdoll)
local RigConverter = require(script.Parent.RigConverter)

local NPCs = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local SKIN = { rgb(236, 188, 150), rgb(216, 162, 122), rgb(198, 142, 106), rgb(242, 204, 170), rgb(176, 124, 92) }
local M = Enum.Material

local OUTFITS = {
	{ Name = "Pescatore", Torso = rgb(36, 56, 96), Legs = rgb(72, 72, 76), Hat = "Coppola", HatColor = rgb(92, 84, 76) },
	{ Name = "Pescatore", Torso = rgb(232, 230, 222), Legs = rgb(44, 58, 90), Hat = "Coppola", HatColor = rgb(60, 60, 64), Stripes = true },
	{ Name = "Nonna", Torso = rgb(30, 30, 34), Legs = rgb(30, 30, 34), Hat = "Scarf", HatColor = rgb(24, 24, 28), Skirt = rgb(30, 30, 34) },
	{ Name = "Signore", Torso = rgb(120, 92, 64), Legs = rgb(96, 74, 54), Hat = "Fedora", HatColor = rgb(64, 52, 42), Mustache = true },
	{ Name = "Signore", Torso = rgb(214, 208, 190), Legs = rgb(110, 104, 94), Hat = "Coppola", HatColor = rgb(120, 110, 96), Mustache = true },
	{ Name = "Signora", Torso = rgb(170, 44, 52), Legs = rgb(236, 188, 150), Hair = rgb(46, 32, 24), Skirt = rgb(150, 36, 46) },
	{ Name = "Ragazza", Torso = rgb(236, 196, 84), Legs = rgb(236, 188, 150), Hair = rgb(92, 60, 36), Skirt = rgb(232, 232, 226) },
	{ Name = "Ragazzo", Torso = rgb(96, 150, 200), Legs = rgb(52, 60, 80) },
	{ Name = "Padre", Torso = rgb(22, 22, 26), Legs = rgb(22, 22, 26), Hat = "Saturno", HatColor = rgb(20, 20, 24), Skirt = rgb(22, 22, 26) },
	{ Name = "Turista", Torso = rgb(240, 240, 236), Legs = rgb(206, 190, 150), Hat = "Straw", HatColor = rgb(222, 198, 132) },
}
local VENDOR = { Name = "Venditore", Torso = rgb(238, 234, 224), Legs = rgb(58, 60, 70), Hat = "Coppola", HatColor = rgb(80, 72, 64), Apron = true, Mustache = true }
local FISHER = OUTFITS[1]

local function prop(model, part, offset, size, color, material, className, shape)
	return R6.AttachProp(model, part, offset, {
		Size = size,
		Color = color,
		Material = material or M.SmoothPlastic,
		ClassName = className,
		Shape = shape,
	})
end

local function dress(model: Model, outfit)
	if outfit.Hat == "Coppola" then
		prop(model, "Head", CFrame.new(0, 0.72, 0.04), Vector3.new(1.36, 0.34, 1.42), outfit.HatColor, M.Fabric)
		prop(model, "Head", CFrame.new(0, 0.6, -0.8) * CFrame.Angles(math.rad(-8), 0, 0), Vector3.new(1.3, 0.1, 0.5), outfit.HatColor, M.Fabric)
	elseif outfit.Hat == "Fedora" then
		prop(model, "Head", CFrame.new(0, 0.62, 0), Vector3.new(2, 0.1, 2), outfit.HatColor, M.Fabric)
		prop(model, "Head", CFrame.new(0, 0.98, 0), Vector3.new(1.2, 0.72, 1.2), outfit.HatColor, M.Fabric)
		prop(model, "Head", CFrame.new(0, 0.74, 0), Vector3.new(1.24, 0.16, 1.24), rgb(24, 22, 22), M.Fabric)
	elseif outfit.Hat == "Scarf" then
		prop(model, "Head", CFrame.new(0, 0.42, 0.1), Vector3.new(1.46, 0.72, 1.44), outfit.HatColor, M.Fabric)
		prop(model, "Head", CFrame.new(0, -0.2, 0.52), Vector3.new(1.3, 0.8, 0.3), outfit.HatColor, M.Fabric)
	elseif outfit.Hat == "Saturno" then
		prop(model, "Head", CFrame.new(0, 0.66, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.12, 2.3, 2.3), outfit.HatColor, M.Fabric, "Part", Enum.PartType.Cylinder)
		prop(model, "Head", CFrame.new(0, 0.8, 0), Vector3.new(1.1, 1.1, 1.1), outfit.HatColor, M.Fabric, "Part", Enum.PartType.Ball)
	elseif outfit.Hat == "Straw" then
		prop(model, "Head", CFrame.new(0, 0.64, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.1, 2.5, 2.5), outfit.HatColor, M.Fabric, "Part", Enum.PartType.Cylinder)
		prop(model, "Head", CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.5, 1.3, 1.3), outfit.HatColor, M.Fabric, "Part", Enum.PartType.Cylinder)
	end
	if outfit.Hair then
		prop(model, "Head", CFrame.new(0, 0.62, 0.06), Vector3.new(1.34, 0.3, 1.36), outfit.Hair, M.SmoothPlastic)
		prop(model, "Head", CFrame.new(0, 0.05, 0.5), Vector3.new(1.34, 1.2, 0.42), outfit.Hair, M.SmoothPlastic)
	end
	if outfit.Mustache then
		prop(model, "Head", CFrame.new(0, -0.14, -0.62), Vector3.new(0.7, 0.14, 0.1), rgb(40, 32, 28), M.SmoothPlastic)
	end
	if outfit.Apron then
		prop(model, "Torso", CFrame.new(0, -0.35, -0.54), Vector3.new(1.6, 1.9, 0.08), rgb(246, 244, 238), M.Fabric)
	end
	if outfit.Stripes then
		for i = 0, 2 do
			prop(model, "Torso", CFrame.new(0, 0.6 - i * 0.55, -0.51), Vector3.new(2.02, 0.16, 0.04), rgb(36, 56, 110), M.Fabric)
		end
	end
	if outfit.Skirt then
		prop(model, "Torso", CFrame.new(0, -1.45, 0), Vector3.new(2.2, 1.6, 1.3), outfit.Skirt, M.Fabric)
	end
end

local function makeNPC(parent: Instance, outfit, rng: Random, rootCFrame: CFrame, anchored: boolean): (Model, Humanoid)
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local model = R6.Build({
		Name = outfit.Name,
		CFrame = rootCFrame,
		Anchored = anchored,
		BodyColors = { Head = skin, Arms = skin, Torso = outfit.Torso, Legs = outfit.Legs },
	})
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = rng:NextNumber(5.2, 7.4)
	humanoid.BreakJointsOnDeath = not Config.Characters.Ragdoll
	dress(model, outfit)
	model:SetAttribute("Townsfolk", true)
	model:AddTag(R6.Tag)
	model.Parent = parent
	if not anchored then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	if Config.Characters.Ragdoll then
		humanoid.Died:Connect(function()
			Ragdoll.Apply(model)
			task.delay(12, function()
				model:Destroy()
			end)
		end)
	end
	return model, humanoid
end

local function moveTo(humanoid: Humanoid, target: Vector3, timeout: number): boolean
	local done, reached = false, false
	local connection = humanoid.MoveToFinished:Connect(function(ok)
		done, reached = true, ok
	end)
	humanoid:MoveTo(target)
	local elapsed = 0
	while not done and elapsed < timeout and humanoid.Parent do
		elapsed += task.wait(0.25)
	end
	connection:Disconnect()
	return reached
end

local function nearestNode(nav, position: Vector3): number?
	local best, bestDistance = nil, math.huge
	for i, node in nav.Nodes do
		local d = (node - position).Magnitude
		if d < bestDistance then
			best, bestDistance = i, d
		end
	end
	return best
end

local function stroll(model: Model, humanoid: Humanoid, nav, rng: Random, startNode: number)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local current, previous = startNode, nil
	local failures = 0
	while model.Parent and humanoid.Health > 0 do
		local neighbours = nav.Edges[current] or {}
		if #neighbours == 0 then
			task.wait(4)
			current = nearestNode(nav, root.Position) or current
			continue
		end
		local choices = {}
		for _, n in neighbours do
			if n ~= previous then
				table.insert(choices, n)
			end
		end
		if #choices == 0 then
			choices = neighbours
		end
		local nextNode = choices[rng:NextInteger(1, #choices)]
		local target = nav.Nodes[nextNode] + Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
		local distance = (target - root.Position).Magnitude
		if moveTo(humanoid, target, distance / math.max(humanoid.WalkSpeed, 1) + 3) then
			previous, current = current, nextNode
			failures = 0
			if rng:NextNumber() < 0.14 then
				task.wait(rng:NextNumber(2, 7)) -- stop to look around
			end
		else
			failures += 1
			if failures >= 3 then
				-- stuck: hop back onto the nearest walkway node
				local node = nearestNode(nav, root.Position) or startNode
				model:PivotTo(CFrame.new(nav.Nodes[node] + Vector3.new(0, 3, 0)))
				current, previous, failures = node, nil, 0
			end
			task.wait(0.5)
		end
	end
end

local function spawnTownsfolk(info)
	local town = info.Model
	local folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = town or Workspace
	local rng = Random.new(Config.Town.Seed + 7)
	local nav = info.Nav

	-- Strollers on the street graph.
	if nav and #nav.Nodes > 0 then
		for i = 1, Config.Town.TownsfolkCount do
			local node = rng:NextInteger(1, #nav.Nodes)
			local outfit = OUTFITS[(i - 1) % #OUTFITS + 1]
			local cf = CFrame.new(nav.Nodes[node] + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			local model, humanoid = makeNPC(folder, outfit, rng, cf, false)
			task.spawn(stroll, model, humanoid, nav, Random.new(rng:NextInteger(1, 1e6)), node)
		end
	end

	local function posed(list, pose: string, outfitPicker, limit: number)
		for i, cf in list do
			if i > limit then
				break
			end
			local model = makeNPC(folder, outfitPicker(i), rng, cf, true)
			model:SetAttribute("Pose", pose)
			if pose == "Fish" then
				-- rod held in the hands, pointing forward and up while the arms are out
				local direction = Vector3.new(0, -0.41, -0.91)
				local rodOffset = CFrame.new(Vector3.new(0, -1, 0) + direction * 3.3) * CFrame.lookAt(Vector3.zero, direction).Rotation
				R6.AttachProp(model, "Right Arm", rodOffset, {
					Size = Vector3.new(0.14, 0.14, 7),
					Color = rgb(120, 90, 60),
					Material = M.Wood,
				})
			end
		end
	end
	local function randomOutfit()
		return OUTFITS[rng:NextInteger(1, #OUTFITS)]
	end
	if Config.Town.Vendors then
		posed(info.Vendors or {}, "Vendor", function()
			return VENDOR
		end, 12)
	end
	posed(info.Seats or {}, "Sit", randomOutfit, 12)
	posed(info.Leans or {}, "Lean", randomOutfit, 6)
	posed(info.Fish or {}, "Fish", function()
		return FISHER
	end, 4)
	local chatters = {}
	for _, pair in info.Chats or {} do
		table.insert(chatters, pair[1])
		table.insert(chatters, pair[2])
	end
	posed(chatters, "Chat", randomOutfit, 10)
end

local function convertExisting()
	if not Config.Characters.ConvertExistingNPCs then
		return
	end
	local function consider(humanoid: Instance)
		if not humanoid:IsA("Humanoid") then
			return
		end
		local model = humanoid.Parent
		if not model or not model:IsA("Model") or model:GetAttribute("Townsfolk") then
			return
		end
		if Players:GetPlayerFromCharacter(model) then
			return
		end
		task.defer(function()
			if model.Parent and RigConverter.IsCandidate(model) then
				local ok, err = pcall(RigConverter.Convert, model)
				if not ok then
					warn(("[Sicily] Couldn't convert NPC %s to R6: %s"):format(model:GetFullName(), tostring(err)))
				end
			end
		end)
	end
	for _, descendant in Workspace:GetDescendants() do
		consider(descendant)
	end
	Workspace.DescendantAdded:Connect(consider)
end

-- Exposed for the offline test harness.
NPCs._Test = { MakeNPC = makeNPC, Outfits = OUTFITS, Vendor = VENDOR }

function NPCs.Start(townInfo)
	convertExisting()
	if townInfo and Config.Town.TownsfolkCount >= 0 then
		local ok, err = pcall(spawnTownsfolk, townInfo)
		if not ok then
			warn("[Sicily] Townsfolk failed to spawn: " .. tostring(err))
		end
	end
end

return NPCs
