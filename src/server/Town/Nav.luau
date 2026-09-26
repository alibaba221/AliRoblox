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

local function insideAny(rects, x: number, z: number): boolean
	for _, r in rects do
		if x >= r.X0 and x <= r.X1 and z >= r.Z0 and z <= r.Z1 then
			return true
		end
	end
	return false
end

-- On the paved area with `margin` clearance, treating adjoining streets as one surface.
local function onPaving(rects, x: number, z: number, margin: number): boolean
	return insideAny(rects, x, z)
		and insideAny(rects, x + margin, z)
		and insideAny(rects, x - margin, z)
		and insideAny(rects, x, z + margin)
		and insideAny(rects, x, z - margin)
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
		if not onPaving(rects, p.X, p.Z, 1.2) or blocked(info, p, 0.8) then
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

	local function addNode(x: number, z: number, force: boolean?)
		local p = Vector3.new(x, G, z)
		if not onPaving(rects, x, z, 1.4) or blocked(info, p, 1) then
			return
		end
		for _, existing in nodes do
			if (existing - p).Magnitude < (if force then 2.5 else 5) then
				return
			end
		end
		table.insert(nodes, p)
	end

	-- Junctions first (where a north-south street meets or crosses an east-west one).
	for _, a in Plan.Streets do
		if a.X1 - a.X0 < a.Z1 - a.Z0 then
			for _, b in Plan.Streets do
				if b.X1 - b.X0 > b.Z1 - b.Z0 then
					local x = (a.X0 + a.X1) / 2
					local z = (b.Z0 + b.Z1) / 2
					if x >= b.X0 and x <= b.X1 and z >= a.Z0 - 20 and z <= a.Z1 + 20 then
						addNode(x, z, true)
					end
				end
			end
		end
	end
	-- Street centre-lines (slightly off-centre so passers-by don't walk in single file).
	for _, street in Plan.Streets do
		local w, d = street.X1 - street.X0, street.Z1 - street.Z0
		if w < d then
			local x = (street.X0 + street.X1) / 2
			local z = street.Z0 + 3
			while z <= street.Z1 - 3 do
				addNode(x + ctx.Rng:Range(-1, 1), z)
				z += 12
			end
			addNode(x, street.Z1 - 3)
		else
			local z = (street.Z0 + street.Z1) / 2
			local x = street.X0 + 3
			while x <= street.X1 - 3 do
				addNode(x, z + ctx.Rng:Range(-1, 1))
				x += 12
			end
			addNode(street.X1 - 3, z)
		end
	end
	-- Piazza grid
	local p = Plan.Piazza
	local z = p.Z0 + 8
	while z <= p.Z1 - 5 do
		local x = p.X0 + 8
		while x <= p.X1 - 8 do
			addNode(x + ctx.Rng:Range(-2, 2), z + ctx.Rng:Range(-2, 2))
			x += 13
		end
		z += 13
	end

	local edges = {}
	for i = 1, #nodes do
		edges[i] = {}
	end
	local function link(i: number, j: number)
		table.insert(edges[i], j)
		table.insert(edges[j], i)
	end
	for i = 1, #nodes do
		for j = i + 1, #nodes do
			if (nodes[i] - nodes[j]).Magnitude < 22 and clearLine(info, rects, nodes[i], nodes[j]) then
				link(i, j)
			end
		end
	end

	-- Stitch any islands to the main network with the shortest clear connection available.
	local function components()
		local label, count = {}, 0
		for s = 1, #nodes do
			if not label[s] then
				count += 1
				local stack = { s }
				label[s] = count
				while #stack > 0 do
					local x = table.remove(stack)
					for _, y in edges[x] do
						if not label[y] then
							label[y] = count
							table.insert(stack, y)
						end
					end
				end
			end
		end
		return label, count
	end
	for _ = 1, 40 do
		local label, count = components()
		if count <= 1 then
			break
		end
		local merged = false
		local bestI, bestJ, bestD = nil, nil, 45
		for i = 1, #nodes do
			for j = i + 1, #nodes do
				if label[i] ~= label[j] then
					local d = (nodes[i] - nodes[j]).Magnitude
					if d < bestD and clearLine(info, rects, nodes[i], nodes[j]) then
						bestI, bestJ, bestD = i, j, d
					end
				end
			end
		end
		if bestI and bestJ then
			link(bestI, bestJ)
			merged = true
		end
		if not merged then
			break
		end
	end

	-- Keep only the largest connected network.
	local label, count = components()
	local sizes = {}
	for i = 1, #nodes do
		sizes[label[i]] = (sizes[label[i]] or 0) + 1
	end
	local main, mainSize = 1, 0
	for c = 1, count do
		if (sizes[c] or 0) > mainSize then
			main, mainSize = c, sizes[c]
		end
	end
	local remap, finalNodes = {}, {}
	for i = 1, #nodes do
		if label[i] == main then
			table.insert(finalNodes, nodes[i])
			remap[i] = #finalNodes
		end
	end
	local finalEdges = {}
	for i = 1, #finalNodes do
		finalEdges[i] = {}
	end
	for i = 1, #nodes do
		if remap[i] then
			for _, j in edges[i] do
				if remap[j] then
					table.insert(finalEdges[remap[i]], remap[j])
				end
			end
		end
	end
	info.Nav = { Nodes = finalNodes, Edges = finalEdges }
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
