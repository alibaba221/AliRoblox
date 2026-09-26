--[[
	Premium third-person movement for the local player.

	* Relaxed walk by default, hold Shift (keyboard) / click L3 (gamepad) / tap RUN (mobile) to run.
	* Momentum: input is eased in and out, so starts, stops and direction changes have weight.
	* The body turns smoothly toward where you're going (wider arcs while running) instead of
	  snapping, and faces the camera in shift-lock / first person.
	* Heavy landings slow you down for a moment; a short jump cooldown stops bunny-hopping.
	* Shift-lock is moved from Shift to Ctrl (Shift is Run now).

	Hooks into Roblox's default PlayerModule, so keyboard, gamepad, touch and click-to-move all
	keep working. Other scripts can set these attributes on the Humanoid:
	  SpeedMultiplier (number)  e.g. 0.5 while aiming
	  MovementLocked  (bool)    freezes input (cutscenes, menus)
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))

local Movement = {}

local settings = Config.Movement
local player = Players.LocalPlayer
local userGameSettings = UserSettings():GetService("UserGameSettings")
local HST = Enum.HumanoidStateType
local SPRINT_ACTION = "SicilyRun"

local controls = nil
local inputEnabled = true
local characterConnections = {}

local state = {
	Character = nil :: Model?,
	Humanoid = nil :: Humanoid?,
	Root = nil :: BasePart?,
	Align = nil :: AlignOrientation?,
	Smoothed = Vector3.zero,
	Speed = settings.WalkSpeed,
	RunAmount = 0,
	SprintHeld = false,
	SprintToggle = false,
	Sprinting = false,
	Stamina = settings.Stamina.Max,
	LastSprintAt = 0,
	SlowFactor = 1,
	StillTime = 0,
	Yaw = 0,
	MinVY = 0,
	LastProcess = os.clock(),
	LastHook = 0,
	RawInput = Vector3.zero, -- this frame's unsmoothed move input (world space, camera-relative applied)
	RawInputAt = 0,
}
Movement.State = state

local landedListeners = {}
local sprintListeners = {}

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function cameraYaw(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	local _, yaw = camera.CFrame:ToEulerAnglesYXZ()
	return yaw
end

local function toWorld(moveVector: Vector3, cameraRelative: boolean): Vector3
	local world = if cameraRelative then CFrame.Angles(0, cameraYaw(), 0):VectorToWorldSpace(moveVector) else moveVector
	world = Vector3.new(world.X, 0, world.Z)
	if world.Magnitude > 1 then
		world = world.Unit
	end
	return world
end

local function isLocked(humanoid: Humanoid): boolean
	return not inputEnabled or humanoid:GetAttribute("MovementLocked") == true
end

local function smoothInput(humanoid: Humanoid, moveVector: Vector3, cameraRelative: boolean, dt: number): Vector3
	state.RawInput = toWorld(moveVector, cameraRelative)
	state.RawInputAt = os.clock()
	local input = if isLocked(humanoid) then Vector3.zero else state.RawInput
	local current = state.Smoothed
	local rate = if input.Magnitude >= current.Magnitude then settings.Acceleration else settings.Deceleration
	local smoothed = current:Lerp(input, 1 - math.exp(-rate * dt))
	if input.Magnitude < 1e-3 and smoothed.Magnitude < 0.015 then
		smoothed = Vector3.zero
	end
	state.Smoothed = smoothed
	return smoothed
end

local function setSprinting(sprinting: boolean)
	if state.Sprinting ~= sprinting then
		state.Sprinting = sprinting
		for _, callback in sprintListeners do
			task.spawn(callback, sprinting)
		end
	end
end

local function updateSpeed(humanoid: Humanoid, dt: number)
	local moving = state.Smoothed.Magnitude > 0.3
	if moving then
		state.StillTime = 0
	else
		state.StillTime += dt
		if state.StillTime > 0.35 then
			state.SprintToggle = false -- gamepad/touch run cancels when you stop
		end
	end

	local wantsRun = (state.SprintHeld or state.SprintToggle) and moving and not isLocked(humanoid)
	if wantsRun and settings.RunOnlyForward then
		local forward = CFrame.Angles(0, cameraYaw(), 0).LookVector
		wantsRun = state.Smoothed.Unit:Dot(forward) > 0.3
	end

	local stamina = settings.Stamina
	if stamina.Enabled then
		if state.Sprinting then
			state.Stamina = math.max(0, state.Stamina - stamina.DrainPerSecond * dt)
			state.LastSprintAt = os.clock()
			if state.Stamina <= 0 then
				wantsRun = false
				state.SprintToggle = false
			end
		else
			if os.clock() - state.LastSprintAt > stamina.RegenDelay then
				state.Stamina = math.min(stamina.Max, state.Stamina + stamina.RegenPerSecond * dt)
			end
			if state.Stamina < stamina.MinToStart then
				wantsRun = false
			end
		end
	end
	setSprinting(wantsRun)

	if state.SlowFactor < 1 then
		local recover = (1 - settings.HardLandingSlowdown) / math.max(settings.HardLandingRecovery, 0.05)
		state.SlowFactor = math.min(1, state.SlowFactor + recover * dt)
	end

	local target = if state.Sprinting then settings.RunSpeed else settings.WalkSpeed
	local rate = if target > state.Speed then settings.SprintRampUp else settings.SprintRampDown
	state.Speed = approach(state.Speed, target, rate, dt)
	state.RunAmount = math.clamp((state.Speed - settings.WalkSpeed) / (settings.RunSpeed - settings.WalkSpeed), 0, 1)

	local multiplier = humanoid:GetAttribute("SpeedMultiplier")
	if type(multiplier) ~= "number" then
		multiplier = 1
	end
	humanoid.WalkSpeed = state.Speed * multiplier * state.SlowFactor
end

local function updateFacing(humanoid: Humanoid, root: BasePart)
	local align = state.Align
	if not align or not align.Parent then
		return
	end
	local humanoidState = humanoid:GetState()
	local blocked = humanoid.Sit
		or humanoid.PlatformStand
		or humanoid.Health <= 0
		or root.Anchored
		or humanoidState == HST.Climbing
		or humanoidState == HST.Seated
		or humanoidState == HST.Dead
		or humanoidState == HST.Ragdoll
		or humanoidState == HST.FallingDown
		or humanoidState == HST.Physics
	if blocked then
		align.Enabled = false
		humanoid.AutoRotate = true
		local look = root.CFrame.LookVector
		state.Yaw = math.atan2(-look.X, -look.Z)
		return
	end

	humanoid.AutoRotate = false
	align.Enabled = true
	if userGameSettings.RotationType == Enum.RotationType.CameraRelative then
		state.Yaw = cameraYaw()
		align.Responsiveness = settings.CameraRelativeTurnResponsiveness
	else
		local direction = state.Smoothed
		if direction.Magnitude > 0.08 then
			state.Yaw = math.atan2(-direction.X, -direction.Z)
		end
		align.Responsiveness = settings.TurnResponsiveness
			+ (settings.SprintTurnResponsiveness - settings.TurnResponsiveness) * state.RunAmount
	end
	align.CFrame = CFrame.Angles(0, state.Yaw, 0)
end

-- Called by the ControlModule every frame with the raw input; returns the eased move vector.
local function smoothMove(moveVector: Vector3, cameraRelative: boolean): (Vector3, boolean)
	local humanoid = state.Humanoid
	if not humanoid or not humanoid.Parent or humanoid.Health <= 0 or humanoid.Sit then
		return moveVector, cameraRelative
	end
	local now = os.clock()
	local dt = math.clamp(now - state.LastProcess, 1 / 240, 0.1)
	state.LastProcess = now
	state.LastHook = now
	return smoothInput(humanoid, moveVector, cameraRelative, dt), false
end

-- Runs every frame right after the ControlModule: speed, run state and body facing.
local function postInput(dt: number)
	local humanoid, root = state.Humanoid, state.Root
	if not humanoid or not root or not humanoid.Parent or humanoid.Health <= 0 then
		return
	end
	if os.clock() - (state.LastHook or 0) > 0.25 then
		-- The PlayerModule didn't route input through us (custom controls, vehicles, a newer
		-- PlayerModule...): follow the humanoid's own move direction so facing still works.
		local direction = humanoid.MoveDirection
		state.Smoothed = state.Smoothed:Lerp(Vector3.new(direction.X, 0, direction.Z), 1 - math.exp(-12 * dt))
	end
	if humanoid:GetState() == HST.Freefall then
		state.MinVY = math.min(state.MinVY, root.AssemblyLinearVelocity.Y)
	end
	updateSpeed(humanoid, dt)
	updateFacing(humanoid, root)
end

local function hookControls(): boolean
	local playerScripts = player:WaitForChild("PlayerScripts")
	local moduleScript = playerScripts:WaitForChild("PlayerModule", 30)
	if not moduleScript then
		warn("[Sicily] PlayerModule not found; movement easing disabled (running still works).")
		return false
	end
	local ok, playerModule = pcall(require, moduleScript)
	if not ok or type(playerModule) ~= "table" or type(playerModule.GetControls) ~= "function" then
		warn("[Sicily] Couldn't load PlayerModule controls; movement easing disabled (running still works).")
		return false
	end
	controls = playerModule:GetControls()
	if not controls then
		return false
	end
	if not inputEnabled then
		pcall(function()
			controls:Disable()
		end)
	end

	if type(controls.moveFunction) == "function" then
		local original = controls.moveFunction
		controls.moveFunction = function(p, moveVector, cameraRelative)
			local ok2, vector, relative = pcall(smoothMove, moveVector, cameraRelative)
			if ok2 then
				return original(p, vector, relative)
			end
			return original(p, moveVector, cameraRelative)
		end
	elseif type(controls.GetMoveVector) == "function" then
		-- Forked PlayerModule without moveFunction: re-issue the eased move after it runs.
		RunService:BindToRenderStep("SicilyMovementInput", Enum.RenderPriority.Input.Value + 1, function()
			local humanoid = state.Humanoid
			if humanoid and humanoid.Parent and inputEnabled then
				local vector, relative = smoothMove(controls:GetMoveVector(), true)
				humanoid:Move(vector, relative)
			end
		end)
	end

	-- Shift is Run now: move the shift-lock toggle to Config.Movement.ShiftLockKeys.
	if settings.ShiftLockKeys ~= "" then
		task.spawn(function()
			local cameraModule = moduleScript:WaitForChild("CameraModule", 10)
			local mouseLock = cameraModule and cameraModule:WaitForChild("MouseLockController", 10)
			local boundKeys = mouseLock and mouseLock:WaitForChild("BoundKeys", 10)
			if boundKeys and boundKeys:IsA("StringValue") then
				boundKeys.Value = settings.ShiftLockKeys
			end
		end)
	end
	return true
end

local function updateTouchButton()
	task.spawn(function()
		local button = ContextActionService:GetButton(SPRINT_ACTION)
		if button and button:IsA("ImageButton") then
			button.ImageColor3 = if state.SprintToggle then Color3.fromRGB(255, 205, 120) else Color3.new(1, 1, 1)
		end
	end)
end

local function onSprintAction(_: string, inputState: Enum.UserInputState, inputObject: InputObject)
	if inputObject.UserInputType == Enum.UserInputType.Touch then
		if inputState == Enum.UserInputState.Begin then
			state.SprintToggle = not state.SprintToggle
			updateTouchButton()
		end
		return Enum.ContextActionResult.Sink
	elseif inputObject.KeyCode == settings.GamepadSprintKey then
		if inputState == Enum.UserInputState.Begin then
			state.SprintToggle = not state.SprintToggle
		end
		return Enum.ContextActionResult.Pass
	end
	state.SprintHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Pass
end

local function bindInput()
	local keys = table.clone(settings.SprintKeys)
	table.insert(keys, settings.GamepadSprintKey)
	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		onSprintAction,
		settings.MobileSprintButton,
		Enum.ContextActionPriority.High.Value,
		table.unpack(keys)
	)
	if settings.MobileSprintButton then
		ContextActionService:SetTitle(SPRINT_ACTION, "RUN")
	end
	-- Never get stuck running if Shift is released while typing or alt-tabbed.
	UserInputService.TextBoxFocused:Connect(function()
		state.SprintHeld = false
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		state.SprintHeld = false
	end)
end

local function cleanupCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	if state.Align then
		state.Align:Destroy()
	end
	state.Character, state.Humanoid, state.Root, state.Align = nil, nil, nil, nil
end

local function onCharacterAdded(character: Model)
	cleanupCharacter()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	if player.Character ~= character then
		return
	end

	state.Character, state.Humanoid, state.Root = character, humanoid, root
	state.Smoothed = Vector3.zero
	state.Speed = settings.WalkSpeed
	state.SlowFactor = 1
	state.SprintToggle = false
	state.MinVY = 0
	state.Stamina = settings.Stamina.Max
	setSprinting(false)

	humanoid.WalkSpeed = settings.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = settings.JumpHeight
	local look = root.CFrame.LookVector
	state.Yaw = math.atan2(-look.X, -look.Z)

	local attachment = root:FindFirstChild("SicilyFacingAttachment") or Instance.new("Attachment")
	attachment.Name = "SicilyFacingAttachment"
	attachment.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "SicilyFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment :: Attachment
	align.RigidityEnabled = false
	align.MaxTorque = 1e7
	align.MaxAngularVelocity = 20
	align.Responsiveness = settings.TurnResponsiveness
	align.CFrame = CFrame.Angles(0, state.Yaw, 0)
	align.Parent = root
	state.Align = align
	humanoid.AutoRotate = false

	table.insert(
		characterConnections,
		humanoid.StateChanged:Connect(function(_, new)
			if new == HST.Landed then
				local fallSpeed = -state.MinVY
				state.MinVY = 0
				if fallSpeed > settings.HardLandingSpeed then
					state.SlowFactor = settings.HardLandingSlowdown
				end
				for _, callback in landedListeners do
					task.spawn(callback, fallSpeed)
				end
				if settings.JumpCooldown > 0 then
					humanoid:SetStateEnabled(HST.Jumping, false)
					task.delay(settings.JumpCooldown, function()
						if humanoid.Parent then
							humanoid:SetStateEnabled(HST.Jumping, true)
						end
					end)
				end
			elseif new == HST.Freefall then
				state.MinVY = math.min(0, root.AssemblyLinearVelocity.Y)
			end
		end)
	)
	table.insert(
		characterConnections,
		humanoid.Died:Connect(function()
			if state.Align then
				state.Align.Enabled = false
			end
		end)
	)
end

function Movement.Start()
	if not settings.Enabled then
		return
	end
	task.spawn(hookControls)
	bindInput()
	RunService:BindToRenderStep("SicilyMovement", Enum.RenderPriority.Input.Value + 2, postInput)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function(character)
		if character == state.Character then
			cleanupCharacter()
		end
	end)
end

-- Enables/disables player control (used by the intro camera).
function Movement.SetInputEnabled(enabled: boolean)
	inputEnabled = enabled
	if controls then
		pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
end

-- The player's current move input (world space, magnitude 0..1), e.g. for steering a horse.
-- Falls back to the humanoid's MoveDirection when the PlayerModule hook isn't available.
function Movement.GetMoveInput(): Vector3
	if os.clock() - state.RawInputAt < 0.25 then
		return state.RawInput
	end
	local humanoid = state.Humanoid
	if humanoid then
		local direction = humanoid.MoveDirection
		return Vector3.new(direction.X, 0, direction.Z)
	end
	return Vector3.zero
end

-- Is the Run input (Shift / L3 toggle / RUN button) active?
function Movement.RunHeld(): boolean
	return state.SprintHeld or state.SprintToggle
end

function Movement.OnLanded(callback: (fallSpeed: number) -> ())
	table.insert(landedListeners, callback)
end

function Movement.OnSprintChanged(callback: (sprinting: boolean) -> ())
	table.insert(sprintListeners, callback)
end

return Movement
