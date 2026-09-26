--[[
	lune run tools/lune/test-horses.luau <place.rbxl> <out-dir>

	1. Builds a horse of every coat (+ tack) and checks joints, Humanoid setup and the rest pose.
	2. Runs the real gait solver (HorseGait) through walk/trot/canter/gallop, turning on the spot,
	   speeding up and stopping, slopes and steps, then poses the rig with forward kinematics and
	   measures what players would notice: hooves sliding while planted, hooves floating or sinking,
	   and pops (hooves jumping between frames).
	3. Writes <out-dir>/town.json with a line-up of poses for the preview renderer.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = require("./harness")
local RigFK = require("./rigfk")
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

local placePath = process.args[1] or "build/SicilyDemo.rbxl"
local outDir = process.args[2] or "tools/preview/out-horses"
fs.writeDir(outDir)

local game, requireModule = Harness.load(placePath)
local shared = game:GetService("ReplicatedStorage").SicilyShared
local HorseRig = requireModule(shared.HorseRig)
local HorseGait = requireModule(shared.HorseGait)
local HorseTypes = requireModule(shared.HorseTypes)

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local L = HorseRig.Layout

-- 1. Structure -----------------------------------------------------------------------------------
for _, coat in HorseTypes.CoatNames() do
	local horse = HorseRig.Build({ Coat = coat, CFrame = CFrame.new(0, L.RootHeight, 0) })
	local joints = HorseRig.GetJoints(horse)
	for _, name in HorseRig.JointNames do
		check(joints[name] ~= nil, coat .. ": missing joint " .. name)
	end
	local humanoid = horse:FindFirstChildOfClass("Humanoid")
	check(humanoid and humanoid.RigType == roblox.Enum.HumanoidRigType.R15, coat .. ": humanoid")
	check(math.abs(humanoid.HipHeight - (L.RootHeight - L.RootSize.Y / 2)) < 1e-4, coat .. ": hip height")
	check(horse.PrimaryPart and horse.PrimaryPart.Name == "HumanoidRootPart", coat .. ": primary part")
	-- rest pose consistency: FK with identity transforms reproduces the built parts
	local rig = RigFK.Capture(horse)
	local cfs = RigFK.Pose(rig, horse.PrimaryPart.CFrame, {})
	for part, cf in cfs do
		check((part.CFrame.Position - cf.Position).Magnitude < 1e-3, coat .. ": rest pose mismatch on " .. part.Name)
	end
	local collide = 0
	for _, d in horse:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			collide += 1
		end
	end
	check(collide == 1, coat .. ": only the root should collide (got " .. collide .. ")")
end
local tacked = HorseRig.Build({ Coat = "Bay" })
HorseRig.AddTack(tacked)
check(tacked:FindFirstChild("Saddle") ~= nil and tacked:GetAttribute("Tack") == true, "tack added")

-- 2. Gait simulation -----------------------------------------------------------------------------
local temperament = HorseTypes.GetTemperament("Spirited")
local HOOF = L.HoofHeight

local grounds = {
	Flat = function(_p)
		return 0
	end,
	Slope = function(p)
		return -0.32 * p.Z -- uphill towards -Z (the horse's forward)
	end,
	Steps = function(p)
		return math.floor(-p.Z / 3) * 0.6
	end,
}

local function speedProfile(sc, time)
	if sc.Profile == "accelerate" then
		return math.min(temperament.GallopSpeed, time * 9)
	elseif sc.Profile == "stop" then
		return math.max(0, temperament.GallopSpeed - math.max(0, time - 2) * 14)
	end
	return sc.Speed
end

local scenarios = {
	{ Name = "idle", Speed = 0, Time = 3 },
	{ Name = "walk", Speed = temperament.WalkSpeed, Time = 4 },
	{ Name = "trot", Speed = temperament.TrotSpeed, Time = 4 },
	{ Name = "canter", Speed = temperament.CanterSpeed, Time = 4 },
	{ Name = "gallop", Speed = temperament.GallopSpeed, Time = 4 },
	{ Name = "turn-in-place", Speed = 0, Turn = 1.6, Time = 3 },
	{ Name = "turn-walk", Speed = temperament.WalkSpeed, Turn = 1.2, Time = 4 },
	{ Name = "turn-gallop", Speed = temperament.GallopSpeed, Turn = 0.9, Time = 4 },
	{ Name = "accelerate", Profile = "accelerate", Time = 5 },
	{ Name = "stop", Profile = "stop", Time = 6 },
	{ Name = "backwards", Speed = -temperament.BackSpeed, Time = 3 },
	{ Name = "slope-walk", Speed = temperament.WalkSpeed, Ground = "Slope", Time = 4 },
	{ Name = "slope-gallop", Speed = temperament.GallopSpeed, Ground = "Slope", Time = 3 },
	{ Name = "steps-trot", Speed = temperament.TrotSpeed, Ground = "Steps", Time = 4 },
}

local sampleHorse = HorseRig.Build({ Coat = "Bay" })
local sampleRig = RigFK.Capture(sampleHorse)
local hoofParts = {}
for _, name in L.LegOrder do
	hoofParts[name] = sampleHorse:FindFirstChild(name .. "Hoof")
end

local function hoofBottom(cfs, name)
	local cf = cfs[hoofParts[name]]
	return (cf * CFrame.new(0, -HOOF / 2, -0.04)).Position
end

print("Gait checks (studs): slide = max hoof drift while planted, float/sink = planted hoof vs ground")
print(("  %-15s %7s %7s %7s %6s %6s"):format("scenario", "slide", "float", "sink", "pops", "steps"))
local results = {}
for _, sc in scenarios do
	local ground = grounds[sc.Ground or "Flat"]
	local groundFn = function(p)
		return ground(p)
	end
	math.randomseed(tonumber(process.args[3]) or 7)
	local state = HorseGait.New(temperament)
	local dt = 1 / 60
	local pos = Vector3.new(0, 0, 0)
	local yaw = 0
	local lastBottoms = {}
	local plantedAt = {}
	local maxSlide, maxFloat, maxSink, pops, steps = 0, 0, 0, 0, 0
	local frames = math.floor(sc.Time / dt)
	local lastVelocity = Vector3.zero
	for f = 1, frames do
		local time = f * dt
		local speed = speedProfile(sc, time)
		local turn = sc.Turn or 0
		yaw += turn * dt
		local heading = CFrame.Angles(0, yaw, 0)
		local velocity = heading.LookVector * speed
		pos += velocity * dt
		local rootCF = CFrame.new(pos.X, ground(pos) + L.RootHeight, pos.Z) * heading
		local transforms, events = HorseGait.Step(state, {
			RootCFrame = rootCF,
			Velocity = velocity,
			AngularVelocity = turn,
			Mode = "Ground",
		}, dt, groundFn)
		steps += #events
		local cfs = RigFK.Pose(sampleRig, rootCF, transforms)
		local settled = time > 1.2 -- ignore the first second (starting from a square stance)
		for _, name in L.LegOrder do
			local leg = state.Legs[name]
			local bottom = hoofBottom(cfs, name)
			if not leg.Swinging then
				if plantedAt[name] == nil then
					plantedAt[name] = bottom
				elseif settled then
					maxSlide = math.max(maxSlide, (bottom - plantedAt[name]).Magnitude)
				end
				if settled then
					-- the planted hoof sits on its plant, and the plant sits on the ground
					local plant = leg.Plant
					local gy = ground(plant)
					maxFloat = math.max(maxFloat, bottom.Y - plant.Y, plant.Y - gy)
					maxSink = math.max(maxSink, plant.Y - bottom.Y, gy - plant.Y)
				end
			else
				plantedAt[name] = nil
			end
			if lastBottoms[name] and settled then
				local jump = (bottom - lastBottoms[name]).Magnitude
				if jump > math.abs(speed) * dt * 2.5 + 0.6 then
					pops += 1
				end
			end
			lastBottoms[name] = bottom
		end
		for jointName, cf in transforms do
			local x, y, z = cf:ToEulerAnglesXYZ()
			check(x == x and y == y and z == z, sc.Name .. ": NaN in " .. jointName)
		end
		lastVelocity = velocity
	end
	local _ = lastVelocity
	results[sc.Name] = { Slide = maxSlide, Float = maxFloat, Sink = maxSink, Pops = pops, Steps = steps }
	print(("  %-15s %7.3f %7.3f %7.3f %6d %6d"):format(sc.Name, maxSlide, maxFloat, maxSink, pops, steps))
	check(maxSlide < 0.12, sc.Name .. ": planted hooves slide " .. maxSlide)
	check(maxFloat < 0.2, sc.Name .. ": planted hooves float " .. maxFloat)
	check(maxSink < 0.2, sc.Name .. ": planted hooves sink " .. maxSink)
	check(pops == 0, sc.Name .. ": " .. pops .. " hoof pops")
	if sc.Speed ~= 0 or sc.Turn or sc.Profile then
		check(steps > 0, sc.Name .. ": the horse never took a step")
	end
end
check(results.idle.Steps == 0, "idle horse shouldn't step")

-- IK round trip
for _, front in { true, false } do
	for _, target in { { 0, 2.9 }, { 0.8, 2.6 }, { -1.1, 2.4 }, { 1.4, 1.8 }, { 0.2, 1.7 } } do
		local u, l = 1.6, 1.45
		local a, k = HorseGait.SolveLeg(u, l, target[1], target[2], front)
		local fwd, down = HorseGait.LegEnd(u, l, a, k)
		check(math.abs(fwd - target[1]) < 1e-3 and math.abs(down - target[2]) < 1e-3, ("IK round trip (%s, %s)"):format(tostring(front), table.concat(target, ",")))
		check((if front then k <= 0 else k >= 0), "knee bends the right way")
	end
end

-- 3. Preview line-up -------------------------------------------------------------------------------
local out = {}
local poses = {
	{ Name = "stand", Coat = "Bay", Speed = 0, Time = 2 },
	{ Name = "walk", Coat = "Chestnut", Speed = temperament.WalkSpeed, Time = 2.35 },
	{ Name = "trot", Coat = "Grey", Speed = temperament.TrotSpeed, Time = 2.2 },
	{ Name = "canter", Coat = "Palomino", Speed = temperament.CanterSpeed, Time = 2.1 },
	{ Name = "gallop", Coat = "Black", Speed = temperament.GallopSpeed, Time = 2.05 },
	{ Name = "gallop2", Coat = "Pinto", Speed = temperament.GallopSpeed, Time = 2.25 },
	{ Name = "graze", Coat = "Dun", Speed = 0, Time = 4, Graze = 1 },
	{ Name = "rear", Coat = "Bay", Speed = 0, Time = 2, Rear = 1 },
	{ Name = "buck", Coat = "Chestnut", Speed = 0, Time = 2, Buck = 1, Kick = 1 },
	{ Name = "jump", Coat = "Grey", Speed = 20, Time = 1.5, Air = true },
	{ Name = "tack", Coat = "Bay", Speed = 0, Time = 1.5, Tack = true },
}
for index, p in poses do
	local horse = HorseRig.Build({ Coat = p.Coat })
	if p.Tack then
		HorseRig.AddTack(horse)
	end
	local rig = RigFK.Capture(horse)
	local state = HorseGait.New(temperament)
	local dt = 1 / 60
	local pos = Vector3.zero
	local transforms
	for f = 1, math.floor(p.Time / dt) do
		local velocity = Vector3.new(0, if p.Air then 12 - f * dt * 6 else 0, -p.Speed)
		pos += Vector3.new(0, 0, -p.Speed) * dt
		transforms = HorseGait.Step(state, {
			RootCFrame = CFrame.new(pos.X, L.RootHeight, pos.Z),
			Velocity = velocity,
			AngularVelocity = 0,
			Mode = if p.Air then "Air" else "Ground",
			Graze = p.Graze,
			Rear = p.Rear,
			Buck = p.Buck,
			Kick = p.Kick,
		}, dt, function()
			return 0
		end)
	end
	-- line up along X, side-on to the camera (horse faces -X in the picture)
	local display = CFrame.new((index - 1) * 11 - 55, L.RootHeight + (if p.Air then 1.5 else 0), 0) * CFrame.Angles(0, math.pi / 2, 0)
	local rootCF = display
	-- shift the posed feet back under the display root
	local cfs = RigFK.Pose(rig, rootCF, transforms)
	RigFK.Emit(out, cfs)
end
-- 4. Riders --------------------------------------------------------------------------------------
local R6 = requireModule(shared.R6)
local HorseMount = requireModule(shared.HorseMount)
local Animator = requireModule(game:GetService("StarterPlayer").StarterPlayerScripts.SicilyClient.Animator)
local Solve, BlankState = Animator._Test.Solve, Animator._Test.BlankState
local SEAT = HorseMount.SeatOffset()
local ROOT_C0 = R6.Joints[1].C0

local riderScenes = {
	{ Name = "seated", Speed = 0, Phase = "Seated", U = 1 },
	{ Name = "trot", Speed = temperament.TrotSpeed, Phase = "Seated", U = 1, Time = 2.3 },
	{ Name = "gallop", Speed = temperament.GallopSpeed, Phase = "Seated", U = 1, Time = 2.1 },
	{ Name = "mount-step", Speed = 0, Phase = "Mount", U = 0.25 },
	{ Name = "mount-swing", Speed = 0, Phase = "Mount", U = 0.62 },
	{ Name = "dismount", Speed = 0, Phase = "Dismount", U = 0.45 },
}
local riderOut = {}
for index, scene in riderScenes do
	local horse = HorseRig.Build({ Coat = if index % 2 == 0 then "Grey" else "Bay" })
	HorseRig.AddTack(horse)
	local hrig = RigFK.Capture(horse)
	local hstate = HorseGait.New(temperament)
	local dt = 1 / 60
	local pos = Vector3.zero
	local htransforms
	for _ = 1, math.floor((scene.Time or 1.5) / dt) do
		pos += Vector3.new(0, 0, -scene.Speed) * dt
		htransforms = HorseGait.Step(hstate, {
			RootCFrame = CFrame.new(pos.X, L.RootHeight, pos.Z),
			Velocity = Vector3.new(0, 0, -scene.Speed),
			AngularVelocity = 0,
			Mode = "Ground",
		}, dt, function()
			return 0
		end)
	end
	-- rider pose from the real animator
	local rstate = BlankState()
	local motors = {}
	for _, joint in R6.Joints do
		motors[joint.Name] = { Transform = CFrame.new() }
	end
	rstate.Motors = motors
	local joint = { Attributes = {} }
	local from = CFrame.new(-4.5, -3.19, 1.5) * CFrame.Angles(0, math.pi / 2, 0)
	local jointTransform = if scene.Phase == "Mount"
		then HorseMount.MountTransform(from, scene.U)
		elseif scene.Phase == "Dismount" then HorseMount.DismountTransform(HorseMount.ChooseDismount(), scene.U)
		else CFrame.new()
	local blend = if scene.Phase == "Seated" then 1 elseif scene.Phase == "Mount" then math.clamp((scene.U - 0.6) / 0.4, 0, 1) else 1 - math.clamp(scene.U / 0.4, 0, 1)
	local saddle = CFrame.new():Lerp(SEAT:Inverse() * hstate.BodyTransform * SEAT, blend)
	local riding = { Phase = scene.Phase, Progress = scene.U, Gait = hstate, Saddle = saddle }
	for f = 1, 90 do
		Solve(rstate, {
			Velocity = Vector3.new(0, 0, -scene.Speed),
			RootCFrame = CFrame.new(),
			Anchored = false,
			State = roblox.Enum.HumanoidStateType.PlatformStanding,
			Sit = false,
			Riding = riding,
		}, 1 / 60, f / 60, CFrame.new(0, 10, 30))
	end
	local _ = joint
	-- place: horse side-on to the camera, rider on its saddle
	local display = CFrame.new((index - 1) * 11 - 27.5, L.RootHeight, 40) * CFrame.Angles(0, math.pi / 2, 0)
	RigFK.Emit(riderOut, RigFK.Pose(hrig, display, htransforms))
	local rider = R6.Build({ Name = "Rider", BodyColors = { Head = Color3.fromRGB(234, 184, 146), Arms = Color3.fromRGB(234, 184, 146), Torso = Color3.fromRGB(150, 60, 50), Legs = Color3.fromRGB(60, 58, 64) } })
	local rrig = RigFK.Capture(rider)
	local rtransforms = {}
	for name, m in motors do
		rtransforms[name] = m.Transform
	end
	local riderRoot = display * SEAT * jointTransform
	RigFK.Emit(riderOut, RigFK.Pose(rrig, riderRoot, rtransforms))
	-- the seated rider's hips should sit on the saddle (not float above or sink into it)
	if scene.Phase == "Seated" and scene.Speed == 0 then
		local cfs = RigFK.Pose(rrig, riderRoot, rtransforms)
		local torso = cfs[rider.Torso]
		local hipY = (torso * CFrame.new(0, -1, 0)).Position.Y
		local seatY = (display * CFrame.new(0, L.SeatHeight, 0)).Position.Y
		check(math.abs(hipY - seatY) < 0.25, ("rider hips %.2f vs seat %.2f"):format(hipY, seatY))
	end
	local _ = ROOT_C0
end
for _, item in riderOut do
	table.insert(out, item)
end

fs.writeFile(outDir .. "/town.json", serde.encode("json", { parts = out, lights = {} }))

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
