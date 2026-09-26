--[[
	UpperBody (client): the gun layer of the procedural animator. It runs for every R6 rig on top
	of the locomotion pose (legs keep walking / riding underneath).

	  * Guns sit in their holsters until drawn. Drawing reaches for the grip and brings the gun up
	    in the hand. The cross-draw pistol on the left hip is handed from the left hand to the
	    right. Holstering plays the same motion backwards, and a switch does both.
	  * Drawn: low ready, blending into a proper aim that follows where the player aims (a bladed
	    stance for long guns). Hip-fire snaps the gun up for a moment.
	  * Recoil kick, plus the moving parts: revolver hammer and cylinder, pistol bolt, lever action,
	    bolt action, break-action shotgun.
	  * Reloads by type: rounds into a revolver or the repeater's gate, a stripper clip, shells into
	    the broken-open shotgun. The free hand fetches each round from the belt.
	  * The torso turns toward the aim while the legs stay put, which keeps a rider's legs on the
	    horse.
	  * Hit reactions for every rig (by body part and bullet direction), and a crouch behind low
	    cover.

	The local player's state comes from Gunplay (instant). Everyone else's comes from the
	character attributes the server sets (Weapon, WeaponState, WeaponStateAt, PreviousWeapon,
	Aiming, AimPitch, AimYaw, ReloadRounds, Cover).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local AimRig = require(Shared:WaitForChild("AimRig"))
local R6 = require(Shared:WaitForChild("R6"))
local Spring = require(Shared:WaitForChild("Spring"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local UpperBody = {}

local JOINTS = {}
for _, joint in R6.Joints do
	JOINTS[joint.Name] = joint
end
local ROOT_C0, ROOT_C1 = JOINTS.RootJoint.C0, JOINTS.RootJoint.C1
local RIGHT_HIP_C0, LEFT_HIP_C0 = JOINTS["Right Hip"].C0, JOINTS["Left Hip"].C0
local SHOULDER = AimRig.RightPivot -- where the aim is measured from (Torso space)
local IDENTITY = CFrame.new()
local UP = Vector3.new(0, 1, 0)
local FRONT = Vector3.new(0, 0, -1)
local REACH = 0.3 -- share of a draw spent reaching for the holster
local MAX_TWIST = 1.5
-- where a cross-drawn pistol changes hands (in front of the belly, muzzle down)
local HANDOFF = CFrame.new(0, -0.35, -0.95) * CFrame.Angles(math.rad(-50), 0, 0)
-- where the free hand fetches rounds: the belt loops (sidearms) or the bandolier (long guns)
local BELT = Vector3.new(-0.62, -0.86, -0.62)
local BANDOLIER = Vector3.new(-0.4, 0.55, -0.62)
local CROUCH_DROP = 0.9
local CROUCH_LEG = math.acos(1 - CROUCH_DROP / 2) -- leg angle that keeps the feet on the ground
local CROUCH_LEAN = 0.22

local states = setmetatable({}, { __mode = "k" }) -- [character] = layer state
local localSource: (() -> any)? = nil
local clock = function(): number
	return Workspace:GetServerTimeNow()
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- Gunplay hands us a function returning the local player's weapon state every frame:
-- { Current, Phase, PhaseAt, Previous, Aiming, ReloadRounds, AimPoint, HipAimUntil, Cover }
function UpperBody.SetLocalSource(fn: () -> any)
	localSource = fn
end

-- Tests drive time themselves.
function UpperBody._SetClock(fn: () -> number)
	clock = fn
end

local function stateFor(character: Model)
	local state = states[character]
	if not state then
		state = {
			Weapons = {},
			Count = -1,
			Aim = 0,
			HipAim = 0,
			HipAimUntil = -10,
			Twist = 0,
			Weight = 0,
			Crouch = 0,
			Kick = Spring.new(0, 4.5, 0.55),
			Flinch = Spring.new(Vector3.zero, 3.4, 0.42), -- torso (pitch, twist, roll)
			FlinchHead = Spring.new(0, 4, 0.4),
			FlinchLimbs = Spring.new(Vector3.zero, 3.6, 0.45), -- (right arm, left arm, legs)
			LastShot = -10,
			Shots = 0,
			Cylinder = 0,
			AimDirection = nil :: Vector3?,
		}
		states[character] = state
	end
	return state
end

-- Where the right hand takes a holstered gun: pistols by the grip; long guns off the back by the
-- body of the gun, where a straight R6 arm actually reaches.
local function grabPoint(def, holster: CFrame): Vector3
	if def.Hold ~= "Long" then
		return holster.Position
	end
	local best, bestError = holster.Position, math.huge
	for i = 0, 24 do
		local point = holster:PointToWorldSpace(Vector3.new(0, 0, -i * 0.05))
		local reachError = math.abs((point - AimRig.RightPivot).Magnitude - AimRig.ArmReach)
		if reachError < bestError then
			best, bestError = point, reachError
		end
	end
	return best
end

local function weaponsOf(state, character: Model)
	local folder = character:FindFirstChild(WeaponModels.FolderName)
	local count = if folder then #folder:GetChildren() else 0
	if folder ~= state.Folder or count ~= state.Count then
		state.Folder = folder
		state.Count = count
		state.Weapons = {}
		if folder then
			for _, model in folder:GetChildren() do
				local id = model:GetAttribute("WeaponId")
				local handle = model:IsA("Model") and model.PrimaryPart
				local joint = handle and handle:FindFirstChild(WeaponModels.JointName)
				local def = Weapons.Get(id)
				if def and joint and joint:IsA("Motor6D") then
					local support = handle:FindFirstChild("Support")
					state.Weapons[id] = {
						Def = def,
						Model = model,
						Joint = joint,
						Holster = joint.C0,
						Grab = grabPoint(def, joint.C0),
						Movers = WeaponModels.GetMovers(model),
						Support = if support and support:IsA("Attachment") then support.Position else nil,
					}
				end
			end
		end
	end
	return state.Weapons
end

-- A shot was fired by this character (local prediction, or someone else's ShotFX).
function UpperBody.OnShot(character: Model, weaponId: string, fromHip: boolean)
	local state = stateFor(character)
	local def = Weapons.Get(weaponId)
	state.LastShot = clock()
	state.Shots += 1
	if fromHip then
		state.HipAimUntil = clock() + 0.5
	end
	state.Kick:Impulse((if def then def.Recoil.Kick else 0.25) * 24)
end

--[[
	Hit reaction. direction: the bullet's travel direction (world); strength ~0.3..1.4.
	The torso rocks away from the hit, a hit limb is knocked back, head shots snap the head.
]]
function UpperBody.Flinch(character: Model, partName: string, direction: Vector3, strength: number)
	local state = stateFor(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local d = root.CFrame:VectorToObjectSpace(direction)
	local k = math.clamp(strength, 0.2, 1.6) * 7
	-- d.Z > 0: the bullet travels backwards through us, i.e. it came from the front
	state.Flinch:Impulse(Vector3.new(-d.Z * 0.6, -d.X * 0.5, d.X * 0.35) * k)
	if partName == "Head" then
		state.FlinchHead:Impulse(-(math.abs(d.Z) + 0.3) * k * 1.4)
	elseif partName == "Right Arm" then
		state.FlinchLimbs:Impulse(Vector3.new(k * 1.6, 0, 0))
	elseif partName == "Left Arm" then
		state.FlinchLimbs:Impulse(Vector3.new(0, k * 1.6, 0))
	elseif partName == "Right Leg" or partName == "Left Leg" then
		state.FlinchLimbs:Impulse(Vector3.new(0, 0, k * (if partName == "Right Leg" then 1 else -1)))
	end
end

-- Poses ---------------------------------------------------------------------------------------------------

-- The gun's CFrame in the hand's grip frame, turning from hold `a` to hold `b` while the hand
-- slides along the gun between the two (so it never lets go of it).
local function slide(a: CFrame, b: CFrame, k: number): CFrame
	local rotation = a.Rotation:Lerp(b.Rotation, k)
	local held = a:PointToObjectSpace(Vector3.zero):Lerp(b:PointToObjectSpace(Vector3.zero), k)
	return CFrame.new(-rotation:VectorToWorldSpace(held)) * rotation
end

--[[
	The drawn pose (Torso space): low ready blended into the aim by `w`. The gun always stays in
	the right hand; the left hand comes onto a long gun's fore-end as it comes up.
	Returns { Gun, Right, Left?, LeftWeight } (Handle CFrame and shoulder Transforms).
]]
local function drawnPose(weapon, aimTorso: Vector3, w: number, swing: number)
	local def = weapon.Def
	local k = smooth(w)
	if def.Hold == "Pistol" then
		local _, readyRight = AimRig.Ready("Pistol", nil, swing)
		local _, aimRight = AimRig.Aim("Pistol", aimTorso)
		local right = readyRight:Lerp(aimRight, k)
		return { Gun = AimRig.GripFrame(right), Right = right, LeftWeight = 0 }
	end
	local readyGun, readyRight = AimRig.Ready("Long", weapon.Support, swing)
	local aimGun, aimRight = AimRig.Aim("Long", aimTorso, weapon.Support)
	local right = readyRight:Lerp(aimRight, k)
	local readyHold = AimRig.GripFrame(readyRight):Inverse() * readyGun
	local aimHold = AimRig.GripFrame(aimRight):Inverse() * aimGun
	local gun = AimRig.GripFrame(right) * slide(readyHold, aimHold, k)
	return {
		Gun = gun,
		Right = right,
		Left = AimRig.Reach("Left", AimRig.SupportPoint(gun, weapon.Support), gun.UpVector),
		LeftWeight = k,
	}
end

--[[
	Drawing (u: 0 -> 1 is holster -> target; holstering plays u backwards). The hand reaches for
	the grip, then the gun travels in the hand while the wrist turns it from its holstered angle
	to the target's. Returns { Gun, Right, RightWeight, Left, LeftWeight }.
]]
local function drawPath(weapon, u: number, target)
	local holster = weapon.Holster
	if weapon.Def.Holster == "HipLeft" then
		-- cross-draw: the left hand pulls it out and hands it over
		local grabLeft = AimRig.Reach("Left", holster.Position, FRONT)
		if u < 0.25 then
			return { Gun = holster, Left = grabLeft, LeftWeight = smooth(u / 0.25), RightWeight = 0 }
		end
		local rightAtHandoff = AimRig.Reach("Right", HANDOFF.Position, UP)
		if u < 0.55 then
			local v = smooth((u - 0.25) / 0.3)
			local gun = holster:Lerp(HANDOFF, v)
			return {
				Gun = gun,
				Left = AimRig.Reach("Left", gun.Position, FRONT),
				LeftWeight = 1,
				Right = rightAtHandoff,
				RightWeight = v,
			}
		end
		local v = smooth((u - 0.55) / 0.45)
		local startOffset = AimRig.GripFrame(rightAtHandoff):Inverse() * HANDOFF
		local endOffset = AimRig.GripFrame(target.Right):Inverse() * target.Gun
		local right = rightAtHandoff:Lerp(target.Right, v)
		local gun = AimRig.GripFrame(right) * slide(startOffset, endOffset, v)
		local left, leftWeight = AimRig.Reach("Left", HANDOFF.Position, FRONT), 1 - smooth((u - 0.55) / 0.2)
		if target.Left and target.LeftWeight > 0 then
			local support = AimRig.Reach("Left", AimRig.SupportPoint(gun, weapon.Support), gun.UpVector)
			local k = smooth((u - 0.7) / 0.3)
			left = left:Lerp(support, k)
			leftWeight = leftWeight + (target.LeftWeight - leftWeight) * k
		end
		return { Gun = gun, Right = right, RightWeight = 1, Left = left, LeftWeight = leftWeight }
	end

	local grab = AimRig.Reach("Right", weapon.Grab or holster.Position, FRONT)
	if u < REACH then
		return { Gun = holster, Right = grab, RightWeight = smooth(u / REACH), LeftWeight = 0 }
	end
	local v = smooth((u - REACH) / (1 - REACH))
	local startOffset = AimRig.GripFrame(grab):Inverse() * holster
	local endOffset = AimRig.GripFrame(target.Right):Inverse() * target.Gun
	local right = grab:Lerp(target.Right, v)
	local gun = AimRig.GripFrame(right) * slide(startOffset, endOffset, smooth((u - REACH) / 0.45))
	local left, leftWeight = nil, 0
	if target.Left then
		leftWeight = smooth((u - 0.68) / 0.32) * target.LeftWeight
		left = AimRig.Reach("Left", AimRig.SupportPoint(gun, weapon.Support), gun.UpVector)
	end
	return { Gun = gun, Right = right, RightWeight = 1, Left = left, LeftWeight = leftWeight }
end

-- Reload hold per gun model: where the right arm points, the wrist turn, where the rounds go.
local RELOAD_HOLDS = {
	Revolver = {
		Arm = Vector3.new(0.3, -0.35, -1.25),
		Wrist = CFrame.Angles(math.rad(55), 0, math.rad(-30)),
		Work = Vector3.new(0.14, 0.16, -0.26),
		Fetch = BELT,
	},
	Pistol = {
		Arm = Vector3.new(0.3, -0.3, -1.25),
		Wrist = CFrame.Angles(math.rad(25), 0, 0),
		Work = Vector3.new(0, 0.48, -0.08),
		Fetch = BELT,
	},
	Repeater = {
		Arm = Vector3.new(0.65, -0.55, -1.05),
		Wrist = CFrame.Angles(math.rad(60), math.rad(25), 0),
		Work = Vector3.new(0.16, 0.08, -0.38),
		Fetch = BANDOLIER,
	},
	Rifle = {
		Arm = Vector3.new(0.6, -0.5, -1.1),
		Wrist = CFrame.Angles(math.rad(45), math.rad(20), 0),
		Work = Vector3.new(0, 0.46, -0.3),
		Fetch = BELT, -- clips come from the belt pouch
	},
	Shotgun = {
		Arm = Vector3.new(0.55, -0.6, -1.05),
		Wrist = CFrame.Angles(math.rad(8), math.rad(15), 0),
		Work = Vector3.new(0, 0.15, -0.36),
		Fetch = BELT,
	},
}

-- Reload pose { Gun, Right, Left }: the gun held up in the right hand, the left hand fetching rounds.
local function reloadPose(weapon, elapsed: number, rounds: number)
	local def = weapon.Def
	local hold = RELOAD_HOLDS[def.Model] or RELOAD_HOLDS.Revolver
	local right = AimRig.Reach("Right", hold.Arm, UP)
	local gun = AimRig.GripFrame(right) * hold.Wrist
	local r = def.Reload
	local fetch = 0
	if r.Kind == "PerRound" then
		local inRounds = elapsed - r.Start
		if inRounds > 0 and inRounds < r.PerRound * rounds then
			fetch = math.sin((inRounds % r.PerRound) / r.PerRound * math.pi)
		end
	else
		fetch = math.sin(math.clamp((elapsed / math.max(r.Time, 0.1) - 0.15) / 0.55, 0, 1) * math.pi)
	end
	local work = gun:PointToWorldSpace(hold.Work)
	return { Gun = gun, Right = right, Left = AimRig.Reach("Left", work:Lerp(hold.Fetch, fetch * 0.9), UP) }
end

local function blendPose(a, b, t: number)
	return {
		Gun = a.Gun:Lerp(b.Gun, t),
		Right = a.Right:Lerp(b.Right, t),
		Left = if a.Left and b.Left then a.Left:Lerp(b.Left, t) else (b.Left or a.Left),
	}
end

-- Layer -----------------------------------------------------------------------------------------------

--[[
	Applies the layer to one rig. `t` holds this frame's Transforms (RootJoint, Neck,
	RightShoulder, LeftShoulder, RightHip, LeftHip) and is modified in place.
	context = { Root (HRP CFrame), Riding (table?), IsLocal, Walk (0..1), Phase (step phase) }
]]
function UpperBody.Apply(rig, dt: number, t, context)
	local character: Model = rig.Model
	local state = stateFor(character)
	local now = clock()

	-- Hit reactions (every rig) -----------------------------------------------------------------------
	local flinch = state.Flinch:Step(dt)
	local flinchHead = state.FlinchHead:Step(dt)
	local flinchLimbs = state.FlinchLimbs:Step(dt)
	if flinch.Magnitude > 1e-3 then
		t.RootJoint = t.RootJoint * CFrame.Angles(flinch.X, -flinch.Z, flinch.Y)
	end
	if math.abs(flinchHead) > 1e-3 then
		t.Neck = t.Neck * CFrame.Angles(flinchHead, 0, 0)
	end
	if flinchLimbs.Magnitude > 1e-3 then
		t.RightShoulder = t.RightShoulder * CFrame.Angles(0, 0, -flinchLimbs.X)
		t.LeftShoulder = t.LeftShoulder * CFrame.Angles(0, 0, flinchLimbs.Y)
		t.RightHip = t.RightHip * CFrame.Angles(0, 0, -math.max(flinchLimbs.Z, 0))
		t.LeftHip = t.LeftHip * CFrame.Angles(0, 0, -math.min(flinchLimbs.Z, 0))
	end

	-- Where do we stand? -----------------------------------------------------------------------------
	local current, phase, phaseAt, previous, aiming, rounds, aimPoint, cover
	if context.IsLocal and localSource then
		local s = localSource()
		current, phase, phaseAt, previous = s.Current, s.Phase, s.PhaseAt, s.Previous
		aiming, rounds, aimPoint, cover = s.Aiming, s.ReloadRounds or 0, s.AimPoint, s.Cover
		if s.HipAimUntil and s.HipAimUntil > state.HipAimUntil then
			state.HipAimUntil = s.HipAimUntil
		end
	else
		local id = character:GetAttribute("Weapon")
		current = if type(id) == "string" and id ~= "" then id else nil
		phase = character:GetAttribute("WeaponState") or "Holstered"
		phaseAt = character:GetAttribute("WeaponStateAt") or 0
		previous = character:GetAttribute("PreviousWeapon")
		aiming = character:GetAttribute("Aiming") == true
		rounds = character:GetAttribute("ReloadRounds") or 0
		cover = character:GetAttribute("Cover")
	end

	-- Aim direction (world)
	local aimDirection: Vector3
	if aimPoint then
		local torso0 = context.Root * ROOT_C0 * t.RootJoint * ROOT_C1:Inverse()
		local offset = aimPoint - torso0:PointToWorldSpace(SHOULDER)
		aimDirection = if offset.Magnitude > 0.5 then offset.Unit else context.Root.LookVector
	else
		local pitch = character:GetAttribute("AimPitch")
		local yaw = character:GetAttribute("AimYaw")
		local target = context.Root.LookVector
		if type(pitch) == "number" and type(yaw) == "number" then
			target = Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
		end
		local smoothed = (state.AimDirection or target):Lerp(target, 1 - math.exp(-14 * dt))
		aimDirection = if smoothed.Magnitude > 1e-3 then smoothed.Unit else target
		state.AimDirection = aimDirection
	end

	local weapons = weaponsOf(state, character)
	local weapon = current and weapons[current]
	local prev = previous and weapons[previous]
	for _, other in weapons do
		if other ~= weapon and other ~= prev then
			other.Joint.Transform = IDENTITY
		end
	end

	local drawn = phase == "Drawn" or phase == "Reloading"
	state.Aim = approach(state.Aim, if aiming and drawn then 1 else 0, if aiming then 12 else 8, dt)
	state.HipAim = approach(state.HipAim, if now < state.HipAimUntil then 1 else 0, 18, dt)
	local aimWeight = math.max(state.Aim, state.HipAim)
	local kick = state.Kick:Step(dt)

	-- Cover crouch (low cover; rises to shoot over it) -------------------------------------------------
	state.Crouch = approach(state.Crouch, if cover == "Low" and aimWeight < 0.5 and not context.Riding then 1 else 0, 9, dt)
	if state.Crouch > 1e-3 then
		local c = state.Crouch
		t.RootJoint = CFrame.new(0, 0, -CROUCH_DROP * c) * t.RootJoint * CFrame.Angles(CROUCH_LEAN * c, 0, 0)
		-- kneel: right leg back, left leg forward (the lean turns both legs back a little)
		t.RightHip = t.RightHip * CFrame.Angles(0, 0, -(CROUCH_LEG - CROUCH_LEAN) * c)
		t.LeftHip = t.LeftHip * CFrame.Angles(0, 0, -(CROUCH_LEG + CROUCH_LEAN) * c)
	end

	local active = weapon ~= nil and phase ~= "Holstered"
	local moving = phase == "Drawing" or phase == "Holstering"
	-- draws and holsters blend the arms in and out along their own path; the weight only
	-- smooths jumps between other states (e.g. a remote player's state arriving late)
	state.Weight = if moving then 1 else approach(state.Weight, if active then 1 else 0, 14, dt)
	if not weapon or not active then
		if weapon then
			weapon.Joint.Transform = IDENTITY
		end
		if prev then
			prev.Joint.Transform = IDENTITY
		end
		return
	end
	local def = weapon.Def

	-- Torso twist toward the aim; the legs are counter-turned so they stay where they were ------------
	local twistTarget = AimRig.Twist[def.Hold] * aimWeight
	local rootLook = context.Root.LookVector
	local flatAim = Vector3.new(aimDirection.X, 0, aimDirection.Z)
	local flatLook = Vector3.new(rootLook.X, 0, rootLook.Z)
	if flatAim.Magnitude > 1e-3 and flatLook.Magnitude > 1e-3 and (context.Riding or aimWeight > 0.01) then
		local relative = math.atan2(flatLook:Cross(flatAim).Y, flatLook:Dot(flatAim))
		-- on foot the body already faces the aim; in the saddle the torso does the turning
		local share = if context.Riding then 0.8 else 0.35
		local amount = if context.Riding then math.max(aimWeight, 0.35) else aimWeight
		twistTarget += math.clamp(relative * share, -1.35, 1.35) * amount
	end
	state.Twist = approach(state.Twist, math.clamp(twistTarget, -MAX_TWIST, MAX_TWIST), 12, dt)
	local twist = state.Twist * state.Weight
	if math.abs(twist) > 1e-4 then
		t.RootJoint = t.RootJoint * CFrame.Angles(0, 0, twist)
		-- the legs keep their world pose (the twist turns the torso about its centre)
		local undo = ROOT_C1 * CFrame.Angles(0, 0, -twist) * ROOT_C1:Inverse()
		t.RightHip = RIGHT_HIP_C0:Inverse() * undo * RIGHT_HIP_C0 * t.RightHip
		t.LeftHip = LEFT_HIP_C0:Inverse() * undo * LEFT_HIP_C0 * t.LeftHip
	end
	local torso = context.Root * ROOT_C0 * t.RootJoint * ROOT_C1:Inverse()
	local aimTorso = torso:VectorToObjectSpace(aimDirection).Unit
	if kick > 1e-3 then
		-- recoil flips the aim up for a moment
		local side = aimTorso:Cross(UP)
		if side.Magnitude > 1e-3 then
			aimTorso = CFrame.fromAxisAngle(side.Unit, kick):VectorToWorldSpace(aimTorso)
		end
	end
	local swing = math.sin(context.Phase or 0) * (context.Walk or 0) * (1 - aimWeight)
	local target = drawnPose(weapon, aimTorso, aimWeight, swing)
	if kick > 1e-3 and def.Hold == "Long" then
		target.Gun = target.Gun * CFrame.new(0, 0, kick * 0.5)
	end

	-- Pose by phase ------------------------------------------------------------------------------------------
	local elapsed = now - (phaseAt or now)
	local pose = target
	local rightWeight, leftWeight = 1, target.LeftWeight
	local switching = false
	if phase == "Drawing" or phase == "Holstering" then
		local duration = if phase == "Drawing" then def.DrawTime else def.HolsterTime
		local switchTime = if phase == "Drawing" and prev and prev ~= weapon then prev.Def.HolsterTime * 0.7 else 0
		if switchTime > 0 and elapsed < switchTime then
			-- putting the previous gun away first
			switching = true
			local path = drawPath(prev, 1 - elapsed / switchTime, drawnPose(prev, aimTorso, 0, swing))
			prev.Joint.Transform = AimRig.WeaponTransform(prev.Holster, path.Gun)
			pose, rightWeight, leftWeight = path, path.RightWeight, path.LeftWeight
		else
			if prev and prev ~= weapon then
				prev.Joint.Transform = IDENTITY
			end
			local u = math.clamp((elapsed - switchTime) / math.max(duration, 0.05), 0, 1)
			if phase == "Holstering" then
				u = 1 - u
			end
			local path = drawPath(weapon, u, target)
			pose, rightWeight, leftWeight = path, path.RightWeight, path.LeftWeight
		end
	elseif phase == "Reloading" then
		local total = Weapons.ReloadTime(def, math.max(rounds, 1))
		local blend = math.min(smooth(elapsed / 0.22), smooth((total - elapsed) / 0.22))
		pose = blendPose(target, reloadPose(weapon, elapsed, math.max(rounds, 1)), blend)
		leftWeight = math.max(target.LeftWeight, blend)
	end

	-- Moving parts -------------------------------------------------------------------------------------------
	local movers = weapon.Movers
	local sinceShot = now - state.LastShot
	local ready = drawn and not switching
	if movers.Hammer then
		-- cocked while drawn, falls with the shot and is thumbed back
		local cocked = if sinceShot < 0.04 then 0 else 0.75 * smooth((sinceShot - 0.04) / 0.18)
		if phase == "Reloading" then
			cocked = 0.3 -- half-cock to turn the cylinder
		end
		movers.Hammer.Transform = CFrame.Angles(if ready then cocked else 0, 0, 0)
	end
	if movers.Cylinder then
		local turns = state.Shots
		if phase == "Reloading" and def.Reload.Kind == "PerRound" then
			turns += math.clamp(math.floor((elapsed - def.Reload.Start) / def.Reload.PerRound), 0, rounds)
		end
		state.Cylinder = approach(state.Cylinder, turns * math.pi / 3, 16, dt)
		movers.Cylinder.Transform = CFrame.Angles(0, 0, state.Cylinder)
	end
	if movers.Bolt and def.Model == "Pistol" then
		local back = math.max(0, 1 - sinceShot / 0.08)
		if phase == "Reloading" then
			back = math.min(smooth(elapsed / 0.15), smooth((Weapons.ReloadTime(def, 1) - elapsed) / 0.1))
		end
		movers.Bolt.Transform = CFrame.new(0, 0, 0.2 * back)
	end
	if movers.Lever then
		local k = math.clamp((sinceShot - 0.12) / 0.34, 0, 1)
		local angle = if k > 0 and k < 1 and ready then math.sin(k * math.pi) * 0.95 else 0
		if phase == "Reloading" then
			local total = Weapons.ReloadTime(def, math.max(rounds, 1))
			local k2 = math.clamp((elapsed - (total - 0.42)) / 0.34, 0, 1)
			angle = math.max(angle, if k2 > 0 and k2 < 1 then math.sin(k2 * math.pi) * 0.95 else 0)
		end
		movers.Lever.Transform = CFrame.Angles(angle, 0, 0)
		if angle > 0 and not switching then
			pose.Gun = pose.Gun * CFrame.new(0, -0.06 * angle, 0) * CFrame.Angles(-0.08 * angle, 0, 0)
		end
	end
	if movers.Bolt and def.Model == "Rifle" then
		local k = math.clamp((sinceShot - 0.15) / 0.6, 0, 1)
		if phase == "Reloading" then
			local total = Weapons.ReloadTime(def, 1)
			k = if elapsed < 0.4 then math.clamp(elapsed / 0.4, 0, 0.5)
				elseif elapsed > total - 0.4 then 0.5 + math.clamp((elapsed - (total - 0.4)) / 0.4, 0, 0.5)
				else 0.5
		elseif not ready then
			k = 0
		end
		local lift = math.clamp(math.min(k, 1 - k) * 4, 0, 1)
		local slide = math.clamp(math.min(k - 0.2, 0.8 - k) * 3.3, 0, 1)
		movers.Bolt.Transform = CFrame.new(0, 0, 0.36 * slide) * CFrame.Angles(0, 0, 1.3 * lift)
		if k > 0 and k < 1 and phase == "Drawn" and pose.Right then
			-- the right hand works the bolt
			local knob = pose.Gun:PointToWorldSpace(Vector3.new(0.38, 0.24 + 0.12 * lift, 0.02 + 0.36 * slide))
			pose.Right = pose.Right:Lerp(AimRig.Reach("Right", knob, pose.Gun.UpVector), math.sin(k * math.pi))
		end
	end
	if movers.Barrels then
		local open = 0
		if phase == "Reloading" then
			open = math.min(smooth(elapsed / 0.25), smooth((Weapons.ReloadTime(def, math.max(rounds, 1)) - elapsed) / 0.25))
		end
		movers.Barrels.Transform = CFrame.Angles(-0.75 * open, 0, 0)
	end
	weapon.Joint.Transform = if switching then IDENTITY else AimRig.WeaponTransform(weapon.Holster, pose.Gun)

	-- Arms and head -------------------------------------------------------------------------------------------
	local weight = state.Weight
	if pose.Right and rightWeight > 0 then
		t.RightShoulder = t.RightShoulder:Lerp(pose.Right, rightWeight * weight)
	end
	if pose.Left and leftWeight > 0 then
		t.LeftShoulder = t.LeftShoulder:Lerp(pose.Left, leftWeight * weight)
	end
	if aimWeight > 0.01 then
		-- look where we aim
		local yaw = math.atan2(-aimTorso.X, -aimTorso.Z)
		local pitch = math.asin(math.clamp(aimTorso.Y, -1, 1))
		local look = CFrame.Angles(math.clamp(-pitch, -0.8, 0.8), 0, math.clamp(yaw, -1.2, 1.2))
		t.Neck = t.Neck:Lerp(look, aimWeight * 0.85 * weight)
	end
end

-- The muzzle attachment of a character's gun (for effects), or nil.
function UpperBody.Muzzle(character: Model, weaponId: string): Attachment?
	local state = states[character]
	local weapon = state and state.Weapons[weaponId]
	local handle = weapon and weapon.Model.PrimaryPart
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

-- Exposed for the offline tests.
UpperBody._Test = { DrawnPose = drawnPose, DrawPath = drawPath, ReloadPose = reloadPose, GrabPoint = grabPoint }

return UpperBody
