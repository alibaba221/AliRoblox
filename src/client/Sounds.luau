--[[
	Character sounds for every R6 rig: footsteps fired by the animator exactly when a foot lands
	(pitch/volume by floor material and speed), jump, landing thud, splash and swim strokes.
	Replaces Roblox's default RbxCharacterSounds (overridden by an empty script of that name).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local R6 = require(Shared:WaitForChild("R6"))

local Sounds = {}

local audio = Config.Audio
local HST = Enum.HumanoidStateType
local HEARING_DISTANCE = 90

local STONE = { Pitch = 1.05, Volume = 1 }
local PROFILES = {
	[Enum.Material.Wood] = { Pitch = 0.82, Volume = 1.15 },
	[Enum.Material.WoodPlanks] = { Pitch = 0.82, Volume = 1.15 },
	[Enum.Material.Grass] = { Pitch = 0.72, Volume = 0.55 },
	[Enum.Material.LeafyGrass] = { Pitch = 0.72, Volume = 0.55 },
	[Enum.Material.Ground] = { Pitch = 0.74, Volume = 0.6 },
	[Enum.Material.Mud] = { Pitch = 0.68, Volume = 0.6 },
	[Enum.Material.Sand] = { Pitch = 0.66, Volume = 0.45 },
	[Enum.Material.Metal] = { Pitch = 1.3, Volume = 0.9 },
	[Enum.Material.DiamondPlate] = { Pitch = 1.3, Volume = 0.9 },
	[Enum.Material.CorrodedMetal] = { Pitch = 1.25, Volume = 0.9 },
	[Enum.Material.Fabric] = { Pitch = 0.8, Volume = 0.4 },
	[Enum.Material.Carpet] = { Pitch = 0.8, Volume = 0.4 },
}

local sets = setmetatable({}, { __mode = "k" })
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function newSound(parent: Instance, soundId: string, name: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = HEARING_DISTANCE
	sound.Parent = parent
	return sound
end

local function getSet(model: Model, root: BasePart)
	local set = sets[model]
	if set and set.Root == root and root.Parent then
		return set
	end
	set = {
		Root = root,
		Steps = {
			newSound(root, audio.FootstepSoundId, "SicilyStepA"),
			newSound(root, audio.FootstepSoundId, "SicilyStepB"),
		},
		Tokens = { 0, 0 },
		Next = 1,
		Jump = newSound(root, audio.JumpSoundId, "SicilyJump"),
		Land = newSound(root, audio.LandSoundId, "SicilyLand"),
		Splash = newSound(root, audio.SplashSoundId, "SicilySplash"),
		Swim = newSound(root, audio.SwimSoundId, "SicilySwim"),
		FloorMaterial = Enum.Material.Plastic,
		NextFloorCheck = 0,
	}
	set.Swim.Looped = true
	sets[model] = set
	return set
end

local function nearCamera(position: Vector3, range: number): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < range
end

local function floorMaterial(rig, set): Enum.Material
	if rig.IsLocal then
		return rig.Humanoid.FloorMaterial
	end
	local now = os.clock()
	if now >= set.NextFloorCheck then
		set.NextFloorCheck = now + 0.4
		rayParams.FilterDescendantsInstances = { rig.Model }
		local hit = Workspace:Raycast(rig.Root.Position, Vector3.new(0, -4.5, 0), rayParams)
		set.FloorMaterial = if hit then hit.Material else Enum.Material.Plastic
	end
	return set.FloorMaterial
end

local function playStep(rig, speed: number, run: number)
	local root = rig.Root
	if not root.Parent or not nearCamera(root.Position, HEARING_DISTANCE) then
		return
	end
	local set = getSet(rig.Model, root)
	local index = set.Next
	set.Next = index % #set.Steps + 1
	local sound = set.Steps[index]
	local profile = PROFILES[floorMaterial(rig, set)] or STONE

	sound.PlaybackSpeed = profile.Pitch * (0.92 + math.random() * 0.16) * (1 + run * 0.1)
	local pace = math.clamp(speed / math.max(Config.Movement.RunSpeed, 1), 0, 1)
	sound.Volume = audio.FootstepVolume * profile.Volume * (0.55 + 0.45 * pace) * (if rig.IsLocal then 1 else 0.8)
	sound.TimePosition = 0
	sound:Play()

	-- The built-in step clip holds several steps; keep only the first one.
	set.Tokens[index] += 1
	local token = set.Tokens[index]
	task.delay(0.2, function()
		if set.Tokens[index] == token and sound.IsPlaying then
			sound:Stop()
		end
	end)
end

local watched = setmetatable({}, { __mode = "k" })

local function watchRig(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	watched[model] = true
	task.spawn(function()
		local humanoid = model:WaitForChild("Humanoid", 10)
		local root = model:WaitForChild("HumanoidRootPart", 10)
		if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
			return
		end
		humanoid.StateChanged:Connect(function(old, new)
			if not root.Parent or not nearCamera(root.Position, HEARING_DISTANCE) then
				return
			end
			local set = getSet(model :: Model, root :: BasePart)
			if new == HST.Jumping then
				set.Jump.Volume = 0.35
				set.Jump.PlaybackSpeed = 0.95 + math.random() * 0.1
				set.Jump:Play()
			elseif new == HST.Swimming and old == HST.Freefall then
				local impact = math.abs((root :: BasePart).AssemblyLinearVelocity.Y)
				set.Splash.Volume = math.clamp(impact / 60, 0.2, 0.7)
				set.Splash:Play()
			end
			if new == HST.Swimming then
				set.Swim.Volume = 0.25
				set.Swim:Play()
			elseif old == HST.Swimming then
				set.Swim:Stop()
			end
		end)
	end)
end

function Sounds.Start(animator)
	animator.OnFootstep(function(rig, _side, speed, run)
		if audio.Footsteps then
			playStep(rig, speed, run)
		end
	end)
	animator.OnLanded(function(rig, impact)
		local root = rig.Root
		if not root.Parent or not nearCamera(root.Position, HEARING_DISTANCE) then
			return
		end
		local set = getSet(rig.Model, root)
		set.Land.Volume = math.clamp(impact / 120, 0.12, 0.7)
		set.Land.PlaybackSpeed = 0.9 + math.random() * 0.15
		set.Land:Play()
	end)

	for _, model in CollectionService:GetTagged(R6.Tag) do
		watchRig(model)
	end
	CollectionService:GetInstanceAddedSignal(R6.Tag):Connect(watchRig)
end

return Sounds
