--[[
	lune run tools/lune/test-characters.luau <place.rbxl> <out-dir>

	1. Builds the R6 rig and checks its parts, joints and attachments.
	2. Drives the real procedural animation solver (client Animator) through each movement
	   state and poses rigs with forward kinematics using the rig's actual Motor6D offsets.
	3. Builds every townsfolk outfit and converts a mock R15 NPC to R6 in place.
	Writes <out-dir>/rigs.json for the preview renderer.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = require("./harness")
local CFrame, Vector3, Enum = roblox.CFrame, roblox.Vector3, roblox.Enum

local placePath = process.args[1] or "build/place.rbxl"
local outDir = process.args[2] or "tools/preview/out-rigs"
fs.writeDir(outDir)

local game, requireModule = Harness.load(placePath)
local shared = game:GetService("ReplicatedStorage").SicilyShared
local R6 = requireModule(shared.R6)
local Config = requireModule(shared.Config)
Config.Characters.Ragdoll = false -- Lune has no events (Died:Connect)

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- 1. Rig structure -------------------------------------------------------------------------
local rig = R6.Build({ Name = "Test" })
for _, name in R6.BodyParts do
	check(rig:FindFirstChild(name) ~= nil, "missing part " .. name)
end
local motors = R6.GetMotors(rig)
for _, joint in R6.Joints do
	check(motors[joint.Name] ~= nil, "missing motor " .. joint.Name)
end
check(rig.PrimaryPart and rig.PrimaryPart.Name == "HumanoidRootPart", "PrimaryPart")
check(rig.Head:FindFirstChild("HatAttachment") ~= nil, "HatAttachment")
check(rig:FindFirstChildOfClass("Humanoid").RigType == Enum.HumanoidRigType.R6, "RigType")
-- rest pose sanity: each part sits where its joint says it should
local root = rig.HumanoidRootPart
for _, joint in R6.Joints do
	local p0 = rig:FindFirstChild(joint.Part0)
	local p1 = rig:FindFirstChild(joint.Part1)
	local expected = p0.CFrame * joint.C0 * joint.C1:Inverse()
	check((expected.Position - p1.CFrame.Position).Magnitude < 1e-3, "rest pose mismatch " .. joint.Name)
end

-- 2. Animation poses ----------------------------------------------------------------------
local Animator = requireModule(game:GetService("StarterPlayer").StarterPlayerScripts.SicilyClient.Animator)
local Solve, BlankState = Animator._Test.Solve, Animator._Test.BlankState
local HST = Enum.HumanoidStateType

local function fakeMotors()
	local m = {}
	for _, joint in R6.Joints do
		m[joint.Name] = { Transform = CFrame.new() }
	end
	return m
end

local jointByName = {}
for _, joint in R6.Joints do
	jointByName[joint.Name] = joint
end

-- Forward kinematics with the real joint offsets.
local function posedParts(rootCFrame, m)
	local cfs = { HumanoidRootPart = rootCFrame }
	local function solve(jointName)
		local j = jointByName[jointName]
		cfs[j.Part1] = cfs[j.Part0] * j.C0 * m[jointName].Transform * j.C1:Inverse()
	end
	solve("RootJoint")
	for _, name in { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" } do
		solve(name)
	end
	return cfs
end

local out = {}
local function emitRig(cfs, colors, extra)
	local palette = {
		Head = colors.Head,
		Torso = colors.Torso,
		["Left Arm"] = colors.Head,
		["Right Arm"] = colors.Head,
		["Left Leg"] = colors.Legs,
		["Right Leg"] = colors.Legs,
	}
	for _, name in R6.BodyParts do
		local cf = cfs[name]
		local size = R6.Sizes[name]
		local c = palette[name]
		table.insert(out, {
			k = if name == "Head" then "MeshHead" else "Block",
			s = if name == "Head" then { 1.25, 1.25, 1.25 } else { size.X, size.Y, size.Z },
			cf = { cf:GetComponents() },
			c = c,
			m = "SmoothPlastic",
			t = 0,
		})
	end
	for _, e in extra or {} do
		table.insert(out, e)
	end
end

local lowest = {}
local scenarios = {
	{ Name = "idle", Speed = 0, Frames = 80 },
	{ Name = "walk", Speed = Config.Movement.WalkSpeed, Frames = 50 },
	{ Name = "walk-mid", Speed = Config.Movement.WalkSpeed, Frames = 58 },
	{ Name = "run", Speed = Config.Movement.RunSpeed, Frames = 40 },
	{ Name = "run-mid", Speed = Config.Movement.RunSpeed, Frames = 44 },
	{ Name = "jump", Speed = 8, VY = 40, State = HST.Jumping, Frames = 20 },
	{ Name = "fall", Speed = 4, VY = -70, State = HST.Freefall, Frames = 90 },
	{ Name = "land", Speed = 0, Frames = 4, Before = { VY = -80, State = HST.Freefall, Frames = 40 } },
	{ Name = "sit", Speed = 0, Pose = "Sit", Frames = 60 },
	{ Name = "fish", Speed = 0, Pose = "Fish", Frames = 60 },
	{ Name = "vendor", Speed = 0, Pose = "Vendor", Frames = 125 },
	{ Name = "lean", Speed = 0, Pose = "Lean", Frames = 60 },
	{ Name = "swim", Speed = 12, State = HST.Swimming, Frames = 60 },
	{ Name = "climb", Speed = 0, VY = 8, State = HST.Climbing, Frames = 30 },
	{ Name = "turn", Speed = Config.Movement.RunSpeed, Frames = 40, TurnRate = 2.5 },
}
local camera = CFrame.new(0, 10, 30)
for index, sc in scenarios do
	local state = BlankState()
	state.Phase = 0
	state.PoseName = sc.Pose
	local m = fakeMotors()
	state.Motors = m
	local yaw = 0
	local function run(frames, speed, vy, humanoidState)
		for f = 1, frames do
			yaw += (sc.TurnRate or 0) / 60
			local rootCF = CFrame.new(0, 3, 0) * CFrame.Angles(0, yaw, 0)
			local forward = rootCF.LookVector
			state.Clock = state.Clock
			Solve(state, {
				Velocity = forward * speed + Vector3.new(0, vy or 0, 0),
				RootCFrame = rootCF,
				Anchored = sc.Pose ~= nil,
				State = humanoidState or HST.Running,
				Sit = false,
			}, 1 / 60, f / 60, camera)
		end
		return CFrame.new(0, 3, 0) * CFrame.Angles(0, yaw, 0)
	end
	if sc.Before then
		run(sc.Before.Frames, sc.Speed, sc.Before.VY, sc.Before.State)
	end
	local rootCF = run(sc.Frames, sc.Speed, sc.VY, sc.State)
	-- display: line up along X, everyone facing the camera (+Z)
	local display = CFrame.new((index - 1) * 5 - 35, 3, 0) * CFrame.Angles(0, math.pi + 0.5, 0)
	local cfs = posedParts(display * rootCF.Rotation:Inverse() * rootCF.Rotation, m)
	local minY = math.huge
	for _, name in { "Left Leg", "Right Leg" } do
		local foot = (cfs[name] * CFrame.new(0, -1, 0)).Position.Y
		minY = math.min(minY, foot)
	end
	lowest[sc.Name] = minY
	emitRig(cfs, { Head = { 234, 184, 146 }, Torso = { 60 + index * 10, 90, 150 }, Legs = { 60, 58, 64 } })
	for k, v in state.Pose do
		check(v == v and math.abs(v) < 10, ("pose %s.%s is not sane: %s"):format(sc.Name, k, tostring(v)))
	end
end
print("Lowest foot height per state (ground = 0, positive = floating, negative = sinking):")
for _, sc in scenarios do
	print(("  %-9s %6.2f"):format(sc.Name, lowest[sc.Name]))
end

-- 3. Townsfolk outfits and in-place R15 -> R6 conversion ----------------------------------------
local NPCs = requireModule(game:GetService("ServerScriptService").SicilyServer.NPCs)
local folder = roblox.Instance.new("Folder")
folder.Parent = game:GetService("Workspace")
local rng = Harness.Random.new(3)
local outfits = table.clone(NPCs._Test.Outfits)
table.insert(outfits, NPCs._Test.Vendor)
for i, outfit in outfits do
	local model = NPCs._Test.MakeNPC(folder, outfit, rng, CFrame.new((i - 1) * 5 - 27, 3, -16) * CFrame.Angles(0, math.pi + 0.3, 0), true)
	check(model:HasTag(R6.Tag), "townsfolk tagged")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local c = d.Color
			local shape = if d.ClassName == "Part" then d.Shape.Name else d.ClassName
			if d.Name == "Head" then
				shape = "MeshHead"
			end
			table.insert(out, {
				k = shape,
				s = if d.Name == "Head" then { 1.25, 1.25, 1.25 } else { d.Size.X, d.Size.Y, d.Size.Z },
				cf = { d.CFrame:GetComponents() },
				c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
				m = d.Material.Name,
				t = 0,
			})
		end
	end
end

-- mock R15 NPC
roblox.implementMethod("Players", "GetPlayerFromCharacter", function()
	return nil
end)
roblox.implementMethod("Animator", "GetPlayingAnimationTracks", function()
	return {}
end)
roblox.implementMethod("Humanoid", "AddAccessory", function(self, accessory)
	accessory.Parent = self.Parent
end)
local RigConverter = requireModule(game:GetService("ServerScriptService").SicilyServer.RigConverter)
local npc = roblox.Instance.new("Model")
npc.Name = "OldCowboy"
local hrp = roblox.Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.Size = Vector3.new(2, 2, 1)
hrp.CFrame = CFrame.new(20, 3, 20)
hrp.Parent = npc
for _, name in { "UpperTorso", "LowerTorso", "Head", "LeftUpperArm", "RightFoot" } do
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Parent = npc
end
local hum = roblox.Instance.new("Humanoid")
hum.RigType = Enum.HumanoidRigType.R15
hum.HipHeight = 2
hum.MaxHealth = 100
hum.Health = 100
hum.RequiresNeck = true
hum.Parent = npc
roblox.Instance.new("Animator").Parent = hum
local shirt = roblox.Instance.new("Shirt")
shirt.Parent = npc
local script = roblox.Instance.new("Script")
script.Name = "CowboyBrain"
script.Parent = npc
npc.Parent = game:GetService("Workspace")
local converted = RigConverter.Convert(npc)
check(converted, "R15 NPC converted")
check(npc:FindFirstChild("UpperTorso") == nil and npc:FindFirstChild("Torso") ~= nil, "R15 parts replaced by R6 parts")
check(hum.RigType == Enum.HumanoidRigType.R6 and hum.Parent == npc, "same Humanoid, now R6")
check(npc:FindFirstChild("HumanoidRootPart") == hrp, "same HumanoidRootPart kept")
check(npc:FindFirstChild("CowboyBrain") ~= nil and npc:FindFirstChild("Shirt") ~= nil, "scripts and clothing kept")
local newMotors = R6.GetMotors(npc)
check(newMotors.RootJoint ~= nil and newMotors.RootJoint.Part0 == hrp, "RootJoint attached to the original root")
check(math.abs(hrp.CFrame.Position.Y - 3) < 1e-3, "root re-seated for R6 hip height (y=3 on flat ground)")

fs.writeFile(outDir .. "/town.json", serde.encode("json", { parts = out, lights = {} }))
print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
