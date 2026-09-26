--[[
	Gun buttons for phones and tablets, grouped above the jump button:
	  FIRE      shoot. Drag your thumb on it to keep aiming while you fire.
	  AIM       toggles aiming (draws your gun)
	  GUN       next gun, or holster after the last one
	  RELOAD, DEAD EYE and COVER appear when they can be used.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraFX = require(script.Parent.CameraFX)

local CombatTouch = {}

local CREAM = Color3.fromRGB(246, 236, 214)
local INK = Color3.fromRGB(24, 20, 18)
local DRAG_SPEED = 0.0055 -- radians per pixel while dragging on FIRE

-- name = { label, size, offset of the centre from the bottom-right corner (small screens) }
local LAYOUT = {
	Fire = { "FIRE", 86, Vector2.new(-158, -150) },
	Aim = { "AIM", 62, Vector2.new(-62, -178) },
	Gun = { "GUN", 50, Vector2.new(-62, -258) },
	Reload = { "RELOAD", 50, Vector2.new(-248, -96) },
	DeadEye = { "DEAD\nEYE", 50, Vector2.new(-150, -252) },
	Cover = { "COVER", 50, Vector2.new(-250, -176) },
}

local root: Frame? = nil
local buttons: { [string]: TextButton } = {}
local handlers = {}
local fireTouch: InputObject? = nil
local lastPosition = Vector3.zero

local function styleButton(button: TextButton, active: boolean)
	button.BackgroundColor3 = if active then CREAM else INK
	button.TextColor3 = if active then INK else CREAM
	button.BackgroundTransparency = if active then 0.1 else 0.35
end

local function layout()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(800, 400)
	local scale = if math.min(viewport.X, viewport.Y) > 500 then 1.35 else 1
	-- big screens have a bigger jump button further in
	local shift = if scale > 1 then Vector2.new(-40, -70) else Vector2.zero
	for name, spec in LAYOUT do
		local button = buttons[name]
		if button then
			local size = spec[2] * scale
			local offset = spec[3] * scale + shift
			button.Size = UDim2.fromOffset(size, size)
			button.Position = UDim2.new(1, offset.X, 1, offset.Y)
			button.TextSize = math.floor(size * (if name == "Fire" then 0.22 else 0.2))
		end
	end
end

function CombatTouch.Build(gui: ScreenGui, callbacks)
	handlers = callbacks
	local frame = Instance.new("Frame")
	frame.Name = "CombatTouch"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Visible = false
	frame.Parent = gui
	root = frame
	for name, spec in LAYOUT do
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.Text = spec[1]
		button.Font = Enum.Font.GothamBold
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Visible = name == "Fire" or name == "Aim" or name == "Gun"
		button.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Color = CREAM
		stroke.Thickness = 2
		stroke.Transparency = 0.45
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		styleButton(button, false)
		buttons[name] = button
		if name == "Fire" then
			button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch and input.UserInputState == Enum.UserInputState.Begin then
					fireTouch = input
					lastPosition = input.Position
					styleButton(button, true)
					handlers.Fire(true)
				end
			end)
		else
			button.Activated:Connect(function()
				local handler = handlers[name]
				if handler then
					handler()
				end
			end)
		end
	end
	-- dragging on FIRE turns the camera
	UserInputService.TouchMoved:Connect(function(touch)
		if touch == fireTouch then
			local delta = touch.Position - lastPosition
			lastPosition = touch.Position
			CameraFX.Rotate(-delta.X * DRAG_SPEED, -delta.Y * DRAG_SPEED)
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == fireTouch then
			fireTouch = nil
			styleButton(buttons.Fire, false)
			handlers.Fire(false)
		end
	end)
	layout()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

function CombatTouch.SetEnabled(enabled: boolean)
	if root then
		root.Visible = enabled
	end
	if not enabled and fireTouch then
		fireTouch = nil
		handlers.Fire(false)
	end
end

function CombatTouch.SetVisible(name: string, visible: boolean)
	local button = buttons[name]
	if button then
		button.Visible = visible
	end
end

function CombatTouch.SetActive(name: string, active: boolean)
	local button = buttons[name]
	if button and name ~= "Fire" then
		styleButton(button, active)
	end
end

return CombatTouch
