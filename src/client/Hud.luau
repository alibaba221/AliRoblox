--[[
	Minimal, cinematic HUD: controls hint that adapts to keyboard / gamepad / touch, a soft
	vignette while running, an optional stamina bar and a fade-from-black on every spawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))

local Hud = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local fade: Frame
local hint: Frame?
local vignette: Frame?
local staminaBar: Frame?
local hintDismissed = false

local CREAM = Color3.fromRGB(246, 236, 214)
local INK = Color3.fromRGB(24, 20, 18)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font
	l.TextColor3 = CREAM
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, size + 6)
	l.Parent = parent
	return l
end

local function keyRow(parent: Instance, key: string, action: string, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = action
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromOffset(0, 26)
	row.LayoutOrder = order
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	local cap = Instance.new("TextLabel")
	cap.Name = "Key"
	cap.BackgroundColor3 = CREAM
	cap.BackgroundTransparency = 0.05
	cap.TextColor3 = INK
	cap.Font = Enum.Font.GothamBold
	cap.TextSize = 12
	cap.Text = key
	cap.AutomaticSize = Enum.AutomaticSize.X
	cap.Size = UDim2.fromOffset(0, 22)
	cap.Parent = row
	corner(cap, 5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = cap

	local text = label(row, action, 15, Enum.Font.GothamMedium)
	text.Name = "Action"
	return row
end

local function buildHint()
	local frame = Instance.new("Frame")
	frame.Name = "ControlsHint"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 22, 1, -22)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = INK
	frame.BackgroundTransparency = 0.35
	frame.Visible = false
	frame.Parent = gui
	corner(frame, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	keyRow(frame, "SHIFT", "Run", 1)
	local lockKeys = Config.Movement.ShiftLockKeys
	if lockKeys ~= "" then
		local first = string.split(lockKeys, ",")[1] or ""
		local short = string.gsub(string.gsub(first, "Left", ""), "Right", "")
		keyRow(frame, string.upper(short), "Shift lock", 2)
	end
	return frame
end

local function refreshHint()
	if not hint then
		return
	end
	local lastInput = UserInputService:GetLastInputType()
	local touch = lastInput == Enum.UserInputType.Touch
	local gamepad = string.find(lastInput.Name, "Gamepad") ~= nil
	local run = hint:FindFirstChild("Run")
	local lock = hint:FindFirstChild("Shift lock")
	if run then
		local key = run:FindFirstChild("Key") :: TextLabel
		key.Text = if gamepad then "L3" else "SHIFT"
	end
	if lock then
		(lock :: Frame).Visible = not gamepad
	end
	hint.Visible = not touch and not hintDismissed and hint:GetAttribute("Shown") == true
end

local function buildVignette()
	local holder = Instance.new("Frame")
	holder.Name = "RunVignette"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 0
	holder.Parent = gui
	local edges = {
		{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 },
	}
	for i, edge in edges do
		local f = Instance.new("Frame")
		f.Name = "Edge" .. i
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.Size = edge[1]
		f.Position = edge[2]
		f.Parent = holder
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge[3]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = f
	end
	holder.Visible = false
	return holder
end

local function buildStamina()
	local back = Instance.new("Frame")
	back.Name = "Stamina"
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -34)
	back.Size = UDim2.fromOffset(220, 6)
	back.BackgroundColor3 = INK
	back.BackgroundTransparency = 0.45
	back.Parent = gui
	corner(back, 3)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = CREAM
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	corner(fill, 3)
	return back
end

function Hud.Fade(toTransparency: number, duration: number)
	local tween = TweenService:Create(
		fade,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = toTransparency }
	)
	tween:Play()
	return tween
end

function Hud.SetBlack(black: boolean)
	fade.BackgroundTransparency = if black then 0 else 1
end

function Hud.ShowHint()
	if hint and Config.Hud.ControlsHint then
		hint:SetAttribute("Shown", true)
		refreshHint()
		task.delay(14, function()
			hintDismissed = true
			refreshHint()
		end)
	end
end

function Hud.Start(movement)
	gui = Instance.new("ScreenGui")
	gui.Name = "SicilyHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundTransparency = 1
	fade.ZIndex = 50
	fade.Parent = gui

	if Config.Hud.ControlsHint then
		hint = buildHint()
		UserInputService.LastInputTypeChanged:Connect(refreshHint)
	end
	if Config.Hud.RunVignette then
		vignette = buildVignette()
	end
	if Config.Movement.Stamina.Enabled then
		staminaBar = buildStamina()
	end

	local sprintedFor = 0
	RunService.RenderStepped:Connect(function(dt)
		local state = movement.State
		local run = state.RunAmount or 0
		if vignette then
			vignette.Visible = run > 0.02
			for _, edge in vignette:GetChildren() do
				if edge:IsA("Frame") then
					edge.BackgroundTransparency = 1 - run * 0.55
				end
			end
		end
		if staminaBar then
			local stamina = Config.Movement.Stamina
			local ratio = math.clamp(state.Stamina / stamina.Max, 0, 1)
			local fill = staminaBar:FindFirstChild("Fill") :: Frame
			fill.Size = UDim2.fromScale(ratio, 1)
			staminaBar.Visible = ratio < 0.999
		end
		if hint and not hintDismissed and state.Sprinting then
			sprintedFor += dt
			if sprintedFor > 2.5 then
				hintDismissed = true
				refreshHint()
			end
		end
	end)

	-- Fade in from black on every respawn (the intro handles the very first spawn).
	player.CharacterAdded:Connect(function()
		if Config.Hud.SpawnFade and gui:GetAttribute("IntroDone") then
			Hud.SetBlack(true)
			task.delay(0.15, function()
				Hud.Fade(1, 0.9)
			end)
		end
	end)
end

function Hud.GetGui(): ScreenGui
	return gui
end

return Hud
