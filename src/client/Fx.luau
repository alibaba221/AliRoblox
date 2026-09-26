--[[
	Small effects toolkit shared by horses and gunplay (client only, nothing replicates).

	Fx.EmitAt(position, preset, count, options?)  particle burst anywhere in the world
	Fx.Sound(soundId, at, options?)               one-shot 3D sound (Vector3 or Instance)
	Fx.Hearts(adornee)                            little hearts floating up (a tamed horse)
	Fx.Streak(from, to, options?)                 fast bullet streak (tracer)
	Fx.Flash(parent, color, range, duration)      short light flash
	Fx.Hole(result)                               bullet mark on a surface

	Only textures that ship with Roblox are used, so there's nothing to upload.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fx = {}

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_CORE = "rbxasset://textures/particles/explosion01_core_main.dds"

local function seq(...): NumberSequence
	local points = { ... }
	local keypoints = {}
	for i = 1, #points, 2 do
		table.insert(keypoints, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(keypoints)
end

-- Emitter presets (properties applied to a ParticleEmitter; Rate is always 0, we Emit()).
local PRESETS = {
	Dust = {
		Texture = TEX_SMOKE,
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(2, 4.5),
		SpreadAngle = Vector2.new(70, 70),
		Size = seq(0, 0.5, 1, 1.9),
		Transparency = seq(0, 0.55, 1, 1),
		Acceleration = Vector3.new(0, 1.5, 0),
		Drag = 3,
		LightInfluence = 1,
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
	},
	Puff = {
		Texture = TEX_SMOKE,
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(35, 35),
		Size = seq(0, 0.35, 1, 1.4),
		Transparency = seq(0, 0.35, 1, 1),
		Drag = 6,
		LightInfluence = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
	},
	Smoke = {
		Texture = TEX_SMOKE,
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(1.5, 4),
		SpreadAngle = Vector2.new(18, 18),
		Size = seq(0, 0.4, 1, 3.2),
		Transparency = seq(0, 0.45, 0.4, 0.7, 1, 1),
		Acceleration = Vector3.new(0, 2.2, 0),
		Drag = 2.5,
		LightInfluence = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
	},
	Sparks = {
		Texture = TEX_SPARK,
		Lifetime = NumberRange.new(0.15, 0.35),
		Speed = NumberRange.new(12, 26),
		SpreadAngle = Vector2.new(55, 55),
		Size = seq(0, 0.25, 1, 0),
		Transparency = seq(0, 0, 1, 1),
		Acceleration = Vector3.new(0, -40, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 140), Color3.fromRGB(255, 140, 60)),
	},
	Flash = {
		Texture = TEX_CORE,
		Lifetime = NumberRange.new(0.05, 0.08),
		Speed = NumberRange.new(0, 0.5),
		SpreadAngle = Vector2.new(10, 10),
		Size = seq(0, 0.9, 1, 1.6),
		Transparency = seq(0, 0, 1, 1),
		LightEmission = 1,
		LightInfluence = 0,
		Rotation = NumberRange.new(0, 360),
		Color = ColorSequence.new(Color3.fromRGB(255, 226, 170), Color3.fromRGB(255, 150, 70)),
	},
	Fire = {
		Texture = TEX_FIRE,
		Lifetime = NumberRange.new(0.04, 0.07),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(9, 9),
		Size = seq(0, 0.7, 1, 0.1),
		Transparency = seq(0, 0, 1, 1),
		LightEmission = 1,
		LightInfluence = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 236, 190), Color3.fromRGB(255, 120, 40)),
	},
	Splinters = {
		Texture = TEX_SPARK,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(50, 50),
		Size = seq(0, 0.22, 1, 0.1),
		Transparency = seq(0, 0, 1, 1),
		Acceleration = Vector3.new(0, -50, 0),
		LightInfluence = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-400, 400),
	},
	Splash = {
		Texture = TEX_SMOKE,
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(22, 22),
		Size = seq(0, 0.3, 1, 1.2),
		Transparency = seq(0, 0.2, 1, 1),
		Acceleration = Vector3.new(0, -45, 0),
		LightInfluence = 1,
		Color = ColorSequence.new(Color3.fromRGB(226, 240, 246)),
	},
}
Fx.Presets = PRESETS

local holder: Part? = nil
local emitters: { [string]: { Attachment: Attachment, Emitter: ParticleEmitter } } = {}

local function getHolder(): Part
	if holder and holder.Parent then
		return holder
	end
	local part = Instance.new("Part")
	part.Name = "SicilyFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = Workspace.CurrentCamera or Workspace
	holder = part
	table.clear(emitters)
	return part
end

local function emitterFor(preset: string)
	local existing = emitters[preset]
	if existing and existing.Emitter.Parent then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = preset
	attachment.Parent = getHolder()
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	for key, value in PRESETS[preset] do
		(emitter :: any)[key] = value
	end
	emitter.Parent = attachment
	local entry = { Attachment = attachment, Emitter = emitter }
	emitters[preset] = entry
	return entry
end

--[[
	options: Color (Color3), Direction (Vector3, default up), Scale (number), Speed (multiplier)
]]
function Fx.EmitAt(position: Vector3, preset: string, count: number, options: { [string]: any }?)
	local entry = emitterFor(preset)
	local emitter = entry.Emitter
	local o = options or {}
	local direction = o.Direction or Vector3.new(0, 1, 0)
	if direction.Magnitude < 1e-3 then
		direction = Vector3.new(0, 1, 0)
	end
	-- emitter "Top" = attachment +Y, so point +Y along the direction
	local up = direction.Unit
	local helper = if math.abs(up.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local right = helper:Cross(up).Unit
	local back = right:Cross(up)
	entry.Attachment.WorldCFrame = CFrame.fromMatrix(position, right, up, back)
	local base = PRESETS[preset]
	emitter.Color = if o.Color then ColorSequence.new(o.Color) else (base.Color or ColorSequence.new(Color3.new(1, 1, 1)))
	local scale = o.Scale or 1
	if scale ~= 1 then
		local points = {}
		for _, k in base.Size.Keypoints do
			table.insert(points, NumberSequenceKeypoint.new(k.Time, k.Value * scale))
		end
		emitter.Size = NumberSequence.new(points)
	else
		emitter.Size = base.Size
	end
	local speed = o.Speed or 1
	emitter.Speed = NumberRange.new(base.Speed.Min * speed, base.Speed.Max * speed)
	emitter:Emit(count)
end

--[[
	One-shot 3D sound. `at` is a Vector3 (a temporary attachment is used) or an Instance.
	options: Volume, Pitch, RollOff (max distance), StopAfter (seconds), TimePosition, Effects
]]
function Fx.Sound(soundId: string, at: Vector3 | Instance, options: { [string]: any }?): Sound?
	if soundId == nil or soundId == "" then
		return nil
	end
	local o = options or {}
	local parent: Instance
	if typeof(at) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = at :: Vector3
		attachment.Parent = getHolder()
		Debris:AddItem(attachment, (o.StopAfter or 3) + 0.5)
		parent = attachment
	else
		parent = at :: Instance
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = o.Volume or 0.5
	sound.PlaybackSpeed = o.Pitch or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = o.RollOffMin or 8
	sound.RollOffMaxDistance = o.RollOff or 150
	if o.TimePosition then
		sound.TimePosition = o.TimePosition
	end
	for _, effect in o.Effects or {} do
		effect:Clone().Parent = sound
	end
	sound.Parent = parent
	sound:Play()
	local life = o.StopAfter or 3
	if o.StopAfter then
		-- fade out quickly instead of cutting (clips here are trimmed stock sounds)
		task.delay(math.max(0, life - 0.08), function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(0.08), { Volume = 0 }):Play()
			end
		end)
	end
	Debris:AddItem(sound, life + 0.2)
	return sound
end

-- A short light burst (muzzle flash) parented to an attachment/part.
function Fx.Flash(parent: Instance, color: Color3, range: number, duration: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 4
	light.Shadows = false
	light.Parent = parent
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(light, duration + 0.05)
end

-- A bullet streak racing from `from` to `to` (a short glowing segment, not a laser line).
function Fx.Streak(from: Vector3, to: Vector3, options: { [string]: any }?)
	local o = options or {}
	local distance = (to - from).Magnitude
	if distance < 2 then
		return
	end
	local length = math.min(o.Length or 7, distance)
	local streak = Instance.new("Part")
	streak.Name = "Tracer"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CastShadow = false
	streak.Material = Enum.Material.Neon
	streak.Color = o.Color or Color3.fromRGB(255, 226, 170)
	streak.Transparency = o.Transparency or 0.35
	streak.Size = Vector3.new(o.Width or 0.07, o.Width or 0.07, length)
	local direction = (to - from).Unit
	streak.CFrame = CFrame.lookAt(from + direction * (length / 2), to)
	streak.Parent = getHolder()
	local speed = o.Speed or 900
	local travel = math.max(distance - length, 0)
	local duration = math.max(travel / speed, 0.03)
	TweenService:Create(streak, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to - direction * (length / 2), to + direction),
	}):Play()
	task.delay(duration, function()
		TweenService:Create(streak, TweenInfo.new(0.06), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(streak, duration + 0.15)
end

-- Small dark mark where a bullet struck (fades after a while).
function Fx.Hole(position: Vector3, normal: Vector3, surface: BasePart?)
	if not surface or not surface:IsA("BasePart") or surface.Transparency > 0.5 then
		return
	end
	local mark = Instance.new("Part")
	mark.Name = "BulletMark"
	mark.Anchored = surface.Anchored
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Shape = Enum.PartType.Cylinder
	mark.Size = Vector3.new(0.04, 0.28, 0.28)
	mark.Color = Color3.fromRGB(28, 24, 22)
	mark.Material = Enum.Material.SmoothPlastic
	mark.CFrame = CFrame.lookAt(position + normal * 0.02, position + normal * 2) * CFrame.Angles(0, math.pi / 2, 0)
	if not surface.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = surface
		weld.Part1 = mark
		weld.Parent = mark
		mark.Massless = true
	end
	mark.Parent = getHolder()
	task.delay(10, function()
		if mark.Parent then
			TweenService:Create(mark, TweenInfo.new(2), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(mark, 12.5)
end

-- Hearts made from UI shapes (no image assets): a rotated square plus two circles.
local function heart(parent: Instance, size: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(size, size)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local d = size * 0.58
	local square = Instance.new("Frame")
	square.BorderSizePixel = 0
	square.BackgroundColor3 = color
	square.Size = UDim2.fromOffset(d, d)
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = UDim2.new(0.5, 0, 0.5, size * 0.1)
	square.Rotation = 45
	square.Parent = frame
	for _, side in { -1, 1 } do
		local lobe = Instance.new("Frame")
		lobe.BorderSizePixel = 0
		lobe.BackgroundColor3 = color
		lobe.Size = UDim2.fromOffset(d, d)
		lobe.AnchorPoint = Vector2.new(0.5, 0.5)
		lobe.Position = UDim2.new(0.5, side * d * 0.36, 0.5, -size * 0.12)
		lobe.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = lobe
	end
	frame.Parent = parent
	return frame
end

function Fx.Hearts(adornee: BasePart, count: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SicilyHearts"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(220, 240)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 150
	gui.Parent = getHolder()
	local n = count or 6
	for i = 1, n do
		local size = math.random(26, 40)
		local color = if i % 2 == 0 then Color3.fromRGB(240, 70, 110) else Color3.fromRGB(255, 120, 150)
		local h = heart(gui, size, color)
		h.Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.5, 0.92)
		h.Rotation = math.random(-20, 20)
		local delay = (i - 1) * 0.12
		task.delay(delay, function()
			local tween = TweenService:Create(h, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(h.Position.X.Scale + (math.random() - 0.5) * 0.3, 0.12),
				Rotation = h.Rotation + math.random(-25, 25),
			})
			tween:Play()
			for _, child in h:GetDescendants() do
				if child:IsA("Frame") then
					TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.0), {
						BackgroundTransparency = 1,
					}):Play()
				end
			end
		end)
	end
	Debris:AddItem(gui, 3.2)
end

return Fx
