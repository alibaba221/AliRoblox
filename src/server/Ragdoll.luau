--[[
	R6 ragdoll: on death the limb motors are swapped for limited ball sockets so the body
	crumples naturally instead of the classic "falls apart" death.
]]

local Ragdoll = {}

local LIMITS = {
	Neck = { Upper = 35, Twist = 30, Collider = Vector3.new(1.1, 1, 1) },
	["Right Shoulder"] = { Upper = 95, Twist = 70, Collider = Vector3.new(0.9, 1.8, 0.9) },
	["Left Shoulder"] = { Upper = 95, Twist = 70, Collider = Vector3.new(0.9, 1.8, 0.9) },
	["Right Hip"] = { Upper = 60, Twist = 25, Collider = Vector3.new(0.9, 1.8, 0.9) },
	["Left Hip"] = { Upper = 60, Twist = 25, Collider = Vector3.new(0.9, 1.8, 0.9) },
}

function Ragdoll.Apply(character: Model)
	if character:GetAttribute("SicilyRagdolled") then
		return
	end
	local torso = character:FindFirstChild("Torso")
	if not torso then
		return
	end
	character:SetAttribute("SicilyRagdolled", true)

	for jointName, limit in LIMITS do
		local motor = torso:FindFirstChild(jointName)
		if not (motor and motor:IsA("Motor6D") and motor.Part0 and motor.Part1) then
			continue
		end
		local part0 = motor.Part0 :: BasePart
		local part1 = motor.Part1 :: BasePart

		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollSocket0"
		a0.CFrame = motor.C0
		a0.Parent = part0

		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollSocket1"
		a1.CFrame = motor.C1
		a1.Parent = part1

		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "RagdollSocket"
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = limit.Upper
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -limit.Twist
		socket.TwistUpperAngle = limit.Twist
		socket.Parent = part0

		-- Humanoids manage limb collisions themselves, so give each limb its own collider.
		local collider = Instance.new("Part")
		collider.Name = "RagdollCollider"
		collider.Size = limit.Collider
		collider.Transparency = 1
		collider.CanCollide = true
		collider.CanQuery = false
		collider.CanTouch = false
		collider.Massless = true
		collider.CFrame = part1.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part1
		weld.Part1 = collider
		weld.Parent = collider
		collider.Parent = part1

		motor.Enabled = false
	end
end

return Ragdoll
