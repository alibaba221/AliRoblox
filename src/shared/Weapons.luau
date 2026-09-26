--[[
	SicilyShared.Weapons
	Every gun in the game. The server uses these numbers for damage, fire rate, ammo and hit
	validation; clients use them for handling, recoil, spread, animation and sound.

	To add a variant, add an entry with `Inherit` and only the fields that differ:

		Weapons.Defs.Schofield = { Inherit = "Cattleman", DisplayName = "Schofield Revolver", Damage = 44 }

	Then put its id in Config.Combat.Loadout (or on the weapon rack).

	Units: studs, seconds, degrees. Damage is per bullet (per pellet for shotguns) before the
	body-part multiplier and distance falloff. Players have 100 health.
]]

local Weapons = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STEEL = rgb(64, 64, 70)
local BLUED = rgb(44, 46, 54)
local BRASS = rgb(196, 156, 74)
local WALNUT = rgb(116, 72, 42)
local MAPLE = rgb(150, 100, 58)

-- Built-in stand-in for a gunshot (a Roblox explosion clip, sped up and trimmed). Paste real
-- sound ids into Config.Combat.Sounds to replace it.
local BANG = "rbxasset://sounds/impact_explosion_03.mp3"

Weapons.Defs = {
	-- Single-action revolver: accurate when aimed, "fanned" fast from the hip.
	Cattleman = {
		DisplayName = "Cattleman Revolver",
		Class = "Revolver",
		Model = "Revolver",
		Hold = "Pistol",
		Slot = "Sidearm",
		Holster = "HipRight",
		Colors = { Metal = STEEL, Grip = WALNUT, Accent = BRASS },

		Damage = 38,
		HeadMultiplier = 2.4,
		LimbMultiplier = 0.7,
		Range = 260,
		FalloffStart = 70,
		FalloffEnd = 190,
		MinDamage = 0.55, -- fraction of damage at FalloffEnd and beyond
		Pellets = 1,

		Action = "Hammer", -- cocked between shots (animation): Hammer | Lever | Bolt | None
		FireInterval = 0.46, -- aimed
		HipFireInterval = 0.24, -- fanning the hammer
		Magazine = 6,
		Reserve = 54,
		Reload = { Kind = "PerRound", Start = 0.35, PerRound = 0.3, Finish = 0.25 },
		DrawTime = 0.3,
		HolsterTime = 0.3,

		Spread = { Aim = 0.35, Hip = 3.4, Moving = 1.6, Mounted = 1.3, Bloom = 1.1, BloomMax = 4.5, Recovery = 7 },
		Recoil = { Pitch = 3.6, Yaw = 1.1, Roll = 1.4, Kick = 0.3 },
		AimFOV = 54,
		AimDistance = 6.2,
		AimAssist = 1,

		Sound = { Id = BANG, Pitch = 2.2, Volume = 0.8, Length = 0.7 },
		ShellColor = nil, -- revolvers keep their cases
	},

	-- Semi-automatic "broomhandle" pistol: quick follow-ups, a stripper-clip reload.
	Mauser = {
		DisplayName = "Mauser Pistol",
		Class = "Pistol",
		Model = "Pistol",
		Hold = "Pistol",
		Slot = "Sidearm",
		Holster = "HipLeft",
		Colors = { Metal = BLUED, Grip = WALNUT, Accent = STEEL },

		Damage = 30,
		HeadMultiplier = 2.2,
		LimbMultiplier = 0.7,
		Range = 220,
		FalloffStart = 50,
		FalloffEnd = 160,
		MinDamage = 0.5,
		Pellets = 1,

		Action = "None",
		FireInterval = 0.22,
		HipFireInterval = 0.2,
		Magazine = 10,
		Reserve = 70,
		Reload = { Kind = "Clip", Time = 1.7 },
		DrawTime = 0.32,
		HolsterTime = 0.3,

		Spread = { Aim = 0.45, Hip = 3.0, Moving = 1.4, Mounted = 1.3, Bloom = 0.8, BloomMax = 4, Recovery = 6 },
		Recoil = { Pitch = 2.4, Yaw = 0.9, Roll = 0.8, Kick = 0.2 },
		AimFOV = 55,
		AimDistance = 6.2,
		AimAssist = 1,

		Sound = { Id = BANG, Pitch = 2.6, Volume = 0.65, Length = 0.55 },
		ShellColor = BRASS,
	},

	-- Lever-action repeater: the all-rounder.
	Carbine = {
		DisplayName = "Carbine Repeater",
		Class = "Repeater",
		Model = "Repeater",
		Hold = "Long",
		Slot = "Longarm",
		Holster = "BackRight",
		Colors = { Metal = BLUED, Grip = MAPLE, Accent = BRASS },

		Damage = 44,
		HeadMultiplier = 2.2,
		LimbMultiplier = 0.75,
		Range = 330,
		FalloffStart = 110,
		FalloffEnd = 260,
		MinDamage = 0.6,
		Pellets = 1,

		Action = "Lever",
		FireInterval = 0.55,
		HipFireInterval = 0.48,
		Magazine = 12,
		Reserve = 72,
		Reload = { Kind = "PerRound", Start = 0.4, PerRound = 0.26, Finish = 0.35 },
		DrawTime = 0.5,
		HolsterTime = 0.45,

		Spread = { Aim = 0.25, Hip = 4.0, Moving = 1.8, Mounted = 1.5, Bloom = 0.9, BloomMax = 4, Recovery = 6 },
		Recoil = { Pitch = 3.0, Yaw = 1.0, Roll = 1.0, Kick = 0.25 },
		AimFOV = 48,
		AimDistance = 5.8,
		AimAssist = 0.9,

		Sound = { Id = BANG, Pitch = 1.8, Volume = 0.85, Length = 0.8 },
		ShellColor = BRASS,
	},

	-- Bolt-action rifle: one clean shot at long range.
	Carcano = {
		DisplayName = "Carcano Rifle",
		Class = "Rifle",
		Model = "Rifle",
		Hold = "Long",
		Slot = "Longarm",
		Holster = "BackLeft",
		Colors = { Metal = STEEL, Grip = WALNUT, Accent = STEEL },

		Damage = 78,
		HeadMultiplier = 2.2,
		LimbMultiplier = 0.8,
		Range = 520,
		FalloffStart = 240,
		FalloffEnd = 460,
		MinDamage = 0.75,
		Pellets = 1,

		Action = "Bolt",
		FireInterval = 1.15,
		HipFireInterval = 1.05,
		Magazine = 6,
		Reserve = 36,
		Reload = { Kind = "Clip", Time = 2.1 },
		DrawTime = 0.55,
		HolsterTime = 0.5,

		Spread = { Aim = 0.08, Hip = 5.0, Moving = 2.5, Mounted = 2.0, Bloom = 1.5, BloomMax = 5, Recovery = 4 },
		Recoil = { Pitch = 5.5, Yaw = 1.2, Roll = 1.6, Kick = 0.38 },
		AimFOV = 36,
		AimDistance = 5.4,
		AimAssist = 0.7,

		Sound = { Id = BANG, Pitch = 1.45, Volume = 1, Length = 1.1 },
		ShellColor = BRASS,
	},

	-- Sawn-off double barrel, the lupara: devastating up close, useless far away.
	Lupara = {
		DisplayName = "Lupara",
		Class = "Shotgun",
		Model = "Shotgun",
		Hold = "Long",
		Slot = "Longarm",
		Holster = "BackLow",
		Colors = { Metal = STEEL, Grip = WALNUT, Accent = BRASS },

		Damage = 13,
		HeadMultiplier = 1.6,
		LimbMultiplier = 0.8,
		Range = 110,
		FalloffStart = 16,
		FalloffEnd = 55,
		MinDamage = 0.2,
		Pellets = 9,

		Action = "None",
		FireInterval = 0.32,
		HipFireInterval = 0.3,
		Magazine = 2,
		Reserve = 30,
		Reload = { Kind = "PerRound", Start = 0.45, PerRound = 0.38, Finish = 0.35 },
		DrawTime = 0.45,
		HolsterTime = 0.4,

		Spread = { Aim = 3.2, Hip = 5.5, Moving = 1.2, Mounted = 1.0, Bloom = 0.6, BloomMax = 2, Recovery = 5, Pellet = 3.6 },
		Recoil = { Pitch = 7, Yaw = 2, Roll = 2.5, Kick = 0.45 },
		AimFOV = 56,
		AimDistance = 5.8,
		AimAssist = 1.2,

		Sound = { Id = BANG, Pitch = 1.25, Volume = 1, Length = 1.0 },
		ShellColor = rgb(170, 40, 36),
	},

	-- Example variants (not in the default loadout).
	Schofield = {
		Inherit = "Cattleman",
		DisplayName = "Schofield Revolver",
		Damage = 42,
		FireInterval = 0.5,
		Colors = { Metal = rgb(150, 150, 156), Grip = rgb(60, 40, 30), Accent = STEEL },
	},
	Lancaster = {
		Inherit = "Carbine",
		DisplayName = "Lancaster Repeater",
		Damage = 40,
		FireInterval = 0.45,
		Magazine = 14,
		Colors = { Metal = STEEL, Grip = WALNUT, Accent = STEEL },
	},
}

-- Where holstered weapons sit on the body (Torso space). Grip (the Handle) placement.
-- (barrel down, grip back on the right hip; butt forward on the left hip for a cross-draw)
local BARREL_DOWN = CFrame.Angles(math.rad(-90), 0, 0)
Weapons.Holsters = {
	HipRight = CFrame.new(1.13, -0.95, 0.12) * CFrame.Angles(0, 0, math.rad(-6)) * BARREL_DOWN,
	HipLeft = CFrame.new(-1.13, -0.95, -0.12) * CFrame.Angles(0, math.pi, math.rad(-6)) * BARREL_DOWN,
	BackRight = CFrame.new(0.2, 0.1, 0.72) * CFrame.Angles(0, 0, math.rad(-38)) * CFrame.Angles(math.rad(-90), 0, 0),
	BackLeft = CFrame.new(-0.2, 0.2, 0.86) * CFrame.Angles(0, 0, math.rad(38)) * CFrame.Angles(math.rad(-90), 0, 0),
	-- slung barrel-down across the back, below the rifles
	BackLow = CFrame.new(0.55, -0.5, 1.0) * CFrame.Angles(0, math.pi, math.rad(12)) * BARREL_DOWN,
}

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function resolve(name: string, seen: { [string]: boolean }?)
	local entry = Weapons.Defs[name]
	if not entry then
		return nil
	end
	local visited = seen or {}
	assert(not visited[name], "Weapons: circular Inherit at " .. name)
	visited[name] = true
	local result = if entry.Inherit then deepCopy(resolve(entry.Inherit, visited)) else {}
	for key, value in entry do
		if key ~= "Inherit" then
			if type(value) == "table" and type(result[key]) == "table" then
				-- merge one level deep, so a variant can change a single spread/recoil number
				for k, v in value do
					result[key][k] = deepCopy(v)
				end
			else
				result[key] = deepCopy(value)
			end
		end
	end
	result.Id = name
	return result
end

local cache = {}

-- Fully resolved weapon definition, or nil for an unknown id.
function Weapons.Get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	if cache[id] == nil then
		cache[id] = resolve(id) or false
	end
	return cache[id] or nil
end

-- Minimum time the server allows between two shots of a weapon.
function Weapons.MinInterval(def): number
	return math.min(def.FireInterval, def.HipFireInterval)
end

-- Total reload time for `missing` rounds.
function Weapons.ReloadTime(def, missing: number): number
	local r = def.Reload
	if r.Kind == "PerRound" then
		return r.Start + r.PerRound * missing + r.Finish
	end
	return r.Time
end

-- Damage multiplier for distance (1 up close, MinDamage far away).
function Weapons.Falloff(def, distance: number): number
	if distance <= def.FalloffStart then
		return 1
	end
	local t = math.clamp((distance - def.FalloffStart) / math.max(def.FalloffEnd - def.FalloffStart, 1), 0, 1)
	return 1 + (def.MinDamage - 1) * t
end

return Weapons
