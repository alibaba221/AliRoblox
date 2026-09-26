--[[
	lune run tools/lune/test-riding.luau <place.rbxl>

	Checks the feel numbers of riding without Roblox physics:
	  1. HorseMotor driving a simulated horse: time to trot / gallop, turning circle at each gait,
	     braking distance, stamina and spur bursts, no instant rotation.
	  2. Taming: how long it takes (or fails) at different press rates, for every temperament.
	  3. The riderless-horse brain: grazing / wandering, bolting from a running player, turning
	     to watch a walking one, coming to its owner's whistle, getting unstuck.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Harness = require("./harness")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local game, requireModule = Harness.load(process.args[1] or "build/SicilyDemo.rbxl")
local shared = game:GetService("ReplicatedStorage").SicilyShared
local HorseMotor = requireModule(shared.HorseMotor)
local HorseTypes = requireModule(shared.HorseTypes)
local Taming = requireModule(shared.Taming)
local Brain = requireModule(game:GetService("ServerScriptService").SicilyServer.Horses.Brain)

roblox.implementMethod("Workspace", "Raycast", function()
	return nil
end)

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- 1. Motor ----------------------------------------------------------------------------------------
-- A stand-in for the horse's Humanoid + root: moves at WalkSpeed along the Move direction and
-- turns towards the AlignOrientation target like a stiff spring.
local function fakeHorse()
	local horse = {
		Position = Vector3.zero,
		Yaw = 0,
		Velocity = Vector3.zero,
		WalkSpeed = 0,
		MoveDir = Vector3.zero,
		Jumped = false,
	}
	local humanoid = {
		JumpHeight = 0,
		GetState = function()
			return roblox.Enum.HumanoidStateType.Running
		end,
		Move = function(_, direction)
			horse.MoveDir = direction
		end,
	}
	setmetatable(humanoid, {
		__newindex = function(t, k, v)
			if k == "WalkSpeed" then
				horse.WalkSpeed = v
			elseif k == "Jump" then
				horse.Jumped = v
			else
				rawset(t, k, v)
			end
		end,
	})
	local root = {}
	setmetatable(root, {
		__index = function(_, k)
			if k == "CFrame" then
				return CFrame.new(horse.Position) * CFrame.Angles(0, horse.Yaw, 0)
			elseif k == "Position" then
				return horse.Position
			elseif k == "AssemblyLinearVelocity" then
				return horse.Velocity
			elseif k == "AssemblyAngularVelocity" then
				return Vector3.zero
			elseif k == "Parent" then
				return true
			end
			return nil
		end,
	})
	local align = { CFrame = CFrame.new() }
	local motor = setmetatable({}, HorseMotor)
	motor.Model = {}
	motor.Humanoid = humanoid
	motor.Root = root
	motor.Align = align
	motor.Temperament = HorseTypes.GetTemperament("Spirited")
	motor.Speed = 0
	motor.Heading = 0
	motor.TurnRate = 0
	motor.Stamina = motor.Temperament.Stamina
	motor.Winded = 0
	motor.SinceGallop = 10
	motor.Spur = 0
	motor.JumpCooldown = 0
	motor.Slope = 0
	motor.NextSlopeCheck = math.huge
	motor.Blocked = 0
	motor.Gait = 0
	local function physics(dt)
		-- the body follows the align target quickly; velocity follows WalkSpeed * MoveDir
		local _, targetYaw = align.CFrame:ToEulerAnglesYXZ()
		local diff = (targetYaw - horse.Yaw + math.pi) % (2 * math.pi) - math.pi
		horse.Yaw += diff * math.min(1, 25 * dt)
		horse.Velocity = horse.MoveDir * horse.WalkSpeed
		horse.Position += horse.Velocity * dt
	end
	return motor, horse, physics
end

local t = HorseTypes.GetTemperament("Spirited")
local dt = 1 / 60

local function timeToReach(gait: number, speed: number): number
	local motor, _, physics = fakeHorse()
	for f = 1, 60 * 20 do
		motor:Update(dt, { Gait = gait, Direction = Vector3.new(0, 0, -1) })
		physics(dt)
		if motor.Speed >= speed * 0.97 then
			return f * dt
		end
	end
	return math.huge
end
local toTrot = timeToReach(2, t.TrotSpeed)
local toGallop = timeToReach(4, t.GallopSpeed)
print(("Motor: 0 -> trot %.2fs, 0 -> gallop %.2fs"):format(toTrot, toGallop))
check(toTrot > 0.8 and toTrot < 3, "time to trot " .. toTrot)
check(toGallop > 2.5 and toGallop < 6.5, "time to gallop " .. toGallop)

-- turning circle: hold full steer at each gait
for _, gait in { 1, 2, 3, 4 } do
	local motor, horse, physics = fakeHorse()
	for _ = 1, 60 * 6 do
		motor:Update(dt, { Gait = gait, Direction = Vector3.new(0, 0, -1) })
		physics(dt)
	end
	local speed = motor.Speed
	local yaw0 = motor.Heading
	local maxRate = 0
	local start = horse.Position
	for f = 1, 60 * 3 do
		local left = CFrame.Angles(0, motor.Heading + math.pi / 2, 0).LookVector
		motor:Update(dt, { Gait = gait, Direction = left })
		physics(dt)
		maxRate = math.max(maxRate, math.abs(motor.TurnRate))
		local _ = f
	end
	local radius = speed / math.max(maxRate, 1e-3)
	print(("  gait %d: speed %.1f, turn rate %.0f deg/s, turning radius %.1f studs"):format(gait, speed, math.deg(maxRate), radius))
	check(math.deg(maxRate) <= t.TurnRates.Idle * 1.2, "turn rate capped")
	local _ = { yaw0, start }
end

-- no instant rotation: one frame of a 180° request turns only a little
do
	local motor, _, physics = fakeHorse()
	motor:Update(dt, { Gait = 0, Direction = Vector3.new(0, 0, 1) })
	physics(dt)
	check(math.abs(motor.Heading) < math.rad(3), "a 180-degree request must not snap the heading")
end

-- braking from a gallop
do
	local motor, horse, physics = fakeHorse()
	for _ = 1, 60 * 6 do
		motor:Update(dt, { Gait = 4, Direction = Vector3.new(0, 0, -1) })
		physics(dt)
	end
	local start = horse.Position
	local frames = 0
	while motor.Speed > 0.5 and frames < 600 do
		motor:Update(dt, { Gait = 0, Brake = true })
		physics(dt)
		frames += 1
	end
	local distance = (horse.Position - start).Magnitude
	print(("  braking from %.0f: %.2fs over %.1f studs"):format(t.GallopSpeed, frames * dt, distance))
	check(distance > 10 and distance < 40, "braking distance " .. distance)
end

-- stamina: galloping runs it down, then the horse is winded and drops to a canter
do
	local motor, _, physics = fakeHorse()
	local windedAt = nil
	for f = 1, 60 * 30 do
		motor:Update(dt, { Gait = 4, Direction = Vector3.new(0, 0, -1) })
		physics(dt)
		if motor.Winded > 0 and not windedAt then
			windedAt = f * dt
		end
	end
	print(("  stamina: winded after %.1fs of galloping"):format(windedAt or -1))
	check(windedAt ~= nil and windedAt > t.Stamina * 0.8 and windedAt < t.Stamina * 2, "winded timing")
	check(motor.Speed < t.GallopSpeed * 0.9, "winded horse can't hold a gallop")
end

-- spur: a fresh press gives a burst above gallop speed
do
	local motor, _, physics = fakeHorse()
	for _ = 1, 60 * 6 do
		motor:Update(dt, { Gait = 4, Direction = Vector3.new(0, 0, -1) })
		physics(dt)
	end
	local before = motor.Speed
	motor:Update(dt, { Gait = 4, Direction = Vector3.new(0, 0, -1), Spur = true })
	for _ = 1, 40 do
		motor:Update(dt, { Gait = 4, Direction = Vector3.new(0, 0, -1) })
		physics(dt)
	end
	print(("  spur: %.1f -> %.1f studs/s"):format(before, motor.Speed))
	check(motor.Speed > before + 1.5, "spur burst")
end

-- 2. Taming ----------------------------------------------------------------------------------------
print("Taming (seconds to tame; FAIL = thrown off):")
for _, name in { "Calm", "Spirited", "Wild" } do
	local temperament = HorseTypes.GetTemperament(name)
	local row = {}
	for _, rate in { 0, 3, 4, 5, 6, 8 } do
		local results = {}
		for seed = 1, 6 do
			local timeline = Taming.Timeline(seed * 7919, temperament)
			local progress = temperament.Taming.StartProgress
			local nextImpact = 1
			local nextPress = Taming.Delay + 0.2
			local result = nil
			local step = 1 / 30
			local elapsed = 0
			while elapsed < 40 do
				elapsed += step
				progress = Taming.Drain(progress, step, elapsed, temperament)
				while timeline[nextImpact] and timeline[nextImpact].Impact <= elapsed do
					progress -= Taming.Knock(timeline[nextImpact], temperament)
					nextImpact += 1
				end
				if rate > 0 and elapsed >= nextPress then
					progress = Taming.Press(progress, temperament)
					nextPress += 1 / rate
				end
				if progress >= 1 then
					result = elapsed
					break
				elseif progress <= 0 or elapsed > temperament.Taming.MaxDuration + Taming.Delay then
					break
				end
			end
			table.insert(results, result or -1)
		end
		local sum, wins = 0, 0
		for _, r in results do
			if r > 0 then
				sum += r
				wins += 1
			end
		end
		row[rate] = if wins > 0 then ("%4.1fs (%d/6)"):format(sum / wins, wins) else "   FAIL   "
	end
	print(("  %-9s 0/s %s | 3/s %s | 4/s %s | 5/s %s | 6/s %s | 8/s %s"):format(name, row[0], row[3], row[4], row[5], row[6], row[8]))
	check(row[0] == "   FAIL   ", name .. ": doing nothing must fail")
	check(row[8] ~= "   FAIL   ", name .. ": fast pressing must succeed")
end

-- timeline determinism: same seed, same struggles
do
	local a = Taming.Timeline(1234, t)
	local b = Taming.Timeline(1234, t)
	check(#a == #b and a[3].Kind == b[3].Kind and a[3].Start == b[3].Start, "timeline is deterministic")
end

-- 3. Brain -------------------------------------------------------------------------------------------
local function senses(overrides)
	local base = {
		Now = 0,
		Position = Vector3.new(0, 12, 0),
		Heading = 0,
		Speed = 0,
		Threat = nil,
		Gunshot = nil,
		Whistle = nil,
		Owner = nil,
		Home = Vector3.new(0, 12, 0),
		HomeRadius = 40,
		Wild = true,
		Clear = function()
			return 30
		end,
		Walkable = function()
			return true
		end,
	}
	for k, v in overrides or {} do
		base[k] = v
	end
	return base
end

do
	local brain = Brain.new(t, Harness.Random.new(5))
	local states = {}
	for tick = 1, 600 do
		local command = brain:Update(senses({ Now = tick * 0.1 }))
		states[brain.State] = (states[brain.State] or 0) + 1
		check(command.Gait <= 2, "a calm horse never gallops")
	end
	check((states.Graze or 0) > 0 and (states.Wander or 0) > 0, "horse grazes and wanders")
	print(("Brain: 60s alone -> graze %d, idle %d, wander %d ticks"):format(states.Graze or 0, states.Idle or 0, states.Wander or 0))
end
do
	local brain = Brain.new(t, Harness.Random.new(6))
	brain:Update(senses({ Now = 0 }))
	local command = brain:Update(senses({ Now = 0.1, Threat = { Position = Vector3.new(10, 12, 0), Speed = 23, Distance = 10 } }))
	check(brain.State == "Flee" and command.Gait == 4, "running up to a wild horse makes it bolt")
	check(command.Direction and command.Direction.X < 0, "it bolts away from the player")
end
do
	local brain = Brain.new(t, Harness.Random.new(7))
	local _, pose = brain:Update(senses({ Now = 0, Threat = { Position = Vector3.new(0, 12, 25), Speed = 8, Distance = 25 } }))
	check(brain.State == "Alert" and pose.Alert, "a walking player makes it look up")
end
do
	local brain = Brain.new(t, Harness.Random.new(8))
	brain:Update(senses({ Now = 0, Gunshot = Vector3.new(0, 12, 60) }))
	check(brain.State == "Flee", "gunfire scares wild horses")
end
do
	local brain = Brain.new(t, Harness.Random.new(9))
	local command = brain:Update(senses({ Now = 0, Wild = false, Whistle = true, Owner = Vector3.new(0, 12, -150) }))
	check(brain.State == "Follow" and command.Gait == 4, "whistled horse gallops to a far owner")
	command = brain:Update(senses({ Now = 1, Wild = false, Owner = Vector3.new(0, 12, -5) }))
	check(brain.State == "Idle", "it stops next to the owner")
end
do
	-- a horse walking into a wall that never moves picks something else to do
	local brain = Brain.new(t, Harness.Random.new(10))
	brain.Target = Vector3.new(30, 12, 0)
	brain:Set("Wander", 0, 30)
	local changed = false
	for tick = 1, 60 do
		brain:Update(senses({ Now = tick * 0.1 }))
		if brain.Target and (brain.Target - Vector3.new(30, 12, 0)).Magnitude > 0.1 then
			changed = true
		end
	end
	check(changed, "stuck horse picks a new spot")
end

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
