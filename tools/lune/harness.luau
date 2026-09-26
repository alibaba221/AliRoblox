--[[
	Offline harness: loads the Rojo-built place in Lune and lets scripts `require` its
	ModuleScripts exactly like Roblox does. Engine methods Lune doesn't have are polyfilled.
	Property writes are validated by Lune against Roblox's reflection database, so a typo'd
	property, enum or wrong value type fails here instead of in Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = {}

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	if not child then
		error("WaitForChild would hang: " .. tostring(name) .. " under " .. self:GetFullName())
	end
	return child
end)

-- Minimal stand-in for Roblox's Random (deterministic LCG; good enough for tests).
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	return setmetatable({ State = (math.floor(seed or os.clock() * 1e6) % 2147483646) + 1 }, Random)
end
function Random:_next(): number
	self.State = (self.State * 48271) % 2147483647
	return self.State / 2147483647
end
function Random:NextNumber(low: number?, high: number?): number
	local a, b = low or 0, high or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(low: number, high: number): number
	return math.min(high, low + math.floor(self:_next() * (high - low + 1)))
end
Harness.Random = Random

function Harness.load(placePath: string)
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local cache = {}
	local loading = {}
	local requireModule

	local function makeEnv(scriptInstance)
		return {
			script = scriptInstance,
			game = game,
			workspace = game:GetService("Workspace"),
			require = function(target)
				return requireModule(target)
			end,
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			BrickColor = roblox.BrickColor,
			Enum = roblox.Enum,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			NumberRange = roblox.NumberRange,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			Region3 = roblox.Region3,
			Font = roblox.Font,
			Random = Random,
			task = task,
			typeof = typeof,
			warn = function(...)
				print("[warn]", ...)
			end,
		}
	end

	requireModule = function(moduleScript)
		if cache[moduleScript] ~= nil then
			return cache[moduleScript]
		end
		assert(typeof(moduleScript) == "Instance" and moduleScript:IsA("ModuleScript"), "require expects a ModuleScript")
		assert(not loading[moduleScript], "cyclic require: " .. moduleScript:GetFullName())
		loading[moduleScript] = true
		local chunk = luau.load(moduleScript.Source, {
			debugName = moduleScript:GetFullName(),
			environment = makeEnv(moduleScript),
		})
		local result = chunk()
		loading[moduleScript] = nil
		cache[moduleScript] = result
		return result
	end

	return game, requireModule
end

return Harness
