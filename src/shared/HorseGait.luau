--[[
	SicilyShared.HorseGait
	Procedural locomotion for HorseRig horses. Pure maths: give it the horse's physics every frame
	and it returns a Motor6D Transform for every joint.

	* Real footfall patterns that blend with speed: 4-beat walk, 2-beat trot, 3-beat canter and
	  4-beat gallop (with a moment of suspension), plus stepping on the spot when turning.
	* Hooves are planted in the world while they bear weight and swing to predicted landing spots,
	  so they never slide. Legs are solved with two-bone IK (knees forward in front, hocks back
	  behind) and the hooves stay level on the ground.
	* The body follows the ground under the hooves (slopes and steps), bobs with the gait, leans
	  into turns, squats when braking hard and stretches out at a gallop.
	* Neck nods with the stride, lowers to graze, lifts when alert; the tail swings and streams back.
	* Jumps (tucked legs), swimming, rearing and bucking (for taming).
]]

local HorseRig = require(script.Parent.HorseRig)

local HorseGait = {}

local L = HorseRig.Layout
local TAU = 2 * math.pi
local UP = Vector3.new(0, 1, 0)
local LEGS = L.LegOrder

--[[
	Gait anchors. Offsets are each leg's place in the stride (0..1), Duty is the fraction of the
	stride a hoof is on the ground, Freq the base strides per second (raised automatically so a
	hoof never has to reach further than MaxTravel).
]]
local GAITS = {
	{
		Name = "Walk",
		Duty = 0.66,
		Freq = 1.2,
		Offsets = { HL = 0, FL = 0.25, HR = 0.5, FR = 0.75 },
		Lift = 0.42,
		Crouch = 0.08,
		Bob = 0.045,
		BobCycles = 2,
		BobPhase = 0.2,
		Pitch = 0.018,
		Nod = 0.07,
		NodCycles = 2,
		Neck = 0.06,
		Roll = 0.028,
	},
	{
		Name = "Trot",
		Duty = 0.46,
		Freq = 1.62,
		Offsets = { FL = 0, HR = 0, FR = 0.5, HL = 0.5 },
		Lift = 0.72,
		Crouch = 0.2,
		Bob = 0.12,
		BobCycles = 2,
		BobPhase = 0.23,
		Pitch = 0.012,
		Nod = 0.02,
		NodCycles = 2,
		Neck = -0.04,
		Roll = 0.012,
	},
	{
		Name = "Canter",
		Duty = 0.4,
		Freq = 1.8,
		Offsets = { HL = 0, HR = 0.28, FL = 0.28, FR = 0.52 },
		Lift = 0.78,
		Crouch = 0.3,
		Bob = 0.16,
		BobCycles = 1,
		BobPhase = 0.45,
		Pitch = 0.075,
		Nod = 0.11,
		NodCycles = 1,
		Neck = 0.1,
		Roll = 0.02,
	},
	{
		Name = "Gallop",
		Duty = 0.28,
		Freq = 2.15,
		Offsets = { HL = 0, HR = 0.1, FL = 0.44, FR = 0.55 },
		Lift = 0.85,
		Crouch = 0.38,
		Bob = 0.2,
		BobCycles = 1,
		BobPhase = 0.62,
		Pitch = 0.085,
		Nod = 0.13,
		NodCycles = 1,
		Neck = 0.3,
		Roll = 0.015,
	},
}

local HIP_SLIDE = 0.45 -- shoulders/hips slide along the body this far to extend a stride
local MAX_REACH = 2.1 -- horizontal hoof distance from its hip before it's forced to step
local MAX_ABDUCTION = 0.5 -- how far a leg can swing out sideways (radians)
local SETTLE_DISTANCE = 0.3 -- a standing horse squares up feet further than this from rest
local HOOF = L.HoofHeight

local function clamp(x: number, a: number, b: number): number
	return if x < a then a elseif x > b then b else x
end

local function smoothstep(a: number, b: number, x: number): number
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function wrap01(x: number): number
	return x - math.floor(x)
end

-- Signed shortest difference b - a on a circle of circumference 1.
local function circularDelta(a: number, b: number): number
	local d = wrap01(b - a)
	return if d > 0.5 then d - 1 else d
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- 1D spring (critically damped by default) that's stable at any frame rate.
local function newSpring(value: number, frequency: number, damping: number?)
	return { P = value, V = 0, F = frequency, D = damping or 1 }
end

local function stepSpring(s, target: number, dt: number): number
	local omega = s.F * TAU
	local remaining = math.min(dt, 0.1)
	while remaining > 1e-6 do
		local h = math.min(remaining, 1 / 120)
		local a = (target - s.P) * omega * omega - s.V * 2 * s.D * omega
		s.V += a * h
		s.P += s.V * h
		remaining -= h
	end
	return s.P
end

--[[
	Two-bone IK in the leg's plane. `forward`/`down` locate the target (fetlock) relative to the
	hip; returns the upper-leg angle and the knee angle (radians, positive = swing forward).
]]
function HorseGait.SolveLeg(upper: number, lower: number, forward: number, down: number, kneeForward: boolean): (number, number)
	local distance = math.sqrt(forward * forward + down * down)
	distance = clamp(distance, math.abs(upper - lower) + 0.05, upper + lower - 1e-3)
	local cosA = clamp((upper * upper + distance * distance - lower * lower) / (2 * upper * distance), -1, 1)
	local cosC = clamp((upper * upper + lower * lower - distance * distance) / (2 * upper * lower), -1, 1)
	local a = math.acos(cosA)
	local bend = math.pi - math.acos(cosC)
	local beta = math.atan2(forward, down)
	if kneeForward then
		return beta + a, -bend
	end
	return beta - a, bend
end

-- Forward kinematics matching SolveLeg (used by tests): fetlock position relative to the hip.
function HorseGait.LegEnd(upper: number, lower: number, thetaUpper: number, thetaKnee: number): (number, number)
	local fwd = upper * math.sin(thetaUpper) + lower * math.sin(thetaUpper + thetaKnee)
	local down = upper * math.cos(thetaUpper) + lower * math.cos(thetaUpper + thetaKnee)
	return fwd, down
end

function HorseGait.New(temperament)
	local legs = {}
	for _, name in LEGS do
		local def = L.Legs[name]
		legs[name] = {
			Name = name,
			Def = def,
			Front = def.Front,
			Phase = 0,
			Mode = "Stance",
			Armed = true,
			TimedFrom = 0,
			FirstFrame = false,
			Swinging = false,
			Plant = nil :: Vector3?,
			From = Vector3.zero,
			Target = Vector3.zero,
			SwingT = 0,
			SwingTime = 0.3,
			GroundY = 0,
			Settle = false,
		}
	end
	local speeds = {
		temperament and temperament.WalkSpeed or 7.5,
		temperament and temperament.TrotSpeed or 15,
		temperament and temperament.CanterSpeed or 23,
		temperament and temperament.GallopSpeed or 32,
	}
	local phase = math.random()
	for _, name in LEGS do
		legs[name].Phase = wrap01(phase + GAITS[1].Offsets[name])
	end
	return {
		Legs = legs,
		Speeds = speeds,
		Phase = phase,
		Freq = 0,
		Duty = 1,
		Weights = { 1, 0, 0, 0 },
		Moving = 0,
		Speed = 0,
		ForwardSpeed = 0,
		TurnRate = 0,
		Accel = 0,
		LastForward = 0,
		Clock = math.random() * 50,
		LastRoot = nil :: CFrame?,
		Height = newSpring(0, 3.2),
		Pitch = newSpring(0, 3),
		Roll = newSpring(0, 2.5),
		Air = 0,
		Swim = 0,
		Graze = newSpring(0, 0.9),
		Alert = newSpring(0, 1.4),
		NeckYaw = newSpring(0, 1.6),
		Rear = newSpring(0, 1.8, 0.7),
		Buck = newSpring(0, 2.2, 0.55),
		TailSwish = newSpring(0, 1.1, 0.35),
		TailLift = newSpring(0, 1.5),
		Stretch = 0,
		Settling = nil :: string?,
		NextSettleCheck = 0,
		BodyTransform = CFrame.new(),
		Transforms = {},
		Events = {},
	}
end

local function gaitParams(state, speed: number)
	-- weights over the 4 gaits from the current speed (linear between anchors)
	local s = state.Speeds
	local w = state.Weights
	w[1], w[2], w[3], w[4] = 0, 0, 0, 0
	if speed <= s[1] then
		w[1] = 1
	elseif speed >= s[4] then
		w[4] = 1
	else
		for i = 1, 3 do
			if speed <= s[i + 1] then
				local t = smoothstep(s[i], s[i + 1], speed)
				-- stay in the lower gait a little longer, then change over briskly
				t = smoothstep(0.25, 0.75, t)
				w[i] = 1 - t
				w[i + 1] = t
				break
			end
		end
	end
	local duty, freq, lift, crouch = 0, 0, 0, 0
	for i, g in GAITS do
		duty += w[i] * g.Duty
		freq += w[i] * g.Freq
		lift += w[i] * g.Lift
		crouch += w[i] * g.Crouch
	end
	return duty, freq, lift, crouch
end

-- Where a leg's hoof rests when standing square, projected to the ground.
local function restPoint(rootCFrame: CFrame, def): Vector3
	return rootCFrame:PointToWorldSpace(Vector3.new(def.Hip.X, -L.RootHeight, def.Hip.Z))
end

local function groundAt(ground, point: Vector3): number
	if ground then
		local y = ground(point)
		if y then
			return y
		end
	end
	return point.Y
end

--[[
	HorseGait.Step(state, sample, dt, ground) -> transforms, events
	sample = {
		RootCFrame: CFrame, Velocity: Vector3, AngularVelocity: number (yaw rad/s),
		Mode: "Ground" | "Air" | "Swim",
		Graze: 0..1, Alert: 0..1, LookAt: Vector3?,
		Rear: 0..1, Buck: 0..1, Kick: 0..1 (hind kick), Startle: 0..1,
	}
	ground(point: Vector3) -> number? : terrain height under a point (nil = unknown)
	events: list of { Leg, Position, Front } for hooves that touched down this frame.
]]
function HorseGait.Step(state, sample, dt: number, ground: ((Vector3) -> number?)?)
	dt = clamp(dt, 1 / 240, 0.1)
	state.Clock += dt
	local t = state.Clock
	table.clear(state.Events)

	local rootCF: CFrame = sample.RootCFrame
	local velocity: Vector3 = sample.Velocity
	local flatVelocity = flat(velocity)
	local look = flat(rootCF.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local forwardSpeed = flatVelocity:Dot(look)
	local speed = flatVelocity.Magnitude
	local omega = sample.AngularVelocity or 0

	-- Teleported or just streamed in: start from a square stance.
	if state.LastRoot == nil or (state.LastRoot.Position - rootCF.Position).Magnitude > 10 then
		for _, name in LEGS do
			local leg = state.Legs[name]
			local rest = restPoint(rootCF, leg.Def)
			leg.Plant = Vector3.new(rest.X, groundAt(ground, rest), rest.Z)
			leg.Swinging = false
			leg.Mode = "Stance"
		end
	end
	state.LastRoot = rootCF

	state.Speed = approach(state.Speed, speed, 10, dt)
	state.ForwardSpeed = approach(state.ForwardSpeed, forwardSpeed, 10, dt)
	state.TurnRate = approach(state.TurnRate, omega, 8, dt)
	state.Accel = approach(state.Accel, (forwardSpeed - state.LastForward) / dt, 4, dt)
	state.LastForward = forwardSpeed

	local mode = sample.Mode or "Ground"
	state.Air = approach(state.Air, if mode == "Air" then 1 else 0, if mode == "Air" then 10 else 16, dt)
	state.Swim = approach(state.Swim, if mode == "Swim" then 1 else 0, 5, dt)
	local grounded = 1 - math.max(state.Air, state.Swim)

	-- Gait -------------------------------------------------------------------------------------
	local stepSpeed = math.abs(state.Speed) + math.abs(state.TurnRate) * 2.3
	local duty, baseFreq, lift, crouch = gaitParams(state, math.abs(state.Speed))
	-- How far a planted hoof can travel under the body at this crouch (shorter front legs limit it).
	local front = L.Legs.FL
	local chain = front.Upper + front.Lower
	local hipHeight = L.RootHeight + front.Hip.Y - HOOF - crouch
	local reach = math.sqrt(math.max(chain * chain - hipHeight * hipHeight, 0)) + HIP_SLIDE
	local maxTravel = 2 * reach * 0.8
	state.MaxTravel = maxTravel
	local travelFreq = math.abs(state.Speed) * duty / maxTravel
	local freq = math.max(baseFreq, travelFreq)
	if math.abs(state.Speed) < 1 and math.abs(state.TurnRate) > 0.2 then
		freq = math.max(freq, 1.3) -- quick little steps when turning on the spot
		duty = 0.62
	end
	state.Moving = approach(state.Moving, if stepSpeed > 0.45 then 1 else 0, if stepSpeed > 0.45 then 12 else 6, dt)
	state.Freq, state.Duty = freq, duty
	state.Phase = wrap01(state.Phase + freq * dt * state.Moving)

	local offsets = { FL = 0, FR = 0, HL = 0, HR = 0 }
	for i, g in GAITS do
		local w = state.Weights[i]
		if w > 0 then
			for _, name in LEGS do
				-- blend offsets around the circle relative to the walk pattern
				offsets[name] += w * circularDelta(GAITS[1].Offsets[name], g.Offsets[name])
			end
		end
	end

	-- Body (computed before the legs; the IK needs this frame's body) -------------------------
	local w = state.Weights
	local bob, pitchOsc, nod, neckBase, rollOsc = 0, 0, 0, 0, 0
	for i, g in GAITS do
		if w[i] > 0 then
			local ph = TAU * (state.Phase - g.BobPhase)
			bob += w[i] * -g.Bob * math.cos(ph * g.BobCycles)
			pitchOsc += w[i] * g.Pitch * math.sin(TAU * state.Phase)
			nod += w[i] * g.Nod * math.sin(TAU * state.Phase * g.NodCycles + 0.6)
			neckBase += w[i] * g.Neck
			rollOsc += w[i] * g.Roll * math.sin(TAU * state.Phase)
		end
	end
	local moving = state.Moving * grounded
	bob *= moving
	pitchOsc *= moving
	nod *= moving
	rollOsc *= moving

	-- terrain: heights under the hooves -> body height and pitch
	local frontY, hindY, nF, nH = 0, 0, 0, 0
	for _, name in LEGS do
		local leg = state.Legs[name]
		local y = if leg.Swinging then leg.Target.Y else (if leg.Plant then leg.Plant.Y else rootCF.Y - L.RootHeight)
		if leg.Front then
			frontY += y
			nF += 1
		else
			hindY += y
			nH += 1
		end
	end
	frontY /= nF
	hindY /= nH
	local groundUnderRoot = rootCF.Y - L.RootHeight
	local span = L.Legs.HL.Hip.Z - L.Legs.FL.Hip.Z
	local terrainPitch = clamp(math.atan2(frontY - hindY, span), -0.55, 0.55) * grounded
	local terrainHeight = clamp((frontY + hindY) / 2 - groundUnderRoot, -1, 1) * grounded

	-- braking squat / accelerating lift, lean into turns
	local brake = smoothstep(6, 26, -state.Accel) * smoothstep(4, 12, state.Speed)
	local accelPitch = clamp(state.Accel * 0.004, -0.02, 0.05) + brake * 0.16
	local lean = clamp(-state.TurnRate * state.Speed * 0.0042, -0.2, 0.2) * grounded

	local rear = stepSpring(state.Rear, sample.Rear or 0, dt)
	local buck = stepSpring(state.Buck, sample.Buck or 0, dt)
	local startle = sample.Startle or 0

	local height = stepSpring(state.Height, terrainHeight, dt)
	local pitch = stepSpring(state.Pitch, terrainPitch + accelPitch, dt)
	local roll = stepSpring(state.Roll, lean + rollOsc, dt)

	local airPitch = clamp(velocity.Y * 0.012, -0.35, 0.3) * state.Air
	local swimSink = -0.9 * state.Swim

	-- rear pivots on the hind hooves, buck pivots on the front hooves
	local bodyY = height + bob - crouch * state.Moving * grounded - brake * 0.18 + swimSink - startle * 0.08
	-- never lift the body so high that a planted hoof (e.g. on a lower step) can't be reached
	local limit = math.huge
	if grounded > 0.5 then
		for _, name in LEGS do
			local leg = state.Legs[name]
			-- planted hooves, and hooves about to land
			local point = if leg.Swinging then (if leg.SwingT > 0.45 then leg.Target else nil) else leg.Plant
			if point then
				local def = leg.Def
				local hipRest = rootCF:PointToWorldSpace(def.Hip)
				local horizontal = math.max(flat(point - hipRest).Magnitude - HIP_SLIDE, 0)
				local chainLength = def.Upper + def.Lower
				local reachY = math.sqrt(math.max(chainLength * chainLength - horizontal * horizontal, 0)) * 0.985
				limit = math.min(limit, point.Y + HOOF + reachY - hipRest.Y)
			end
		end
	end
	-- drop at once when a hoof needs it, but rise back smoothly when it lets go
	local previous = state.ReachLimit or limit
	if limit > previous then
		limit = math.min(limit, previous + (if previous == math.huge then 0 else 1) * 4 * dt)
	end
	state.ReachLimit = limit
	bodyY = math.min(bodyY, limit)
	local body = CFrame.new(0, bodyY, 0)
		* CFrame.Angles(pitch + pitchOsc + airPitch + state.Swim * 0.12, 0, roll)
	if rear > 1e-3 then
		local pivot = Vector3.new(0, -1.6, L.Legs.HL.Hip.Z)
		body = body * CFrame.new(pivot) * CFrame.Angles(rear * 1.0, 0, 0) * CFrame.new(-pivot)
	end
	if math.abs(buck) > 1e-3 then
		local pivot = Vector3.new(0, -1.5, L.Legs.FL.Hip.Z)
		body = body * CFrame.new(pivot) * CFrame.Angles(-buck * 0.42, 0, 0) * CFrame.new(-pivot)
	end
	state.BodyTransform = body
	local barrelCF = rootCF * body

	-- Legs -------------------------------------------------------------------------------------
	local transforms = state.Transforms
	local planarVelocity = flatVelocity
	local stanceTime = duty / math.max(freq, 0.1)
	local swingTime = (1 - duty) / math.max(freq, 0.1)
	local anySwinging = false
	local levelRotation = CFrame.lookAt(Vector3.zero, look)

	for _, name in LEGS do
		local leg = state.Legs[name]
		local def = leg.Def
		local rest = restPoint(rootCF, def)
		-- velocity of this hip including the body's rotation
		local r = rest - rootCF.Position
		local hipVelocity = planarVelocity + Vector3.new(omega * r.Z, 0, -omega * r.X)

		-- each leg's phase is pulled towards the gait's pattern (no pops when gaits change)
		local wantPhase = wrap01(state.Phase + offsets[name])
		local legPhaseRate = freq * state.Moving
		local phaseStep = legPhaseRate * dt + circularDelta(leg.Phase, wantPhase) * math.min(1, 3 * dt) * state.Moving
		leg.Phase = wrap01(leg.Phase + phaseStep)

		if leg.Plant == nil then
			leg.Plant = Vector3.new(rest.X, groundAt(ground, rest), rest.Z)
		end

		-- Swings normally follow the stride phase; forced steps (reaching too far, squaring up
		-- after stopping) and swings interrupted by stopping run on a short timer instead.
		local plant = leg.Plant :: Vector3
		local inSwingRange = leg.Phase >= duty
		if not inSwingRange and leg.Mode == "Stance" then
			leg.Armed = true
		end
		if leg.Mode == "Phase" and state.Moving < 0.3 then
			leg.Mode = "Timed"
			leg.SwingTime = math.max(0.12, (1 - leg.SwingT) * 0.3)
			leg.TimedFrom = leg.SwingT
		end
		if leg.Mode == "Stance" and grounded > 0.5 then
			local tooFar = flat(plant - rest).Magnitude > MAX_REACH
			local settle = state.Settling == name
			if state.Moving > 0.05 and inSwingRange and leg.Armed then
				leg.Mode = "Phase"
			elseif tooFar or settle then
				leg.Mode = "Timed"
				leg.SwingTime = if settle then 0.32 else math.max(swingTime, 0.14)
				leg.TimedFrom = 0
			end
			if leg.Mode ~= "Stance" then
				leg.Armed = false
				leg.Settle = settle
				leg.From = plant
				leg.SwingT = 0
				leg.Target = plant
				leg.FirstFrame = true
			end
		end
		leg.Swinging = leg.Mode ~= "Stance"

		local foot: Vector3
		if leg.Swinging then
			local remaining: number
			if leg.Mode == "Phase" then
				-- advance with the stride (not from the absolute phase, which jumps when the duty
				-- factor changes between gaits); finish briskly once the stride says "land"
				local nominal = freq * dt / math.max(1 - duty, 0.05)
				local ds = math.min(math.max(phaseStep, 0) / math.max(1 - duty, 0.05), nominal * 1.5)
				if not inSwingRange then
					ds = math.max(ds, math.min(nominal * 1.5, 0.15))
				end
				leg.SwingT = math.min(1, leg.SwingT + ds)
				remaining = (1 - leg.SwingT) * swingTime
			else
				leg.SwingT = math.min(1, leg.SwingT + dt / leg.SwingTime * (1 - (leg.TimedFrom or 0)))
				remaining = (1 - leg.SwingT) * leg.SwingTime
			end
			-- aim ahead so the hoof lands in front of its hip by half a stance
			local lead = if leg.Settle then Vector3.zero else hipVelocity * (remaining + stanceTime * 0.5)
			if lead.Magnitude > MAX_REACH * 0.92 then
				lead = lead.Unit * MAX_REACH * 0.92
			end
			local aim = rest + lead
			local target = Vector3.new(aim.X, 0, aim.Z)
			local targetY: number
			if leg.FirstFrame then
				leg.FirstFrame = false
				targetY = groundAt(ground, target)
			else
				target = flat(leg.Target):Lerp(target, 1 - math.exp(-14 * dt))
				-- ease height changes (a step edge under the target) instead of snapping
				targetY = approach(leg.Target.Y, groundAt(ground, target), 30, dt)
			end
			leg.Target = Vector3.new(target.X, targetY, target.Z)
			local s = leg.SwingT
			local eased = s * s * s * (s * (s * 6 - 15) + 10)
			local rise = math.max(0, leg.Target.Y - leg.From.Y)
			local arc = (lift * (if leg.Front then 1.1 else 0.85) * (if leg.Settle then 0.5 else 1) + rise * 0.6)
				* math.sin(math.pi * s) ^ 0.8
			foot = leg.From:Lerp(leg.Target, eased) + UP * arc
			if s >= 1 then
				leg.Mode = "Stance"
				leg.Swinging = false
				leg.Target = Vector3.new(leg.Target.X, groundAt(ground, leg.Target), leg.Target.Z)
				leg.Plant = leg.Target
				foot = leg.Target
				if state.Settling == name then
					state.Settling = nil
				end
				table.insert(state.Events, { Leg = name, Position = leg.Target, Front = leg.Front })
			end
			anySwinging = anySwinging or leg.Swinging
		else
			foot = plant
		end
		leg.GroundY = foot.Y

		-- body-space overrides: jump tuck, swimming paddle, rearing forelegs, bucking hind legs
		local override: Vector3? = nil
		local overrideWeight = 0
		if state.Air > 0.01 then
			local rising = smoothstep(-8, 8, velocity.Y)
			local tuck: Vector3
			if leg.Front then
				tuck = Vector3.new(0, -1.55, -0.1):Lerp(Vector3.new(0, -2.75, -0.85), 1 - rising)
			else
				tuck = Vector3.new(0, -2.6, 1.0):Lerp(Vector3.new(0, -1.9, 0.35), 1 - rising)
			end
			override = barrelCF:PointToWorldSpace(def.Hip + tuck)
			overrideWeight = state.Air
		end
		if state.Swim > 0.01 then
			local sp = TAU * (t * 1.1 + (if leg.Front then 0 else 0.5) + (if def.Side < 0 then 0.25 else 0))
			local paddle = Vector3.new(0, -2.2 + 0.35 * math.sin(sp), -0.55 * math.cos(sp) * (if leg.Front then 1 else -0.6))
			local p = barrelCF:PointToWorldSpace(def.Hip + paddle)
			override = if override then override:Lerp(p, state.Swim) else p
			overrideWeight = math.max(overrideWeight, state.Swim)
		end
		if rear > 0.05 and leg.Front then
			local paw = math.sin(t * 7 + (if def.Side < 0 then 0 else 1.8))
			local p = barrelCF:PointToWorldSpace(def.Hip + Vector3.new(0, -1.9 + 0.35 * paw, -0.9 - 0.3 * paw))
			override = if override then override:Lerp(p, rear) else p
			overrideWeight = math.max(overrideWeight, smoothstep(0.05, 0.4, rear))
		end
		local kick = sample.Kick or 0
		if kick > 0.02 and not leg.Front then
			local p = barrelCF:PointToWorldSpace(def.Hip + Vector3.new(def.Side * 0.1, -1.6, 2.1))
			override = if override then override:Lerp(p, kick) else p
			overrideWeight = math.max(overrideWeight, kick)
		end
		if override then
			foot = foot:Lerp(override, overrideWeight)
		end
		leg.Foot = foot

		-- IK in barrel space
		local fetlock = foot + UP * HOOF
		local d = barrelCF:PointToObjectSpace(fetlock) - def.Hip
		-- the shoulder/hip slides towards far-forward or far-back hooves (like a real scapula)
		local slide = clamp(d.Z * 0.32, -HIP_SLIDE, HIP_SLIDE)
		d -= Vector3.new(0, 0, slide)
		local rawAbduction = math.atan2(d.X, math.max(-d.Y, 0.2))
		local abduction = clamp(rawAbduction, -MAX_ABDUCTION, MAX_ABDUCTION)
		local down = math.sqrt(d.X * d.X + d.Y * d.Y) * (if d.Y > 0 then -1 else 1)
		local legLength = def.Upper + def.Lower
		local unreachable = math.sqrt(down * down + d.Z * d.Z) > legLength - 0.01
			or math.abs(rawAbduction) > MAX_ABDUCTION - 0.02
		local trailing = flat(foot - rest):Dot(hipVelocity) < 0
		if not leg.Swinging and overrideWeight == 0 and unreachable and trailing then
			-- a trailing hoof is about to be dragged: pick it up now
			leg.Mode = "Timed"
			leg.Swinging = true
			leg.SwingT = 0
			leg.TimedFrom = 0
			leg.SwingTime = math.max(swingTime, 0.14)
			leg.From = foot
			leg.Target = foot
			leg.FirstFrame = true
			leg.Armed = false
			leg.Settle = false
		end
		local thetaUpper, thetaKnee = HorseGait.SolveLeg(def.Upper, def.Lower, -d.Z, down, def.Front)
		-- Keep the hoof level with the horse's heading (undo the leg's pitch, splay and the body's
		-- tilt); while swinging it curls back.
		local curl = 0
		if leg.Swinging then
			curl = math.sin(math.pi * leg.SwingT) * (if leg.Front then -1.25 else -0.55) * (if leg.Settle then 0.4 else 1)
		end
		if overrideWeight > 0 then
			curl += (if leg.Front then -1.1 else -0.4) * overrideWeight * (1 - state.Swim * 0.5)
		end
		local hipT = CFrame.new(0, 0, slide) * CFrame.Angles(0, 0, abduction) * CFrame.Angles(thetaUpper, 0, 0)
		local lowerRotation = barrelCF.Rotation * hipT.Rotation * CFrame.Angles(thetaKnee, 0, 0)
		transforms[name .. "Hip"] = hipT
		transforms[name .. "Knee"] = CFrame.Angles(thetaKnee, 0, 0)
		transforms[name .. "Fetlock"] = lowerRotation:Inverse() * levelRotation * CFrame.Angles(curl, 0, 0)
	end

	-- Standing: square up one foot at a time.
	if state.Moving < 0.05 and not anySwinging and state.Settling == nil and t >= state.NextSettleCheck then
		state.NextSettleCheck = t + 0.25
		local worst, worstDistance = nil, SETTLE_DISTANCE
		for _, name in LEGS do
			local leg = state.Legs[name]
			local distance = flat((leg.Plant :: Vector3) - restPoint(rootCF, leg.Def)).Magnitude
			if distance > worstDistance then
				worst, worstDistance = name, distance
			end
		end
		state.Settling = worst
	end

	-- Neck, head, tail ---------------------------------------------------------------------------
	local graze = stepSpring(state.Graze, sample.Graze or 0, dt)
	local alert = stepSpring(state.Alert, sample.Alert or 0, dt)
	local lookYaw = 0
	if sample.LookAt then
		local localLook = rootCF:PointToObjectSpace(sample.LookAt)
		lookYaw = clamp(math.atan2(-localLook.X, -localLook.Z), -0.9, 0.9)
	end
	local neckYaw = stepSpring(state.NeckYaw, clamp(state.TurnRate * 0.22, -0.35, 0.35) + lookYaw * 0.55, dt)
	local gallop = w[4] * moving
	local neckPitch = neckBase * moving + nod - alert * 0.28 + graze * 1.05 - rear * 0.5 + buck * 0.35
		+ state.Air * clamp(-velocity.Y * 0.01, -0.25, 0.2) - state.Swim * 0.35 - startle * 0.3
	local chew = graze * 0.05 * math.sin(t * 9)
	local headPitch = -nod * 0.4 + graze * 0.55 + alert * 0.12 + chew - state.Swim * 0.2
	-- neck frame: bend about the body's vertical axis (yaw) and the neck's side axis (pitch)
	local tilt = L.NeckTilt
	local yawAxis = Vector3.new(0, math.cos(tilt), math.sin(tilt))
	transforms.Neck = CFrame.fromAxisAngle(yawAxis, neckYaw) * CFrame.Angles(-neckPitch, 0, 0)
	transforms.Head = CFrame.Angles(-headPitch, lookYaw * 0.35 * (1 - graze), 0)

	local tailLift = stepSpring(state.TailLift, gallop * 0.75 + alert * 0.25 + rear * 0.4 + buck * 0.6, dt)
	local swishTarget = math.sin(t * 1.3) * 0.25 + math.sin(t * 3.7 + 1) * 0.1 * (1 - moving)
		- state.TurnRate * 0.25 + (sample.Startle or 0) * 0.6
	local swish = stepSpring(state.TailSwish, swishTarget, dt)
	local trail = clamp(state.Speed * 0.012, 0, 0.45)
	transforms.Tail1 = CFrame.Angles(-tailLift - trail * 0.5, 0, swish)
	transforms.Tail2 = CFrame.Angles(-trail * 0.6 + tailLift * 0.2, 0, swish * 0.6 + 0.05 * math.sin(t * 5))
	transforms.Tail3 = CFrame.Angles(-trail * 0.5, 0, swish * 0.5 + 0.08 * math.sin(t * 5 + 1))
	transforms.Body = body

	return transforms, state.Events
end

HorseGait.Gaits = GAITS

return HorseGait
