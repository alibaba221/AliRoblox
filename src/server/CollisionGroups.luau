--[[
	Collision groups shared by horses and guns (server):
	  SicilyRider  a rider's body while on a horse: carried by the horse, collides with nothing
	  SicilyShot   used by bullet raycasts: hits everything, riders included
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HorseMount = require(ReplicatedStorage:WaitForChild("SicilyShared"):WaitForChild("HorseMount"))

local CollisionGroups = {}

local done = false

function CollisionGroups.Setup()
	if done then
		return
	end
	done = true
	for _, name in { HorseMount.RiderGroup, HorseMount.ShotGroup } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	for _, other in PhysicsService:GetRegisteredCollisionGroups() do
		PhysicsService:CollisionGroupSetCollidable(HorseMount.RiderGroup, other.name, false)
	end
	for _, other in PhysicsService:GetRegisteredCollisionGroups() do
		if other.name ~= HorseMount.RiderGroup then
			PhysicsService:CollisionGroupSetCollidable(HorseMount.ShotGroup, other.name, true)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(HorseMount.ShotGroup, HorseMount.RiderGroup, true)
end

return CollisionGroups
