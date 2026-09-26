--[[
	Cinematic polish on top of Roblox's default camera (zoom, collision, shift-lock and gamepad/touch
	controls all stay intact):

	  * FOV widens smoothly while running.
	  * Soft follow: the camera trails the body by a fraction of a stud.
	  * Head-bob and sway synced to the actual footsteps (stronger when running, off in first person).
	  * Slight roll when strafing, subtle shake at full sprint, springy dip on hard landings.

	The offset is removed right before the default camera updates and re-applied right after, so
	it never accumulates or fights the camera scripts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local Spring = require(Shared:WaitForChild("Spring"))

local CameraFX = {}

local settings = Config.Camera
local player = Players.LocalPlayer

local appliedOffset: CFrame? = nil
local followSpring = Spring.new(Vector3.zero, settings.FollowFrequency, 1)
local dipSpring = Spring.new(0, 2.6, 0.55)
local roll = 0
local fov = settings.BaseFOV
local lastFov: number? = nil
local lastFocus: Vector3? = nil
local shakeClock = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function removeOffset()
	local camera = Workspace.CurrentCamera
	if appliedOffset and camera then
		camera.CFrame = camera.CFrame * appliedOffset:Inverse()
	end
	appliedOffset = nil
end

function CameraFX.Start(movement, animator)
	if not settings.Enabled then
		return
	end

	movement.OnLanded(function(fallSpeed: number)
		if fallSpeed > 25 then
			dipSpring:Impulse(-math.clamp(fallSpeed / 50, 0.3, 2.2) * settings.LandingDip * 9)
		end
	end)

	RunService:BindToRenderStep("SicilyCameraFX_Remove", Enum.RenderPriority.Camera.Value - 1, removeOffset)

	RunService:BindToRenderStep("SicilyCameraFX_Apply", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or camera.CameraType ~= Enum.CameraType.Custom or not humanoid or not root then
			lastFocus = nil
			return
		end
		if humanoid.Health <= 0 then
			lastFocus = nil
			return
		end

		local state = movement.State
		local gait = animator.GetLocalGait()
		local cameraCFrame = camera.CFrame
		local distance = (cameraCFrame.Position - camera.Focus.Position).Magnitude
		local firstPerson = distance < 1.5
		local runAmount = state.RunAmount or 0

		-- FOV (only while nobody else has changed it, e.g. an aiming script).
		if lastFov == nil or math.abs(camera.FieldOfView - lastFov) < 0.01 then
			local targetFov = settings.BaseFOV + (settings.RunFOV - settings.BaseFOV) * runAmount
			fov = approach(fov, targetFov, settings.FOVResponsiveness, dt)
			camera.FieldOfView = fov
			lastFov = camera.FieldOfView
		end

		-- Soft follow: offset = (smoothed focus - actual focus), clamped and collision-checked.
		local focus = (root :: BasePart).Position
		if lastFocus == nil or (focus - lastFocus).Magnitude > 12 then
			followSpring:Reset(focus)
		end
		lastFocus = focus
		followSpring.Target = focus
		local smoothedFocus = followSpring:Step(dt)
		local lag = smoothedFocus - focus
		local maxLag = if firstPerson then 0 else settings.MaxFollowLag * math.clamp((distance - 1.5) / 6, 0, 1)
		if lag.Magnitude > maxLag then
			lag = if maxLag > 0 then lag.Unit * maxLag else Vector3.zero
		end
		if lag.Magnitude > 0.01 then
			rayParams.FilterDescendantsInstances = { character :: Model }
			local hit = Workspace:Raycast(cameraCFrame.Position, lag, rayParams)
			if hit then
				lag = lag.Unit * math.max(0, hit.Distance - 0.3)
			end
		end

		-- Step-synced bob and sway.
		local grounded = gait.Ground or 1
		local walk = (gait.Walk or 0) * grounded
		local bobAmp = (settings.WalkBob + (settings.RunBob - settings.WalkBob) * (gait.Run or 0)) * walk
		if firstPerson then
			bobAmp *= 0.35
		end
		local phase = gait.Phase or 0
		local bobY = -bobAmp * math.abs(math.sin(phase))
		local bobX = bobAmp * 0.55 * math.sin(phase)

		-- Roll into sideways motion (relative to the camera).
		local velocity = (root :: BasePart).AssemblyLinearVelocity
		local lateral = velocity:Dot(cameraCFrame.RightVector) / math.max(Config.Movement.RunSpeed, 1)
		roll = approach(roll, -math.clamp(lateral, -1, 1) * math.rad(settings.StrafeTilt), 6, dt)

		-- Sprint shake.
		shakeClock += dt
		local shake = settings.RunShake * (gait.Run or 0) * grounded
		local shakeX = math.noise(shakeClock * 7, 0.3) * shake
		local shakeY = math.noise(0.7, shakeClock * 7) * shake

		local dip = dipSpring:Step(dt)

		local localLag = cameraCFrame:VectorToObjectSpace(lag)
		local offset = CFrame.new(localLag + Vector3.new(bobX + shakeX, bobY + shakeY + dip, 0))
			* CFrame.Angles(shakeY * 0.25, shakeX * 0.25, roll + bobX * 0.08)
		camera.CFrame = cameraCFrame * offset
		appliedOffset = offset
	end)
end

return CameraFX
