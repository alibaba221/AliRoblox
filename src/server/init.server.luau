--[[
	SicilyServer — boots the Sicily upgrade.

	  1. Blocky R6 characters for every player (and holds spawns until the town exists).
	  2. Golden-hour lighting.
	  3. Generates the Sicilian town, unless a baked copy named "SicilianTown" is already in Workspace.
	     (To bake it into your place so you can see/edit it in Studio, run this in the command bar:
	        require(game.ServerScriptService.SicilyServer.Town).Bake()
	     then save the place.)
	  4. Townsfolk NPCs + converts existing NPCs to blocky R6.
	  5. Wild horses you can tame and ride, and saddled horses at the stable.
	  6. Guns: loadouts, server-validated shooting, the shooting range.

	All settings: ReplicatedStorage.SicilyShared.Config
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Characters = require(script.Characters)
local CollisionGroups = require(script.CollisionGroups)
local Combat = require(script.Combat)
local Horses = require(script.Horses)
local LightingPreset = require(script.LightingPreset)
local NPCs = require(script.NPCs)
local Town = require(script.Town)

-- Remotes and collision groups first, so clients that join while the town generates don't wait.
Remotes.Init()
CollisionGroups.Setup()

local townExists = Town.GetBuilt() ~= nil
local releaseSpawns = Characters.Start({
	HoldSpawns = Config.Town.Enabled and Config.Town.HoldSpawnsUntilBuilt and not townExists,
})

if Config.Lighting.Enabled then
	local ok, err = pcall(LightingPreset.Apply, Config.Lighting.Preset)
	if not ok then
		warn("[Sicily] Lighting preset failed: " .. tostring(err))
	end
end

local townInfo = nil
if Config.Town.Enabled then
	local startedAt = os.clock()
	local ok, result = pcall(Town.EnsureBuilt)
	if ok then
		townInfo = result
		print(("[Sicily] %s is ready (%.1fs)."):format(Config.Town.Name, os.clock() - startedAt))
	else
		warn("[Sicily] Town generation failed: " .. tostring(result))
	end
end

releaseSpawns(if townInfo then townInfo.SpawnCFrames else nil)

NPCs.Start(townInfo)

local ok, err = pcall(Horses.Start, townInfo)
if not ok then
	warn("[Sicily] Horses failed to start: " .. tostring(err))
end

ok, err = pcall(Combat.Start, townInfo)
if not ok then
	warn("[Sicily] Combat failed to start: " .. tostring(err))
end
-- horses and townsfolk react to gunfire and to being hit
Combat.OnGunshot(function(position, shooter)
	Horses.OnGunshot(position, shooter)
	NPCs.OnGunshot(position)
end)
Combat.OnHit(function(instance, from)
	Horses.OnHit(instance, from)
end)
