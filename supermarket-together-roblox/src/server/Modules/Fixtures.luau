-- Muebles que construyen los jugadores (TAB): estanterías, heladeras, freezers, cajas,
-- autocajas, estantes de depósito y decoración. Maneja los productos de cada nivel y las cajas guardadas.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Products = require(script.Parent.Products)

local Fixtures = {}
Fixtures.list = {} -- [id] = fixture
Fixtures.removeGuards = {} -- function(fixture) -> ok, motivo
local createdListeners, removedListeners = {}, {}
local nextId = 0

local fmt = Config.formatMoney
local V, C = Vector3.new, Color3.fromRGB
local surfaceText = StoreBuilder.surfaceText

function Fixtures.onCreated(fn)
	table.insert(createdListeners, fn)
end

function Fixtures.onRemoved(fn)
	table.insert(removedListeners, fn)
end

---------------------------------------------------------------------------
-- Niveles de productos de cada mueble (coordenadas locales; el frente mira a -Z)
---------------------------------------------------------------------------
local function levels(tops, width, depth, height)
	local list = {}
	for i, top in tops do
		list[i] = { origin = V(0, top, 0), width = width, depth = depth, height = height }
	end
	return list
end

local SLOT_SPECS = {
	product_shelf = levels({ 0.5, 2.15, 3.8, 5.45 }, 11.4, 2.5, 1.55),
	fridge = levels({ 0.6, 2.3, 4.0, 5.7 }, 7.3, 2.3, 1.6),
	freezer = {
		{ origin = V(-1.9, 0.6, 0), width = 3.6, depth = 3.4, height = 2.4, stack = true },
		{ origin = V(1.9, 0.6, 0), width = 3.6, depth = 3.4, height = 2.4, stack = true },
	},
	-- Verdulería: 4 cajones (2 adelante abajo, 2 atrás arriba); la fruta se apila
	produce_stand = {
		{ origin = V(-1.95, 1.25, -0.8), width = 3.5, depth = 1.4, height = 1.0, stack = true },
		{ origin = V(1.95, 1.25, -0.8), width = 3.5, depth = 1.4, height = 1.0, stack = true },
		{ origin = V(-1.95, 2.25, 0.85), width = 3.5, depth = 1.4, height = 1.0, stack = true },
		{ origin = V(1.95, 2.25, 0.85), width = 3.5, depth = 1.4, height = 1.0, stack = true },
	},
	-- Góndola de electrodomésticos: 3 niveles altos
	appliance_shelf = levels({ 0.5, 3.0, 5.5 }, 11.4, 2.5, 2.35),
}
-- Los electrodomésticos se exhiben de a pocos por nivel (no 24 televisores apilados)
for _, spec in SLOT_SPECS.appliance_shelf do
	spec.maxUnits = 10
end
local STORAGE_TOPS = { 0.5, 3.7 }

---------------------------------------------------------------------------
-- Helpers de construcción
---------------------------------------------------------------------------
local function add(fixture, props, localCF)
	props.CFrame = fixture.cframe * localCF
	props.Parent = props.Parent or fixture.model
	return StoreBuilder.part(props)
end

local function addCylinder(fixture, height, diameter, localCF, props)
	props.Shape = Enum.PartType.Cylinder
	props.Size = V(height, diameter, diameter)
	return add(fixture, props, localCF * CFrame.Angles(0, 0, math.rad(90)))
end

local BUILD = {}

-- Vidrio "falso": plástico transparente (el material Glass oculta lo transparente que queda detrás)
local GLASS = { Color = C(190, 215, 230), Material = Enum.Material.SmoothPlastic, Transparency = 0.78, Reflectance = 0.08, CanQuery = false, CastShadow = false }

local function glassProps(extra)
	local props = {}
	for k, v in GLASS do
		props[k] = v
	end
	for k, v in extra do
		props[k] = v
	end
	return props
end

BUILD.product_shelf = function(f)
	local frame, board, back, accent = C(64, 70, 82), C(212, 212, 214), C(188, 190, 194), C(58, 140, 90)
	add(f, { Name = "Base", Size = V(12, 0.5, 3), Color = frame }, CFrame.new(0, 0.25, 0))
	add(f, { Name = "Kick", Size = V(11.9, 0.32, 0.05), Color = C(48, 52, 60), CanQuery = false }, CFrame.new(0, 0.2, -1.52))
	add(f, { Name = "Back", Size = V(11.6, 6.6, 0.15), Color = back, Material = Enum.Material.DiamondPlate }, CFrame.new(0, 3.8, 1.38))
	add(f, { Name = "BackFrame", Size = V(12, 7, 0.1), Color = frame }, CFrame.new(0, 3.5, 1.46))
	for _, x in { -5.9, 5.9 } do
		add(f, { Name = "Side", Size = V(0.2, 7, 3), Color = frame }, CFrame.new(x, 3.5, 0))
		add(f, { Name = "SideAccent", Size = V(0.24, 6.6, 0.25), Color = accent, CanQuery = false }, CFrame.new(x, 3.6, -1.38))
	end
	for i = 2, 4 do
		local top = SLOT_SPECS.product_shelf[i].origin.Y
		add(f, { Name = "Board", Size = V(11.6, 0.1, 2.8), Color = board, Material = Enum.Material.Metal }, CFrame.new(0, top - 0.05, 0.05))
		add(f, { Name = "PriceRail", Size = V(11.6, 0.34, 0.06), Color = C(170, 172, 176), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, top - 0.16, -1.47))
	end
	add(f, { Name = "PriceRail", Size = V(11.6, 0.34, 0.06), Color = C(170, 172, 176), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, 0.34, -1.49))
	add(f, { Name = "Header", Size = V(12, 0.9, 0.3), Color = accent }, CFrame.new(0, 7.45, 1.25))
	add(f, { Name = "HeaderLine", Size = V(11.6, 0.08, 0.05), Color = C(225, 220, 205), CanQuery = false }, CFrame.new(0, 7.2, 1.08))
end

BUILD.fridge = function(f)
	local white, frame = C(208, 210, 214), C(150, 154, 160)
	add(f, { Name = "Bottom", Size = V(8, 0.7, 3), Color = C(55, 58, 66) }, CFrame.new(0, 0.35, 0))
	add(f, { Name = "Grille", Size = V(7.4, 0.35, 0.05), Color = C(35, 38, 44), Material = Enum.Material.DiamondPlate, CanQuery = false }, CFrame.new(0, 0.35, -1.52))
	add(f, { Name = "Back", Size = V(7.6, 7.2, 0.2), Color = C(225, 232, 238) }, CFrame.new(0, 4.1, 1.4))
	add(f, { Name = "SideL", Size = V(0.2, 8, 3), Color = white }, CFrame.new(-3.9, 4, 0))
	add(f, { Name = "SideR", Size = V(0.2, 8, 3), Color = white }, CFrame.new(3.9, 4, 0))
	add(f, { Name = "Top", Size = V(8.2, 0.9, 3.3), Color = white }, CFrame.new(0, 8.05, -0.1))
	add(f, { Name = "LightStrip", Size = V(7.4, 0.08, 0.12), Color = C(215, 230, 240), Material = Enum.Material.Neon, CanQuery = false, CastShadow = false }, CFrame.new(0, 7.55, -1.35))
	for i = 2, 4 do
		local top = SLOT_SPECS.fridge[i].origin.Y
		add(f, { Name = "Board", Size = V(7.6, 0.08, 2.6), Color = C(190, 196, 204), Material = Enum.Material.Metal }, CFrame.new(0, top - 0.04, 0))
	end
	-- Dos puertas de vidrio con marco y manija
	for _, x in { -1.9, 1.9 } do
		add(f, glassProps({ Name = "DoorGlass", Size = V(3.6, 6.8, 0.06) }), CFrame.new(x, 4.1, -1.47))
		add(f, { Name = "DoorFrameTop", Size = V(3.7, 0.15, 0.1), Color = frame, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x, 7.5, -1.49))
		add(f, { Name = "DoorFrameBottom", Size = V(3.7, 0.15, 0.1), Color = frame, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x, 0.72, -1.49))
		add(f, { Name = "DoorFrameSide", Size = V(0.12, 6.9, 0.1), Color = frame, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x - 1.8, 4.1, -1.49))
		add(f, { Name = "DoorFrameSide", Size = V(0.12, 6.9, 0.1), Color = frame, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x + 1.8, 4.1, -1.49))
		add(f, { Name = "Handle", Size = V(0.1, 2.2, 0.14), Color = C(175, 178, 184), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x + (x < 0 and 1.5 or -1.5), 4.2, -1.58))
	end
	local sign = add(f, { Name = "Sign", Size = V(7.6, 0.55, 0.05), Color = C(40, 90, 160) }, CFrame.new(0, 8.05, -1.77))
	surfaceText(sign, Enum.NormalId.Front, "LÁCTEOS Y FRESCOS", { color = C(235, 230, 220) })
	local light = Instance.new("PointLight")
	light.Color = C(210, 230, 245)
	light.Range = 9
	light.Brightness = 0.7
	light.Shadows = false
	light.Parent = add(f, { Name = "InnerLight", Size = V(0.2, 0.2, 0.2), Transparency = 1, CanCollide = false, CanQuery = false }, CFrame.new(0, 5, 0.5))
end

BUILD.freezer = function(f)
	local white = C(208, 210, 214)
	add(f, { Name = "Bottom", Size = V(8, 0.6, 4), Color = C(55, 58, 66) }, CFrame.new(0, 0.3, 0))
	add(f, { Name = "Front", Size = V(8, 3.2, 0.2), Color = white }, CFrame.new(0, 1.6, -1.9))
	add(f, { Name = "BackWall", Size = V(8, 3.2, 0.2), Color = white }, CFrame.new(0, 1.6, 1.9))
	add(f, { Name = "SideL", Size = V(0.2, 3.2, 4), Color = white }, CFrame.new(-3.9, 1.6, 0))
	add(f, { Name = "SideR", Size = V(0.2, 3.2, 4), Color = white }, CFrame.new(3.9, 1.6, 0))
	add(f, { Name = "Rim", Size = V(8.1, 0.12, 4.1), Color = C(150, 154, 160), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, 3.2, 0))
	add(f, { Name = "Divider", Size = V(0.1, 2.6, 3.6), Color = white }, CFrame.new(0, 1.9, 0))
	add(f, { Name = "Inside", Size = V(7.6, 0.05, 3.6), Color = C(170, 200, 222) }, CFrame.new(0, 0.62, 0))
	add(f, glassProps({ Name = "LidA", Size = V(3.9, 0.06, 3.8) }), CFrame.new(-1.95, 3.28, 0))
	add(f, glassProps({ Name = "LidB", Size = V(3.9, 0.06, 3.8) }), CFrame.new(1.95, 3.32, 0))
	add(f, { Name = "Grille", Size = V(7.4, 0.35, 0.05), Color = C(35, 38, 44), Material = Enum.Material.DiamondPlate, CanQuery = false }, CFrame.new(0, 0.35, -2.02))
	local stripe = add(f, { Name = "Stripe", Size = V(8.02, 0.55, 0.05), Color = C(40, 90, 160) }, CFrame.new(0, 2.85, -2.02))
	surfaceText(stripe, Enum.NormalId.Front, "CONGELADOS", { color = C(235, 230, 220) })
end

BUILD.storage_shelf = function(f)
	local blue, orange, wood = C(45, 78, 150), C(205, 115, 40), C(168, 130, 88)
	for _, x in { -4.9, 4.9 } do
		for _, z in { -1.35, 1.35 } do
			add(f, { Name = "Upright", Size = V(0.25, 7.2, 0.25), Color = blue, Material = Enum.Material.Metal }, CFrame.new(x, 3.6, z))
		end
		-- refuerzos en cruz a los costados
		for _, sign in { 1, -1 } do
			add(f, { Name = "Brace", Size = V(0.08, 3.4, 0.08), Color = blue, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x, 2.1, 0) * CFrame.Angles(math.rad(38 * sign), 0, 0))
			add(f, { Name = "Brace", Size = V(0.08, 3.4, 0.08), Color = blue, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x, 5.3, 0) * CFrame.Angles(math.rad(38 * sign), 0, 0))
		end
	end
	for _, top in { 0.5, 3.7, 6.9 } do
		add(f, { Name = "Board", Size = V(9.8, 0.1, 2.8), Color = wood, Material = Enum.Material.WoodPlanks }, CFrame.new(0, top - 0.05, 0))
		for _, z in { -1.4, 1.4 } do
			add(f, { Name = "Beam", Size = V(10, 0.3, 0.12), Color = orange, Material = Enum.Material.Metal }, CFrame.new(0, top - 0.2, z))
		end
	end
	for _, x in { -4.9, 4.9 } do
		for _, z in { -1.35, 1.35 } do
			add(f, { Name = "Foot", Size = V(0.5, 0.06, 0.5), Color = C(40, 42, 48), CanQuery = false }, CFrame.new(x, 0.03, z))
		end
	end
end

BUILD.produce_stand = function(f)
	local wood, woodDark, green = C(168, 124, 80), C(120, 86, 56), C(58, 120, 70)
	-- Patas y estructura
	for _, x in { -3.9, 3.9 } do
		for _, z in { -1.55, 1.55 } do
			add(f, { Name = "Leg", Size = V(0.25, z < 0 and 1.2 or 2.2, 0.25), Color = woodDark, Material = Enum.Material.Wood }, CFrame.new(x, z < 0 and 0.6 or 1.1, z))
		end
	end
	add(f, { Name = "Platform", Size = V(8, 0.2, 1.7), Color = woodDark, Material = Enum.Material.Wood }, CFrame.new(0, 1.05, -0.8))
	add(f, { Name = "PlatformHigh", Size = V(8, 0.2, 1.7), Color = woodDark, Material = Enum.Material.Wood }, CFrame.new(0, 2.05, 0.85))
	add(f, { Name = "Skirt", Size = V(8, 1, 0.1), Color = green, CanQuery = false }, CFrame.new(0, 0.5, -1.65))
	-- Cajones de madera abiertos
	for _, spec in SLOT_SPECS.produce_stand do
		local o = spec.origin
		add(f, { Name = "CrateBottom", Size = V(3.7, 0.08, 1.6), Color = wood, Material = Enum.Material.WoodPlanks, CanQuery = false }, CFrame.new(o.X, o.Y - 0.04, o.Z))
		for _, dz in { -0.8, 0.8 } do
			add(f, { Name = "CrateSide", Size = V(3.7, 0.45, 0.08), Color = wood, Material = Enum.Material.WoodPlanks, CanQuery = false }, CFrame.new(o.X, o.Y + 0.2, o.Z + dz))
		end
		for _, dx in { -1.85, 1.85 } do
			add(f, { Name = "CrateSide", Size = V(0.08, 0.45, 1.6), Color = wood, Material = Enum.Material.WoodPlanks, CanQuery = false }, CFrame.new(o.X + dx, o.Y + 0.2, o.Z))
		end
	end
	-- Toldo y cartel
	for _, x in { -3.9, 3.9 } do
		add(f, { Name = "AwningPole", Size = V(0.15, 2.2, 0.15), Color = woodDark, Material = Enum.Material.Wood }, CFrame.new(x, 3.3, 1.55))
	end
	local sign = add(f, { Name = "Sign", Size = V(8, 0.7, 0.12), Color = green }, CFrame.new(0, 4.1, 1.55))
	surfaceText(sign, Enum.NormalId.Front, "🍎 VERDULERÍA 🥕", { color = C(240, 235, 220) })
	for i = 0, 7 do
		add(f, { Name = "AwningStripe", Size = V(1, 0.08, 1.2), Color = i % 2 == 0 and C(200, 70, 60) or C(235, 228, 215), CanQuery = false, CastShadow = i == 0 }, CFrame.new(-3.5 + i, 4.45, 1.1) * CFrame.Angles(math.rad(-12), 0, 0))
	end
end

BUILD.appliance_shelf = function(f)
	local frame, board, accent = C(58, 62, 72), C(200, 202, 206), C(52, 100, 165)
	add(f, { Name = "Base", Size = V(12, 0.5, 3), Color = frame }, CFrame.new(0, 0.25, 0))
	add(f, { Name = "Back", Size = V(11.6, 7.4, 0.15), Color = C(180, 184, 190), Material = Enum.Material.DiamondPlate }, CFrame.new(0, 4.2, 1.38))
	for _, x in { -5.9, 5.9 } do
		add(f, { Name = "Side", Size = V(0.25, 8, 3), Color = frame }, CFrame.new(x, 4, 0))
		add(f, { Name = "SideAccent", Size = V(0.3, 7.6, 0.25), Color = accent, CanQuery = false }, CFrame.new(x, 4.1, -1.38))
	end
	for i = 2, 3 do
		local top = SLOT_SPECS.appliance_shelf[i].origin.Y
		add(f, { Name = "Board", Size = V(11.6, 0.14, 2.8), Color = board, Material = Enum.Material.Metal }, CFrame.new(0, top - 0.07, 0.05))
		add(f, { Name = "PriceRail", Size = V(11.6, 0.34, 0.06), Color = C(170, 172, 176), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, top - 0.16, -1.47))
	end
	add(f, { Name = "PriceRail", Size = V(11.6, 0.34, 0.06), Color = C(170, 172, 176), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, 0.34, -1.49))
	local header = add(f, { Name = "Header", Size = V(12, 1, 0.3), Color = accent }, CFrame.new(0, 8.3, 1.25))
	surfaceText(header, Enum.NormalId.Front, "ELECTRODOMÉSTICOS", { color = C(235, 230, 220) })
end

-- Mostrador de pedidos online "PedidosLla": el frente (-Z) da al repartidor
local APP_RED = C(214, 36, 74)
BUILD.delivery_counter = function(f)
	local body = add(f, { Name = "Counter", Size = V(5, 3.1, 1.8), Color = C(235, 232, 226) }, CFrame.new(0, 1.55, 0))
	add(f, { Name = "CounterTop", Size = V(5.2, 0.12, 2), Color = C(60, 62, 70), Material = Enum.Material.Metal }, CFrame.new(0, 3.16, 0))
	local front = add(f, { Name = "Brand", Size = V(4.6, 1.2, 0.06), Color = APP_RED, CanQuery = false }, CFrame.new(0, 1.9, -0.93))
	surfaceText(front, Enum.NormalId.Front, "🛵 " .. Config.DELIVERY_APP, { color = C(255, 255, 255), font = Enum.Font.GothamBlack })
	add(f, { Name = "Kick", Size = V(5.02, 0.35, 1.82), Color = C(50, 52, 58), CanQuery = false }, CFrame.new(0, 0.18, 0))
	-- Pantalla con el pedido (se lee de los dos lados)
	add(f, { Name = "ScreenPole", Size = V(0.15, 1.2, 0.15), Color = C(40, 40, 45), CanQuery = false }, CFrame.new(1.7, 3.8, 0.4))
	local screen = add(f, { Name = "OrderScreen", Size = V(2.4, 1.5, 0.12), Color = C(20, 22, 28) }, CFrame.new(1.7, 5, 0.4))
	f.orderLabels = {
		surfaceText(screen, Enum.NormalId.Front, "", { bg = C(30, 12, 20), color = C(255, 235, 240), rich = true, pps = 90 }),
		surfaceText(screen, Enum.NormalId.Back, "", { bg = C(30, 12, 20), color = C(255, 235, 240), rich = true, pps = 90 }),
	}
	-- Bolsas vacías apiladas y cartel de arriba
	for i = 0, 2 do
		add(f, { Name = "BagStack", Size = V(0.9, 0.08, 0.6), Color = C(190, 160, 120), CanQuery = false }, CFrame.new(-1.7, 3.26 + i * 0.08, 0.4))
	end
	local sign = add(f, { Name = "AppSign", Size = V(3.2, 0.8, 0.12), Color = APP_RED, Material = Enum.Material.Neon, CastShadow = false }, CFrame.new(-0.6, 6.4, 0.8))
	surfaceText(sign, Enum.NormalId.Front, "RETIRO DE PEDIDOS", { color = C(255, 255, 255) })
	add(f, { Name = "SignPole", Size = V(0.12, 3.2, 0.12), Color = C(40, 40, 45), CanQuery = false }, CFrame.new(-0.6, 4.8, 0.8))
	f.counterPart = body
	f.anchors = {
		bag = f.cframe * CFrame.new(0, 3.22, -0.2),
		rider = (f.cframe * CFrame.new(0, 0, -2.4)).Position,
		face = (f.cframe * CFrame.new(0, 0, 0)).Position,
	}
end

-- Maquinita retro (juegos inventados, estilo años 80). La pantalla la anima cada jugador en su compu.
local ARCADE_GAMES = {
	{ id = "comepuntos", title = "COME-PUNTOS", color = C(235, 200, 40), art = C(40, 60, 170) },
	{ id = "invasores", title = "INVASORES", color = C(90, 220, 110), art = C(30, 30, 36) },
	{ id = "bloques", title = "BLOQUES", color = C(230, 90, 160), art = C(120, 40, 140) },
}
BUILD.arcade = function(f)
	local gameInfo = ARCADE_GAMES[(tonumber(string.match(f.id, "%d+")) or 1) % #ARCADE_GAMES + 1]
	local black = C(24, 24, 28)
	local body = add(f, { Name = "Cabinet", Size = V(2.4, 5.2, 2.2), Color = gameInfo.art }, CFrame.new(0, 2.6, 0.1))
	body:SetAttribute("Kind", "info")
	body:SetAttribute("Hint", "🕹️ " .. gameInfo.title .. " · los clientes juegan y pagan " .. fmt(Config.ARCADE_PRICE) .. " por partida")
	for _, x in { -1.22, 1.22 } do
		add(f, { Name = "SideArt", Size = V(0.06, 4.6, 1.9), Color = gameInfo.color, CanQuery = false }, CFrame.new(x, 2.9, 0.1))
	end
	add(f, { Name = "Kick", Size = V(2.42, 0.6, 0.1), Color = black, CanQuery = false }, CFrame.new(0, 0.3, -1.02))
	-- panel de control con palanca y botones
	add(f, { Name = "Panel", Size = V(2.4, 0.3, 0.9), Color = black }, CFrame.new(0, 3.05, -1.25) * CFrame.Angles(math.rad(-15), 0, 0))
	add(f, { Name = "Stick", Size = V(0.1, 0.4, 0.1), Color = C(40, 40, 45), CanQuery = false }, CFrame.new(-0.55, 3.35, -1.3))
	add(f, { Name = "StickBall", Shape = Enum.PartType.Ball, Size = V(0.26, 0.26, 0.26), Color = C(200, 40, 40), CanQuery = false, CastShadow = false }, CFrame.new(-0.55, 3.58, -1.3))
	for i, color in { C(220, 60, 60), C(60, 140, 220) } do
		addCylinder(f, 0.08, 0.2, CFrame.new(0.25 + i * 0.35, 3.24, -1.3), { Name = "Button", Color = color, CanQuery = false, CastShadow = false })
	end
	-- pantalla (la animación la dibuja el cliente) y marquesina con el nombre del juego
	add(f, { Name = "Bezel", Size = V(2.2, 1.9, 0.1), Color = black, CanQuery = false }, CFrame.new(0, 4.35, -1.0) * CFrame.Angles(math.rad(-8), 0, 0))
	local screen = add(f, { Name = "Screen", Size = V(1.9, 1.55, 0.05), Color = C(5, 5, 10), CanQuery = false, CastShadow = false }, CFrame.new(0, 4.35, -1.07) * CFrame.Angles(math.rad(-8), 0, 0))
	screen:SetAttribute("Game", gameInfo.id)
	CollectionService:AddTag(screen, "ArcadeScreen")
	local marquee = add(f, { Name = "Marquee", Size = V(2.4, 0.7, 0.5), Color = gameInfo.color, Material = Enum.Material.Neon, CastShadow = false }, CFrame.new(0, 5.55, -0.8))
	surfaceText(marquee, Enum.NormalId.Front, gameInfo.title, { color = C(25, 25, 30), font = Enum.Font.Arcade })
	add(f, { Name = "Top", Size = V(2.4, 0.3, 2.4), Color = black }, CFrame.new(0, 6.05, 0))
	f.screen = screen
	f.anchors = {
		play = (f.cframe * CFrame.new(0, 0, -2.4)).Position,
		face = (f.cframe * CFrame.new(0, 0, 0)).Position,
	}
end

local function toggleTarget(f, part)
	part:SetAttribute("Kind", "checkouttoggle")
	part:SetAttribute("CheckoutId", f.id)
end

BUILD.checkout = function(f)
	local body, top, steel, dark = C(196, 198, 202), C(120, 124, 132), C(165, 168, 174), C(38, 40, 46)
	add(f, { Name = "Counter", Size = V(3, 3.1, 8), Color = body }, CFrame.new(0, 1.55, 0))
	add(f, { Name = "CounterTop", Size = V(3.1, 0.1, 8.1), Color = top, Material = Enum.Material.Metal }, CFrame.new(0, 3.15, 0))
	add(f, { Name = "Kick", Size = V(3.05, 0.4, 8.05), Color = C(55, 58, 66) }, CFrame.new(0, 0.2, 0))
	add(f, { Name = "Stripe", Size = V(3.12, 0.3, 8.12), Color = C(58, 140, 90), CanQuery = false }, CFrame.new(0, 2.6, 0))
	add(f, { Name = "Belt", Size = V(2.4, 0.08, 4.6), Color = C(28, 28, 32), Material = Enum.Material.Rubber }, CFrame.new(0, 3.24, 1.6))
	for _, z in { 3.9, -0.7 } do
		-- los cilindros de Roblox van a lo largo del eje X: justo a lo ancho de la cinta
		add(f, { Name = "Roller", Shape = Enum.PartType.Cylinder, Size = V(2.4, 0.22, 0.22), Color = steel, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, 3.22, z))
	end
	add(f, { Name = "Divider", Size = V(2.2, 0.14, 0.14), Color = C(200, 60, 50), CanQuery = false }, CFrame.new(0, 3.35, 3.85))
	add(f, { Name = "Scanner", Size = V(2.2, 0.06, 0.9), Color = C(25, 35, 45), Transparency = 0.1 }, CFrame.new(0, 3.23, -1.2))
	add(f, { Name = "Laser", Size = V(1.8, 0.02, 0.05), Color = C(230, 50, 50), Material = Enum.Material.Neon, CanQuery = false, CastShadow = false }, CFrame.new(0, 3.27, -1.2))
	add(f, { Name = "BagArea", Size = V(2.6, 0.06, 2.4), Color = steel, Material = Enum.Material.Metal }, CFrame.new(0, 3.23, -2.7))
	for _, x in { -1.45, 1.45 } do
		add(f, { Name = "Rail", Size = V(0.1, 0.3, 8), Color = steel, Material = Enum.Material.Metal }, CFrame.new(x, 3.35, 0))
	end
	-- Soporte de bolsas al final
	for _, x in { -0.9, 0.9 } do
		add(f, { Name = "BagPole", Size = V(0.08, 1.2, 0.08), Color = steel, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(x, 3.85, -3.8))
	end
	add(f, { Name = "BagBar", Size = V(1.9, 0.08, 0.08), Color = steel, Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(0, 4.45, -3.8))
	add(f, { Name = "Bags", Size = V(1.6, 0.9, 0.3), Color = C(225, 225, 220), Transparency = 0.3, CanQuery = false }, CFrame.new(0, 3.95, -3.85))
	-- Pantalla del cajero (+X) y del cliente (-X)
	add(f, { Name = "MonitorPole", Size = V(0.2, 1.4, 0.2), Color = dark }, CFrame.new(1.2, 3.9, -1.3))
	local screen = add(f, { Name = "Monitor", Size = V(0.14, 1.1, 1.5), Color = C(15, 15, 20) }, CFrame.new(1.3, 4.9, -1.3))
	f.monitorLabel = surfaceText(screen, Enum.NormalId.Right, "CAJA", { bg = C(15, 40, 70), color = C(225, 225, 220), pps = 80 })
	f.customerLabel = surfaceText(screen, Enum.NormalId.Left, "", { bg = C(10, 30, 20), color = C(140, 230, 160), pps = 80 })
	add(f, { Name = "CardTerminal", Size = V(0.5, 0.25, 0.7), Color = C(30, 30, 35) }, CFrame.new(-1.15, 3.35, -2.1))
	add(f, { Name = "CardScreen", Size = V(0.36, 0.02, 0.3), Color = C(120, 200, 140), Material = Enum.Material.Neon, CanQuery = false, CastShadow = false }, CFrame.new(-1.15, 3.48, -2.2))
	add(f, { Name = "Drawer", Size = V(1.2, 0.5, 1.2), Color = C(50, 50, 55) }, CFrame.new(0.9, 3.45, -3.2))
	add(f, { Name = "CashierMat", Size = V(2.5, 0.04, 3), Color = C(45, 50, 60), CanCollide = false, Material = Enum.Material.Fabric }, CFrame.new(3.3, 0.02, -1.4))
	-- Exhibidor de golosinas del lado de la fila
	add(f, { Name = "CandyRack", Size = V(0.5, 2.6, 1.6), Color = C(60, 64, 72), CanCollide = false }, CFrame.new(-1.8, 1.3, 3.2))
	for i, color in { C(210, 70, 70), C(230, 190, 60), C(80, 150, 210), C(120, 190, 90) } do
		add(f, { Name = "Candy", Size = V(0.18, 0.35, 1.4), Color = color, CanCollide = false, CanQuery = false, CastShadow = false }, CFrame.new(-2.1, 0.5 + i * 0.5, 3.2))
	end
	-- Poste con el número de caja: click para abrir / cerrar
	local pole = add(f, { Name = "LanePole", Size = V(0.2, 6, 0.2), Color = C(60, 60, 65) }, CFrame.new(-1.3, 3, 4.2))
	local lamp = add(f, { Name = "LaneLight", Size = V(1, 1, 1), Color = C(40, 180, 80), Material = Enum.Material.Neon }, CFrame.new(-1.3, 6.4, 4.2))
	toggleTarget(f, pole)
	toggleTarget(f, lamp)
	f.laneLight = lamp
	f.laneLabels = {
		surfaceText(lamp, Enum.NormalId.Front, "1", { color = C(235, 230, 220) }),
		surfaceText(lamp, Enum.NormalId.Back, "1", { color = C(235, 230, 220) }),
	}

	f.anchors = {
		cashier = (f.cframe * CFrame.new(3.3, 0, -1.4)).Position,
		counter = (f.cframe * CFrame.new(0, 0, -1.4)).Position,
		exit = (f.cframe * CFrame.new(-3.5, 0, -7)).Position,
		bag = f.cframe * CFrame.new(0, 3.27, -2.7),
		card = f.cframe * CFrame.new(-0.6, 3.27, -1.9),
		cash = f.cframe * CFrame.new(-0.6, 3.27, -2.6),
		bell = f.cframe * CFrame.new(-1.3, 7.4, 4.2),
		belt = function(k)
			return f.cframe * CFrame.new(0, 3.28, 3.6 - (k - 1) * 0.85)
		end,
		queue = function(i)
			return (f.cframe * CFrame.new(-3.2, 0, -1.4 + (i - 1) * 2.8)).Position
		end,
	}
end

BUILD.self_checkout = function(f)
	local body, dark = C(196, 198, 202), C(55, 58, 66)
	add(f, { Name = "Body", Size = V(2.4, 3.2, 1.8), Color = body }, CFrame.new(0, 1.6, 0.4))
	add(f, { Name = "Kick", Size = V(2.45, 0.35, 1.85), Color = dark }, CFrame.new(0, 0.18, 0.4))
	add(f, { Name = "Tower", Size = V(0.6, 1.8, 0.6), Color = dark }, CFrame.new(0, 4.1, 0.9))
	local screen = add(f, { Name = "Screen", Size = V(1.8, 1.3, 0.1), Color = C(15, 15, 20) }, CFrame.new(0, 4.2, 0.55) * CFrame.Angles(math.rad(-15), 0, 0))
	f.monitorLabel = surfaceText(screen, Enum.NormalId.Front, "AUTOCAJA", { bg = C(15, 40, 70), color = C(225, 225, 220), pps = 80 })
	add(f, { Name = "Scanner", Size = V(2.4, 0.1, 1.2), Color = C(25, 35, 45), Transparency = 0.1 }, CFrame.new(0, 3.25, -0.9))
	add(f, { Name = "Laser", Size = V(1.8, 0.02, 0.05), Color = C(230, 50, 50), Material = Enum.Material.Neon, CanQuery = false, CastShadow = false }, CFrame.new(0, 3.31, -0.9))
	add(f, { Name = "BagScale", Size = V(1.1, 0.12, 1.1), Color = C(165, 168, 174), Material = Enum.Material.Metal }, CFrame.new(1.8, 2.4, -0.2))
	add(f, { Name = "BagStand", Size = V(0.12, 2.4, 0.12), Color = C(165, 168, 174), Material = Enum.Material.Metal, CanQuery = false }, CFrame.new(1.8, 1.2, -0.2))
	add(f, { Name = "CardReader", Size = V(0.4, 0.5, 0.2), Color = C(30, 30, 35) }, CFrame.new(-0.9, 3.6, 0.1))
	local lamp = add(f, { Name = "LaneLight", Size = V(0.6, 0.6, 0.6), Color = C(40, 180, 80), Material = Enum.Material.Neon }, CFrame.new(0, 5.4, 0.9))
	toggleTarget(f, lamp)
	f.laneLight = lamp
	f.laneLabels = {}
	f.anchors = {
		cashier = nil,
		counter = (f.cframe * CFrame.new(0, 0, 0)).Position,
		exit = (f.cframe * CFrame.new(0, 0, -6)).Position,
		bag = f.cframe * CFrame.new(1.8, 2.5, -0.2),
		card = f.cframe * CFrame.new(-0.6, 3.32, -0.9),
		cash = f.cframe * CFrame.new(-0.6, 3.32, -0.9),
		bell = f.cframe * CFrame.new(0, 6.2, 0.9),
		belt = function(k)
			return f.cframe * CFrame.new(-0.9 + ((k - 1) % 4) * 0.6, 3.32, -0.9)
		end,
		queue = function(i)
			return (f.cframe * CFrame.new(0, 0, -2.4 - (i - 1) * 2.8)).Position
		end,
	}
end

BUILD.plant = function(f)
	addCylinder(f, 1.4, 1.8, CFrame.new(0, 0.7, 0), { Name = "Pot", Color = C(185, 95, 60) })
	add(f, { Name = "Soil", Shape = Enum.PartType.Cylinder, Size = V(0.1, 1.6, 1.6), Color = C(80, 55, 35) }, CFrame.new(0, 1.42, 0) * CFrame.Angles(0, 0, math.rad(90)))
	add(f, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = V(2.6, 2.6, 2.6), Color = C(70, 150, 70), Material = Enum.Material.Grass }, CFrame.new(0, 2.8, 0))
	add(f, { Name = "Leaves2", Shape = Enum.PartType.Ball, Size = V(1.8, 1.8, 1.8), Color = C(85, 165, 80), Material = Enum.Material.Grass }, CFrame.new(0.3, 3.7, 0.2))
end

BUILD.flowers = function(f)
	add(f, { Name = "Planter", Size = V(6, 1, 2), Color = C(150, 105, 70), Material = Enum.Material.Wood }, CFrame.new(0, 0.5, 0))
	add(f, { Name = "Soil", Size = V(5.8, 0.1, 1.8), Color = C(80, 55, 35) }, CFrame.new(0, 1.02, 0))
	local colors = { C(230, 60, 80), C(250, 210, 60), C(240, 240, 250), C(180, 90, 220), C(255, 140, 60) }
	for i = 1, 8 do
		add(f, { Name = "Flower", Shape = Enum.PartType.Ball, Size = V(0.6, 0.6, 0.6), Color = colors[(i % #colors) + 1] }, CFrame.new(-2.6 + (i - 1) * 0.75, 1.4, (i % 2 == 0) and 0.4 or -0.4))
	end
end

BUILD.bench = function(f)
	add(f, { Name = "Seat", Size = V(5, 0.3, 1.6), Color = C(150, 105, 70), Material = Enum.Material.Wood }, CFrame.new(0, 1.6, 0))
	add(f, { Name = "Backrest", Size = V(5, 1, 0.2), Color = C(150, 105, 70), Material = Enum.Material.Wood }, CFrame.new(0, 2.4, 0.75))
	for _, x in { -2.2, 2.2 } do
		add(f, { Name = "Leg", Size = V(0.2, 1.5, 1.4), Color = C(50, 50, 55), Material = Enum.Material.Metal }, CFrame.new(x, 0.75, 0))
	end
end

BUILD.bin = function(f)
	addCylinder(f, 2.4, 1.5, CFrame.new(0, 1.2, 0), { Name = "Bin", Color = C(90, 95, 100), Material = Enum.Material.Metal })
	addCylinder(f, 0.2, 1.6, CFrame.new(0, 2.5, 0), { Name = "Lid", Color = C(60, 62, 66) })
end

BUILD.lamp = function(f)
	add(f, { Name = "Base", Size = V(1, 0.3, 1), Color = C(50, 50, 55) }, CFrame.new(0, 0.15, 0))
	add(f, { Name = "Pole", Size = V(0.35, 8.5, 0.35), Color = C(50, 50, 55) }, CFrame.new(0, 4.4, 0))
	local head = add(f, { Name = "Head", Size = V(1.2, 0.5, 1.2), Color = C(215, 200, 170), Material = Enum.Material.Neon }, CFrame.new(0, 8.8, 0))
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.6
	light.Color = C(255, 230, 180)
	light.Parent = head
end

BUILD.offer_sign = function(f)
	add(f, { Name = "Pole", Size = V(0.2, 2.2, 0.2), Color = C(60, 60, 65) }, CFrame.new(0, 1.1, 0))
	add(f, { Name = "Foot", Size = V(1.4, 0.15, 0.8), Color = C(60, 60, 65) }, CFrame.new(0, 0.08, 0))
	local board = add(f, { Name = "Board", Size = V(3, 1.8, 0.2), Color = C(250, 220, 40) }, CFrame.new(0, 3, 0))
	surfaceText(board, Enum.NormalId.Front, "¡OFERTAS!", { color = C(200, 30, 30) })
	surfaceText(board, Enum.NormalId.Back, "¡OFERTAS!", { color = C(200, 30, 30) })
end

---------------------------------------------------------------------------
-- Productos dentro de los niveles
---------------------------------------------------------------------------
local function slotLayout(spec, prod)
	local s = prod.size
	local cols = math.max(1, math.floor(spec.width / (s.X + 0.06)))
	local rows = math.max(1, math.floor(spec.depth / (s.Z + 0.06)))
	local layers = spec.stack and math.max(1, math.floor(spec.height / (s.Y + 0.02))) or 1
	return cols, rows, layers
end

local function unitCFrame(fixture, slot, prod, n)
	local spec = slot.spec
	local cols, rows = slotLayout(spec, prod)
	local perLayer = cols * rows
	local layer = math.floor((n - 1) / perLayer)
	local k = (n - 1) % perLayer
	local col = k % cols
	local row = math.floor(k / cols)
	local x = spec.origin.X - spec.width / 2 + (col + 0.5) * (spec.width / cols)
	local z = spec.origin.Z - spec.depth / 2 + (row + 0.5) * (spec.depth / rows)
	local y = spec.origin.Y + layer * (prod.size.Y + 0.02)
	return fixture.cframe * CFrame.new(x, y, z)
end

function Fixtures.capacity(fixture, index, productId)
	local slot = fixture.slots[index]
	local prod = Config.ProductsById[productId]
	if not slot or not prod then
		return 0
	end
	local cols, rows, layers = slotLayout(slot.spec, prod)
	return math.min(cols * rows * layers, Config.MAX_UNITS_PER_SLOT, slot.spec.maxUnits or math.huge)
end

function Fixtures.accepts(fixture, productId)
	local prod = Config.ProductsById[productId]
	return prod ~= nil and fixture.def.storage == prod.storage
end

local function updateSlotLabel(fixture, index)
	local slot = fixture.slots[index]
	if not slot or not slot.label then
		return
	end
	local prod = slot.productId and Config.ProductsById[slot.productId]
	slot.hit:SetAttribute("ProductId", slot.productId or "")
	slot.hit:SetAttribute("Stock", slot.stock)
	if prod then
		slot.label.Text = prod.name .. "  " .. fmt(State.getPrice(prod.id))
		slot.tag.Color = slot.stock > 0 and C(232, 204, 86) or C(222, 146, 136)
	else
		slot.label.Text = ""
		slot.tag.Color = C(218, 218, 215)
	end
end

local function updateStorageLabel(fixture, index)
	local s = fixture.storage[index]
	if not s then
		return
	end
	local box = s.box
	if box and box.Parent then
		local prod = Config.ProductsById[box:GetAttribute("ProductId") or ""]
		s.label.Text = prod and (prod.name .. " x" .. (box:GetAttribute("Units") or 0)) or "Caja vacía"
	else
		s.label.Text = ""
	end
end
Fixtures.updateStorageLabel = updateStorageLabel

function Fixtures.canPlace(fixture, index, productId)
	local slot = fixture.slots[index]
	if not slot then
		return false, "noslot"
	end
	if not Fixtures.accepts(fixture, productId) then
		return false, "wrongtype"
	end
	if slot.productId and slot.productId ~= productId and slot.stock > 0 then
		return false, "occupied"
	end
	if slot.productId == productId and slot.stock >= Fixtures.capacity(fixture, index, productId) then
		return false, "full"
	end
	return true
end

function Fixtures.addUnit(fixture, index, productId)
	local ok, reason = Fixtures.canPlace(fixture, index, productId)
	if not ok then
		return false, reason
	end
	local slot = fixture.slots[index]
	local prod = Config.ProductsById[productId]
	if slot.productId ~= productId then
		slot.productId = productId
	end
	slot.stock += 1
	local unit = Products.build(prod, unitCFrame(fixture, slot, prod, slot.stock))
	unit.Parent = fixture.unitsFolder
	slot.units[slot.stock] = unit
	updateSlotLabel(fixture, index)
	return true
end

-- Saca la última unidad. clearLabel: si queda vacío, el nivel pierde la etiqueta del producto.
function Fixtures.removeUnit(fixture, index, clearLabel)
	local slot = fixture.slots[index]
	if not slot or slot.stock <= 0 then
		return nil
	end
	local unit = slot.units[slot.stock]
	if unit then
		unit:Destroy()
	end
	slot.units[slot.stock] = nil
	slot.stock -= 1
	local productId = slot.productId
	if slot.stock == 0 and clearLabel then
		slot.productId = nil
	end
	updateSlotLabel(fixture, index)
	return productId
end

-- Carga directa (al restaurar la partida)
function Fixtures.fillSlot(fixture, index, productId, amount)
	local slot = fixture.slots[index]
	if not slot or not Fixtures.accepts(fixture, productId) then
		return
	end
	slot.productId = productId
	local cap = Fixtures.capacity(fixture, index, productId)
	for _ = 1, math.min(amount, cap) do
		slot.stock += 1
		local unit = Products.build(Config.ProductsById[productId], unitCFrame(fixture, slot, Config.ProductsById[productId], slot.stock))
		unit.Parent = fixture.unitsFolder
		slot.units[slot.stock] = unit
	end
	updateSlotLabel(fixture, index)
end

-- Devuelve un producto a cualquier nivel que lo tenga (cliente que se fue sin pagar, etc.)
function Fixtures.returnProduct(productId)
	for _, f in Fixtures.list do
		for i, slot in f.slots do
			if slot.productId == productId and Fixtures.canPlace(f, i, productId) then
				Fixtures.addUnit(f, i, productId)
				return true
			end
		end
	end
	return false
end

function Fixtures.findSlotsWithProduct(productId)
	local result = {}
	for _, f in Fixtures.list do
		for i, slot in f.slots do
			if slot.productId == productId then
				table.insert(result, { fixture = f, index = i, stock = slot.stock })
			end
		end
	end
	return result
end

function Fixtures.allProductSlots()
	local result = {}
	for _, f in Fixtures.list do
		for i, slot in f.slots do
			table.insert(result, { fixture = f, index = i, slot = slot })
		end
	end
	return result
end

-- Punto donde se para un cliente/empleado frente a un nivel o estante
function Fixtures.standPoint(fixture, index, isStorage)
	local x = 0
	if isStorage then
		local s = fixture.storage[index]
		x = s and s.x or 0
	else
		local slot = fixture.slots[index]
		if slot then
			x = slot.spec.origin.X + (math.random() - 0.5) * slot.spec.width * 0.5
		end
	end
	local d = fixture.def.size.Z / 2 + 1.8
	return (fixture.cframe * CFrame.new(x, 0, -d)).Position, (fixture.cframe * CFrame.new(x, 0, 0)).Position
end

---------------------------------------------------------------------------
-- Estantes de depósito
---------------------------------------------------------------------------
function Fixtures.setStorageBox(fixture, index, box)
	local s = fixture.storage[index]
	s.box = box
	if box then
		box:SetAttribute("StorageFixture", fixture.id)
		box:SetAttribute("StorageSlot", index)
		box.CFrame = s.cf
	end
	updateStorageLabel(fixture, index)
end

function Fixtures.clearStorageBox(box)
	local fixture = Fixtures.list[box:GetAttribute("StorageFixture") or ""]
	local index = box:GetAttribute("StorageSlot")
	box:SetAttribute("StorageFixture", nil)
	box:SetAttribute("StorageSlot", nil)
	if fixture and index and fixture.storage[index] and fixture.storage[index].box == box then
		fixture.storage[index].box = nil
		updateStorageLabel(fixture, index)
	end
end

function Fixtures.freeStorageSlot(nearPosition)
	local best, bestIndex, bestDist
	for _, f in Fixtures.list do
		for i, s in f.storage do
			if not (s.box and s.box.Parent) then
				local d = nearPosition and (s.cf.Position - nearPosition).Magnitude or 0
				if not best or d < bestDist then
					best, bestIndex, bestDist = f, i, d
				end
			end
		end
	end
	return best, bestIndex
end

function Fixtures.storedBoxes()
	local result = {}
	for _, f in Fixtures.list do
		for i, s in f.storage do
			if s.box and s.box.Parent then
				table.insert(result, { fixture = f, index = i, box = s.box })
			end
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Crear / quitar / mover
---------------------------------------------------------------------------
local function createProductSlots(f)
	for i, spec in SLOT_SPECS[f.type] do
		local slot = { index = i, spec = spec, productId = nil, stock = 0, units = {} }
		local hit = add(f, {
			Name = "Slot" .. i,
			Size = V(spec.width, spec.height, spec.depth + 0.5),
			Transparency = 1,
			CanCollide = false,
			CanTouch = false,
			CastShadow = false,
		}, CFrame.new(spec.origin.X, spec.origin.Y + spec.height / 2, spec.origin.Z - 0.25))
		hit:SetAttribute("Kind", "slot")
		hit:SetAttribute("FixtureId", f.id)
		hit:SetAttribute("Slot", i)
		slot.hit = hit

		local tagCF, tagSize
		if f.type == "freezer" then
			tagCF, tagSize = CFrame.new(spec.origin.X, 2.3, -2.03), V(2.6, 0.45, 0.04)
		elseif f.type == "produce_stand" then
			-- cartelito de precio en el frente de cada cajón
			tagCF, tagSize = CFrame.new(spec.origin.X, spec.origin.Y + 0.2, spec.origin.Z - 0.86), V(2.2, 0.36, 0.04)
		else
			tagCF, tagSize = CFrame.new(0, spec.origin.Y - 0.16, -1.54), V(2.6, 0.3, 0.04)
		end
		local tag = add(f, { Name = "PriceTag" .. i, Size = tagSize, Color = C(218, 218, 215), CanCollide = false, CanQuery = false }, tagCF)
		slot.tag = tag
		slot.label = surfaceText(tag, Enum.NormalId.Front, "", { color = C(20, 20, 20), pps = 70 })
		f.slots[i] = slot
		updateSlotLabel(f, i)
	end
end

local function createStorageSlots(f)
	for level, top in STORAGE_TOPS do
		for j = 1, 5 do
			local x = -4 + (j - 1) * 2
			local index = (level - 1) * 5 + j
			local hit = add(f, {
				Name = "StorageSlot" .. index,
				Size = V(1.95, 2.9, 3.2),
				Transparency = 1,
				CanCollide = false,
				CanTouch = false,
				CastShadow = false,
			}, CFrame.new(x, top + 1.45, -0.2))
			hit:SetAttribute("Kind", "storageslot")
			hit:SetAttribute("FixtureId", f.id)
			hit:SetAttribute("Slot", index)
			local tag = add(f, { Name = "Tag" .. index, Size = V(1.8, 0.3, 0.04), Color = C(218, 218, 215), CanCollide = false, CanQuery = false }, CFrame.new(x, top - 0.2, -1.5))
			f.storage[index] = {
				index = index,
				x = x,
				cf = f.cframe * CFrame.new(x, top + Config.BOX_SIZE.Y / 2 + 0.02, 0),
				hit = hit,
				label = surfaceText(tag, Enum.NormalId.Front, "", { color = C(20, 20, 20), pps = 70 }),
				box = nil,
			}
		end
	end
end

function Fixtures.create(fixtureType, x, z, rot, id, level)
	local def = Config.Fixtures[fixtureType]
	if id then
		nextId = math.max(nextId, tonumber(string.match(id, "%d+")) or 0)
	else
		nextId += 1
		id = "F" .. nextId
	end
	level = math.clamp(math.floor(tonumber(level) or 0), 0, Config.MAX_LEVEL)
	local fixture = { id = id, type = fixtureType, def = def, x = x, z = z, rot = rot, level = level, slots = {}, storage = {} }
	fixture.cframe = CFrame.new(x, Config.levelY(level), z) * CFrame.Angles(0, rot * math.pi / 2, 0)
	fixture.footprint = Config.footprint(fixtureType, x, z, rot)

	local model = Instance.new("Model")
	model.Name = def.name
	fixture.model = model
	local units = Instance.new("Folder")
	units.Name = "Units"
	units.Parent = model
	fixture.unitsFolder = units

	BUILD[fixtureType](fixture)
	if SLOT_SPECS[fixtureType] then
		createProductSlots(fixture)
	end
	if fixtureType == "storage_shelf" then
		createStorageSlots(fixture)
	end

	model:SetAttribute("FixtureId", id)
	model:SetAttribute("FixtureType", fixtureType)
	model:SetAttribute("FRot", rot)
	model:SetAttribute("FLevel", level)
	model:SetAttribute("FMinX", fixture.footprint.minX)
	model:SetAttribute("FMaxX", fixture.footprint.maxX)
	model:SetAttribute("FMinZ", fixture.footprint.minZ)
	model:SetAttribute("FMaxZ", fixture.footprint.maxZ)
	model.Parent = StoreBuilder.fixturesFolder
	Fixtures.list[id] = fixture

	for _, fn in createdListeners do
		fn(fixture)
	end
	return fixture
end

function Fixtures.hasContents(fixture)
	for _, slot in fixture.slots do
		if slot.stock > 0 then
			return true
		end
	end
	for _, s in fixture.storage do
		if s.box and s.box.Parent then
			return true
		end
	end
	return false
end

local function runGuards(fixture)
	for _, guard in Fixtures.removeGuards do
		local ok, reason = guard(fixture)
		if not ok then
			return false, reason
		end
	end
	return true
end

function Fixtures.remove(fixture)
	for _, fn in removedListeners do
		fn(fixture)
	end
	fixture.model:Destroy()
	Fixtures.list[fixture.id] = nil
end

function Fixtures.relocate(fixture, x, z, rot, level)
	local contents = {}
	for i, slot in fixture.slots do
		contents[i] = { slot.productId, slot.stock }
	end
	local boxes = {}
	for i, s in fixture.storage do
		boxes[i] = s.box
	end
	Fixtures.remove(fixture)
	local moved = Fixtures.create(fixture.type, x, z, rot, fixture.id, level or fixture.level)
	for i, c in contents do
		if c[1] then
			Fixtures.fillSlot(moved, i, c[1], c[2])
		end
	end
	for i, box in boxes do
		if box and box.Parent and moved.storage[i] then
			Fixtures.setStorageBox(moved, i, box)
		end
	end
	return moved
end

-- level: solo los muebles de ese piso (nil = todos)
function Fixtures.footprints(ignoreId, level)
	local list = {}
	for id, f in Fixtures.list do
		if id ~= ignoreId and (level == nil or (f.level or 0) == level) then
			table.insert(list, f.footprint)
		end
	end
	return list
end

function Fixtures.byType(fixtureType)
	local list = {}
	for _, f in Fixtures.list do
		if f.type == fixtureType then
			table.insert(list, f)
		end
	end
	return list
end

function Fixtures.countNonDecor()
	local n = 0
	for _, f in Fixtures.list do
		if not f.def.decor then
			n += 1
		end
	end
	return n
end

function Fixtures.stockCounts()
	local shelf, storage = {}, {}
	for _, f in Fixtures.list do
		for _, slot in f.slots do
			if slot.productId and slot.stock > 0 then
				shelf[slot.productId] = (shelf[slot.productId] or 0) + slot.stock
			end
		end
		for _, s in f.storage do
			local box = s.box
			if box and box.Parent then
				local pid = box:GetAttribute("ProductId") or ""
				if pid ~= "" then
					storage[pid] = (storage[pid] or 0) + (box:GetAttribute("Units") or 0)
				end
			end
		end
	end
	return shelf, storage
end

function Fixtures.refreshLabels()
	for _, f in Fixtures.list do
		for i in f.slots do
			updateSlotLabel(f, i)
		end
		for i in f.storage do
			updateStorageLabel(f, i)
		end
	end
end

---------------------------------------------------------------------------
-- Remotes (construir con TAB)
---------------------------------------------------------------------------
local function snap(v)
	return math.floor(v * 2 + 0.5) / 2
end

function Fixtures.init()
	-- Ya no se construye al instante: los muebles se compran (llegan en caja) y se arman desde la caja
	Remotes.PlaceFixture.OnServerInvoke = function()
		return false, "Comprá el mueble en el menú de construcción: llega en una caja con la camioneta."
	end

	Remotes.MoveFixture.OnServerInvoke = function(player, id, x, z, rot)
		local fixture = type(id) == "string" and Fixtures.list[id]
		if not fixture or type(x) ~= "number" or type(z) ~= "number" or type(rot) ~= "number" then
			return false, "Datos inválidos."
		end
		local okGuard, guardReason = runGuards(fixture)
		if not okGuard then
			return false, guardReason
		end
		x, z, rot = snap(x), snap(z), math.floor(rot) % 4
		-- Se mueve al piso donde está parado el jugador
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local level = root and Config.levelAt(root.Position.Y) or fixture.level
		local ok, reason = Config.validatePlacement(fixture.type, x, z, rot, State.data.expansions, Fixtures.footprints(id, level), level)
		if not ok then
			return false, reason
		end
		Fixtures.relocate(fixture, x, z, rot, level)
		return true, "Mueble movido."
	end

	Remotes.SellFixture.OnServerInvoke = function(_player, id)
		local fixture = type(id) == "string" and Fixtures.list[id]
		if not fixture then
			return false, "Ese mueble no existe."
		end
		if Fixtures.hasContents(fixture) then
			return false, "Vaciá el mueble antes de venderlo."
		end
		local okGuard, guardReason = runGuards(fixture)
		if not okGuard then
			return false, guardReason
		end
		local refund = math.floor(fixture.def.cost * Config.FIXTURE_REFUND)
		Fixtures.remove(fixture)
		State.data.money += refund
		State.publish()
		return true, "Vendiste " .. fixture.def.name .. " (+" .. fmt(refund) .. ")"
	end
end

return Fixtures
