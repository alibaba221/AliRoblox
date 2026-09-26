--[[
	Riderless horse behaviour (server). Pure decision-making: it reads a `senses` table and
	returns a command for HorseMotor plus what the horse is doing (for clients to animate).

	States
	  Graze    head down, eating (the default for a calm horse)
	  Idle     standing, looking about, tail swishing
	  Wander   ambling to another spot in its home area
	  Alert    a player is near: stops, lifts its head and watches them
	  Flee     bolts away from a threat (a running player, gunfire), then trots it off
	  Return   heads back to its home area
	  Follow   comes to its owner's whistle
	  Hold     stands still (being mounted)

	senses = {
		Now, Position (Vector3), Heading (yaw), Speed,
		Threat = { Position, Speed, Distance }?   nearest player (and how fast they're moving)
		Gunshot = Vector3?                          a gunshot heard this tick
		Whistle = Vector3?                          owner's position when called
		Owner = Vector3?                            owner's position (for Follow)
		Home = Vector3, HomeRadius, Wild (bool)
		Clear(direction) -> number                  free distance ahead in a direction
		Walkable(point) -> boolean                  ground there is fine for a horse
	}
]]

local Brain = {}
Brain.__index = Brain

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function yawDirection(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function Brain.new(temperament, rng: Random)
	local self = setmetatable({}, Brain)
	self.Temperament = temperament
	self.Rng = rng
	self.State = "Graze"
	self.Until = rng:NextNumber(3, 10)
	self.Target = nil :: Vector3?
	self.Away = nil :: Vector3?
	self.StuckTime = 0
	self.LastProgress = nil :: Vector3?
	self.LastProgressAt = 0
	self.Spooked = 0
	self.LookAt = nil :: Vector3?
	return self
end

function Brain:Set(state: string, now: number, duration: number?)
	self.State = state
	self.Until = now + (duration or 5)
	self.StuckTime = 0
	self.LastProgress = nil
end

-- Random reachable point in the home area.
local function pickSpot(self, senses): Vector3?
	for _ = 1, 8 do
		local angle = self.Rng:NextNumber(0, math.pi * 2)
		local radius = senses.HomeRadius * math.sqrt(self.Rng:NextNumber(0.05, 1))
		local point = senses.Home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if senses.Walkable(point) then
			return point
		end
	end
	return nil
end

-- Steers towards `direction`, bending around obstacles found by senses.Clear.
local function avoid(senses, direction: Vector3, lookAhead: number): Vector3
	local dir = flat(direction)
	if dir.Magnitude < 1e-3 then
		return dir
	end
	dir = dir.Unit
	if senses.Clear(dir) >= lookAhead then
		return dir
	end
	local best, bestScore = dir, -math.huge
	for _, angle in { 0.45, -0.45, 0.9, -0.9, 1.4, -1.4, 2.0, -2.0 } do
		local rotated = CFrame.Angles(0, angle, 0):VectorToWorldSpace(dir)
		local free = senses.Clear(rotated)
		local score = math.min(free, lookAhead) - math.abs(angle) * 1.5
		if score > bestScore then
			best, bestScore = rotated, score
		end
	end
	return best
end

local function towards(senses, point: Vector3, lookAhead: number): Vector3
	return avoid(senses, point - senses.Position, lookAhead)
end

-- Returns command, pose ({ Graze, Alert, LookAt }).
function Brain:Update(senses)
	local now = senses.Now
	local t = self.Temperament
	local position = senses.Position
	local command = { Gait = 0 }
	local pose = { Graze = false, Alert = false, LookAt = nil :: Vector3? }

	-- Reactions that interrupt anything (except being held for mounting) -------------------
	if self.State ~= "Hold" then
		if senses.Gunshot and senses.Wild then
			local distance = (senses.Gunshot - position).Magnitude
			if distance < t.GunshotSpookRadius then
				self.Away = senses.Gunshot
				self:Set("Flee", now, self.Rng:NextNumber(5, 8))
			end
		elseif senses.Gunshot and not senses.Wild and (senses.Gunshot - position).Magnitude < 30 then
			-- tamed horses shy away a few strides, then settle
			self.Away = senses.Gunshot
			self:Set("Flee", now, 1.6)
		end
		local threat = senses.Threat
		if threat and senses.Wild and self.State ~= "Flee" then
			if threat.Distance < t.SpookRadius and threat.Speed > 14 then
				self.Away = threat.Position
				self:Set("Flee", now, self.Rng:NextNumber(4.5, 7))
			elseif threat.Distance < t.AlertRadius and self.State ~= "Alert" then
				self:Set("Alert", now, self.Rng:NextNumber(3, 6))
			end
		end
		if senses.Whistle and not senses.Wild then
			self:Set("Follow", now, 40)
		end
	end

	local state = self.State
	if state == "Hold" then
		command.Gait = 0
	elseif state == "Graze" or state == "Idle" then
		pose.Graze = state == "Graze"
		if now >= self.Until then
			local roll = self.Rng:NextNumber()
			if (position - senses.Home).Magnitude > senses.HomeRadius * 1.1 then
				self:Set("Return", now, 30)
			elseif roll < 0.45 then
				self.Target = pickSpot(self, senses)
				self:Set(if self.Target then "Wander" else "Idle", now, 20)
			elseif roll < 0.75 then
				self:Set("Graze", now, self.Rng:NextNumber(5, 14))
			else
				self:Set("Idle", now, self.Rng:NextNumber(3, 7))
			end
		end
	elseif state == "Wander" or state == "Return" then
		local target = if state == "Return" then senses.Home else self.Target
		if not target then
			self:Set("Idle", now, 3)
		else
			local offset = flat(target - position)
			local arrive = if state == "Return" then senses.HomeRadius * 0.5 else 3
			if offset.Magnitude < arrive or now >= self.Until then
				self:Set(if self.Rng:NextNumber() < 0.6 then "Graze" else "Idle", now, self.Rng:NextNumber(4, 12))
			else
				command.Direction = towards(senses, target, 9)
				command.Gait = if state == "Return" and offset.Magnitude > 60 then 2 else 1
			end
		end
	elseif state == "Alert" then
		local threat = senses.Threat
		pose.Alert = true
		if threat then
			pose.LookAt = threat.Position
			-- turn to face them without walking
			local facing = flat(threat.Position - position)
			if facing.Magnitude > 1 and facing.Unit:Dot(yawDirection(senses.Heading)) < 0.6 then
				command.Direction = facing.Unit
				command.Gait = 0
			end
		end
		if now >= self.Until or not threat or threat.Distance > t.AlertRadius * 1.2 then
			self:Set(if self.Rng:NextNumber() < 0.5 then "Graze" else "Idle", now, self.Rng:NextNumber(3, 8))
		end
	elseif state == "Flee" then
		local away = flat(position - (self.Away or position))
		if away.Magnitude < 1 then
			away = yawDirection(senses.Heading)
		end
		-- run away, but curve back towards home if we're getting far from it
		local home = flat(senses.Home - position)
		local blend = math.clamp((home.Magnitude - senses.HomeRadius * 2) / (senses.HomeRadius * 3), 0, 0.8)
		local direction = away.Unit:Lerp(if home.Magnitude > 1 then home.Unit else away.Unit, blend)
		command.Direction = avoid(senses, direction, 16)
		local remaining = self.Until - now
		command.Gait = if remaining > 1.5 then 4 elseif remaining > 0 then 2 else 1
		if not senses.Wild and remaining < 1.6 then
			command.Gait = 2
		end
		if remaining <= 0 then
			self:Set(if senses.Wild then "Return" else "Idle", now, if senses.Wild then 40 else 4)
		end
	elseif state == "Follow" then
		local owner = senses.Owner
		if not owner or now >= self.Until then
			self:Set("Idle", now, 5)
		else
			local offset = flat(owner - position)
			local distance = offset.Magnitude
			if distance < 7 then
				pose.LookAt = owner
				self:Set("Idle", now, 8)
			else
				command.Direction = towards(senses, owner, 12)
				command.Gait = if distance > 60 then 4 elseif distance > 22 then 3 elseif distance > 12 then 2 else 1
			end
		end
	end

	-- Stuck? pick something else to do (the service teleports horses that stay stuck).
	if command.Gait > 0 then
		if self.LastProgress == nil or (position - self.LastProgress).Magnitude > 3 then
			self.LastProgress = position
			self.LastProgressAt = now
			self.StuckTime = 0
		else
			self.StuckTime = now - self.LastProgressAt
			if self.StuckTime > 3 and self.State ~= "Flee" then
				self.Target = pickSpot(self, senses)
				self:Set(if self.Target then "Wander" else "Idle", now, 12)
			end
		end
	else
		self.LastProgress = nil
	end
	self.LookAt = pose.LookAt
	return command, pose
end

-- Seconds a horse has been unable to make progress (for the service's teleport fallback).
function Brain:Stuck(): number
	return self.StuckTime
end

return Brain
