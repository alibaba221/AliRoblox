--[[
	Riding (client): everything the rider's own client does while on a horse. The server gives
	this client physics ownership of the horse, so steering responds instantly.

	Controls (camera-relative, like Breath of the Wild / Red Dead):
	  W / stick            trot where the camera looks (a light stick push walks)
	  Shift / L3 / RUN     gallop (costs stamina; a fresh press spurs a short burst)
	  Alt                  walk
	  S / stick back       pull up; from a standstill, back up
	  Space / A / JUMP     jump
	  E / Y / DISMOUNT     get off (at speed you leap off); while taming: calm the horse
	  H / D-pad up         whistle for your horse (works on foot)

	While aiming from the saddle the horse keeps its pace and A/D steer it (see Gunplay).
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local HorseMotor = require(Shared:WaitForChild("HorseMotor"))
local HorseMount = require(Shared:WaitForChild("HorseMount"))
local HorseRig = require(Shared:WaitForChild("HorseRig"))
local HorseTypes = require(Shared:WaitForChild("HorseTypes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Taming = require(Shared:WaitForChild("Taming"))

local CameraFX = require(script.Parent.CameraFX)
local HorseAnimator = require(script.Parent.HorseAnimator)
local RideHud = require(script.Parent.RideHud)

local Riding = {}

local settings = Config.Horses
local player = Players.LocalPlayer
local ACTION = "SicilyHorseAction"
local WALK = "SicilyHorseWalk"
local CALL = "SicilyHorseCall"

local movement = nil
local hud = nil
local horseRequest = nil

local state = {
	Horse = nil :: Model?,
	Root = nil :: BasePart?,
	Joint = nil :: Motor6D?,
	Motor = nil :: any,
	Taming = false,
	Timeline = nil :: any,
	TameStart = 0,
	Predicted = 0,
	RunLatch = false,
	WalkHeld = false,
	Aiming = false,
	CruiseGait = 2,
	LastForwardInput = 0,
	DismountSent = false,
	Thrown = false,
	HiddenPrompts = {},
	Connections = {},
}
Riding.State = state

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function yawDirection(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function Riding.IsRiding(): boolean
	return state.Horse ~= nil
end

function Riding.GetHorse(): Model?
	return state.Horse
end

-- Hands busy with the horse: climbing on or off, or hanging on while taming (no guns).
function Riding.IsBusy(): boolean
	if not state.Horse then
		return false
	end
	if state.Taming or state.DismountSent then
		return true
	end
	local joint = state.Joint
	if not joint then
		return false
	end
	local mountStart = joint:GetAttribute("MountStart")
	if type(mountStart) == "number" and serverNow() - mountStart < HorseMount.MountTime then
		return true
	end
	return joint:GetAttribute("DismountStart") ~= nil
end

-- Gunplay tells us when the rider aims: the horse keeps its pace and A/D steer it.
function Riding.SetAiming(aiming: boolean)
	if aiming and not state.Aiming and state.Motor then
		state.CruiseGait = state.Motor.Gait
	end
	state.Aiming = aiming
end

local function actionKeyLabel(): string
	local device = if hud then hud.Device() else "keyboard"
	if device == "gamepad" then
		return "Y"
	elseif device == "touch" then
		return "TAP"
	end
	return "E"
end

local function setHints()
	if not hud then
		return
	end
	if not state.Horse then
		hud.SetContext("Riding", 0, nil)
		return
	end
	if state.Taming then
		hud.SetContext("Riding", 10, {
			{ Keys = { Keyboard = "E", Gamepad = "Y" }, Action = "Calm the horse (press fast)" },
		})
		return
	end
	hud.SetContext("Riding", 10, {
		{ Keys = { Keyboard = "W", Gamepad = "L-STICK" }, Action = "Ride" },
		{ Keys = { Keyboard = "SHIFT", Gamepad = "L3" }, Action = "Gallop" },
		{ Keys = { Keyboard = "ALT" }, Action = "Walk" },
		{ Keys = { Keyboard = "SPACE", Gamepad = "A" }, Action = "Jump" },
		{ Keys = { Keyboard = "E", Gamepad = "Y" }, Action = "Dismount" },
	})
end

local function hidePrompts(hide: boolean)
	if hide then
		for _, horse in CollectionService:GetTagged(HorseRig.Tag) do
			for _, prompt in horse:GetDescendants() do
				if prompt:IsA("ProximityPrompt") and prompt.Enabled then
					prompt.Enabled = false
					state.HiddenPrompts[prompt] = true
				end
			end
		end
	else
		for prompt in state.HiddenPrompts do
			if prompt.Parent then
				local horse = prompt:FindFirstAncestorOfClass("Model")
				prompt.Enabled = horse == nil or horse:GetAttribute("Rider") == nil
			end
		end
		table.clear(state.HiddenPrompts)
	end
end

local BODY_PARTS = {
	HumanoidRootPart = true,
	Torso = true,
	Head = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}

-- Undo the riding physics on our own character right away (the server does it too, a moment later).
local function restoreLocalPhysics(character: Model?)
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			if d.CollisionGroup == HorseMount.RiderGroup then
				d.CollisionGroup = "Default"
			end
			if BODY_PARTS[d.Name] and d.Parent == character then
				d.Massless = false
			end
		end
	end
end

local function cleanup()
	local horse = state.Horse
	if horse then
		HorseAnimator.SetOverride(horse, nil)
	end
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	table.clear(state.Connections)
	state.Horse, state.Root, state.Joint, state.Motor = nil, nil, nil, nil
	state.Taming = false
	state.Timeline = nil
	state.DismountSent = false
	state.Aiming = false
	CameraFX.SetRide(nil)
	hidePrompts(false)
	ContextActionService:UnbindAction(ACTION)
	ContextActionService:UnbindAction(WALK)
	RunService:UnbindFromRenderStep("SicilyRiding")
	RideHud.SetVisible(false)
	RideHud.SetTaming(false)
	setHints()
end

-- Commands --------------------------------------------------------------------------------------
local function steerCommand()
	local motor = state.Motor
	local input = movement.GetMoveInput()
	if input.Magnitude < 0.12 then
		return { Gait = 0 }
	end
	local direction = input.Unit
	local forward = yawDirection(motor.Heading)
	if forward:Dot(direction) < -0.72 then
		-- pulling back: brake, and from a standstill back up
		if motor.Speed > 4 then
			return { Gait = 0, Brake = true }
		end
		return { Back = true }
	end
	local gait
	if movement.RunHeld() then
		gait = 4
	elseif state.WalkHeld or input.Magnitude < 0.55 then
		gait = 1
	else
		gait = 2
	end
	return { Direction = direction, Gait = gait }
end

-- Aiming from the saddle: keep the pace, W speeds up, S slows, A/D steer relative to the horse.
local function aimCommand()
	local camera = Workspace.CurrentCamera
	local input = movement.GetMoveInput()
	local look = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
	local x, z = input:Dot(right), input:Dot(flatLook)
	local now = os.clock()
	if z > 0.5 and now - state.LastForwardInput > 0.35 then
		state.CruiseGait = math.max(state.CruiseGait, 2)
	end
	if z > 0.5 then
		state.LastForwardInput = now
	end
	local gait = state.CruiseGait
	if movement.RunHeld() then
		gait = 4
	end
	if z < -0.5 then
		state.CruiseGait = 0
		gait = 0
	end
	return { Turn = -x, Gait = gait, Brake = z < -0.5 and state.Motor.Speed > 6 }
end

local function tamingCommand()
	local motor = state.Motor
	local elapsed = serverNow() - state.TameStart
	local sample = Taming.Sample(state.Timeline, elapsed)
	local command = { Gait = 0 }
	if math.abs(sample.Spin) > 0.05 then
		command.Turn = math.clamp(sample.Spin, -1, 1)
		command.TurnScale = 1.9
	end
	if sample.Lunge > 0.15 then
		command.Gait = 2
		command.Direction = yawDirection(motor.Heading)
	end
	return command, sample
end

-- Per frame ---------------------------------------------------------------------------------------
local function update(dt: number)
	local horse, joint, motor = state.Horse, state.Joint, state.Motor
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not horse or not horse.Parent or not joint or not joint.Parent or not motor or not humanoid then
		return
	end
	local now = serverNow()
	local mountStart = joint:GetAttribute("MountStart")
	local mounting = type(mountStart) == "number" and now - mountStart < HorseMount.MountTime
	local dismounting = joint:GetAttribute("DismountStart") ~= nil or state.DismountSent

	local command, tameSample = nil, nil
	if mounting or dismounting then
		command = { Gait = 0, Brake = motor.Speed > 3 }
	elseif state.Taming then
		command, tameSample = tamingCommand()
	elseif state.Aiming then
		command = aimCommand()
	else
		command = steerCommand()
	end
	if not (mounting or dismounting or state.Taming) then
		command.Jump = humanoid.Jump
		local run = movement.RunHeld()
		command.Spur = run and not state.RunLatch
		state.RunLatch = run
	end
	motor:Update(dt, command)

	-- a hard stop at speed sits the horse back on its haunches
	HorseAnimator.SetOverride(horse, if command.Brake and motor.Speed > 12 then { Rear = 0.18 } else nil)

	-- HUD
	local t = motor.Temperament
	RideHud.SetStamina(motor.Stamina / t.Stamina, motor.Winded > 0, os.clock())
	if state.Taming then
		local server = horse:GetAttribute("TameProgress")
		if type(server) == "number" then
			-- trust our prediction for a moment after each press, then follow the server
			state.Predicted += (server - state.Predicted) * math.min(1, dt * 3)
		end
		RideHud.SetTaming(true, state.Predicted, tameSample and tameSample.Intensity or 0, actionKeyLabel(), os.clock())
		if tameSample and tameSample.Intensity > 0.6 then
			CameraFX.Shake(0.12 * tameSample.Intensity, 6)
		end
	else
		RideHud.SetTaming(false)
	end
end

-- Actions ------------------------------------------------------------------------------------------
local function leapOff()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local horseRoot = state.Root
	horseRequest:FireServer("Dismount", "Leap")
	if not humanoid or not root or not root:IsA("BasePart") or not horseRoot then
		return
	end
	local joint = state.Joint
	if joint then
		joint.Enabled = false
	end
	restoreLocalPhysics(character)
	humanoid.PlatformStand = false
	local left = -horseRoot.CFrame.RightVector
	root.CFrame = root.CFrame + left * 1.6 + Vector3.new(0, 0.6, 0)
	root.AssemblyLinearVelocity = horseRoot.AssemblyLinearVelocity * 0.75 + left * 12 + Vector3.new(0, 24, 0)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	cleanup()
end

local function onAction(_: string, inputState: Enum.UserInputState, _input: InputObject)
	if inputState ~= Enum.UserInputState.Begin or not state.Horse then
		return Enum.ContextActionResult.Pass
	end
	if state.Taming then
		horseRequest:FireServer("Calm")
		local temperament = HorseTypes.GetTemperament(state.Horse:GetAttribute("Temperament"))
		state.Predicted = math.min(1, Taming.Press(state.Predicted, temperament))
		RideHud.Pulse()
		return Enum.ContextActionResult.Sink
	end
	local joint = state.Joint
	local mountStart = joint and joint:GetAttribute("MountStart")
	if type(mountStart) == "number" and serverNow() - mountStart < HorseMount.MountTime + 0.3 then
		return Enum.ContextActionResult.Sink -- still climbing on (don't hop straight back off)
	end
	if state.DismountSent then
		return Enum.ContextActionResult.Sink
	end
	if state.Motor and state.Motor.Speed > 18 then
		leapOff()
	else
		state.DismountSent = true
		horseRequest:FireServer("Dismount")
	end
	return Enum.ContextActionResult.Sink
end

local function onWalk(_: string, inputState: Enum.UserInputState)
	state.WalkHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Pass
end

local function onCall(_: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin and not state.Horse then
		horseRequest:FireServer("Call")
	end
	return Enum.ContextActionResult.Pass
end

-- Mount / unmount ------------------------------------------------------------------------------
local function onMounted(joint: Motor6D)
	local horseRoot = joint.Part0
	local horse = horseRoot and horseRoot.Parent
	if not horseRoot or not horse or not horse:IsA("Model") then
		return
	end
	cleanup()
	state.Horse = horse
	state.Root = horseRoot :: BasePart
	state.Joint = joint
	local temperament = HorseTypes.GetTemperament(horse:GetAttribute("Temperament"))
	local motor = HorseMotor.new(horse, temperament)
	motor:Sync()
	state.Motor = motor
	local horseHumanoid = horse:FindFirstChildOfClass("Humanoid")
	if horseHumanoid then
		HorseMotor.ConfigureHumanoid(horseHumanoid)
	end

	local function refreshTaming()
		local taming = horse:GetAttribute("Mode") == "Taming"
		local seed = horse:GetAttribute("TameSeed")
		local start = horse:GetAttribute("TameStart")
		if taming and type(seed) == "number" and type(start) == "number" then
			state.Taming = true
			state.Timeline = Taming.Timeline(seed, temperament)
			state.TameStart = start
			local progress = horse:GetAttribute("TameProgress")
			state.Predicted = if type(progress) == "number" then progress else temperament.Taming.StartProgress
		else
			state.Taming = false
		end
		setHints()
	end
	refreshTaming()
	table.insert(state.Connections, horse:GetAttributeChangedSignal("Mode"):Connect(refreshTaming))
	table.insert(state.Connections, horse:GetAttributeChangedSignal("TameSeed"):Connect(refreshTaming))

	CameraFX.SetRide(horse)
	hidePrompts(true)
	ContextActionService:BindActionAtPriority(ACTION, onAction, true, Enum.ContextActionPriority.High.Value, settings.MountKey, settings.MountGamepadKey)
	ContextActionService:SetTitle(ACTION, "RIDE")
	ContextActionService:BindActionAtPriority(WALK, onWalk, false, Enum.ContextActionPriority.High.Value, table.unpack(settings.WalkKeys))
	RunService:BindToRenderStep("SicilyRiding", Enum.RenderPriority.Input.Value + 3, function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			warn("[Sicily] Riding update failed: " .. tostring(err))
		end
	end)
	RideHud.SetVisible(true)
	setHints()
	task.defer(function()
		-- the touch button reads CALM while taming, DISMOUNT otherwise
		ContextActionService:SetTitle(ACTION, if state.Taming then "CALM" else "DISMOUNT")
	end)
end

local function onUnmounted(joint: Instance)
	if joint ~= state.Joint then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	restoreLocalPhysics(character)
	if humanoid and humanoid.Health > 0 and humanoid.PlatformStand and not state.Thrown then
		humanoid.PlatformStand = false
	end
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
	end
	cleanup()
end

local function watchCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	root.ChildAdded:Connect(function(child)
		if child.Name == HorseMount.JointName and child:IsA("Motor6D") then
			-- wait for Part0 to replicate
			for _ = 1, 30 do
				if child.Part0 then
					break
				end
				task.wait()
			end
			if child.Parent then
				onMounted(child)
			end
		end
	end)
	root.ChildRemoved:Connect(onUnmounted)
	local existing = root:FindFirstChild(HorseMount.JointName)
	if existing and existing:IsA("Motor6D") then
		onMounted(existing)
	end
end

local function thrown(direction: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	state.Thrown = true
	restoreLocalPhysics(character)
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = direction * 30
	root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-4, 4), math.random(-6, 6))
	CameraFX.Shake(0.5, 3)
	task.delay(1.1, function()
		state.Thrown = false
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function onHorseEvent(kind: string, ...)
	local args = { ... }
	if kind == "Tamed" then
		hud.Toast("Tamed! This horse is yours now.  Whistle for it with H.", 4, Color3.fromRGB(250, 222, 140))
		if state.Horse then
			state.Taming = false
			setHints()
			ContextActionService:SetTitle(ACTION, "DISMOUNT")
		end
	elseif kind == "Thrown" then
		local direction = args[2]
		hud.Toast("The horse threw you off! Give it a moment, then try again.", 3.5)
		if typeof(direction) == "Vector3" then
			thrown(direction)
		end
	elseif kind == "Startled" then
		-- a tamed horse just flinches at gunfire; a half-wild one breaks stride
		local horse = state.Horse
		local tame = horse ~= nil and horse:GetAttribute("Wild") ~= true and not state.Taming
		CameraFX.Shake(if tame then 0.07 else 0.18, 6)
		if state.Motor and state.Motor.Speed > 4 then
			state.Motor.Speed *= if tame then 0.97 else 0.85
		end
	elseif kind == "NotYours" then
		hud.Toast(("That's %s's horse."):format(tostring(args[1])), 2.5)
	elseif kind == "Spooked" then
		hud.Toast("It's still skittish. Give it a moment.", 2.5)
	elseif kind == "Called" then
		hud.Toast("You whistle for your horse.", 2)
	elseif kind == "CallFailed" then
		local reason = args[1]
		hud.Toast(if reason == "NoHorse" then "You don't have a horse yet. Tame a wild one!"
			elseif reason == "TooFar" then "Your horse is too far away to hear you."
			else "Your horse is busy.", 2.8)
	end
end

function Riding.Start(movementModule, hudModule)
	if not settings.Enabled then
		return
	end
	movement = movementModule
	hud = hudModule
	horseRequest = Remotes.Get("HorseRequest")
	RideHud.Build(hud.GetGui())
	Remotes.Get("HorseEvent").OnClientEvent:Connect(function(kind, ...)
		local ok, err = pcall(onHorseEvent, kind, ...)
		if not ok then
			warn("[Sicily] Horse event failed: " .. tostring(err))
		end
	end)
	ContextActionService:BindAction(CALL, onCall, false, settings.CallKey, settings.CallGamepadKey)
	UserInputService.WindowFocusReleased:Connect(function()
		state.WalkHeld = false
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(function()
		cleanup()
	end)
end

return Riding
