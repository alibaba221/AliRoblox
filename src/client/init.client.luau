--[[
	SicilyClient — premium movement, cinematic camera, procedural R6 animation, character sounds,
	HUD and the opening flyover. All settings: ReplicatedStorage.SicilyShared.Config
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("SicilyShared"):WaitForChild("Config"))

local Animator = require(script.Animator)
local CameraFX = require(script.CameraFX)
local Hud = require(script.Hud)
local Intro = require(script.Intro)
local Movement = require(script.Movement)
local Sounds = require(script.Sounds)

local function start(name: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[Sicily] %s failed to start: %s"):format(name, tostring(err)))
	end
end

start("Animator", Animator.Start)
start("Movement", Movement.Start)
start("Hud", Hud.Start, Movement)
start("CameraFX", CameraFX.Start, Movement, Animator)
start("Sounds", Sounds.Start, Animator)

if Config.Intro.Enabled then
	task.spawn(Intro.Play, Movement, Hud)
else
	Hud.GetGui():SetAttribute("IntroDone", true)
	Hud.ShowHint()
end
