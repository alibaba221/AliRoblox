--[[
	Horses (server)

	* Spawns the wild herds (Config.Horses.Herds) and the saddled stable horses.
	* Runs every riderless horse: grazing, wandering, watching players, bolting from runners and
	  gunfire, coming to its owner's whistle, going home (see Brain.luau).
	* Mounting ("E  Mount" prompt), taming (the server keeps the real progress), dismounting,
	  throwing riders off, ownership (one tamed horse per player) and network ownership:
	  while ridden, the rider's client simulates the horse so it responds instantly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local HorseMotor = require(Shared:WaitForChild("HorseMotor"))
local HorseMount = require(Shared:WaitForChild("HorseMount"))
local HorseRig = require(Shared:WaitForChild("HorseRig"))
local HorseTypes = require(Shared:WaitForChild("HorseTypes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Taming = require(Shared:WaitForChild("Taming"))

local Brain = require(script.Brain)
local CollisionGroups = require(script.Parent.CollisionGroups)
local Plan = require(script.Parent.Town.Plan)

local Horses = {}

local settings = Config.Horses
local L = HorseRig.Layout

local folder: Folder
local records = {} -- [Model] = record
local riding = {} -- [Player] = record
local ownedBy = {} -- [userId] = record
local lastRequest = {} -- [Player] = { [action] = clock }
local pendingShots = {} -- gunshot positions heard since the last AI tick
local rng = Random.new()
local nextId = 0
local horseEvent, horseRequest

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
rayParams.RespectCanCollide = true

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Terrain queries -----------------------------------------------------------------------------------
local function refreshFilter()
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
end

local function groundAt(x: number, z: number): RaycastResult?
	return Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -900, 0), rayParams)
end

local function walkable(point: Vector3): boolean
	if Plan.InTown(point.X, point.Z, 12) then
		return false
	end
	local b = Plan.Bounds
	if point.X < b.X0 + 25 or point.X > b.X1 - 25 or point.Z < b.Z0 + 25 or point.Z > b.Z1 - 25 then
		return false
	end
	local hit = groundAt(point.X, point.Z)
	return hit ~= nil and hit.Material ~= Enum.Material.Water and hit.Position.Y > 2
end

local function clearDistance(root: BasePart, direction: Vector3, range: number): number
	local origin = root.Position + Vector3.new(0, 0.4, 0)
	local hit = Workspace:Raycast(origin, direction * range, rayParams)
	local free = if hit then hit.Distance else range
	-- don't walk off cliffs or into water
	local probe = root.Position + direction * math.min(free, 7)
	local ground = Workspace:Raycast(probe + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), rayParams)
	if not ground or ground.Material == Enum.Material.Water or ground.Position.Y < root.Position.Y - L.RootHeight - 5 then
		free = math.min(free, 4)
	end
	return free
end

-- Rider helpers -----------------------------------------------------------------------------------------
local function setRiderPhysics(record, character: Model, mounted: boolean)
	if mounted then
		record.SavedParts = {}
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				record.SavedParts[d] = { Massless = d.Massless, Group = d.CollisionGroup }
				d.Massless = true
				d.CollisionGroup = HorseMount.RiderGroup
			end
		end
	else
		for part, saved in record.SavedParts or {} do
			if part.Parent then
				part.Massless = saved.Massless
				part.CollisionGroup = saved.Group
			end
		end
		record.SavedParts = nil
	end
end

local function notify(player: Player, kind: string, ...)
	horseEvent:FireClient(player, kind, ...)
end

local function setMode(record, mode: string)
	record.Mode = mode
	record.Model:SetAttribute("Mode", mode)
end

local function objectText(record): string
	local coat = HorseTypes.GetCoat(record.Coat)
	if record.Wild then
		return ("Wild %s · %s"):format(coat.DisplayName, record.Temperament.DisplayName)
	elseif record.OwnerName then
		return record.OwnerName .. "'s horse"
	elseif record.Stable then
		return "Stable horse · " .. coat.DisplayName
	end
	return coat.DisplayName .. " horse"
end

local function refreshPrompt(record)
	local prompt = record.Prompt
	if prompt then
		prompt.ObjectText = objectText(record)
		prompt.ActionText = if record.Wild then "Mount (tame)" else "Mount"
		prompt.Enabled = record.Rider == nil
	end
end

-- Spawning -------------------------------------------------------------------------------------------
local function spawnHorse(options)
	nextId += 1
	local temperament = HorseTypes.GetTemperament(options.Temperament)
	local coatNames = options.Coats or HorseTypes.CoatNames()
	local coat = options.Coat or coatNames[rng:NextInteger(1, #coatNames)]
	local model = HorseRig.Build({ Coat = coat, CFrame = options.CFrame, Name = "Horse" .. nextId })
	local root = model.PrimaryPart :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	model:SetAttribute("HorseId", nextId)
	model:SetAttribute("Temperament", temperament.Id)
	model:SetAttribute("Wild", options.Wild)
	if not options.Wild then
		HorseRig.AddTack(model)
	end
	HorseMotor.EnsureAlign(root)
	model:AddTag(HorseRig.Tag)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MountPrompt"
	prompt.KeyboardKeyCode = settings.MountKey
	prompt.GamepadKeyCode = settings.MountGamepadKey
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = settings.MountDistance
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.UIOffset = Vector2.new(0, -20)
	local barrel = model:FindFirstChild("Barrel")
	prompt.Parent = barrel and barrel:FindFirstChild("PromptAttachment") or root

	model.Parent = folder
	HorseMotor.ConfigureHumanoid(humanoid)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local record = {
		Id = nextId,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Prompt = prompt,
		Temperament = temperament,
		Coat = coat,
		Wild = options.Wild,
		Stable = options.Stable,
		Slot = options.Slot,
		Herd = options.Herd,
		Home = options.Home,
		HomeRadius = options.HomeRadius,
		Motor = HorseMotor.new(model, temperament),
		Brain = Brain.new(temperament, Random.new(rng:NextInteger(1, 1e9))),
		Mode = "Graze",
		OwnerId = nil :: number?,
		OwnerName = nil :: string?,
		Rider = nil :: Player?,
		ThrownUntil = {},
		LastRidden = os.clock(),
		Stuck = 0,
	}
	records[model] = record
	setMode(record, "Graze")
	refreshPrompt(record)
	prompt.Triggered:Connect(function(player)
		Horses.TryMount(record, player)
	end)
	return record
end

local function randomHerdSpot(herd): CFrame?
	for _ = 1, 12 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = herd.Radius * math.sqrt(rng:NextNumber(0, 1))
		local x = herd.Center.X + math.cos(angle) * radius
		local z = herd.Center.Y + math.sin(angle) * radius
		local hit = groundAt(x, z)
		if hit and hit.Material ~= Enum.Material.Water and hit.Position.Y > 2 then
			return CFrame.new(hit.Position + Vector3.new(0, L.RootHeight + 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		end
	end
	return nil
end

local function playersNear(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function spawnWild(herd)
	local cf = randomHerdSpot(herd)
	if not cf then
		return nil
	end
	return spawnHorse({
		Wild = true,
		Temperament = herd.Temperament,
		Coats = herd.Coats,
		CFrame = cf,
		Herd = herd,
		Home = Vector3.new(herd.Center.X, cf.Y, herd.Center.Y),
		HomeRadius = herd.Radius,
	})
end

local function spawnStable(slot: CFrame, index: number)
	local coats = settings.StableCoats or {}
	local hit = groundAt(slot.X, slot.Z)
	local y = if hit then hit.Position.Y else slot.Y
	local cf = CFrame.new(slot.X, y + L.RootHeight + 0.3, slot.Z) * slot.Rotation
	return spawnHorse({
		Wild = false,
		Stable = true,
		Slot = slot,
		Temperament = "Calm",
		Coat = coats[(index - 1) % math.max(#coats, 1) + 1],
		CFrame = cf,
		Home = cf.Position,
		HomeRadius = 5,
	})
end

local function despawn(record)
	records[record.Model] = nil
	if record.OwnerId and ownedBy[record.OwnerId] == record then
		ownedBy[record.OwnerId] = nil
	end
	record.Model:Destroy()
end

-- Replace a horse later (out of sight), e.g. after it fell into the sea.
local function scheduleRespawn(record)
	local herd, stable, slot = record.Herd, record.Stable, record.Slot
	despawn(record)
	task.delay(if stable then 5 else settings.RespawnTime, function()
		if herd then
			for _ = 1, 20 do
				local cf = randomHerdSpot(herd)
				if cf and not playersNear(cf.Position, 70) then
					spawnWild(herd)
					return
				end
				task.wait(5)
			end
		elseif stable and slot then
			spawnStable(slot, 1)
		end
	end)
end

-- Riding -------------------------------------------------------------------------------------------------
local function release(record, reason: string)
	local player = record.Rider
	local character = record.RiderCharacter
	if record.Joint then
		record.Joint:Destroy()
		record.Joint = nil
	end
	for _, connection in record.RiderConnections or {} do
		connection:Disconnect()
	end
	record.RiderConnections = nil
	if character and character.Parent then
		setRiderPhysics(record, character, false)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.PlatformStand = false
		end
		character:SetAttribute("SicilyRiding", nil)
	end
	if player then
		riding[player] = nil
	end
	record.Rider = nil
	record.RiderCharacter = nil
	record.Dismounting = false
	record.Taming = nil
	local model = record.Model
	model:SetAttribute("Rider", nil)
	model:SetAttribute("TameSeed", nil)
	model:SetAttribute("TameStart", nil)
	model:SetAttribute("TameProgress", nil)
	record.LastRidden = os.clock()
	if not record.Wild then
		record.Home = record.Root.Position
		record.HomeRadius = 10
	end
	record.Brain:Set("Idle", os.clock(), 2)
	setMode(record, "Idle")
	refreshPrompt(record)
	task.defer(function()
		if record.Model.Parent and record.Rider == nil then
			pcall(function()
				record.Root:SetNetworkOwner(nil)
			end)
			record.Motor:Sync()
		end
	end)
	if player and player.Parent and reason ~= "Thrown" then
		notify(player, "Dismounted", model)
	end
end

local function tamed(record)
	local player = record.Rider
	if not player then
		return
	end
	record.Taming = nil
	record.Wild = false
	local model = record.Model
	model:SetAttribute("Wild", false)
	model:SetAttribute("TameSeed", nil)
	model:SetAttribute("TameStart", nil)
	model:SetAttribute("TameProgress", 1)
	-- one horse per player: the old one goes back to its herd in a while
	local previous = ownedBy[player.UserId]
	if previous and previous ~= record then
		previous.OwnerId = nil
		previous.OwnerName = nil
		previous.Model:SetAttribute("Owner", nil)
		previous.AbandonedAt = os.clock()
		refreshPrompt(previous)
	end
	ownedBy[player.UserId] = record
	record.OwnerId = player.UserId
	record.OwnerName = player.DisplayName
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("TamedAt", serverNow())
	HorseRig.AddTack(model)
	setMode(record, "Ridden")
	refreshPrompt(record)
	notify(player, "Tamed", model)
end

local function thrown(record)
	local player = record.Rider
	local rootCF = record.Root.CFrame
	local character = record.RiderCharacter
	release(record, "Thrown")
	if player then
		record.ThrownUntil[player.UserId] = os.clock() + record.Temperament.Taming.RetryCooldown
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local direction = (rootCF.RightVector * side * 1.0 + rootCF.LookVector * -0.6 + Vector3.new(0, 0.9, 0)).Unit
		notify(player, "Thrown", record.Model, direction)
	end
	-- the horse bolts
	local brain = record.Brain
	brain.Away = if character and character.PrimaryPart then character.PrimaryPart.Position else rootCF.Position
	brain:Set("Flee", os.clock(), rng:NextNumber(5, 8))
	setMode(record, "Flee")
end

local function startTaming(record, now: number)
	local seed = rng:NextInteger(1, 2 ^ 30)
	local rules = record.Temperament.Taming
	record.Taming = {
		Seed = seed,
		Start = now,
		Progress = rules.StartProgress,
		Timeline = Taming.Timeline(seed, record.Temperament),
		Next = 1,
		LastPress = 0,
		LastPublished = -1,
		PublishedAt = 0,
	}
	local model = record.Model
	model:SetAttribute("TameSeed", seed)
	model:SetAttribute("TameStart", now)
	model:SetAttribute("TameProgress", rules.StartProgress)
	setMode(record, "Taming")
end

local function stepTaming(record, dt: number)
	local tame = record.Taming
	local t = record.Temperament
	local elapsed = serverNow() - tame.Start
	tame.Progress = Taming.Drain(tame.Progress, dt, elapsed, t)
	local event = tame.Timeline[tame.Next]
	while event and event.Impact <= elapsed do
		tame.Progress -= Taming.Knock(event, t)
		tame.Next += 1
		event = tame.Timeline[tame.Next]
	end
	if tame.Progress >= 1 then
		tamed(record)
	elseif tame.Progress <= 0 or elapsed > t.Taming.MaxDuration + Taming.Delay then
		thrown(record)
	elseif math.abs(tame.Progress - tame.LastPublished) > 0.004 and os.clock() - tame.PublishedAt > 0.07 then
		tame.LastPublished = tame.Progress
		tame.PublishedAt = os.clock()
		record.Model:SetAttribute("TameProgress", tame.Progress)
	end
end

function Horses.TryMount(record, player: Player)
	if not record.Model.Parent or record.Rider or riding[player] then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if character:GetAttribute("SicilyRagdolled") or HorseMount.GetJoint(character) then
		return
	end
	local seatWorld = record.Root.CFrame * HorseMount.SeatOffset()
	if (root.Position - seatWorld.Position).Magnitude > settings.MountDistance + 6 then
		return
	end
	if record.OwnerId and record.OwnerId ~= player.UserId and Players:GetPlayerByUserId(record.OwnerId) then
		notify(player, "NotYours", record.OwnerName or "someone")
		return
	end
	if record.Wild and (record.ThrownUntil[player.UserId] or 0) > os.clock() then
		notify(player, "Spooked", record.Model)
		return
	end

	local now = serverNow()
	record.Brain:Set("Hold", os.clock(), 1e9)
	record.Motor:Halt()
	local from = seatWorld:ToObjectSpace(root.CFrame)
	if from.Position.Magnitude > 12 then
		from = CFrame.new(from.Position.Unit * 12) * from.Rotation
	end

	setRiderPhysics(record, character, true)
	humanoid.PlatformStand = true
	local joint = Instance.new("Motor6D")
	joint.Name = HorseMount.JointName
	joint.Part0 = record.Root
	joint.Part1 = root
	joint.C0 = HorseMount.SeatOffset()
	joint.C1 = CFrame.new()
	joint:SetAttribute("MountStart", now)
	joint:SetAttribute("MountFrom", from)
	joint.Parent = root

	record.Joint = joint
	record.Rider = player
	record.RiderCharacter = character
	riding[player] = record
	record.Model:SetAttribute("Rider", player.UserId)
	character:SetAttribute("SicilyRiding", record.Id)
	refreshPrompt(record)
	pcall(function()
		record.Root:SetNetworkOwner(player)
	end)
	if record.Wild then
		startTaming(record, now)
	else
		setMode(record, "Ridden")
	end
	record.RiderConnections = {
		humanoid.Died:Connect(function()
			if record.Rider == player then
				release(record, "Died")
			end
		end),
		character.AncestryChanged:Connect(function()
			if record.Rider == player and not character:IsDescendantOf(Workspace) then
				release(record, "Left")
			end
		end),
	}
	notify(player, "Mounted", record.Model, record.Wild)
end

local function allowed(player: Player, action: string, interval: number): boolean
	local times = lastRequest[player]
	if not times then
		times = {}
		lastRequest[player] = times
	end
	local now = os.clock()
	if now - (times[action] or 0) < interval then
		return false
	end
	times[action] = now
	return true
end

local function onRequest(player: Player, action: unknown, payload: unknown)
	if type(action) ~= "string" then
		return
	end
	local record = riding[player]
	if action == "Calm" then
		if not record or not record.Taming then
			return
		end
		local tame = record.Taming
		local now = os.clock()
		if now - tame.LastPress < Taming.PressInterval then
			return
		end
		tame.LastPress = now
		tame.Progress = Taming.Press(tame.Progress, record.Temperament)
	elseif action == "Dismount" then
		if not record or record.Dismounting or not allowed(player, "Dismount", 0.3) then
			return
		end
		if record.Taming then
			thrown(record) -- letting go of a wild horse: it bolts and you tumble off
			return
		end
		local speed = record.Root.AssemblyLinearVelocity.Magnitude
		if payload == "Leap" or speed > 18 then
			-- jumping off at speed: no step-down animation, the client throws itself clear
			release(record, "Leap")
			return
		end
		local to = HorseMount.ChooseDismount(function(spot: Vector3)
			local world = record.Root.CFrame:PointToWorldSpace(spot)
			local origin = record.Root.Position
			return Workspace:Raycast(origin, world - origin, rayParams) == nil
		end)
		local joint = record.Joint
		if not joint then
			return
		end
		record.Dismounting = true
		joint:SetAttribute("DismountTo", to)
		joint:SetAttribute("DismountStart", serverNow())
		task.delay(HorseMount.DismountTime, function()
			if record.Joint == joint then
				release(record, "Dismount")
			end
		end)
	elseif action == "Call" then
		if not allowed(player, "Call", 2) then
			return
		end
		local own = ownedBy[player.UserId]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not own or not own.Model.Parent or not root then
			notify(player, "CallFailed", "NoHorse")
			return
		end
		if own.Rider then
			notify(player, "CallFailed", "Ridden")
			return
		end
		if (own.Root.Position - (root :: BasePart).Position).Magnitude > settings.CallRange then
			notify(player, "CallFailed", "TooFar")
			return
		end
		own.Whistle = true
		notify(player, "Called", own.Model)
	end
end

-- AI tick -------------------------------------------------------------------------------------------------
local function nearestThreat(position: Vector3)
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				local velocity = root.AssemblyLinearVelocity
				best = { Position = root.Position, Speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude, Distance = distance }
				bestDistance = distance
			end
		end
	end
	if best and best.Distance < 70 then
		return best
	end
	return nil
end

local function ownerPosition(record): Vector3?
	if not record.OwnerId then
		return nil
	end
	local player = Players:GetPlayerByUserId(record.OwnerId)
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function thinkAll()
	refreshFilter()
	local shots = pendingShots
	pendingShots = {}
	local now = os.clock()
	for model, record in records do
		if not model.Parent then
			records[model] = nil
			continue
		end
		local root = record.Root
		-- lost: fell off the world, into deep water, or wandered far away
		if record.Rider == nil then
			local position = root.Position
			local tooFar = (position - record.Home).Magnitude > 900
			if position.Y < -30 or tooFar then
				scheduleRespawn(record)
				continue
			end
			-- abandoned tamed horses go back to their herd; stable horses go back to the stable
			local abandonedFor = now - math.max(record.LastRidden, record.AbandonedAt or 0)
			if not record.Wild and not record.OwnerId and abandonedFor > settings.AbandonTime and not playersNear(position, 60) then
				if record.Stable then
					local slot = record.Slot
					if slot and (position - slot.Position).Magnitude > 15 then
						root.CFrame = CFrame.new(slot.Position + Vector3.new(0, L.RootHeight + 0.3, 0)) * slot.Rotation
						record.Home = root.Position
						record.HomeRadius = 5
						record.Motor:Sync()
					end
					record.LastRidden = now
				elseif record.Herd then
					scheduleRespawn(record)
					continue
				end
			end
		end
		if record.Rider or record.Mode == "Hold" then
			continue
		end
		local gunshot = nil
		for _, shot in shots do
			if not gunshot or (shot - root.Position).Magnitude < (gunshot - root.Position).Magnitude then
				gunshot = shot
			end
		end
		local senses = {
			Now = now,
			Position = root.Position,
			Heading = record.Motor.Heading,
			Speed = record.Motor.Speed,
			Threat = nearestThreat(root.Position),
			Gunshot = gunshot,
			Whistle = if record.Whistle then true else nil,
			Owner = ownerPosition(record),
			Home = record.Home,
			HomeRadius = record.HomeRadius,
			Wild = record.Wild,
			Clear = function(direction: Vector3)
				return clearDistance(root, direction, 18)
			end,
			Walkable = walkable,
		}
		record.Whistle = nil
		local command, pose = record.Brain:Update(senses)
		record.Command = command
		setMode(record, record.Brain.State)
		model:SetAttribute("Graze", pose.Graze or nil)
		model:SetAttribute("Alert", pose.Alert or nil)
		model:SetAttribute("LookAt", pose.LookAt)
		-- stuck for a long time with nobody watching: pop back home
		if record.Brain:Stuck() > 12 and not playersNear(root.Position, 80) then
			local cf = if record.Herd then randomHerdSpot(record.Herd) else nil
			if cf then
				root.CFrame = cf
				record.Motor:Sync()
				record.Brain:Set("Graze", now, 6)
			end
		end
	end
end

local function heartbeat(dt: number)
	for model, record in records do
		if not model.Parent then
			continue
		end
		if record.Taming and record.Rider then
			stepTaming(record, dt)
		elseif record.Rider == nil then
			record.Motor:Update(dt, record.Command or { Gait = 0 })
		end
	end
end

-- Called by the combat system for every shot fired.
function Horses.OnGunshot(position: Vector3, shooter: Player?)
	table.insert(pendingShots, position)
	-- ridden horses nearby flinch (the rider keeps control of a tamed horse)
	for _, record in records do
		if record.Rider and (record.Root.Position - position).Magnitude < 45 then
			record.Model:SetAttribute("Startle", serverNow())
			notify(record.Rider, "Startled", record.Model, position)
		end
	end
	local _ = shooter
end

function Horses.GetRiding(player: Player)
	return riding[player]
end

function Horses.IsHorse(instance: Instance): boolean
	for model in records do
		if instance:IsDescendantOf(model) then
			return true
		end
	end
	return false
end

-- Wild horses hit by a stray bullet bolt; tamed ones flinch.
function Horses.OnHit(instance: Instance, from: Vector3)
	for model, record in records do
		if instance:IsDescendantOf(model) then
			record.Model:SetAttribute("Startle", serverNow())
			if not record.Rider then
				record.Brain.Away = from
				record.Brain:Set("Flee", os.clock(), if record.Wild then 7 else 2)
			end
			return true
		end
	end
	return false
end

function Horses.Start(townInfo)
	if not settings.Enabled then
		return
	end
	CollisionGroups.Setup()
	Remotes.Init()
	horseEvent = Remotes.Get("HorseEvent")
	horseRequest = Remotes.Get("HorseRequest")
	horseRequest.OnServerEvent:Connect(function(player, action, payload)
		local ok, err = pcall(onRequest, player, action, payload)
		if not ok then
			warn("[Sicily] Horse request failed: " .. tostring(err))
		end
	end)

	folder = Workspace:FindFirstChild("SicilyHorses") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SicilyHorses"
		folder.Parent = Workspace
	end
	refreshFilter()

	for _, herd in settings.Herds do
		for _ = 1, herd.Count do
			local ok, err = pcall(spawnWild, herd)
			if not ok then
				warn("[Sicily] Couldn't spawn a horse for " .. tostring(herd.Name) .. ": " .. tostring(err))
			end
		end
	end
	local slots = if townInfo then townInfo.StableSlots else nil
	if slots then
		for i = 1, math.min(settings.StableHorses, #slots) do
			pcall(spawnStable, slots[i], i)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local record = riding[player]
		if record then
			release(record, "Left")
		end
		local own = ownedBy[player.UserId]
		if own then
			ownedBy[player.UserId] = nil
			own.OwnerId = nil
			own.OwnerName = nil
			own.Model:SetAttribute("Owner", nil)
			own.AbandonedAt = os.clock()
			refreshPrompt(own)
		end
		lastRequest[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(heartbeat, dt)
		if not ok then
			warn("[Sicily] Horse update failed: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(thinkAll)
			if not ok then
				warn("[Sicily] Horse AI failed: " .. tostring(err))
			end
			task.wait(0.1)
		end
	end)
end

return Horses
