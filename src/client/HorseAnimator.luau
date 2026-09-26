--[[
	Animates every horse near the camera with the shared gait solver (HorseGait): hooves planted
	on the real ground, gaits blended from the horse's physics, grazing / alert / taming poses
	from its attributes. Also: hoof-beat sounds and dust, hearts when a horse is tamed, and a
	flinch when it's startled.

	Other modules read HorseAnimator.GetState(model) (the body motion) so a rider moves with the
	saddle, and can push extra pose inputs with HorseAnimator.SetOverride(model, table).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local HorseGait = require(Shared:WaitForChild("HorseGait"))
local HorseRig = require(Shared:WaitForChild("HorseRig"))
local HorseTypes = require(Shared:WaitForChild("HorseTypes"))
local Taming = require(Shared:WaitForChild("Taming"))

local Fx = require(script.Parent.Fx)

local HorseAnimator = {}

local HST = Enum.HumanoidStateType
local MAX_DISTANCE = 320
local LOW_RATE_DISTANCE = 140
local HOOF_SOUND = "rbxasset://sounds/action_footsteps_plastic.mp3"

local horses = {} -- [Model] = entry
local overrides = {} -- [Model] = table merged into the sample
local timelines = {} -- [seed] = timeline

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true
local nextFilterRefresh = 0

local SOFT = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Snow] = true,
}
local DUSTY = {
	[Enum.Material.Ground] = Color3.fromRGB(170, 144, 110),
	[Enum.Material.Sand] = Color3.fromRGB(222, 202, 160),
	[Enum.Material.Grass] = Color3.fromRGB(156, 142, 104),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(156, 142, 104),
	[Enum.Material.Mud] = Color3.fromRGB(110, 90, 70),
	[Enum.Material.Cobblestone] = Color3.fromRGB(190, 180, 166),
	[Enum.Material.Pavement] = Color3.fromRGB(190, 180, 166),
}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function refreshFilter()
	local list: { Instance } = {}
	local folder = Workspace:FindFirstChild("SicilyHorses")
	if folder then
		table.insert(list, folder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(list, camera)
	end
	rayParams.FilterDescendantsInstances = list
end

-- Ground height under a point (terrain and solid parts, never horses or people).
local lastMaterial = Enum.Material.Grass
local function ground(point: Vector3): number?
	local hit = Workspace:Raycast(point + Vector3.new(0, 4.5, 0), Vector3.new(0, -12, 0), rayParams)
	if hit then
		lastMaterial = hit.Material
		return hit.Position.Y
	end
	return nil
end

local function timelineFor(seed: number, temperament)
	local key = seed .. ":" .. temperament.Id
	local timeline = timelines[key]
	if not timeline then
		timeline = Taming.Timeline(seed, temperament)
		timelines[key] = timeline
	end
	return timeline
end

local function register(model: Instance)
	if not model:IsA("Model") or horses[model] then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 10)
		local humanoid = model:WaitForChild("Humanoid", 10)
		if not root or not humanoid or not model:IsDescendantOf(Workspace) then
			return
		end
		-- joints may still be streaming in
		for _ = 1, 20 do
			local joints = HorseRig.GetJoints(model)
			local count = 0
			for _ in joints do
				count += 1
			end
			if count >= #HorseRig.JointNames then
				break
			end
			task.wait(0.1)
		end
		local temperament = HorseTypes.GetTemperament(model:GetAttribute("Temperament"))
		local entry = {
			Model = model,
			Root = root :: BasePart,
			Humanoid = humanoid :: Humanoid,
			Joints = HorseRig.GetJoints(model),
			Temperament = temperament,
			Gait = HorseGait.New(temperament),
			Skip = false,
			LastTamedAt = model:GetAttribute("TamedAt"),
			Startle = 0,
			LastStartle = model:GetAttribute("Startle"),
			Sounds = {},
			NextSound = 1,
			Connections = {},
		}
		for i = 1, 4 do
			local sound = Instance.new("Sound")
			sound.Name = "Hoof" .. i
			sound.SoundId = if Config.Horses.HoofSoundId ~= "" then Config.Horses.HoofSoundId else HOOF_SOUND
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 8
			sound.RollOffMaxDistance = 110
			sound.Parent = root
			entry.Sounds[i] = sound
		end
		table.insert(entry.Connections, model:GetAttributeChangedSignal("TamedAt"):Connect(function()
			local tamedAt = model:GetAttribute("TamedAt")
			if type(tamedAt) == "number" and serverNow() - tamedAt < 4 then
				local head = model:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					Fx.Hearts(head, 7)
				end
			end
		end))
		table.insert(entry.Connections, model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				HorseAnimator.Unregister(model)
			end
		end))
		horses[model] = entry
	end)
end

function HorseAnimator.Unregister(model: Instance)
	local entry = horses[model]
	if not entry then
		return
	end
	horses[model] = nil
	overrides[model] = nil
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
end

local function playHoof(entry, event, speed: number)
	local camera = Workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - event.Position).Magnitude > 110 then
		return
	end
	local sound = entry.Sounds[entry.NextSound]
	entry.NextSound = entry.NextSound % #entry.Sounds + 1
	local soft = SOFT[lastMaterial] == true
	local pace = math.clamp(speed / 30, 0, 1)
	sound.PlaybackSpeed = (if soft then 0.56 else 0.7) * (0.93 + math.random() * 0.14)
	sound.Volume = (if soft then 0.22 else 0.4) * (0.45 + 0.55 * pace) * (if event.Front then 1 else 0.85)
	sound.TimePosition = 0
	sound:Play()
	local token = (entry.SoundTokens or 0) + 1
	entry.SoundTokens = token
	task.delay(0.16, function()
		if entry.SoundTokens == token and sound.IsPlaying then
			sound:Stop()
		end
	end)
	-- dust kicked up at a canter or faster, and on landings
	local dust = DUSTY[lastMaterial]
	if dust and speed > 16 then
		Fx.EmitAt(event.Position + Vector3.new(0, 0.2, 0), "Dust", if speed > 26 then 2 else 1, {
			Color = dust,
			Scale = 0.8 + pace * 0.6,
		})
	end
end

local function sampleFor(entry, now: number)
	local model, root, humanoid = entry.Model, entry.Root, entry.Humanoid
	local velocity = root.AssemblyLinearVelocity
	local state = humanoid:GetState()
	local mode = "Ground"
	if state == HST.Swimming then
		mode = "Swim"
	elseif state == HST.Freefall or state == HST.Jumping or math.abs(velocity.Y) > 11 then
		mode = "Air" -- (remote horses don't always report their state, so velocity counts too)
	end
	local sample = {
		RootCFrame = root.CFrame,
		Velocity = velocity,
		AngularVelocity = root.AssemblyAngularVelocity.Y,
		Mode = mode,
		Graze = if model:GetAttribute("Graze") then 1 else 0,
		Alert = if model:GetAttribute("Alert") then 1 else 0,
		LookAt = model:GetAttribute("LookAt"),
		Rear = 0,
		Buck = 0,
		Kick = 0,
		Startle = 0,
	}
	-- taming: everyone plays the same struggle from the shared seed
	if model:GetAttribute("Mode") == "Taming" then
		local seed = model:GetAttribute("TameSeed")
		local start = model:GetAttribute("TameStart")
		if type(seed) == "number" and type(start) == "number" then
			local s = Taming.Sample(timelineFor(seed, entry.Temperament), now - start)
			sample.Rear = s.Rear
			sample.Buck = s.Buck
			sample.Kick = s.Kick
			sample.Startle = math.abs(s.Shake) * 0.5
			entry.TameSample = s
		end
	else
		entry.TameSample = nil
	end
	-- startled by a gunshot
	local startle = model:GetAttribute("Startle")
	if type(startle) == "number" then
		local age = now - startle
		if age >= 0 and age < 0.7 then
			sample.Startle = math.max(sample.Startle, math.sin(math.clamp(age / 0.7, 0, 1) * math.pi))
			sample.Rear = math.max(sample.Rear, 0.25 * math.sin(math.clamp(age / 0.7, 0, 1) * math.pi))
		end
	end
	local extra = overrides[model]
	if extra then
		for key, value in extra do
			if type(value) == "number" and type(sample[key]) == "number" then
				sample[key] = math.max(sample[key], value)
			else
				sample[key] = value
			end
		end
	end
	return sample
end

function HorseAnimator.Step(dt: number, cameraPosition: Vector3)
	local clock = os.clock()
	if clock >= nextFilterRefresh then
		nextFilterRefresh = clock + 1
		refreshFilter()
	end
	local now = serverNow()
	for model, entry in horses do
		local root = entry.Root
		if not root.Parent then
			continue
		end
		local distance = (root.Position - cameraPosition).Magnitude
		if distance > MAX_DISTANCE then
			continue
		end
		local step = dt
		if distance > LOW_RATE_DISTANCE then
			entry.Skip = not entry.Skip
			if entry.Skip then
				entry.Pending = (entry.Pending or 0) + dt
				continue
			end
			step = dt + (entry.Pending or 0)
			entry.Pending = 0
		end
		local ok, err = pcall(function()
			local sample = sampleFor(entry, now)
			local transforms, events = HorseGait.Step(entry.Gait, sample, step, ground)
			local joints = entry.Joints
			for name, cf in transforms do
				local joint = joints[name]
				if joint then
					joint.Transform = cf
				end
			end
			for _, event in events do
				playHoof(entry, event, entry.Gait.Speed)
			end
		end)
		if not ok then
			warn("[Sicily] Horse animation error on " .. model:GetFullName() .. ": " .. tostring(err))
			HorseAnimator.Unregister(model)
		end
	end
end

-- Body motion of a horse this frame (for the rider), or nil if it isn't animated.
function HorseAnimator.GetState(model: Model)
	local entry = horses[model]
	if not entry then
		return nil
	end
	return entry.Gait, entry.TameSample
end

-- Extra pose input for a horse (e.g. the rider's client adds a sliding stop). nil clears it.
function HorseAnimator.SetOverride(model: Model, values: { [string]: any }?)
	overrides[model] = values
end

function HorseAnimator.Start()
	for _, model in CollectionService:GetTagged(HorseRig.Tag) do
		register(model)
	end
	CollectionService:GetInstanceAddedSignal(HorseRig.Tag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(HorseRig.Tag):Connect(HorseAnimator.Unregister)
end

return HorseAnimator
