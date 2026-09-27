-- Logo de "Tesoro Digital" (el banco del juego) armado con piezas de interfaz, igual al diseño original:
-- un escudo azul marino con borde verde agua y el dial de una caja fuerte adentro.
-- Sirve tanto en pantallas 3D (SurfaceGui de los cajeros) como en la interfaz del jugador.
local TesoroLogo = {}

TesoroLogo.NAVY = Color3.fromHex("#0a3d62")
TesoroLogo.NAVY2 = Color3.fromHex("#0d5c8c")
TesoroLogo.TEAL = Color3.fromHex("#1abc9c")
TesoroLogo.LIGHT = Color3.fromHex("#eafaf6")

local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function gradient(parent, rotation)
	new("UIGradient", {
		Color = ColorSequence.new(TesoroLogo.NAVY, TesoroLogo.NAVY2),
		Rotation = rotation or 45,
	}, parent)
end

-- Crea el escudo dentro de `parent`. size = lado en píxeles (el logo es cuadrado).
function TesoroLogo.create(parent, size, position)
	local s = size / 64 -- el diseño original mide 64x64
	local holder = new("Frame", {
		Name = "TesoroLogo",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = position or UDim2.new(),
	}, parent)

	-- Borde verde agua (formas un poco más grandes detrás) + escudo azul encima
	local function shield(inset, color, useGradient, z)
		local top = new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			Position = UDim2.fromOffset((6 + inset) * s, (7 + inset) * s),
			Size = UDim2.fromOffset((52 - inset * 2) * s, (26 - inset) * s),
			ZIndex = z,
		}, holder)
		new("UICorner", { CornerRadius = UDim.new(0, 5 * s) }, top)
		-- punta de abajo: un cuadrado girado
		local side = (37 - inset * 1.4) * s
		local tip = new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(32 * s, (34 - inset * 0.2) * s),
			Size = UDim2.fromOffset(side, side),
			Rotation = 45,
			ZIndex = z,
		}, holder)
		new("UICorner", { CornerRadius = UDim.new(0, 5 * s) }, tip)
		if useGradient then
			gradient(top, 90)
			gradient(tip, 45)
		end
	end
	shield(0, TesoroLogo.TEAL, false, 1)
	shield(2, TesoroLogo.NAVY, true, 2)

	-- Dial de caja fuerte
	local dial = new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(32 * s, 30 * s),
		Size = UDim2.fromOffset(26 * s, 26 * s),
		ZIndex = 3,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dial)
	new("UIStroke", { Color = TesoroLogo.LIGHT, Thickness = math.max(1, 2.5 * s) }, dial)
	-- agujas (una hacia arriba, clara; otra hacia la derecha, verde agua)
	new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = TesoroLogo.LIGHT,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(32 * s, 30.5 * s),
		Size = UDim2.fromOffset(math.max(1, 2.5 * s), 9.5 * s),
		ZIndex = 4,
	}, holder)
	new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = TesoroLogo.TEAL,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(31.5 * s, 30 * s),
		Size = UDim2.fromOffset(6.5 * s, math.max(1, 2.5 * s)),
		ZIndex = 4,
	}, holder)
	local center = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = TesoroLogo.TEAL,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(32 * s, 30 * s),
		Size = UDim2.fromOffset(6 * s, 6 * s),
		ZIndex = 5,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, center)
	-- barrita de abajo
	local bar = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = TesoroLogo.LIGHT,
		Position = UDim2.fromOffset(24 * s, 43 * s),
		Size = UDim2.fromOffset(16 * s, 4 * s),
		ZIndex = 4,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
	return holder
end

-- Logo + nombre "Tesoro Digital" en una fila
function TesoroLogo.lockup(parent, height, textColor)
	local row = new("Frame", {
		Name = "TesoroLockup",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
	}, parent)
	TesoroLogo.create(row, height, UDim2.new())
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(height * 1.1, 0),
		Size = UDim2.new(1, -height * 1.1, 1, 0),
		Font = Enum.Font.GothamBlack,
		Text = "Tesoro Digital",
		TextColor3 = textColor or Color3.new(1, 1, 1),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	return row
end

return TesoroLogo
