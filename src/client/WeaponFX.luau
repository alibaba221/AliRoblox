--[[
	WeaponFX (client): what a gunshot looks and sounds like. Your own shots play instantly (the
	client predicts them); everyone else's arrive from the server.

	  * Muzzle fire, flash of light and a drifting smoke puff at the gun's barrel.
	  * The report, with a canyon echo; farther away it's duller and quieter.
	  * A faint bullet streak, then an impact that matches the surface: dust, stone chips,
	    splinters, sparks, splashes, glass. Solid surfaces keep a bullet mark for a while.
	  * Spent casings flying out of repeaters, rifles and pistols. Lever, bolt and hammer clicks,
	    reload sounds and an empty click.
	  * People who are hit flinch (see UpperBody), and the shooter hears a hit tick.

	Only sounds and textures that ship with Roblox are used (see Config.Combat.Sounds to use
	real gun sounds).
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local Fx = require(script.Parent.Fx)
local UpperBody = require(script.Parent.UpperBody)

local WeaponFX = {}

local settings = Config.Combat
local overrides = settings.Sounds
local rng = Random.new()

local CLICK = "rbxasset://sounds/volume_slider.ogg"
local TAP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local RUSTLE = "rbxasset://sounds/action_get_up.mp3"
local THUD = "rbxasset://sounds/action_jump_land.mp3"
local SPLASH = "rbxasset://sounds/impact_water.mp3"
local FIRE_COLOR = Color3.fromRGB(255, 196, 120)
local EFFECT_RANGE = 450 -- nothing is drawn for shots farther away than this
local DETAIL_RANGE = 90 -- casings, mechanics and impact sounds only nearby

local SURFACE_FX = {
	Dirt = { Preset = "Dust", Count = 7, Color = Color3.fromRGB(150, 120, 88), Mark = true },
	Grass = { Preset = "Dust", Count = 6, Color = Color3.fromRGB(128, 122, 86) },
	Sand = { Preset = "Dust", Count = 9, Color = Color3.fromRGB(214, 190, 140) },
	Stone = { Preset = "Dust", Count = 6, Color = Color3.fromRGB(200, 190, 174), Sparks = 3, Mark = true },
	Wood = { Preset = "Splinters", Count = 7, Color = Color3.fromRGB(150, 104, 64), Dust = 3, Mark = true },
	Metal = { Preset = "Sparks", Count = 10, Mark = true, Ping = true },
	Glass = { Preset = "Sparks", Count = 8, Color = Color3.fromRGB(220, 236, 240) },
	Fabric = { Preset = "Puff", Count = 4, Color = Color3.fromRGB(184, 172, 150) },
	Flesh = { Preset = "Puff", Count = 5, Color = Color3.fromRGB(156, 136, 116) },
	Water = { Preset = "Splash", Count = 10 },
}
if settings.ShowBloodPuffs then
	SURFACE_FX.Flesh = { Preset = "Puff", Count = 6, Color = Color3.fromRGB(122, 18, 20) }
end

local echo = Instance.new("EchoSoundEffect")
echo.Delay = 0.22
echo.Feedback = 0.28
echo.WetLevel = -9
echo.DryLevel = 0

-- Local-only folder for loose physics debris (casings): it isn't replicated.
local function debrisFolder(): Instance
	local folder = Workspace:FindFirstChild("SicilyLocalDebris")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SicilyLocalDebris"
		folder.Parent = Workspace
	end
	return folder
end

local holeParams = RaycastParams.new()
holeParams.FilterType = Enum.RaycastFilterType.Exclude
holeParams.IgnoreWater = true

local function cameraDistance(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

local function gunSound(def): string
	local override = overrides[def.Class]
	return if type(override) == "string" and override ~= "" then override else def.Sound.Id
end

local function soundOr(name: string, fallback: string): string
	local override = overrides[name]
	return if type(override) == "string" and override ~= "" then override else fallback
end

local function click(at: Vector3 | Instance, pitch: number, volume: number?, delay: number?)
	local function play()
		Fx.Sound(soundOr("Cock", CLICK), at, { Volume = volume or 0.35, Pitch = pitch, RollOff = 60, RollOffMin = 4, StopAfter = 0.25 })
	end
	if delay and delay > 0 then
		task.delay(delay, play)
	else
		play()
	end
end

-- A spent case thrown out of the ejection port.
local function casing(model: Model?, def)
	local handle = model and model.PrimaryPart
	local port = handle and handle:FindFirstChild("Eject")
	if not port or not port:IsA("Attachment") or not def.ShellColor then
		return
	end
	local world = port.WorldCFrame
	local shell = Instance.new("Part")
	shell.Name = "Casing"
	shell.Shape = Enum.PartType.Cylinder
	shell.Size = if def.Class == "Shotgun" then Vector3.new(0.3, 0.16, 0.16) else Vector3.new(0.2, 0.08, 0.08)
	shell.Color = def.ShellColor
	shell.Material = Enum.Material.Metal
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.CFrame = world * CFrame.Angles(0, math.pi / 2, 0)
	shell.Parent = debrisFolder()
	local right, up = world.RightVector, world.UpVector
	shell.AssemblyLinearVelocity = right * (9 + rng:NextNumber() * 4) + up * (7 + rng:NextNumber() * 3) + world.LookVector * rng:NextNumber(-1, 2)
	shell.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(-25, 25), rng:NextNumber(-25, 25))
	Debris:AddItem(shell, 2.5)
	task.delay(0.3 + rng:NextNumber() * 0.2, function()
		if shell.Parent then
			Fx.Sound(TAP, shell.Position, { Volume = 0.12, Pitch = 2.4 + rng:NextNumber() * 0.4, RollOff = 30, RollOffMin = 3, StopAfter = 0.12 })
		end
	end)
end

-- The gun's action between shots: hammer, lever, bolt.
local function mechanics(model: Model?, def, at: Vector3 | Instance)
	local action = def.Action
	if action == "Hammer" then
		click(at, 1.35, 0.28, 0.12)
	elseif action == "Lever" then
		Fx.Sound(TAP, at, { Volume = 0.3, Pitch = 1.9, RollOff = 60, RollOffMin = 4, StopAfter = 0.12 })
		task.delay(0.14, function()
			casing(model, def)
		end)
		click(at, 1.1, 0.35, 0.3)
	elseif action == "Bolt" then
		click(at, 0.75, 0.4, 0.25)
		task.delay(0.42, function()
			casing(model, def)
		end)
		click(at, 0.95, 0.4, 0.6)
	elseif def.ShellColor and def.Class ~= "Shotgun" then
		casing(model, def)
	end
end

-- Dust / chips / splinters / sparks / splash where a bullet landed.
function WeaponFX.Impact(impact, from: Vector3)
	local surface = impact.Surface
	if not surface or surface == "Air" then
		return
	end
	local spec = SURFACE_FX[surface] or SURFACE_FX.Stone
	local toShooter = from - impact.Position
	local normal = impact.Normal or (if toShooter.Magnitude > 1e-3 then toShooter.Unit else Vector3.new(0, 1, 0))
	local position = impact.Position + normal * 0.06
	Fx.EmitAt(position, spec.Preset, spec.Count, { Direction = normal, Color = spec.Color })
	if spec.Dust then
		Fx.EmitAt(position, "Dust", spec.Dust, { Direction = normal, Color = spec.Color, Scale = 0.6 })
	end
	if spec.Sparks then
		Fx.EmitAt(position, "Sparks", spec.Sparks, { Direction = normal })
	end
	local distance = cameraDistance(position)
	if spec.Mark and distance < 160 then
		local part = impact.Part
		if not part then
			-- someone else's shot: find the surface ourselves
			local hit = Workspace:Raycast(position + normal * 0.4, -normal * 0.8, holeParams)
			part = hit and hit.Instance
		end
		if part and part:IsA("BasePart") and not part:IsA("Terrain") then
			Fx.Hole(impact.Position, normal, part)
		end
	end
	if distance < DETAIL_RANGE then
		if surface == "Water" then
			Fx.Sound(SPLASH, position, { Volume = 0.3, Pitch = 1.7, RollOff = 70, StopAfter = 0.5 })
		elseif spec.Ping then
			Fx.Sound(soundOr("Ricochet", CLICK), position, { Volume = 0.45, Pitch = 2.6, RollOff = 80, StopAfter = 0.3 })
		elseif surface ~= "Flesh" then
			Fx.Sound(soundOr("Impact", THUD), position, { Volume = 0.22, Pitch = 1.7 + rng:NextNumber() * 0.4, RollOff = 60, StopAfter = 0.18 })
		end
	end
end

--[[
	One trigger pull. impacts = { { Position, Normal?, Surface, Part? } } (Part only for our own
	shots). isLocal: our own shot (always drawn in full).
]]
function WeaponFX.Shot(character: Model?, weaponId: string, origin: Vector3, impacts, isLocal: boolean)
	local def = Weapons.Get(weaponId)
	if not def then
		return
	end
	local muzzle = if character then UpperBody.Muzzle(character, weaponId) else nil
	local muzzlePosition = if muzzle then muzzle.WorldPosition else origin
	local distance = cameraDistance(muzzlePosition)
	if distance > EFFECT_RANGE and not isLocal then
		-- far away: just the distant report
		Fx.Sound(gunSound(def), muzzlePosition, { Volume = def.Sound.Volume * 0.5, Pitch = def.Sound.Pitch * 0.8, RollOff = 1200, RollOffMin = 40, StopAfter = def.Sound.Length })
		return
	end
	local barrel = if muzzle then muzzle.WorldCFrame.LookVector else nil
	if not barrel and impacts[1] then
		local offset = impacts[1].Position - origin
		barrel = if offset.Magnitude > 1e-3 then offset.Unit else nil
	end
	barrel = barrel or Vector3.new(0, 0, -1)
	local big = def.Class == "Rifle" or def.Class == "Shotgun"

	-- fire, light, smoke
	Fx.EmitAt(muzzlePosition, "Fire", if big then 8 else 5, { Direction = barrel })
	Fx.EmitAt(muzzlePosition + barrel * 0.15, "Flash", 1, { Direction = barrel, Scale = if big then 1.35 else 1 })
	Fx.EmitAt(muzzlePosition, "Smoke", if def.Class == "Shotgun" then 5 else 3, { Direction = barrel, Speed = 0.7, Scale = if big then 1.2 else 0.9 })
	if muzzle then
		Fx.Flash(muzzle, FIRE_COLOR, if big then 18 else 14, 0.08)
	end

	-- the report: duller and quieter with distance, with an echo off the hills
	local far = math.clamp((distance - 50) / 350, 0, 1)
	Fx.Sound(gunSound(def), muzzle or muzzlePosition, {
		Volume = def.Sound.Volume * (1 - far * 0.45),
		Pitch = def.Sound.Pitch * (1 - far * 0.22) * (0.96 + rng:NextNumber() * 0.08),
		RollOff = 1000,
		RollOffMin = 30,
		StopAfter = def.Sound.Length + 0.35,
		Effects = { echo },
	})

	-- streaks and impacts
	local streaks = 0
	for _, impact in impacts do
		local to = impact.Position
		local travel = (to - muzzlePosition).Magnitude
		if travel > 6 and streaks < 3 then
			streaks += 1
			Fx.Streak(muzzlePosition, to, { Width = 0.05, Length = 6, Speed = 1400, Transparency = 0.55, Color = Color3.fromRGB(255, 234, 186) })
		end
		task.delay(math.min(travel / 1400, 0.35), WeaponFX.Impact, impact, muzzlePosition)
	end

	if distance < DETAIL_RANGE or isLocal then
		local model = muzzle and muzzle.Parent and muzzle.Parent.Parent
		mechanics(if model and model:IsA("Model") then model else nil, def, muzzle or muzzlePosition)
	end
end

-- Someone else's shot, from the server: impacts arrive as { position, normal | false, surface }.
function WeaponFX.RemoteShot(shooter: Player?, weaponId: string, origin: Vector3, raw)
	if typeof(origin) ~= "Vector3" or type(raw) ~= "table" then
		return
	end
	local character = shooter and shooter.Character
	if character then
		UpperBody.OnShot(character, weaponId, character:GetAttribute("Aiming") ~= true)
	end
	local impacts = {}
	for _, entry in raw do
		if type(entry) == "table" and typeof(entry[1]) == "Vector3" then
			table.insert(impacts, {
				Position = entry[1],
				Normal = if typeof(entry[2]) == "Vector3" then entry[2] else nil,
				Surface = if type(entry[3]) == "string" then entry[3] else "Stone",
			})
		end
	end
	WeaponFX.Shot(character, weaponId, origin, impacts, false)
end

-- Out of rounds.
function WeaponFX.DryFire(character: Model?, weaponId: string)
	local muzzle = character and UpperBody.Muzzle(character, weaponId)
	if muzzle then
		click(muzzle, 1.55, 0.4)
	end
end

-- Drawing or holstering: leather and steel.
function WeaponFX.Draw(character: Model?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		Fx.Sound(RUSTLE, root, { Volume = 0.22, Pitch = 1.7 + rng:NextNumber() * 0.2, RollOff = 40, RollOffMin = 4, StopAfter = 0.3 })
	end
end

function WeaponFX.ReloadStart(character: Model?, weaponId: string)
	local muzzle = character and UpperBody.Muzzle(character, weaponId)
	if muzzle then
		Fx.Sound(soundOr("Reload", RUSTLE), muzzle, { Volume = 0.2, Pitch = 1.4, RollOff = 40, RollOffMin = 4, StopAfter = 0.3 })
		click(muzzle, 0.85, 0.35, 0.1)
	end
end

-- One round (or the clip) goes in.
function WeaponFX.RoundIn(character: Model?, weaponId: string)
	local muzzle = character and UpperBody.Muzzle(character, weaponId)
	if muzzle then
		Fx.Sound(TAP, muzzle, { Volume = 0.25, Pitch = 2.1 + rng:NextNumber() * 0.2, RollOff = 40, RollOffMin = 4, StopAfter = 0.1 })
	end
end

function WeaponFX.ReloadDone(character: Model?, weaponId: string)
	local muzzle = character and UpperBody.Muzzle(character, weaponId)
	if muzzle then
		click(muzzle, 1.05, 0.4)
	end
end

-- The shooter's confirmation that a bullet connected.
function WeaponFX.HitConfirm(kind: string)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if kind == "Kill" then
		Fx.Sound(THUD, camera, { Volume = 0.45, Pitch = 0.8, StopAfter = 0.3 })
	end
	Fx.Sound(CLICK, camera, { Volume = if kind == "Head" then 0.5 else 0.35, Pitch = if kind == "Head" then 2.2 else 1.8, StopAfter = 0.15 })
end

-- A character was hit (every client): they flinch where the bullet struck.
function WeaponFX.Flinch(victim: Instance?, partName: unknown, direction: unknown, strength: unknown, killed: unknown)
	if typeof(victim) ~= "Instance" or not victim:IsA("Model") or typeof(direction) ~= "Vector3" then
		return
	end
	local amount = if type(strength) == "number" then strength else 0.6
	UpperBody.Flinch(victim, if type(partName) == "string" then partName else "Torso", direction, amount * (if killed then 1.5 else 1))
end

return WeaponFX
