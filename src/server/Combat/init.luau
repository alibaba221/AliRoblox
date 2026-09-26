--[[
	Combat (server) — the authority for guns.

	* Gives every player their loadout (Config.Combat.Loadout): real gun models on a gun belt,
	  holstered on the hips and back, and keeps each gun's ammo (magazine + reserve) here.
	* Draw / holster / switch / reload timing, fire rate, ammo, Dead Eye meter: all tracked on the
	  server. Clients predict for responsiveness; the server has the final say.
	* Hit validation: every hit a client reports is checked (muzzle near the shooter, fire rate,
	  bullet path, range, the struck part really being there allowing for lag, no wall in the way)
	  before any damage is dealt. Damage is always computed here from the weapon's stats.
	* Replicates what others need to see: weapon/aim state as character attributes, other
	  players' shots (flash, tracers, impacts) and hit reactions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Ballistics = require(Shared:WaitForChild("Ballistics"))
local Config = require(Shared:WaitForChild("Config"))
local HorseMount = require(Shared:WaitForChild("HorseMount"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local CollisionGroups = require(script.Parent.CollisionGroups)
local Targets = require(script.Targets)

local Combat = {}

local settings = Config.Combat
local players = {} -- [Player] = state
local hooks = { Gunshot = {}, Hit = {} } -- other systems (horses, townsfolk) listen here
local combatEvent, shotFX
local rng = Random.new()

local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
shotParams.IgnoreWater = true

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function fire(list, ...)
	for _, callback in list do
		task.spawn(callback, ...)
	end
end

-- Other systems: Combat.OnGunshot(fn(position, shooter)), Combat.OnHit(fn(instance, from, shooter)).
function Combat.OnGunshot(callback)
	table.insert(hooks.Gunshot, callback)
end
function Combat.OnHit(callback)
	table.insert(hooks.Hit, callback)
end

-- Ammo is published as player attributes so the owner's HUD (and anyone curious) can read it.
local function publishAmmo(player: Player, state, id: string)
	local ammo = state.Ammo[id]
	if ammo then
		player:SetAttribute("Ammo_" .. id, ammo.Mag)
		player:SetAttribute("Reserve_" .. id, ammo.Reserve)
	end
end

local function setWeaponState(state, weaponState: string, duration: number?)
	state.State = weaponState
	state.StateAt = now()
	state.StateUntil = if duration then state.StateAt + duration else nil
	local character = state.Character
	if character then
		character:SetAttribute("WeaponState", weaponState)
		character:SetAttribute("WeaponStateAt", state.StateAt)
		character:SetAttribute("Weapon", state.Equipped or "")
		character:SetAttribute("ReloadRounds", state.ReloadRounds)
	end
end

-- Gun belt ----------------------------------------------------------------------------------------
local LEATHER = Color3.fromRGB(88, 56, 34)
local LEATHER_DARK = Color3.fromRGB(58, 38, 26)
local BRASS = Color3.fromRGB(196, 156, 74)

local function accessory(parent: Instance, torso: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Leather
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = size.X * size.Y * size.Z > 0.05
	part.CFrame = torso.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function buildBelt(folder: Instance, torso: BasePart, loadout: { string })
	accessory(folder, torso, "Belt", Vector3.new(2.08, 0.26, 1.08), CFrame.new(0, -0.86, 0), LEATHER_DARK)
	accessory(folder, torso, "Buckle", Vector3.new(0.34, 0.24, 0.06), CFrame.new(0, -0.86, -0.56), BRASS, Enum.Material.Metal)
	for i = 0, 5 do
		accessory(folder, torso, "Loop", Vector3.new(0.14, 0.2, 0.06), CFrame.new(-0.9 + i * 0.12, -0.86, -0.57), BRASS, Enum.Material.Metal)
	end
	local hasLongarm = false
	for _, id in loadout do
		local def = Weapons.Get(id)
		if def and def.Slot == "Sidearm" then
			local holster = Weapons.Holsters[def.Holster]
			if holster then
				-- a leather sheath around the barrel, hanging from the belt
				local side = if holster.Position.X > 0 then 1 else -1
				accessory(folder, torso, "Holster", Vector3.new(0.3, 1.05, 0.48), CFrame.new(side * 1.13, -1.45, 0.02) * CFrame.Angles(0, 0, side * math.rad(-6)), LEATHER)
			end
		elseif def then
			hasLongarm = true
		end
	end
	if hasLongarm then
		-- bandolier across the chest, from the left shoulder to the right hip
		local strap = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(-42))
		accessory(folder, torso, "Bandolier", Vector3.new(0.34, 2.9, 1.06), strap, LEATHER)
		for i = -3, 3 do
			accessory(folder, torso, "Cartridge", Vector3.new(0.1, 0.24, 0.06), strap * CFrame.new(0, i * 0.3, -0.56), BRASS, Enum.Material.Metal)
		end
	end
end

-- Loadout ------------------------------------------------------------------------------------------
local function equipLoadout(_player: Player, state, character: Model)
	local torso = character:WaitForChild("Torso", 10)
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild(WeaponModels.FolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = WeaponModels.FolderName
	state.Models = {}
	state.Joints = {}
	for _, id in state.Loadout do
		local def = Weapons.Get(id)
		local holster = def and Weapons.Holsters[def.Holster]
		local model = def and WeaponModels.Build(id, torso.CFrame * (holster or CFrame.new()))
		if model and holster then
			local joint = Instance.new("Motor6D")
			joint.Name = WeaponModels.JointName
			joint.Part0 = torso
			joint.Part1 = model.PrimaryPart
			joint.C0 = holster
			joint.C1 = CFrame.new()
			joint.Parent = model.PrimaryPart
			model.Parent = folder
			state.Models[id] = model
			state.Joints[id] = joint
		end
	end
	if settings.GunBelt then
		local belt = Instance.new("Folder")
		belt.Name = "GunBelt"
		belt.Parent = folder
		buildBelt(belt, torso, state.Loadout)
	end
	folder.Parent = character
	state.Equipped = nil
	state.ReloadRounds = 0
	setWeaponState(state, "Holstered")
	character:SetAttribute("Loadout", table.concat(state.Loadout, ","))
end

local function refill(player: Player, state)
	for _, id in state.Loadout do
		local def = Weapons.Get(id)
		if def then
			state.Ammo[id] = { Mag = def.Magazine, Reserve = def.Reserve }
			publishAmmo(player, state, id)
		end
	end
end

-- Timed states --------------------------------------------------------------------------------------
-- Per-round reloads add each round as it goes in (by time `t`), so an interrupted reload keeps them.
local function progressReload(player: Player, state, t: number)
	local def = Weapons.Get(state.Equipped)
	local ammo = state.Equipped and state.Ammo[state.Equipped]
	if state.State ~= "Reloading" or not def or not ammo or def.Reload.Kind ~= "PerRound" then
		return
	end
	local elapsed = t - state.StateAt - def.Reload.Start
	local shouldHave = math.clamp(math.floor(elapsed / def.Reload.PerRound), 0, state.ReloadRounds)
	while (state.ReloadInserted or 0) < shouldHave and ammo.Reserve > 0 do
		ammo.Mag += 1
		ammo.Reserve -= 1
		state.ReloadInserted = (state.ReloadInserted or 0) + 1
		publishAmmo(player, state, state.Equipped)
	end
end

-- Completes a draw / holster / reload whose time is up.
local function finishState(player: Player, state)
	if state.State == "Drawing" then
		setWeaponState(state, "Drawn")
	elseif state.State == "Holstering" then
		state.Equipped = nil
		setWeaponState(state, "Holstered")
	elseif state.State == "Reloading" then
		local id = state.Equipped
		local ammo = id and state.Ammo[id]
		if ammo then
			local left = state.ReloadRounds - (state.ReloadInserted or 0)
			local moved = math.min(left, ammo.Reserve)
			ammo.Mag += moved
			ammo.Reserve -= moved
			publishAmmo(player, state, id)
		end
		state.ReloadRounds = 0
		setWeaponState(state, "Drawn")
		combatEvent:FireClient(player, "Reloaded", id)
	end
end

-- Requests -------------------------------------------------------------------------------------------
local function alive(state): (boolean, Humanoid?)
	local character = state.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and not character:GetAttribute("SicilyRagdolled"), humanoid
end

local function startDraw(state, id: string)
	local def = Weapons.Get(id)
	local switching = state.Equipped and state.Equipped ~= id and state.State ~= "Holstered"
	local previous = state.Equipped
	state.Equipped = id
	state.ReloadRounds = 0
	local duration = def.DrawTime + (if switching and previous then (Weapons.Get(previous) :: any).HolsterTime * 0.7 else 0)
	state.Character:SetAttribute("PreviousWeapon", if switching then previous else nil)
	setWeaponState(state, "Drawing", duration)
end

local function startReload(player: Player, state)
	local id = state.Equipped
	local def = Weapons.Get(id)
	local ammo = id and state.Ammo[id]
	if not def or not ammo or ammo.Mag >= def.Magazine or ammo.Reserve <= 0 then
		return
	end
	local missing = math.min(def.Magazine - ammo.Mag, ammo.Reserve)
	state.ReloadRounds = missing
	state.ReloadInserted = 0
	setWeaponState(state, "Reloading", Weapons.ReloadTime(def, missing))
	local _ = player
end

local function onRequest(player: Player, action: unknown, arg: unknown)
	local state = players[player]
	if not state or type(action) ~= "string" then
		return
	end
	local ok = alive(state)
	if not ok then
		return
	end
	-- the client finishes a draw / reload a moment before we do; a request right after that
	-- shouldn't bounce
	if (action == "Reload" or action == "DeadEye") and state.StateUntil and (state.State == "Drawing" or state.State == "Reloading") then
		if state.StateUntil - now() <= math.min(player:GetNetworkPing(), 0.3) + 0.1 then
			finishState(player, state)
		end
	end
	if action == "Equip" then
		if type(arg) ~= "string" or not table.find(state.Loadout, arg) then
			return
		end
		if state.Equipped == arg and (state.State == "Drawn" or state.State == "Drawing") then
			return
		end
		-- both hands are busy climbing on / off a horse or hanging on to a wild one
		local joint = HorseMount.GetJoint(state.Character)
		if joint then
			local mountStart = joint:GetAttribute("MountStart")
			local horse = joint.Part0 and joint.Part0.Parent
			if joint:GetAttribute("DismountStart")
				or (type(mountStart) == "number" and now() - mountStart < HorseMount.MountTime)
				or (horse and horse:GetAttribute("Mode") == "Taming")
			then
				return
			end
		end
		startDraw(state, arg)
	elseif action == "Holster" then
		if state.Equipped and state.State ~= "Holstered" and state.State ~= "Holstering" then
			local def = Weapons.Get(state.Equipped)
			setWeaponState(state, "Holstering", if def then def.HolsterTime else 0.3)
			state.Character:SetAttribute("Aiming", false)
		end
	elseif action == "Reload" then
		if state.State == "Drawn" then
			startReload(player, state)
		end
	elseif action == "DeadEye" then
		local deadEye = settings.DeadEye
		if not deadEye.Enabled then
			return
		end
		if arg == false or (state.DeadEyeUntil or 0) > now() then
			if (state.DeadEyeUntil or 0) > now() then
				state.DeadEyeGrace = now() + 1.5 -- the painted shots may still be on their way
			end
			state.DeadEyeUntil = 0
			state.Character:SetAttribute("DeadEye", false)
		elseif state.DeadEye >= deadEye.Cost and state.State == "Drawn" then
			state.DeadEyeUntil = now() + state.DeadEye / deadEye.DrainPerSecond
			state.Character:SetAttribute("DeadEye", true)
		end
	elseif action == "Cover" then
		-- purely cosmetic for other players' animation
		state.Character:SetAttribute("Cover", if arg == "Low" or arg == "High" then arg else nil)
	end
end

local function onAimState(player: Player, aiming: unknown, pitch: unknown, yaw: unknown)
	local state = players[player]
	if not state or not state.Character then
		return
	end
	if type(aiming) ~= "boolean" or type(pitch) ~= "number" or type(yaw) ~= "number" then
		return
	end
	if pitch ~= pitch or yaw ~= yaw then
		return
	end
	local character = state.Character
	local drawn = state.State == "Drawn" or state.State == "Reloading"
	character:SetAttribute("Aiming", aiming and drawn)
	character:SetAttribute("AimPitch", math.floor(math.clamp(pitch, -1.5, 1.5) * 100 + 0.5) / 100)
	character:SetAttribute("AimYaw", math.floor(yaw * 100 + 0.5) / 100)
end

-- Firing ----------------------------------------------------------------------------------------------
local function characterOf(instance: Instance): (Model?, Humanoid?)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model, humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

local function canDamage(shooter: Player, victim: Model, humanoid: Humanoid): boolean
	if victim == shooter.Character or humanoid.Health <= 0 then
		return false
	end
	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if victimPlayer then
		return settings.PvP
	end
	if victim:GetAttribute("Townsfolk") then
		return settings.DamageTownsfolk
	end
	return victim:FindFirstAncestor("SicilyHorses") == nil
end

-- Bullets pass through decoration that isn't solid (invisible or non-colliding parts), but
-- always stop on characters, horses, range targets and terrain. Clients use the same rule.
local function stopsBullets(part: BasePart): boolean
	if part:IsA("Terrain") or characterOf(part) then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:HasTag(Targets.Tag) then
		return true
	end
	return part.CanCollide and part.Transparency < 0.9
end

-- Server check that nothing solid is between the muzzle and a claimed hit.
local function lineOfSight(origin: Vector3, point: Vector3, ignore: { Instance }): (boolean, RaycastResult?)
	local offset = point - origin
	local distance = offset.Magnitude
	if distance < 0.6 then
		return true, nil
	end
	local list = table.clone(ignore)
	local from, direction, remaining = origin, offset.Unit, distance - 0.6
	for _ = 1, 6 do
		shotParams.FilterDescendantsInstances = list
		shotParams.CollisionGroup = HorseMount.ShotGroup
		local result = Workspace:Raycast(from, direction * remaining, shotParams)
		if not result then
			return true, nil
		end
		-- characters and horses don't count as obstructions here (they move, the client saw them)
		if characterOf(result.Instance) then
			return true, nil
		end
		if stopsBullets(result.Instance) then
			return false, result
		end
		table.insert(list, result.Instance)
		remaining -= (result.Position - from).Magnitude
		from = result.Position
		if remaining <= 0.05 then
			return true, nil
		end
	end
	return true, nil
end

-- Body region of a struck part; hats and hair count as the head.
local HEAD_ATTACHMENTS = { HatAttachment = true, HairAttachment = true, FaceFrontAttachment = true, FaceCenterAttachment = true }
local function regionOf(part: BasePart): string
	if part:FindFirstAncestorOfClass("Accessory") then
		for _, child in part:GetChildren() do
			if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
				return "Head"
			end
		end
		return "Torso"
	end
	return Ballistics.Region(part.Name)
end

local function ignoreList(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local horses = Workspace:FindFirstChild("SicilyHorses")
	if horses then
		table.insert(list, horses)
	end
	return list
end

local function reject(player: Player, reason: string)
	combatEvent:FireClient(player, "Rejected", reason)
end

local function onFire(player: Player, shot: unknown)
	local state = players[player]
	if not state or type(shot) ~= "table" then
		return
	end
	local ok, shooterHumanoid = alive(state)
	if not ok or not shooterHumanoid then
		return
	end
	local shotData = shot :: { [string]: any }
	local id = state.Equipped
	local def = Weapons.Get(id)
	if not def or shotData.Weapon ~= id then
		return reject(player, "not equipped")
	end
	local t = now()
	local latency = player:GetNetworkPing()
	-- the client starts its draw / reload timers a moment before we hear about them, so let a
	-- shot through that arrives just before ours run out
	local slack = math.min(latency, 0.3) + 0.1
	-- (rounds going in need no allowance: the shot's own trip lines the two clocks up)
	progressReload(player, state, t + 0.05)
	if state.StateUntil and (state.State == "Drawing" or state.State == "Reloading") and state.StateUntil - t <= slack then
		finishState(player, state)
	end
	-- a shot interrupts a per-round reload (the rounds already loaded stay loaded)
	if state.State == "Reloading" and def.Reload.Kind == "PerRound" and (state.ReloadInserted or 0) > 0 then
		state.ReloadRounds = 0
		setWeaponState(state, "Drawn")
	end
	if state.State ~= "Drawn" then
		return reject(player, "not ready")
	end
	local ammo = state.Ammo[id]
	if not ammo or ammo.Mag <= 0 then
		return reject(player, "empty")
	end
	-- Fire rate: a credit that refills at the gun's pace. Shots bunched up by network jitter
	-- still pass, but nobody can keep firing faster than the gun allows.
	local deadEye = (state.DeadEyeUntil or 0) > t or (state.DeadEyeGrace or 0) > t
	local interval = if deadEye then settings.DeadEye.ShotInterval else Weapons.MinInterval(def)
	local credit = math.min(1, (state.ShotCredit or 1) + (t - state.LastShot) / interval)
	local allowance = math.min(0.5, (settings.FireRateTolerance + 0.06) / interval)
	if credit < 1 - allowance then
		return reject(player, "too fast")
	end
	state.ShotCredit = credit - 1

	local origin, direction = shotData.Origin, shotData.Direction
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 then
		return reject(player, "bad shot")
	end
	direction = direction.Unit
	local character = state.Character :: Model
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return
	end
	local speed = (root :: BasePart).AssemblyLinearVelocity.Magnitude
	if not Ballistics.ValidOrigin(origin, (head :: BasePart).Position, speed, latency + 0.1, settings.MaxOriginDistance) then
		return reject(player, "origin")
	end

	state.LastShot = t
	ammo.Mag -= 1
	publishAmmo(player, state, id)

	-- Pellets --------------------------------------------------------------------------------------
	local pellets = shotData.Pellets
	if type(pellets) ~= "table" then
		pellets = {}
	end
	local maxDeviation = Ballistics.MaxDeviation(def)
	local impacts = {}
	local ignore = ignoreList()
	local confirmed = {}
	local struck = {} -- other things hit (targets, horses): told once the shot is resolved
	for index = 1, math.min(#pellets, def.Pellets) do
		local pellet = pellets[index]
		if type(pellet) ~= "table" or typeof(pellet.Direction) ~= "Vector3" then
			continue
		end
		local pelletDir = pellet.Direction.Unit
		if Ballistics.Angle(pelletDir, direction) > maxDeviation then
			continue
		end
		local hitPart, hitPosition, hitNormal = pellet.Hit, pellet.Position, pellet.Normal
		if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") or typeof(hitPosition) ~= "Vector3" then
			-- a miss (or the ground): trace where it ends for everyone else's effects
			shotParams.FilterDescendantsInstances = { character }
			shotParams.CollisionGroup = HorseMount.ShotGroup
			local result = Workspace:Raycast(origin, pelletDir * def.Range, shotParams)
			if result then
				table.insert(impacts, { result.Position, result.Normal, Ballistics.Surface(result.Material.Name) })
			else
				table.insert(impacts, { origin + pelletDir * def.Range, false, "Air" })
			end
			continue
		end
		if not hitPart:IsDescendantOf(Workspace) or hitPart:IsDescendantOf(character) then
			continue
		end
		local valid = Ballistics.ValidateHit({ Origin = origin, Direction = pelletDir }, { Position = hitPosition }, {
			CFrame = hitPart.CFrame,
			Size = hitPart.Size,
			Velocity = hitPart.AssemblyLinearVelocity,
		}, {
			Range = def.Range,
			Tolerance = settings.HitTolerance,
			Latency = latency + 0.1,
		})
		if not valid then
			continue
		end
		local clear, blocker = lineOfSight(origin, hitPosition, ignore)
		if not clear and blocker then
			table.insert(impacts, { blocker.Position, blocker.Normal, Ballistics.Surface(blocker.Material.Name) })
			continue
		end
		local distance = (hitPosition - origin).Magnitude
		local victim, humanoid = characterOf(hitPart)
		local normal = if typeof(hitNormal) == "Vector3" then hitNormal else -pelletDir
		table.insert(impacts, { hitPosition, normal, Ballistics.Surface(hitPart.Material.Name, victim ~= nil) })
		if victim and humanoid and canDamage(player, victim, humanoid) then
			local region = regionOf(hitPart)
			local damage = Ballistics.Damage(def, region, distance)
			local entry = confirmed[victim]
			if not entry then
				local partName = if region == "Head" then "Head" else hitPart.Name
				entry = { Humanoid = humanoid, Damage = 0, Head = false, Part = partName, Direction = pelletDir }
				confirmed[victim] = entry
			end
			entry.Damage += damage
			entry.Head = entry.Head or region == "Head"
		else
			struck[hitPart] = true
		end
	end

	for part in struck do
		fire(hooks.Hit, part, origin, player)
	end

	-- Apply damage once per victim (shotguns add up their pellets) ------------------------------------
	for victim, entry in confirmed do
		local humanoid = entry.Humanoid
		local before = humanoid.Health
		humanoid:TakeDamage(entry.Damage)
		local killed = before > 0 and humanoid.Health <= 0
		combatEvent:FireAllClients("Flinch", victim, entry.Part, entry.Direction, math.clamp(entry.Damage / 40, 0.3, 1.4), killed)
		combatEvent:FireClient(player, "Hit", victim, entry.Head, killed)
		local victimPlayer = Players:GetPlayerFromCharacter(victim)
		if victimPlayer then
			combatEvent:FireClient(victimPlayer, "Damaged", origin, entry.Damage)
		end
		fire(hooks.Hit, victim, origin, player)
		-- Dead Eye fills up a little with every hit
		state.DeadEye = math.min(settings.DeadEye.Max, state.DeadEye + settings.DeadEye.RegenPerHit)
	end

	-- Everyone else sees the shot (the shooter already drew it) ------------------------------------------
	for _, other in Players:GetPlayers() do
		if other ~= player then
			shotFX:FireClient(other, player, id, origin, impacts)
		end
	end
	fire(hooks.Gunshot, origin, player)
end

-- Tick: state timers, reload progress, Dead Eye ------------------------------------------------------
local function tick(dt: number)
	local t = now()
	for player, state in players do
		local character = state.Character
		if not character then
			continue
		end
		if state.StateUntil and t >= state.StateUntil then
			finishState(player, state)
		elseif state.State == "Reloading" then
			progressReload(player, state, t)
		end
		-- Dead Eye meter
		local deadEye = settings.DeadEye
		if deadEye.Enabled then
			if (state.DeadEyeUntil or 0) > t then
				state.DeadEye = math.max(0, state.DeadEye - deadEye.DrainPerSecond * dt)
				if state.DeadEye <= 0 then
					state.DeadEyeUntil = 0
					state.DeadEyeGrace = t + 1.5
				end
			else
				state.DeadEye = math.min(deadEye.Max, state.DeadEye + deadEye.RegenPerSecond * dt)
				if character:GetAttribute("DeadEye") then
					character:SetAttribute("DeadEye", false)
				end
			end
			local rounded = math.floor(state.DeadEye + 0.5)
			if player:GetAttribute("DeadEye") ~= rounded then
				player:SetAttribute("DeadEye", rounded)
			end
		end
	end
end

-- Players ----------------------------------------------------------------------------------------------
local function onCharacter(player: Player, character: Model)
	local state = players[player]
	if not state then
		return
	end
	state.Character = character
	state.Equipped = nil
	state.DeadEyeUntil = 0
	refill(player, state)
	task.spawn(function()
		-- wait until the avatar is applied so ApplyDescription can't disturb the guns
		for _ = 1, 40 do
			if character:GetAttribute("SicilyDressed") or not character.Parent then
				break
			end
			task.wait(0.25)
		end
		if character.Parent and player.Character == character then
			equipLoadout(player, state, character)
		end
	end)
end

local function onPlayer(player: Player)
	local loadout = {}
	for _, id in settings.Loadout do
		if Weapons.Get(id) then
			table.insert(loadout, id)
		else
			warn("[Sicily] Unknown weapon in Config.Combat.Loadout: " .. tostring(id))
		end
	end
	players[player] = {
		Loadout = loadout,
		Ammo = {},
		Models = {},
		Joints = {},
		State = "Holstered",
		StateAt = 0,
		LastShot = 0,
		DeadEye = settings.DeadEye.Max * 0.6,
		DeadEyeUntil = 0,
		DeadEyeGrace = 0,
		ShotCredit = 1,
		ReloadRounds = 0,
	}
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

-- Refill a player's reserve ammo (ammo crates).
function Combat.Refill(player: Player): boolean
	local state = players[player]
	if not state then
		return false
	end
	for _, id in state.Loadout do
		local def = Weapons.Get(id)
		local ammo = state.Ammo[id]
		if def and ammo then
			ammo.Reserve = def.Reserve
			publishAmmo(player, state, id)
		end
	end
	return true
end

function Combat.Start(townInfo)
	if not settings.Enabled then
		return
	end
	CollisionGroups.Setup()
	Remotes.Init()
	combatEvent = Remotes.Get("CombatEvent")
	shotFX = Remotes.Get("ShotFX")
	Remotes.Get("CombatRequest").OnServerEvent:Connect(function(player, action, arg)
		local ok, err = pcall(onRequest, player, action, arg)
		if not ok then
			warn("[Sicily] Combat request failed: " .. tostring(err))
		end
	end)
	Remotes.Get("Fire").OnServerEvent:Connect(function(player, shot)
		local ok, err = pcall(onFire, player, shot)
		if not ok then
			warn("[Sicily] Shot rejected with an error: " .. tostring(err))
		end
	end)
	Remotes.Get("AimState").OnServerEvent:Connect(onAimState)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		players[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(tick, dt)
		if not ok then
			warn("[Sicily] Combat tick failed: " .. tostring(err))
		end
	end)

	Targets.Start(townInfo, Combat)
	local _ = rng
end

-- Exposed for tests.
Combat._Test = { Players = players, OnFire = onFire, OnRequest = onRequest, OnAimState = onAimState, Tick = tick }

return Combat
