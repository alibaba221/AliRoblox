--[[
	SicilyShared.HorseTypes
	Horse temperaments (how a horse moves, how hard it is to tame) and coats (how it looks).

	To add a variant, add an entry. `Inherit` copies another entry first, so a variant only lists
	what's different:

		HorseTypes.Temperaments.Racer = { Inherit = "Spirited", GallopSpeed = 36, Stamina = 9 }
		HorseTypes.Coats.Sorrel = { Inherit = "Chestnut", Body = Color3.fromRGB(176, 96, 52) }

	Speeds are studs/s (players walk at 10 and run at 23). Turn rates are degrees/s.
]]

local HorseTypes = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

HorseTypes.Temperaments = {
	Spirited = {
		DisplayName = "Spirited",

		WalkSpeed = 7.5,
		TrotSpeed = 15,
		CanterSpeed = 23,
		GallopSpeed = 32,
		BackSpeed = 3.5,
		SwimSpeed = 7,

		Acceleration = 9, -- studs/s² when speeding up to walk/trot/canter
		GallopAcceleration = 7, -- the last push to full gallop is slower
		Deceleration = 11, -- letting go of the controls
		Braking = 24, -- pulling back

		-- Turn rate by speed (degrees/s); in between is interpolated. Faster = wider arcs.
		TurnRates = { Idle = 105, Walk = 115, Trot = 95, Canter = 78, Gallop = 62 },
		TurnAcceleration = 480, -- degrees/s² (no instant rotation)

		JumpHeight = 6.5, -- studs, at a canter or gallop
		JumpCooldown = 0.9,

		-- Galloping uses stamina (seconds of gallop). Empty = winded (canter only for a bit).
		Stamina = 12,
		StaminaRegen = 0.8, -- per second while not galloping
		StaminaRegenDelay = 1.2,
		WindedTime = 2.5,
		SpurCost = 1.2, -- a fresh press of Shift/L3 gives a short burst for this much stamina
		SpurBoost = 1.14,
		SpurTime = 1.1,

		-- Wild behaviour
		AlertRadius = 34, -- notices players inside this radius
		SpookRadius = 17, -- bolts if a player runs up closer than this
		GunshotSpookRadius = 110,

		-- Taming (see Taming.luau): progress starts at StartProgress and must reach 1.
		Taming = {
			StartProgress = 0.35,
			Decay = 0.12, -- progress lost per second
			PressGain = 0.066, -- progress per E press
			BuckKnock = 0.085, -- progress lost on each big buck
			BuckRate = 0.9, -- bucks per second
			MaxDuration = 16, -- seconds before the horse wins
			GraceTime = 1.2, -- no progress loss for the first moments
			RetryCooldown = 4,
		},
	},

	Calm = {
		Inherit = "Spirited",
		DisplayName = "Calm",
		GallopSpeed = 30,
		AlertRadius = 26,
		SpookRadius = 11,
		Stamina = 14,
		Taming = {
			StartProgress = 0.45,
			Decay = 0.085,
			PressGain = 0.075,
			BuckKnock = 0.06,
			BuckRate = 0.7,
			MaxDuration = 18,
			GraceTime = 1.5,
			RetryCooldown = 3,
		},
	},

	Wild = {
		Inherit = "Spirited",
		DisplayName = "Wild",
		TrotSpeed = 16,
		CanterSpeed = 24.5,
		GallopSpeed = 35,
		Stamina = 10,
		AlertRadius = 44,
		SpookRadius = 24,
		TurnRates = { Idle = 115, Walk = 120, Trot = 100, Canter = 82, Gallop = 66 },
		Taming = {
			StartProgress = 0.32,
			Decay = 0.15,
			PressGain = 0.062,
			BuckKnock = 0.11,
			BuckRate = 1.15,
			MaxDuration = 14,
			GraceTime = 1,
			RetryCooldown = 6,
		},
	},
}

--[[
	Coats. Body/Mane/Points (lower legs)/Hoof/Muzzle colours; optional markings:
	  Blaze (white stripe down the face), Socks = { "FL", "FR", "HL", "HR" } (white lower legs),
	  Patches = true (pinto).
]]
HorseTypes.Coats = {
	Bay = {
		DisplayName = "Bay",
		Body = rgb(122, 70, 40),
		Mane = rgb(30, 24, 22),
		Points = rgb(38, 30, 26),
		Hoof = rgb(46, 40, 36),
		Muzzle = rgb(58, 40, 30),
		Blaze = true,
	},
	Chestnut = {
		DisplayName = "Chestnut",
		Body = rgb(158, 82, 42),
		Mane = rgb(120, 58, 30),
		Points = rgb(148, 76, 40),
		Hoof = rgb(70, 58, 48),
		Muzzle = rgb(96, 56, 36),
		Socks = { "HL", "FR" },
	},
	Black = {
		DisplayName = "Black",
		Body = rgb(34, 32, 34),
		Mane = rgb(20, 18, 20),
		Points = rgb(28, 26, 28),
		Hoof = rgb(40, 38, 38),
		Muzzle = rgb(30, 28, 30),
	},
	Grey = {
		DisplayName = "Dapple Grey",
		Body = rgb(196, 196, 192),
		Mane = rgb(120, 120, 124),
		Points = rgb(136, 136, 138),
		Hoof = rgb(70, 66, 62),
		Muzzle = rgb(110, 110, 112),
	},
	Palomino = {
		DisplayName = "Palomino",
		Body = rgb(214, 170, 96),
		Mane = rgb(246, 236, 212),
		Points = rgb(206, 162, 92),
		Hoof = rgb(96, 80, 64),
		Muzzle = rgb(160, 120, 84),
		Blaze = true,
		Socks = { "FL", "FR", "HL", "HR" },
	},
	Pinto = {
		DisplayName = "Pinto",
		Body = rgb(110, 66, 42),
		Mane = rgb(40, 32, 28),
		Points = rgb(236, 232, 224),
		Hoof = rgb(90, 80, 70),
		Muzzle = rgb(74, 50, 38),
		Patches = true,
		Blaze = true,
	},
	Dun = {
		DisplayName = "Dun",
		Body = rgb(190, 156, 110),
		Mane = rgb(52, 42, 34),
		Points = rgb(60, 48, 38),
		Hoof = rgb(50, 44, 40),
		Muzzle = rgb(80, 64, 50),
	},
}

HorseTypes.Tack = {
	Leather = rgb(92, 56, 34),
	LeatherDark = rgb(58, 36, 24),
	Blanket = rgb(164, 38, 42),
	BlanketStripe = rgb(232, 196, 92),
	Metal = rgb(176, 172, 160),
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

local function resolve(list, name: string, seen: { [string]: boolean }?)
	local entry = list[name]
	if not entry then
		return nil
	end
	local visited = seen or {}
	assert(not visited[name], "HorseTypes: circular Inherit at " .. name)
	visited[name] = true
	local result = if entry.Inherit then deepCopy(resolve(list, entry.Inherit, visited)) else {}
	for key, value in entry do
		if key ~= "Inherit" then
			result[key] = deepCopy(value)
		end
	end
	result.Id = name
	return result
end

local cache = {}

-- Fully resolved temperament (inheritance applied). Unknown names fall back to "Spirited".
function HorseTypes.GetTemperament(name: string?)
	local key = "T:" .. tostring(name)
	if not cache[key] then
		cache[key] = resolve(HorseTypes.Temperaments, name or "Spirited")
			or resolve(HorseTypes.Temperaments, "Spirited")
	end
	return cache[key]
end

function HorseTypes.GetCoat(name: string?)
	local key = "C:" .. tostring(name)
	if not cache[key] then
		cache[key] = resolve(HorseTypes.Coats, name or "Bay") or resolve(HorseTypes.Coats, "Bay")
	end
	return cache[key]
end

function HorseTypes.CoatNames(): { string }
	local names = {}
	for name in HorseTypes.Coats do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Turn rate (radians/s) for a given forward speed, interpolated between the gait anchors.
function HorseTypes.TurnRate(temperament, speed: number): number
	local rates = temperament.TurnRates
	local anchors = {
		{ 0, rates.Idle },
		{ temperament.WalkSpeed, rates.Walk },
		{ temperament.TrotSpeed, rates.Trot },
		{ temperament.CanterSpeed, rates.Canter },
		{ temperament.GallopSpeed, rates.Gallop },
	}
	local s = math.abs(speed)
	if s <= 0 then
		return math.rad(rates.Idle)
	end
	for i = 2, #anchors do
		local a, b = anchors[i - 1], anchors[i]
		if s <= b[1] then
			local t = (s - a[1]) / math.max(b[1] - a[1], 1e-3)
			return math.rad(a[2] + (b[2] - a[2]) * t)
		end
	end
	return math.rad(rates.Gallop)
end

return HorseTypes
