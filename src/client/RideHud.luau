--[[
	Riding HUD: the horse's stamina as horseshoe pips (they flash red when the horse is winded)
	and the taming meter, a bar you fill by pressing E / Y / tapping, which shakes when the
	horse bucks.
]]

local TweenService = game:GetService("TweenService")

local RideHud = {}

local CREAM = Color3.fromRGB(246, 236, 214)
local INK = Color3.fromRGB(24, 20, 18)
local GOLD = Color3.fromRGB(236, 190, 96)
local RED = Color3.fromRGB(214, 70, 60)
local PIPS = 6

local root: Frame
local pips: { Frame } = {}
local staminaFrame: Frame
local tameFrame: Frame
local tameFill: Frame
local tameGhost: Frame
local tameKey: TextLabel
local tameLabel: TextLabel
local shownProgress = 0

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = parent
end

function RideHud.Build(gui: ScreenGui)
	root = Instance.new("Frame")
	root.Name = "RideHud"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = gui

	-- stamina: a row of pips above the bottom edge
	staminaFrame = Instance.new("Frame")
	staminaFrame.Name = "Stamina"
	staminaFrame.AnchorPoint = Vector2.new(0.5, 1)
	staminaFrame.Position = UDim2.new(0.5, 0, 1, -30)
	staminaFrame.Size = UDim2.fromOffset(PIPS * 30, 26)
	staminaFrame.BackgroundTransparency = 1
	staminaFrame.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = staminaFrame
	for i = 1, PIPS do
		-- a horseshoe: an arch with its ends open at the bottom
		local shoe = Instance.new("Frame")
		shoe.Name = "Pip" .. i
		shoe.Size = UDim2.fromOffset(22, 24)
		shoe.BackgroundTransparency = 1
		shoe.Parent = staminaFrame
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundColor3 = INK
		ring.BackgroundTransparency = 0.45
		ring.Parent = shoe
		corner(ring, 11)
		stroke(ring, GOLD, 3)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0.5, 1)
		fill.Position = UDim2.fromScale(0.5, 0.86)
		fill.Size = UDim2.fromScale(0.52, 0.62)
		fill.BackgroundColor3 = GOLD
		fill.Parent = shoe
		corner(fill, 5)
		pips[i] = shoe
	end

	-- taming meter
	tameFrame = Instance.new("Frame")
	tameFrame.Name = "Taming"
	tameFrame.AnchorPoint = Vector2.new(0.5, 1)
	tameFrame.Position = UDim2.new(0.5, 0, 1, -96)
	tameFrame.Size = UDim2.fromOffset(420, 64)
	tameFrame.BackgroundTransparency = 1
	tameFrame.Visible = false
	tameFrame.Parent = root

	tameLabel = Instance.new("TextLabel")
	tameLabel.Name = "Label"
	tameLabel.BackgroundTransparency = 1
	tameLabel.Size = UDim2.new(1, 0, 0, 24)
	tameLabel.Font = Enum.Font.GothamBold
	tameLabel.TextSize = 18
	tameLabel.TextColor3 = CREAM
	tameLabel.Text = "CALM THE HORSE"
	tameLabel.Parent = tameFrame
	local shadow = Instance.new("UIStroke")
	shadow.Color = INK
	shadow.Thickness = 1.5
	shadow.Transparency = 0.3
	shadow.Parent = tameLabel

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 30)
	bar.Size = UDim2.new(1, -70, 0, 18)
	bar.BackgroundColor3 = INK
	bar.BackgroundTransparency = 0.3
	bar.ClipsDescendants = true
	bar.Parent = tameFrame
	corner(bar, 9)
	stroke(bar, CREAM, 2, 0.2)
	tameGhost = Instance.new("Frame")
	tameGhost.Name = "Ghost"
	tameGhost.BackgroundColor3 = RED
	tameGhost.BackgroundTransparency = 0.35
	tameGhost.Size = UDim2.fromScale(0.3, 1)
	tameGhost.Parent = bar
	corner(tameGhost, 9)
	tameFill = Instance.new("Frame")
	tameFill.Name = "Fill"
	tameFill.BackgroundColor3 = GOLD
	tameFill.Size = UDim2.fromScale(0.3, 1)
	tameFill.Parent = bar
	corner(tameFill, 9)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(214, 150, 70), Color3.fromRGB(250, 222, 140))
	gradient.Parent = tameFill

	tameKey = Instance.new("TextLabel")
	tameKey.Name = "Key"
	tameKey.AnchorPoint = Vector2.new(0, 0.5)
	tameKey.Position = UDim2.new(1, -54, 0, 39)
	tameKey.Size = UDim2.fromOffset(40, 32)
	tameKey.BackgroundColor3 = CREAM
	tameKey.TextColor3 = INK
	tameKey.Font = Enum.Font.GothamBlack
	tameKey.TextSize = 18
	tameKey.Text = "E"
	tameKey.Parent = tameFrame
	corner(tameKey, 7)
end

function RideHud.SetVisible(visible: boolean)
	if root then
		root.Visible = visible
	end
end

-- stamina 0..1 of the horse, winded = can't gallop right now
function RideHud.SetStamina(fraction: number, winded: boolean, clock: number)
	for i, shoe in pips do
		local fill = shoe:FindFirstChild("Fill") :: Frame
		local ring = shoe:FindFirstChild("Ring") :: Frame
		local stroke_ = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
		local k = math.clamp(fraction * PIPS - (i - 1), 0, 1)
		fill.Size = UDim2.fromScale(0.52, 0.62 * k)
		local flash = winded and math.sin(clock * 12) > 0
		fill.BackgroundColor3 = if winded then RED else GOLD
		stroke_.Color = if flash then RED else GOLD
	end
	staminaFrame.Visible = true
end

--[[
	progress 0..1 (predicted), serverProgress 0..1 (authoritative, drawn as the red ghost),
	intensity 0..1 of the current struggle (shakes the meter), key = key label.
]]
function RideHud.SetTaming(active: boolean, progress: number?, intensity: number?, key: string?, clock: number?)
	if not tameFrame then
		return
	end
	tameFrame.Visible = active
	if not active then
		return
	end
	local p = math.clamp(progress or 0, 0, 1)
	shownProgress += (p - shownProgress) * 0.35
	tameFill.Size = UDim2.fromScale(shownProgress, 1)
	tameGhost.Size = UDim2.fromScale(math.max(shownProgress, p), 1)
	local shake = (intensity or 0) * 6
	local t = clock or 0
	tameFrame.Position = UDim2.new(0.5, math.sin(t * 43) * shake, 1, -96 + math.cos(t * 37) * shake * 0.5)
	tameKey.Text = key or "E"
	tameLabel.Text = if p > 0.8 then "ALMOST THERE…" elseif (intensity or 0) > 0.5 then "HOLD ON!" else "CALM THE HORSE"
	tameLabel.TextColor3 = if p < 0.18 then RED else CREAM
end

-- Pulse the key cap when the player presses it.
function RideHud.Pulse()
	if not tameKey then
		return
	end
	tameKey.Size = UDim2.fromOffset(48, 38)
	tameKey.BackgroundColor3 = GOLD
	TweenService:Create(tameKey, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(40, 32),
		BackgroundColor3 = CREAM,
	}):Play()
end

return RideHud
