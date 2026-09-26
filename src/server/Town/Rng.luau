--[[
	Deterministic xorshift32 random numbers, so the same seed always builds the same town
	(Roblox's Random isn't guaranteed identical across machines/engines).
]]

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number)
	local state = math.floor(math.abs(seed)) % 4294967296
	if state == 0 then
		state = 2654435769
	end
	local self = setmetatable({ State = state }, Rng)
	for _ = 1, 8 do
		self:NextInt()
	end
	return self
end

function Rng:NextInt(): number
	local x = self.State
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.State = x
	return x
end

-- Uniform in [0, 1)
function Rng:Next(): number
	return self:NextInt() / 4294967296
end

function Rng:Range(low: number, high: number): number
	return low + (high - low) * self:Next()
end

function Rng:Int(low: number, high: number): number
	return math.min(high, low + math.floor(self:Next() * (high - low + 1)))
end

function Rng:Chance(probability: number): boolean
	return self:Next() < probability
end

function Rng:Pick<T>(list: { T }): T
	return list[self:Int(1, #list)]
end

function Rng:Sign(): number
	return if self:Next() < 0.5 then -1 else 1
end

-- Independent sub-stream (so adding/removing one feature doesn't reshuffle the whole town).
function Rng:Fork(salt: number)
	return Rng.new((self:NextInt() + salt * 7919) % 4294967296)
end

return Rng
