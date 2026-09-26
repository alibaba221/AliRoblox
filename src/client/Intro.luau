--[[
	Opening title + letterboxed flyover of the town, then a fade into gameplay.
	Any key / button / tap skips it. Shots come from ReplicatedStorage.SicilyTownData.Shots
	(written by the town generator).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SicilyShared")
local Config = require(Shared:WaitForChild("Config"))

local Intro = {}

local player = Players.LocalPlayer
local CREAM = Color3.fromRGB(246, 236, 214)

local function tween(instance: Instance, duration: number, props: { [string]: any })
	local t = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props)
	t:Play()
	return t
end

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function readShots(): { { CFrame } }
	local shots = {}
	local data = ReplicatedStorage:FindFirstChild("SicilyTownData")
	local folder = data and data:FindFirstChild("Shots")
	if not folder then
		return shots
	end
	local names = {}
	for _, value in folder:GetChildren() do
		if value:IsA("CFrameValue") then
			table.insert(names, value.Name)
		end
	end
	table.sort(names)
	for _, name in names do
		local index, which = string.match(name, "^(%d+)_([AB])$")
		if index then
			local i = tonumber(index) :: number
			shots[i] = shots[i] or {}
			shots[i][if which == "A" then 1 else 2] = (folder:FindFirstChild(name) :: CFrameValue).Value
		end
	end
	local list = {}
	for i = 1, #names do
		local shot = shots[i]
		if shot and shot[1] and shot[2] then
			table.insert(list, shot)
		end
	end
	return list
end

local function waitForTown(timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local data = ReplicatedStorage:FindFirstChild("SicilyTownData")
		if data and data:GetAttribute("Ready") then
			return true
		end
		task.wait(0.2)
	end
	return false
end

function Intro.Play(movement, hud)
	local settings = Config.Intro
	local screen = hud.GetGui()
	movement.SetInputEnabled(false)
	hud.SetBlack(true)

	local camera = Workspace.CurrentCamera
	local skipped = false
	local skipConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.MouseButton1
			or string.find(t.Name, "Gamepad") ~= nil
		then
			skipped = true
		end
	end)

	-- Title card ----------------------------------------------------------------------------
	local titleHolder = Instance.new("Frame")
	titleHolder.Name = "IntroTitle"
	titleHolder.BackgroundTransparency = 1
	titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	titleHolder.Position = UDim2.fromScale(0.5, 0.46)
	titleHolder.Size = UDim2.fromScale(0.9, 0.3)
	titleHolder.ZIndex = 60
	titleHolder.Parent = screen

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.55)
	title.Font = Enum.Font.Bodoni
	title.Text = settings.Title
	title.TextColor3 = CREAM
	title.TextScaled = true
	title.TextTransparency = 1
	title.ZIndex = 61
	title.Parent = titleHolder
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 96
	sizeLimit.Parent = title

	local rule = Instance.new("Frame")
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = CREAM
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.fromScale(0.5, 0.6)
	rule.Size = UDim2.fromOffset(0, 1)
	rule.ZIndex = 61
	rule.Parent = titleHolder
	local ruleGradient = Instance.new("UIGradient")
	ruleGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	ruleGradient.Parent = rule

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0, 0.66)
	subtitle.Size = UDim2.fromScale(1, 0.14)
	subtitle.Font = Enum.Font.Garamond
	subtitle.Text = settings.Subtitle
	subtitle.TextColor3 = CREAM
	subtitle.TextScaled = true
	subtitle.TextTransparency = 1
	subtitle.ZIndex = 61
	subtitle.Parent = titleHolder
	local subLimit = Instance.new("UITextSizeConstraint")
	subLimit.MaxTextSize = 26
	subLimit.Parent = subtitle

	local skipHint = Instance.new("TextLabel")
	skipHint.BackgroundTransparency = 1
	skipHint.AnchorPoint = Vector2.new(1, 1)
	skipHint.Position = UDim2.new(1, -28, 1, -24)
	skipHint.Size = UDim2.fromOffset(260, 20)
	skipHint.Font = Enum.Font.GothamMedium
	skipHint.TextSize = 13
	skipHint.TextXAlignment = Enum.TextXAlignment.Right
	skipHint.Text = "Press any key to skip"
	skipHint.TextColor3 = CREAM
	skipHint.TextTransparency = 1
	skipHint.ZIndex = 61
	skipHint.Parent = screen

	-- Letterbox bars
	local bars = {}
	for i, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.fromScale(1, 0.11)
		bar.ZIndex = 55
		bar.Parent = screen
		bars[i] = bar
	end

	tween(title, 1.4, { TextTransparency = 0 })
	tween(rule, 1.6, { Size = UDim2.new(0.34, 0, 0, 1) })
	task.delay(0.5, function()
		tween(subtitle, 1.4, { TextTransparency = 0.1 })
		tween(skipHint, 1.4, { TextTransparency = 0.45 })
	end)

	local function waitOrSkip(seconds: number)
		local deadline = os.clock() + seconds
		while os.clock() < deadline and not skipped do
			task.wait()
		end
	end

	waitOrSkip(1.8)

	-- Flyover ---------------------------------------------------------------------------------
	local shots = {}
	if not skipped and Config.Town.Enabled and waitForTown(30) then
		shots = readShots()
	end
	local shotCFrame: CFrame? = nil
	RunService:BindToRenderStep("SicilyIntroCamera", Enum.RenderPriority.Camera.Value + 5, function()
		if shotCFrame then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = shotCFrame
		end
	end)

	for index, shot in shots do
		if skipped then
			break
		end
		if Workspace.StreamingEnabled then
			pcall(function()
				player:RequestStreamAroundAsync(shot[1].Position, 4)
			end)
		end
		local startedAt = os.clock()
		local duration = settings.ShotDuration
		shotCFrame = shot[1]
		hud.Fade(1, if index == 1 then 1.2 else 0.6)
		if index == 1 then
			task.delay(duration * 0.55, function()
				tween(title, 1.2, { TextTransparency = 1 })
				tween(subtitle, 1.2, { TextTransparency = 1 })
				tween(rule, 1.2, { BackgroundTransparency = 1 })
			end)
		end
		local faded = false
		while not skipped do
			local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
			shotCFrame = shot[1]:Lerp(shot[2], ease(alpha))
			if not faded and alpha > 1 - 0.55 / duration and index < #shots then
				faded = true
				hud.Fade(0, 0.5)
			end
			if alpha >= 1 then
				break
			end
			task.wait()
		end
	end

	-- Into gameplay ---------------------------------------------------------------------------
	hud.Fade(0, if skipped then 0.25 else 0.6).Completed:Wait()
	title.TextTransparency = 1
	subtitle.TextTransparency = 1
	rule.BackgroundTransparency = 1

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 10)
	shotCFrame = nil
	RunService:UnbindFromRenderStep("SicilyIntroCamera")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
	task.wait(0.35) -- let the default camera settle behind the character

	skipConnection:Disconnect()
	screen:SetAttribute("IntroDone", true)
	hud.Fade(1, 1.1)
	tween(skipHint, 0.4, { TextTransparency = 1 })
	for i, bar in bars do
		tween(bar, 1.2, { Position = UDim2.fromScale(0, if i == 1 then -0.12 else 1.12) })
	end
	movement.SetInputEnabled(true)
	task.delay(1.3, function()
		titleHolder:Destroy()
		skipHint:Destroy()
		for _, bar in bars do
			bar:Destroy()
		end
	end)
	hud.ShowHint()
end

return Intro
