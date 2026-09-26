--[[
	Dead Eye (client): press F / R3 / DEAD EYE with a gun out.

	  * The world drains to sepia, sound turns hollow, your heart thumps, your aim steadies and
	    you move slower.
	  * Tap fire on people or bottles to paint marks (up to the rounds in your gun).
	  * Let go of aim (or press Dead Eye again) and you fire at every mark in turn, the view
	    snapping from one to the next.
	  * With nothing painted, shots go exactly where the crosshair is.

	The meter drains while Dead Eye is on and refills slowly (faster with every hit). The server
	keeps the real meter (player attribute "DeadEye") and allows the quick marked shots.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))

local CameraFX = require(script.Parent.CameraFX)
local Fx = require(script.Parent.Fx)

local DeadEye = {}

local settings = Config.Combat.DeadEye
local sounds = Config.Combat.Sounds
local player = Players.LocalPlayer
local TARGET_TAG = "SicilyTarget"
local THUD = "rbxasset://sounds/action_jump_land.mp3"
local CLICK = "rbxasset://sounds/volume_slider.ogg"
local WHOOSH = "rbxasset://sounds/impact_explosion_03.mp3"
local SEPIA = Color3.fromRGB(255, 222, 176)

local callbacks = nil -- { Request(active), Fire(point) -> boolean, Rounds() -> number, Toast(text) }
local state = {
	Active = false,
	Executing = false,
	Confirmed = false,
	StartedAt = 0,
	Meter = 0,
	Marks = {},
	NextShot = 0,
	NextBeat = 0,
	ReleasedAt = nil :: number?,
	Reverb = nil :: Enum.ReverbType?,
	Loop = nil :: Sound?,
}

local grade: ColorCorrectionEffect
local vignette: Frame?

local function tween(instance: Instance, time: number, goal)
	TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), goal):Play()
end

local function buildVisuals(gui: ScreenGui)
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SicilyDeadEye"
	grade.Enabled = false
	grade.TintColor = Color3.new(1, 1, 1)
	grade.Parent = Lighting

	local holder = Instance.new("Frame")
	holder.Name = "DeadEyeVignette"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Visible = false
	holder.ZIndex = 0
	holder.Parent = gui
	local edges = {
		{ UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.7), -90 },
		{ UDim2.fromScale(0.22, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.22, 1), UDim2.fromScale(0.78, 0), 180 },
	}
	for i, edge in edges do
		local f = Instance.new("Frame")
		f.Name = "Edge" .. i
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(70, 42, 18)
		f.BackgroundTransparency = 1
		f.Size = edge[1]
		f.Position = edge[2]
		f.Parent = holder
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge[3]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = f
	end
	vignette = holder
end

local function setVisuals(on: boolean)
	local time = if on then 0.25 else 0.45
	if on then
		grade.Enabled = true
	end
	tween(grade, time, {
		TintColor = if on then SEPIA else Color3.new(1, 1, 1),
		Saturation = if on then -0.55 else 0,
		Contrast = if on then 0.18 else 0,
		Brightness = if on then -0.03 else 0,
	})
	if not on then
		task.delay(time + 0.05, function()
			if not state.Active then
				grade.Enabled = false
			end
		end)
	end
	if vignette then
		vignette.Visible = true
		for _, edge in vignette:GetChildren() do
			if edge:IsA("Frame") then
				tween(edge, time, { BackgroundTransparency = if on then 0.15 else 1 })
			end
		end
	end
	-- sound turns hollow
	if on then
		state.Reverb = SoundService.AmbientReverb
		SoundService.AmbientReverb = Enum.ReverbType.ConcertHall
	elseif state.Reverb then
		SoundService.AmbientReverb = state.Reverb
		state.Reverb = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		Fx.Sound(WHOOSH, camera, { Volume = 0.25, Pitch = if on then 0.32 else 0.42, StopAfter = 0.9 })
	end
	if on and sounds.DeadEyeLoop ~= "" then
		local loop = Instance.new("Sound")
		loop.SoundId = sounds.DeadEyeLoop
		loop.Looped = true
		loop.Volume = 0.4
		loop.Parent = SoundService
		loop:Play()
		state.Loop = loop
	elseif not on and state.Loop then
		state.Loop:Destroy()
		state.Loop = nil
	end
end

local function clearMarks()
	for _, mark in state.Marks do
		mark.Attachment:Destroy()
	end
	table.clear(state.Marks)
end

local function finish()
	if not state.Active then
		return
	end
	state.Active = false
	state.Executing = false
	state.ReleasedAt = nil
	clearMarks()
	setVisuals(false)
	if callbacks then
		callbacks.Request(false)
	end
end

local function execute()
	if #state.Marks == 0 then
		finish()
		return
	end
	state.Executing = true
	state.NextShot = os.clock() + 0.06
end

local function markTarget(instance: Instance): Instance?
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health > 0 and model ~= player.Character and not model:FindFirstAncestor("SicilyHorses") then
				return model
			end
			return nil
		end
		if model:HasTag(TARGET_TAG) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function DeadEye.Start(gui: ScreenGui, hooks)
	callbacks = hooks
	buildVisuals(gui)
end

function DeadEye.Active(): boolean
	return state.Active
end

function DeadEye.Executing(): boolean
	return state.Executing
end

-- The meter to show: our running prediction while active, the server's value otherwise.
function DeadEye.Meter(): number
	if state.Active then
		return state.Meter
	end
	local meter = player:GetAttribute("DeadEye")
	return if type(meter) == "number" then meter else 0
end

-- The Dead Eye key. `ready`: a gun is out. Returns true when the key was used.
function DeadEye.Toggle(ready: boolean): boolean
	if state.Active then
		if not state.Executing then
			execute()
		end
		return true
	end
	if not settings.Enabled or not ready then
		return false
	end
	local meter = player:GetAttribute("DeadEye")
	if type(meter) ~= "number" or meter < settings.Cost then
		if callbacks then
			callbacks.Toast("Dead Eye isn't ready yet.")
		end
		return true
	end
	state.Active = true
	state.Executing = false
	state.Confirmed = false
	state.StartedAt = os.clock()
	state.Meter = meter
	state.NextBeat = os.clock() + 0.3
	state.ReleasedAt = nil
	clearMarks()
	setVisuals(true)
	if callbacks then
		callbacks.Request(true)
	end
	return true
end

-- Fire pressed during Dead Eye: paint whoever is under the crosshair. Returns true if used.
function DeadEye.TryMark(hit: RaycastResult?): boolean
	if not state.Active or state.Executing or not hit then
		return false
	end
	local target = markTarget(hit.Instance)
	if not target then
		return false
	end
	if not callbacks or #state.Marks >= callbacks.Rounds() then
		return true -- no rounds left to paint with
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SicilyDeadEyeMark"
	attachment.Parent = hit.Instance
	attachment.WorldPosition = hit.Position
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Mark"
	billboard.Adornee = attachment
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(26, 26)
	billboard.Parent = attachment
	local cross = Instance.new("TextLabel")
	cross.BackgroundTransparency = 1
	cross.Size = UDim2.fromScale(1, 1)
	cross.Font = Enum.Font.GothamBlack
	cross.Text = "X"
	cross.TextScaled = true
	cross.TextColor3 = Color3.fromRGB(214, 40, 34)
	cross.TextStrokeTransparency = 0.3
	cross.Parent = billboard
	table.insert(state.Marks, { Attachment = attachment })
	local camera = Workspace.CurrentCamera
	if camera then
		Fx.Sound(CLICK, camera, { Volume = 0.35, Pitch = 1.9 + #state.Marks * 0.06, StopAfter = 0.15 })
	end
	return true
end

local function turnTo(point: Vector3)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cf = camera.CFrame
	local direction = (point - cf.Position).Unit
	local look = cf.LookVector
	local yaw = math.atan2(-direction.X, -direction.Z) - math.atan2(-look.X, -look.Z)
	yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
	local pitch = math.asin(math.clamp(direction.Y, -1, 1)) - math.asin(math.clamp(look.Y, -1, 1))
	CameraFX.Rotate(yaw, pitch)
end

-- Every frame. aiming: the aim input is held.
function DeadEye.Update(dt: number, aiming: boolean)
	if not state.Active then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		DeadEye.Cancel()
		return
	end
	-- the server has the last word (not enough meter, gun put away...)
	if character:GetAttribute("DeadEye") == true then
		state.Confirmed = true
	elseif os.clock() - state.StartedAt > 0.8 + player:GetNetworkPing() * 2 and not state.Executing then
		DeadEye.Cancel()
		return
	end
	state.Meter = math.max(0, state.Meter - settings.DrainPerSecond * dt)

	-- heartbeat
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	if now >= state.NextBeat and camera then
		state.NextBeat = now + 0.95
		Fx.Sound(THUD, camera, { Volume = 0.5, Pitch = 0.5, StopAfter = 0.25 })
		task.delay(0.2, function()
			if state.Active and camera.Parent then
				Fx.Sound(THUD, camera, { Volume = 0.32, Pitch = 0.46, StopAfter = 0.25 })
			end
		end)
	end

	if state.Executing then
		if now >= state.NextShot then
			local mark = table.remove(state.Marks, 1)
			if mark then
				local attachment = mark.Attachment
				if attachment.Parent and attachment:IsDescendantOf(Workspace) then
					local point = attachment.WorldPosition
					turnTo(point)
					if callbacks and not callbacks.Fire(point) then
						clearMarks() -- out of rounds
					end
				end
				attachment:Destroy()
				state.NextShot = now + settings.ShotInterval
			end
			if #state.Marks == 0 then
				finish()
			end
		end
		return
	end
	if state.Meter <= 0 then
		execute()
	elseif not aiming then
		if #state.Marks > 0 then
			execute()
		else
			state.ReleasedAt = state.ReleasedAt or now
			if now - (state.ReleasedAt :: number) > 0.35 then
				finish()
			end
		end
	else
		state.ReleasedAt = nil
	end
end

-- Stop at once (death, holstering, mounting...).
function DeadEye.Cancel()
	finish()
end

return DeadEye
