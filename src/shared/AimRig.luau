--[[
	SicilyShared.AimRig
	Pose maths for holding guns on an R6 rig (pure CFrame maths, used by the client animator and
	the offline tests).

	R6 arms are single rigid blocks, so poses are built "gun first": decide where the gun is (in
	Torso space), then point each arm so its hand lands on the gun's grip / fore-end.

	  * Pistol hold: one-handed, arm straight at the target (a classic western stance).
	  * Long hold: bladed stance (torso turned so the left shoulder leads), stock at the right
	    shoulder, left hand on the fore-end.
	  * Ready: pistols pointed low; long guns carried in the right hand, muzzle forward and down
	    (short R6 arms can't also reach the fore-end down there). The left hand joins as the gun
	    comes up to aim.
]]

local R6 = require(script.Parent.R6)

local AimRig = {}

local JOINTS = {}
for _, joint in R6.Joints do
	JOINTS[joint.Name] = joint
end
local RIGHT = JOINTS["Right Shoulder"]
local LEFT = JOINTS["Left Shoulder"]

AimRig.RightPivot = RIGHT.C0.Position
AimRig.LeftPivot = LEFT.C0.Position
-- Pivot -> hand vector in each arm's own space (hands are the grip attachments at (0, -1, 0)).
local RIGHT_HAND = Vector3.new(0, -1, 0) - RIGHT.C1.Position
local LEFT_HAND = Vector3.new(0, -1, 0) - LEFT.C1.Position
AimRig.ArmReach = RIGHT_HAND.Magnitude
local GRIP = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0) -- R6 RightGripAttachment

local UP = Vector3.new(0, 1, 0)

local function orthonormal(forward: Vector3, upHint: Vector3): (Vector3, Vector3)
	local f = forward.Unit
	local u = upHint - f * upHint:Dot(f)
	if u.Magnitude < 1e-4 then
		u = if math.abs(f.Y) < 0.9 then UP else Vector3.new(0, 0, -1)
		u = u - f * u:Dot(f)
	end
	return f, u.Unit
end

-- Shoulder Transform that gives the arm part this rotation in Torso space.
local function shoulderFor(joint, armRotation: CFrame): CFrame
	return joint.C0.Rotation:Inverse() * armRotation * joint.C1.Rotation
end

--[[
	Arm rotation (Torso space) that puts the hand on `target` (Torso space), with the arm's front
	face turned towards `hint` (e.g. the gun's top, so the palm sits under it).
]]
local function reachRotation(pivot: Vector3, handVector: Vector3, target: Vector3, hint: Vector3): CFrame
	local toTarget = target - pivot
	if toTarget.Magnitude < 1e-3 then
		toTarget = Vector3.new(0, -1, 0)
	end
	local a1 = handVector.Unit
	local a2 = Vector3.new(0, 0, -1)
	local a3 = a1:Cross(a2)
	local b1, b2 = orthonormal(toTarget, hint)
	local b3 = b1:Cross(b2)
	local A = CFrame.fromMatrix(Vector3.zero, a1, a2, a3)
	local B = CFrame.fromMatrix(Vector3.zero, b1, b2, b3)
	return B * A:Inverse()
end

-- Right/left shoulder Transform reaching for a Torso-space point.
function AimRig.Reach(side: string, target: Vector3, hint: Vector3?): CFrame
	local isRight = side == "Right"
	local joint = if isRight then RIGHT else LEFT
	local rotation = reachRotation(joint.C0.Position, if isRight then RIGHT_HAND else LEFT_HAND, target, hint or UP)
	return shoulderFor(joint, rotation)
end

-- Where a hand is (Torso space) for a given shoulder Transform.
function AimRig.HandPosition(side: string, transform: CFrame): Vector3
	local joint = if side == "Right" then RIGHT else LEFT
	local arm = joint.C0 * transform * joint.C1:Inverse()
	return arm:PointToWorldSpace(Vector3.new(0, -1, 0))
end

-- The right hand's grip frame (Torso space): -Z out of the fist, +Y towards the arm's front.
function AimRig.GripFrame(transform: CFrame): CFrame
	return RIGHT.C0 * transform * RIGHT.C1:Inverse() * GRIP
end

-- Weapon joint Transform (Motor6D on the Torso, C0 = holster) that puts the Handle at `gun`.
function AimRig.WeaponTransform(holsterC0: CFrame, gun: CFrame): CFrame
	return holsterC0:Inverse() * gun
end

local function gunFrame(position: Vector3, forward: Vector3, up: Vector3): CFrame
	local f, u = orthonormal(forward, up)
	return CFrame.fromMatrix(position, f:Cross(u), u, -f)
end

-- Torso twist (yaw, radians; negative turns the torso right) for each hold while aiming.
AimRig.Twist = { Pistol = -0.2, Long = -0.65 }

-- Where the left hand holds a long gun: on the fore-end, but no further out than R6 arms reach.
AimRig.SupportReach = 0.62
function AimRig.SupportPoint(gun: CFrame, support: Vector3?): Vector3
	local s = support or Vector3.new(0, 0, -1.1)
	return gun:PointToWorldSpace(Vector3.new(s.X, s.Y, math.max(s.Z, -AimRig.SupportReach)))
end

--[[
	Gun pose while aiming along `aim` (unit, Torso space, measured AFTER the twist is applied).
	Returns the Handle CFrame (Torso space) and the right/left shoulder Transforms
	(left = nil when the left hand is free).
	support: the weapon's Support attachment position (Handle space), for long guns.
]]
function AimRig.Aim(hold: string, aim: Vector3, support: Vector3?): (CFrame, CFrame, CFrame?)
	if hold == "Long" then
		-- stock tucked in front of the right chest, hands close together (R6 arms are short)
		local f, u = orthonormal(aim, UP)
		local stock = Vector3.new(0.15, 0.5, -0.55)
		local grip = stock + f * 0.6
		local gun = gunFrame(grip, f, u)
		local right = AimRig.Reach("Right", grip, u)
		local left = AimRig.Reach("Left", AimRig.SupportPoint(gun, support), u)
		return gun, right, left
	end
	-- one-handed: arm straight along the aim, gun in the fist
	local f, u = orthonormal(aim, UP)
	local armRotation = CFrame.fromMatrix(Vector3.zero, f:Cross(u), -f, -u)
	local right = shoulderFor(RIGHT, armRotation)
	local gun = AimRig.GripFrame(right)
	return gun, right, nil
end

--[[
	Low-ready pose (gun out, not aiming): pistols point down at ~55°; long guns hang in the right
	hand, muzzle forward and down (the left hand is free). `swing` lets the pose sway with the walk.
]]
function AimRig.Ready(hold: string, _support: Vector3?, swing: number?): (CFrame, CFrame, CFrame?)
	local s = swing or 0
	if hold == "Long" then
		local arm = Vector3.new(-0.1, -0.85, -0.5 + s * 0.06).Unit
		local grip = AimRig.RightPivot + arm * AimRig.ArmReach -- exactly where the hand is
		local gun = gunFrame(grip, Vector3.new(-0.12, -0.4, -0.91), UP)
		return gun, AimRig.Reach("Right", grip, gun.UpVector), nil
	end
	local f = Vector3.new(0.05, -math.sin(math.rad(58)), -math.cos(math.rad(58)) + s * 0.05).Unit
	return AimRig.Aim("Pistol", f)
end

-- Aim direction in Torso space from a world direction and the Torso's world CFrame.
function AimRig.ToTorso(torso: CFrame, worldDirection: Vector3): Vector3
	return torso:VectorToObjectSpace(worldDirection).Unit
end

return AimRig
