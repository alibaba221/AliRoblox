--[[
	SicilyShared.HorseMount
	How a rider sits on a horse, shared by the server (which creates the joint) and every client
	(which animates it).

	The rider's HumanoidRootPart is attached to the horse's HumanoidRootPart with a Motor6D named
	"SicilySaddle" (parented to the rider's root). Its C0 is the seat. While mounting or
	dismounting, every client animates the joint's Transform along the same arc from attributes
	the server sets, so the rider climbs on and steps off smoothly instead of teleporting:

		MountStart     server time the climb started
		MountFrom      rider root CFrame relative to the seat when it started
		DismountStart  server time the step-off started
		DismountTo     where the rider ends up, relative to the seat
]]

local HorseRig = require(script.Parent.HorseRig)

local HorseMount = {}

HorseMount.JointName = "SicilySaddle"
HorseMount.MountTime = 0.85
HorseMount.DismountTime = 0.6
HorseMount.RiderGroup = "SicilyRider"
HorseMount.HorseGroup = "SicilyHorse"
HorseMount.ShotGroup = "SicilyShot"

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- The seat frame in horse-root space (rider root sits here when mounted).
function HorseMount.SeatOffset(): CFrame
	return HorseRig.RiderOffset
end

-- Which side to mount/dismount (-1 = left, the traditional side; 1 = right).
function HorseMount.SideFromOffset(offset: Vector3): number
	return if offset.X > 0.3 then 1 else -1
end

--[[
	Transform (relative to the seat) of the rider while climbing on, u = 0..1.
	from: rider root relative to the seat at the start.
	Two beats: step in beside the stirrup, then swing up and over into the saddle.
]]
function HorseMount.MountTransform(from: CFrame, u: number): CFrame
	local side = HorseMount.SideFromOffset(from.Position)
	local stirrup = Vector3.new(side * 2.2, -2.75, 0.15)
	local position: Vector3
	if u < 0.35 then
		local k = ease(u / 0.35)
		position = from.Position:Lerp(stirrup, k)
	else
		local k = ease((u - 0.35) / 0.65)
		position = bezier(stirrup, stirrup + Vector3.new(0, 2.1, 0), Vector3.new(side * 0.9, 1.35, 0), Vector3.zero, k)
	end
	local turn = ease(u / 0.55)
	local rotation = from.Rotation:Lerp(CFrame.new(), turn)
	return CFrame.new(position) * rotation
end

-- Transform while stepping off (u = 0..1) towards `to` (relative to the seat).
function HorseMount.DismountTransform(to: CFrame, u: number): CFrame
	local side = HorseMount.SideFromOffset(to.Position)
	local k = ease(u)
	local position = bezier(Vector3.zero, Vector3.new(side * 0.8, 1.2, 0), to.Position + Vector3.new(0, 1.6, 0), to.Position, k)
	local rotation = CFrame.new():Lerp(to.Rotation, ease(u / 0.6))
	return CFrame.new(position) * rotation
end

-- Current transform of a saddle joint from its attributes (identity when seated).
-- Returns transform, phase ("Mount" | "Seated" | "Dismount"), progress 0..1.
function HorseMount.JointTransform(joint: Instance, serverNow: number): (CFrame, string, number)
	local dismountStart = joint:GetAttribute("DismountStart")
	if type(dismountStart) == "number" then
		local to = joint:GetAttribute("DismountTo")
		local u = math.clamp((serverNow - dismountStart) / HorseMount.DismountTime, 0, 1)
		if typeof(to) == "CFrame" then
			return HorseMount.DismountTransform(to, u), "Dismount", u
		end
	end
	local mountStart = joint:GetAttribute("MountStart")
	if type(mountStart) == "number" then
		local from = joint:GetAttribute("MountFrom")
		local u = math.clamp((serverNow - mountStart) / HorseMount.MountTime, 0, 1)
		if u < 1 and typeof(from) == "CFrame" then
			return HorseMount.MountTransform(from, u), "Mount", u
		end
	end
	return CFrame.new(), "Seated", 1
end

-- Finds the saddle joint on a rider (character) or nil.
function HorseMount.GetJoint(character: Model?): Motor6D?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local joint = root and root:FindFirstChild(HorseMount.JointName)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

-- The horse model a rider is on (via the saddle joint), or nil.
function HorseMount.GetHorse(character: Model?): Model?
	local joint = HorseMount.GetJoint(character)
	local horseRoot = joint and joint.Part0
	local horse = horseRoot and horseRoot.Parent
	if horse and horse:IsA("Model") and horse:HasTag(HorseRig.Tag) then
		return horse
	end
	return nil
end

--[[
	Picks where a rider should step off: the left side if there's room, else the right.
	`clear(localOffset)` tells whether a spot (in horse-root space) is free; returns a CFrame
	relative to the seat for DismountTo.
]]
function HorseMount.ChooseDismount(clear: ((Vector3) -> boolean)?): CFrame
	local layout = HorseRig.Layout
	local seat = HorseRig.RiderOffset
	for _, spot in { layout.MountLeft, layout.MountRight } do
		if not clear or clear(spot) then
			local relative = seat:Inverse() * CFrame.new(spot)
			return CFrame.new(relative.Position)
		end
	end
	-- no room on either side: slide off the back
	local back = seat:Inverse() * CFrame.new(0, layout.MountLeft.Y, 4.6)
	return CFrame.new(back.Position)
end

return HorseMount
