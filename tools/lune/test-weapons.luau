--[[
	lune run tools/lune/test-weapons.luau <place.rbxl> <out-dir>

	1. Builds every weapon: Handle, Muzzle/Support/Eject attachments, moving parts, no collisions.
	2. Poses an R6 rig with the real AimRig maths: every gun holstered, then each gun aimed
	   (level, up, down, left, right) and at low ready. Checks the barrel points where the player
	   aims, and the hands sit on the grip and fore-end.
	3. Checks weapon numbers (falloff, reload times, variants) and hit-validation maths.
	Writes <out-dir>/town.json for the preview renderer.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Harness = require("./harness")
local RigFK = require("./rigfk")
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

local placePath = process.args[1] or "build/SicilyDemo.rbxl"
local outDir = process.args[2] or "tools/preview/out-weapons"
fs.writeDir(outDir)

local game, requireModule = Harness.load(placePath)
local shared = game:GetService("ReplicatedStorage").SicilyShared
local Weapons = requireModule(shared.Weapons)
local WeaponModels = requireModule(shared.WeaponModels)
local AimRig = requireModule(shared.AimRig)
local R6 = requireModule(shared.R6)

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local LOADOUT = { "Cattleman", "Mauser", "Carbine", "Carcano", "Lupara" }
local MOVERS = { Revolver = { "Cylinder", "Hammer" }, Pistol = { "Bolt" }, Repeater = { "Lever" }, Rifle = { "Bolt" }, Shotgun = { "Barrels" } }

-- 1. Models ---------------------------------------------------------------------------------------
for id in Weapons.Defs do
	local def = Weapons.Get(id)
	check(def ~= nil, "resolve " .. id)
	local model = WeaponModels.Build(id)
	check(model ~= nil and model.PrimaryPart ~= nil, id .. ": model")
	if model then
		local handle = model.PrimaryPart
		for _, name in { "Muzzle", "Support", "Eject" } do
			check(handle:FindFirstChild(name) ~= nil, id .. ": attachment " .. name)
		end
		local movers = WeaponModels.GetMovers(model)
		for _, name in MOVERS[def.Model] do
			check(movers[name] ~= nil, id .. ": moving part " .. name)
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				check(not part.CanCollide and not part.CanQuery and part.Massless, id .. ": " .. part.Name .. " must not collide/query")
			end
		end
		check(Weapons.Holsters[def.Holster] ~= nil, id .. ": holster " .. tostring(def.Holster))
	end
end
check(Weapons.Get("Schofield").Spread.Hip == Weapons.Get("Cattleman").Spread.Hip, "variants inherit nested tables")
check(Weapons.Get("Schofield").Damage == 42, "variants override")
check(Weapons.Get("Nope") == nil, "unknown weapon")
local carbine = Weapons.Get("Carbine")
check(math.abs(Weapons.Falloff(carbine, 10) - 1) < 1e-6 and math.abs(Weapons.Falloff(carbine, 1000) - carbine.MinDamage) < 1e-6, "falloff range")
check(math.abs(Weapons.ReloadTime(carbine, 3) - (0.4 + 3 * 0.26 + 0.35)) < 1e-6, "per-round reload time")

-- 2. Poses --------------------------------------------------------------------------------------------
local JOINT = {}
for _, joint in R6.Joints do
	JOINT[joint.Name] = joint
end
local ROOT_C0, ROOT_C1 = JOINT.RootJoint.C0, JOINT.RootJoint.C1
local out = {}

local function rig(position: Vector3, yaw: number)
	local character = R6.Build({ Name = "Shooter", BodyColors = { Head = Color3.fromRGB(234, 184, 146), Arms = Color3.fromRGB(234, 184, 146), Torso = Color3.fromRGB(70, 90, 130), Legs = Color3.fromRGB(58, 52, 50) } })
	local fk = RigFK.Capture(character)
	return character, fk, CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

-- Pose one character with guns: `guns` = { [id] = handle CFrame in Torso space or "holster" }.
local function emitCharacter(rootCF, twist, shoulders, guns)
	local character, fk = rig(Vector3.zero, 0)
	local transforms = {
		RootJoint = CFrame.Angles(0, 0, twist),
		["Right Shoulder"] = shoulders.Right or CFrame.new(),
		["Left Shoulder"] = shoulders.Left or CFrame.new(),
		["Right Hip"] = CFrame.new(),
		["Left Hip"] = CFrame.new(),
		Neck = CFrame.Angles(0, 0, -twist),
	}
	local cfs = RigFK.Pose(fk, rootCF, transforms)
	RigFK.Emit(out, cfs)
	local torso = cfs[character.Torso]
	for id, where in guns do
		local def = Weapons.Get(id)
		local model = WeaponModels.Build(id)
		local handleTorso = if where == "holster" then Weapons.Holsters[def.Holster] else where
		local gunRig = RigFK.Capture(model)
		RigFK.Emit(out, RigFK.Pose(gunRig, torso * handleTorso, {}))
	end
	return torso
end

-- every gun holstered on one character: facing the camera (+Z) and with its back to it
for i, yaw in { math.pi, 0 } do
	local guns = {}
	for _, id in LOADOUT do
		guns[id] = "holster"
	end
	emitCharacter(CFrame.new(-60 + (i - 1) * 6, 3, 0) * CFrame.Angles(0, yaw, 0), 0, {}, guns)
end

-- aims: each gun, level / up / down / left / right, plus ready
local directions = {
	{ Name = "level", Dir = Vector3.new(0, 0, -1) },
	{ Name = "up", Dir = Vector3.new(0, 0.5, -0.87) },
	{ Name = "down", Dir = Vector3.new(0, -0.45, -0.9) },
	{ Name = "left", Dir = Vector3.new(-0.6, 0, -0.8) },
	{ Name = "right", Dir = Vector3.new(0.6, 0, -0.8) },
}
print("Aim accuracy (barrel vs aim, degrees) and hand placement (studs from grip / fore-end):")
for gi, id in LOADOUT do
	local def = Weapons.Get(id)
	local model = WeaponModels.Build(id)
	local support = model.PrimaryPart:FindFirstChild("Support").Position
	local worst, worstRight, worstLeft = 0, 0, 0
	for di, d in directions do
		local twist = AimRig.Twist[def.Hold]
		-- world aim straight ahead of the (untwisted) character; convert into the twisted torso
		local aimTorso = CFrame.Angles(0, -twist, 0):VectorToWorldSpace(d.Dir).Unit
		local gun, right, left = AimRig.Aim(def.Hold, aimTorso, support)
		-- barrel direction
		local barrel = gun.LookVector
		local angle = math.deg(math.acos(math.clamp(barrel:Dot(aimTorso), -1, 1)))
		worst = math.max(worst, angle)
		local hand = AimRig.HandPosition("Right", right)
		worstRight = math.max(worstRight, (hand - gun.Position).Magnitude)
		if left then
			local leftHand = AimRig.HandPosition("Left", left)
			worstLeft = math.max(worstLeft, (leftHand - AimRig.SupportPoint(gun, support)).Magnitude)
		end
		if di <= 2 then
			-- shooters face +X (side-on to a camera on +Z); the twist turns the torso
			local rootCF = CFrame.new(-30 + (gi - 1) * 14 + (di - 1) * 6, 3, -20) * CFrame.Angles(0, -math.pi / 2, 0)
			emitCharacter(rootCF, twist, { Right = right, Left = left }, { [id] = gun })
		end
	end
	print(("  %-10s barrel %.2f°  right hand %.2f  left hand %s"):format(id, worst, worstRight, if def.Hold == "Long" then ("%.2f"):format(worstLeft) else "free"))
	check(worst < 0.5, id .. ": barrel must follow the aim")
	check(worstRight < (if def.Hold == "Long" then 0.45 else 0.05), id .. ": right hand on the grip")
	if def.Hold == "Long" then
		check(worstLeft < 0.75, id .. ": left hand near the fore-end")
	end
	-- ready pose
	local gun, right, left = AimRig.Ready(def.Hold, support, 0)
	emitCharacter(CFrame.new(-30 + (gi - 1) * 14, 3, 20) * CFrame.Angles(0, -math.pi / 4, 0), 0, { Right = right, Left = left }, { [id] = gun })
end

fs.writeFile(outDir .. "/town.json", serde.encode("json", { parts = out, lights = {} }))
print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
