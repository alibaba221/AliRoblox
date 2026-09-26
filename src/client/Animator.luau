--[[
	Procedural R6 animator.

	Runs on every client and animates every R6 rig tagged "SicilyR6" (players and NPCs) straight
	from physics: velocity, humanoid state, turning and landings. Nothing to upload, and cadence
	always matches the actual speed, so walking/running never looks like ice-skating.

	States: idle (breathing, weight shift), walk, run (lean + arm pump), jump, fall (arms out,
	flail on long falls), landing dip, climb, swim, sit, tool hold, lean into turns, head look,
	riding a horse (climbing on, seated with the saddle's motion, posting trot, two-point gallop,
	stepping off). NPC poses via the "Pose" attribute: "Sit", "Vendor", "Chat", "Lean", "Fish".

	If another script plays an Action-priority AnimationTrack on a rig (e.g. a sword swing), the
	upper body is left to that animation and only the legs keep walking.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local HorseMount = require(Shared:WaitForChild("HorseMount"))
local R6 = require(Shared:WaitForChild("R6"))
local Spring = require(Shared:WaitForChild("Spring"))

local Animator = {}

local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local HST = Enum.HumanoidStateType
local ACTION_PRIORITIES = {
	[Enum.AnimationPriority.Action] = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}

local localPlayer = Players.LocalPlayer
local SEAT = HorseMount.SeatOffset()
local ROOT_C0 = R6.Joints[1].C0
local horseAnimator = nil -- set in Start (HorseAnimator module), gives us the saddle's motion
local rigs = {}
local footstepListeners = {}
local landListeners = {}

-- Read by CameraFX for head-bob that matches the footsteps.
local localGait = { Phase = 0, Speed = 0, Walk = 0, Run = 0, Ground = 1, Rig = nil }

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

local POSE_KEYS = {
	"RootUp",
	"RootFwd",
	"RootPitch",
	"RootRoll",
	"RootYaw",
	"NeckPitch",
	"NeckYaw",
	"NeckRoll",
	"RArmSwing",
	"LArmSwing",
	"RArmSpread",
	"LArmSpread",
	"RLegSwing",
	"LLegSwing",
	"RLegSpread",
	"LLegSpread",
}

local function clearPose(pose)
	for _, key in POSE_KEYS do
		pose[key] = 0
	end
end

local function findLookTarget(rig): BasePart?
	local origin = rig.Root.Position
	local look = rig.Root.CFrame.LookVector
	local best, bestDistance = nil, 15
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") and character ~= rig.Model then
			local offset = head.Position - origin
			local distance = offset.Magnitude
			if distance < bestDistance and distance > 0.5 and look:Dot(offset.Unit) > -0.1 then
				best, bestDistance = head, distance
			end
		end
	end
	return best
end

-- Per-rig animation state (pure data, no engine objects).
local function blankState()
	local rig = {
		Seed = math.random() * 100,
		Phase = math.random() * TAU,
		PhaseTotal = 0,
		Clock = math.random() * 100,
		Speed = 0,
		Forward = 1,
		Side = 0,
		Weights = { Ground = 1, Air = 0, Climb = 0, Swim = 0, Sit = 0, Ride = 0 },
		RidePost = 0,
		RideLean = 0,
		AirTime = 0,
		WasAir = false,
		MinVY = 0,
		Land = Spring.new(0, 3.2, 0.5),
		Yaw = 0,
		TurnRate = 0,
		Accel = 0,
		LastForwardSpeed = 0,
		HeadYaw = 0,
		HeadPitch = 0,
		LookTarget = nil,
		NextLookCheck = 0,
		ClimbPhase = 0,
		SwimPhase = 0,
		ToolWeight = 0,
		HasTool = false,
		PoseName = nil,
		External = false,
		NextExternalCheck = 0,
		LastStep = nil,
		NextMotorCheck = 0,
		Pose = {},
		Connections = {},
		Motors = {},
		IsLocal = false,
		IsNPC = false,
	}
	clearPose(rig.Pose)
	return rig
end

local function newRig(model: Model, humanoid: Humanoid, root: BasePart, torso: BasePart)
	local rig = blankState()
	rig.Model = model
	rig.Humanoid = humanoid
	rig.Root = root
	rig.Torso = torso
	rig.Motors = R6.GetMotors(model)
	rig.IsLocal = model == localPlayer.Character
	rig.IsNPC = Players:GetPlayerFromCharacter(model) == nil
	rig.PoseName = model:GetAttribute("Pose")
	local look = root.CFrame.LookVector
	rig.Yaw = math.atan2(-look.X, -look.Z)

	local function refreshTool()
		rig.HasTool = model:FindFirstChildOfClass("Tool") ~= nil
	end
	refreshTool()
	table.insert(rig.Connections, model.ChildAdded:Connect(refreshTool))
	table.insert(rig.Connections, model.ChildRemoved:Connect(refreshTool))
	table.insert(
		rig.Connections,
		model:GetAttributeChangedSignal("Pose"):Connect(function()
			rig.PoseName = model:GetAttribute("Pose")
		end)
	)
	return rig
end

local function fire(listeners, ...)
	for _, callback in listeners do
		task.spawn(callback, ...)
	end
end

local function checkExternalAnimation(rig)
	rig.External = false
	local animator = rig.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if ACTION_PRIORITIES[track.Priority] and track.IsPlaying and track.WeightCurrent > 0.05 then
			rig.External = true
			return
		end
	end
end

--[[
	Pure pose solver: advances the rig's animation state from a physics `sample` and writes the
	resulting Motor6D transforms. sample = { Velocity, RootCFrame, Anchored, State, Sit }.
]]
local function solveRig(rig, sample, dt: number, now: number, cameraCFrame: CFrame)
	rig.Clock += dt
	local t = rig.Clock
	local pose = rig.Pose
	clearPose(pose)

	-- Physics inputs -----------------------------------------------------------------------
	local velocity = sample.Velocity
	local rootCFrame = sample.RootCFrame
	local look = rootCFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.new(0, 0, -1)
	local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flatVelocity.Magnitude

	local yaw = math.atan2(-flatLook.X, -flatLook.Z)
	local deltaYaw = wrapAngle(yaw - rig.Yaw)
	rig.Yaw = yaw
	rig.TurnRate = approach(rig.TurnRate, deltaYaw / math.max(dt, 1 / 240), 8, dt)

	local forwardSpeed = flatVelocity:Dot(flatLook)
	local sideSpeed = flatVelocity:Dot(flatRight)
	rig.Speed = approach(rig.Speed, speed, 9, dt)
	if speed > 0.6 then
		rig.Forward = approach(rig.Forward, forwardSpeed / speed, 10, dt)
		rig.Side = approach(rig.Side, sideSpeed / speed, 10, dt)
	else
		rig.Forward = approach(rig.Forward, 1, 4, dt)
		rig.Side = approach(rig.Side, 0, 4, dt)
	end
	rig.Accel = approach(rig.Accel, (forwardSpeed - rig.LastForwardSpeed) / math.max(dt, 1 / 240), 5, dt)
	rig.LastForwardSpeed = forwardSpeed

	-- State ----------------------------------------------------------------------------------
	local state = sample.State
	local poseName = rig.PoseName
	local seated = sample.Sit or poseName == "Sit" or poseName == "Fish"
	local climbing = state == HST.Climbing
	local swimming = state == HST.Swimming
	local airborne = state == HST.Freefall or state == HST.Jumping or state == HST.FallingDown or state == HST.Flying
	if state == HST.Physics or state == HST.None or state == HST.PlatformStanding then
		airborne = math.abs(velocity.Y) > 6
	end
	-- Remote humanoids may not report every state change; fall back to physics.
	if not rig.IsLocal and not climbing and not swimming and math.abs(velocity.Y) > 12 then
		airborne = true
	end
	if sample.Anchored then
		airborne, climbing, swimming = false, false, false
	end

	local riding = sample.Riding
	if riding then
		seated, climbing, swimming, airborne = false, false, false, false
	end
	local targets = rig.Weights
	local wantRide = if riding then 1 else 0
	local wantSit = if seated then 1 else 0
	local wantClimb = if not seated and climbing then 1 else 0
	local wantSwim = if not seated and not climbing and swimming then 1 else 0
	local wantAir = if not seated and not climbing and not swimming and airborne then 1 else 0
	local wantGround = 1 - wantSit - wantClimb - wantSwim - wantAir - wantRide
	targets.Ride = approach(targets.Ride, wantRide, if riding then 14 else 9, dt)
	targets.Sit = approach(targets.Sit, wantSit, 10, dt)
	targets.Climb = approach(targets.Climb, wantClimb, 12, dt)
	targets.Swim = approach(targets.Swim, wantSwim, 8, dt)
	targets.Air = approach(targets.Air, wantAir, if wantAir > 0 then 14 else 18, dt)
	targets.Ground = approach(targets.Ground, wantGround, 16, dt)
	local total = targets.Sit + targets.Climb + targets.Swim + targets.Air + targets.Ground + targets.Ride
	local wSit, wClimb, wSwim = targets.Sit / total, targets.Climb / total, targets.Swim / total
	local wAir, wGround, wRide = targets.Air / total, targets.Ground / total, targets.Ride / total

	-- Landing ---------------------------------------------------------------------------------
	if riding then
		rig.AirTime, rig.MinVY, rig.WasAir = 0, 0, false
	elseif airborne then
		rig.AirTime += dt
		rig.MinVY = math.min(rig.MinVY, velocity.Y)
	else
		if rig.WasAir and rig.AirTime > 0.12 then
			local impact = -rig.MinVY
			if impact > 10 then
				local dip = math.clamp((impact - 10) / 140, 0.05, 0.55)
				rig.Land:Impulse(-dip * 37)
				fire(landListeners, rig, impact)
			end
		end
		rig.AirTime = 0
		rig.MinVY = 0
	end
	rig.WasAir = airborne

	-- Gait --------------------------------------------------------------------------------------
	local walkSpeed = Config.Movement.WalkSpeed
	local runSpeed = Config.Movement.RunSpeed
	local s = rig.Speed
	local walkAmt = smoothstep(0.25, 3.2, s)
	local runAmt = smoothstep(walkSpeed + 1.5, runSpeed - 1.5, s)
	local stride = Config.Animation.WalkStride + (Config.Animation.RunStride - Config.Animation.WalkStride) * runAmt
	local direction = if rig.Forward < -0.25 then -1 else 1
	local phaseDelta = TAU * (s / stride) * dt * direction
	rig.Phase = (rig.Phase + phaseDelta) % TAU
	rig.PhaseTotal += phaseDelta

	local phase = rig.Phase
	local sn, cs = math.sin(phase), math.cos(phase)
	local slowScale = 0.62 + 0.38 * smoothstep(2, walkSpeed, s)
	local legAmp = (0.5 + 0.46 * runAmt) * walkAmt * slowScale
	local armAmp = (0.38 + 0.52 * runAmt) * walkAmt * slowScale
	local forwardMix = math.clamp(math.abs(rig.Forward), 0, 1)
	local sideMix = math.clamp(math.abs(rig.Side), 0, 1)

	-- Ground: idle + walk/run ----------------------------------------------------------------
	if wGround > 0.001 then
		local w = wGround
		local legSwing = legAmp * sn
		pose.RLegSwing += w * legSwing * forwardMix
		pose.LLegSwing -= w * legSwing * forwardMix
		pose.RLegSpread += w * legAmp * 0.45 * math.max(0, sn) * sideMix
		pose.LLegSpread += w * legAmp * 0.45 * math.max(0, -sn) * sideMix

		local drop = 2 * (1 - math.cos(legSwing))
		pose.RootUp += w * (-drop * 0.78 - 0.07 * runAmt)
		pose.RootPitch += w * (0.045 * walkAmt + 0.17 * runAmt) * direction
		pose.RootYaw += w * (-(0.06 + 0.07 * runAmt) * sn * walkAmt)
		pose.RootRoll += w * (-(0.028 + 0.02 * runAmt) * cs * walkAmt)
		pose.NeckYaw += w * ((0.05 + 0.06 * runAmt) * sn * walkAmt)
		pose.NeckPitch += w * -(0.03 * walkAmt + 0.11 * runAmt)

		local armSwing = armAmp * sn
		pose.RArmSwing += w * (-armSwing + 0.12 * runAmt)
		pose.LArmSwing += w * (armSwing + 0.12 * runAmt)
		pose.RArmSpread += w * (0.045 + 0.1 * runAmt)
		pose.LArmSpread += w * (0.045 + 0.1 * runAmt)

		-- Idle life: breathing, relaxed arms, feet apart, slow weight shift.
		local idle = w * (1 - walkAmt)
		if idle > 0.001 then
			local breath = math.sin(t * TAU * 0.24)
			pose.RootUp += idle * 0.018 * breath
			pose.RootPitch += idle * 0.01 * breath
			pose.RootRoll += idle * 0.022 * math.sin(t * 0.33 + rig.Seed)
			pose.NeckPitch -= idle * 0.012 * breath
			pose.RArmSpread += idle * (0.065 + 0.014 * breath)
			pose.LArmSpread += idle * (0.065 + 0.014 * breath)
			pose.RArmSwing += idle * 0.025 * math.sin(t * TAU * 0.24 + 0.7)
			pose.LArmSwing += idle * 0.025 * math.sin(t * TAU * 0.24 + 0.2)
			pose.RLegSpread += idle * 0.035
			pose.LLegSpread += idle * 0.035

			-- NPC flavour poses
			if poseName == "Vendor" or poseName == "Chat" then
				local gesture = math.max(0, math.sin(t * 0.8 + rig.Seed)) ^ 6
				local gesture2 = math.max(0, math.sin(t * 0.65 + rig.Seed * 2.3)) ^ 6
				pose.RArmSwing += idle * gesture * 1.05
				pose.RArmSpread += idle * gesture * 0.25
				pose.LArmSwing += idle * gesture2 * 0.8
				pose.LArmSpread += idle * gesture2 * 0.3
				pose.NeckPitch += idle * 0.08 * math.sin(t * 2.1) * (gesture + gesture2)
			elseif poseName == "Lean" then
				pose.RootPitch -= idle * 0.1
				pose.RootRoll += idle * 0.06
				pose.RArmSwing += idle * 0.95
				pose.LArmSwing += idle * 0.85
				pose.RArmSpread -= idle * 0.62
				pose.LArmSpread -= idle * 0.55
				pose.RLegSwing += idle * 0.16
				pose.RLegSpread -= idle * 0.14
			end
		end

		-- Lean into turns and with acceleration.
		local turnLean = math.clamp(-rig.TurnRate * s * 0.0085, -0.3, 0.3)
		pose.RootRoll += w * turnLean
		pose.NeckRoll -= w * turnLean * 0.5
		pose.RootPitch += w * math.clamp(rig.Accel * 0.01, -0.12, 0.16) * walkAmt
	end

	-- Air: jump / fall ----------------------------------------------------------------------------
	if wAir > 0.001 then
		local w = wAir
		local rising = smoothstep(-6, 6, velocity.Y)
		local falling = 1 - rising
		pose.RArmSwing += w * (rising * 0.55 + falling * 0.22)
		pose.LArmSwing += w * (rising * 0.32 + falling * 0.22)
		pose.RArmSpread += w * (rising * 0.28 + falling * 1.05)
		pose.LArmSpread += w * (rising * 0.28 + falling * 1.05)
		pose.RLegSwing += w * (rising * 0.45 + falling * 0.2)
		pose.LLegSwing += w * (rising * -0.22 + falling * -0.12)
		pose.RLegSpread += w * falling * 0.1
		pose.LLegSpread += w * falling * 0.1
		pose.RootPitch += w * (rising * 0.07 - falling * 0.05)
		pose.NeckPitch += w * falling * 0.12

		local flail = smoothstep(0.7, 1.6, rig.AirTime) * falling
		if flail > 0.001 then
			local ft = t * 9
			pose.RArmSwing += w * flail * 0.35 * math.sin(ft)
			pose.LArmSwing += w * flail * 0.35 * math.sin(ft + 1.7)
			pose.RLegSwing += w * flail * 0.25 * math.sin(ft + 0.9)
			pose.LLegSwing += w * flail * 0.25 * math.sin(ft + 2.6)
		end
	end

	-- Climb ------------------------------------------------------------------------------------------
	if wClimb > 0.001 then
		local w = wClimb
		rig.ClimbPhase += TAU * (math.abs(velocity.Y) / 3.2) * dt
		local c = math.sin(rig.ClimbPhase)
		pose.RArmSwing += w * (2.5 + 0.45 * c)
		pose.LArmSwing += w * (2.5 - 0.45 * c)
		pose.RArmSpread += w * 0.12
		pose.LArmSpread += w * 0.12
		pose.RLegSwing += w * (0.22 - 0.3 * c)
		pose.LLegSwing += w * (0.22 + 0.3 * c)
		pose.RootPitch -= w * 0.04
		pose.NeckPitch -= w * 0.35
	end

	-- Swim -------------------------------------------------------------------------------------------
	if wSwim > 0.001 then
		local w = wSwim
		local moving = smoothstep(1, 6, s)
		rig.SwimPhase += TAU * (0.5 + s / 16) * dt
		local sp = rig.SwimPhase
		local tread = 1 - moving
		pose.RootPitch += w * moving * 1.35
		pose.NeckPitch -= w * moving * 1.0
		pose.RootUp += w * (-0.25 + 0.06 * math.sin(sp * 2))
		pose.RArmSwing += w * (moving * (1.6 + 1.55 * math.sin(sp)) + tread * 0.35 * math.sin(sp * 2.2))
		pose.LArmSwing += w * (moving * (1.6 + 1.55 * math.sin(sp + math.pi)) + tread * 0.35 * math.sin(sp * 2.2 + math.pi))
		pose.RArmSpread += w * (tread * (0.95 + 0.25 * math.sin(sp * 2.2)) + moving * 0.15)
		pose.LArmSpread += w * (tread * (0.95 + 0.25 * math.sin(sp * 2.2)) + moving * 0.15)
		pose.RLegSwing += w * 0.22 * math.sin(sp * 3.1)
		pose.LLegSwing -= w * 0.22 * math.sin(sp * 3.1)
	end

	-- Sit --------------------------------------------------------------------------------------------
	if wSit > 0.001 then
		local w = wSit
		pose.RLegSwing += w * HALF_PI
		pose.LLegSwing += w * HALF_PI
		pose.RLegSpread += w * 0.04
		pose.LLegSpread += w * 0.04
		pose.RootPitch -= w * 0.05
		if poseName == "Fish" then
			pose.RArmSwing += w * 0.95
			pose.LArmSwing += w * 0.85
			pose.RArmSpread -= w * 0.2
			pose.LArmSpread -= w * 0.12
		else
			local gesture = if poseName == "Sit" then math.max(0, math.sin(t * 0.55 + rig.Seed)) ^ 8 else 0
			pose.RArmSwing += w * (0.45 + gesture * 0.7)
			pose.LArmSwing += w * 0.45
			pose.RArmSpread -= w * 0.03
			pose.LArmSpread -= w * 0.03
		end
	end

	-- Riding ------------------------------------------------------------------------------------------
	if wRide > 0.001 then
		local w = wRide
		local phaseName = if riding then riding.Phase else "Seated"
		local u = if riding then riding.Progress else 1
		local gait = riding and riding.Gait
		-- seated: thighs forward and around the barrel, hands low on the reins
		local seat = 1
		if phaseName == "Mount" then
			seat = smoothstep(0.7, 1, u)
		elseif phaseName == "Dismount" then
			seat = 1 - smoothstep(0, 0.45, u)
		end
		local weights = gait and gait.Weights or { 1, 0, 0, 0 }
		local moving = gait and gait.Moving or 0
		local gaitPhase = gait and gait.Phase or 0
		local trot, canter, gallop = weights[2] * moving, weights[3] * moving, weights[4] * moving
		-- posting at the trot: rise and sit with each diagonal pair
		rig.RidePost = approach(rig.RidePost, trot, 6, dt)
		rig.RideLean = approach(rig.RideLean, gallop * 0.9 + canter * 0.35, 4, dt)
		local post = rig.RidePost * math.max(0, math.sin(TAU * 2 * gaitPhase + 0.8)) * 0.3
		local lean = rig.RideLean
		pose.RLegSwing += w * seat * (0.52 + 0.1 * lean)
		pose.LLegSwing += w * seat * (0.52 + 0.1 * lean)
		pose.RLegSpread += w * seat * 0.5
		pose.LLegSpread += w * seat * 0.5
		pose.RootUp += w * seat * (post + lean * 0.22 - 0.02)
		pose.RootPitch += w * seat * (0.06 + lean * 0.42 + rig.RidePost * 0.12)
		pose.NeckPitch -= w * seat * lean * 0.3
		pose.RArmSwing += w * seat * (0.62 + lean * 0.35)
		pose.LArmSwing += w * seat * (0.62 + lean * 0.35)
		pose.RArmSpread += w * seat * -0.2
		pose.LArmSpread += w * seat * -0.2
		-- small counter-sway with the canter / gallop rock
		pose.RootPitch += w * seat * (canter + gallop) * 0.05 * math.sin(TAU * gaitPhase + 1.2)
		if riding and riding.Tame then
			-- hanging on to a bucking horse
			local s = riding.Tame
			pose.RootPitch += w * (-s.Rear * 0.45 + s.Buck * 0.35)
			pose.RArmSwing += w * (0.3 + s.Intensity * 0.3)
			pose.LArmSwing += w * (0.3 + s.Intensity * 0.3)
			pose.RootRoll += w * s.Shake * 0.08
			pose.NeckPitch += w * s.Buck * 0.2
		end
		if phaseName == "Mount" then
			local k = 1 - seat
			if u < 0.35 then
				-- stepping in beside the horse
				local stepPhase = math.sin(u / 0.35 * math.pi * 2)
				pose.RLegSwing += w * k * 0.35 * stepPhase
				pose.LLegSwing -= w * k * 0.35 * stepPhase
				pose.RArmSwing += w * k * 0.4
				pose.LArmSwing += w * k * 0.9
			else
				-- foot in the stirrup, swing the other leg up and over
				local swing = math.sin(math.clamp((u - 0.35) / 0.55, 0, 1) * math.pi)
				pose.LLegSwing += w * k * 1.1
				pose.RLegSpread += w * k * (0.3 + 1.1 * swing)
				pose.RLegSwing += w * k * 0.4 * swing
				pose.RootPitch += w * k * 0.35
				pose.RArmSwing += w * k * 1.2
				pose.LArmSwing += w * k * 1.35
			end
		elseif phaseName == "Dismount" then
			local k = 1 - seat
			local swing = math.sin(math.clamp(u / 0.7, 0, 1) * math.pi)
			pose.RLegSpread += w * k * 0.9 * swing
			pose.LLegSwing += w * k * 0.5 * swing
			pose.RArmSwing += w * k * 0.9 * swing
			pose.LArmSwing += w * k * 0.9 * swing
			pose.RootPitch += w * k * 0.2 * swing
		end
	end

	-- Landing dip (additive, springy) ------------------------------------------------------------
	local dip = math.min(rig.Land:Step(dt), 0.05)
	if math.abs(dip) > 1e-3 then
		pose.RootUp += dip
		pose.RootPitch -= dip * 0.35
		pose.RArmSpread -= dip * 0.5
		pose.LArmSpread -= dip * 0.5
		-- splay the (knee-less) legs just enough to keep the feet on the ground
		local splay = math.acos(math.clamp(1 + math.min(dip, 0) * 0.5, -1, 1))
		pose.RLegSwing += splay * 0.8
		pose.RLegSpread += splay * 0.6
		pose.LLegSwing -= splay * 0.5
		pose.LLegSpread += splay * 0.87
	end

	-- Tool hold (classic R6 arm-out pose) ------------------------------------------------------------
	rig.ToolWeight = approach(rig.ToolWeight, if rig.HasTool then 1 else 0, 12, dt)
	if rig.ToolWeight > 0.001 then
		local k = rig.ToolWeight
		pose.RArmSwing = pose.RArmSwing * (1 - k) + k * (HALF_PI + 0.05 * sn * walkAmt)
		pose.RArmSpread *= 1 - k
	end

	-- Head look --------------------------------------------------------------------------------------
	local targetYaw, targetPitch = 0, 0
	local lookDirection: Vector3? = nil
	if rig.IsLocal and Config.Animation.HeadFollowsCamera then
		lookDirection = cameraCFrame.LookVector
	elseif rig.IsNPC and Config.Animation.NPCHeadTracking then
		if now >= rig.NextLookCheck then
			rig.NextLookCheck = now + 0.35 + math.random() * 0.35
			rig.LookTarget = findLookTarget(rig)
		end
		local target = rig.LookTarget
		if target and target.Parent then
			lookDirection = (target.Position - (rootCFrame.Position + Vector3.new(0, 1.5, 0))).Unit
		else
			targetYaw = 0.4 * math.noise(t * 0.12, rig.Seed)
			targetPitch = 0.1 * math.noise(rig.Seed, t * 0.1)
		end
	end
	if lookDirection then
		local relative = rootCFrame:VectorToObjectSpace(lookDirection)
		local yawRelative = math.atan2(-relative.X, -relative.Z)
		local pitchRelative = math.asin(math.clamp(relative.Y, -1, 1))
		if math.abs(yawRelative) < 1.95 then
			targetYaw = math.clamp(yawRelative, -1.1, 1.1) * 0.75
			targetPitch = math.clamp(-pitchRelative, -0.55, 0.6) * 0.65
		end
	end
	rig.HeadYaw = approach(rig.HeadYaw, targetYaw, 6, dt)
	rig.HeadPitch = approach(rig.HeadPitch, targetPitch, 6, dt)
	pose.NeckYaw += rig.HeadYaw
	pose.NeckPitch += rig.HeadPitch

	-- Footsteps -----------------------------------------------------------------------------------
	if wGround > 0.6 and walkAmt > 0.35 and not riding then
		local stepIndex = math.floor((rig.PhaseTotal - HALF_PI) / math.pi)
		if rig.LastStep ~= nil and stepIndex ~= rig.LastStep then
			fire(footstepListeners, rig, if stepIndex % 2 == 0 then "Right" else "Left", s, runAmt)
		end
		rig.LastStep = stepIndex
	else
		rig.LastStep = nil
	end

	if rig.IsLocal then
		localGait.Phase = phase
		localGait.Speed = s
		localGait.Walk = walkAmt
		localGait.Run = runAmt
		localGait.Ground = wGround
		localGait.Rig = rig
	end

	-- Apply -----------------------------------------------------------------------------------------
	local motors = rig.Motors
	local upperBodyFree = not rig.External
	local rootTransform = CFrame.new(0, -pose.RootFwd, pose.RootUp) * CFrame.Angles(pose.RootPitch, -pose.RootRoll, pose.RootYaw)
	if riding and riding.Saddle then
		-- move with the saddle as the horse's body bobs and pitches
		rootTransform = ROOT_C0:Inverse() * riding.Saddle * ROOT_C0 * rootTransform
	end
	if upperBodyFree and motors.RootJoint then
		motors.RootJoint.Transform = rootTransform
	elseif motors.RootJoint and riding and riding.Saddle then
		motors.RootJoint.Transform = ROOT_C0:Inverse() * riding.Saddle * ROOT_C0
	end
	if upperBodyFree and motors.Neck then
		motors.Neck.Transform = CFrame.Angles(pose.NeckPitch, -pose.NeckRoll, pose.NeckYaw)
	end
	if upperBodyFree and motors["Right Shoulder"] then
		motors["Right Shoulder"].Transform = CFrame.Angles(-pose.RArmSpread, 0, pose.RArmSwing)
	end
	if upperBodyFree and motors["Left Shoulder"] then
		motors["Left Shoulder"].Transform = CFrame.Angles(-pose.LArmSpread, 0, -pose.LArmSwing)
	end
	if motors["Right Hip"] then
		motors["Right Hip"].Transform = CFrame.Angles(-pose.RLegSpread, 0, pose.RLegSwing)
	end
	if motors["Left Hip"] then
		motors["Left Hip"].Transform = CFrame.Angles(-pose.LLegSpread, 0, -pose.LLegSwing)
	end
end

local function updateRig(rig, dt: number, now: number, cameraCFrame: CFrame)
	local humanoid: Humanoid = rig.Humanoid
	local model: Model = rig.Model
	local root: BasePart = rig.Root
	if not root.Parent then
		-- streamed out/in or rebuilt: pick up the current parts
		local newRoot = model:FindFirstChild("HumanoidRootPart")
		if not newRoot or not newRoot:IsA("BasePart") then
			return
		end
		root = newRoot
		rig.Root = newRoot
		rig.Motors = R6.GetMotors(model)
	end

	if humanoid.Health <= 0 or model:GetAttribute("SicilyRagdolled") then
		return
	end
	if not rig.IsLocal and (root.Position - cameraCFrame.Position).Magnitude > Config.Animation.MaxDistance then
		return
	end
	if now >= rig.NextMotorCheck then
		rig.NextMotorCheck = now + 1
		local rootJoint = rig.Motors.RootJoint
		if not rootJoint or not rootJoint.Parent then
			rig.Motors = R6.GetMotors(model)
		end
	end
	if now >= rig.NextExternalCheck then
		rig.NextExternalCheck = now + 0.2
		checkExternalAnimation(rig)
	end

	-- On a horse: animate the saddle joint (climbing on / stepping off) and follow the saddle.
	local riding = nil
	local saddleJoint = root:FindFirstChild(HorseMount.JointName)
	if saddleJoint and saddleJoint:IsA("Motor6D") and saddleJoint.Enabled then
		local transform, phase, progress = HorseMount.JointTransform(saddleJoint, Workspace:GetServerTimeNow())
		saddleJoint.Transform = transform
		local horse = saddleJoint.Part0 and saddleJoint.Part0.Parent
		local gait, tame = nil, nil
		if horseAnimator and horse then
			gait, tame = horseAnimator.GetState(horse)
		end
		local saddle = nil
		if gait then
			local blend = if phase == "Seated"
				then 1
				elseif phase == "Mount" then smoothstep(0.6, 1, progress)
				else 1 - smoothstep(0, 0.4, progress)
			saddle = CFrame.new():Lerp(SEAT:Inverse() * gait.BodyTransform * SEAT, blend)
		end
		riding = { Phase = phase, Progress = progress, Gait = gait, Saddle = saddle, Horse = horse, Tame = tame }
	end
	rig.Riding = riding

	local anchored = root.Anchored
	solveRig(rig, {
		Velocity = if anchored then Vector3.zero else root.AssemblyLinearVelocity,
		RootCFrame = root.CFrame,
		Anchored = anchored,
		State = humanoid:GetState(),
		Sit = humanoid.Sit,
		Riding = riding,
	}, dt, now, cameraCFrame)
end

local function unregister(model: Model)
	local rig = rigs[model]
	if not rig then
		return
	end
	rigs[model] = nil
	for _, connection in rig.Connections do
		connection:Disconnect()
	end
	if localGait.Rig == rig then
		localGait.Rig = nil
	end
end

local pending = {}

local function register(model: Instance)
	if not model:IsA("Model") or rigs[model] or pending[model] then
		return
	end
	pending[model] = true
	task.spawn(function()
		local humanoid = model:WaitForChild("Humanoid", 10)
		local root = model:WaitForChild("HumanoidRootPart", 10)
		local torso = model:WaitForChild("Torso", 10)
		if torso then
			for _, joint in R6.Joints do
				if joint.Parent == "Torso" then
					torso:WaitForChild(joint.Name, 5)
				end
			end
		end
		if root then
			root:WaitForChild("RootJoint", 5)
		end
		pending[model] = nil
		if not (humanoid and root and torso) or not humanoid:IsA("Humanoid") then
			return
		end
		if humanoid.RigType ~= Enum.HumanoidRigType.R6 or not model:IsDescendantOf(Workspace) then
			return
		end
		local rig = newRig(model, humanoid, root :: BasePart, torso :: BasePart)
		rigs[model] = rig
		table.insert(
			rig.Connections,
			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(Workspace) then
					unregister(model)
				end
			end)
		)
	end)
end

local warned = {}

function Animator.Start(horses)
	if not Config.Animation.Enabled then
		return
	end
	horseAnimator = horses
	for _, model in CollectionService:GetTagged(R6.Tag) do
		register(model)
	end
	CollectionService:GetInstanceAddedSignal(R6.Tag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(R6.Tag):Connect(unregister)

	-- Start animating our own character immediately (before the server's tag replicates).
	local function onCharacter(character: Model)
		task.defer(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") and humanoid.RigType == Enum.HumanoidRigType.R6 then
				register(character)
			end
		end)
	end
	if localPlayer.Character then
		onCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)

	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local cameraCFrame = if camera then camera.CFrame else CFrame.new()
		-- horses first: riders follow their saddle's motion from this frame
		if horseAnimator then
			local ok, err = pcall(horseAnimator.Step, dt, cameraCFrame.Position)
			if not ok and not warned.Horses then
				warned.Horses = true
				warn("[Sicily] Horse animator error: " .. tostring(err))
			end
		end
		for model, rig in rigs do
			local ok, err = pcall(updateRig, rig, dt, now, cameraCFrame)
			if not ok then
				if not warned[model] then
					warned[model] = true
					warn("[Sicily] Animator error on " .. model:GetFullName() .. ": " .. tostring(err))
				end
				unregister(model)
			end
		end
	end)
end

function Animator.OnFootstep(callback: (rig: any, side: string, speed: number, run: number) -> ())
	table.insert(footstepListeners, callback)
end

function Animator.OnLanded(callback: (rig: any, impact: number) -> ())
	table.insert(landListeners, callback)
end

function Animator.GetLocalGait()
	return localGait
end

-- Exposed for the offline test harness (tools/lune/test-animation.luau).
Animator._Test = { BlankState = blankState, Solve = solveRig }

return Animator
