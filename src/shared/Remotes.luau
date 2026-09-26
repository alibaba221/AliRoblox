--[[
	SicilyShared.Remotes
	Every RemoteEvent the horse and combat systems use, in ReplicatedStorage.SicilyRemotes.
	The server creates them at start-up; clients wait for them.

	Client -> server
	  HorseRequest   (action: string, ...)      "Dismount", "Calm", "Call"
	  CombatRequest  (action: string, ...)      "Equip", "Holster", "Reload", "DeadEye", "Cover"
	  Fire           (shot: table)              one trigger pull (validated, see Combat)
	  AimState       (aiming, pitch, yaw)       unreliable, ~12 Hz, drives other players' poses

	Server -> client(s)
	  HorseEvent     (kind: string, ...)        "Mounted", "Tamed", "Thrown", "Dismounted", "Startled"
	  CombatEvent    (kind: string, ...)        "Hit", "Damaged", "Ammo", "Rejected", "Killed"
	  ShotFX         (shooter, weapon, ...)     unreliable, other players' muzzle flash / tracers
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER = "SicilyRemotes"
local DEFINITIONS = {
	HorseRequest = "RemoteEvent",
	HorseEvent = "RemoteEvent",
	CombatRequest = "RemoteEvent",
	CombatEvent = "RemoteEvent",
	Fire = "RemoteEvent",
	AimState = "UnreliableRemoteEvent",
	ShotFX = "UnreliableRemoteEvent",
}

local cache: { [string]: Instance } = {}

local function folder(): Instance
	local existing = ReplicatedStorage:FindFirstChild(FOLDER)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local new = Instance.new("Folder")
		new.Name = FOLDER
		new.Parent = ReplicatedStorage
		return new
	end
	return ReplicatedStorage:WaitForChild(FOLDER)
end

function Remotes.Get(name: string): any
	local cached = cache[name]
	if cached and cached.Parent then
		return cached
	end
	local className = DEFINITIONS[name]
	assert(className, "Unknown remote " .. name)
	local parent = folder()
	local remote = parent:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			local ok, created = pcall(Instance.new, className)
			if not ok then
				-- very old builds without UnreliableRemoteEvent
				created = Instance.new("RemoteEvent")
			end
			created.Name = name
			created.Parent = parent
			remote = created
		else
			remote = parent:WaitForChild(name)
		end
	end
	cache[name] = remote
	return remote
end

-- Server: create everything up front so clients never wait.
function Remotes.Init()
	for name in DEFINITIONS do
		Remotes.Get(name)
	end
end

return Remotes
