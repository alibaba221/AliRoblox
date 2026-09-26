--[[
	Sicily upgrade installer (for people not using Rojo).

	1. In Studio, right-click ServerStorage > Insert from File... > choose SicilyUpgrade.rbxm
	2. Paste this in the Command Bar (View > Command Bar) and press Enter:

		require(game.ServerStorage.SicilyUpgrade.Install)()

	Moves every script into the right service, enables them, and backs up anything it replaces
	(same name) into ServerStorage.SicilyUpgrade_Backup. Undo with Ctrl+Z if needed.
]]

return function()
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	local ServerStorage = game:GetService("ServerStorage")
	local StarterPlayer = game:GetService("StarterPlayer")

	local root = script.Parent
	local targets = {
		ReplicatedStorage = game:GetService("ReplicatedStorage"),
		ServerScriptService = game:GetService("ServerScriptService"),
		StarterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts"),
		StarterCharacterScripts = StarterPlayer:FindFirstChild("StarterCharacterScripts"),
	}

	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording("Install Sicily upgrade")
	end)

	local backup = Instance.new("Folder")
	backup.Name = "SicilyUpgrade_Backup"
	local installed = {}
	for folderName, target in targets do
		local folder = root:FindFirstChild(folderName)
		if folder and target then
			for _, item in folder:GetChildren() do
				local existing = target:FindFirstChild(item.Name)
				if existing then
					existing.Parent = backup
				end
				item.Parent = target
				local scripts = item:GetDescendants()
				table.insert(scripts, item)
				for _, d in scripts do
					if d:IsA("BaseScript") then
						d.Enabled = true
					end
				end
				table.insert(installed, target.Name .. "." .. item.Name)
			end
		end
	end
	if #backup:GetChildren() > 0 then
		local old = ServerStorage:FindFirstChild(backup.Name)
		if old then
			old:Destroy()
		end
		backup.Parent = ServerStorage
	end

	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end)
	end

	print("[Sicily] Installed: " .. table.concat(installed, ", "))
	if backup.Parent then
		print("[Sicily] Replaced items were moved to ServerStorage." .. backup.Name)
	end
	print("[Sicily] Next: set Lighting > Technology to Future, remove or rename your old map, then press Play.")
	print("[Sicily] Optional: bake the town into the place with  require(game.ServerScriptService.SicilyServer.Town).Bake()")
	root:Destroy()
end
