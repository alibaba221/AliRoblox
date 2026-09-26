--[[
	Cinematic lighting presets (Sicilian golden hour by default) + optional day/night cycle.

	NOTE: Lighting.Technology can't be set from scripts. For the intended look, set
	Lighting > Technology to "Future" in Studio (or LightingStyle = Realistic on the new system).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("SicilyShared"):WaitForChild("Config"))

local LightingPreset = {}

LightingPreset.LampTag = "SicilyLamp"

local PRESETS = {
	GoldenHour = {
		Lighting = {
			ClockTime = 17.35,
			GeographicLatitude = 37.5,
			Brightness = 2.8,
			ExposureCompensation = 0.12,
			Ambient = Color3.fromRGB(62, 50, 46),
			OutdoorAmbient = Color3.fromRGB(136, 112, 98),
			ColorShift_Top = Color3.fromRGB(255, 212, 166),
			ColorShift_Bottom = Color3.fromRGB(62, 44, 36),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.65,
			ShadowSoftness = 0.16,
			GlobalShadows = true,
			FogEnd = 100000,
			FogStart = 0,
		},
		Atmosphere = {
			Density = 0.3,
			Offset = 0.24,
			Color = Color3.fromRGB(214, 176, 140),
			Decay = Color3.fromRGB(128, 92, 84),
			Glare = 0.6,
			Haze = 1.7,
		},
		Bloom = { Intensity = 0.55, Size = 28, Threshold = 1.3 },
		SunRays = { Intensity = 0.075, Spread = 0.72 },
		ColorCorrection = {
			Brightness = 0.015,
			Contrast = 0.14,
			Saturation = 0.1,
			TintColor = Color3.fromRGB(255, 244, 230),
		},
		DepthOfField = { FarIntensity = 0.12, FocusDistance = 60, InFocusRadius = 55, NearIntensity = 0 },
		Clouds = { Cover = 0.5, Density = 0.3, Color = Color3.fromRGB(255, 228, 200) },
		Sky = { SunAngularSize = 15, MoonAngularSize = 9, StarCount = 2500 },
		LampsOn = true,
	},

	BlueHour = {
		Lighting = {
			ClockTime = 18.45,
			GeographicLatitude = 37.5,
			Brightness = 1.4,
			ExposureCompensation = 0.35,
			Ambient = Color3.fromRGB(60, 58, 78),
			OutdoorAmbient = Color3.fromRGB(96, 100, 140),
			ColorShift_Top = Color3.fromRGB(255, 176, 120),
			ColorShift_Bottom = Color3.fromRGB(40, 40, 70),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.8,
			ShadowSoftness = 0.3,
			GlobalShadows = true,
			FogEnd = 100000,
			FogStart = 0,
		},
		Atmosphere = {
			Density = 0.34,
			Offset = 0.2,
			Color = Color3.fromRGB(128, 132, 172),
			Decay = Color3.fromRGB(122, 84, 110),
			Glare = 0.35,
			Haze = 1.4,
		},
		Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.1 },
		SunRays = { Intensity = 0.04, Spread = 0.6 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.16,
			Saturation = 0.08,
			TintColor = Color3.fromRGB(242, 240, 255),
		},
		DepthOfField = { FarIntensity = 0.1, FocusDistance = 60, InFocusRadius = 55, NearIntensity = 0 },
		Clouds = { Cover = 0.45, Density = 0.25, Color = Color3.fromRGB(210, 190, 220) },
		Sky = { SunAngularSize = 12, MoonAngularSize = 10, StarCount = 3000 },
		LampsOn = true,
	},

	Midday = {
		Lighting = {
			ClockTime = 13.4,
			GeographicLatitude = 37.5,
			Brightness = 3.2,
			ExposureCompensation = 0,
			Ambient = Color3.fromRGB(70, 66, 62),
			OutdoorAmbient = Color3.fromRGB(150, 146, 140),
			ColorShift_Top = Color3.fromRGB(255, 244, 226),
			ColorShift_Bottom = Color3.fromRGB(60, 54, 48),
			EnvironmentDiffuseScale = 0.8,
			EnvironmentSpecularScale = 0.8,
			ShadowSoftness = 0.12,
			GlobalShadows = true,
			FogEnd = 100000,
			FogStart = 0,
		},
		Atmosphere = {
			Density = 0.26,
			Offset = 0.2,
			Color = Color3.fromRGB(206, 214, 226),
			Decay = Color3.fromRGB(150, 160, 176),
			Glare = 0.2,
			Haze = 1.2,
		},
		Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.6 },
		SunRays = { Intensity = 0.03, Spread = 0.8 },
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.1,
			Saturation = 0.12,
			TintColor = Color3.fromRGB(255, 250, 244),
		},
		DepthOfField = { FarIntensity = 0.08, FocusDistance = 80, InFocusRadius = 70, NearIntensity = 0 },
		Clouds = { Cover = 0.6, Density = 0.35, Color = Color3.fromRGB(255, 255, 255) },
		Sky = { SunAngularSize = 11, MoonAngularSize = 9, StarCount = 3000 },
		LampsOn = false,
	},
}

local function setProps(instance: Instance, props: { [string]: any })
	for key, value in props do
		local ok, err = pcall(function()
			(instance :: any)[key] = value
		end)
		if not ok then
			warn(("[Sicily] Couldn't set %s.%s: %s"):format(instance.ClassName, key, tostring(err)))
		end
	end
end

local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local lampsOn = true

local function setLampState(lamp: Instance, on: boolean)
	for _, descendant in lamp:GetDescendants() do
		if descendant:IsA("Light") then
			descendant.Enabled = on
		elseif descendant:IsA("BasePart") and descendant.Name == "Bulb" then
			descendant.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		end
	end
end

function LightingPreset.SetLamps(on: boolean)
	lampsOn = on
	for _, lamp in CollectionService:GetTagged(LightingPreset.LampTag) do
		setLampState(lamp, on)
	end
end

local cycleRunning = false

local function startDayNightCycle()
	if cycleRunning then
		return
	end
	cycleRunning = true
	task.spawn(function()
		local hoursPerSecond = 24 / (math.max(Config.Lighting.MinutesPerDay, 1) * 60)
		while true do
			local dt = task.wait(0.1)
			local clock = (Lighting.ClockTime + dt * hoursPerSecond) % 24
			Lighting.ClockTime = clock
			local shouldBeOn = clock >= 17.2 or clock < 6.9
			if shouldBeOn ~= lampsOn then
				LightingPreset.SetLamps(shouldBeOn)
			end
		end
	end)
end

local lampSignalConnected = false

-- options.EditMode: applying from the Command Bar (Town.Bake) — never start the clock loop there.
function LightingPreset.Apply(presetName: string?, options: { EditMode: boolean? }?)
	local preset = PRESETS[presetName or "GoldenHour"] or PRESETS.GoldenHour
	local editMode = options ~= nil and options.EditMode == true

	if Config.Lighting.ReplaceExistingEffects then
		local stash = ServerStorage:FindFirstChild("SicilyReplacedLighting")
		if not stash then
			stash = Instance.new("Folder")
			stash.Name = "SicilyReplacedLighting"
			stash.Parent = ServerStorage
		end
		for _, child in Lighting:GetChildren() do
			local ours = string.sub(child.Name, 1, 6) == "Sicily"
			if not ours and (child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky")) then
				child.Parent = stash
			end
		end
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		local oldClouds = terrain and terrain:FindFirstChildOfClass("Clouds")
		if oldClouds and oldClouds.Name ~= "SicilyClouds" then
			oldClouds.Parent = stash
		end
	end

	setProps(Lighting, preset.Lighting)
	-- Newer lighting system properties; ignored on builds that don't have them.
	pcall(function()
		(Lighting :: any).LightingStyle = Enum.LightingStyle.Realistic
	end)
	pcall(function()
		(Lighting :: any).PrioritizeLightingQuality = true
	end)

	setProps(ensure(Lighting, "Atmosphere", "SicilyAtmosphere"), preset.Atmosphere)
	setProps(ensure(Lighting, "Sky", "SicilySky"), preset.Sky)
	setProps(ensure(Lighting, "BloomEffect", "SicilyBloom"), preset.Bloom)
	setProps(ensure(Lighting, "SunRaysEffect", "SicilySunRays"), preset.SunRays)
	setProps(ensure(Lighting, "ColorCorrectionEffect", "SicilyColorCorrection"), preset.ColorCorrection)
	setProps(ensure(Lighting, "DepthOfFieldEffect", "SicilyDepthOfField"), preset.DepthOfField)

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		setProps(ensure(terrain, "Clouds", "SicilyClouds"), preset.Clouds)
	end

	LightingPreset.SetLamps(preset.LampsOn)
	if editMode then
		return
	end
	if not lampSignalConnected then
		lampSignalConnected = true
		CollectionService:GetInstanceAddedSignal(LightingPreset.LampTag):Connect(function(lamp)
			setLampState(lamp, lampsOn)
		end)
	end
	if Config.Lighting.DayNightCycle then
		startDayNightCycle()
	end
end

return LightingPreset
