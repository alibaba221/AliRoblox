--[[
	lune run tools/lune/test-gunplay.luau <place.rbxl> <out-dir>

	Drives the real client gun layer (UpperBody) on an R6 rig carrying the whole loadout:
	  1. Draw / holster: the gun starts in its holster and stays in the hand on its way out (the
	     cross-draw pistol goes from the left hand to the right), ending at the ready pose. A
	     switch puts the first gun away before the next comes out.
	  2. Aiming: the barrel lines up with where the player aims.
	  3. Reloads: the gun stays in the right hand while the left hand works.
	  4. In the saddle: the torso turns toward the aim and the legs don't move.
	  5. The cover crouch keeps the feet on the ground; hit reactions settle back.
	Writes <out-dir>/town.json (the poses laid out in rows) for the preview renderer.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = require("./harness")
local RigFK = require("./rigfk")
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

local placePath = process.args[1] or "build/SicilyDemo.rbxl"
local outDir = process.args[2] or "tools/preview/out-gunplay"
fs.writeDir(outDir)

local game, requireModule = Harness.load(placePath)
local shared = game:GetService("ReplicatedStorage").SicilyShared
local client = game:GetService("StarterPlayer").StarterPlayerScripts.SicilyClient
local AimRig = requireModule(shared.AimRig)
local R6 = requireModule(shared.R6)
local WeaponModels = requireModule(shared.WeaponModels)
local Weapons = requireModule(shared.Weapons)
local UpperBody = requireModule(client.UpperBody)

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local LOADOUT = { "Cattleman", "Mauser", "Carbine", "Carcano", "Lupara" }
local DT = 1 / 60
local now = 100
UpperBody._SetClock(function()
	return now
end)

local out = {}

-- An R6 character carrying every gun in its holster, like the server builds it.
local function gunslinger(rootCF)
	local character = R6.Build({
		Name = "Gunslinger",
		CFrame = rootCF,
		BodyColors = { Head = Color3.fromRGB(234, 184, 146), Arms = Color3.fromRGB(234, 184, 146), Torso = Color3.fromRGB(122, 64, 50), Legs = Color3.fromRGB(58, 52, 50) },
	})
	local fk = RigFK.Capture(character) -- the body only
	local torso = character.Torso
	local folder = roblox.Instance.new("Folder")
	folder.Name = WeaponModels.FolderName
	for _, id in LOADOUT do
		local def = Weapons.Get(id)
		local holster = Weapons.Holsters[def.Holster]
		local model = WeaponModels.Build(id, torso.CFrame * holster)
		local joint = roblox.Instance.new("Motor6D")
		joint.Name = WeaponModels.JointName
		joint.Part0 = torso
		joint.Part1 = model.PrimaryPart
		joint.C0 = holster
		joint.C1 = CFrame.new()
		joint.Parent = model.PrimaryPart
		model.Parent = folder
	end
	folder.Parent = character
	return { Model = character, FK = fk, Root = rootCF }
end

local function setWeaponState(g, id, phase, at, extra)
	local character = g.Model
	character:SetAttribute("Weapon", id or "")
	character:SetAttribute("WeaponState", phase)
	character:SetAttribute("WeaponStateAt", at)
	for key, value in extra or {} do
		character:SetAttribute(key, value)
	end
end

-- One animator frame: locomotion at rest, then the gun layer on top.
local function frame(g, riding)
	local t = {
		RootJoint = CFrame.new(),
		Neck = CFrame.new(),
		RightShoulder = CFrame.new(),
		LeftShoulder = CFrame.new(),
		RightHip = CFrame.new(),
		LeftHip = CFrame.new(),
	}
	UpperBody.Apply({ Model = g.Model }, DT, t, { Root = g.Root, Riding = riding, IsLocal = false, Walk = 0, Phase = 0 })
	return t
end

local function run(g, seconds, riding)
	local t
	for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
		now += DT
		t = frame(g, riding)
	end
	return t
end

-- World CFrames of the body parts and each gun's handle.
local function solve(g, t)
	local cfs = RigFK.Pose(g.FK, g.Root, {
		RootJoint = t.RootJoint,
		Neck = t.Neck,
		["Right Shoulder"] = t.RightShoulder,
		["Left Shoulder"] = t.LeftShoulder,
		["Right Hip"] = t.RightHip,
		["Left Hip"] = t.LeftHip,
	})
	local character = g.Model
	local guns = {}
	for _, model in character[WeaponModels.FolderName]:GetChildren() do
		local joint = model.PrimaryPart[WeaponModels.JointName]
		guns[model.Name] = cfs[character.Torso] * joint.C0 * joint.Transform * joint.C1:Inverse()
	end
	return cfs, guns
end

-- Distance from a point to the gun (the line from its grip to its muzzle).
local function offGun(point, handle, muzzleOffset)
	local a, b = handle.Position, handle:PointToWorldSpace(muzzleOffset)
	local ab = b - a
	local k = math.clamp((point - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (point - (a + ab * k)).Magnitude
end

local function hands(g, cfs)
	local character = g.Model
	return cfs[character["Right Arm"]]:PointToWorldSpace(Vector3.new(0, -1, 0)), cfs[character["Left Arm"]]:PointToWorldSpace(Vector3.new(0, -1, 0))
end

-- Draw it for the preview renderer.
local function emit(g, t)
	local cfs, guns = solve(g, t)
	RigFK.Emit(out, cfs)
	for _, model in g.Model[WeaponModels.FolderName]:GetChildren() do
		local transforms = {}
		for name, motor in WeaponModels.GetMovers(model) do
			-- (joints nothing has animated yet have no Transform offline)
			local ok, value = pcall(function()
				return motor.Transform
			end)
			transforms[name] = if ok then value else CFrame.new()
		end
		RigFK.Emit(out, RigFK.Pose(RigFK.Capture(model), guns[model.Name], transforms))
	end
end

local function yawCF(position, yaw)
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

-- 1. Draw, aim, reload, holster -------------------------------------------------------------------------
print("Draw path (worst distance hand -> grip once the gun leaves the holster), aim, reload:")
for gi, id in LOADOUT do
	local def = Weapons.Get(id)
	local g = gunslinger(yawCF(Vector3.new(0, 3, 0), 0))
	setWeaponState(g, nil, "Holstered", now)
	local t = run(g, 0.2)
	local _, guns = solve(g, t)
	local restHolster = guns[id]

	local muzzle = WeaponModels.Build(id).PrimaryPart.Muzzle.Position

	-- draw
	local start = now
	setWeaponState(g, id, "Drawing", start)
	local steps = 40
	local worstRight, worstLeftHandoff = 0, 0
	local firstGun = nil
	for k = 0, steps do
		now = start + def.DrawTime * k / steps
		t = frame(g)
		local cfs, g2 = solve(g, t)
		local right, left = hands(g, cfs)
		local u = k / steps
		if k == 0 then
			firstGun = g2[id]
		end
		if def.Holster == "HipLeft" then
			if u > 0.3 and u < 0.5 then
				worstLeftHandoff = math.max(worstLeftHandoff, offGun(left, g2[id], muzzle))
			elseif u > 0.62 then
				worstRight = math.max(worstRight, offGun(right, g2[id], muzzle))
			end
		elseif u > 0.3 then
			worstRight = math.max(worstRight, offGun(right, g2[id], muzzle))
		end
	end
	check((firstGun.Position - restHolster.Position).Magnitude < 0.02, id .. ": the draw starts from the holster")
	check(worstRight < 0.3, ("%s: gun stays in the right hand while drawn (%.2f)"):format(id, worstRight))
	if def.Holster == "HipLeft" then
		check(worstLeftHandoff < 0.45, ("%s: the left hand carries the cross-drawn pistol (%.2f)"):format(id, worstLeftHandoff))
	end

	-- drawn: the ready pose
	now = start + def.DrawTime
	setWeaponState(g, id, "Drawn", now)
	t = run(g, 0.5)
	local cfs, g3 = solve(g, t)
	local model = WeaponModels.Build(id)
	local support = model.PrimaryPart.Support.Position
	local readyGun = AimRig.Ready(def.Hold, support, 0)
	local torso = cfs[g.Model.Torso]
	check((g3[id].Position - (torso * readyGun).Position).Magnitude < 0.05, id .. ": ends the draw at the ready pose")

	-- aim straight ahead and 30° up-left: the barrel follows
	local worstAim = 0
	for _, aim in { { 0, 0 }, { 0.35, 0.5 }, { -0.2, -0.4 } } do
		setWeaponState(g, id, "Drawn", now, { Aiming = true, AimPitch = aim[1], AimYaw = aim[2] })
		t = run(g, 1.2)
		local cfsA, gA = solve(g, t)
		local want = Vector3.new(-math.sin(aim[2]) * math.cos(aim[1]), math.sin(aim[1]), -math.cos(aim[2]) * math.cos(aim[1]))
		local angle = math.deg(math.acos(math.clamp(gA[id].LookVector:Dot(want), -1, 1)))
		worstAim = math.max(worstAim, angle)
		local right = hands(g, cfsA)
		check(offGun(right, gA[id], muzzle) < 0.3, id .. ": right hand on the gun while aiming")
	end
	check(worstAim < 3, ("%s: the barrel follows the aim (%.2f°)"):format(id, worstAim))

	-- reload three rounds (or the clip)
	setWeaponState(g, id, "Drawn", now, { Aiming = false })
	run(g, 0.4)
	local reloadStart = now
	setWeaponState(g, id, "Reloading", reloadStart, { ReloadRounds = 3 })
	local total = Weapons.ReloadTime(def, 3)
	local worstGrip, leftTravel, leftStart = 0, 0, nil
	for k = 0, 60 do
		now = reloadStart + total * k / 60
		t = frame(g)
		local cfsR, gR = solve(g, t)
		local right, left = hands(g, cfsR)
		if k > 8 and k < 52 then
			worstGrip = math.max(worstGrip, (right - gR[id].Position).Magnitude)
			local inTorso = cfsR[g.Model.Torso]:PointToObjectSpace(left)
			leftStart = leftStart or inTorso
			leftTravel = math.max(leftTravel, (inTorso - leftStart).Magnitude)
		end
	end
	check(worstGrip < 0.3, ("%s: the gun stays in the right hand while reloading (%.2f)"):format(id, worstGrip))
	check(leftTravel > 0.5, ("%s: the left hand works during the reload (%.2f)"):format(id, leftTravel))

	-- holster
	now = reloadStart + total
	setWeaponState(g, id, "Drawn", now)
	run(g, 0.3)
	local holsterStart = now
	setWeaponState(g, id, "Holstering", holsterStart)
	now = holsterStart + def.HolsterTime
	t = frame(g)
	local _, gH = solve(g, t)
	check((gH[id].Position - restHolster.Position).Magnitude < 0.02, id .. ": back in the holster")
	print(("  %-10s draw %.2f  aim %.2f°  reload grip %.2f  left hand travel %.2f"):format(id, worstRight, worstAim, worstGrip, leftTravel))

	-- preview rows: the draw at five moments, then the reload
	for k, u in { 0.2, 0.42, 0.6, 0.8, 1 } do
		local shot = gunslinger(yawCF(Vector3.new(-12 + (k - 1) * 6, 3, -(gi - 1) * 20), math.pi + 0.5))
		setWeaponState(shot, id, "Drawing", 0)
		now = def.DrawTime * u
		emit(shot, frame(shot))
	end
	local reloadShot = gunslinger(yawCF(Vector3.new(22, 3, -(gi - 1) * 20), math.pi + 0.5))
	setWeaponState(reloadShot, id, "Reloading", 0, { ReloadRounds = 3 })
	now = total * 0.5
	emit(reloadShot, frame(reloadShot))
	now = 1000 + gi * 100
end

-- 2. Switching: the first gun goes away before the next comes out ----------------------------------------
do
	local g = gunslinger(yawCF(Vector3.new(0, 3, 0), 0))
	setWeaponState(g, "Cattleman", "Drawn", now)
	run(g, 0.5)
	local _, before = solve(g, frame(g))
	local switchStart = now
	setWeaponState(g, "Carbine", "Drawing", switchStart, { PreviousWeapon = "Cattleman" })
	local switchTime = Weapons.Get("Cattleman").HolsterTime * 0.7
	now = switchStart + switchTime * 0.5
	local _, mid = solve(g, frame(g))
	check((mid.Carbine.Position - before.Carbine.Position).Magnitude < 0.02, "switch: the carbine waits on the back")
	check((mid.Cattleman.Position - before.Cattleman.Position).Magnitude > 0.1, "switch: the revolver is on its way back")
	now = switchStart + switchTime + Weapons.Get("Carbine").DrawTime
	local _, finish = solve(g, frame(g))
	local rest = gunslinger(yawCF(Vector3.new(0, 3, 0), 0))
	setWeaponState(rest, nil, "Holstered", now)
	local _, holstered = solve(rest, frame(rest))
	check((finish.Cattleman.Position - holstered.Cattleman.Position).Magnitude < 0.02, "switch: the revolver ends up holstered")
	check((finish.Carbine.Position - holstered.Carbine.Position).Magnitude > 0.5, "switch: the carbine ends up in hand")
end

-- 3. In the saddle: the torso turns, the legs stay put -----------------------------------------------------
do
	local riding = { Phase = "Seated", Progress = 1 }
	local worstLeg, worstBarrel = 0, 0
	for ai, yaw in { -1.2, -0.6, 0.6, 1.2 } do
		local g = gunslinger(yawCF(Vector3.new(0, 3, 0), 0))
		setWeaponState(g, nil, "Holstered", now)
		local cfsRest = solve(g, frame(g, riding))
		setWeaponState(g, "Carbine", "Drawn", now, { Aiming = true, AimPitch = 0, AimYaw = yaw })
		local t = run(g, 1.5, riding)
		local cfs, guns = solve(g, t)
		for _, leg in { "Right Leg", "Left Leg" } do
			local a, b = cfs[g.Model[leg]], cfsRest[g.Model[leg]]
			worstLeg = math.max(worstLeg, (a.Position - b.Position).Magnitude, (a.LookVector - b.LookVector).Magnitude)
		end
		local want = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		worstBarrel = math.max(worstBarrel, math.deg(math.acos(math.clamp(guns.Carbine.LookVector:Dot(want), -1, 1))))
		local shot = gunslinger(yawCF(Vector3.new(-12 + (ai - 1) * 6, 3, 20), math.pi))
		setWeaponState(shot, "Carbine", "Drawn", now, { Aiming = true, AimPitch = 0, AimYaw = math.pi + yaw })
		emit(shot, run(shot, 1.5, riding))
	end
	print(("  saddle: legs moved %.4f, barrel off the aim %.2f°"):format(worstLeg, worstBarrel))
	check(worstLeg < 1e-3, "mounted aiming keeps the legs where they were")
	check(worstBarrel < 3, "mounted aiming points the gun where the rider aims")
end

-- 4. Cover crouch and hit reactions --------------------------------------------------------------------------
do
	local g = gunslinger(yawCF(Vector3.new(0, 3, 0), 0))
	setWeaponState(g, nil, "Holstered", now, { Cover = "Low" })
	local t = run(g, 1.2)
	local cfs = solve(g, t)
	-- the bottom of each (knee-less) leg rests on the ground; a kneeling corner may dig in a little
	local worstFoot, lowest = 0, math.huge
	for _, leg in { "Right Leg", "Left Leg" } do
		local cf = cfs[g.Model[leg]]
		worstFoot = math.max(worstFoot, math.abs(cf:PointToWorldSpace(Vector3.new(0, -1, 0)).Y))
		for _, corner in { Vector3.new(0, -1, -0.5), Vector3.new(0, -1, 0.5) } do
			lowest = math.min(lowest, cf:PointToWorldSpace(corner).Y)
		end
	end
	local torsoDrop = 3 - cfs[g.Model.Torso].Position.Y
	print(("  cover: torso lowered %.2f, feet %.2f off the ground, lowest corner %.2f"):format(torsoDrop, worstFoot, lowest))
	check(torsoDrop > 0.7, "low cover: crouched")
	check(worstFoot < 0.12 and lowest > -0.5, "low cover: feet stay on the ground")
	local shot = gunslinger(yawCF(Vector3.new(14, 3, 20), math.pi + 0.8))
	setWeaponState(shot, nil, "Holstered", now, { Cover = "Low" })
	emit(shot, run(shot, 1.2))

	local h = gunslinger(yawCF(Vector3.new(0, 3, 0), 0))
	setWeaponState(h, nil, "Holstered", now)
	run(h, 0.2)
	UpperBody.Flinch(h.Model, "Head", Vector3.new(0, 0, 1), 1)
	local peak = 0
	for _ = 1, 20 do
		now += DT
		local tf = frame(h)
		local _, _, _, r00 = tf.RootJoint:GetComponents()
		peak = math.max(peak, math.abs(1 - r00), math.abs(tf.Neck.LookVector.Y))
	end
	local settled = run(h, 3)
	check(peak > 0.01, "a hit makes the body flinch")
	local rest = Vector3.new(0, 0, -1)
	check((settled.RootJoint.LookVector - rest).Magnitude < 0.01 and (settled.Neck.LookVector - rest).Magnitude < 0.01, "the flinch settles back")
end

-- 5. Mounted combat scene (for the preview): riders on horses at a canter, aiming each gun --------------
do
	local HorseRig = requireModule(shared.HorseRig)
	local HorseGait = requireModule(shared.HorseGait)
	local HorseMount = requireModule(shared.HorseMount)
	local HorseTypes = requireModule(shared.HorseTypes)
	local Animator = requireModule(client.Animator)
	local Solve, BlankState = Animator._Test.Solve, Animator._Test.BlankState
	local L = HorseRig.Layout
	local SEAT = HorseMount.SeatOffset()
	local temperament = HorseTypes.GetTemperament("Spirited")
	-- horses face -X; a camera on -Z sees their right side, where a right-handed rider aims
	local scenes = {
		{ Gun = "Cattleman", Coat = "Bay", Speed = temperament.CanterSpeed, Aim = Vector3.new(-0.7, 0.05, -0.7) },
		{ Gun = "Carbine", Coat = "Grey", Speed = temperament.CanterSpeed, Aim = Vector3.new(0, 0, -1) },
		{ Gun = "Lupara", Coat = "Palomino", Speed = temperament.TrotSpeed, Aim = Vector3.new(0.6, -0.1, -0.8) },
		{ Gun = "Carcano", Coat = "Black", Speed = temperament.GallopSpeed, Aim = Vector3.new(-1, 0.05, -0.15) },
	}
	for index, scene in scenes do
		local horse = HorseRig.Build({ Coat = scene.Coat })
		HorseRig.AddTack(horse)
		local hrig = RigFK.Capture(horse)
		local hstate = HorseGait.New(temperament)
		local pos = Vector3.zero
		local htransforms
		for _ = 1, 120 + index * 7 do
			pos += Vector3.new(0, 0, -scene.Speed) * DT
			htransforms = HorseGait.Step(hstate, {
				RootCFrame = CFrame.new(pos.X, L.RootHeight, pos.Z),
				Velocity = Vector3.new(0, 0, -scene.Speed),
				AngularVelocity = 0,
				Mode = "Ground",
			}, DT, function()
				return 0
			end)
		end
		local display = CFrame.new((index - 1) * 12 - 18, L.RootHeight, 100) * CFrame.Angles(0, math.pi / 2, 0)
		RigFK.Emit(out, RigFK.Pose(hrig, display, htransforms))

		-- the seated pose from the real animator, then the gun layer on top (as in game)
		local rstate = BlankState()
		local motors = {}
		for _, joint in R6.Joints do
			motors[joint.Name] = { Transform = CFrame.new() }
		end
		rstate.Motors = motors
		local riding = { Phase = "Seated", Progress = 1, Gait = hstate, Saddle = SEAT:Inverse() * hstate.BodyTransform * SEAT }
		for f = 1, 60 do
			Solve(rstate, {
				Velocity = Vector3.new(0, 0, -scene.Speed),
				RootCFrame = CFrame.new(),
				Anchored = false,
				State = roblox.Enum.HumanoidStateType.PlatformStanding,
				Sit = false,
				Riding = riding,
			}, DT, f * DT, CFrame.new(0, 10, 30))
		end
		local riderRoot = display * SEAT
		local g = gunslinger(riderRoot)
		local aim = scene.Aim.Unit
		setWeaponState(g, scene.Gun, "Drawn", now, { Aiming = true, AimPitch = math.asin(aim.Y), AimYaw = math.atan2(-aim.X, -aim.Z) })
		local t
		for _ = 1, 60 do
			now += DT
			t = {
				RootJoint = motors.RootJoint.Transform,
				Neck = motors.Neck.Transform,
				RightShoulder = motors["Right Shoulder"].Transform,
				LeftShoulder = motors["Left Shoulder"].Transform,
				RightHip = motors["Right Hip"].Transform,
				LeftHip = motors["Left Hip"].Transform,
			}
			UpperBody.Apply({ Model = g.Model }, DT, t, { Root = riderRoot, Riding = riding, IsLocal = false, Walk = 0, Phase = 0 })
		end
		local _, guns = solve(g, t)
		local angle = math.deg(math.acos(math.clamp(guns[scene.Gun].LookVector:Dot(aim), -1, 1)))
		check(angle < 4, ("mounted %s aims where the rider aims (%.1f°)"):format(scene.Gun, angle))
		emit(g, t)
	end
end

fs.writeFile(outDir .. "/town.json", serde.encode("json", { parts = out, lights = {} }))
print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
