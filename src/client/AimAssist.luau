--[[
	Aim assist (client) for gamepads and touch screens; mouse aiming is never touched.

	  * Snap: when you start aiming with someone close to the crosshair, the view eases most of
	    the way onto them.
	  * Tracking: while the crosshair is on or near a target, the view drifts gently with it.

	Targets: other players, townsfolk and the range's bottles and cans, only when in plain view.
	Strengths: Config.Combat.AimAssist, scaled per gun (Weapons: AimAssist).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local R6 = require(Shared:WaitForChild("R6"))

local CameraFX = require(script.Parent.CameraFX)

local AimAssist = {}

local settings = Config.Combat.AimAssist
local TARGET_TAG = "SicilyTarget"
local player = Players.LocalPlayer

local cache = {}
local cacheAt = 0
local snap = { Yaw = 0, Pitch = 0, Left = 0 }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

function AimAssist.Strength(device: string, def): number
	local base = if device == "gamepad" then settings.Gamepad elseif device == "touch" then settings.Touch else settings.Mouse
	return base * (if def then def.AimAssist or 1 else 1)
end

-- Everything worth assisting onto: { Model, Part, Radius } (refreshed a few times a second).
local function candidates()
	local now = os.clock()
	if now - cacheAt < 0.25 then
		return cache
	end
	cacheAt = now
	cache = {}
	for _, model in CollectionService:GetTagged(R6.Tag) do
		if model ~= player.Character and model:IsDescendantOf(Workspace) then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local torso = model:FindFirstChild("Torso")
			if humanoid and humanoid.Health > 0 and torso and torso:IsA("BasePart") then
				table.insert(cache, { Model = model, Part = torso, Radius = 1.1 })
			end
		end
	end
	for _, model in CollectionService:GetTagged(TARGET_TAG) do
		local body = model:FindFirstChild("Body") or (model:IsA("Model") and model.PrimaryPart)
		if body and body:IsA("BasePart") then
			table.insert(cache, { Model = model, Part = body, Radius = 0.35 })
		end
	end
	return cache
end

local function visible(from: Vector3, target, ignore: { Instance }): boolean
	rayParams.FilterDescendantsInstances = ignore
	local offset = target.Part.Position - from
	local hit = Workspace:Raycast(from, offset, rayParams)
	return hit == nil or hit.Instance:IsDescendantOf(target.Model)
end

-- The target nearest the crosshair within `maxAngle` (radians), plus its angle.
local function nearest(camera: Camera, maxAngle: number, ignore: { Instance })
	local cf = camera.CFrame
	local best, bestScore = nil, math.huge
	for _, target in candidates() do
		local offset = target.Part.Position - cf.Position
		local distance = offset.Magnitude
		if distance > 2 and distance < settings.Range then
			local angle = math.acos(math.clamp(cf.LookVector:Dot(offset / distance), -1, 1))
			-- bigger / nearer targets reach further from the crosshair
			local reach = maxAngle + math.atan(target.Radius / distance)
			if angle < reach and angle < bestScore and visible(cf.Position, target, ignore) then
				best, bestScore = target, angle
			end
		end
	end
	return best, bestScore
end

-- Yaw / pitch (radians) that would put the camera on `point`.
local function anglesTo(cf: CFrame, point: Vector3): (number, number)
	local direction = (point - cf.Position).Unit
	local look = cf.LookVector
	local yaw = wrapAngle(yawOf(direction) - yawOf(look))
	local pitch = math.asin(math.clamp(direction.Y, -1, 1)) - math.asin(math.clamp(look.Y, -1, 1))
	return yaw, pitch
end

-- Just started aiming.
function AimAssist.OnAimStart(camera: Camera, strength: number, ignore: { Instance })
	if strength <= 0 then
		return
	end
	local target = nearest(camera, math.rad(settings.SnapAngle) * math.min(strength, 1.5), ignore)
	if target then
		local yaw, pitch = anglesTo(camera.CFrame, target.Part.Position)
		local k = math.clamp(settings.SnapStrength * strength, 0, 0.9)
		snap.Yaw, snap.Pitch, snap.Left = yaw * k, pitch * k, 0.14
	end
end

-- Every frame while aiming (or with a gun out, for the snap to finish).
function AimAssist.Update(dt: number, camera: Camera, strength: number, aiming: boolean, ignore: { Instance })
	if snap.Left > 0 then
		-- ease the snap in over a few frames
		local share = math.min(1, dt / snap.Left)
		CameraFX.Rotate(snap.Yaw * share, snap.Pitch * share)
		snap.Yaw *= 1 - share
		snap.Pitch *= 1 - share
		snap.Left = math.max(0, snap.Left - dt)
	end
	if not aiming or strength <= 0 then
		return
	end
	local target, angle = nearest(camera, math.rad(2.2) * strength, ignore)
	if target and angle > math.rad(0.15) then
		local yaw, pitch = anglesTo(camera.CFrame, target.Part.Position)
		local k = math.min(1, settings.Friction * strength * 4 * dt)
		CameraFX.Rotate(yaw * k, pitch * k)
	end
end

function AimAssist.Cancel()
	snap.Left = 0
end

return AimAssist
