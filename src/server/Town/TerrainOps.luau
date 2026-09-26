--[[
	Thin wrapper around Terrain fills. Splits very large fills into chunks and can record every
	operation (the offline preview renderer uses the recording; in Roblox it just fills terrain).
]]

local TerrainOps = {}
TerrainOps.__index = TerrainOps

local MAX_CHUNK = 512

function TerrainOps.new(terrain: Terrain?, recorder: { any }?)
	return setmetatable({ Terrain = terrain, Recorder = recorder, Count = 0 }, TerrainOps)
end

function TerrainOps:_record(op)
	if self.Recorder then
		table.insert(self.Recorder, op)
	end
	self.Count += 1
	-- Big fills are slow; yield regularly so the server (or Studio's command bar) never stalls.
	if self.Terrain and self.Count % 6 == 0 then
		task.wait()
	end
end

-- Axis-aligned or rotated block. Big axis-aligned blocks are split into chunks.
function TerrainOps:Block(cf: CFrame, size: Vector3, material: Enum.Material)
	local rotated = cf.XVector.X < 0.9999 or cf.YVector.Y < 0.9999
	if not rotated and (size.X > MAX_CHUNK or size.Y > MAX_CHUNK or size.Z > MAX_CHUNK) then
		local nx = math.ceil(size.X / MAX_CHUNK)
		local ny = math.ceil(size.Y / MAX_CHUNK)
		local nz = math.ceil(size.Z / MAX_CHUNK)
		local step = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
		local origin = cf.Position - size / 2 + step / 2
		for ix = 0, nx - 1 do
			for iy = 0, ny - 1 do
				for iz = 0, nz - 1 do
					local center = origin + Vector3.new(ix * step.X, iy * step.Y, iz * step.Z)
					self:Block(CFrame.new(center), step, material)
				end
			end
		end
		return
	end
	self:_record({ Kind = "Block", CFrame = cf, Size = size, Material = material })
	if self.Terrain then
		self.Terrain:FillBlock(cf, size, material)
	end
end

function TerrainOps:Ball(center: Vector3, radius: number, material: Enum.Material)
	self:_record({ Kind = "Ball", Center = center, Radius = radius, Material = material })
	if self.Terrain then
		self.Terrain:FillBall(center, radius, material)
	end
end

-- Same orientation convention as a WedgePart (slope rises towards local +Z).
function TerrainOps:Wedge(cf: CFrame, size: Vector3, material: Enum.Material)
	self:_record({ Kind = "Wedge", CFrame = cf, Size = size, Material = material })
	if self.Terrain then
		self.Terrain:FillWedge(cf, size, material)
	end
end

function TerrainOps:Clear()
	self:_record({ Kind = "Clear" })
	if self.Terrain then
		self.Terrain:Clear()
	end
end

function TerrainOps:SetMaterialColor(material: Enum.Material, color: Color3)
	self:_record({ Kind = "MaterialColor", Material = material, Color = color })
	if self.Terrain then
		pcall(function()
			(self.Terrain :: Terrain):SetMaterialColor(material, color)
		end)
	end
end

function TerrainOps:SetWater(props: { [string]: any })
	self:_record({ Kind = "Water", Props = props })
	if self.Terrain then
		for key, value in props do
			pcall(function()
				(self.Terrain :: any)[key] = value
			end)
		end
	end
end

return TerrainOps
