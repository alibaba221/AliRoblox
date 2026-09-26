--[[
	Part-building kit used by every town module. All parts are anchored, CanTouch=false and
	smooth-surfaced. Flags control collision/shadows:
	  Kit.SOLID  - walls, floors, props you bump into (default)
	  Kit.DECO   - visible trim that shouldn't snag the player or the camera
	  Kit.DETAIL - tiny trim: no collision and no shadow (cheap)
]]

local Kit = {}
Kit.__index = Kit

Kit.SOLID = { Collide = true }
Kit.DECO = { Collide = false }
Kit.DETAIL = { Collide = false, Shadow = false }
Kit.GLOW = { Collide = false, Shadow = false, Name = "Bulb" }

local M = Enum.Material

function Kit.new(ctx, parent: Instance)
	return setmetatable({ Ctx = ctx, Parent = parent }, Kit)
end

-- Child kit that builds into a new Model (or Folder).
function Kit:Group(name: string, className: string?)
	local container = Instance.new(className or "Model")
	container.Name = name
	container.Parent = self.Parent
	return Kit.new(self.Ctx, container), container
end

function Kit:Part(className: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, flags)
	local f = flags or Kit.SOLID
	local part = Instance.new(className)
	if f.Shape then
		part.Shape = f.Shape
	end
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or M.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	if f.Collide == false then
		part.CanCollide = false
		part.CanQuery = f.Query == true
	end
	if f.Shadow == false then
		part.CastShadow = false
	end
	if f.Transparency then
		part.Transparency = f.Transparency
	end
	if f.Reflectance then
		part.Reflectance = f.Reflectance
	end
	if f.Name then
		part.Name = f.Name
	end
	part.Parent = self.Parent
	self.Ctx:Tick()
	return part
end

function Kit:Box(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, flags): Part
	return self:Part("Part", cf, size, color, material, flags)
end

-- WedgePart: full bottom face and full back (+Z) face; the slope faces front (-Z).
function Kit:Wedge(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, flags): WedgePart
	return self:Part("WedgePart", cf, size, color, material, flags)
end

local function withShape(flags, shape)
	local f = table.clone(flags or Kit.SOLID)
	f.Shape = shape
	return f
end

-- Cylinder whose axis runs along cf's X axis.
function Kit:Cyl(cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?, flags): Part
	return self:Part(
		"Part",
		cf,
		Vector3.new(length, diameter, diameter),
		color,
		material,
		withShape(flags, Enum.PartType.Cylinder)
	)
end

-- Vertical cylinder standing on `base` (a Vector3 at the bottom centre).
function Kit:Post(base: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, flags): Part
	return self:Cyl(
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		height,
		diameter,
		color,
		material,
		flags
	)
end

function Kit:Ball(position: Vector3, diameter: number, color: Color3, material: Enum.Material?, flags): Part
	return self:Part(
		"Part",
		CFrame.new(position),
		Vector3.new(diameter, diameter, diameter),
		color,
		material,
		withShape(flags, Enum.PartType.Ball)
	)
end

-- Ellipsoid (a block with a Sphere SpecialMesh) — foliage, cushions, pads.
function Kit:Blob(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, flags): Part
	local part = self:Box(cf, size, color, material, flags or Kit.DECO)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Thin beam from p0 to p1 (wires, poles, railings).
function Kit:Beam(p0: Vector3, p1: Vector3, thickness: number, color: Color3, material: Enum.Material?, flags): Part?
	local length = (p1 - p0).Magnitude
	if length < 0.01 then
		return nil
	end
	local cf = CFrame.lookAt((p0 + p1) / 2, p1)
	return self:Box(cf, Vector3.new(thickness, thickness, length), color, material, flags or Kit.DETAIL)
end

function Kit:PointLight(part: BasePart, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = part
	return light
end

function Kit:SpotLight(part: BasePart, face: Enum.NormalId, color: Color3, range: number, brightness: number, angle: number): SpotLight
	local light = Instance.new("SpotLight")
	light.Face = face
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Angle = angle
	light.Shadows = false
	light.Parent = part
	return light
end

-- Text painted on a part face (shop signs, street names).
function Kit:Sign(part: BasePart, face: Enum.NormalId, text: string, options: { [string]: any }?)
	local o = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 40
	gui.LightInfluence = 1
	gui.MaxDistance = o.MaxDistance or 250
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = Font.fromEnum(o.Font or Enum.Font.Bodoni)
	label.TextColor3 = o.Color or Color3.fromRGB(240, 226, 196)
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	return gui
end

--[[
	Semicircular arch in a wall, built from voussoirs plus stepped spandrel fill.
	frame: CFrame at the arch centre on the springing line (X = along the wall, Y = up, Z = out of
	the wall); radius = opening radius; depth = wall thickness (centred on frame Z = -depth/2
	unless `zCenter` is given); ring = voussoir width. `halfWidth`/`top` bound the spandrel fill.
]]
function Kit:Arch(frame: CFrame, radius: number, depth: number, ring: number, color: Color3, material: Enum.Material?, options)
	local o = options or {}
	local segments = o.Segments or math.max(7, math.floor(radius * 1.6))
	local zCenter = o.ZCenter or -depth / 2
	local ringDepth = o.RingDepth or depth + 0.2
	local ringColor = o.RingColor or color
	local outer = radius + ring
	local step = math.pi / segments
	for i = 0, segments - 1 do
		local mid = (i + 0.5) * step
		local r = radius + ring / 2
		local chord = 2 * outer * math.sin(step / 2) * 1.04
		local cf = frame
			* CFrame.new(math.cos(mid) * r, math.sin(mid) * r, zCenter + (o.RingOffset or 0))
			* CFrame.Angles(0, 0, mid + math.pi / 2)
		self:Box(cf, Vector3.new(chord, ring, ringDepth), ringColor, o.RingMaterial or material, o.Flags or Kit.SOLID)
	end
	-- Spandrels: horizontal courses that never cut into the opening (course height <= ring).
	local halfWidth = o.HalfWidth or outer
	local top = o.Top or outer
	local course = math.min(ring * 0.95, 1.2)
	local y = 0
	while y < top - 1e-3 do
		local y1 = math.min(y + course, top)
		-- Reach the ring's outer edge at the top of the course; since a course is never taller
		-- than the ring, that edge is always outside the opening at the course's bottom.
		local inner = if y1 < outer then math.sqrt(outer * outer - y1 * y1) else 0
		local h = y1 - y
		if inner <= 0.01 then
			self:Box(
				frame * CFrame.new(0, y + h / 2, zCenter),
				Vector3.new(halfWidth * 2, h, depth),
				color,
				material,
				o.FillFlags or Kit.SOLID
			)
		elseif halfWidth - inner > 0.02 then
			local w = halfWidth - inner
			for _, side in { -1, 1 } do
				self:Box(
					frame * CFrame.new(side * (inner + w / 2), y + h / 2, zCenter),
					Vector3.new(w, h, depth),
					color,
					material,
					o.FillFlags or Kit.SOLID
				)
			end
		end
		y = y1
	end
end

return Kit
