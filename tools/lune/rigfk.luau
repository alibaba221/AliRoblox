--[[
	Forward kinematics for offline tests: poses a built model from a table of Motor6D transforms
	(Lune can't run Roblox's physics/animation, so we place the parts ourselves) and exports the
	visible parts in the preview renderer's format.
]]

local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local RigFK = {}

-- Captures the rest pose: joints (Motor6D) and welded decorations (WeldConstraint offsets).
function RigFK.Capture(model)
	local rig = { Model = model, Motors = {}, Welds = {}, Root = model.PrimaryPart }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(rig.Motors, { Name = d.Name, Part0 = d.Part0, Part1 = d.Part1, C0 = d.C0, C1 = d.C1 })
		elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 then
			table.insert(rig.Welds, { Part0 = d.Part0, Part1 = d.Part1, Offset = d.Part0.CFrame:Inverse() * d.Part1.CFrame })
		end
	end
	return rig
end

-- Returns { [BasePart] = CFrame } for the root placed at rootCFrame with the given transforms.
function RigFK.Pose(rig, rootCFrame, transforms, extra)
	local cfs = { [rig.Root] = rootCFrame }
	for part, cf in extra or {} do
		cfs[part] = cf
	end
	local pending = table.clone(rig.Motors)
	local progress = true
	while #pending > 0 and progress do
		progress = false
		for i = #pending, 1, -1 do
			local m = pending[i]
			local base = cfs[m.Part0]
			if base then
				local t = transforms[m.Name] or CFrame.new()
				cfs[m.Part1] = base * m.C0 * t * m.C1:Inverse()
				table.remove(pending, i)
				progress = true
			end
		end
	end
	progress = true
	local welds = table.clone(rig.Welds)
	while #welds > 0 and progress do
		progress = false
		for i = #welds, 1, -1 do
			local w = welds[i]
			local base = cfs[w.Part0]
			if base then
				cfs[w.Part1] = base * w.Offset
				table.remove(welds, i)
				progress = true
			end
		end
	end
	return cfs
end

local function shapeOf(part)
	if part.ClassName == "Part" then
		return part.Shape.Name
	end
	return part.ClassName
end

-- Appends the visible parts (at their posed CFrames) to `out` in the preview format.
function RigFK.Emit(out, cfs, overrides)
	for part, cf in cfs do
		if part.Transparency < 0.99 then
			local c = part.Color
			local k = shapeOf(part)
			local size = { part.Size.X, part.Size.Y, part.Size.Z }
			if part.Name == "Head" and part:FindFirstChildOfClass("SpecialMesh") then
				k = "MeshHead"
				size = { 1.25, 1.25, 1.25 }
			end
			if overrides and overrides[part] then
				c = overrides[part]
			end
			table.insert(out, {
				k = k,
				s = size,
				cf = { cf:GetComponents() },
				c = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) },
				m = part.Material.Name,
				t = part.Transparency,
			})
		end
	end
end

return RigFK
