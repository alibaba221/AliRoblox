--[[
	lune run tools/lune/package.luau <installer.rbxm> <demo.rbxl>

	Post-processes the Rojo builds:
	  * installer: disables every script so nothing runs before Install() moves them into place
	  * demo place: Future lighting and golden-hour defaults so it looks right the moment you open it
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local installerPath = process.args[1]
local demoPath = process.args[2]

local models = roblox.deserializeModel(fs.readFile(installerPath))
local disabled = 0
for _, root in models do
	for _, d in root:GetDescendants() do
		if d:IsA("BaseScript") then
			d.Disabled = true
			disabled += 1
		end
	end
end
fs.writeFile(installerPath, roblox.serializeModel(models))
print(("Installer: %d scripts disabled until Install() runs"):format(disabled))

local game = roblox.deserializePlace(fs.readFile(demoPath))
local lighting = game:GetService("Lighting")
lighting.Technology = roblox.Enum.Technology.Future
lighting.ClockTime = 17.35
lighting.GeographicLatitude = 37.5
local players = game:GetService("Players")
players.CharacterAutoLoads = true
fs.writeFile(demoPath, roblox.serializePlace(game))
print("Demo place: Future lighting set")
