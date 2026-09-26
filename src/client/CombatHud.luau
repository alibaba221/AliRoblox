--[[
	Combat HUD (client):
	  * Crosshair whose gap is the gun's real spread right now (it opens up while moving, riding
	    or firing fast, and tightens when you aim). It turns red over a person.
	  * Hit markers: a white tick for a hit, gold for the head, red for a kill.
	  * Ammo: the gun's name, rounds in the gun as cartridges, and the reserve.
	  * Reload progress under the crosshair, and a RELOAD hint when the gun is empty.
	  * The loadout bar pops up while switching guns.
	  * Red wedges point to whoever is shooting you.
	  * The Dead Eye meter.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatHud = {}

local CREAM = Color3.fromRGB(246, 236, 214)
local INK = Color3.fromRGB(24, 20, 18)
local GOLD = Color3.fromRGB(236, 190, 96)
local RED = Color3.fromRGB(226, 72, 58)
local MAX_PIPS = 14

local root: Frame
local crosshair: Frame
local ticks: { Frame } = {}
local dot: Frame
local marker: Frame
local markerTicks: { Frame } = {}
local reloadBar: Frame
local reloadFill: Frame
local reloadHint: TextLabel
local ammoPanel: Frame
local weaponName: TextLabel
local magLabel: TextLabel
local reserveLabel: TextLabel
local pipRow: Frame
local pips: { Frame } = {}
local weaponBar: Frame
local deadEyeFrame: Frame
local deadEyeFill: Frame
local damageRing: Frame
local damageWedges: { Frame } = {}
local damageFlash: Frame

local shownGap = 12
local crosshairAlpha = 0
local weaponBarToken = 0
local lastBarKey = ""
local nextWedge = 1

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
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function box(parent: Instance, name: string, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, size: number, font: Enum.Font, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color or CREAM
	l.Text = ""
	l.Size = UDim2.fromOffset(0, size + 4)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Parent = parent
	return l
end

local function buildCrosshair()
	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(0, 0)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = root
	for i = 1, 4 do
		local vertical = i <= 2
		local t = box(crosshair, "Tick" .. i, if vertical then UDim2.fromOffset(2, 8) else UDim2.fromOffset(8, 2), CREAM)
		stroke(t, INK, 1, 0.45)
		ticks[i] = t
	end
	dot = box(crosshair, "Dot", UDim2.fromOffset(3, 3), CREAM)
	corner(dot, 2)
	stroke(dot, INK, 1, 0.5)

	marker = Instance.new("Frame")
	marker.Name = "HitMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(0, 0)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.Parent = root
	for i = 1, 4 do
		local angle = math.rad(45 + 90 * i)
		local t = box(marker, "Tick" .. i, UDim2.fromOffset(2, 9), CREAM)
		t.Position = UDim2.fromOffset(math.cos(angle) * 11, math.sin(angle) * 11)
		t.Rotation = 45 + 90 * i + 90
		stroke(t, INK, 1, 0.5)
		markerTicks[i] = t
	end

	reloadBar = box(root, "Reload", UDim2.fromOffset(64, 4), INK)
	reloadBar.Position = UDim2.new(0.5, 0, 0.5, 30)
	reloadBar.BackgroundTransparency = 0.4
	reloadBar.Visible = false
	corner(reloadBar, 2)
	reloadFill = Instance.new("Frame")
	reloadFill.Name = "Fill"
	reloadFill.BorderSizePixel = 0
	reloadFill.BackgroundColor3 = CREAM
	reloadFill.Size = UDim2.fromScale(0, 1)
	reloadFill.Parent = reloadBar
	corner(reloadFill, 2)

	reloadHint = text(root, "ReloadHint", 14, Enum.Font.GothamBold, CREAM)
	reloadHint.AnchorPoint = Vector2.new(0.5, 0)
	reloadHint.Position = UDim2.new(0.5, 0, 0.5, 26)
	reloadHint.TextStrokeTransparency = 0.5
	reloadHint.Visible = false
end

local function buildAmmo()
	ammoPanel = Instance.new("Frame")
	ammoPanel.Name = "Ammo"
	ammoPanel.AnchorPoint = Vector2.new(1, 1)
	ammoPanel.Position = UDim2.new(1, -26, 1, -24)
	ammoPanel.AutomaticSize = Enum.AutomaticSize.XY
	ammoPanel.BackgroundColor3 = INK
	ammoPanel.BackgroundTransparency = 0.35
	ammoPanel.Visible = false
	ammoPanel.Parent = root
	corner(ammoPanel, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = ammoPanel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 4)
	layout.Parent = ammoPanel

	weaponName = text(ammoPanel, "Weapon", 13, Enum.Font.GothamBold, GOLD)
	weaponName.LayoutOrder = 1

	local counts = Instance.new("Frame")
	counts.Name = "Counts"
	counts.BackgroundTransparency = 1
	counts.AutomaticSize = Enum.AutomaticSize.XY
	counts.LayoutOrder = 2
	counts.Parent = ammoPanel
	local row = Instance.new("UIListLayout")
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Bottom
	row.Padding = UDim.new(0, 6)
	row.Parent = counts
	magLabel = text(counts, "Mag", 34, Enum.Font.GothamBlack, CREAM)
	magLabel.LayoutOrder = 1
	reserveLabel = text(counts, "Reserve", 16, Enum.Font.GothamMedium, CREAM)
	reserveLabel.TextTransparency = 0.25
	reserveLabel.LayoutOrder = 2

	pipRow = Instance.new("Frame")
	pipRow.Name = "Rounds"
	pipRow.BackgroundTransparency = 1
	pipRow.AutomaticSize = Enum.AutomaticSize.XY
	pipRow.LayoutOrder = 3
	pipRow.Parent = ammoPanel
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pipLayout.Padding = UDim.new(0, 3)
	pipLayout.Parent = pipRow
	for i = 1, MAX_PIPS do
		local p = Instance.new("Frame")
		p.Name = "Round" .. i
		p.Size = UDim2.fromOffset(5, 13)
		p.BackgroundColor3 = GOLD
		p.BorderSizePixel = 0
		p.LayoutOrder = i
		p.Parent = pipRow
		corner(p, 2)
		pips[i] = p
	end

	-- Dead Eye meter, above the ammo
	deadEyeFrame = Instance.new("Frame")
	deadEyeFrame.Name = "DeadEye"
	deadEyeFrame.BackgroundTransparency = 1
	deadEyeFrame.Size = UDim2.fromOffset(150, 18)
	deadEyeFrame.LayoutOrder = 0
	deadEyeFrame.Parent = ammoPanel
	local label = text(deadEyeFrame, "Label", 10, Enum.Font.GothamBold, CREAM)
	label.Text = "DEAD EYE"
	label.TextTransparency = 0.2
	label.Position = UDim2.fromOffset(0, 1)
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.AnchorPoint = Vector2.new(1, 0.5)
	back.Position = UDim2.fromScale(1, 0.5)
	back.Size = UDim2.fromOffset(84, 5)
	back.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
	back.BorderSizePixel = 0
	back.Parent = deadEyeFrame
	corner(back, 3)
	deadEyeFill = Instance.new("Frame")
	deadEyeFill.Name = "Fill"
	deadEyeFill.BackgroundColor3 = GOLD
	deadEyeFill.BorderSizePixel = 0
	deadEyeFill.Size = UDim2.fromScale(0.5, 1)
	deadEyeFill.Parent = back
	corner(deadEyeFill, 3)
end

local function buildWeaponBar()
	weaponBar = Instance.new("Frame")
	weaponBar.Name = "WeaponBar"
	weaponBar.AnchorPoint = Vector2.new(0.5, 1)
	weaponBar.Position = UDim2.new(0.5, 0, 1, -74)
	weaponBar.AutomaticSize = Enum.AutomaticSize.XY
	weaponBar.BackgroundTransparency = 1
	weaponBar.Visible = false
	weaponBar.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = weaponBar
end

local function buildDamage()
	damageRing = Instance.new("Frame")
	damageRing.Name = "DamageRing"
	damageRing.AnchorPoint = Vector2.new(0.5, 0.5)
	damageRing.Position = UDim2.fromScale(0.5, 0.5)
	damageRing.Size = UDim2.fromOffset(0, 0)
	damageRing.BackgroundTransparency = 1
	damageRing.Parent = root
	for i = 1, 4 do
		-- a wedge: a short bar out on a ring around the crosshair, on the shooter's side
		local bar = box(damageRing, "Wedge" .. i, UDim2.fromOffset(78, 7), RED)
		bar.BackgroundTransparency = 1
		corner(bar, 4)
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = bar
		damageWedges[i] = bar
	end
	damageFlash = Instance.new("Frame")
	damageFlash.Name = "DamageFlash"
	damageFlash.Size = UDim2.fromScale(1, 1)
	damageFlash.BackgroundColor3 = Color3.fromRGB(120, 10, 8)
	damageFlash.BackgroundTransparency = 1
	damageFlash.BorderSizePixel = 0
	damageFlash.ZIndex = 0
	damageFlash.Parent = root
	local edge = Instance.new("UIGradient")
	edge.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.85),
		NumberSequenceKeypoint.new(0.75, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
	edge.Parent = damageFlash
end

function CombatHud.Build(gui: ScreenGui)
	root = Instance.new("Frame")
	root.Name = "CombatHud"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	buildDamage()
	buildCrosshair()
	buildAmmo()
	buildWeaponBar()
end

--[[
	Called every frame by Gunplay.
	info = { Visible, Aiming, Spread (degrees), OverTarget, Def, Mag, Reserve, Reload (0..1 | nil),
	         DeadEye (meter), DeadEyeMax, DeadEyeActive, DeadEyeEnabled, Touch }
]]
function CombatHud.Update(info, dt: number)
	if not root then
		return
	end
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local fov = if camera then camera.FieldOfView else 70

	-- Crosshair
	crosshairAlpha += ((if info.Visible then 1 else 0) - crosshairAlpha) * (1 - math.exp(-14 * dt))
	crosshair.Visible = crosshairAlpha > 0.02
	if crosshair.Visible then
		local spread = math.clamp(info.Spread or 1, 0, 30)
		local gap = math.tan(math.rad(spread)) / math.tan(math.rad(fov / 2)) * viewport.Y / 2
		gap = math.clamp(gap, 4, 140)
		shownGap += (gap - shownGap) * (1 - math.exp(-20 * dt))
		local length = if info.Aiming then 7 else 9
		local color = if info.OverTarget then RED else CREAM
		local transparency = 1 - crosshairAlpha * (if info.Reload then 0.45 else 1)
		local offsets = {
			Vector2.new(0, -shownGap - length / 2),
			Vector2.new(0, shownGap + length / 2),
			Vector2.new(-shownGap - length / 2, 0),
			Vector2.new(shownGap + length / 2, 0),
		}
		for i, t in ticks do
			t.Position = UDim2.fromOffset(offsets[i].X, offsets[i].Y)
			t.Size = if i <= 2 then UDim2.fromOffset(2, length) else UDim2.fromOffset(length, 2)
			t.BackgroundColor3 = color
			t.BackgroundTransparency = transparency
		end
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = transparency
	end

	-- Reload progress / empty gun
	reloadBar.Visible = info.Visible and info.Reload ~= nil
	if info.Reload then
		reloadFill.Size = UDim2.fromScale(math.clamp(info.Reload, 0, 1), 1)
	end
	local empty = info.Visible and info.Reload == nil and info.Mag == 0
	reloadHint.Visible = empty
	if empty then
		reloadHint.Text = if (info.Reserve or 0) > 0 then (if info.Touch then "RELOAD" else "R  RELOAD") else "NO AMMO"
		reloadHint.TextColor3 = if (info.Reserve or 0) > 0 then CREAM else RED
	end

	-- Ammo panel
	local def = info.Def
	ammoPanel.Visible = info.Visible and def ~= nil
	ammoPanel.AnchorPoint = if info.Touch then Vector2.new(1, 0) else Vector2.new(1, 1)
	ammoPanel.Position = if info.Touch then UDim2.new(1, -18, 0, 70) else UDim2.new(1, -26, 1, -24)
	if def then
		weaponName.Text = string.upper(def.DisplayName)
		magLabel.Text = tostring(info.Mag or 0)
		magLabel.TextColor3 = if (info.Mag or 0) == 0 then RED else CREAM
		reserveLabel.Text = "/ " .. tostring(info.Reserve or 0)
		local magazine = def.Magazine
		pipRow.Visible = magazine <= MAX_PIPS
		for i, pip in pips do
			pip.Visible = i <= magazine
			local loaded = i <= (info.Mag or 0)
			pip.BackgroundColor3 = if loaded then GOLD else Color3.fromRGB(70, 60, 48)
			pip.BackgroundTransparency = if loaded then 0 else 0.3
		end
		-- the pips read left to right, spent rounds on the left
		for i, pip in pips do
			pip.LayoutOrder = magazine - i
		end
	end

	-- Dead Eye meter
	deadEyeFrame.Visible = info.DeadEyeEnabled == true
	if info.DeadEyeEnabled then
		local fraction = math.clamp((info.DeadEye or 0) / math.max(info.DeadEyeMax or 100, 1), 0, 1)
		deadEyeFill.Size = UDim2.fromScale(fraction, 1)
		local pulse = if info.DeadEyeActive then 0.5 + 0.5 * math.sin(os.clock() * 10) else 0
		deadEyeFill.BackgroundColor3 = GOLD:Lerp(Color3.fromRGB(255, 240, 200), pulse)
	end
end

-- "Predict" (our own raycast hit someone), "Hit", "Head", "Kill" (confirmed by the server).
function CombatHud.HitMarker(kind: string)
	if not marker then
		return
	end
	local color = if kind == "Kill" then RED elseif kind == "Head" then GOLD else CREAM
	local scale = if kind == "Kill" then 1.45 elseif kind == "Head" then 1.2 else 1
	marker.Visible = true
	for i, t in markerTicks do
		local angle = math.rad(45 + 90 * i)
		t.BackgroundColor3 = color
		t.BackgroundTransparency = if kind == "Predict" then 0.35 else 0
		t.Size = UDim2.fromOffset(2, 9 * scale)
		t.Position = UDim2.fromOffset(math.cos(angle) * 12 * scale, math.sin(angle) * 12 * scale)
		TweenService:Create(t, TweenInfo.new(if kind == "Kill" then 0.55 else 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(math.cos(angle) * 15 * scale, math.sin(angle) * 15 * scale),
		}):Play()
	end
end

-- Took damage from a shot fired at `from`.
function CombatHud.Damaged(from: Vector3, amount: number)
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return
	end
	local offset = camera.CFrame:VectorToObjectSpace(from - camera.CFrame.Position)
	local angle = math.deg(math.atan2(offset.X, -offset.Z)) -- 0 = ahead, 90 = right
	local bar = damageWedges[nextWedge]
	nextWedge = nextWedge % #damageWedges + 1
	local radians = math.rad(angle)
	bar.Position = UDim2.fromOffset(math.sin(radians) * 118, -math.cos(radians) * 118)
	bar.Rotation = angle
	bar.BackgroundTransparency = 0.05
	TweenService:Create(bar, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	damageFlash.BackgroundTransparency = 1 - math.clamp(amount / 70, 0.18, 0.5)
	TweenService:Create(damageFlash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

-- The loadout bar while switching. loadout = { { Id, Name } }, current = id.
function CombatHud.ShowWeapons(loadout, current: string?, touch: boolean)
	if not weaponBar then
		return
	end
	local key = table.concat((function()
		local ids = {}
		for _, entry in loadout do
			table.insert(ids, entry.Id)
		end
		return ids
	end)(), ",") .. "|" .. tostring(current)
	if key ~= lastBarKey then
		lastBarKey = key
		for _, child in weaponBar:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, entry in loadout do
			local selected = entry.Id == current
			local slot = Instance.new("Frame")
			slot.Name = entry.Id
			slot.LayoutOrder = i
			slot.AutomaticSize = Enum.AutomaticSize.XY
			slot.BackgroundColor3 = if selected then CREAM else INK
			slot.BackgroundTransparency = if selected then 0.05 else 0.35
			slot.Parent = weaponBar
			corner(slot, 8)
			local pad = Instance.new("UIPadding")
			pad.PaddingTop = UDim.new(0, 6)
			pad.PaddingBottom = UDim.new(0, 6)
			pad.PaddingLeft = UDim.new(0, 10)
			pad.PaddingRight = UDim.new(0, 10)
			pad.Parent = slot
			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
			layout.Padding = UDim.new(0, 6)
			layout.Parent = slot
			if not touch then
				local number = text(slot, "Key", 12, Enum.Font.GothamBlack, if selected then INK else GOLD)
				number.Text = tostring(i)
				number.LayoutOrder = 1
			end
			local name = text(slot, "Name", 13, Enum.Font.GothamMedium, if selected then INK else CREAM)
			name.Text = entry.Name
			name.LayoutOrder = 2
		end
	end
	weaponBar.Visible = true
	weaponBarToken += 1
	local token = weaponBarToken
	task.delay(2, function()
		if token == weaponBarToken then
			weaponBar.Visible = false
		end
	end)
end

return CombatHud
