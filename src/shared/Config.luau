--[[
	SicilyShared.Config
	Every tunable for the Sicily upgrade lives here. Server and client both read it,
	so a change here applies everywhere the next time you press Play.
]]

local Config = {}

-- Player movement --------------------------------------------------------------
Config.Movement = {
	Enabled = true,

	WalkSpeed = 10, -- relaxed default pace (Roblox default is 16)
	RunSpeed = 23, -- while Shift / L3 / the mobile Run button is active

	-- How quickly the stick/WASD input is eased in and out (per second).
	-- Lower = heavier, more momentum. Higher = snappier.
	Acceleration = 6.5,
	Deceleration = 8.5,

	-- How quickly the speed itself ramps between walk and run (per second).
	SprintRampUp = 2.6,
	SprintRampDown = 4.5,

	-- Body turning (AlignOrientation responsiveness). Sprinting turns in wider arcs.
	TurnResponsiveness = 13,
	SprintTurnResponsiveness = 8,
	CameraRelativeTurnResponsiveness = 30, -- shift-lock / first person

	JumpHeight = 6.2, -- Roblox default is 7.2
	JumpCooldown = 0.18, -- seconds after landing before you can jump again

	-- A heavy landing briefly slows you down (and dips the camera).
	HardLandingSpeed = 58, -- downward studs/s that counts as a hard landing
	HardLandingSlowdown = 0.45, -- speed multiplier right after a hard landing
	HardLandingRecovery = 0.45, -- seconds to recover

	-- Only allow running when moving mostly forward relative to the camera?
	-- AAA third-person games let you run in any direction because the body turns.
	RunOnlyForward = false,

	-- Input bindings
	SprintKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
	GamepadSprintKey = Enum.KeyCode.ButtonL3, -- toggles (auto-cancels when you stop)
	MobileSprintButton = true,

	-- Shift is now Run, so the Shift-Lock toggle is moved to these keys.
	-- Set to "" to leave Roblox's shift lock bindings untouched.
	ShiftLockKeys = "LeftControl,RightControl",

	Stamina = {
		Enabled = false, -- flip on for a stamina-limited sprint
		Max = 7,
		DrainPerSecond = 1,
		RegenPerSecond = 1.4,
		RegenDelay = 0.9,
		MinToStart = 1.2,
	},
}

-- Camera -------------------------------------------------------------------------
Config.Camera = {
	Enabled = true,
	BaseFOV = 70,
	RunFOV = 79,
	FOVResponsiveness = 5,

	-- Soft follow: the camera trails the body a tiny bit instead of being glued to it.
	FollowFrequency = 7.5, -- Hz, higher = tighter
	MaxFollowLag = 1.4, -- studs

	WalkBob = 0.03, -- studs of vertical bob per step while walking
	RunBob = 0.1,
	RunShake = 0.022, -- tiny noise while sprinting
	StrafeTilt = 1.4, -- degrees of roll when moving sideways relative to the camera
	LandingDip = 0.55, -- studs per 50 studs/s of fall speed

	MinZoom = 0.5,
	MaxZoom = 28,
}

-- Characters ---------------------------------------------------------------------
Config.Characters = {
	ForceR6 = true, -- every player spawns as a classic R6 rig
	Blocky = true, -- strip bundle/package body meshes -> classic blocks
	KeepClothing = true, -- keep the player's 2D shirt / pants / t-shirt
	KeepAccessories = true, -- keep hats, hair, etc. (3D layered clothing can't fit R6 and is removed)
	KeepBodyColors = true,
	KeepFace = true,

	ConvertExistingNPCs = true, -- any humanoid NPC in Workspace is rebuilt as a blocky R6 in place
	KeepRigTag = "KeepRig", -- CollectionService tag to exclude an NPC from conversion

	Ragdoll = true, -- R6 ragdoll on death instead of breaking apart

	-- Used when a player's avatar can't be fetched (e.g. Studio test players).
	FallbackBodyColors = {
		Head = Color3.fromRGB(234, 184, 146),
		Torso = Color3.fromRGB(239, 233, 222),
		Arms = Color3.fromRGB(234, 184, 146),
		Legs = Color3.fromRGB(62, 58, 64),
	},
}

-- Procedural R6 animation (runs on every client, for players and NPCs) ------------
Config.Animation = {
	Enabled = true,
	MaxDistance = 260, -- characters further than this from the camera aren't animated
	LowRateDistance = 110, -- beyond this, update every other frame

	WalkStride = 5.6, -- studs travelled per full walk cycle (2 steps)
	RunStride = 8.4,
	HeadFollowsCamera = true, -- your own head looks where the camera looks
	NPCHeadTracking = true, -- NPCs glance at players who walk past
}

-- The town ------------------------------------------------------------------------
Config.Town = {
	Enabled = true,
	Name = "Castelmare",
	Seed = 1693, -- same seed = same town every time

	-- Clears existing Terrain before generating (runtime only; your saved place is untouched).
	ClearTerrain = true,

	-- Names of old map containers in Workspace to hide when the town is generated at runtime
	-- (they are moved to ServerStorage while the server runs, never deleted). Example: { "CowboyMap" }
	HideOnBuild = {},

	-- Hold character spawning until the town exists so nobody falls into the void.
	HoldSpawnsUntilBuilt = true,
	-- Always spawn players on the town's spawn points, even if old SpawnLocations still exist.
	UseTownSpawns = true,

	TownsfolkCount = 20,
	Vendors = true,
}

-- Lighting ------------------------------------------------------------------------
Config.Lighting = {
	Enabled = true,
	Preset = "GoldenHour", -- "GoldenHour" | "BlueHour" | "Midday"
	ReplaceExistingEffects = true, -- removes old Sky/Atmosphere/post effects from Lighting at runtime
	DayNightCycle = false,
	MinutesPerDay = 30, -- real minutes for a full 24h when the cycle is on
}

-- Intro / HUD ---------------------------------------------------------------------
Config.Intro = {
	Enabled = true,
	Title = "CASTELMARE",
	Subtitle = "S I C I L I A",
	ShotDuration = 4.2,
	PlayOnce = true, -- only on first spawn, not on respawn
}

Config.Hud = {
	ControlsHint = true,
	RunVignette = true,
	SpawnFade = true,
}

-- Horses --------------------------------------------------------------------------
-- Horse stats (speeds, turning, stamina, taming difficulty) and coats: SicilyShared.HorseTypes
Config.Horses = {
	Enabled = true,

	-- Wild herds roaming open country. Center is (x, z) on the map; each horse picks a random
	-- coat unless Coats is given. Temperament: "Calm" (easy to tame), "Spirited", "Wild" (hard).
	Herds = {
		{ Name = "Piana del Castello", Center = Vector2.new(-192, -186), Radius = 42, Count = 3, Temperament = "Spirited" },
		{ Name = "Prato di Levante", Center = Vector2.new(200, -206), Radius = 45, Count = 3, Temperament = "Calm" },
		{ Name = "Colle Est", Center = Vector2.new(280, -40), Radius = 28, Count = 2, Temperament = "Wild" },
		{ Name = "Piana Ovest", Center = Vector2.new(-398, -275), Radius = 55, Count = 2, Temperament = "Wild" },
	},

	-- Saddled horses at the stable by the west gate. Anyone can ride them, no taming needed.
	StableHorses = 2,
	StableCoats = { "Bay", "Grey" },

	RespawnTime = 75, -- a lost wild horse (fell in the sea, stuck, tamed then abandoned) is replaced
	AbandonTime = 150, -- a tamed horse left alone this long (owner gone/far) returns to its herd/stable
	MountDistance = 9, -- studs from the saddle to show "Mount"

	-- Controls (keyboard / gamepad). Mount uses a ProximityPrompt; E again to dismount.
	MountKey = Enum.KeyCode.E,
	MountGamepadKey = Enum.KeyCode.ButtonY,
	CallKey = Enum.KeyCode.H, -- whistle: your horse comes to you
	CallGamepadKey = Enum.KeyCode.DPadUp,
	CallRange = 400,
	-- Keyboard W is a trot; hold Shift (L3 / RUN on mobile) to gallop. Hold Alt to walk.
	WalkKeys = { Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt },

	-- Camera while riding
	CameraExtraDistance = 4.5, -- pulled back a little so the whole horse is in view
	GallopFOV = 84,
	AutoFollow = true, -- camera swings in behind the horse when you stop steering it
	AutoFollowDelay = 1.3, -- seconds after your last camera input
	AutoFollowSpeed = 1.6,

	-- Hooves / snorts. Leave "" for the built-in approximation (pitched footsteps).
	HoofSoundId = "",
	SnortSoundId = "",
	NeighSoundId = "",
}

-- Combat --------------------------------------------------------------------------
-- Weapon stats (damage, fire rate, recoil, spread, ammo, reload): SicilyShared.Weapons
Config.Combat = {
	Enabled = true,
	-- Guns every player spawns with (ids from SicilyShared.Weapons). Keys 1-5 pick them.
	Loadout = { "Cattleman", "Mauser", "Carbine", "Carcano", "Lupara" },
	PvP = true, -- players can hurt each other
	DamageTownsfolk = true, -- townsfolk can be shot (they ragdoll and come back later)
	TownsfolkRespawn = 45,
	GunBelt = true, -- leather belt, holsters and a bandolier on every player

	-- Hit validation (the server checks every hit a client reports)
	MaxOriginDistance = 7, -- muzzle must be this close to the shooter's head (+ movement)
	HitTolerance = 2.5, -- extra studs allowed between a reported hit and the part (lag, poses)
	FireRateTolerance = 0.05, -- seconds of slack on the fastest allowed fire rate

	-- Dead Eye: slow the moment down and paint targets, then fire at all of them.
	DeadEye = {
		Enabled = true,
		Max = 100,
		Cost = 25, -- needed to activate
		DrainPerSecond = 16,
		RegenPerSecond = 2.5,
		RegenPerHit = 6,
		ShotInterval = 0.13, -- time between the marked shots
		SlowWalk = 0.55, -- your own movement is slowed while it's active
	},

	-- Aim assist (never on mouse): a gentle pull when you start aiming near a target and a
	-- little friction while the crosshair is on one.
	AimAssist = {
		Gamepad = 1,
		Touch = 1.3,
		Mouse = 0,
		SnapAngle = 7, -- degrees around the crosshair a target can be snapped from
		SnapStrength = 0.6,
		Friction = 0.35,
		Range = 180,
	},

	Cover = {
		Enabled = true,
		SearchDistance = 4.5,
		LowHeight = 4.2, -- cover lower than this (above your feet) is crouched behind
	},

	-- Controls
	Keys = {
		Aim = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 },
		Fire = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		Reload = { Enum.KeyCode.R, Enum.KeyCode.ButtonX },
		Holster = { Enum.KeyCode.X, Enum.KeyCode.DPadDown },
		NextWeapon = { Enum.KeyCode.Q, Enum.KeyCode.DPadRight },
		PreviousWeapon = { Enum.KeyCode.DPadLeft },
		DeadEye = { Enum.KeyCode.F, Enum.KeyCode.ButtonR3 },
		Cover = { Enum.KeyCode.C, Enum.KeyCode.ButtonR1 },
		Slots = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five },
	},

	-- Optional real sounds (rbxassetid://...). "" keeps the built-in stand-ins.
	Sounds = {
		Revolver = "",
		Pistol = "",
		Repeater = "",
		Rifle = "",
		Shotgun = "",
		Reload = "",
		Cock = "",
		Impact = "",
		Ricochet = "",
		DeadEyeLoop = "",
	},
	ShowBloodPuffs = false, -- red puffs on hits instead of dust
}

-- Audio ---------------------------------------------------------------------------
Config.Audio = {
	Footsteps = true,
	FootstepVolume = 0.32,
	-- Optional: paste your own sound ids ("rbxassetid://123") to replace the built-in step sound.
	FootstepSoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
	JumpSoundId = "rbxasset://sounds/action_jump.mp3",
	LandSoundId = "rbxasset://sounds/action_jump_land.mp3",
	SplashSoundId = "rbxasset://sounds/impact_water.mp3",
	SwimSoundId = "rbxasset://sounds/action_swim.mp3",

	-- Optional ambience loops (leave "" to disable). Find sounds in the Creator Store.
	Ambience = {
		Town = "", -- e.g. distant chatter / accordion
		Sea = "", -- waves, near the harbour
		ChurchBells = "", -- rung every in-game hour
	},
}

return Config
