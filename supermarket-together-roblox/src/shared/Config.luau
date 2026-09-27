-- Configuración compartida entre servidor y cliente.
-- IMPORTANTE: todo el dinero se maneja en CENTAVOS (enteros). 150 = $1.50

local Config = {}

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
Config.FIRST_PERSON = true -- cámara en primera persona como el juego original
Config.FLOOR_Y = 0.2
-- STARTING_MONEY se calcula más abajo: alcanza justo para 1 estantería, 1 caja registradora
-- y 1 caja de cada producto básico (más el envío). Hay que ganarse el resto.
Config.START_MARGIN = 1500 -- $15 de colchón
Config.START_SATISFACTION = 70
Config.INTERACT_DISTANCE = 12

-- Controles
Config.CURSOR_KEY = Enum.KeyCode.LeftAlt -- muestra / oculta la flecha del mouse
Config.CURSOR_KEY_ALT = Enum.KeyCode.RightAlt
Config.CURSOR_KEY_EXTRA = Enum.KeyCode.C -- alternativa (en Studio, Alt lo usa el propio Studio)

---------------------------------------------------------------------------
-- Horario (08:00 a 22:30 como el original)
---------------------------------------------------------------------------
Config.OPEN_HOUR = 8
Config.LAST_ENTRY_HOUR = 22.5 -- a las 22:30 dejan de entrar clientes
Config.PREP_HOUR = 7.5 -- hora que se ve antes de abrir
Config.SECONDS_PER_GAME_HOUR = 36 -- ~9 minutos reales por día
Config.WEEKDAYS = { "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo" }
Config.INFLATION_WEEKDAY = 4 -- los jueves suben los precios de mercado
Config.INFLATION_MIN = 1 -- %
Config.INFLATION_MAX = 5 -- %

---------------------------------------------------------------------------
-- Clientes
---------------------------------------------------------------------------
Config.CUSTOMER_BASE_INTERVAL = 16
Config.CUSTOMER_MIN_INTERVAL = 2.5
Config.MAX_CUSTOMERS_BASE = 6
Config.MAX_CUSTOMERS_PER_LEVEL = 2
Config.MAX_CUSTOMERS_CAP = 40
Config.PRICE_LIMIT_RATIO = 2 -- con precio >= 2x el de mercado se quejan y no compran
Config.PRICE_COMFORT_RATIO = 1.3 -- hasta 1.3x compran siempre; más caro, cada vez menos gente compra
Config.CAR_CUSTOMER_CHANCE = 0.35 -- parte de los clientes llega en auto
Config.MAX_TRAFFIC_CARS = 3 -- autos de paso por la calle (ambiente)

-- Demanda según la hora (más gente al mediodía y a la tarde-noche) y el día (más gente el fin de semana)
function Config.demandMultiplier(hour, weekday)
	local m = 0.7
	if hour >= 11.5 and hour < 14.5 then
		m = 1.35
	elseif hour >= 17.5 and hour < 20.5 then
		m = 1.5
	elseif hour >= 9 and hour < 11.5 or hour >= 14.5 and hour < 17.5 then
		m = 1
	end
	if weekday == 6 or weekday == 7 then
		m *= 1.3
	end
	return m
end
Config.PATIENCE = 100 -- segundos que aguantan esperando en la caja
Config.QUEUE_MAX = 8 -- clientes por caja; si todas están llenas, se roban la mercadería
Config.CARD_CHANCE = 0.5
Config.THIEF_START_DAY = 7 -- los ladrones aparecen a partir del día 7
Config.THIEF_BASE_CHANCE = 0.04
Config.THIEF_CHANCE_PER_DAY = 0.01
Config.THIEF_MAX_CHANCE = 0.2
Config.ESCAPE_Z = 78 -- si un ladrón llega al borde del estacionamiento, se pierde la mercadería
Config.ARCADE_PRICE = 200 -- $2 por partida en la maquinita
Config.ARCADE_CHANCE = 0.25 -- parte de los clientes que juega una partida (si hay maquinita libre)
Config.BENCH_CHANCE = 0.25 -- parte de los clientes que se sienta un rato en un banco antes de irse
Config.ATM_CHANCE = 0.18 -- parte de los clientes que saca plata del cajero antes de comprar
Config.ATM_HOST_FEE = 30 -- comisión que cobra el súper por cada extracción de un cliente ($0.30)
Config.BANK_INTEREST = 0.005 -- interés diario de Tesoro Digital (0.5%)

-- Delivery "PedidosLla" (pedidos online que retira una moto)
Config.DELIVERY_APP = "PedidosLla"
Config.DELIVERY_COMMISSION = 0.15 -- la app se queda con el 15%
Config.DELIVERY_TIME = 150 -- segundos para preparar cada pedido
Config.DELIVERY_EVERY_MIN = 60 -- cada cuánto llega un pedido nuevo (segundos reales)
Config.DELIVERY_EVERY_MAX = 130
Config.DELIVERY_TIP_CHANCE = 0.35 -- a veces dejan propina si lo preparás rápido

---------------------------------------------------------------------------
-- Cajas y reciclaje
---------------------------------------------------------------------------
Config.BOX_SIZE = Vector3.new(1.8, 1.3, 1.8)
Config.CRATE_SIZE = Vector3.new(2.6, 2, 2.6) -- caja de madera con un mueble adentro
Config.DELIVERY_FEE = 800 -- $8 de envío por cada pedido de mercadería
Config.VAN_NAME = "MercadoPibre" -- la camioneta de reparto
Config.DELIVERY_DELAY = 6
Config.MAX_BOXES = 150
Config.MAX_BOXES_PER_ORDER = 20
Config.RECYCLE_VALUE = 150 -- $1.50 por caja reciclada
Config.RECYCLE_VALUE_PERK = 250
Config.MAX_UNITS_PER_SLOT = 30

---------------------------------------------------------------------------
-- Nivel, experiencia y gastos diarios
---------------------------------------------------------------------------
function Config.xpForLevel(level)
	return 100 + (level - 1) * 60
end

Config.RENT_BASE = 4000 -- $40 de alquiler por día (local chico)
Config.RENT_PER_EXPANSION = 3500
Config.ELECTRICITY_PER_FIXTURE = 250
Config.EMPLOYEE_WAGE = 6000 -- $60 por empleado por día
Config.EMPLOYEE_SCAN_TIME = 0.9

Config.CASH_DENOMINATIONS = { 10000, 5000, 2000, 1000, 500, 100, 50, 25, 10, 5, 1 }

Config.EMPLOYEE_NAMES = {
	"Lucía", "Martín", "Sofía", "Mateo", "Valentina", "Joaquín", "Camila", "Tomás", "Julieta", "Benjamín",
	"Florencia", "Santiago", "Agustina", "Facundo", "Micaela", "Nicolás", "Brenda", "Lautaro", "Rocío", "Franco",
}

Config.ROLES = {
	{ id = "cashier", name = "Cajero" },
	{ id = "restock", name = "Repositor" },
	{ id = "storage", name = "Depósito" },
	{ id = "security", name = "Seguridad", requires = "security" },
}

---------------------------------------------------------------------------
-- Categorías de productos (se desbloquean en la pizarra de franquicia)
---------------------------------------------------------------------------
Config.Categories = {
	{ id = "basic1", name = "Productos básicos I" },
	{ id = "basic2", name = "Productos básicos II" },
	{ id = "cleaning", name = "Limpieza e higiene" },
	{ id = "dairy", name = "Lácteos y refrigerados" },
	{ id = "frozen", name = "Congelados" },
	{ id = "drinks", name = "Bebidas alcohólicas" },
	{ id = "pharmacy", name = "Farmacia" },
	{ id = "produce", name = "Frutas y verduras" },
	{ id = "appliances", name = "Electrodomésticos" },
}

local STORAGE_BY_CATEGORY = { dairy = "fridge", frozen = "freezer", produce = "produce", appliances = "appliance" }

---------------------------------------------------------------------------
-- Productos
-- shape: "bottle" | "can" | "jar" | "carton" | "bag" | "box" | "pack" | "round" | "banana" | "leafy" | "long" | "appliance"
-- size: tamaño de una unidad en studs; market: precio de mercado en centavos
-- Comprás al precio de mercado y vendés con margen (hasta 2x sin quejas).
---------------------------------------------------------------------------
-- extra (opcional): weight = qué tan seguido lo buscan los clientes (1 = normal), maxQty = cuántos llevan como máximo
local function product(id, name, category, shape, size, color, color2, unitsPerBox, market, extra)
	extra = extra or {}
	return {
		weight = extra.weight or 1,
		maxQty = extra.maxQty or 3,
		id = id,
		name = name,
		category = category,
		shape = shape,
		size = size,
		color = color,
		color2 = color2,
		unitsPerBox = unitsPerBox,
		market = market,
		storage = STORAGE_BY_CATEGORY[category] or "shelf",
	}
end

local V, C = Vector3.new, Color3.fromRGB

Config.Products = {
	-- Productos básicos I
	product("agua", "Agua mineral", "basic1", "bottle", V(0.6, 1.3, 0.6), C(170, 215, 255), C(40, 110, 220), 12, 120),
	product("fideos", "Fideos", "basic1", "pack", V(0.9, 0.35, 0.6), C(240, 200, 60), C(30, 90, 200), 16, 150),
	product("arroz", "Arroz", "basic1", "bag", V(0.8, 1.0, 0.45), C(245, 245, 240), C(200, 40, 40), 12, 180),
	product("azucar", "Azúcar", "basic1", "bag", V(0.8, 1.0, 0.45), C(250, 250, 250), C(40, 120, 220), 12, 140),
	product("sal", "Sal fina", "basic1", "box", V(0.5, 0.8, 0.35), C(40, 90, 200), C(255, 255, 255), 20, 90),
	product("harina", "Harina", "basic1", "bag", V(0.8, 1.0, 0.45), C(245, 235, 215), C(220, 150, 40), 12, 130),
	product("yerba", "Yerba mate", "basic1", "bag", V(0.7, 1.0, 0.4), C(60, 140, 60), C(240, 220, 90), 10, 350),
	product("galletitas", "Galletitas", "basic1", "pack", V(0.9, 0.35, 0.5), C(120, 70, 40), C(240, 200, 80), 20, 160),
	-- Productos básicos II
	product("aceite", "Aceite de girasol", "basic2", "bottle", V(0.6, 1.4, 0.6), C(245, 215, 90), C(40, 130, 60), 12, 320),
	product("tomate", "Tomate en lata", "basic2", "can", V(0.55, 0.7, 0.55), C(210, 40, 40), C(200, 200, 205), 24, 110),
	product("atun", "Atún", "basic2", "can", V(0.6, 0.35, 0.6), C(60, 110, 200), C(200, 200, 205), 24, 240),
	product("cafe", "Café", "basic2", "jar", V(0.6, 0.8, 0.6), C(90, 55, 30), C(200, 40, 40), 12, 520),
	product("te", "Té en saquitos", "basic2", "box", V(0.8, 0.5, 0.45), C(40, 140, 90), C(240, 240, 240), 16, 190),
	product("cereal", "Cereal", "basic2", "box", V(1.0, 1.4, 0.4), C(230, 120, 40), C(250, 230, 80), 10, 380),
	product("mermelada", "Mermelada", "basic2", "jar", V(0.55, 0.7, 0.55), C(170, 30, 60), C(240, 240, 240), 12, 280),
	product("gaseosa", "Gaseosa cola", "basic2", "bottle", V(0.65, 1.45, 0.65), C(60, 25, 20), C(220, 30, 30), 8, 250),
	-- Limpieza e higiene
	product("detergente", "Detergente", "cleaning", "bottle", V(0.55, 1.1, 0.55), C(60, 200, 120), C(240, 240, 240), 12, 290),
	product("lavandina", "Lavandina", "cleaning", "bottle", V(0.7, 1.4, 0.7), C(245, 245, 245), C(30, 90, 200), 8, 210),
	product("papel", "Papel higiénico", "cleaning", "pack", V(1.0, 0.9, 0.8), C(250, 250, 255), C(100, 170, 230), 8, 420),
	product("jabon", "Jabón", "cleaning", "box", V(0.5, 0.25, 0.35), C(250, 200, 220), C(220, 80, 140), 24, 110),
	product("shampoo", "Shampoo", "cleaning", "bottle", V(0.5, 1.1, 0.5), C(150, 90, 210), C(250, 250, 250), 12, 450),
	product("dentifrico", "Pasta dental", "cleaning", "box", V(0.9, 0.3, 0.3), C(240, 240, 245), C(220, 40, 40), 20, 230),
	-- Lácteos y refrigerados (van en heladera)
	product("leche", "Leche", "dairy", "carton", V(0.55, 1.2, 0.55), C(250, 250, 250), C(40, 110, 220), 12, 160),
	product("yogur", "Yogur", "dairy", "can", V(0.45, 0.6, 0.45), C(250, 245, 235), C(230, 90, 140), 16, 120),
	product("queso", "Queso", "dairy", "box", V(0.8, 0.35, 0.6), C(255, 210, 80), C(200, 40, 40), 10, 650),
	product("manteca", "Manteca", "dairy", "box", V(0.6, 0.3, 0.4), C(250, 235, 170), C(30, 90, 200), 16, 260),
	product("jamon", "Jamón cocido", "dairy", "pack", V(0.8, 0.2, 0.6), C(240, 160, 170), C(250, 250, 250), 12, 480),
	product("huevos", "Huevos x12", "dairy", "box", V(1.0, 0.4, 0.5), C(220, 190, 150), C(250, 250, 250), 8, 420),
	-- Congelados (van en freezer)
	product("helado", "Helado", "frozen", "box", V(0.8, 0.6, 0.6), C(250, 190, 210), C(120, 70, 40), 8, 600),
	product("hamburguesas", "Hamburguesas", "frozen", "pack", V(1.0, 0.35, 0.8), C(200, 40, 40), C(250, 200, 60), 10, 540),
	product("papas", "Papas congeladas", "frozen", "bag", V(0.9, 1.0, 0.35), C(250, 210, 70), C(200, 40, 40), 10, 370),
	product("pizza", "Pizza congelada", "frozen", "pack", V(1.1, 0.25, 1.1), C(230, 90, 40), C(250, 250, 250), 8, 690),
	product("verduras", "Verduras congeladas", "frozen", "bag", V(0.9, 0.9, 0.35), C(80, 170, 80), C(250, 250, 250), 10, 330),
	-- Bebidas alcohólicas
	product("cerveza", "Cerveza", "drinks", "can", V(0.5, 0.8, 0.5), C(230, 190, 40), C(200, 200, 205), 24, 170),
	product("vino", "Vino tinto", "drinks", "bottle", V(0.55, 1.5, 0.55), C(90, 20, 40), C(240, 230, 200), 6, 890),
	product("fernet", "Fernet", "drinks", "bottle", V(0.6, 1.5, 0.6), C(30, 30, 30), C(240, 240, 240), 6, 1250),
	product("sidra", "Sidra", "drinks", "bottle", V(0.6, 1.5, 0.6), C(80, 140, 60), C(240, 210, 60), 6, 520),
	-- Farmacia
	product("ibuprofeno", "Ibuprofeno", "pharmacy", "box", V(0.6, 0.3, 0.25), C(250, 250, 250), C(230, 120, 40), 20, 380),
	product("curitas", "Curitas", "pharmacy", "box", V(0.6, 0.4, 0.2), C(240, 180, 140), C(40, 110, 220), 20, 250),
	product("alcoholgel", "Alcohol en gel", "pharmacy", "bottle", V(0.45, 0.9, 0.45), C(200, 230, 255), C(40, 110, 220), 12, 310),
	product("protector", "Protector solar", "pharmacy", "bottle", V(0.5, 1.0, 0.5), C(250, 160, 40), C(250, 250, 250), 10, 890),
	-- Frutas y verduras (van en la verdulería; precio por unidad)
	product("manzana", "Manzana", "produce", "round", V(0.48, 0.48, 0.48), C(185, 40, 40), C(90, 60, 30), 30, 60, { maxQty = 5, weight = 1.3 }),
	product("naranja", "Naranja", "produce", "round", V(0.52, 0.52, 0.52), C(235, 140, 35), C(60, 120, 50), 30, 55, { maxQty = 5, weight = 1.2 }),
	product("banana", "Bananas", "produce", "banana", V(0.95, 0.35, 0.45), C(236, 206, 70), C(90, 70, 30), 20, 70, { maxQty = 5, weight = 1.2 }),
	product("tomatefresco", "Tomate", "produce", "round", V(0.46, 0.46, 0.46), C(205, 50, 40), C(60, 130, 50), 30, 50, { maxQty = 5, weight = 1.3 }),
	product("papa", "Papa", "produce", "round", V(0.5, 0.42, 0.5), C(178, 140, 92), C(150, 115, 75), 30, 35, { maxQty = 5, weight = 1.2 }),
	product("cebolla", "Cebolla", "produce", "round", V(0.46, 0.46, 0.46), C(214, 186, 140), C(150, 110, 60), 30, 40, { maxQty = 5 }),
	product("lechuga", "Lechuga", "produce", "leafy", V(0.8, 0.6, 0.8), C(110, 175, 80), C(165, 210, 120), 12, 130, { maxQty = 5 }),
	product("zanahoria", "Zanahoria", "produce", "long", V(0.85, 0.26, 0.26), C(236, 128, 40), C(80, 150, 60), 30, 30, { maxQty = 5 }),
	-- Electrodomésticos (se venden poco pero dejan mucha ganancia; el cliente lleva uno)
	product("pava", "Pava eléctrica", "appliances", "appliance", V(0.9, 1.1, 0.8), C(196, 198, 204), C(40, 40, 45), 4, 4500, { weight = 0.25, maxQty = 1 }),
	product("tostadora", "Tostadora", "appliances", "appliance", V(1.2, 0.8, 0.7), C(188, 190, 196), C(40, 40, 45), 4, 3800, { weight = 0.25, maxQty = 1 }),
	product("licuadora", "Licuadora", "appliances", "appliance", V(0.8, 1.6, 0.8), C(45, 45, 50), C(180, 210, 230), 4, 6500, { weight = 0.2, maxQty = 1 }),
	product("plancha", "Plancha", "appliances", "appliance", V(1.0, 0.6, 0.5), C(80, 140, 200), C(230, 230, 232), 4, 3000, { weight = 0.25, maxQty = 1 }),
	product("microondas", "Microondas", "appliances", "appliance", V(2.0, 1.2, 1.4), C(60, 60, 66), C(30, 30, 35), 2, 12000, { weight = 0.15, maxQty = 1 }),
	product("ventilador", "Ventilador", "appliances", "appliance", V(1.4, 2.2, 0.8), C(230, 230, 232), C(80, 140, 200), 2, 8000, { weight = 0.15, maxQty = 1 }),
	product("tele", "Televisor 32\"", "appliances", "appliance", V(2.8, 1.8, 0.35), C(25, 25, 28), C(40, 60, 90), 2, 25000, { weight = 0.1, maxQty = 1 }),
}

Config.ProductsById = {}
for _, p in Config.Products do
	Config.ProductsById[p.id] = p
end

---------------------------------------------------------------------------
-- Muebles que se construyen con TAB
-- size = tamaño del modelo; footprint = espacio que ocupa en el piso (X, Z)
---------------------------------------------------------------------------
Config.Fixtures = {
	product_shelf = { name = "Estantería", desc = "4 niveles, un producto por nivel.", cost = 25000, size = V(12, 7, 3), footprint = V(12, 0, 3), zone = "shop", storage = "shelf", order = 1 },
	fridge = { name = "Heladera", desc = "Para lácteos y refrigerados.", cost = 60000, size = V(8, 8, 3), footprint = V(8, 0, 3), zone = "shop", storage = "fridge", requires = "dairy", order = 2 },
	freezer = { name = "Freezer", desc = "Para congelados.", cost = 80000, size = V(8, 3.5, 4), footprint = V(8, 0, 4), zone = "shop", storage = "freezer", requires = "frozen", order = 3 },
	checkout = { name = "Caja registradora", desc = "Los clientes hacen fila y pagan acá.", cost = 60000, size = V(3, 3.5, 8), footprint = V(10, 0, 8), zone = "shop", order = 4 },
	self_checkout = { name = "Autocaja", desc = "Los clientes se cobran solos (atrae más ladrones).", cost = 90000, size = V(3, 4.5, 3), footprint = V(5, 0, 5), zone = "shop", requires = "selfcheckout", order = 5 },
	produce_stand = { name = "Verdulería (cajones)", desc = "Cajones de madera para frutas y verduras.", cost = 35000, size = V(8, 4.2, 3.4), footprint = V(8, 0, 3.6), zone = "shop", storage = "produce", requires = "produce", order = 3.5 },
	appliance_shelf = { name = "Góndola de electrodomésticos", desc = "3 niveles altos para electrodomésticos.", cost = 70000, size = V(12, 8, 3), footprint = V(12, 0, 3), zone = "shop", storage = "appliance", requires = "appliances", order = 3.6 },
	delivery_counter = { name = "Mostrador PedidosLla", desc = "Acá preparás los pedidos online; los retira una moto.", cost = 40000, size = V(5, 4.6, 2), footprint = V(5.4, 0, 5.6), zone = "shop", requires = "delivery", order = 8 },
	arcade = { name = "Maquinita retro", desc = "Los clientes juegan una partida y pagan por jugar.", cost = 45000, size = V(2.6, 6.2, 2.4), footprint = V(3, 0, 3.4), zone = "shop", requires = "arcade", order = 7 },
	storage_shelf = { name = "Estante de depósito", desc = "Guarda hasta 10 cajas.", cost = 30000, size = V(10, 7, 3), footprint = V(10, 0, 3), zone = "storage", order = 6 },
	-- Decoración (se puede poner en la tienda, el depósito o afuera)
	plant = { name = "Planta", desc = "Decoración.", cost = 4000, size = V(2, 4, 2), footprint = V(2, 0, 2), zone = "any", decor = true, order = 10 },
	flowers = { name = "Cantero de flores", desc = "Decoración.", cost = 5000, size = V(6, 1.5, 2), footprint = V(6, 0, 2), zone = "any", decor = true, order = 11 },
	bench = { name = "Banco", desc = "Decoración.", cost = 6000, size = V(5, 2, 2), footprint = V(5, 0, 2), zone = "any", decor = true, order = 12 },
	bin = { name = "Tacho de basura", desc = "Decoración.", cost = 3000, size = V(1.6, 2.6, 1.6), footprint = V(1.6, 0, 1.6), zone = "any", decor = true, order = 13 },
	lamp = { name = "Farola", desc = "Decoración con luz.", cost = 8000, size = V(1, 9, 1), footprint = V(1.5, 0, 1.5), zone = "any", decor = true, order = 14 },
	offer_sign = { name = "Cartel de ofertas", desc = "Decoración.", cost = 2500, size = V(3, 4, 0.5), footprint = V(3, 0, 1), zone = "any", decor = true, order = 15 },
}
Config.FIXTURE_REFUND = 0.9

-- Plata inicial: 1 estantería + 1 caja registradora + 1 caja de cada producto básico + envío + colchón
do
	local total = Config.Fixtures.product_shelf.cost + Config.Fixtures.checkout.cost + Config.DELIVERY_FEE + Config.START_MARGIN
	for _, p in Config.Products do
		if p.category == "basic1" then
			total += p.unitsPerBox * p.market
		end
	end
	Config.STARTING_MONEY = total
end

-- Sonidos (biblioteca oficial de Roblox / ProSoundEffects)
Config.SOUNDS = {
	beep = "rbxassetid://9118777437", -- escáner de supermercado
	bell = "rbxassetid://9125390528", -- timbre para llamar al cajero
}

---------------------------------------------------------------------------
-- Zonas del edificio (la tienda y el depósito); las ampliaciones abren más zonas
---------------------------------------------------------------------------
Config.Zones = {
	shop0 = { kind = "shop", minX = -30, maxX = 30, minZ = 0, maxZ = 30 },
	shop1 = { kind = "shop", minX = -30, maxX = 30, minZ = -30, maxZ = 0, expansion = "shop1" },
	shop2 = { kind = "shop", minX = 30, maxX = 60, minZ = -30, maxZ = 30, expansion = "shop2" },
	storage0 = { kind = "storage", minX = -60, maxX = -30, minZ = 5, maxZ = 30 },
	storage1 = { kind = "storage", minX = -60, maxX = -30, minZ = -30, maxZ = 5, expansion = "storage1" },
	outside = { kind = "outside", minX = -28, maxX = 58, minZ = 33, maxZ = 76 }, -- estacionamiento (solo decoración)
	-- Pisos de arriba (encima de la tienda principal), se suben por la escalera del fondo a la derecha
	shopF1 = { kind = "shop", level = 1, minX = -30, maxX = 30, minZ = 0, maxZ = 30, expansion = "floor1" },
	shopF2 = { kind = "shop", level = 2, minX = -30, maxX = 30, minZ = 0, maxZ = 30, expansion = "floor2" },
}

-- Pisos: cada piso está 15 studs más arriba que el anterior
Config.LEVEL_HEIGHT = 15
Config.MAX_LEVEL = 2
function Config.levelY(level)
	return Config.FLOOR_Y + (level or 0) * Config.LEVEL_HEIGHT
end
-- En qué piso está algo según su altura (sirve para personajes, cajas y el piso apuntado)
function Config.levelAt(y)
	return math.clamp(math.floor((y - Config.FLOOR_Y + 4) / Config.LEVEL_HEIGHT), 0, Config.MAX_LEVEL)
end
-- Lugar de la escalera (fondo a la derecha de la tienda): no se puede construir ahí
Config.STAIRWELL = { minX = 14.5, maxX = 30, minZ = 0, maxZ = 10.8 }

-- Lugares donde no se puede construir (puertas, entrada, oficina)
Config.NoBuild = {
	{ minX = -7, maxX = 7, minZ = 21, maxZ = 30 }, -- entrada
	{ minX = -36, maxX = -24, minZ = 7, maxZ = 17 }, -- puerta tienda <-> depósito
	{ minX = -60, maxX = -46, minZ = 18, maxZ = 30 }, -- oficina
	{ minX = -48, maxX = -42, minZ = 19, maxZ = 27 }, -- puerta de la oficina
	{ minX = -47, maxX = -30, minZ = 25, maxZ = 30 }, -- portón del depósito
	{ minX = 7.5, maxX = 13.5, minZ = 31, maxZ = 36 }, -- cartel de ABIERTO/CERRADO
	{ minX = -15.5, maxX = -8, minZ = 31, maxZ = 35.5 }, -- cajeros Tesoro Digital
}

function Config.footprint(fixtureType, x, z, rot)
	local def = Config.Fixtures[fixtureType]
	local sx, sz = def.footprint.X, def.footprint.Z
	if rot % 2 == 1 then
		sx, sz = sz, sx
	end
	return { minX = x - sx / 2, maxX = x + sx / 2, minZ = z - sz / 2, maxZ = z + sz / 2 }
end

local function overlaps(a, b)
	return a.minX < b.maxX and a.maxX > b.minX and a.minZ < b.maxZ and a.maxZ > b.minZ
end

-- unlocked: set de ampliaciones compradas; others: footprints de los otros muebles DEL MISMO PISO
-- level: piso donde se arma (0 = planta baja)
function Config.validatePlacement(fixtureType, x, z, rot, unlocked, others, level)
	local def = Config.Fixtures[fixtureType]
	if not def then
		return false, "Mueble inválido."
	end
	level = level or 0
	local fp = Config.footprint(fixtureType, x, z, rot)
	local inside = false
	for _, zone in Config.Zones do
		local kindOk = zone.kind == def.zone or (def.zone == "any")
		if kindOk and (zone.level or 0) == level and (not zone.expansion or unlocked[zone.expansion]) then
			local m = 0.6
			if fp.minX >= zone.minX + m and fp.maxX <= zone.maxX - m and fp.minZ >= zone.minZ + m and fp.maxZ <= zone.maxZ - m then
				inside = true
				break
			end
		end
	end
	if not inside then
		if def.zone == "shop" then
			return false, "Tiene que ir dentro de la tienda."
		elseif def.zone == "storage" then
			return false, "Tiene que ir dentro del depósito."
		end
		return false, "Tiene que ir dentro del local o en el estacionamiento."
	end
	if level == 0 then
		for _, nb in Config.NoBuild do
			if overlaps(fp, nb) then
				return false, "Ahí bloquea una puerta o la entrada."
			end
		end
	end
	-- La escalera: en planta baja, solo si ya compraste el primer piso; arriba, siempre
	if (level > 0 or unlocked.floor1) and overlaps(fp, Config.STAIRWELL) then
		return false, "Ahí va la escalera."
	end
	for _, other in others do
		if overlaps(fp, other) then
			return false, "Choca con otro mueble."
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Pizarra de franquicia (se paga con puntos de franquicia)
---------------------------------------------------------------------------
Config.Perks = {
	{ id = "basic2", name = "Productos básicos II", desc = "Aceite, latas, café, té, cereal, mermelada y gaseosa.", cost = 1 },
	{ id = "cleaning", name = "Limpieza e higiene", desc = "Detergente, lavandina, papel, jabón, shampoo y pasta dental.", cost = 1 },
	{ id = "employees1", name = "Empleados I", desc = "Podés contratar hasta 2 empleados.", cost = 1 },
	{ id = "recycling", name = "Cursos de reciclaje", desc = "Cada caja reciclada paga $2.50 en vez de $1.50.", cost = 1 },
	{ id = "wifi", name = "Wifi gratis", desc = "+15% de clientes.", cost = 1 },
	{ id = "logistics", name = "Visualización logística", desc = "Ves el stock en tienda y depósito al hacer pedidos.", cost = 1 },
	{ id = "dairy", name = "Lácteos y refrigerados", desc = "Desbloquea la heladera y los productos frescos.", cost = 2, requires = "basic2" },
	{ id = "drinks", name = "Bebidas alcohólicas", desc = "Cerveza, vino, fernet y sidra.", cost = 2, requires = "basic2" },
	{ id = "coffee", name = "Café gratis a la mañana", desc = "Los empleados trabajan 20% más rápido.", cost = 1, requires = "employees1" },
	{ id = "security", name = "Formación en seguridad", desc = "Los empleados pueden trabajar de guardias.", cost = 2, requires = "employees1" },
	{ id = "employees2", name = "Empleados II", desc = "Podés contratar hasta 4 empleados.", cost = 2, requires = "employees1" },
	{ id = "marketing", name = "Cursos de marketing I", desc = "+10% de dinero en cada venta.", cost = 2 },
	{ id = "aircon", name = "Aire acondicionado", desc = "+15% de clientes y +30 s de paciencia.", cost = 2, requires = "wifi" },
	{ id = "frozen", name = "Congelados", desc = "Desbloquea el freezer y los congelados.", cost = 2, requires = "dairy" },
	{ id = "pharmacy", name = "Farmacia", desc = "Ibuprofeno, curitas, alcohol en gel y protector solar.", cost = 3, requires = "cleaning" },
	{ id = "selfcheckout", name = "Autocajas", desc = "Desbloquea las autocajas: cobran solas pero atraen ladrones.", cost = 2, requires = "marketing" },
	{ id = "employees3", name = "Empleados III", desc = "Podés contratar hasta 6 empleados.", cost = 3, requires = "employees2" },
	{ id = "delivery", name = "Delivery PedidosLla", desc = "Mostrador de pedidos online: los preparás y los retira una moto (PedidosLla cobra 15% de comisión).", cost = 2, requires = "logistics" },
	{ id = "arcade", name = "Zona de juegos", desc = "Maquinitas retro: los clientes juegan una partida y pagan $2.00 cada vez.", cost = 2, requires = "wifi" },
	{ id = "produce", name = "Frutas y verduras", desc = "Verdulería: manzanas, naranjas, bananas, tomates, papas, cebollas, lechuga y zanahorias.", cost = 1, requires = "basic2" },
	{ id = "appliances", name = "Electrodomésticos", desc = "Pavas, tostadoras, licuadoras, planchas, microondas, ventiladores y televisores. Se venden poco pero dejan mucha ganancia.", cost = 3, requires = "marketing" },
}
Config.PerksById = {}
for _, perk in Config.Perks do
	Config.PerksById[perk.id] = perk
end

---------------------------------------------------------------------------
-- Ampliaciones (se pagan con dinero)
---------------------------------------------------------------------------
Config.Expansions = {
	{ id = "storage1", name = "Ampliación de depósito", desc = "Duplica el tamaño del depósito.", cost = 150000 },
	{ id = "shop1", name = "Ampliación de tienda I", desc = "Abre la zona trasera de la tienda.", cost = 250000 },
	{ id = "shop2", name = "Ampliación de tienda II", desc = "Abre el ala derecha de la tienda.", cost = 600000, requires = "shop1" },
	{ id = "floor1", name = "Primer piso", desc = "Construye un piso arriba de la tienda, con escalera al fondo a la derecha.", cost = 750000, requires = "shop1" },
	{ id = "floor2", name = "Segundo piso", desc = "Un piso más arriba (la escalera sigue subiendo).", cost = 1200000, requires = "floor1" },
}
Config.Overlaps = overlaps
Config.ExpansionsById = {}
for _, e in Config.Expansions do
	Config.ExpansionsById[e.id] = e
end

---------------------------------------------------------------------------
-- Préstamos y cobradores
---------------------------------------------------------------------------
Config.Loans = {
	{ id = "small", name = "Préstamo chico", amount = 100000, interest = 0.10, days = 5 },
	{ id = "medium", name = "Préstamo mediano", amount = 300000, interest = 0.15, days = 7 },
	{ id = "large", name = "Préstamo grande", amount = 800000, interest = 0.25, days = 10 },
}
Config.LoansById = {}
for _, loan in Config.Loans do
	Config.LoansById[loan.id] = loan
end
Config.COLLECTOR_PENALTY = 0.2 -- los cobradores se llevan la cuota atrasada + 20%
Config.COLLECTOR_HITS = 3 -- escobazos para echar a un cobrador
Config.COLLECTOR_STEAL = 0.25 -- parte de la deuda atrasada que se llevan en cada golpe
Config.COLLECTOR_ATTACK_DELAY = 2.2 -- segundos entre golpes
Config.COLLECTOR_DAMAGE = 15
Config.COLLECTOR_ARRIVAL_HOUR = 9.5
Config.COLLECTOR_MAX = 4

---------------------------------------------------------------------------
-- Personalización del local
---------------------------------------------------------------------------
Config.DEFAULT_STORE_NAME = "SUPERMERCADO"
Config.FloorPresets = {
	{ name = "Clásico", a = C(212, 208, 200), b = C(196, 192, 184) },
	{ name = "Cálido", a = C(218, 206, 186), b = C(200, 186, 160) },
	{ name = "Ajedrez", a = C(215, 212, 205), b = C(55, 55, 60) },
	{ name = "Menta", a = C(200, 214, 200), b = C(172, 196, 176) },
	{ name = "Cielo", a = C(200, 210, 222), b = C(172, 190, 212) },
}
Config.WallPresets = {
	{ name = "Blanco y verde", color = C(214, 208, 198), stripe = C(58, 140, 90) },
	{ name = "Crema y rojo", color = C(218, 206, 182), stripe = C(175, 72, 62) },
	{ name = "Celeste y azul", color = C(192, 208, 218), stripe = C(52, 100, 165) },
	{ name = "Gris y naranja", color = C(182, 184, 188), stripe = C(208, 150, 64) },
}
Config.SignColors = {
	C(58, 140, 90), C(175, 66, 58), C(52, 100, 165), C(208, 150, 64), C(115, 70, 155), C(40, 40, 45),
}

---------------------------------------------------------------------------
-- Salas (menú principal)
---------------------------------------------------------------------------
Config.ROOM_NAME_MIN = 3
Config.ROOM_NAME_MAX = 24
Config.PASSWORD_MIN = 4
Config.PASSWORD_MAX = 20

-- Seguridad de las salas (contra adivinar contraseñas a la fuerza)
Config.JOIN_COOLDOWN = 2 -- segundos mínimos entre intentos de entrar
Config.MAX_FAILS_PER_PLAYER = 5 -- intentos fallidos por jugador...
Config.MAX_FAILS_PER_ROOM = 20 -- ...y por sala...
Config.FAIL_WINDOW = 600 -- ...cada 10 minutos (después se bloquea hasta que pase el tiempo)
Config.TICKET_SECONDS = 180 -- el pase para entrar a una sala dura 3 minutos

-- Para probar rápido en Studio: true = al darle Play entrás directo a tu súper, sin menú, nombre ni contraseña.
-- Ponelo en false para probar el menú principal con salas.
Config.STUDIO_SKIP_LOBBY = true

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
function Config.formatMoney(cents)
	cents = math.floor((cents or 0) + 0.5)
	local sign = cents < 0 and "-" or ""
	cents = math.abs(cents)
	local dollars = tostring(math.floor(cents / 100))
	local withCommas = dollars:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return string.format("%s$%s.%02d", sign, withCommas, cents % 100)
end

function Config.formatClock(hours)
	local total = math.floor(hours * 60 + 0.5)
	return string.format("%02d:%02d", math.floor(total / 60) % 24, total % 60)
end

function Config.weekdayName(day)
	return Config.WEEKDAYS[((day - 1) % 7) + 1]
end

return Config
