--[[
	Cinematic polish on top of Roblox's default camera (zoom, collision, shift-lock and gamepad/touch
	controls all stay intact):

	  * FOV widens smoothly while running (and galloping).
	  * Soft follow: the camera trails the body by a fraction of a stud.
	  * Head-bob and sway synced to the actual footsteps (stronger when running, off in first person).
	  * Slight roll when strafing, subtle shake at full sprint, springy dip on hard landings.
	  * Riding: pulled back to frame the horse, and it swings in behind the horse when you stop
	    steering the camera.
	  * Aiming: over-the-shoulder view with a narrower FOV (weapons set this every frame).
	  * Recoil kick, impact/bucking shake, and gentle rotation (aim assist) for other modules.

	Visual offsets are removed right before the default camera updates and re-applied right after,
	so they never accumulate or fight the camera scripts. Deliberate rotations (auto-follow, aim
	assist) are applied before the camera updates, so the camera keeps them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local Spring = require(Shared:WaitForChild("Spring"))

local CameraFX = {}

local settings = Config.Camera
local rideSettings = Config.Horses
local player = Players.LocalPlayer

local appliedOffset: CFrame? = nil
local followSpring = Spring.new(Vector3.zero, settings.FollowFrequency, 1)
local dipSpring = Spring.new(0, 2.6, 0.55)
local kickSpring = Spring.new(Vector3.zero, 5.5, 0.62) -- recoil (pitch, yaw, roll) in radians
local roll = 0
local fov = settings.BaseFOV
local lastFov: number? = nil
local lastFocus: Vector3? = nil
local shakeClock = 0
local shakeAmount = 0
local shakeDecay = 4

local pendingYaw, pendingPitch = 0, 0
local yawBeforeModule: number? = nil
local lastUserRotate = 0

-- State other modules drive every frame.
local ride = { Active = false, Horse = nil :: Model?, Blend = 0 }
local aim = {
	Target = 0,
	Alpha = 0,
	Shoulder = Vector3.new(1.9, 0.35, 0),
	Distance = 6.5,
	FOV = 55,
	Mounted = false,
}
local mouseLocked = false
local fovOverride: number? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function removeOffset()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if appliedOffset then
		camera.CFrame = camera.CFrame * appliedOffset:Inverse()
	end
	appliedOffset = nil
	-- deliberate rotations (auto-follow, aim assist) go in before the camera module reads them
	if pendingYaw ~= 0 or pendingPitch ~= 0 then
		local cf = camera.CFrame
		local look = cf.LookVector
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		local newPitch = math.clamp(pitch + pendingPitch, -1.35, 1.35)
		local yaw = yawOf(look) + pendingYaw
		camera.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(newPitch, yaw, 0)
		pendingYaw, pendingPitch = 0, 0
	end
	yawBeforeModule = yawOf(camera.CFrame.LookVector)
end

-- Rotate the camera by these angles (radians) next frame; the rotation sticks.
function CameraFX.Rotate(yaw: number, pitch: number?)
	pendingYaw += yaw
	pendingPitch += pitch or 0
end

-- Recoil: kick the view (radians); it springs back by itself.
function CameraFX.Kick(pitch: number, yaw: number, rollAmount: number?)
	kickSpring:Impulse(Vector3.new(pitch, yaw, rollAmount or 0) * 22)
end

-- Short shake (bucking horse, nearby impacts, being hit). amount in studs.
function CameraFX.Shake(amount: number, decay: number?)
	shakeAmount = math.max(shakeAmount, amount)
	shakeDecay = decay or 4
end

-- Riding mode: pulls the camera back and follows the horse.
function CameraFX.SetRide(horse: Model?)
	ride.Active = horse ~= nil
	ride.Horse = horse
end

--[[
	Aiming: alpha 0..1 target (the camera eases in and out), shoulder offset (studs, camera space),
	distance behind the head, FOV. Call every frame while a weapon is out; pass 0 to release.
]]
function CameraFX.SetAim(alpha: number, options: { [string]: any }?)
	aim.Target = alpha
	if options then
		aim.Shoulder = options.Shoulder or aim.Shoulder
		aim.Distance = options.Distance or aim.Distance
		aim.FOV = options.FOV or aim.FOV
		aim.Mounted = options.Mounted == true
	end
end

function CameraFX.GetAimAlpha(): number
	return aim.Alpha
end

-- Lock the mouse to the centre of the screen (weapon drawn) and hide the cursor.
function CameraFX.SetMouseLocked(locked: boolean)
	if mouseLocked and not locked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	mouseLocked = locked
end

-- Temporary FOV override (e.g. Dead Eye); nil clears it.
function CameraFX.SetFOVOverride(value: number?)
	fovOverride = value
end

-- Seconds since the player last turned the camera themselves.
function CameraFX.TimeSinceUserRotate(): number
	return os.clock() - lastUserRotate
end

local function horseSpeed(): (number, Vector3?)
	local horse = ride.Horse
	local root = horse and horse.PrimaryPart
	if not root then
		return 0, nil
	end
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude, root.CFrame.LookVector
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
		local now = os.clock()

		-- Did the player turn the camera this frame? (auto-follow waits for them)
		if yawBeforeModule then
			local turned = wrapAngle(yawOf(camera.CFrame.LookVector) - yawBeforeModule)
			if math.abs(turned) > 0.0015 then
				lastUserRotate = now
			end
		end

		local state = movement.State
		local gait = animator.GetLocalGait()
		local cameraCFrame = camera.CFrame
		local focusPoint = camera.Focus.Position
		local distance = (cameraCFrame.Position - focusPoint).Magnitude
		local firstPerson = distance < 1.5
		local runAmount = state.RunAmount or 0

		ride.Blend = approach(ride.Blend, if ride.Active then 1 else 0, 3, dt)
		aim.Alpha = approach(aim.Alpha, aim.Target, if aim.Target > aim.Alpha then 11 else 8, dt)
		local speed, horseLook = horseSpeed()
		local gallop = if ride.Active then math.clamp((speed - 20) / 12, 0, 1) else 0

		-- FOV (only while nobody else has changed it).
		if lastFov == nil or math.abs(camera.FieldOfView - lastFov) < 0.01 then
			local targetFov = settings.BaseFOV + (settings.RunFOV - settings.BaseFOV) * runAmount * (1 - ride.Blend)
			targetFov += (rideSettings.GallopFOV - settings.BaseFOV) * gallop * ride.Blend
			targetFov = targetFov + (aim.FOV - targetFov) * aim.Alpha
			if fovOverride then
				targetFov = fovOverride
			end
			fov = approach(fov, targetFov, if aim.Target > 0 then 9 else settings.FOVResponsiveness, dt)
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
		maxLag *= 1 - aim.Alpha * 0.8
		if lag.Magnitude > maxLag then
			lag = if maxLag > 0 then lag.Unit * maxLag else Vector3.zero
		end
		rayParams.FilterDescendantsInstances = { character :: Model, ride.Horse :: any }
		if lag.Magnitude > 0.01 then
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
		bobAmp *= 1 - aim.Alpha * 0.7
		local phase = gait.Phase or 0
		local bobY = -bobAmp * math.abs(math.sin(phase))
		local bobX = bobAmp * 0.55 * math.sin(phase)

		-- Roll into sideways motion (relative to the camera).
		local velocity = (root :: BasePart).AssemblyLinearVelocity
		local lateral = velocity:Dot(cameraCFrame.RightVector) / math.max(Config.Movement.RunSpeed, 1)
		roll = approach(roll, -math.clamp(lateral, -1, 1) * math.rad(settings.StrafeTilt) * (1 - ride.Blend), 6, dt)

		-- Sprint / gallop shake plus impulses.
		shakeClock += dt
		shakeAmount = approach(shakeAmount, 0, shakeDecay, dt)
		local shake = settings.RunShake * (gait.Run or 0) * grounded + 0.03 * gallop * ride.Blend + shakeAmount
		local shakeX = math.noise(shakeClock * 7, 0.3) * shake
		local shakeY = math.noise(0.7, shakeClock * 7) * shake

		local dip = dipSpring:Step(dt)
		local kick = kickSpring:Step(dt)

		-- Positional offset in camera space.
		local localLag = cameraCFrame:VectorToObjectSpace(lag)
		local offsetPosition = localLag + Vector3.new(bobX + shakeX, bobY + shakeY + dip, 0)
		if not firstPerson then
			-- riding: pull back so the horse is in frame
			local extra = rideSettings.CameraExtraDistance * ride.Blend * (1 - aim.Alpha)
			-- aiming: over the shoulder, closer in
			local aimOffset = Vector3.zero
			if aim.Alpha > 0.001 then
				aimOffset = Vector3.new(aim.Shoulder.X, aim.Shoulder.Y, aim.Distance - distance) * aim.Alpha
			end
			local wanted = Vector3.new(0, 0, extra) + aimOffset
			if wanted.Magnitude > 0.01 then
				-- keep the camera out of walls: the head must see where the camera wants to be
				local desired = cameraCFrame.Position + cameraCFrame:VectorToWorldSpace(wanted)
				local toCamera = desired - focusPoint
				local hit = Workspace:Raycast(focusPoint, toCamera, rayParams)
				if hit then
					desired = focusPoint + toCamera.Unit * math.max(0.4, hit.Distance - 0.45)
				end
				offsetPosition += cameraCFrame:VectorToObjectSpace(desired - cameraCFrame.Position)
			end
		end
		local offset = CFrame.new(offsetPosition)
			* CFrame.Angles(shakeY * 0.25 + kick.X, shakeX * 0.25 + kick.Y, roll + bobX * 0.08 + kick.Z)
		camera.CFrame = cameraCFrame * offset
		appliedOffset = offset

		-- Riding: swing in behind the horse once the player stops turning the camera.
		if ride.Active and rideSettings.AutoFollow and horseLook and speed > 5 and aim.Target <= 0 then
			if now - lastUserRotate > rideSettings.AutoFollowDelay then
				local delta = wrapAngle(yawOf(horseLook) - yawOf(cameraCFrame.LookVector))
				local rate = rideSettings.AutoFollowSpeed * math.clamp(speed / 20, 0.4, 1.2)
				CameraFX.Rotate(delta * math.min(1, rate * dt))
			end
		end

		if mouseLocked then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
	end)
end

return CameraFX
