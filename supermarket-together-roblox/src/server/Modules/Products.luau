-- Modelos 3D de cada producto (botellas, latas, frascos, cajas, bolsas...) hechos con piezas.
-- El origen es el centro de la base del producto y el frente mira hacia -Z.
local Products = {}

local function piece(model, size, cf, color, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = opts.query == true
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Color = color
	if opts.shape then
		p.Shape = opts.shape
	end
	p.Size = size
	p.CFrame = cf
	p.Transparency = opts.transparency or 0
	p.Parent = model
	return p
end

-- Cilindro vertical (los cilindros de Roblox van a lo largo del eje X)
local function cylinder(model, height, diameter, cf, color, opts)
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	return piece(model, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, opts)
end

-- queryable: true para que se pueda apuntar al producto (cinta de la caja, productos tirados)
-- Colores un poco apagados para que los blancos y los tonos fuertes no encandilen
local SOFT = Color3.fromRGB(190, 186, 178)
local function soften(color)
	return color:Lerp(SOFT, 0.15)
end

function Products.build(product, cf, queryable)
	local m = Instance.new("Model")
	m.Name = product.id
	local s = product.size
	local c1, c2 = soften(product.color), soften(product.color2)
	local o = { query = queryable }

	if product.shape == "bottle" then
		local bodyH = s.Y * 0.72
		local bottleOpts = { query = queryable, material = Enum.Material.SmoothPlastic, transparency = 0.08 }
		cylinder(m, bodyH, s.X, cf * CFrame.new(0, bodyH / 2, 0), c1, bottleOpts)
		cylinder(m, s.Y * 0.28, s.X * 0.4, cf * CFrame.new(0, bodyH + s.Y * 0.14, 0), c1, bottleOpts)
		cylinder(m, bodyH * 0.45, s.X * 1.02, cf * CFrame.new(0, bodyH * 0.5, 0), c2, o)
		cylinder(m, s.Y * 0.06, s.X * 0.42, cf * CFrame.new(0, s.Y - s.Y * 0.03, 0), c2, o)
	elseif product.shape == "can" then
		cylinder(m, s.Y * 0.92, s.X, cf * CFrame.new(0, s.Y * 0.46, 0), c1, o)
		cylinder(m, s.Y * 0.08, s.X * 0.96, cf * CFrame.new(0, s.Y * 0.96, 0), c2, { query = queryable, material = Enum.Material.Metal })
	elseif product.shape == "jar" then
		cylinder(m, s.Y * 0.82, s.X, cf * CFrame.new(0, s.Y * 0.41, 0), c1, { query = queryable, material = Enum.Material.SmoothPlastic, transparency = 0.04 })
		cylinder(m, s.Y * 0.18, s.X * 0.92, cf * CFrame.new(0, s.Y * 0.91, 0), c2, o)
	elseif product.shape == "carton" then
		piece(m, Vector3.new(s.X, s.Y * 0.82, s.Z), cf * CFrame.new(0, s.Y * 0.41, 0), c1, o)
		piece(m, Vector3.new(s.X * 0.95, s.Y * 0.18, s.Z * 0.3), cf * CFrame.new(0, s.Y * 0.91, 0), c1, o)
		piece(m, Vector3.new(s.X * 1.01, s.Y * 0.3, s.Z * 1.01), cf * CFrame.new(0, s.Y * 0.45, 0), c2, o)
	elseif product.shape == "bag" then
		piece(m, Vector3.new(s.X, s.Y * 0.85, s.Z), cf * CFrame.new(0, s.Y * 0.425, 0), c1, { query = queryable, material = Enum.Material.Fabric })
		piece(m, Vector3.new(s.X * 0.9, s.Y * 0.15, s.Z * 0.5), cf * CFrame.new(0, s.Y * 0.92, 0), c1, o)
		piece(m, Vector3.new(s.X * 0.7, s.Y * 0.35, 0.02), cf * CFrame.new(0, s.Y * 0.45, -s.Z / 2 - 0.01), c2, o)
	elseif product.shape == "round" then
		-- fruta / verdura redonda con cabito
		piece(m, Vector3.new(s.X, s.X, s.X), cf * CFrame.new(0, s.Y / 2, 0), c1, { query = queryable, shape = Enum.PartType.Ball, material = Enum.Material.SmoothPlastic })
		piece(m, Vector3.new(0.06, 0.12, 0.06), cf * CFrame.new(0, s.Y + 0.03, 0), c2, o)
	elseif product.shape == "banana" then
		-- racimo de bananas: tres "medialunas" hechas con dos tramos cada una
		for i = -1, 1 do
			local base = cf * CFrame.new(0, 0.12, i * 0.12)
			piece(m, Vector3.new(s.X * 0.52, 0.16, 0.16), base * CFrame.new(-s.X * 0.22, 0.05, 0) * CFrame.Angles(0, 0, math.rad(-18)), c1, o)
			piece(m, Vector3.new(s.X * 0.52, 0.16, 0.16), base * CFrame.new(s.X * 0.22, 0.05, 0) * CFrame.Angles(0, 0, math.rad(18)), c1, o)
		end
		piece(m, Vector3.new(0.12, 0.14, 0.4), cf * CFrame.new(s.X * 0.46, 0.2, 0), c2, o)
	elseif product.shape == "leafy" then
		piece(m, Vector3.new(s.Y, s.Y, s.Y), cf * CFrame.new(0, s.Y / 2, 0), c1, { query = queryable, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
		piece(m, Vector3.new(s.Y * 0.8, s.Y * 0.8, s.Y * 0.8), cf * CFrame.new(s.X * 0.18, s.Y * 0.45, 0), c2, { query = queryable, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
		piece(m, Vector3.new(s.Y * 0.8, s.Y * 0.8, s.Y * 0.8), cf * CFrame.new(-s.X * 0.18, s.Y * 0.45, s.Z * 0.1), c2, { query = queryable, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
	elseif product.shape == "long" then
		-- zanahoria acostada con las hojitas
		piece(m, Vector3.new(s.X * 0.85, s.Y, s.Y), cf * CFrame.new(-s.X * 0.07, s.Y / 2, 0), c1, { query = queryable, shape = Enum.PartType.Cylinder })
		piece(m, Vector3.new(0.18, 0.08, 0.18), cf * CFrame.new(s.X * 0.42, s.Y / 2, 0), c2, o)
	elseif product.shape == "appliance" then
		local dark = Color3.fromRGB(35, 35, 40)
		if product.id == "tele" then
			piece(m, Vector3.new(0.6, 0.12, 0.35), cf * CFrame.new(0, 0.06, 0), dark, o)
			piece(m, Vector3.new(0.14, 0.3, 0.14), cf * CFrame.new(0, 0.2, 0), dark, o)
			piece(m, Vector3.new(s.X, s.Y - 0.35, 0.14), cf * CFrame.new(0, 0.35 + (s.Y - 0.35) / 2, 0), c1, o)
			piece(m, Vector3.new(s.X - 0.2, s.Y - 0.55, 0.02), cf * CFrame.new(0, 0.35 + (s.Y - 0.35) / 2, -0.08), c2, { query = queryable, material = Enum.Material.Glass })
		elseif product.id == "ventilador" then
			piece(m, Vector3.new(0.9, 0.12, 0.7), cf * CFrame.new(0, 0.06, 0), c1, o)
			piece(m, Vector3.new(0.14, s.Y * 0.55, 0.14), cf * CFrame.new(0, s.Y * 0.3, 0), c1, o)
			cylinder(m, 0.3, s.X, cf * CFrame.new(0, s.Y - s.X / 2, 0) * CFrame.Angles(math.rad(90), 0, 0), c2, o)
			piece(m, Vector3.new(0.22, 0.22, 0.34), cf * CFrame.new(0, s.Y - s.X / 2, 0), c1, o)
		elseif product.id == "licuadora" then
			piece(m, Vector3.new(s.X, s.Y * 0.3, s.Z), cf * CFrame.new(0, s.Y * 0.15, 0), c1, o)
			cylinder(m, s.Y * 0.62, s.X * 0.8, cf * CFrame.new(0, s.Y * 0.3 + s.Y * 0.31, 0), c2, { query = queryable, transparency = 0.35 })
			piece(m, Vector3.new(s.X * 0.82, 0.1, s.Z * 0.82), cf * CFrame.new(0, s.Y - 0.05, 0), c1, o)
		elseif product.id == "pava" then
			cylinder(m, s.Y * 0.85, s.X * 0.85, cf * CFrame.new(0, s.Y * 0.425, 0), c1, { query = queryable, material = Enum.Material.Metal })
			piece(m, Vector3.new(0.12, s.Y * 0.6, 0.12), cf * CFrame.new(s.X * 0.48, s.Y * 0.5, 0), c2, o)
			piece(m, Vector3.new(0.3, 0.1, 0.12), cf * CFrame.new(s.X * 0.38, s.Y * 0.8, 0), c2, o)
			piece(m, Vector3.new(0.14, 0.14, 0.3), cf * CFrame.new(-s.X * 0.42, s.Y * 0.6, 0), c1, o)
		else
			-- caja con frente (microondas, tostadora, plancha)
			piece(m, s, cf * CFrame.new(0, s.Y / 2, 0), c1, { query = queryable, material = Enum.Material.Metal })
			piece(m, Vector3.new(s.X * 0.62, s.Y * 0.6, 0.03), cf * CFrame.new(-s.X * 0.12, s.Y * 0.5, -s.Z / 2 - 0.015), c2, o)
			piece(m, Vector3.new(s.X * 0.16, s.Y * 0.6, 0.03), cf * CFrame.new(s.X * 0.36, s.Y * 0.5, -s.Z / 2 - 0.015), dark, o)
		end
	elseif product.shape == "pack" then
		piece(m, s, cf * CFrame.new(0, s.Y / 2, 0), c1, o)
		piece(m, Vector3.new(s.X * 1.01, s.Y * 0.35, s.Z * 1.01), cf * CFrame.new(0, s.Y / 2, 0), c2, o)
	else -- "box"
		piece(m, s, cf * CFrame.new(0, s.Y / 2, 0), c1, o)
		piece(m, Vector3.new(s.X * 0.8, s.Y * 0.5, 0.02), cf * CFrame.new(0, s.Y * 0.5, -s.Z / 2 - 0.01), c2, o)
	end
	return m
end

-- Producto suelto (una sola pieza física) para lo que tiran los ladrones
function Products.buildLoose(product, position)
	local p = Instance.new("Part")
	p.Name = "Dropped_" .. product.id
	p.Size = Vector3.new(math.max(product.size.X, 0.6), math.max(product.size.Y, 0.4), math.max(product.size.Z, 0.4))
	p.Color = soften(product.color)
	p.Material = Enum.Material.SmoothPlastic
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, math.rad(90))
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

return Products
