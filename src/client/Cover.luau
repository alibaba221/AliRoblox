--[[
	Cover (client): press C / R1 / COVER next to a wall, crate or low wall.

	  * Low cover (lower than Config.Combat.Cover.LowHeight above your feet): you crouch behind it
	    and rise to shoot over it while aiming.
	  * High cover: you stand close against it; shoot from its edge.
	  * Move along the cover with the move keys (you stop at its end). Push away from it, run,
	    jump or press the key again to leave it.

	Other players see the crouch too (the server sets the "Cover" attribute on the character).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))

local Cover = {}

local settings = Config.Combat.Cover
local WAIST = -0.7 -- ray height below the HumanoidRootPart's centre
local STAND_OFF = 1.55 -- how far from the wall the root stays

local movement = nil
local request: ((string?) -> ())? = nil
local state = {
	Kind = nil :: string?,
	Point = Vector3.zero,
	Normal = Vector3.new(0, 0, 1),
	Character = nil :: Model?,
	Root = nil :: BasePart?,
	AwayFor = 0,
	LostFor = 0,
}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.zero
end

local function solid(part: Instance): boolean
	if not part:IsA("BasePart") then
		return false
	end
	if part:IsA("Terrain") then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false -- people and horses aren't cover
	end
	return part.CanCollide and part.Transparency < 0.9
end

-- Is there a wall in `direction` from `origin` within `distance`? Returns the hit.
local function wallAt(origin: Vector3, direction: Vector3, distance: number): RaycastResult?
	local hit = Workspace:Raycast(origin, direction * distance, params)
	if hit and solid(hit.Instance) and math.abs(hit.Normal.Y) < 0.4 then
		return hit
	end
	return nil
end

--[[
	Looks for cover in `direction` (flat, unit) from the character. Returns
	{ Point, Normal (flat, away from the wall), Kind = "Low" | "High" } or nil.
]]
function Cover.Probe(character: Model, root: BasePart, direction: Vector3)
	if not settings.Enabled or direction.Magnitude < 0.5 then
		return nil
	end
	params.FilterDescendantsInstances = { character }
	local origin = root.Position + Vector3.new(0, WAIST, 0)
	local hit = wallAt(origin, direction, settings.SearchDistance)
	if not hit then
		return nil
	end
	local normal = flat(hit.Normal)
	if normal.Magnitude < 0.5 then
		return nil
	end
	-- how tall is it? look down onto it from above, just behind the face we hit
	local feet = root.Position.Y - 3
	local probeTop = feet + 9
	local above = Vector3.new(hit.Position.X, probeTop, hit.Position.Z) - normal * 0.35
	local top = Workspace:Raycast(above, Vector3.new(0, -9, 0), params)
	local height = if top then top.Position.Y - feet else 9
	if height < 2.2 then
		return nil -- too low to hide behind
	end
	return { Point = hit.Position, Normal = normal, Kind = if height < settings.LowHeight then "Low" else "High" }
end

-- Movement while in cover: slide along the wall, stay close to it, stop at its ends.
local function filter(input: Vector3): Vector3
	local root = state.Root
	if not state.Kind or not root then
		return input
	end
	local normal = state.Normal
	local tangent = Vector3.new(-normal.Z, 0, normal.X)
	local along = input:Dot(tangent)
	local move = Vector3.zero
	if math.abs(along) > 0.15 then
		local side = if along > 0 then 1 else -1
		local ahead = root.Position + Vector3.new(0, WAIST, 0) + tangent * side * 1.1
		params.FilterDescendantsInstances = { state.Character :: Model }
		if wallAt(ahead, -normal, STAND_OFF + 1.4) then
			move = tangent * along * 0.55
		end
	end
	-- keep close to the wall
	local distance = (root.Position - state.Point):Dot(normal)
	local pull = math.clamp(distance - STAND_OFF, -0.4, 1)
	move += -normal * pull * 0.9
	if move.Magnitude > 1 then
		move = move.Unit
	end
	return move
end

function Cover.Start(movementModule, requestFn: (string?) -> ())
	movement = movementModule
	request = requestFn
end

function Cover.Kind(): string?
	return state.Kind
end

-- Which way to face while in cover (toward the wall), or nil.
function Cover.FaceYaw(): number?
	if not state.Kind then
		return nil
	end
	local n = state.Normal
	return math.atan2(n.X, n.Z) -- facing -normal
end

function Cover.Exit()
	if not state.Kind then
		return
	end
	state.Kind = nil
	if movement then
		movement.SetInputFilter(nil)
	end
	local character = state.Character
	if character and character.Parent then
		character:SetAttribute("Cover", nil)
	end
	if request then
		request(nil)
	end
end

local function enter(character: Model, root: BasePart, found)
	state.Kind = found.Kind
	state.Point = found.Point
	state.Normal = found.Normal
	state.Character = character
	state.Root = root
	state.AwayFor = 0
	state.LostFor = 0
	character:SetAttribute("Cover", found.Kind)
	if movement then
		movement.SetInputFilter(filter)
	end
	if request then
		request(found.Kind)
	end
end

-- The cover key: take cover toward `look` (or where we face), or leave it.
function Cover.Toggle(character: Model, root: BasePart, look: Vector3): boolean
	if state.Kind then
		Cover.Exit()
		return true
	end
	local found = Cover.Probe(character, root, flat(look)) or Cover.Probe(character, root, flat(root.CFrame.LookVector))
	if not found then
		return false
	end
	enter(character, root, found)
	return true
end

-- Every frame: leave cover when it no longer makes sense.
function Cover.Update(dt: number, character: Model?, root: BasePart?, humanoid: Humanoid?, riding: boolean)
	if not state.Kind then
		return
	end
	if not character or character ~= state.Character or not root or not humanoid or humanoid.Health <= 0 or riding then
		Cover.Exit()
		return
	end
	state.Root = root
	-- pushing away from the wall, running or jumping leaves cover
	local input = if movement then movement.GetMoveInput() else Vector3.zero
	if input:Dot(state.Normal) > 0.7 then
		state.AwayFor += dt
	else
		state.AwayFor = 0
	end
	if state.AwayFor > 0.2 or humanoid.Jump or (movement and movement.RunHeld()) then
		Cover.Exit()
		return
	end
	-- follow the wall as we slide along it (and notice when it's gone)
	params.FilterDescendantsInstances = { character }
	local hit = wallAt(root.Position + Vector3.new(0, WAIST, 0), -state.Normal, STAND_OFF + 1.8)
	if hit then
		state.LostFor = 0
		state.Point = hit.Position
		local normal = flat(hit.Normal)
		if normal.Magnitude > 0.5 then
			state.Normal = state.Normal:Lerp(normal, math.min(1, dt * 8)).Unit
		end
	else
		state.LostFor += dt
		if state.LostFor > 0.4 then
			Cover.Exit()
		end
	end
end

return Cover
