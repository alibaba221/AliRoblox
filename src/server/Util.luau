--[[
	Small server helpers shared by the Sicily modules.
]]

local Util = {}

-- Roblox renamed several yielding APIs to *Async (e.g. LoadCharacterAsync). Prefer the new
-- name when it exists and fall back to the classic one, so this works on any Studio build.
function Util.CallAsync(instance: Instance, methodName: string, ...: any): any
	local ok, method = pcall(function()
		return (instance :: any)[methodName .. "Async"]
	end)
	if not ok or typeof(method) ~= "function" then
		method = (instance :: any)[methodName]
	end
	return method(instance, ...)
end

-- Waits for `instance` to be a descendant of `ancestor` (or until timeout). Returns success.
function Util.WaitForAncestor(instance: Instance, ancestor: Instance, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not instance:IsDescendantOf(ancestor) do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.05)
	end
	return true
end

return Util
