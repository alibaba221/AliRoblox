--[[
	Walking graph for townsfolk: nodes along street centre-lines and across the piazza, linked
	when the straight walk between them stays on paving and clear of props.
]]

local Plan = require(script.Parent.Plan)

local Nav = {}

local function walkableRects()
	local rects = { Plan.Piazza }
	for _, street in Plan.Streets do
		table.insert(rects, street)
	end
	return rects
end

local function onPaving(rects, x: number, z: number, margin: number): boolean
	for _, r in rects do
		if x >= r.X0 + margin and x <= r.X1 - margin and z >= r.Z0 + margin and z <= r.Z1 - margin then
			return true
		end
	end
	return false
end

local function blocked(info, point: Vector3, pad: number): boolean
	for _, b in info.Blocked do
		local dx, dz = point.X - b.Center.X, point.Z - b.Center.Z
		if dx * dx + dz * dz < (b.Radius + pad) ^ 2 then
			return true
		end
	end
	return false
end

local function clearLine(info, rects, a: Vector3, b: Vector3): boolean
	local distance = (b - a).Magnitude
	local steps = math.max(1, math.ceil(distance / 2))
	for i = 0, steps do
		local p = a:Lerp(b, i / steps)
		if not onPaving(rects, p.X, p.Z, 1.5) or blocked(info, p, 1.2) then
			return false
		end
	end
	return true
end

function Nav.Build(ctx)
	local info = ctx.Info
	local rects = walkableRects()
	local G = ctx.G
	local nodes = {}

	local function addNode(x: number, z: number)
		local p = Vector3.new(x, G, z)
		if onPaving(rects, x, z, 1.8) and not blocked(info, p, 1.5) then
			for _, existing in nodes do
				if (existing - p).Magnitude < 5 then
					return
				end
			end
			table.insert(nodes, p)
		end
	end

	-- Street centre-lines (slightly off-centre so passers-by don't walk in single file).
	for _, street in Plan.Streets do
		local w, d = street.X1 - street.X0, street.Z1 - street.Z0
		if w < d then
			local x = (street.X0 + street.X1) / 2
			local z = street.Z0 + 4
			while z <= street.Z1 - 4 do
				addNode(x + ctx.Rng:Range(-1.2, 1.2), z)
				z += 16
			end
		else
			local z = (street.Z0 + street.Z1) / 2
			local x = street.X0 + 4
			while x <= street.X1 - 4 do
				addNode(x, z + ctx.Rng:Range(-1.2, 1.2))
				x += 16
			end
		end
	end
	-- Piazza grid
	local p = Plan.Piazza
	local z = p.Z0 + 8
	while z <= p.Z1 - 6 do
		local x = p.X0 + 8
		while x <= p.X1 - 8 do
			addNode(x + ctx.Rng:Range(-2, 2), z + ctx.Rng:Range(-2, 2))
			x += 15
		end
		z += 15
	end

	local edges = {}
	for i = 1, #nodes do
		edges[i] = {}
	end
	for i = 1, #nodes do
		for j = i + 1, #nodes do
			local distance = (nodes[i] - nodes[j]).Magnitude
			if distance < 24 and clearLine(info, rects, nodes[i], nodes[j]) then
				table.insert(edges[i], j)
				table.insert(edges[j], i)
			end
		end
	end
	info.Nav = { Nodes = nodes, Edges = edges }
end

function Nav.Encode(nav): string
	local nodeParts = {}
	for _, p in nav.Nodes do
		table.insert(nodeParts, string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z))
	end
	local edgeParts = {}
	for i, list in nav.Edges do
		for _, j in list do
			if j > i then
				table.insert(edgeParts, i .. "," .. j)
			end
		end
	end
	return table.concat(nodeParts, ";") .. "|" .. table.concat(edgeParts, ";")
end

function Nav.Decode(text: string)
	local nodes, edges = {}, {}
	local nodeText, edgeText = string.match(text, "^(.-)|(.*)$")
	if not nodeText then
		return { Nodes = nodes, Edges = edges }
	end
	for x, y, z in string.gmatch(nodeText, "(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)") do
		table.insert(nodes, Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number))
		edges[#nodes] = {}
	end
	for a, b in string.gmatch(edgeText, "(%d+),(%d+)") do
		local i, j = tonumber(a) :: number, tonumber(b) :: number
		if edges[i] and edges[j] then
			table.insert(edges[i], j)
			table.insert(edges[j], i)
		end
	end
	return { Nodes = nodes, Edges = edges }
end

return Nav
