-- Construye todo el mundo por código: el edificio (tienda, depósito y oficina), la zona de descarga,
-- el estacionamiento, las calles y el barrio con casas, árboles y faroles.
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Builder = {}
Builder.FLOOR_Y = Config.FLOOR_Y
local FLOOR_Y = Config.FLOOR_Y
local H = 14 -- altura de las paredes

local V, C = Vector3.new, Color3.fromRGB

-- Paleta suave: tonos cálidos y sin blancos puros para que no encandile
local COLORS = {
	grass = C(88, 132, 72),
	asphalt = C(58, 58, 62),
	sidewalk = C(172, 168, 160),
	concrete = C(150, 148, 144),
	facade = C(212, 204, 190),
	trim = C(58, 140, 90),
	roof = C(140, 138, 136),
	glass = C(150, 180, 195),
	frame = C(70, 72, 80),
	wood = C(140, 100, 70),
	storageFloor = C(138, 136, 132),
	line = C(215, 212, 205),
	yellow = C(215, 180, 60),
	lamp = C(205, 195, 175), -- paneles de luz (neón suave)
}

Builder.paintable = { walls = {}, stripes = {}, tiles = {} }
Builder.streetLights = {}
Builder.houseWindows = {}
Builder.houseDoors = {}
Builder.zoneLights = {}
Builder.benchSeats = {} -- asientos de los bancos de afuera (los NPCs se sientan a charlar)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function part(props)
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = props.Parent
	props.Parent = nil
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end
Builder.part = part

local function block(parent, name, x1, x2, y1, y2, z1, z2, color, material, extra)
	local p = part({
		Name = name,
		Size = V(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1)),
		Position = V((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	for key, value in extra or {} do
		p[key] = value
	end
	return p
end
Builder.block = block

-- Tamaño de la cara de una pieza (para que el texto no genere texturas gigantes)
local FACE_AXES = {
	[Enum.NormalId.Front] = { "X", "Y" }, [Enum.NormalId.Back] = { "X", "Y" },
	[Enum.NormalId.Left] = { "Z", "Y" }, [Enum.NormalId.Right] = { "Z", "Y" },
	[Enum.NormalId.Top] = { "X", "Z" }, [Enum.NormalId.Bottom] = { "X", "Z" },
}

local function surfaceText(target, face, text, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	-- Los carteles grandes con muchos píxeles por stud dejan de dibujarse de lejos y gastan
	-- memoria en celulares: limitamos el lienzo a ~900 px en su lado más largo.
	local axes = FACE_AXES[face]
	local w, h = target.Size[axes[1]], target.Size[axes[2]]
	local pps = math.min(opts.pps or 50, 900 / math.max(w, h, 0.1))
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.max(pps, 8)
	gui.LightInfluence = 0
	gui.MaxDistance = 0 -- 0 = siempre visible
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = opts.bg and 0 or 1
	if opts.bg then
		label.BackgroundColor3 = opts.bg
	end
	label.TextColor3 = opts.color or Color3.new(0, 0, 0)
	label.Font = opts.font or Enum.Font.GothamBold
	label.TextScaled = true
	label.RichText = opts.rich == true
	label.Text = text
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.PaddingBottom = UDim.new(0.06, 0)
	padding.Parent = label
	gui.Parent = target
	return label
end
Builder.surfaceText = surfaceText

local function prompt(parent, action, object, opts)
	opts = opts or {}
	local pp = Instance.new("ProximityPrompt")
	pp.Name = opts.name or "Prompt"
	pp.ActionText = action
	pp.ObjectText = object or ""
	pp.HoldDuration = opts.hold or 0
	pp.MaxActivationDistance = opts.distance or 8
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = opts.key or Enum.KeyCode.E
	-- No clickeable: así el cartel "E" no atrapa el mouse ni traba la mira
	pp.ClickablePrompt = false
	pp.Parent = parent
	return pp
end
Builder.prompt = prompt

local function pick(list)
	return list[math.random(#list)]
end

local function tagFloor(p)
	CollectionService:AddTag(p, "BuildFloor")
end

---------------------------------------------------------------------------
-- Iluminación general
---------------------------------------------------------------------------
-- Busca el efecto (o lo crea) para configurarlo siempre, aunque la plantilla ya traiga uno
local function effect(className)
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Parent = Lighting
	return created
end

-- Iluminación suave: menos brillo, tono cálido y casi sin resplandor para no cansar la vista
local function setupLighting()
	Lighting.Brightness = 0.9
	Lighting.ExposureCompensation = -0.35
	Lighting.Ambient = C(70, 66, 62)
	Lighting.OutdoorAmbient = C(100, 96, 92)
	Lighting.ColorShift_Top = C(255, 238, 215)
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.ClockTime = Config.PREP_HOUR

	local atmosphere = effect("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Haze = 1.2
	atmosphere.Glare = 0
	atmosphere.Color = C(205, 200, 190)
	atmosphere.Decay = C(110, 105, 100)

	local bloom = effect("BloomEffect")
	bloom.Intensity = 0.1
	bloom.Size = 18
	bloom.Threshold = 2.2

	local cc = effect("ColorCorrectionEffect")
	cc.Brightness = -0.04
	cc.Contrast = -0.06
	cc.Saturation = -0.1
	cc.TintColor = C(255, 245, 232)

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		sunRays.Intensity = 0.03
	end
end

---------------------------------------------------------------------------
-- Luces de techo de cada zona (las zonas bloqueadas quedan a oscuras)
---------------------------------------------------------------------------
local ZONE_LIGHTS = {
	shop0 = { xs = { -25, -15, -5, 5, 15, 25 }, zs = { 5, 15, 25 } },
	shop1 = { xs = { -25, -15, -5, 5, 15, 25 }, zs = { -25, -15, -5 } },
	shop2 = { xs = { 37, 52 }, zs = { -25, -15, -5, 5, 15, 25 } },
	storage0 = { xs = { -52, -38 }, zs = { 10 } },
	storage1 = { xs = { -52, -38 }, zs = { -22, -8 } },
}

function Builder.addZoneLights(zoneId)
	if Builder.zoneLights[zoneId] then
		return
	end
	Builder.zoneLights[zoneId] = true
	local spec = ZONE_LIGHTS[zoneId]
	local count = 0
	for _, x in spec.xs do
		for _, z in spec.zs do
			count += 1
			local panel = part({
				Name = "CeilingLight",
				Size = V(4, 0.2, 1.4),
				Position = V(x, H - 0.15, z),
				Color = COLORS.lamp,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
				Parent = Builder.structure,
			})
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Range = 20
			light.Brightness = 0.85
			light.Angle = 120
			light.Color = C(255, 236, 210)
			light.Shadows = false
			light.Parent = panel
			-- Luz de relleno (una de cada dos lámparas) para que el cielorraso no quede oscuro
			if count % 2 == 0 then
				local fill = Instance.new("PointLight")
				fill.Range = 16
				fill.Brightness = 0.35
				fill.Color = C(255, 236, 210)
				fill.Shadows = false
				fill.Parent = panel
			end
		end
	end
end

---------------------------------------------------------------------------
-- Casas del barrio
---------------------------------------------------------------------------
local HOUSE_COLORS = {
	C(236, 214, 170), C(205, 125, 105), C(170, 200, 220), C(225, 225, 215),
	C(190, 210, 160), C(240, 190, 150), C(200, 180, 220), C(245, 235, 200),
}
local ROOF_COLORS = { C(140, 60, 50), C(80, 80, 90), C(110, 70, 50), C(60, 90, 120), C(90, 110, 80) }

-- cf: punto en el suelo frente a la casa, mirando hacia la calle
local WALL_MATERIALS = { Enum.Material.Brick, Enum.Material.SmoothPlastic, Enum.Material.Concrete }
local WINDOW_GLASS = C(120, 150, 170)

local function houseWindow(m, at, x, y, frameColor)
	part({ Name = "WindowFrame", Size = V(3.4, 3.4, 0.12), CFrame = at(x, y, -0.06), Color = frameColor, Parent = m })
	local glass = part({ Name = "Window", Size = V(2.9, 2.9, 0.1), CFrame = at(x, y, -0.13), Color = WINDOW_GLASS, Material = Enum.Material.SmoothPlastic, Reflectance = 0.15, CastShadow = false, Parent = m })
	part({ Name = "WindowCross", Size = V(0.12, 2.9, 0.05), CFrame = at(x, y, -0.19), Color = frameColor, CastShadow = false, Parent = m })
	part({ Name = "WindowCross", Size = V(2.9, 0.12, 0.05), CFrame = at(x, y, -0.19), Color = frameColor, CastShadow = false, Parent = m })
	part({ Name = "Sill", Size = V(3.8, 0.2, 0.5), CFrame = at(x, y - 1.8, -0.3), Color = frameColor, Parent = m })
	table.insert(Builder.houseWindows, glass)
end

local function buildHouse(parent, cf)
	local m = Instance.new("Model")
	m.Name = "Casa"
	local twoFloors = math.random() < 0.35
	local w, d = math.random(14, 18), math.random(12, 16)
	local h = twoFloors and 16 or 10
	local wallColor = pick(HOUSE_COLORS)
	local roofColor = pick(ROOF_COLORS)
	local frameColor = C(225, 220, 208)
	local material = pick(WALL_MATERIALS)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end

	part({ Name = "Base", Size = V(w + 0.6, 0.8, d + 0.6), CFrame = at(0, 0.4, d / 2), Color = C(110, 106, 100), Material = Enum.Material.Concrete, Parent = m })
	part({ Name = "Body", Size = V(w, h, d), CFrame = at(0, h / 2 + 0.4, d / 2), Color = wallColor, Material = material, Parent = m })
	if twoFloors then
		part({ Name = "FloorBand", Size = V(w + 0.2, 0.4, d + 0.2), CFrame = at(0, 8.4, d / 2), Color = frameColor, Parent = m })
	end
	-- Techo a dos aguas con alero
	part({ ClassName = "WedgePart", Name = "RoofFront", Size = V(w + 2, 4.5, d / 2 + 1.2), CFrame = at(0, h + 2.65, d / 4 - 0.6), Color = roofColor, Material = Enum.Material.Slate, Parent = m })
	part({ ClassName = "WedgePart", Name = "RoofBack", Size = V(w + 2, 4.5, d / 2 + 1.2), CFrame = at(0, h + 2.65, 3 * d / 4 + 0.6) * CFrame.Angles(0, math.pi, 0), Color = roofColor, Material = Enum.Material.Slate, Parent = m })
	part({ Name = "Fascia", Size = V(w + 2, 0.35, 0.25), CFrame = at(0, h + 0.5, -1.15), Color = frameColor, Parent = m })
	part({ Name = "Chimney", Size = V(1.6, 4.5, 1.6), CFrame = at(w / 3, h + 3.4, d * 0.7), Color = C(140, 80, 62), Material = Enum.Material.Brick, Parent = m })

	-- Puerta con marco, alero y luz
	local doorColor = pick({ C(105, 68, 45), C(58, 78, 115), C(140, 45, 42), C(42, 88, 60) })
	part({ Name = "DoorFrame", Size = V(3.7, 7.1, 0.16), CFrame = at(0, 4.0, -0.07), Color = frameColor, Parent = m })
	part({ Name = "Door", Size = V(3, 6.5, 0.2), CFrame = at(0, 3.65, -0.15), Color = doorColor, Material = Enum.Material.Wood, Parent = m })
	part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = V(0.3, 0.3, 0.3), CFrame = at(1, 3.6, -0.3), Color = C(200, 170, 80), Material = Enum.Material.Metal, CastShadow = false, Parent = m })
	part({ Name = "PorchRoof", Size = V(5.5, 0.3, 2.6), CFrame = at(0, 7.9, -1.3), Color = roofColor, Parent = m })
	for _, x in { -2.5, 2.5 } do
		part({ Name = "PorchPost", Size = V(0.3, 7.5, 0.3), CFrame = at(x, 4.15, -2.4), Color = frameColor, Parent = m })
	end
	local porchLight = part({ Name = "PorchLight", Size = V(0.5, 0.6, 0.3), CFrame = at(-2.2, 6.3, -0.3), Color = C(230, 215, 170), Material = Enum.Material.SmoothPlastic, CastShadow = false, Parent = m })
	table.insert(Builder.houseWindows, porchLight)
	part({ Name = "Step", Size = V(5.5, 0.4, 2.6), CFrame = at(0, 0.2, -1.3), Color = C(165, 160, 154), Material = Enum.Material.Concrete, Parent = m })
	part({ Name = "Path", Size = V(2.5, 0.12, 4.6), CFrame = at(0, 0.08, -4.9), Color = C(178, 172, 164), Material = Enum.Material.Concrete, Parent = m })

	-- Ventanas (una o dos filas)
	for _, x in { -w / 3.1, w / 3.1 } do
		houseWindow(m, at, x, 5.4, frameColor)
		if twoFloors then
			houseWindow(m, at, x, 11.8, frameColor)
		end
	end
	if twoFloors then
		houseWindow(m, at, 0, 11.8, frameColor)
	end

	-- Garage en algunas casas (costado derecho)
	if math.random() < 0.4 then
		part({ Name = "Garage", Size = V(7, 7, 8), CFrame = at(w / 2 + 3.5, 3.9, 4), Color = wallColor, Material = material, Parent = m })
		part({ Name = "GarageDoor", Size = V(5.6, 5.2, 0.2), CFrame = at(w / 2 + 3.5, 3.0, -0.05), Color = C(200, 198, 192), Material = Enum.Material.DiamondPlate, Parent = m })
		part({ Name = "GarageRoof", Size = V(7.6, 0.4, 8.6), CFrame = at(w / 2 + 3.5, 7.6, 4), Color = roofColor, Parent = m })
		part({ Name = "Driveway", Size = V(5.6, 0.1, 5), CFrame = at(w / 2 + 3.5, 0.06, -2.6), Color = C(150, 148, 144), Material = Enum.Material.Concrete, Parent = m })
	end

	-- Cerco bajo al frente (con hueco para el camino) y arbustos
	local fenceZ = -5.2
	for _, side in { -1, 1 } do
		local x1, x2 = side * 1.6, side * (w / 2 + 0.3)
		local cx, len = (x1 + x2) / 2, math.abs(x2 - x1)
		part({ Name = "FenceRail", Size = V(len, 0.2, 0.15), CFrame = at(cx, 1.5, fenceZ), Color = frameColor, CastShadow = false, Parent = m })
		part({ Name = "FenceRail", Size = V(len, 0.2, 0.15), CFrame = at(cx, 0.8, fenceZ), Color = frameColor, CastShadow = false, Parent = m })
		for i = 0, 3 do
			part({ Name = "FencePost", Size = V(0.25, 1.9, 0.25), CFrame = at(x1 + (x2 - x1) * i / 3, 0.95, fenceZ), Color = frameColor, CastShadow = false, Parent = m })
		end
		part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = V(2.4, 2.4, 2.4), CFrame = at(side * (w / 2 - 2), 1, -2.8), Color = pick({ C(62, 118, 58), C(74, 132, 64) }), Material = Enum.Material.Grass, Parent = m })
	end
	-- Buzón
	part({ Name = "MailPost", Size = V(0.25, 3, 0.25), CFrame = at(w / 2 - 1, 1.5, -6.2), Color = C(90, 90, 90), Parent = m })
	part({ Name = "Mailbox", Size = V(0.9, 0.8, 1.3), CFrame = at(w / 2 - 1, 3.3, -6.2), Color = C(175, 62, 52), Parent = m })

	m.Parent = parent
	table.insert(Builder.houseDoors, (cf * CFrame.new(0, 0, -3)).Position)
	return m
end

local function tree(parent, position, scale)
	scale = scale or (0.8 + math.random() * 0.5)
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = V(5.5 * scale, 0.9 * scale, 0.9 * scale),
		CFrame = CFrame.new(position + V(0, 2.75 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C(100, 74, 52),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local greens = { C(66, 122, 58), C(78, 136, 66), C(58, 112, 52) }
	for _, offset in { V(0, 6.6, 0), V(1.4, 5.6, 0.6), V(-1.2, 5.8, -0.8), V(0.3, 8, -0.2) } do
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = V(4.6, 4.6, 4.6) * scale,
			Position = position + offset * scale,
			Color = pick(greens),
			Material = Enum.Material.LeafyGrass,
			CastShadow = offset.Y > 6,
			Parent = parent,
		})
	end
end

local function streetLamp(parent, position, facing)
	facing = facing or V(0, 0, 1)
	part({ Name = "LampBase", Size = V(0.9, 0.5, 0.9), Position = position + V(0, 0.25, 0), Color = C(55, 57, 62), Parent = parent })
	part({ Name = "LampPole", Size = V(0.45, 11, 0.45), Position = position + V(0, 5.5, 0), Color = C(60, 62, 68), Material = Enum.Material.Metal, Parent = parent })
	part({ Name = "LampArm", Size = V(0.3, 0.3, 2.6), CFrame = CFrame.lookAt(position + V(0, 10.9, 0) + facing * 1.2, position + V(0, 10.9, 0) + facing * 3), Color = C(60, 62, 68), Material = Enum.Material.Metal, Parent = parent })
	local head = part({ Name = "LampHead", Size = V(1.4, 0.35, 1.8), CFrame = CFrame.lookAt(position + V(0, 10.75, 0) + facing * 2.4, position + V(0, 10.75, 0) + facing * 4), Color = C(210, 198, 172), Material = Enum.Material.SmoothPlastic, CastShadow = false, Parent = parent })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 42
	light.Angle = 110
	light.Brightness = 1.6
	light.Color = C(255, 222, 168)
	light.Enabled = false
	light.Shadows = false
	light.Parent = head
	table.insert(Builder.streetLights, { light = light, head = head })
end

-- Carrito de supermercado (el frente mira a -Z)
function Builder.cart(parent, cf)
	local m = Instance.new("Model")
	m.Name = "Carrito"
	local metal, red = C(170, 174, 180), C(170, 55, 50)
	local function p(name, size, offset, color, extra)
		local props = { Name = name, Size = size, CFrame = cf * offset, Color = color or metal, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = m }
		for k, v in extra or {} do
			props[k] = v
		end
		return part(props)
	end
	p("Bottom", V(1.4, 0.06, 2), CFrame.new(0, 1.6, 0))
	p("SideL", V(0.05, 1, 2), CFrame.new(-0.7, 2.1, 0))
	p("SideR", V(0.05, 1, 2), CFrame.new(0.7, 2.1, 0))
	p("Front", V(1.4, 1, 0.05), CFrame.new(0, 2.1, -1))
	p("Back", V(1.4, 1.1, 0.05), CFrame.new(0, 2.15, 1))
	p("Handle", V(1.5, 0.12, 0.12), CFrame.new(0, 2.85, 1.25), red, { Material = Enum.Material.SmoothPlastic })
	p("Tray", V(1.2, 0.05, 1.6), CFrame.new(0, 0.55, 0))
	for _, x in { -0.6, 0.6 } do
		p("Leg", V(0.06, 1.5, 0.06), CFrame.new(x, 0.85, 0.9))
		p("Leg", V(0.06, 1.5, 0.06), CFrame.new(x, 0.85, -0.9))
		for _, z in { -0.85, 0.85 } do
			p("Wheel", V(0.12, 0.3, 0.3), CFrame.new(x, 0.15, z), C(35, 35, 38), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Rubber })
		end
	end
	m.Parent = parent
	return m
end

-- Banco de plaza con dos asientos (el frente mira hacia `facing`)
local function outdoorBench(parent, position, facing)
	local cf = CFrame.lookAt(position, position + facing)
	local wood, metal = C(150, 105, 70), C(50, 52, 58)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	part({ Name = "BenchBack", Size = V(5, 1, 0.2), CFrame = at(0, 2.5, 0.8) * CFrame.Angles(math.rad(-10), 0, 0), Color = wood, Material = Enum.Material.Wood, Parent = parent })
	for _, x in { -2.2, 2.2 } do
		part({ Name = "BenchLeg", Size = V(0.2, 1.4, 1.5), CFrame = at(x, 0.95, 0.1), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	end
	for _, x in { -1.2, 1.2 } do
		local seat = part({ ClassName = "Seat", Name = "BenchSeat", Size = V(2.3, 0.3, 1.5), CFrame = at(x, 1.7, 0.1), Color = wood, Material = Enum.Material.Wood, Parent = parent })
		seat.Disabled = true -- los jugadores no se sientan sin querer al pasar
		seat:SetAttribute("StandPoint", (at(x, 0, -1.6)).Position)
		table.insert(Builder.benchSeats, seat)
	end
end
Builder.outdoorBench = outdoorBench

-- Parada de colectivo con techito y banco (el banco mira a la calle, +Z)
local function busStop(parent, position)
	local metal, glassColor = C(60, 64, 72), C(150, 180, 195)
	part({ Name = "BusStopRoof", Size = V(7, 0.3, 2.8), Position = position + V(0, 7.2, -0.1), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	part({ Name = "BusStopBack", Size = V(7, 5.6, 0.12), Position = position + V(0, 4.2, -1.3), Color = glassColor, Material = Enum.Material.SmoothPlastic, Transparency = 0.6, CastShadow = false, Parent = parent })
	for _, x in { -3.4, 3.4 } do
		part({ Name = "BusStopPost", Size = V(0.25, 7, 0.25), Position = position + V(x, 3.6, -1.3), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	end
	local sign = part({ Name = "BusStopSign", Size = V(1.6, 1.6, 0.1), Position = position + V(-4.4, 6.2, -1.3), Color = C(40, 90, 160), Parent = parent })
	surfaceText(sign, Enum.NormalId.Front, "🚌 PARADA", { color = C(240, 235, 220) })
	surfaceText(sign, Enum.NormalId.Back, "🚌 PARADA", { color = C(240, 235, 220) })
	part({ Name = "BusStopSignPole", Size = V(0.2, 6, 0.2), Position = position + V(-4.4, 3, -1.3), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	outdoorBench(parent, position + V(0, 0, -0.3), V(0, 0, 1))
end

---------------------------------------------------------------------------
-- Barrio: calles, veredas, casas, árboles, faroles
---------------------------------------------------------------------------
local function buildNeighborhood(parent)
	-- Calle principal (frente al super) y veredas
	block(parent, "MainStreet", -320, 320, -0.1, 0.1, 80, 96, COLORS.asphalt, Enum.Material.Asphalt)
	block(parent, "SidewalkNear", -320, 320, -0.15, 0.25, 76, 80, COLORS.sidewalk, Enum.Material.Concrete)
	block(parent, "SidewalkFar", -320, 320, -0.15, 0.25, 96, 100, COLORS.sidewalk, Enum.Material.Concrete)
	for x = -316, 316, 10 do
		block(parent, "Dash", x, x + 5, 0.1, 0.12, 87.8, 88.2, C(240, 200, 40))
	end
	for z = 81, 95, 2 do
		block(parent, "Zebra", -5, 5, 0.1, 0.12, z, z + 1, COLORS.line)
	end

	-- Calles laterales y trasera
	block(parent, "LeftStreet", -93, -77, -0.1, 0.1, -160, 80, COLORS.asphalt, Enum.Material.Asphalt)
	block(parent, "LeftWalkA", -97, -93, -0.15, 0.25, -160, 76, COLORS.sidewalk, Enum.Material.Concrete)
	block(parent, "LeftWalkB", -77, -73, -0.15, 0.25, -160, 76, COLORS.sidewalk, Enum.Material.Concrete)
	block(parent, "RightStreet", 87, 103, -0.1, 0.1, -160, 80, COLORS.asphalt, Enum.Material.Asphalt)
	block(parent, "RightWalkA", 83, 87, -0.15, 0.25, -160, 76, COLORS.sidewalk, Enum.Material.Concrete)
	block(parent, "RightWalkB", 103, 107, -0.15, 0.25, -160, 76, COLORS.sidewalk, Enum.Material.Concrete)
	block(parent, "BackStreet", -73, 83, -0.1, 0.1, -68, -52, COLORS.asphalt, Enum.Material.Asphalt)
	block(parent, "BackWalk", -73, 83, -0.15, 0.25, -72, -68, COLORS.sidewalk, Enum.Material.Concrete)

	-- Casas
	local housesFolder = Instance.new("Folder")
	housesFolder.Name = "Casas"
	housesFolder.Parent = parent
	for x = -122, 130, 28 do
		if math.abs(x) > 6 then
			buildHouse(housesFolder, CFrame.lookAt(V(x, 0, 105), V(x, 0, 90)))
		end
	end
	for z = -134, 50, 28 do
		buildHouse(housesFolder, CFrame.lookAt(V(-102, 0, z), V(-90, 0, z)))
		buildHouse(housesFolder, CFrame.lookAt(V(112, 0, z), V(100, 0, z)))
	end
	for x = -56, 60, 29 do
		buildHouse(housesFolder, CFrame.lookAt(V(x, 0, -77), V(x, 0, -60)))
	end

	-- Árboles y faroles
	local deco = Instance.new("Folder")
	deco.Name = "Arboles"
	deco.Parent = parent
	for x = -300, 300, 24 do
		if math.abs(x) > 8 then
			tree(deco, V(x + 12, 0.25, 98.5))
		end
		streetLamp(deco, V(x, 0.25, 77.5))
	end
	for z = -150, 60, 30 do
		tree(deco, V(-75, 0.25, z + 10))
		tree(deco, V(105, 0.25, z + 10))
		streetLamp(deco, V(-95, 0.25, z), V(1, 0, 0))
		streetLamp(deco, V(85, 0.25, z), V(1, 0, 0))
	end
	for x = -60, 60, 30 do
		tree(deco, V(x, 0.25, -46))
	end
end

---------------------------------------------------------------------------
-- Edificio
---------------------------------------------------------------------------
local function wall(parent, name, x1, x2, y1, y2, z1, z2)
	local p = block(parent, name, x1, x2, y1, y2, z1, z2, COLORS.facade)
	table.insert(Builder.paintable.walls, p)
	return p
end

local function wallBlock(parent, name, x1, x2, y1, y2, z1, z2)
	return wall(parent, name, x1, x2, y1, y2, z1, z2)
end

-- Vidrio "falso" (plástico transparente): el material Glass de Roblox oculta lo transparente que hay detrás
local function glass(parent, name, x1, x2, y1, y2, z1, z2)
	return block(parent, name, x1, x2, y1, y2, z1, z2, COLORS.glass, Enum.Material.SmoothPlastic, { Transparency = 0.72, Reflectance = 0.12, CastShadow = false, CanQuery = false })
end

---------------------------------------------------------------------------
-- Pisos de arriba y escalera
---------------------------------------------------------------------------
-- Hueco en cada losa, justo arriba del segundo tramo de la escalera (alineado con las baldosas)
local HOLE = { minX = 15, maxX = 25, minZ = 5, maxZ = 10 }
Builder.HOLE = HOLE

-- Losa (techo / cielorraso) en piezas alrededor del hueco; el hueco queda tapado con una "tapa"
-- que se saca al comprar el piso de arriba (expansionId)
function Builder.slabWithHole(parent, name, x1, x2, y1, y2, z1, z2, expansionId, color, material, extra)
	local pieces = {
		{ x1, x2, z1, HOLE.minZ },
		{ x1, x2, HOLE.maxZ, z2 },
		{ x1, HOLE.minX, HOLE.minZ, HOLE.maxZ },
		{ HOLE.maxX, x2, HOLE.minZ, HOLE.maxZ },
	}
	for _, r in pieces do
		if r[2] > r[1] and r[4] > r[3] then
			block(parent, name, r[1], r[2], y1, y2, r[3], r[4], color, material, extra)
		end
	end
	return block(parent, "Hatch_" .. expansionId .. "_" .. name, HOLE.minX, HOLE.maxX, y1, y2, HOLE.minZ, HOLE.maxZ, color, material, extra)
end

local STAIR_COLOR, STEP_COLOR = C(150, 148, 144), C(186, 182, 174)

-- Tramo de escalera: rampa invisible (para caminar) + escalones de adorno encima
local function flight(parent, fromX, toX, z1, z2, y0, rise)
	local dir = toX > fromX and 1 or -1
	local run = math.abs(toX - fromX)
	local cx, cz = (fromX + toX) / 2, (z1 + z2) / 2
	local center = V(cx, y0 + 0.3 + rise / 2, cz)
	-- La cuña sube hacia su +Z local: la apuntamos en la dirección del tramo
	part({
		ClassName = "WedgePart",
		Name = "StairRamp",
		Size = V(z2 - z1, rise, run),
		CFrame = CFrame.lookAt(center, center - V(dir, 0, 0)),
		Transparency = 1,
		CastShadow = false,
		Parent = parent,
	})
	local steps = 10
	for k = 1, steps do
		local xa = fromX + dir * (k - 1) * run / steps
		local xb = fromX + dir * k * run / steps
		block(parent, "Step", math.min(xa, xb), math.max(xa, xb), y0 + (k - 1) * rise / steps, y0 + k * rise / steps, z1, z2, STEP_COLOR, Enum.Material.Concrete, { CanCollide = false, CanQuery = false })
	end
end

-- Escalera del piso `level` al siguiente (dos tramos con descanso, siempre en el mismo lugar)
local function buildStairs(parent, level)
	local y0 = Config.levelY(level)
	local slabBottom = (level + 1) * Config.LEVEL_HEIGHT - 1
	local half = Config.LEVEL_HEIGHT / 2
	local f = Instance.new("Folder")
	f.Name = "Escalera_" .. level
	f.Parent = parent
	-- Tramo 1 (sube hacia +X), descanso, tramo 2 (sube hacia -X hasta el piso de arriba)
	flight(f, 15, 25, 0.9, 4.4, y0, half)
	block(f, "Landing", 25, 29.5, y0, y0 + half, 0.9, 9.6, STAIR_COLOR, Enum.Material.Concrete)
	flight(f, 25, 15, 5.5, 9.5, y0 + half, half)
	-- Pared del medio y pared exterior (hacen de baranda)
	wallBlock(f, "StairDivider", 15, 25, y0, slabBottom, 4.5, 5.3)
	wallBlock(f, "StairWallOuter", 15, 30, y0, slabBottom, 9.7, 10.1)
	if level == 0 then
		-- en planta baja: base maciza debajo del tramo 2 y paredes del fondo y del costado
		block(f, "StairBase", 15, 25, y0, y0 + half, 5.4, 9.6, STAIR_COLOR, Enum.Material.Concrete)
		wallBlock(f, "StairWallBack", 14.6, 30, y0, slabBottom, 0.3, 0.8)
		wallBlock(f, "StairWallSide", 29.5, 30, y0, slabBottom, 0.3, 10.1)
	end
	-- Cartel al pie de la escalera
	local sign = block(f, "StairSign", 13.2, 13.4, y0 + 6, y0 + 7.4, 0.9, 4.4, C(40, 90, 160))
	surfaceText(sign, Enum.NormalId.Left, (level == 0 and "SUBE AL 1° PISO" or "SUBE AL 2° PISO"), { color = C(240, 235, 220) })
	block(f, "StairSignPole", 13.25, 13.35, y0, y0 + 6, 2.6, 2.7, C(60, 62, 66), Enum.Material.Metal)
	return f
end

-- Barandas alrededor del hueco en el piso de más arriba (se sacan si después se compra otro piso)
local function topRailings(parent, level)
	local y0 = Config.levelY(level)
	local f = Instance.new("Folder")
	f.Name = "Barandas_" .. level
	f.Parent = parent
	local metal = C(150, 154, 160)
	for _, r in { { 15, 25, 4.6, 5.0 }, { 15, 25.4, 9.7, 10.1 }, { 25, 25.4, 5.0, 10.1 } } do
		block(f, "Railing", r[1], r[2], y0 + 3.2, y0 + 3.5, r[3], r[4], metal, Enum.Material.Metal)
		block(f, "RailingGlass", r[1], r[2], y0, y0 + 3.2, r[3] + 0.1, r[4] - 0.1, COLORS.glass, Enum.Material.SmoothPlastic, { Transparency = 0.6, CastShadow = false, CanQuery = false })
	end
	return f
end

-- Construye el piso `level` (1 o 2) encima de la tienda principal
local function buildUpperFloor(parent, level)
	local yb = level * Config.LEVEL_HEIGHT
	local fy = yb + FLOOR_Y
	local f = Instance.new("Folder")
	f.Name = "Piso_" .. level
	f.Parent = parent
	-- Baldosas (sin el hueco de la escalera)
	for x = -30, 25, 5 do
		for z = 0, 25, 5 do
			if not (x >= HOLE.minX and x < HOLE.maxX and z >= HOLE.minZ and z < HOLE.maxZ) then
				local tile = block(f, "Tile", x, x + 5, yb, fy, z, z + 5, C(212, 208, 200))
				local parity = (math.floor(x / 5) + math.floor(z / 5)) % 2
				table.insert(Builder.paintable.tiles, { part = tile, parity = parity })
				tagFloor(tile)
			end
		end
	end
	-- Paredes con vidrieras al frente
	local top = yb + H
	wall(f, "UpperWallW", -30.5, -29.5, yb, top, -0.5, 31)
	wall(f, "UpperWallE", 29.5, 30.5, yb, top, -0.5, 31)
	wall(f, "UpperWallBack", -30.5, 30.5, yb, top, -0.5, 0.5)
	wall(f, "UpperFrontLow", -29.5, 29.5, yb, yb + 1.5, 30, 31)
	wall(f, "UpperFrontHigh", -29.5, 29.5, yb + 10, top, 30, 31)
	glass(f, "UpperWindow", -29.5, 29.5, yb + 1.5, yb + 10, 30.3, 30.7)
	for x = -24, 24, 6 do
		block(f, "Mullion", x - 0.15, x + 0.15, yb + 1.5, yb + 10, 30.2, 30.8, COLORS.frame)
	end
	for _, spec in { { -29.4, -28.9, 0.5, 29.9 }, { 28.9, 29.4, 0.5, 29.9 }, { -29.4, 29.4, 0.5, 1 } } do
		local stripe = block(f, "Stripe", spec[1], spec[2], yb + 8.5, yb + 9.4, spec[3], spec[4], COLORS.trim)
		table.insert(Builder.paintable.stripes, stripe)
	end
	-- Techo y cielorraso (con el hueco tapado para el piso siguiente)
	local nextExp = "floor" .. (level + 1)
	Builder.slabWithHole(f, "UpperRoof", -30.5, 30.5, top, top + 1, -0.5, 31, nextExp, COLORS.roof, Enum.Material.SmoothPlastic)
	Builder.slabWithHole(f, "UpperCeiling", -29.5, 29.5, top - 0.06, top - 0.01, 0.5, 30, nextExp, C(200, 198, 192), Enum.Material.SmoothPlastic, { CastShadow = false })
	block(f, "UpperParapet", -30.5, 30.5, top + 1, top + 1.6, 30.6, 31.2, COLORS.trim)
	-- Luces (menos donde está la escalera)
	local count = 0
	for _, x in { -25, -15, -5, 5, 15, 25 } do
		for _, z in { 5, 15, 25 } do
			if not (x >= 13 and z <= 11) then
				count += 1
				local panel = part({ Name = "CeilingLight", Size = V(4, 0.2, 1.4), Position = V(x, top - 0.15, z), Color = COLORS.lamp, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = f })
				local light = Instance.new("SurfaceLight")
				light.Face = Enum.NormalId.Bottom
				light.Range = 20
				light.Brightness = 0.85
				light.Angle = 120
				light.Color = C(255, 236, 210)
				light.Shadows = false
				light.Parent = panel
				if count % 3 == 0 then
					local fill = Instance.new("PointLight")
					fill.Range = 16
					fill.Brightness = 0.3
					fill.Color = C(255, 236, 210)
					fill.Shadows = false
					fill.Parent = panel
				end
			end
		end
	end
	-- Cartel del piso junto a la escalera
	local sign = block(f, "FloorSign", 13.2, 13.4, yb + 6, yb + 7.4, 5.5, 9.5, C(40, 90, 160))
	surfaceText(sign, Enum.NormalId.Left, (level == 1 and "BAJA A PLANTA BAJA" or "BAJA AL 1° PISO"), { color = C(240, 235, 220) })
	return f
end

local function buildBuilding(s)
	-- Pisos: tienda con baldosas, depósito de cemento, oficina de madera
	for zoneId, zone in Config.Zones do
		if zone.level then
			-- los pisos de arriba se construyen al comprarlos
			continue
		elseif zone.kind == "shop" then
			for x = zone.minX, zone.maxX - 5, 5 do
				for z = zone.minZ, zone.maxZ - 5, 5 do
					local tile = block(s, "Tile", x, x + 5, 0, FLOOR_Y, z, z + 5, C(212, 208, 200))
					local parity = (math.floor(x / 5) + math.floor(z / 5)) % 2
					table.insert(Builder.paintable.tiles, { part = tile, parity = parity })
					tagFloor(tile)
				end
			end
		elseif zone.kind == "storage" then
			tagFloor(block(s, "StorageFloor_" .. zoneId, zone.minX, zone.maxX, 0, FLOOR_Y, zone.minZ, zone.maxZ, COLORS.storageFloor, Enum.Material.Concrete))
		end
	end
	block(s, "OfficeFloor", -60, -47, FLOOR_Y, FLOOR_Y + 0.02, 19, 30, COLORS.wood, Enum.Material.WoodPlanks)

	-- Pared del frente (z = 30..31) con vidrieras, entrada, portón del depósito y ventana de la oficina
	wall(s, "Front1", -61, -58, 0, H, 30, 31)
	wall(s, "OfficeWinLow", -58, -50, 0, 3, 30, 31)
	glass(s, "OfficeWindow", -58, -50, 3, 9, 30.3, 30.7)
	wall(s, "OfficeWinHigh", -58, -50, 9, H, 30, 31)
	wall(s, "Front2", -50, -45, 0, H, 30, 31)
	wall(s, "GateTop", -45, -33, 11, H, 30, 31)
	block(s, "GateRoll", -45, -33, 11, 12.2, 30.9, 32, C(120, 125, 130), Enum.Material.DiamondPlate)
	wall(s, "Front3", -33, -28, 0, H, 30, 31)
	for _, range in { { -28, -4 }, { 4, 28 } } do
		wall(s, "ShopWinLow", range[1], range[2], 0, 1, 30, 31)
		glass(s, "ShopWindow", range[1], range[2], 1, 11, 30.3, 30.7)
		wall(s, "ShopWinHigh", range[1], range[2], 11, H, 30, 31)
		for x = range[1], range[2], 6 do
			block(s, "Mullion", x - 0.15, x + 0.15, 1, 11, 30.2, 30.8, COLORS.frame)
		end
	end
	wall(s, "DoorTop", -4, 4, 10, H, 30, 31)
	wall(s, "Front4", 28, 61, 0, H, 30, 31)

	-- Laterales y fondo
	wall(s, "LeftWall", -61, -60, 0, H, -31, 30)
	wall(s, "RightWall", 60, 61, 0, H, -31, 30)
	wall(s, "BackWall", -60, 60, 0, H, -31, -30)

	-- Pared tienda <-> depósito con puerta de personal
	wall(s, "StaffWallA", -30.5, -29.5, 0, H, -30, 9)
	wall(s, "StaffWallB", -30.5, -29.5, 0, H, 15, 30)
	wall(s, "StaffDoorTop", -30.5, -29.5, 10, H, 9, 15)
	local staffSign = block(s, "StaffSign", -29.4, -29.3, 10.5, 12, 9.5, 14.5, C(40, 40, 45))
	surfaceText(staffSign, Enum.NormalId.Right, "SOLO PERSONAL · DEPÓSITO", { color = C(235, 230, 220) })

	-- Oficina del gerente
	wall(s, "OfficeWallA", -47.5, -46.5, 0, H, 19, 21)
	wall(s, "OfficeWallB", -47.5, -46.5, 0, H, 25, 30)
	wall(s, "OfficeDoorTop", -47.5, -46.5, 9, H, 21, 25)
	wall(s, "OfficeWallBack", -60, -46.5, 0, H, 18.5, 19.5)
	local officeSign = block(s, "OfficeSign", -46.4, -46.3, 9.4, 10.6, 21.2, 24.8, C(40, 40, 45))
	surfaceText(officeSign, Enum.NormalId.Right, "OFICINA", { color = C(235, 230, 220) })

	-- Divisiones de las ampliaciones (se quitan al comprarlas)
	local p1 = wall(s, "Partition_shop1", -29.5, 29.5, 0, H, -0.5, 0.5)
	surfaceText(p1, Enum.NormalId.Back, "🔒 AMPLIACIÓN DISPONIBLE", { color = C(90, 90, 95) })
	local p2 = wall(s, "Partition_shop2", 29.5, 30.5, 0, H, -30, 30)
	surfaceText(p2, Enum.NormalId.Left, "🔒 AMPLIACIÓN DISPONIBLE", { color = C(90, 90, 95) })
	local p3 = wall(s, "Partition_storage1", -60, -30.5, 0, H, 4.5, 5.5)
	surfaceText(p3, Enum.NormalId.Back, "🔒 AMPLIACIÓN DEL DEPÓSITO", { color = C(90, 90, 95) })

	-- Franja de color en las paredes interiores de la tienda
	for _, spec in {
		{ "Stripe", -29.4, -28.9, 0.5, 9 }, -- pared del depósito (lado tienda)
		{ "Stripe", -29.4, -28.9, 15, 29.4 },
		{ "Stripe_shop1", -28.9, 29.4, 0.5, 1 }, -- división trasera (se va con la ampliación)
		{ "Stripe", -29.5, 29.5, -29.9, -29.4 }, -- pared del fondo
	} do
		local stripe = block(s, spec[1], spec[2], spec[3], 8.5, 9.4, spec[4], spec[5], COLORS.trim)
		table.insert(Builder.paintable.stripes, stripe)
	end

	-- Techo y cartel
	-- El techo tiene el hueco de la escalera tapado hasta que se compra el primer piso
	Builder.slabWithHole(s, "Roof", -61, 61, H, H + 1, -31, 31, "floor1", COLORS.roof, Enum.Material.SmoothPlastic)
	block(s, "Parapet", -61, 61, H + 1, H + 1.6, 30.6, 31.2, COLORS.trim)
	local sign = block(s, "StoreSign", -20, 20, H + 1.6, H + 6.6, 30.8, 31.4, COLORS.trim)
	Builder.storeSign = sign
	Builder.storeSignLabel = surfaceText(sign, Enum.NormalId.Back, Config.DEFAULT_STORE_NAME, { color = C(235, 230, 220), font = Enum.Font.FredokaOne })

	-- Puertas automáticas de vidrio
	Builder.doorPanels = {}
	for _, side in { -1, 1 } do
		local panel = glass(s, "AutoDoor", side * 4, 0, FLOOR_Y, 10, 30.35, 30.65)
		panel.CanCollide = false
		table.insert(Builder.doorPanels, { part = panel, closed = panel.CFrame, open = panel.CFrame * CFrame.new(side * 3.6, 0, 0) })
	end
	block(s, "DoorMat", -4, 4, FLOOR_Y, FLOOR_Y + 0.03, 26, 30, C(60, 60, 70), Enum.Material.Fabric)

	-- Cielorraso claro (las lámparas quedan embutidas)
	Builder.slabWithHole(s, "Ceiling", -60, 60, H - 0.06, H - 0.01, -30, 30, "floor1", C(200, 198, 192), Enum.Material.SmoothPlastic, { CastShadow = false })

	-- Alero sobre la entrada con luces y cartel
	local canopy = block(s, "EntranceCanopy", -8, 8, 10.4, 10.9, 31, 35.5, COLORS.trim)
	surfaceText(canopy, Enum.NormalId.Back, "ENTRADA  ·  ABIERTO 08:00 A 22:30", { color = C(235, 230, 220) })
	for _, x in { -7.5, 7.5 } do
		block(s, "CanopyPost", x - 0.2, x + 0.2, 0.25, 10.4, 34.9, 35.3, C(70, 72, 78), Enum.Material.Metal)
	end
	for _, x in { -4, 4 } do
		local downlight = block(s, "CanopyLight", x - 0.6, x + 0.6, 10.35, 10.4, 32.6, 33.8, COLORS.lamp, Enum.Material.Neon, { CastShadow = false })
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Bottom
		l.Range = 14
		l.Brightness = 0.8
		l.Angle = 90
		l.Color = C(255, 230, 200)
		l.Shadows = false
		l.Parent = downlight
	end

	-- Cartel de ABIERTO / CERRADO en la entrada: con un click se abre o se cierra el súper
	block(s, "OpenSignFoot", 9.6, 11.4, 0.25, 0.45, 33.2, 34.4, C(60, 62, 66), Enum.Material.Metal)
	block(s, "OpenSignPole", 10.3, 10.7, 0.45, 4.1, 33.6, 34.0, C(70, 72, 78), Enum.Material.Metal)
	local openSign = block(s, "OpenSign", 8.4, 12.6, 4.0, 6.6, 33.62, 33.98, C(36, 38, 44))
	Builder.openSign = openSign
	Builder.openSignLabels = {
		surfaceText(openSign, Enum.NormalId.Back, "", { color = C(235, 230, 220), rich = true }),
		surfaceText(openSign, Enum.NormalId.Front, "", { color = C(235, 230, 220), rich = true }),
	}
	Builder.openSignGlow = block(s, "OpenSignGlow", 8.3, 12.7, 6.6, 6.8, 33.58, 34.02, C(200, 60, 60), Enum.Material.Neon, { CastShadow = false, CanQuery = false })

	-- Pila de canastos junto a la entrada (adentro)
	block(s, "BasketStand", 6.2, 7.8, FLOOR_Y, 0.6, 26.3, 27.7, C(70, 72, 78), Enum.Material.Metal)
	for i = 0, 5 do
		block(s, "Basket", 6.3, 7.7, 0.6 + i * 0.28, 0.85 + i * 0.28, 26.4, 27.6, C(170, 55, 50), nil, { CastShadow = false })
	end

	-- Equipos de aire acondicionado en el techo
	for _, x in { -40, -10, 25 } do
		block(s, "RoofAC", x - 2, x + 2, H + 1, H + 3.2, -10, -6, C(165, 168, 172), Enum.Material.DiamondPlate)
		block(s, "RoofACFan", x - 1.4, x + 1.4, H + 3.2, H + 3.3, -9.4, -6.6, C(60, 62, 66), nil, { CastShadow = false })
	end

	-- Vereda del edificio y estacionamiento (la zona de descarga está pintada sobre el asfalto)
	block(s, "BuildingWalk", -61, 61, -0.15, 0.25, 31, 33, COLORS.sidewalk, Enum.Material.Concrete)
	local parking = block(s, "Parking", -50, 60, -0.1, 0.15, 33, 76, COLORS.asphalt, Enum.Material.Asphalt)
	tagFloor(parking)
	for x = -22, 56, 6 do
		block(s, "ParkLine", x - 0.15, x + 0.15, 0.15, 0.17, 58, 70, COLORS.line, nil, { CastShadow = false })
	end
	block(s, "ParkLineFar", -22, 56, 0.15, 0.17, 69.85, 70.15, COLORS.line, nil, { CastShadow = false })
	for x = -19, 53, 6 do
		block(s, "WheelStop", x - 1.3, x + 1.3, 0.15, 0.45, 68.8, 69.4, C(160, 156, 150), Enum.Material.Concrete)
	end
	-- Pasillo del estacionamiento con dos carriles: se entra por z=55 (hacia +X) y se sale por z=47.5 (hacia -X)
	for x = -14, 50, 16 do
		block(s, "AisleArrow", x - 1.5, x + 1.5, 0.15, 0.17, 54.8, 55.2, COLORS.line, nil, { CastShadow = false })
		block(s, "ArrowTip", x + 1.3, x + 1.9, 0.15, 0.17, 54.4, 55.6, COLORS.line, nil, { CastShadow = false })
		block(s, "AisleArrow", x - 1.5, x + 1.5, 0.15, 0.17, 47.3, 47.7, COLORS.line, nil, { CastShadow = false })
		block(s, "ArrowTip", x - 1.9, x - 1.3, 0.15, 0.17, 46.9, 48.1, COLORS.line, nil, { CastShadow = false })
	end
	for x = -22, 52, 6 do
		block(s, "AisleCenterLine", x, x + 3, 0.15, 0.17, 51.1, 51.4, COLORS.yellow, nil, { CastShadow = false })
	end

	-- Zona de carga y descarga: marco amarillo pintado sobre el asfalto
	local dockRect = { minX = -47, maxX = -31, minZ = 33.6, maxZ = 42.6 }
	block(s, "DockLine", dockRect.minX, dockRect.maxX, 0.15, 0.18, dockRect.minZ, dockRect.minZ + 0.3, COLORS.yellow, nil, { CastShadow = false })
	block(s, "DockLine", dockRect.minX, dockRect.maxX, 0.15, 0.18, dockRect.maxZ - 0.3, dockRect.maxZ, COLORS.yellow, nil, { CastShadow = false })
	block(s, "DockLine", dockRect.minX, dockRect.minX + 0.3, 0.15, 0.18, dockRect.minZ, dockRect.maxZ, COLORS.yellow, nil, { CastShadow = false })
	block(s, "DockLine", dockRect.maxX - 0.3, dockRect.maxX, 0.15, 0.18, dockRect.minZ, dockRect.maxZ, COLORS.yellow, nil, { CastShadow = false })
	local dockLabel = block(s, "DockLabel", -44, -34, 0.15, 0.18, 43, 44.4, COLORS.asphalt, nil, { CastShadow = false })
	surfaceText(dockLabel, Enum.NormalId.Top, "CARGA Y DESCARGA", { color = COLORS.yellow })
	for _, pos in { V(-48.8, 0, 43.6), V(-29.2, 0, 43.6) } do
		part({ Name = "Bollard", Shape = Enum.PartType.Cylinder, Size = V(3, 0.7, 0.7), CFrame = CFrame.new(pos + V(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = COLORS.yellow, Parent = s })
		part({ Name = "BollardBand", Shape = Enum.PartType.Cylinder, Size = V(0.4, 0.74, 0.74), CFrame = CFrame.new(pos + V(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(40, 40, 42), CastShadow = false, Parent = s })
	end
	Builder.deliveryRect = { minX = -46, maxX = -32, minZ = 34.5, maxZ = 41.5 }

	-- Cartel del estacionamiento
	block(s, "ParkingSignPole", 57.8, 58.2, 0.15, 7, 73.8, 74.2, C(70, 72, 78), Enum.Material.Metal)
	local parkingSign = block(s, "ParkingSign", 55.5, 60.5, 5.2, 7.8, 73.9, 74.1, C(40, 80, 150))
	surfaceText(parkingSign, Enum.NormalId.Back, "P  ESTACIONAMIENTO\nCLIENTES", { color = C(235, 230, 220) })

	-- Bancos afuera, contra la vidriera (miran al estacionamiento) y parada de colectivo en la vereda
	for _, x in { -22, 16, 23 } do
		outdoorBench(s, V(x, 0.25, 31.9), V(0, 0, 1))
	end
	busStop(s, V(24, 0.25, 77.6))

	-- Corral de carritos
	for _, x in { 12, 18 } do
		block(s, "CartRail", x - 0.1, x + 0.1, 0.15, 3, 35, 39, C(150, 154, 160), Enum.Material.Metal)
	end
	block(s, "CartRailTop", 12, 18, 2.9, 3.1, 35, 35.2, C(150, 154, 160), Enum.Material.Metal)
	for i = 0, 2 do
		Builder.cart(s, CFrame.new(15, 0.15, 36.2 + i * 1.1))
	end

	-- Zona "solo personal" para el pathfinding: los clientes no cruzan por el depósito ni la oficina
	local staffOnly = part({
		Name = "StaffOnlyZone",
		Size = V(31, 10, 62),
		Position = V(-45.5, 5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = s,
	})
	local modifier = Instance.new("PathfindingModifier")
	modifier.Label = "StaffOnly"
	modifier.Parent = staffOnly
end

---------------------------------------------------------------------------
-- Oficina: pizarras, botones de abrir/cerrar
---------------------------------------------------------------------------
local function buildOffice(s, refs)
	local boards = {}
	local function board(key, x, title, subtitle)
		local b = block(s, "Board_" .. key, x - 1.8, x + 1.8, 4.5, 7.5, 19.5, 19.7, C(35, 70, 50))
		surfaceText(b, Enum.NormalId.Back, "<b>" .. title .. "</b>\n<font size=\"14\">" .. subtitle .. "</font>", { color = C(235, 230, 220), rich = true })
		block(s, "BoardFrame", x - 1.95, x + 1.95, 4.35, 7.65, 19.45, 19.55, C(120, 85, 55), Enum.Material.Wood)
		boards[key] = prompt(b, "Usar pizarra", title, { distance = 9 })
	end
	board("orders", -57.2, "PIZARRA DEL GERENTE", "Pedidos · Ampliaciones · Préstamos")
	board("franchise", -53, "FRANQUICIA", "Puntos y mejoras")
	board("employees", -48.9, "EMPLEADOS", "Contratar y asignar puestos")
	local custom = block(s, "Board_custom", -59.9, -59.7, 4.5, 7.5, 22.7, 26.3, C(40, 60, 110))
	surfaceText(custom, Enum.NormalId.Right, "<b>PERSONALIZAR</b>\n<font size=\"14\">Colores, nombre y sala</font>", { color = C(235, 230, 220), rich = true })
	boards.custom = prompt(custom, "Usar pizarra", "PERSONALIZAR", { distance = 9 })

	-- Escritorio con los botones de la tienda
	block(s, "Desk", -58, -52, FLOOR_Y, 3.2, 26.5, 28.7, COLORS.wood, Enum.Material.Wood)
	local green = part({ Name = "OpenButton", Shape = Enum.PartType.Cylinder, Size = V(0.4, 1.2, 1.2), CFrame = CFrame.new(-56.5, 3.4, 27.6) * CFrame.Angles(0, 0, math.rad(90)), Color = C(40, 200, 80), Material = Enum.Material.Neon, Parent = s })
	local red = part({ Name = "CloseButton", Shape = Enum.PartType.Cylinder, Size = V(0.4, 1.2, 1.2), CFrame = CFrame.new(-53.5, 3.4, 27.6) * CFrame.Angles(0, 0, math.rad(90)), Color = C(220, 50, 50), Material = Enum.Material.Neon, Parent = s })
	refs.openButton = prompt(green, "Abrir tienda", "Botón verde", { distance = 7, hold = 0.4 })
	refs.closeButton = prompt(red, "Cerrar tienda", "Botón rojo", { distance = 7, hold = 0.4 })
	part({ Name = "Chair", Size = V(2, 2.4, 2), Position = V(-55, 1.4, 29.6), Color = C(40, 40, 45), Parent = s })

	-- Luz de la oficina
	local lamp = part({ Name = "OfficeLight", Size = V(3, 0.2, 1.2), Position = V(-53.5, H - 0.15, 24.5), Color = COLORS.lamp, Material = Enum.Material.Neon, CanCollide = false, Parent = s })
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 16
	light.Brightness = 1.3
	light.Parent = lamp

	refs.boards = boards
end

---------------------------------------------------------------------------
-- Puertas automáticas
---------------------------------------------------------------------------
local function startDoors()
	local doorCenter = V(0, 3, 30.5)
	local isOpen = false
	task.spawn(function()
		while true do
			task.wait(0.15)
			local near = false
			for _, p in Players:GetPlayers() do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - doorCenter).Magnitude < 9 then
					near = true
					break
				end
			end
			if not near then
				local npcs = workspace:FindFirstChild("NPCs")
				if npcs then
					for _, model in npcs:GetChildren() do
						local root = model:FindFirstChild("HumanoidRootPart")
						if root and (root.Position - doorCenter).Magnitude < 9 then
							near = true
							break
						end
					end
				end
			end
			if near ~= isOpen then
				isOpen = near
				for _, door in Builder.doorPanels do
					TweenService:Create(door.part, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CFrame = near and door.open or door.closed }):Play()
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function Builder.build()
	-- El bloque de spawn de la plantilla Baseplate quedaba dentro de la tienda: se borra en la partida
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end
	local old = workspace:FindFirstChild("Supermarket")
	if old then
		old:Destroy()
	end

	setupLighting()

	local model = Instance.new("Model")
	model.Name = "Supermarket"
	model.Parent = workspace
	Builder.model = model

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = model
	Builder.structure = structure

	local fixtures = Instance.new("Folder")
	fixtures.Name = "Fixtures"
	fixtures.Parent = model
	Builder.fixturesFolder = fixtures

	local neighborhood = Instance.new("Folder")
	neighborhood.Name = "Neighborhood"
	neighborhood.Parent = model

	part({ Name = "Ground", Size = V(700, 1, 700), Position = V(0, -0.45, 0), Color = COLORS.grass, Material = Enum.Material.Grass, Parent = structure })
	buildNeighborhood(neighborhood)
	buildBuilding(structure)

	local refs = {}
	buildOffice(structure, refs)

	-- Reciclaje: contenedor afuera y tacho adentro del depósito
	local outsideBin = block(structure, "RecycleContainer", -58, -52, 0.2, 3.6, 34, 38, C(40, 100, 200))
	surfaceText(outsideBin, Enum.NormalId.Back, "♻ RECICLAJE", { color = C(235, 230, 220) })
	local insideBin = block(structure, "RecycleBin", -33.5, -31.5, FLOOR_Y, 2.6, 26.5, 28.5, C(40, 100, 200))
	surfaceText(insideBin, Enum.NormalId.Back, "♻", { color = C(235, 230, 220) })
	refs.recycleBins = { outsideBin, insideBin }

	-- Spawn de jugadores (en el depósito, al lado de la oficina)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "StoreSpawn"
	spawn.Anchored = true
	spawn.Size = V(4, 0.2, 4)
	spawn.Position = V(-40, FLOOR_Y + 0.1, 16)
	spawn.Color = COLORS.trim
	spawn.Transparency = 1
	spawn.CastShadow = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CanCollide = false
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = structure

	Builder.addZoneLights("shop0")
	Builder.addZoneLights("storage0")
	startDoors()

	-- Límites del mapa: paredes invisibles para no salir del barrio
	local limits = Instance.new("Folder")
	limits.Name = "Limites"
	limits.Parent = structure
	local minX, maxX, minZ, maxZ = -135, 145, -115, 138
	for _, spec in {
		{ minX, maxX, minZ - 1, minZ }, { minX, maxX, maxZ, maxZ + 1 },
		{ minX - 1, minX, minZ, maxZ }, { maxX, maxX + 1, minZ, maxZ },
	} do
		block(limits, "Limit", spec[1], spec[2], -2, 80, spec[3], spec[4], Color3.new(0, 0, 0), nil, { Transparency = 1, CanQuery = false, CastShadow = false })
	end

	refs.points = {
		entranceOutside = V(0, FLOOR_Y, 36),
		entranceInside = V(0, FLOOR_Y, 24),
		staff = V(-40, FLOOR_Y, 20),
		recycleInside = V(-34.5, FLOOR_Y, 25),
		recycleOutside = V(-55, FLOOR_Y, 40),
		delivery = V(-39, FLOOR_Y, 38),
		securityPost = V(8, FLOOR_Y, 25),
	}
	refs.deliveryRect = Builder.deliveryRect
	return refs
end

function Builder.unlockExpansion(id)
	local s = Builder.structure
	if id == "shop1" then
		for _, name in { "Partition_shop1", "Stripe_shop1" } do
			local w = s:FindFirstChild(name)
			if w then
				w:Destroy()
			end
		end
		Builder.addZoneLights("shop1")
	elseif id == "shop2" then
		local w = s:FindFirstChild("Partition_shop2")
		if w then
			w:Destroy()
		end
		Builder.addZoneLights("shop2")
	elseif id == "storage1" then
		local w = s:FindFirstChild("Partition_storage1")
		if w then
			w:Destroy()
		end
		Builder.addZoneLights("storage1")
	elseif id == "floor1" or id == "floor2" then
		local level = id == "floor1" and 1 or 2
		if s:FindFirstChild("Piso_" .. level) then
			return
		end
		-- se destapa el hueco de la losa de abajo
		for _, d in s:GetDescendants() do
			if d:IsA("BasePart") and string.find(d.Name, "^Hatch_" .. id .. "_") then
				d:Destroy()
			end
		end
		-- se sacan las lámparas que quedarían sobre el hueco y las barandas del piso de abajo
		for _, d in s:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "CeilingLight" and math.abs(d.Position.Y - (level * Config.LEVEL_HEIGHT - 1)) < 1.5
				and d.Position.X > HOLE.minX - 2.5 and d.Position.X < HOLE.maxX + 2.5 and d.Position.Z > HOLE.minZ - 1.5 and d.Position.Z < HOLE.maxZ + 1.5 then
				d:Destroy()
			end
		end
		local oldRailings = s:FindFirstChild("Barandas_" .. (level - 1), true)
		if oldRailings then
			oldRailings:Destroy()
		end
		buildStairs(s, level - 1)
		buildUpperFloor(s, level)
		if level < Config.MAX_LEVEL and not s:FindFirstChild("Piso_" .. (level + 1)) then
			topRailings(s, level)
		end
	end
end

function Builder.applyCustom(custom)
	local floor = Config.FloorPresets[custom.floor] or Config.FloorPresets[1]
	for _, tile in Builder.paintable.tiles do
		tile.part.Color = tile.parity == 0 and floor.a or floor.b
	end
	local walls = Config.WallPresets[custom.walls] or Config.WallPresets[1]
	for _, w in Builder.paintable.walls do
		if w.Parent then
			w.Color = walls.color
		end
	end
	for _, stripe in Builder.paintable.stripes do
		if stripe.Parent then
			stripe.Color = walls.stripe
		end
	end
	if Builder.storeSign then
		Builder.storeSign.Color = Config.SignColors[custom.signColor] or Config.SignColors[1]
		Builder.storeSignLabel.Text = custom.storeName or Config.DEFAULT_STORE_NAME
	end
end

-- Cartel de la entrada según la fase del día
local SIGN_STATES = {
	Cerrado = { title = "CERRADO", sub = "Click para ABRIR", color = C(200, 60, 60) },
	Abierto = { title = "ABIERTO", sub = "08:00 a 22:30", color = C(60, 180, 90) },
	Cierre = { title = "CERRANDO", sub = "Click para CERRAR el día", color = C(225, 150, 50) },
}
function Builder.setOpenSign(phase)
	local st = SIGN_STATES[phase] or SIGN_STATES.Cerrado
	if not Builder.openSign then
		return
	end
	for _, label in Builder.openSignLabels do
		label.Text = "<b>" .. st.title .. "</b>\n<font size=\"14\">" .. st.sub .. "</font>"
		label.TextColor3 = st.color:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	Builder.openSignGlow.Color = st.color
end

function Builder.setNight(isNight)
	for _, lamp in Builder.streetLights do
		lamp.light.Enabled = isNight
		lamp.head.Material = isNight and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
	for _, window in Builder.houseWindows do
		if math.random() < 0.7 then
			window.Material = isNight and Enum.Material.Neon or Enum.Material.Glass
			window.Color = isNight and C(255, 220, 150) or COLORS.glass
		end
	end
end

return Builder
