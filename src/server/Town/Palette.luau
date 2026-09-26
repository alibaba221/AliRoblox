--[[
	Sicilian baroque palette: honey limestone, ochre and salmon plaster, green shutters,
	terracotta roofs, lava-stone paving, bougainvillea.
]]

local Palette = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Palette.rgb = rgb

local M = Enum.Material
Palette.M = M

Palette.Walls = {
	rgb(228, 198, 148), -- honey limestone
	rgb(220, 186, 134),
	rgb(236, 210, 164),
	rgb(224, 178, 110), -- ochre
	rgb(232, 192, 122),
	rgb(230, 174, 150), -- salmon
	rgb(238, 196, 172), -- pale pink
	rgb(242, 228, 200), -- cream
	rgb(244, 234, 214),
	rgb(208, 136, 98), -- faded terracotta
	rgb(216, 152, 112),
	rgb(240, 206, 170), -- peach
	rgb(246, 240, 228), -- whitewash
	rgb(208, 196, 178), -- weathered beige
	rgb(232, 216, 174),
}

Palette.WallMaterials = { M.Plaster, M.Plaster, M.Plaster, M.Limestone, M.Sandstone }

Palette.Stone = rgb(236, 220, 184) -- carved limestone trim
Palette.StoneWarm = rgb(226, 204, 160)
Palette.StoneShadow = rgb(198, 178, 142)
Palette.Lava = rgb(82, 80, 80) -- basalt / pietra lavica
Palette.LavaDark = rgb(58, 57, 58)
Palette.Marble = rgb(242, 238, 230)

Palette.Shutters = {
	rgb(50, 78, 56),
	rgb(72, 98, 68),
	rgb(98, 124, 98),
	rgb(104, 74, 52),
	rgb(62, 92, 108),
	rgb(116, 124, 118),
	rgb(86, 112, 134),
	rgb(62, 86, 60),
}

Palette.Doors = {
	rgb(78, 52, 36),
	rgb(52, 68, 50),
	rgb(100, 40, 34),
	rgb(44, 60, 86),
	rgb(94, 68, 46),
	rgb(66, 46, 34),
}

Palette.Iron = rgb(36, 34, 34)
Palette.Interior = rgb(36, 36, 40)
Palette.Glass = rgb(52, 66, 72)
Palette.Window = rgb(40, 44, 48)

Palette.Roofs = {
	rgb(170, 86, 56),
	rgb(182, 98, 62),
	rgb(158, 80, 52),
	rgb(188, 110, 72),
	rgb(166, 92, 64),
}

Palette.Awnings = {
	rgb(160, 44, 40),
	rgb(44, 84, 64),
	rgb(206, 178, 128),
	rgb(38, 64, 112),
	rgb(188, 114, 46),
	rgb(122, 40, 62),
}
Palette.Canvas = rgb(234, 220, 192)

Palette.Paving = rgb(150, 142, 132) -- worn lava/limestone mix
Palette.PavingLight = rgb(206, 194, 168)
Palette.Cobble = rgb(128, 118, 106)

Palette.Foliage = { rgb(74, 104, 50), rgb(90, 118, 56), rgb(62, 90, 44) }
Palette.Olive = { rgb(118, 130, 92), rgb(128, 140, 100), rgb(106, 120, 86) }
Palette.Cypress = rgb(44, 66, 40)
Palette.PalmFrond = { rgb(82, 112, 48), rgb(96, 124, 54), rgb(72, 100, 44) }
Palette.Bark = rgb(104, 88, 70)
Palette.PalmBark = rgb(122, 102, 78)
Palette.Bougainvillea = { rgb(206, 38, 126), rgb(224, 62, 152), rgb(188, 28, 110), rgb(234, 94, 170) }
Palette.Geranium = { rgb(212, 40, 46), rgb(232, 74, 92), rgb(242, 122, 142) }
Palette.Lemon = rgb(246, 214, 60)
Palette.Orange = rgb(240, 140, 36)
Palette.Terracotta = rgb(178, 98, 64)
Palette.Wood = rgb(124, 90, 60)
Palette.WoodDark = rgb(86, 62, 44)
Palette.WoodPale = rgb(170, 140, 104)
Palette.Bulb = rgb(255, 216, 156)
Palette.LampLight = rgb(255, 186, 112)
Palette.Water = rgb(92, 150, 156)

-- Small, natural variation of a colour.
function Palette.Vary(color: Color3, rng, amount: number?): Color3
	local a = amount or 0.04
	local h, s, v = color:ToHSV()
	h = (h + rng:Range(-a, a) * 0.25) % 1
	s = math.clamp(s + rng:Range(-a, a), 0, 1)
	v = math.clamp(v + rng:Range(-a, a), 0, 1)
	return Color3.fromHSV(h, s, v)
end

function Palette.Darken(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + amount * 0.3, 0, 1), math.clamp(v - amount, 0, 1))
end

function Palette.Lighten(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s - amount * 0.4, 0, 1), math.clamp(v + amount, 0, 1))
end

return Palette
