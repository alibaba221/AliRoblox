--[[
	Gunplay (client): drawing, aiming and shooting for the local player, on foot and in the saddle.

	                   Keyboard & mouse   Gamepad       Touch
	  Aim              RMB (gun out)      L2            AIM (toggles)
	  Shoot / draw     LMB                R2            FIRE (drag it to keep aiming)
	  Reload           R                  X             RELOAD
	  Pick a gun       1-5, Q             D-pad < >     GUN
	  Holster          X                  D-pad down    GUN after the last gun
	  Dead Eye         F                  R3            DEAD EYE
	  Cover            C                  R1            COVER

	Aimed shots are accurate. Hip-fire is quicker but spreads more. Moving and riding widen the
	spread, and every shot blooms it for a moment (the crosshair shows the real spread). With a
	gun out, the mouse steers the camera directly and RMB aims. With guns holstered, RMB turns the
	camera as usual and LMB draws.

	In the saddle the horse keeps its pace while you aim, and A/D steer it. Your body turns toward
	the aim while your legs stay in the stirrups.

	Everything is predicted here for instant response (draw, fire, ammo, reload, recoil and
	effects). The server (Combat) re-checks every shot and alone decides damage and ammo.
]]

local ContextActionService = game:GetService("ContextActionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Ballistics = require(Shared:WaitForChild("Ballistics"))
local Config = require(Shared:WaitForChild("Config"))
local HorseMount = require(Shared:WaitForChild("HorseMount"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local AimAssist = require(script.Parent.AimAssist)
local CameraFX = require(script.Parent.CameraFX)
local CombatHud = require(script.Parent.CombatHud)
local CombatTouch = require(script.Parent.CombatTouch)
local Cover = require(script.Parent.Cover)
local DeadEye = require(script.Parent.DeadEye)
local Riding = require(script.Parent.Riding)
local UpperBody = require(script.Parent.UpperBody)
local WeaponFX = require(script.Parent.WeaponFX)

local Gunplay = {}

local settings = Config.Combat
local KEYS = settings.Keys
local TARGET_TAG = "SicilyTarget"
local FIRE_BUFFER = 0.3 -- a trigger press waits this long for the gun to be ready
local player = Players.LocalPlayer
local rng = Random.new()

local movement = nil
local hud = nil
local combatRequest = nil
local fireRemote = nil
local aimRemote = nil

local state = {
	Character = nil :: Model?,
	Humanoid = nil :: Humanoid?,
	Root = nil :: BasePart?,
	Loadout = {} :: { string },
	Current = nil :: string?, -- the gun in hand (or being drawn / put away)
	Previous = nil :: string?, -- the gun being put away during a switch
	LastWeapon = nil :: string?, -- what fire / aim draws when nothing is out
	Phase = "Holstered", -- Holstered | Drawing | Drawn | Reloading | Holstering
	PhaseAt = 0, -- server time
	PhaseUntil = nil :: number?,
	ChangedAt = 0, -- os.clock() of our last change (the server needs a moment to catch up)
	Mismatch = 0,
	AimHeld = false,
	AimToggle = false,
	Aiming = false,
	FireHeld = false,
	FireQueued = -10,
	LastShot = -10, -- server time
	HipAimUntil = -10, -- server time
	FaceUntil = 0,
	Bloom = 0,
	Ammo = {} :: { [string]: { Mag: number, Reserve: number } },
	AmmoStableAt = 0,
	ReloadRounds = 0,
	ReloadFrom = { Mag = 0, Reserve = 0 },
	ReloadInserted = 0,
	AimPoint = nil :: Vector3?,
	AimHit = nil :: RaycastResult?,
	AimCharacter = nil :: Model?,
	Sent = { Aiming = false, Pitch = 0, Yaw = 0, At = 0 },
	Attributes = {} :: { [string]: any },
	HintKey = "",
	ToastAt = 0,
	NextCoverProbe = 0,
	CoverNearby = false,
	Connections = {} :: { RBXScriptConnection },
}
Gunplay.State = state

local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
shotParams.IgnoreWater = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function ping(): number
	return math.clamp(player:GetNetworkPing(), 0, 1)
end

local function toast(text: string)
	if hud and os.clock() - state.ToastAt > 2 then
		state.ToastAt = os.clock()
		hud.Toast(text, 2)
	end
end

local function gunOut(): boolean
	return state.Current ~= nil and state.Phase ~= "Holstered"
end

local function characterOf(instance: Instance): Model?
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- A person (not a horse, not us) that's still standing.
local function isPerson(model: Model?): boolean
	if not model or model == state.Character or model:FindFirstAncestor("SicilyHorses") then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Bullets pass through see-through / non-solid decoration, like on the server.
local function stopsBullets(part: BasePart): boolean
	if part:IsA("Terrain") or characterOf(part) then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:HasTag(TARGET_TAG) then
		return true
	end
	return part.CanCollide and part.Transparency < 0.9
end

local function ignoreList(): { Instance }
	local list = {}
	if state.Character then
		table.insert(list, state.Character)
	end
	local horse = Riding.GetHorse()
	if horse then
		table.insert(list, horse)
	end
	return list
end

local function cast(origin: Vector3, direction: Vector3, range: number): RaycastResult?
	if shotParams.CollisionGroup ~= HorseMount.ShotGroup and PhysicsService:IsCollisionGroupRegistered(HorseMount.ShotGroup) then
		shotParams.CollisionGroup = HorseMount.ShotGroup -- (bullets must also hit riders)
	end
	local ignore = ignoreList()
	local from, remaining = origin, range
	for _ = 1, 6 do
		shotParams.FilterDescendantsInstances = ignore
		local result = Workspace:Raycast(from, direction * remaining, shotParams)
		if not result then
			return nil
		end
		if stopsBullets(result.Instance) then
			return result
		end
		table.insert(ignore, result.Instance)
		remaining -= (result.Position - from).Magnitude
		from = result.Position
		if remaining <= 0.05 then
			return nil
		end
	end
	return nil
end

local function setAttribute(instance: Instance, name: string, value: any)
	if state.Attributes[name] ~= value then
		state.Attributes[name] = value
		instance:SetAttribute(name, value)
	end
end

local function ammoOf(id: string)
	local ammo = state.Ammo[id]
	if not ammo then
		local def = Weapons.Get(id)
		local mag = player:GetAttribute("Ammo_" .. id)
		local reserve = player:GetAttribute("Reserve_" .. id)
		ammo = {
			Mag = if type(mag) == "number" then mag elseif def then def.Magazine else 0,
			Reserve = if type(reserve) == "number" then reserve elseif def then def.Reserve else 0,
		}
		state.Ammo[id] = ammo
	end
	return ammo
end

local function setPhase(phase: string, duration: number?)
	state.Phase = phase
	state.PhaseAt = serverNow()
	state.PhaseUntil = if duration then state.PhaseAt + duration else nil
	state.ChangedAt = os.clock()
end

local function canUseGuns(): boolean
	local character, humanoid = state.Character, state.Humanoid
	if not character or not humanoid or humanoid.Health <= 0 or character:GetAttribute("SicilyRagdolled") then
		return false
	end
	if Riding.IsBusy() or #state.Loadout == 0 then
		return false
	end
	return character:FindFirstChild(WeaponModels.FolderName) ~= nil
end

local function loadoutEntries()
	local entries = {}
	for _, id in state.Loadout do
		local def = Weapons.Get(id)
		table.insert(entries, { Id = id, Name = if def then def.DisplayName else id })
	end
	return entries
end

-- Actions ----------------------------------------------------------------------------------------------
local function equip(id: string?)
	if not id or not table.find(state.Loadout, id) or not canUseGuns() then
		return
	end
	if state.Current == id and (state.Phase == "Drawn" or state.Phase == "Drawing") then
		return
	end
	local def = Weapons.Get(id)
	if not def then
		return
	end
	local switching = state.Current ~= nil and state.Current ~= id and state.Phase ~= "Holstered"
	local previousDef = if switching then Weapons.Get(state.Current) else nil
	state.Previous = if switching then state.Current else nil
	state.Current = id
	state.LastWeapon = id
	state.ReloadRounds = 0
	setPhase("Drawing", def.DrawTime + (if previousDef then previousDef.HolsterTime * 0.7 else 0))
	combatRequest:FireServer("Equip", id)
	WeaponFX.Draw(state.Character)
	CombatHud.ShowWeapons(loadoutEntries(), id, hud.Device() == "touch")
end

local function holster()
	if not gunOut() or state.Phase == "Holstering" then
		return
	end
	local def = Weapons.Get(state.Current)
	state.Previous = nil
	setPhase("Holstering", if def then def.HolsterTime else 0.3)
	state.AimToggle = false
	combatRequest:FireServer("Holster")
	DeadEye.Cancel()
	WeaponFX.Draw(state.Character)
end

local function reload()
	if state.Phase ~= "Drawn" or not state.Current then
		return
	end
	local id = state.Current :: string
	local def = Weapons.Get(id)
	local ammo = ammoOf(id)
	if not def or ammo.Mag >= def.Magazine then
		return
	end
	if ammo.Reserve <= 0 then
		toast("Out of ammo. Find an ammo crate at the range.")
		return
	end
	local rounds = math.min(def.Magazine - ammo.Mag, ammo.Reserve)
	state.ReloadRounds = rounds
	state.ReloadFrom = { Mag = ammo.Mag, Reserve = ammo.Reserve }
	state.ReloadInserted = 0
	setPhase("Reloading", Weapons.ReloadTime(def, rounds))
	combatRequest:FireServer("Reload")
	WeaponFX.ReloadStart(state.Character, id)
end

-- Next / previous gun (draws the last gun if nothing is out).
local function cycle(step: number)
	local count = #state.Loadout
	if count == 0 then
		return
	end
	if not gunOut() or state.Phase == "Holstering" then
		equip(state.LastWeapon or state.Loadout[1])
		return
	end
	local index = table.find(state.Loadout, state.Current :: string) or 1
	equip(state.Loadout[(index - 1 + step) % count + 1])
end

-- Spread cone (degrees, half-angle) of the next shot's centre.
local function spreadFor(def): number
	local s = def.Spread
	if DeadEye.Active() then
		return s.Aim * 0.25
	end
	local root = state.Root
	local speed = 0
	if root then
		local v = root.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local spread = (if state.Aiming then s.Aim else s.Hip) + state.Bloom
	if Riding.IsRiding() then
		spread += s.Mounted * math.clamp(speed / 24, 0.3, 1.2)
	else
		spread += s.Moving * math.clamp(speed / Config.Movement.WalkSpeed, 0, 1.4)
		local humanoid = state.Humanoid
		if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
			spread += s.Moving
		end
		if Cover.Kind() and state.Aiming then
			spread *= 0.85 -- braced on cover
		end
	end
	return spread
end

local function recoil(def)
	local r = def.Recoil
	local scale = (if state.Aiming then 1 else 0.75) * (if Riding.IsRiding() then 1.15 else 1)
	if DeadEye.Active() then
		scale *= 0.45
	end
	local yaw = (rng:NextNumber() * 2 - 1) * r.Yaw
	CameraFX.Kick(math.rad(r.Pitch) * scale, math.rad(yaw) * scale, math.rad((rng:NextNumber() * 2 - 1) * r.Roll) * scale)
	-- a little of it stays: the muzzle climbs
	CameraFX.Rotate(math.rad(yaw * 0.3) * scale, math.rad(r.Pitch * 0.22) * scale)
	CameraFX.Shake(0.04 + r.Kick * 0.12, 9)
end

--[[
	Fires one round of `def` now. `point`: fire exactly at this world point (Dead Eye) instead of
	the crosshair with spread. Returns true if a shot left the gun.
]]
local function fireShot(def, point: Vector3?): boolean
	local character, root = state.Character, state.Root
	local camera = Workspace.CurrentCamera
	local head = character and character:FindFirstChild("Head")
	if not character or not root or not camera or not head or not head:IsA("BasePart") then
		return false
	end
	local id = def.Id
	local ammo = ammoOf(id)
	local look = camera.CFrame.LookVector
	local target = point or state.AimPoint or (camera.CFrame.Position + look * def.Range)

	-- from the muzzle (kept close to the head, where the server expects it)
	local muzzle = UpperBody.Muzzle(character, id)
	local origin = if muzzle then muzzle.WorldPosition else head.Position
	-- (a barrel poking through a wall fires from our side of it)
	local fromHead = origin - head.Position
	local tooFar = fromHead.Magnitude > settings.MaxOriginDistance - 1
	if tooFar or (fromHead.Magnitude > 0.2 and cast(head.Position, fromHead.Unit, fromHead.Magnitude)) then
		origin = head.Position
	end
	local toTarget = target - origin
	local direction = if toTarget.Magnitude > 0.5 then toTarget.Unit else look
	if not point and direction:Dot(look) < 0.1 then
		direction = look
	end

	local center = if point then direction else Ballistics.Spread(direction, spreadFor(def), rng)
	local pellets, impacts = {}, {}
	local struckPerson = false
	for i = 1, def.Pellets do
		local pelletDirection = if def.Pellets > 1 then Ballistics.Spread(center, def.Spread.Pellet or 0, rng) else center
		local result = cast(origin, pelletDirection, def.Range)
		local pellet: { [string]: any } = { Direction = pelletDirection }
		if result then
			local part = result.Instance
			local victim = characterOf(part)
			if not part:IsA("Terrain") then
				pellet.Hit = part
			end
			pellet.Position = result.Position
			pellet.Normal = result.Normal
			struckPerson = struckPerson or isPerson(victim)
			table.insert(impacts, {
				Position = result.Position,
				Normal = result.Normal,
				Surface = Ballistics.Surface(result.Material.Name, victim ~= nil),
				Part = part,
			})
		else
			table.insert(impacts, { Position = origin + pelletDirection * def.Range, Surface = "Air" })
		end
		pellets[i] = pellet
	end
	fireRemote:FireServer({ Weapon = id, Origin = origin, Direction = center, Pellets = pellets })

	-- predict: ammo, timing, animation, effects, recoil
	ammo.Mag -= 1
	state.AmmoStableAt = os.clock() + 0.6 + ping() * 2
	state.LastShot = serverNow()
	local fromHip = not state.Aiming and not DeadEye.Active()
	if fromHip then
		state.HipAimUntil = state.LastShot + 0.5
		state.FaceUntil = os.clock() + 0.9
	end
	state.Bloom = math.min(def.Spread.BloomMax, state.Bloom + def.Spread.Bloom)
	UpperBody.OnShot(character, id, fromHip)
	WeaponFX.Shot(character, id, origin, impacts, true)
	recoil(def)
	if struckPerson then
		CombatHud.HitMarker("Predict")
	end
	return true
end

local function facingCamera(maxDegrees: number): boolean
	local root, camera = state.Root, Workspace.CurrentCamera
	if not root or not camera then
		return true
	end
	local a, b = root.CFrame.LookVector, camera.CFrame.LookVector
	local fa, fb = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	if fa.Magnitude < 1e-3 or fb.Magnitude < 1e-3 then
		return true
	end
	return fa.Unit:Dot(fb.Unit) >= math.cos(math.rad(maxDegrees))
end

-- One trigger press. Returns true when it's been dealt with (fired, drew, clicked empty...).
local function tryFire(): boolean
	if not canUseGuns() then
		return true
	end
	local id = state.Current
	if not id or state.Phase == "Holstered" or state.Phase == "Holstering" then
		equip(id or state.LastWeapon or state.Loadout[1])
		return true
	end
	if state.Phase == "Drawing" then
		return false
	end
	local def = Weapons.Get(id)
	if not def then
		return true
	end
	local ammo = ammoOf(id)
	if state.Phase == "Reloading" then
		if def.Reload.Kind == "PerRound" and ammo.Mag > state.ReloadFrom.Mag then
			-- stop feeding rounds and shoot (the server does the same)
			state.ReloadRounds = 0
			setPhase("Drawn")
		else
			return false
		end
	end
	if ammo.Mag <= 0 then
		WeaponFX.DryFire(state.Character, id)
		if ammo.Reserve > 0 then
			reload()
		else
			toast("Out of ammo. Find an ammo crate at the range.")
		end
		return true
	end
	local interval = if DeadEye.Active() then settings.DeadEye.ShotInterval elseif state.Aiming then def.FireInterval else def.HipFireInterval
	if serverNow() - state.LastShot < interval then
		return false
	end
	-- hip-fire on foot: turn toward the shot first
	if not state.Aiming and not Riding.IsRiding() and not facingCamera(75) then
		state.FaceUntil = os.clock() + 0.9
		return false
	end
	return fireShot(def, nil)
end

-- Dead Eye's painted shots.
local function fireAt(point: Vector3): boolean
	local id = state.Current
	local def = id and Weapons.Get(id)
	if not def or not canUseGuns() then
		return false
	end
	if state.Phase == "Reloading" and def.Reload.Kind == "PerRound" then
		state.ReloadRounds = 0
		setPhase("Drawn")
	end
	if state.Phase ~= "Drawn" or ammoOf(def.Id).Mag <= 0 then
		return false
	end
	return fireShot(def, point)
end

-- Per frame ------------------------------------------------------------------------------------------
local function updatePhase()
	local now = serverNow()
	local id = state.Current
	if state.Phase == "Drawing" and state.PhaseUntil and now >= state.PhaseUntil then
		state.Previous = nil
		setPhase("Drawn")
	elseif state.Phase == "Holstering" and state.PhaseUntil and now >= state.PhaseUntil then
		state.Current = nil
		state.Previous = nil
		setPhase("Holstered")
	elseif state.Phase == "Reloading" and id then
		local def = Weapons.Get(id)
		local ammo = ammoOf(id)
		local from = state.ReloadFrom
		if def and def.Reload.Kind == "PerRound" then
			local elapsed = now - state.PhaseAt - def.Reload.Start
			local inserted = math.clamp(math.floor(elapsed / def.Reload.PerRound), 0, state.ReloadRounds)
			if inserted > state.ReloadInserted then
				state.ReloadInserted = inserted
				WeaponFX.RoundIn(state.Character, id)
			end
			ammo.Mag = from.Mag + inserted
			ammo.Reserve = from.Reserve - inserted
			state.AmmoStableAt = os.clock() + 0.6 + ping() * 2
		end
		if state.PhaseUntil and now >= state.PhaseUntil then
			ammo.Mag = from.Mag + state.ReloadRounds
			ammo.Reserve = from.Reserve - state.ReloadRounds
			state.ReloadRounds = 0
			state.AmmoStableAt = os.clock() + 0.6 + ping() * 2
			setPhase("Drawn")
			WeaponFX.ReloadDone(state.Character, id)
		end
	end
end

-- Where the crosshair points: the first thing a bullet would hit along the camera's aim.
local function updateAimPoint(camera: Camera, def)
	local cf = camera.CFrame
	local look = cf.LookVector
	local head = state.Character and state.Character:FindFirstChild("Head")
	-- start level with the character, so nothing between the camera and us gets in the way
	local skip = if head and head:IsA("BasePart") then math.max(0, (head.Position - cf.Position):Dot(look)) else 0
	local start = cf.Position + look * skip
	local range = if def then def.Range else 250
	local hit = cast(start, look, range)
	state.AimHit = hit
	state.AimPoint = if hit then hit.Position else start + look * range
	state.AimCharacter = if hit then characterOf(hit.Instance) else nil
end

local function processTrigger()
	local now = os.clock()
	if now - state.FireQueued < FIRE_BUFFER then
		local handled = false
		if DeadEye.Active() and not DeadEye.Executing() then
			handled = DeadEye.TryMark(state.AimHit)
		end
		if not handled then
			handled = tryFire()
		end
		if handled then
			state.FireQueued = -10
		end
	elseif state.FireHeld and state.Phase == "Drawn" and state.Current and not DeadEye.Active() then
		-- holding the trigger keeps firing at the gun's pace
		local def = Weapons.Get(state.Current)
		if def and ammoOf(def.Id).Mag > 0 then
			local interval = (if state.Aiming then def.FireInterval else def.HipFireInterval) + 0.08
			if serverNow() - state.LastShot >= interval then
				state.FireQueued = now
			end
		end
	end
end

local function updateCamera(def, riding: boolean, device: string)
	local out = gunOut() and def ~= nil
	if out then
		CameraFX.SetAim(if state.Aiming then 1 else 0, {
			Shoulder = if riding then Vector3.new(2.3, 1.1, 0) else Vector3.new(1.9, 0.4, 0),
			Distance = def.AimDistance + (if riding then 2.6 else 0),
			FOV = def.AimFOV + (if riding then 8 else 0),
			Mounted = riding,
		})
	else
		CameraFX.SetAim(0)
	end
	CameraFX.SetReady(if out then 1 else 0)
	CameraFX.SetMouseLocked(out and device == "keyboard")
end

local function updateMovement(humanoid: Humanoid, camera: Camera, riding: boolean)
	local deadEye = DeadEye.Active()
	setAttribute(humanoid, "SpeedMultiplier", if deadEye then settings.DeadEye.SlowWalk elseif state.Aiming then 0.55 else nil)
	setAttribute(humanoid, "NoSprint", if state.Aiming or deadEye then true else nil)
	local face = nil
	if not riding then
		if state.Aiming or deadEye or os.clock() < state.FaceUntil then
			local look = camera.CFrame.LookVector
			if Vector3.new(look.X, 0, look.Z).Magnitude > 1e-3 then
				face = math.atan2(-look.X, -look.Z)
			end
		else
			face = Cover.FaceYaw()
		end
	end
	setAttribute(humanoid, "FaceYaw", face)
end

-- Other players see where we aim (a few times a second is plenty).
local function replicateAim()
	local now = os.clock()
	local sent = state.Sent
	local out = gunOut()
	local aiming = state.Aiming or DeadEye.Executing()
	if not out then
		if sent.Aiming then
			sent.Aiming, sent.At = false, now
			aimRemote:FireServer(false, sent.Pitch, sent.Yaw)
		end
		return
	end
	local pitch, yaw = sent.Pitch, sent.Yaw
	local head = state.Character and state.Character:FindFirstChild("Head")
	if state.AimPoint and head and head:IsA("BasePart") then
		local d = state.AimPoint - head.Position
		if d.Magnitude > 0.5 then
			d = d.Unit
			pitch = math.asin(math.clamp(d.Y, -1, 1))
			yaw = math.atan2(-d.X, -d.Z)
		end
	end
	local turned = math.abs((yaw - sent.Yaw + math.pi) % (2 * math.pi) - math.pi)
	local changed = aiming ~= sent.Aiming or math.abs(pitch - sent.Pitch) > 0.03 or turned > 0.03
	if (changed and now - sent.At > 1 / 12) or now - sent.At > 1 then
		sent.Aiming, sent.Pitch, sent.Yaw, sent.At = aiming, pitch, yaw, now
		aimRemote:FireServer(aiming, pitch, yaw)
	end
end

-- If the server consistently disagrees with us (a request it refused), go with the server.
local function reconcile()
	local character = state.Character
	if not character or os.clock() - state.ChangedAt < 0.45 + ping() * 2 then
		state.Mismatch = 0
		return
	end
	local serverPhase = character:GetAttribute("WeaponState")
	local serverWeapon = character:GetAttribute("Weapon")
	if type(serverPhase) ~= "string" then
		return
	end
	local weapon = if type(serverWeapon) == "string" and serverWeapon ~= "" then serverWeapon else nil
	if serverPhase == state.Phase and (weapon == state.Current or serverPhase == "Holstered") then
		state.Mismatch = 0
		return
	end
	state.Mismatch += 1
	if state.Mismatch < 4 then
		return
	end
	state.Mismatch = 0
	local def = Weapons.Get(weapon)
	state.Current = weapon
	state.Previous = nil
	state.Phase = serverPhase
	state.PhaseAt = character:GetAttribute("WeaponStateAt") or serverNow()
	state.ReloadRounds = character:GetAttribute("ReloadRounds") or 0
	state.PhaseUntil = nil
	if def then
		if serverPhase == "Drawing" then
			state.PhaseUntil = state.PhaseAt + def.DrawTime
		elseif serverPhase == "Holstering" then
			state.PhaseUntil = state.PhaseAt + def.HolsterTime
		elseif serverPhase == "Reloading" then
			state.PhaseUntil = state.PhaseAt + Weapons.ReloadTime(def, math.max(state.ReloadRounds, 1))
			local ammo = ammoOf(def.Id)
			state.ReloadFrom = { Mag = ammo.Mag, Reserve = ammo.Reserve }
			state.ReloadInserted = 0
		end
		state.LastWeapon = def.Id
	end
	state.AmmoStableAt = 0
end

local function reconcileAmmo()
	if os.clock() < state.AmmoStableAt or state.Phase == "Reloading" then
		return
	end
	for _, id in state.Loadout do
		local mag = player:GetAttribute("Ammo_" .. id)
		local reserve = player:GetAttribute("Reserve_" .. id)
		if type(mag) == "number" and type(reserve) == "number" then
			local ammo = ammoOf(id)
			ammo.Mag, ammo.Reserve = mag, reserve
		end
	end
end

local function refreshHints(riding: boolean)
	local out = gunOut() and state.Phase ~= "Holstering"
	local key = tostring(out) .. tostring(riding) .. tostring(Cover.Kind())
	if key == state.HintKey then
		return
	end
	state.HintKey = key
	if not out then
		hud.SetContext("Guns", 0, nil)
		return
	end
	local rows = {
		{ Keys = { Keyboard = "RMB", Gamepad = "L2" }, Action = "Aim" },
		{ Keys = { Keyboard = "LMB", Gamepad = "R2" }, Action = "Shoot" },
		{ Keys = { Keyboard = "R", Gamepad = "X" }, Action = "Reload" },
		{ Keys = { Keyboard = "1-5 / Q", Gamepad = "D-PAD" }, Action = "Switch gun" },
		{ Keys = { Keyboard = "X", Gamepad = "D-PAD DOWN" }, Action = "Holster" },
	}
	if settings.DeadEye.Enabled then
		table.insert(rows, { Keys = { Keyboard = "F", Gamepad = "R3" }, Action = "Dead Eye" })
	end
	if riding then
		table.insert(rows, 1, { Keys = { Keyboard = "A / D", Gamepad = "L-STICK" }, Action = "Steer while aiming" })
	elseif settings.Cover.Enabled then
		table.insert(rows, { Keys = { Keyboard = "C", Gamepad = "R1" }, Action = if Cover.Kind() then "Leave cover" else "Take cover" })
	end
	hud.SetContext("Guns", 20, rows)
end

local function updateTouch(device: string, riding: boolean)
	local touch = device == "touch" and #state.Loadout > 0
	CombatTouch.SetEnabled(touch)
	if not touch then
		return
	end
	local out = gunOut()
	CombatTouch.SetVisible("Reload", out)
	CombatTouch.SetVisible("DeadEye", out and settings.DeadEye.Enabled)
	CombatTouch.SetActive("Aim", state.AimToggle)
	CombatTouch.SetActive("DeadEye", DeadEye.Active())
	CombatTouch.SetActive("Cover", Cover.Kind() ~= nil)
	-- COVER only shows up next to something you can hide behind
	if os.clock() >= state.NextCoverProbe then
		state.NextCoverProbe = os.clock() + 0.25
		local camera = Workspace.CurrentCamera
		local look = if camera then Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z) else Vector3.zero
		state.CoverNearby = settings.Cover.Enabled
			and not riding
			and state.Character ~= nil
			and state.Root ~= nil
			and look.Magnitude > 1e-3
			and Cover.Probe(state.Character :: Model, state.Root :: BasePart, look.Unit) ~= nil
	end
	CombatTouch.SetVisible("Cover", Cover.Kind() ~= nil or state.CoverNearby)
end

local function step(dt: number)
	local character, humanoid, root = state.Character, state.Humanoid, state.Root
	local camera = Workspace.CurrentCamera
	if not character or not humanoid or not root or not camera or not character.Parent then
		return
	end
	local device = hud.Device()
	local riding = Riding.IsRiding()
	local alive = humanoid.Health > 0

	updatePhase()
	-- hands busy with the horse (climbing on or off, taming): put the gun away
	if Riding.IsBusy() and gunOut() and state.Phase ~= "Holstering" then
		holster()
	end

	-- aiming (gamepad / touch aim draws your gun; with a mouse, RMB only aims a drawn gun)
	local wantsAim = (state.AimHeld or state.AimToggle) and alive
	if wantsAim and (not gunOut() or state.Phase == "Holstering") and device ~= "keyboard" then
		equip(state.Current or state.LastWeapon or state.Loadout[1])
	end
	local wasAiming = state.Aiming
	state.Aiming = (wantsAim and gunOut() and state.Phase ~= "Holstering" and not Riding.IsBusy()) or DeadEye.Executing()
	local def = if state.Current then Weapons.Get(state.Current) else nil
	local ignore = ignoreList()
	local strength = AimAssist.Strength(device, def)
	if state.Aiming and not wasAiming then
		AimAssist.OnAimStart(camera, strength, ignore)
	end
	AimAssist.Update(dt, camera, strength, state.Aiming and not DeadEye.Executing(), ignore)

	updateAimPoint(camera, def)
	DeadEye.Update(dt, wantsAim)
	Cover.Update(dt, character, root, humanoid, riding)
	processTrigger()
	if def then
		state.Bloom = math.max(0, state.Bloom - def.Spread.Recovery * dt)
	end

	updateCamera(def, riding, device)
	updateMovement(humanoid, camera, riding)
	Riding.SetAiming(riding and state.Aiming)
	replicateAim()
	reconcileAmmo()
	refreshHints(riding)
	updateTouch(device, riding)

	local ammo = if def then ammoOf(def.Id) else nil
	local reloadProgress = nil
	if state.Phase == "Reloading" and state.PhaseUntil then
		reloadProgress = (serverNow() - state.PhaseAt) / math.max(state.PhaseUntil - state.PhaseAt, 0.05)
	end
	CombatHud.Update({
		Visible = gunOut() and state.Phase ~= "Holstering" and not Riding.IsBusy() and alive,
		Aiming = state.Aiming,
		Spread = if def then spreadFor(def) + (def.Spread.Pellet or 0) else 0,
		OverTarget = isPerson(state.AimCharacter),
		Def = def,
		Mag = if ammo then ammo.Mag else 0,
		Reserve = if ammo then ammo.Reserve else 0,
		Reload = reloadProgress,
		DeadEye = DeadEye.Meter(),
		DeadEyeMax = settings.DeadEye.Max,
		DeadEyeActive = DeadEye.Active(),
		DeadEyeEnabled = settings.DeadEye.Enabled,
		Touch = device == "touch",
	}, dt)
end

-- Input ---------------------------------------------------------------------------------------------
local SINK = Enum.ContextActionResult.Sink
local PASS = Enum.ContextActionResult.Pass

local function began(inputState: Enum.UserInputState): boolean
	return inputState == Enum.UserInputState.Begin
end

local function onAim(_: string, inputState: Enum.UserInputState, input: InputObject)
	if began(inputState) then
		-- RMB turns the camera as usual while guns are holstered
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not gunOut() then
			return PASS
		end
		state.AimHeld = true
		return SINK
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		local held = state.AimHeld
		state.AimHeld = false
		return if held then SINK else PASS
	end
	return PASS
end

local function onFire(_: string, inputState: Enum.UserInputState)
	if began(inputState) then
		if #state.Loadout == 0 or not state.Character then
			return PASS
		end
		state.FireHeld = true
		state.FireQueued = os.clock()
		return SINK
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		state.FireHeld = false
	end
	return PASS
end

local function onReload(_: string, inputState: Enum.UserInputState)
	if began(inputState) and gunOut() then
		reload()
		return SINK
	end
	return PASS
end

local function onHolster(_: string, inputState: Enum.UserInputState)
	if began(inputState) and gunOut() then
		holster()
		return SINK
	end
	return PASS
end

local function onNext(_: string, inputState: Enum.UserInputState)
	if began(inputState) and #state.Loadout > 0 and canUseGuns() then
		cycle(1)
		return SINK
	end
	return PASS
end

local function onPrevious(_: string, inputState: Enum.UserInputState)
	if began(inputState) and #state.Loadout > 0 and canUseGuns() then
		cycle(-1)
		return SINK
	end
	return PASS
end

local function onSlot(_: string, inputState: Enum.UserInputState, input: InputObject)
	if not began(inputState) then
		return PASS
	end
	local index = table.find(KEYS.Slots, input.KeyCode)
	local id = index and state.Loadout[index]
	if not id then
		return PASS
	end
	if state.Current == id and gunOut() and state.Phase ~= "Holstering" then
		holster() -- the same number again puts it away
	else
		equip(id)
	end
	return SINK
end

local function onDeadEye(_: string, inputState: Enum.UserInputState)
	if not began(inputState) then
		return PASS
	end
	local ready = gunOut() and (state.Phase == "Drawn" or state.Phase == "Reloading") and canUseGuns()
	return if DeadEye.Toggle(ready) then SINK else PASS
end

local function onCover(_: string, inputState: Enum.UserInputState)
	if not began(inputState) or not settings.Cover.Enabled or Riding.IsRiding() then
		return PASS
	end
	local character, root, camera = state.Character, state.Root, Workspace.CurrentCamera
	if not character or not root or not camera then
		return PASS
	end
	return if Cover.Toggle(character, root, camera.CFrame.LookVector) then SINK else PASS
end

local function bindInput()
	local priority = Enum.ContextActionPriority.High.Value
	local function bind(name: string, handler, keys: { any })
		ContextActionService:BindActionAtPriority(name, handler, false, priority, table.unpack(keys))
	end
	bind("SicilyAim", onAim, KEYS.Aim)
	bind("SicilyFire", onFire, KEYS.Fire)
	bind("SicilyReload", onReload, KEYS.Reload)
	bind("SicilyHolster", onHolster, KEYS.Holster)
	bind("SicilyNextGun", onNext, KEYS.NextWeapon)
	bind("SicilyPreviousGun", onPrevious, KEYS.PreviousWeapon)
	bind("SicilyGunSlot", onSlot, KEYS.Slots)
	if settings.DeadEye.Enabled then
		bind("SicilyDeadEye", onDeadEye, KEYS.DeadEye)
	end
	if settings.Cover.Enabled then
		bind("SicilyCover", onCover, KEYS.Cover)
	end
	UserInputService.WindowFocusReleased:Connect(function()
		state.AimHeld = false
		state.FireHeld = false
	end)

	CombatTouch.Build(hud.GetGui(), {
		Fire = function(down: boolean)
			state.FireHeld = down
			if down then
				state.FireQueued = os.clock()
			end
		end,
		Aim = function()
			state.AimToggle = not state.AimToggle
		end,
		Gun = function()
			-- next gun, or holster after the last one
			if not canUseGuns() then
				return
			end
			if not gunOut() or state.Phase == "Holstering" then
				equip(state.LastWeapon or state.Loadout[1])
				return
			end
			local index = table.find(state.Loadout, state.Current :: string) or 0
			if index >= #state.Loadout then
				holster()
			else
				equip(state.Loadout[index + 1])
			end
		end,
		Reload = reload,
		DeadEye = function()
			DeadEye.Toggle(gunOut() and (state.Phase == "Drawn" or state.Phase == "Reloading") and canUseGuns())
		end,
		Cover = function()
			local camera = Workspace.CurrentCamera
			if state.Character and state.Root and camera and not Riding.IsRiding() then
				Cover.Toggle(state.Character, state.Root, camera.CFrame.LookVector)
			end
		end,
	})
end

-- Server events -------------------------------------------------------------------------------------
local function onCombatEvent(kind: string, ...)
	if kind == "Flinch" then
		WeaponFX.Flinch(...)
	elseif kind == "Hit" then
		local _, head, killed = ...
		local marker = if killed then "Kill" elseif head then "Head" else "Hit"
		CombatHud.HitMarker(marker)
		WeaponFX.HitConfirm(marker)
	elseif kind == "Damaged" then
		local from, amount = ...
		if typeof(from) == "Vector3" and type(amount) == "number" then
			CombatHud.Damaged(from, amount)
			CameraFX.Shake(math.clamp(amount / 80, 0.1, 0.5), 5)
		end
	elseif kind == "Rejected" then
		-- the server didn't take a shot: take its word for the ammo straight away
		state.AmmoStableAt = 0
		state.Mismatch = math.max(state.Mismatch, 2)
	end
end

-- Characters ------------------------------------------------------------------------------------------
local function resetState()
	state.Current, state.Previous = nil, nil
	state.Phase, state.PhaseAt, state.PhaseUntil = "Holstered", 0, nil
	state.AimHeld, state.AimToggle, state.Aiming = false, false, false
	state.FireHeld, state.FireQueued = false, -10
	state.Bloom, state.ReloadRounds = 0, 0
	state.AimPoint, state.AimHit, state.AimCharacter = nil, nil, nil
	state.HintKey = ""
	table.clear(state.Ammo)
	table.clear(state.Attributes)
	DeadEye.Cancel()
	Cover.Exit()
	CameraFX.SetAim(0)
	CameraFX.SetReady(0)
	CameraFX.SetMouseLocked(false)
	if hud then
		hud.SetContext("Guns", 0, nil)
	end
end

local function onCharacter(character: Model)
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	table.clear(state.Connections)
	resetState()
	state.Character = character
	state.Loadout = {}
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") or player.Character ~= character then
		return
	end
	state.Humanoid, state.Root = humanoid, root
	local function readLoadout()
		local list = {}
		local raw = character:GetAttribute("Loadout")
		if type(raw) == "string" then
			for _, id in string.split(raw, ",") do
				if Weapons.Get(id) then
					table.insert(list, id)
				end
			end
		end
		state.Loadout = list
		if state.LastWeapon and not table.find(list, state.LastWeapon) then
			state.LastWeapon = nil
		end
	end
	readLoadout()
	table.insert(state.Connections, character:GetAttributeChangedSignal("Loadout"):Connect(readLoadout))
	table.insert(state.Connections, humanoid.Died:Connect(resetState))
end

function Gunplay.Start(movementModule, hudModule)
	if not settings.Enabled then
		return
	end
	movement = movementModule
	hud = hudModule
	combatRequest = Remotes.Get("CombatRequest")
	fireRemote = Remotes.Get("Fire")
	aimRemote = Remotes.Get("AimState")

	local gui = hud.GetGui()
	CombatHud.Build(gui)
	DeadEye.Start(gui, {
		Request = function(active: boolean)
			combatRequest:FireServer("DeadEye", active)
		end,
		Fire = fireAt,
		Rounds = function(): number
			return if state.Current then ammoOf(state.Current).Mag else 0
		end,
		Toast = toast,
	})
	Cover.Start(movement, function(kind: string?)
		combatRequest:FireServer("Cover", kind)
	end)
	local source = {}
	UpperBody.SetLocalSource(function()
		source.Current = state.Current
		source.Phase = state.Phase
		source.PhaseAt = state.PhaseAt
		source.Previous = state.Previous
		source.Aiming = state.Aiming
		source.ReloadRounds = state.ReloadRounds
		source.AimPoint = state.AimPoint
		source.HipAimUntil = state.HipAimUntil
		source.Cover = Cover.Kind()
		return source
	end)
	bindInput()

	Remotes.Get("CombatEvent").OnClientEvent:Connect(function(kind, ...)
		local ok, err = pcall(onCombatEvent, kind, ...)
		if not ok then
			warn("[Sicily] Combat event failed: " .. tostring(err))
		end
	end)
	Remotes.Get("ShotFX").OnClientEvent:Connect(function(shooter, weaponId, origin, impacts)
		if typeof(shooter) == "Instance" and shooter:IsA("Player") and type(weaponId) == "string" then
			local ok, err = pcall(WeaponFX.RemoteShot, shooter, weaponId, origin, impacts)
			if not ok then
				warn("[Sicily] Shot effect failed: " .. tostring(err))
			end
		end
	end)

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	local warned = false
	RunService:BindToRenderStep("SicilyGunplay", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not warned then
			warned = true
			warn("[Sicily] Gunplay update failed: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			pcall(reconcile)
		end
	end)
end

return Gunplay
