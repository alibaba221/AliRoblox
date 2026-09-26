--[[
	lune run tools/lune/test-combat.luau <place.rbxl>

	Runs the real server combat module (ServerScriptService.SicilyServer.Combat) against fake
	players, with the network and physics stubbed out:
	  * loadout: guns built on the belt, ammo published
	  * draw -> drawn, fire, fire rate (bursts from jitter pass, spam doesn't), wrong gun, no ammo
	  * damage by body part (head / torso / limbs), kills, PvP on
	  * hit validation: claims off the bullet's path, far from the struck part, from a muzzle that
	    isn't near the shooter
	  * reloads: per-round progress, a shot interrupting it, clip reloads, the network allowance
	  * Dead Eye's fast marked shots
	  * range targets: a bottle shatters and comes back
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = require("./harness")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local placePath = process.args[1] or "build/SicilyDemo.rbxl"

-- Stubs ---------------------------------------------------------------------------------------------------
local clock = 1000
local sent = {} -- remote traffic: { Remote, Kind, To, Args }
local fakePlayers = {}
local blocker = nil -- when set, raycasts hit this { Instance, Position, Normal, Material }

local function inertSignal()
	local signal = {}
	function signal:Connect()
		return { Connected = true, Disconnect = function() end }
	end
	signal.Once = signal.Connect
	return signal
end
for className, events in {
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	UnreliableRemoteEvent = { "OnServerEvent", "OnClientEvent" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	RunService = { "Heartbeat", "Stepped" },
	ProximityPrompt = { "Triggered" },
} do
	for _, event in events do
		roblox.implementProperty(className, event, function()
			return inertSignal()
		end)
	end
end
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return clock
end)
roblox.implementMethod("Workspace", "Raycast", function()
	return blocker
end)
roblox.implementMethod("Players", "GetPlayers", function()
	return fakePlayers
end)
roblox.implementMethod("Players", "GetPlayerFromCharacter", function(_, character)
	for _, player in fakePlayers do
		if player.Character == character then
			return player
		end
	end
	return nil
end)
roblox.implementMethod("Player", "GetNetworkPing", function()
	return 0.06
end)
roblox.implementMethod("Humanoid", "TakeDamage", function(self, amount)
	self.Health = math.max(0, self.Health - amount)
end)
roblox.implementMethod("Debris", "AddItem", function() end)
roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("RunService", "IsClient", function()
	return false
end)
for _, className in { "RemoteEvent", "UnreliableRemoteEvent" } do
	roblox.implementMethod(className, "FireClient", function(self, player, kind, ...)
		table.insert(sent, { Remote = self.Name, Kind = kind, To = player, Args = { ... } })
	end)
	roblox.implementMethod(className, "FireAllClients", function(self, kind, ...)
		table.insert(sent, { Remote = self.Name, Kind = kind, To = "all", Args = { ... } })
	end)
end
roblox.implementMethod("PhysicsService", "IsCollisionGroupRegistered", function()
	return true
end)
for _, method in { "RegisterCollisionGroup", "CollisionGroupSetCollidable" } do
	roblox.implementMethod("PhysicsService", method, function() end)
end
roblox.implementMethod("PhysicsService", "GetRegisteredCollisionGroups", function()
	return { { name = "Default" } }
end)

-- Setup ---------------------------------------------------------------------------------------------------
local game, requireModule = Harness.load(placePath)
local shared = game:GetService("ReplicatedStorage").SicilyShared
local R6 = requireModule(shared.R6)
local Weapons = requireModule(shared.Weapons)
local Config = requireModule(shared.Config)
local Combat = requireModule(game:GetService("ServerScriptService").SicilyServer.Combat)
local Workspace = game:GetService("Workspace")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- Lune stores properties but can't derive Position / velocity from the CFrame: set them (the
-- parts here never move).
local function settle(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Position = part.CFrame.Position
			part.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function makePlayer(name: string, position: Vector3)
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.Parent = game:GetService("Players") -- same DOM as the character, so the reference holds
	local character = R6.Build({ Name = name, CFrame = CFrame.new(position) })
	character:SetAttribute("SicilyDressed", true)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	settle(character)
	character.Parent = Workspace
	player.Character = character
	table.insert(fakePlayers, player)
	return player
end

local shooter = makePlayer("Shooter", Vector3.new(0, 3, 0))
local target = makePlayer("Target", Vector3.new(0, 3, -40))
Config.Combat.PvP = true

Combat.Start({ RangeBottles = { CFrame.new(10, 4, -30) }, RangeCans = {}, AmmoCrates = {} })
task.wait(0.1) -- the loadout is built on a spawned thread
settle(Workspace:FindFirstChild("SicilyRange"))
local state = Combat._Test.Players[shooter]
check(state ~= nil, "shooter registered")
local character = shooter.Character
check(character:FindFirstChild("SicilyWeapons") ~= nil, "guns built on the character")
check(#character.SicilyWeapons:GetChildren() == #Config.Combat.Loadout + 1, "every gun plus the belt")
check(shooter:GetAttribute("Ammo_Cattleman") == 6 and shooter:GetAttribute("Reserve_Cattleman") == 54, "ammo published")

local function advance(seconds: number)
	local steps = math.max(1, math.floor(seconds / 0.05 + 0.5))
	for _ = 1, steps do
		clock += seconds / steps
		Combat._Test.Tick(seconds / steps)
	end
end

local function lastSent(kind: string)
	for i = #sent, 1, -1 do
		if sent[i].Kind == kind then
			return sent[i]
		end
	end
	return nil
end

local function shotAt(weapon: string, part, offset: Vector3?)
	local head = character.Head.Position
	local origin = head + Vector3.new(0.6, -0.4, -1)
	local point = part.Position + (offset or Vector3.zero)
	local direction = (point - origin).Unit
	local pellets = {}
	for i = 1, Weapons.Get(weapon).Pellets do
		pellets[i] = { Direction = direction, Hit = part, Position = point, Normal = -direction }
	end
	return { Weapon = weapon, Origin = origin, Direction = direction, Pellets = pellets }
end

local targetHumanoid = target.Character.Humanoid

-- Draw and shoot ----------------------------------------------------------------------------------------
Combat._Test.OnRequest(shooter, "Equip", "Cattleman")
check(character:GetAttribute("WeaponState") == "Drawing" and character:GetAttribute("Weapon") == "Cattleman", "drawing")
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Torso))
check(lastSent("Rejected") ~= nil and targetHumanoid.Health == 100, "can't shoot mid-draw")
advance(0.35)
check(character:GetAttribute("WeaponState") == "Drawn", "drawn")

sent = {}
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Torso))
local torsoDamage = 100 - targetHumanoid.Health
check(math.abs(torsoDamage - 38) < 0.01, ("torso hit does the gun's damage (%.1f)"):format(torsoDamage))
check(shooter:GetAttribute("Ammo_Cattleman") == 5, "a round used")
check(lastSent("Hit") ~= nil and lastSent("Flinch") ~= nil, "shooter told about the hit, everyone sees the flinch")
local fx = nil
for _, entry in sent do
	if entry.Remote == "ShotFX" then
		fx = entry
	end
end
check(fx ~= nil and fx.To == target, "the other player gets the shot effect")
if fx then
	local impacts = fx.Args[3]
	check(type(impacts) == "table" and typeof(impacts[1][1]) == "Vector3" and impacts[1][3] == "Flesh", "compact impact: position, normal, surface")
end

-- fire rate: straight away is too fast, a jittery-but-honest follow-up passes
sent = {}
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Torso))
check(lastSent("Rejected") and lastSent("Rejected").Args[1] == "too fast", "spam is rejected")
advance(0.2) -- hip-fire interval is 0.24; this one arrives a little early (jitter)
sent = {}
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character["Left Arm"]))
check(lastSent("Rejected") == nil, "a slightly early shot (network jitter) still counts")
check(math.abs((100 - torsoDamage - targetHumanoid.Health) - 38 * 0.7) < 0.01, "limb shots do less")
sent = {}
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Torso))
check(lastSent("Rejected") ~= nil, "but the credit doesn't allow a second early shot")

-- validation
advance(0.5)
local healthBefore = targetHumanoid.Health
local lying = shotAt("Cattleman", target.Character.Torso)
lying.Pellets[1].Position = target.Character.Torso.Position + Vector3.new(0, 30, 0)
Combat._Test.OnFire(shooter, lying)
check(targetHumanoid.Health == healthBefore, "a hit claimed far from the bullet's path does nothing")
advance(0.5)
local teleport = shotAt("Cattleman", target.Character.Torso)
teleport.Origin = target.Character.Head.Position + Vector3.new(0, 0, 3)
sent = {}
Combat._Test.OnFire(shooter, teleport)
check(lastSent("Rejected") and lastSent("Rejected").Args[1] == "origin", "shots must start near the shooter")
check(targetHumanoid.Health == healthBefore, "no damage from a bad origin")
advance(0.5)
local wrong = shotAt("Carbine", target.Character.Torso)
sent = {}
Combat._Test.OnFire(shooter, wrong)
check(lastSent("Rejected") and lastSent("Rejected").Args[1] == "not equipped", "only the gun in hand fires")
blocker = { Instance = Workspace:FindFirstChildWhichIsA("BasePart", true) or target.Character.Torso, Position = Vector3.new(0, 3, -20), Normal = Vector3.new(0, 0, 1), Material = roblox.Enum.Material.Brick }
local wall = roblox.Instance.new("Part")
wall.Anchored = true
wall.Size = Vector3.new(10, 10, 1)
wall.Position = Vector3.new(0, 3, -20)
wall.Parent = Workspace
blocker.Instance = wall
advance(0.5)
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Torso))
check(targetHumanoid.Health == healthBefore, "a wall in the way stops the bullet")
blocker = nil

-- head shot kill
advance(0.5)
sent = {}
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Head))
check(targetHumanoid.Health <= 0, "a revolver head shot finishes a wounded target")
local hit = lastSent("Hit")
check(hit ~= nil and hit.Args[2] == true and hit.Args[3] == true, "head + kill reported to the shooter")

-- Reloads ------------------------------------------------------------------------------------------------
targetHumanoid.Health = 100
local mag = shooter:GetAttribute("Ammo_Cattleman")
Combat._Test.OnRequest(shooter, "Reload")
check(character:GetAttribute("WeaponState") == "Reloading", "reloading")
local rounds = character:GetAttribute("ReloadRounds")
check(rounds == 6 - mag, "reloads the missing rounds")
local def = Weapons.Get("Cattleman")
advance(def.Reload.Start + def.Reload.PerRound * 1.5)
check(shooter:GetAttribute("Ammo_Cattleman") == mag + 1, "rounds go in one at a time")
sent = {}
Combat._Test.OnFire(shooter, shotAt("Cattleman", target.Character.Torso))
check(lastSent("Rejected") == nil and character:GetAttribute("WeaponState") == "Drawn", "a shot interrupts a per-round reload")
check(shooter:GetAttribute("Ammo_Cattleman") == mag, "the loaded round was fired")
advance(0.5)

-- a reload asked for just before our draw timer runs out still happens
Combat._Test.OnRequest(shooter, "Equip", "Cattleman")
advance(0.3)
Combat._Test.OnRequest(shooter, "Holster")
advance(0.4)
Combat._Test.OnRequest(shooter, "Equip", "Cattleman")
advance(Weapons.Get("Cattleman").DrawTime - 0.06)
Combat._Test.OnRequest(shooter, "Reload")
check(character:GetAttribute("WeaponState") == "Reloading", "a reload right at the end of the draw isn't lost")
advance(3)

-- the client finishes its clip reload a moment before we do: allowed
Combat._Test.OnRequest(shooter, "Equip", "Mauser")
advance(Weapons.Get("Mauser").DrawTime + Weapons.Get("Cattleman").HolsterTime * 0.7 + 0.05)
check(character:GetAttribute("Weapon") == "Mauser" and character:GetAttribute("WeaponState") == "Drawn", "switched guns")
advance(0.3)
Combat._Test.OnFire(shooter, shotAt("Mauser", target.Character.Torso))
Combat._Test.OnRequest(shooter, "Reload")
advance(Weapons.Get("Mauser").Reload.Time - 0.08)
sent = {}
Combat._Test.OnFire(shooter, shotAt("Mauser", target.Character.Torso))
check(lastSent("Rejected") == nil, "a shot just before the reload ends on our clock is allowed")
check(shooter:GetAttribute("Ammo_Mauser") == 9, "clip reload filled the gun first")

-- Dead Eye ---------------------------------------------------------------------------------------------------
advance(0.5)
targetHumanoid.Health = 1000
Combat._Test.OnRequest(shooter, "DeadEye", true)
check(character:GetAttribute("DeadEye") == true, "Dead Eye on")
local fired = 0
for _ = 1, 4 do
	advance(Config.Combat.DeadEye.ShotInterval)
	sent = {}
	Combat._Test.OnFire(shooter, shotAt("Mauser", target.Character.Torso))
	if lastSent("Rejected") == nil then
		fired += 1
	end
end
check(fired == 4, ("Dead Eye allows quick marked shots (%d/4)"):format(fired))
Combat._Test.OnRequest(shooter, "DeadEye", false)
check(character:GetAttribute("DeadEye") == false, "Dead Eye off")

-- Shotgun: pellets add up; the range falls off ------------------------------------------------------------
advance(0.5)
Combat._Test.OnRequest(shooter, "Equip", "Lupara")
advance(1)
targetHumanoid.Health = 1000
Combat._Test.OnFire(shooter, shotAt("Lupara", target.Character.Torso))
local shotgunDamage = 1000 - targetHumanoid.Health
local luparaShot = shotAt("Lupara", target.Character.Torso)
local expected = Weapons.Get("Lupara").Damage * 9 * Weapons.Falloff(Weapons.Get("Lupara"), (target.Character.Torso.Position - luparaShot.Origin).Magnitude)
check(math.abs(shotgunDamage - expected) < 1, ("shotgun pellets add up with falloff (%.1f vs %.1f)"):format(shotgunDamage, expected))

-- Range target ------------------------------------------------------------------------------------------------
advance(0.5)
local range = Workspace:FindFirstChild("SicilyRange")
local bottle = range and range:FindFirstChild("Bottle")
check(bottle ~= nil, "a bottle on the range")
if bottle then
	Combat._Test.OnFire(shooter, shotAt("Lupara", bottle.Body))
	check(bottle.Parent == nil, "the bottle shatters")
end

-- Holster ---------------------------------------------------------------------------------------------------------
Combat._Test.OnRequest(shooter, "Holster")
advance(0.6)
check(character:GetAttribute("WeaponState") == "Holstered" and character:GetAttribute("Weapon") == "", "holstered")

-- Aim state is clamped / validated
Combat._Test.OnAimState(shooter, true, 5, 1)
check(character:GetAttribute("Aiming") == false, "can't aim a holstered gun")
check(character:GetAttribute("AimPitch") <= 1.5, "aim pitch clamped")

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
