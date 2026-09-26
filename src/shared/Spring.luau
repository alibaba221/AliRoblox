--[[
	SicilyShared.Spring
	Damped spring for numbers and Vector3s. Frame-rate independent (sub-stepped).

		local s = Spring.new(0, 4, 0.8) -- initial, frequency (Hz), damping ratio (1 = no overshoot)
		s.Target = 10
		local value = s:Step(dt)
]]

local Spring = {}
Spring.__index = Spring

local MAX_STEP = 1 / 120

function Spring.new(initial, frequency: number, damping: number?)
	local self = setmetatable({}, Spring)
	self.Position = initial
	self.Velocity = initial * 0
	self.Target = initial
	self.Frequency = frequency
	self.Damping = damping or 1
	return self
end

function Spring:Step(dt: number)
	local omega = self.Frequency * 2 * math.pi
	local k = omega * omega
	local c = 2 * self.Damping * omega
	local target = self.Target
	local position = self.Position
	local velocity = self.Velocity

	local remaining = math.min(dt, 0.1)
	while remaining > 1e-6 do
		local h = math.min(remaining, MAX_STEP)
		local acceleration = (target - position) * k - velocity * c
		velocity += acceleration * h
		position += velocity * h
		remaining -= h
	end

	self.Position = position
	self.Velocity = velocity
	return position
end

function Spring:Impulse(velocity)
	self.Velocity += velocity
end

function Spring:Reset(value)
	self.Position = value
	self.Target = value
	self.Velocity = value * 0
end

-- Exponential smoothing helper: moves `current` toward `target` at `rate` per second.
function Spring.Approach(current, target, rate: number, dt: number)
	local alpha = 1 - math.exp(-rate * dt)
	return current + (target - current) * alpha
end

return Spring
