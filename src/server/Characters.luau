--[[
	Blocky R6 characters for every player.

	* Installs an R6 StarterCharacter built in code (no web requests, so it's ready instantly).
	* Stops Roblox from loading the R15/bundle appearance, then applies a "blockified" copy of the
	  player's avatar to the R6 body: 2D shirt/pants, rigid accessories (hats, hair), body colours
	  and face. Bundle body meshes and 3D layered clothing are dropped (they can't fit R6).
	* Optionally holds spawns until the town exists and puts players on the town's spawn points.
	* R6 ragdoll on death.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))
local R6 = require(Shared:WaitForChild("R6"))
local Ragdoll = require(script.Parent.Ragdoll)
local Util = require(script.Parent.Util)

local Characters = {}

local descriptions: { [Player]: HumanoidDescription } = {}
local townSpawns: { CFrame } = {}
local holdingSpawns = false

local function fallbackDescription(): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	local colors = Config.Characters.FallbackBodyColors
	description.HeadColor = colors.Head
	description.TorsoColor = colors.Torso
	description.LeftArmColor = colors.Arms
	description.RightArmColor = colors.Arms
	description.LeftLegColor = colors.Legs
	description.RightLegColor = colors.Legs
	return description
end

-- Returns a copy of `source` that only contains things a classic blocky R6 body can wear.
local function blockify(source: HumanoidDescription): HumanoidDescription
	local description = source:Clone()
	local settings = Config.Characters

	if settings.Blocky then
		description.Head = 0
		description.Torso = 0
		description.LeftArm = 0
		description.RightArm = 0
		description.LeftLeg = 0
		description.RightLeg = 0
	end
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	description.BodyTypeScale = 0
	description.ProportionScale = 0

	-- 3D layered clothing needs R15 cages; keep only rigid accessories (hats, hair, glasses...).
	local ok, accessories = pcall(function()
		return description:GetAccessories(true)
	end)
	if ok and type(accessories) == "table" then
		local keep = {}
		if settings.KeepAccessories then
			for _, info in accessories do
				if not info.IsLayered then
					table.insert(keep, info)
				end
			end
		end
		pcall(function()
			description:SetAccessories(keep, true)
		end)
	end

	if not settings.KeepClothing then
		description.Shirt = 0
		description.Pants = 0
		description.GraphicTShirt = 0
	end
	if not settings.KeepFace then
		description.Face = 0
	end
	if not settings.KeepBodyColors then
		local colors = settings.FallbackBodyColors
		description.HeadColor = colors.Head
		description.TorsoColor = colors.Torso
		description.LeftArmColor = colors.Arms
		description.RightArmColor = colors.Arms
		description.LeftLegColor = colors.Legs
		description.RightLegColor = colors.Legs
	end
	return description
end

local function fetchDescription(player: Player): HumanoidDescription
	local description: HumanoidDescription? = nil
	if player.UserId > 0 then
		for attempt = 1, 3 do
			local ok, result = pcall(Util.CallAsync, Players, "GetHumanoidDescriptionFromUserId", player.UserId)
			if ok and typeof(result) == "Instance" and result:IsA("HumanoidDescription") then
				description = result
				break
			end
			task.wait(attempt)
		end
	end
	return blockify(description or fallbackDescription())
end

local function waitForDescription(player: Player, timeout: number): HumanoidDescription?
	local deadline = os.clock() + timeout
	while descriptions[player] == nil and player.Parent ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return descriptions[player]
end

local function ensureClassicHead(character: Model)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if Config.Characters.Blocky and mesh and mesh.MeshType == Enum.MeshType.FileMesh then
		mesh.MeshType = Enum.MeshType.Head
		mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	end
	if not head:FindFirstChildWhichIsA("Decal") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = R6.DefaultFace
		face.Parent = head
	end
end

local function stripBundleMeshes(character: Model)
	if not Config.Characters.Blocky then
		return
	end
	for _, child in character:GetChildren() do
		if child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end
end

local function dress(player: Player, character: Model, humanoid: Humanoid)
	local description = waitForDescription(player, 20)
	if not description then
		return
	end
	if not Util.WaitForAncestor(character, Workspace, 10) then
		return
	end
	local ok, err = pcall(Util.CallAsync, humanoid, "ApplyDescription", description)
	if not ok then
		warn(("[Sicily] Couldn't apply %s's avatar to the R6 body: %s"):format(player.Name, tostring(err)))
	end
	if character.Parent == nil then
		return
	end
	stripBundleMeshes(character)
	ensureClassicHead(character)
	character:SetAttribute("SicilyDressed", true)
end

local function placeAtTownSpawn(character: Model)
	if not Config.Town.UseTownSpawns or #townSpawns == 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	for _, spawnCFrame in townSpawns do
		if (root.Position - spawnCFrame.Position).Magnitude < 18 then
			return -- already spawned on one of the town's spawn points
		end
	end
	local spawnCFrame = townSpawns[math.random(1, #townSpawns)]
	local jitter = Vector3.new(math.random(-25, 25) / 10, 3.1, math.random(-25, 25) / 10)
	character:PivotTo(spawnCFrame + jitter)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	if Config.Characters.ForceR6 and humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		-- Spawned before the R6 StarterCharacter was installed (or by another system). Respawn once.
		local attempts = player:GetAttribute("SicilyR6Attempts") or 0
		if attempts < 2 then
			player:SetAttribute("SicilyR6Attempts", attempts + 1)
			task.defer(function()
				if player.Parent and player.Character == character then
					pcall(Util.CallAsync, player, "LoadCharacter")
				end
			end)
		else
			warn(("[Sicily] %s keeps spawning as R15. Is another script replacing StarterCharacter?"):format(player.Name))
		end
		return
	end
	player:SetAttribute("SicilyR6Attempts", 0)

	character:AddTag(R6.Tag)

	humanoid.BreakJointsOnDeath = not Config.Characters.Ragdoll
	if Config.Characters.Ragdoll then
		humanoid.Died:Connect(function()
			Ragdoll.Apply(character)
		end)
	end

	task.spawn(function()
		if Util.WaitForAncestor(character, Workspace, 5) then
			placeAtTownSpawn(character)
		end
	end)
	task.spawn(dress, player, character, humanoid)
end

local function onPlayerAdded(player: Player)
	player.CanLoadCharacterAppearance = false
	player.CameraMaxZoomDistance = Config.Camera.MaxZoom
	player.CameraMinZoomDistance = Config.Camera.MinZoom

	task.spawn(function()
		local description = fetchDescription(player)
		if player.Parent then
			descriptions[player] = description
		end
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function installStarterCharacter()
	local existing = StarterPlayer:FindFirstChild("StarterCharacter")
	if existing then
		-- Keep the old one around (runtime only) instead of destroying it.
		existing.Name = "StarterCharacter_Original"
		existing.Parent = ServerStorage
	end
	local starter = R6.Build({ Name = "StarterCharacter" })
	starter.Parent = StarterPlayer
end

--[[
	Starts the character pipeline. Returns `release(spawnCFrames)`, which must be called once the
	world is ready: it stores the town spawn points and lets held players spawn.
]]
function Characters.Start(options: { HoldSpawns: boolean }): ({ CFrame }?) -> ()
	if Config.Characters.ForceR6 then
		installStarterCharacter()
	end

	StarterPlayer.LoadCharacterAppearance = false
	StarterPlayer.CharacterWalkSpeed = Config.Movement.WalkSpeed
	StarterPlayer.CharacterUseJumpPower = false
	StarterPlayer.CharacterJumpHeight = Config.Movement.JumpHeight
	StarterPlayer.CameraMaxZoomDistance = Config.Camera.MaxZoom
	StarterPlayer.CameraMinZoomDistance = Config.Camera.MinZoom
	StarterPlayer.CharacterBreakJointsOnDeath = not Config.Characters.Ragdoll

	if options.HoldSpawns and Players.CharacterAutoLoads then
		holdingSpawns = true
		Players.CharacterAutoLoads = false
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
	end)

	return function(spawnCFrames: { CFrame }?)
		townSpawns = spawnCFrames or {}
		if holdingSpawns then
			holdingSpawns = false
			Players.CharacterAutoLoads = true
			for _, player in Players:GetPlayers() do
				if player.Character == nil then
					task.spawn(function()
						local ok, err = pcall(Util.CallAsync, player, "LoadCharacter")
						if not ok then
							warn("[Sicily] LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
						end
					end)
				end
			end
		end
	end
end

return Characters
