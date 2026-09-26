--[[
	SicilyShared.HorseMotor
	Drives a horse's Humanoid so it moves like a horse, not a VehicleSeat:

	  * speed eases between gaits (walk, trot, canter, gallop) with separate acceleration,
	    easing off and braking, and slows down uphill and in sharp turns;
	  * the body turns at a limited, speed-dependent rate: pivots on the spot when standing,
	    wide arcs at a gallop, never an instant rotation;
	  * galloping costs stamina; a fresh spur gives a short burst; empty stamina = winded;
	  * jumping (higher at speed) with a cooldown.

	Used by the rider's client (it owns the horse's physics while riding) and by the server's
	AI for riderless horses, so both move identically.

	Command (all optional):
		Direction  Vector3   world direction to head towards (camera-relative steering)
		Turn       number    -1..1 turn left/right relative to the horse (used while aiming)
		Gait       number    0 stop, 1 walk, 2 trot, 3 canter, 4 gallop
		Back       boolean   walk backwards
		Brake      boolean   pull up hard
		Spur       boolean   true on the frame Shift/L3 is pressed
		Jump       boolean
		TurnScale  number    multiplies the turn rate (a bucking horse spins faster)
]]

local Workspace = game:GetService("Workspace")

local HorseTypes = require(script.Parent.HorseTypes)

local HorseMotor = {}
HorseMotor.__index = HorseMotor

HorseMotor.Stop, HorseMotor.Walk, HorseMotor.Trot, HorseMotor.Canter, HorseMotor.Gallop = 0, 1, 2, 3, 4

local HST = Enum.HumanoidStateType
local DISABLED_STATES = {
	HST.Climbing,
	HST.FallingDown,
	HST.Ragdoll,
	HST.GettingUp,
	HST.Seated,
	HST.Flying,
	HST.StrafingNoPhysics,
	HST.Dead,
}

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Horse humanoids never climb, trip, sit or die. State flags don't replicate, so this runs on
-- whichever machine is simulating the horse (the server, or the rider's client).
function HorseMotor.ConfigureHumanoid(humanoid: Humanoid)
	for _, state in DISABLED_STATES do
		pcall(function()
			humanoid:SetStateEnabled(state, false)
		end)
	end
	humanoid.AutoRotate = false
	humanoid.UseJumpPower = false
end

-- The AlignOrientation that turns the horse (created on the server so every machine has it).
function HorseMotor.EnsureAlign(root: BasePart): AlignOrientation
	local align = root:FindFirstChild("HorseFacing")
	if align and align:IsA("AlignOrientation") then
		return align
	end
	local attachment = root:FindFirstChild("HorseFacingAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "HorseFacingAttachment"
		attachment.Parent = root
	end
	local new = Instance.new("AlignOrientation")
	new.Name = "HorseFacing"
	new.Mode = Enum.OrientationAlignmentMode.OneAttachment
	new.Attachment0 = attachment :: Attachment
	new.RigidityEnabled = false
	new.Responsiveness = 45
	new.MaxTorque = 1e8
	new.MaxAngularVelocity = math.huge
	new.CFrame = CFrame.Angles(0, yawOf(root.CFrame), 0)
	new.Parent = root
	return new
end

function HorseMotor.new(model: Model, temperament)
	local self = setmetatable({}, HorseMotor)
	self.Model = model
	self.Humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.Root = model.PrimaryPart :: BasePart
	self.Temperament = temperament or HorseTypes.GetTemperament(model:GetAttribute("Temperament"))
	self.Align = HorseMotor.EnsureAlign(self.Root)
	self.Speed = 0
	self.Heading = yawOf(self.Root.CFrame)
	self.TurnRate = 0
	self.Stamina = self.Temperament.Stamina
	self.Winded = 0
	self.SinceGallop = 10
	self.Spur = 0
	self.JumpCooldown = 0
	self.Slope = 0
	self.NextSlopeCheck = 0
	self.Blocked = 0
	self.Gait = 0
	return self
end

-- Resets the motor to the horse's current physical state (e.g. when a rider takes over).
function HorseMotor:Sync()
	local root = self.Root
	local look = root.CFrame.LookVector
	self.Heading = yawOf(root.CFrame)
	local velocity = root.AssemblyLinearVelocity
	self.Speed = Vector3.new(velocity.X, 0, velocity.Z):Dot(Vector3.new(look.X, 0, look.Z).Unit)
	self.TurnRate = root.AssemblyAngularVelocity.Y
end

function HorseMotor:GaitSpeed(gait: number): number
	local t = self.Temperament
	if gait >= 4 then
		return t.GallopSpeed
	elseif gait >= 3 then
		return t.CanterSpeed
	elseif gait >= 2 then
		return t.TrotSpeed
	elseif gait >= 1 then
		return t.WalkSpeed
	end
	return 0
end

function HorseMotor:CanGallop(): boolean
	return self.Winded <= 0 and self.Stamina > 0.05
end

local slopeParams = RaycastParams.new()
slopeParams.FilterType = Enum.RaycastFilterType.Exclude
slopeParams.IgnoreWater = true
slopeParams.RespectCanCollide = true

local function sampleSlope(self)
	local root = self.Root
	local forward = Vector3.new(-math.sin(self.Heading), 0, -math.cos(self.Heading))
	slopeParams.FilterDescendantsInstances = { self.Model }
	local heights = {}
	for i, offset in { 3.2, -3.2 } do
		local origin = root.Position + forward * offset + Vector3.new(0, 1, 0)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -9, 0), slopeParams)
		heights[i] = if hit then hit.Position.Y else nil
	end
	if heights[1] and heights[2] then
		self.Slope = math.clamp((heights[1] - heights[2]) / 6.4, -1, 1)
	else
		self.Slope = 0
	end
end

function HorseMotor:Update(dt: number, command)
	local humanoid, root = self.Humanoid, self.Root
	if not humanoid or not root or not root.Parent then
		return
	end
	local t = self.Temperament
	dt = math.clamp(dt, 1 / 240, 0.1)
	local state = humanoid:GetState()
	local airborne = state == HST.Freefall or state == HST.Jumping
	local swimming = state == HST.Swimming

	-- Stamina -----------------------------------------------------------------------------
	local galloping = self.Speed > (t.CanterSpeed + t.GallopSpeed) / 2
	if galloping then
		self.SinceGallop = 0
		self.Stamina = math.max(0, self.Stamina - dt)
		if self.Stamina <= 0 then
			self.Winded = t.WindedTime
		end
	else
		self.SinceGallop += dt
		if self.SinceGallop > t.StaminaRegenDelay then
			self.Stamina = math.min(t.Stamina, self.Stamina + t.StaminaRegen * dt)
		end
	end
	if self.Winded > 0 then
		self.Winded = math.max(0, self.Winded - dt)
		if self.Winded <= 0 and self.Stamina < t.Stamina * 0.25 then
			self.Winded = 0.2 -- stay winded until a quarter of the stamina is back
		end
	end

	-- Target speed ------------------------------------------------------------------------
	local gait = math.clamp(command.Gait or 0, 0, 4)
	if gait >= 4 and not self:CanGallop() then
		gait = 3
	end
	if command.Spur and gait >= 2 and self.Stamina >= t.SpurCost and self.Winded <= 0 then
		self.Stamina -= t.SpurCost
		self.Spur = t.SpurTime
	end
	self.Spur = math.max(0, self.Spur - dt)
	self.Gait = gait

	local target = self:GaitSpeed(gait)
	if command.Back then
		target = -t.BackSpeed
	end
	if self.Spur > 0 and target > 0 then
		target *= t.SpurBoost
	end
	if swimming then
		target = math.clamp(target, -t.BackSpeed, t.SwimSpeed)
	end

	-- steering
	local maxRate = HorseTypes.TurnRate(t, self.Speed) * (command.TurnScale or 1)
	local desiredRate = 0
	local turnError = 0
	if command.Direction and command.Direction.Magnitude > 0.05 then
		local direction = command.Direction
		local desiredYaw = math.atan2(-direction.X, -direction.Z)
		turnError = wrapAngle(desiredYaw - self.Heading)
		desiredRate = math.clamp(turnError * 3.2, -maxRate, maxRate)
	elseif command.Turn then
		desiredRate = math.clamp(command.Turn, -1, 1) * maxRate
	end
	-- sharp turns at speed bleed off speed (a galloping horse can't turn on a coin)
	local sharp = math.clamp((math.abs(turnError) - 1.0) / 1.4, 0, 1)
	if target > t.TrotSpeed then
		target = target - (target - t.TrotSpeed) * sharp * 0.75
	end

	-- slopes
	local now = os.clock()
	if now >= self.NextSlopeCheck then
		self.NextSlopeCheck = now + 0.15
		sampleSlope(self)
	end
	if target > 0 then
		target *= math.clamp(1 - self.Slope * 0.55, 0.62, 1.12)
	end

	-- Speed -------------------------------------------------------------------------------
	local diff = target - self.Speed
	local accel: number
	if command.Brake or (target < self.Speed and target <= 0.5 and self.Speed > t.TrotSpeed) then
		accel = if command.Brake then t.Braking else t.Deceleration * 1.3
	elseif diff > 0 then
		accel = if self.Speed > t.CanterSpeed then t.GallopAcceleration else t.Acceleration
		if self.Spur > 0 then
			accel *= 1.6
		end
	else
		accel = t.Deceleration
	end
	if airborne then
		accel *= 0.15 -- can't push off the air
	end
	-- ease in close to the target so gait changes settle softly
	local step = math.clamp(diff * 2.4, -accel, accel) * dt
	self.Speed += step

	-- don't build up phantom speed against a wall
	local velocity = root.AssemblyLinearVelocity
	local forward = Vector3.new(-math.sin(self.Heading), 0, -math.cos(self.Heading))
	local actual = Vector3.new(velocity.X, 0, velocity.Z):Dot(forward)
	if not airborne and math.abs(self.Speed) > 4 and math.abs(actual) < math.abs(self.Speed) * 0.35 then
		self.Blocked += dt
		if self.Blocked > 0.35 then
			self.Speed = actual + (self.Speed - actual) * math.exp(-4 * dt)
		end
	else
		self.Blocked = 0
	end

	-- Turning -----------------------------------------------------------------------------
	local turnAccel = math.rad(t.TurnAcceleration) * (if airborne then 0.3 else 1)
	self.TurnRate += math.clamp(desiredRate - self.TurnRate, -turnAccel * dt, turnAccel * dt)
	self.Heading = wrapAngle(self.Heading + self.TurnRate * dt)

	-- Jumping -----------------------------------------------------------------------------
	self.JumpCooldown = math.max(0, self.JumpCooldown - dt)
	if command.Jump and self.JumpCooldown <= 0 and not airborne and not swimming then
		local pace = math.clamp(self.Speed / math.max(t.CanterSpeed, 1), 0, 1)
		humanoid.JumpHeight = 2.2 + (t.JumpHeight - 2.2) * pace
		humanoid.Jump = true
		self.JumpCooldown = t.JumpCooldown
	end

	-- Apply -------------------------------------------------------------------------------
	humanoid.WalkSpeed = math.abs(self.Speed)
	forward = Vector3.new(-math.sin(self.Heading), 0, -math.cos(self.Heading))
	if math.abs(self.Speed) > 0.05 then
		humanoid:Move(forward * (if self.Speed > 0 then 1 else -1), false)
	else
		humanoid:Move(Vector3.zero, false)
	end
	self.Align.CFrame = CFrame.Angles(0, self.Heading, 0)
end

-- Instantly stop (e.g. when mounting), keeping the current heading.
function HorseMotor:Halt()
	self.Speed = 0
	self.TurnRate = 0
	if self.Humanoid then
		self.Humanoid.WalkSpeed = 0
		self.Humanoid:Move(Vector3.zero, false)
	end
	if self.Align then
		self.Align.CFrame = CFrame.Angles(0, self.Heading, 0)
	end
end

return HorseMotor
