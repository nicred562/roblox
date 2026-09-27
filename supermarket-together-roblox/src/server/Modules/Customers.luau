-- Clientes: salen de las casas del barrio, entran con su canasto, buscan su lista de compras,
-- se quejan de precios altos o faltantes, hacen fila y pagan. Algunos son ladrones.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.State)
local NPC = require(script.Parent.NPC)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Fixtures = require(script.Parent.Fixtures)
local Checkouts = require(script.Parent.Checkouts)
local Trash = require(script.Parent.Trash)
local Products = require(script.Parent.Products)
local Vehicles = require(script.Parent.Vehicles)
local Remotes = require(Shared:WaitForChild("Remotes"))
local Bank = require(script.Parent.Bank)

local Customers = {}
Customers.active = {} -- [id] = cliente
local refs
local nextId = 0
local droppedFolder

local fmt = Config.formatMoney

local function pick(list)
	return list[math.random(#list)]
end

-- Charlas cuando dos clientes se sientan juntos en un banco
local CHATS = {
	{ "¿Viste cómo subió todo? 😩", "Ni me digas... 😅" },
	{ "Qué lindo día, ¿no? ☀️", "¡Hermoso! 😊" },
	{ "Acá los precios están bien 👍", "Sí, mejor que en CARREFIVE 😏" },
	{ "¿Vas a ver el partido hoy? ⚽", "¡Obvio! 🙌" },
	{ "Me olvidé la yerba 🤦", "Jaja, a mí siempre me pasa 😂" },
	{ "¿Probaste las maquinitas? 🕹️", "¡Sí! Estoy enganchadísimo 😄" },
	{ "La cajera de acá es re amable 😊", "Posta, da gusto venir 👌" },
}
function Customers.init(builderRefs)
	refs = builderRefs
	droppedFolder = Instance.new("Folder")
	droppedFolder.Name = "Dropped"
	droppedFolder.Parent = workspace
	-- Recuperar productos tirados con un click (además de la escoba)
	Remotes.Action.OnServerEvent:Connect(function(player, kind, part)
		if kind ~= "recover" or typeof(part) ~= "Instance" or part.Parent ~= droppedFolder then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - part.Position).Magnitude <= Config.INTERACT_DISTANCE then
			Customers.recoverDropped(part, player)
		end
	end)
end

-- Cuenta solo los clientes que todavía están en la tienda (no los que ya se van a su casa)
function Customers.count()
	local n = 0
	for _, c in Customers.active do
		if not c.leaving then
			n += 1
		end
	end
	return n
end

function Customers.maxCustomers()
	return math.min(Config.MAX_CUSTOMERS_CAP, Config.MAX_CUSTOMERS_BASE + Config.MAX_CUSTOMERS_PER_LEVEL * (State.data.level - 1))
end

local function thiefChance()
	local day = State.data.day
	if day < Config.THIEF_START_DAY then
		return 0
	end
	local chance = Config.THIEF_BASE_CHANCE + (day - Config.THIEF_START_DAY) * Config.THIEF_CHANCE_PER_DAY
	chance += #Fixtures.byType("self_checkout") * 0.03
	return math.min(chance, Config.THIEF_MAX_CHANCE)
end

local function makeShoppingList()
	local present, presentList = {}, {}
	for _, s in Fixtures.allProductSlots() do
		local id = s.slot.productId
		if id and not present[id] then
			present[id] = true
			table.insert(presentList, id)
		end
	end
	local unlocked = State.unlockedProducts()
	local unlockedIds = {}
	for _, prod in unlocked do
		table.insert(unlockedIds, prod.id)
	end
	-- Elige al azar pero respetando qué tan seguido se busca cada producto
	-- (la fruta se lleva mucho; un televisor, muy de vez en cuando)
	local function weightedPick(ids)
		local total = 0
		for _, id in ids do
			total += Config.ProductsById[id].weight or 1
		end
		local r = math.random() * total
		for _, id in ids do
			r -= Config.ProductsById[id].weight or 1
			if r <= 0 then
				return id
			end
		end
		return ids[#ids]
	end
	local n = math.random(1, math.min(6, 2 + math.floor(State.data.level / 3)))
	local byId, list = {}, {}
	for _ = 1, n do
		local id
		if #presentList > 0 and math.random() < 0.85 then
			id = weightedPick(presentList)
		else
			id = weightedPick(unlockedIds)
		end
		local maxQty = Config.ProductsById[id].maxQty or 3
		if byId[id] then
			byId[id].qty = math.min(byId[id].qty + 1, math.max(maxQty, 1) + (maxQty > 1 and 1 or 0))
		else
			byId[id] = { id = id, qty = math.random(1, maxQty) }
			table.insert(list, byId[id])
		end
	end
	return list
end

local function complain(c, message)
	NPC.say(c.npc, message, 3)
	State.addStat("complaints", 1)
	State.changeSatisfaction(-1.2)
end

local function returnCart(c)
	for _, line in c.cart do
		Fixtures.returnProduct(line.productId)
	end
	c.cart = {}
end

local function pickSlot(productId, fromPos)
	local best, bestDist, fallback
	for _, s in Fixtures.findSlotsWithProduct(productId) do
		local slot = s.fixture.slots[s.index]
		local d = (slot.hit.Position - fromPos).Magnitude
		if slot.stock > 0 then
			if not best or d < bestDist then
				best, bestDist = s, d
			end
		else
			fallback = fallback or s
		end
	end
	return best or fallback
end

-- Se sienta un rato en un banco de afuera (y charla si hay alguien al lado)
local function restOnBench(c)
	local free = {}
	for _, seat in StoreBuilder.benchSeats do
		if seat.Parent and not seat.Occupant and not seat:GetAttribute("Reserved") then
			table.insert(free, seat)
		end
	end
	if #free == 0 then
		return
	end
	local seat = pick(free)
	seat:SetAttribute("Reserved", true)
	local npc = c.npc
	local arrived = NPC.walkTo(npc, seat:GetAttribute("StandPoint"), 30)
	if arrived and not c.gone and NPC.sit(npc, seat) then
		c.seat = seat
		task.wait(1.2)
		local neighbour
		for _, other in Customers.active do
			if other ~= c and other.seat and other.npc and (other.seat.Position - seat.Position).Magnitude < 3 then
				neighbour = other
				break
			end
		end
		if neighbour and not c.gone then
			local chat = pick(CHATS)
			NPC.say(npc, chat[1], 3)
			task.wait(2.6)
			if not neighbour.gone and neighbour.npc then
				NPC.say(neighbour.npc, chat[2], 3)
			end
		elseif math.random() < 0.5 then
			NPC.say(npc, pick({ "Ahhh, un descansito 😌", "Qué buenas compras hice 🛍️", "📱...", "Espero el colectivo 🚌" }), 3)
		end
		task.wait(6 + math.random() * 10)
		NPC.standUp(npc, seat)
		c.seat = nil
		task.wait(0.6)
	end
	seat:SetAttribute("Reserved", nil)
end

local function leaveStore(c)
	if c.gone then
		return
	end
	NPC.setIcon(c.npc, nil)
	NPC.walkTo(c.npc, refs.points.entranceInside + Vector3.new(math.random(-3, 3), 0, 0), 30)
	NPC.walkTo(c.npc, refs.points.entranceOutside + Vector3.new(math.random(-3, 3), 0, 0), 20)
	c.leaving = true
	if not c.gone and not c.thief and math.random() < Config.BENCH_CHANCE then
		restOnBench(c)
	end
	NPC.walkTo(c.npc, c.home, 60)
end

-- Juega una partida en una maquinita libre y paga
local function playArcade(c)
	local machines = {}
	for _, f in Fixtures.byType("arcade") do
		if not f.busy and f.anchors and f.anchors.play then
			table.insert(machines, f)
		end
	end
	if #machines == 0 then
		return
	end
	local f = pick(machines)
	f.busy = true
	local npc = c.npc
	if NPC.walkTo(npc, f.anchors.play, 25) and not c.gone and Fixtures.list[f.id] == f then
		NPC.face(npc, f.anchors.face)
		if f.screen and f.screen.Parent then
			f.screen:SetAttribute("Playing", true)
		end
		NPC.say(npc, pick({ "🕹️ ¡Una partidita!", "A ver si bato el récord 🏆", "¡Me encanta este juego! 👾" }), 2.5)
		State.addIncome(Config.ARCADE_PRICE)
		State.addStat("arcade", 1)
		task.wait(7 + math.random() * 7)
		if not c.gone then
			NPC.say(npc, pick({ "¡Récord! 🏆", "Uh, perdí 😅", "¡Casi! 😤", "¡Qué vicio! 😄" }), 2.5)
			State.changeSatisfaction(0.3)
		end
	end
	if f.screen and f.screen.Parent then
		f.screen:SetAttribute("Playing", false)
	end
	f.busy = false
end

---------------------------------------------------------------------------
-- Productos que tiran los ladrones
---------------------------------------------------------------------------
function Customers.recoverDropped(part, player)
	if not part.Parent then
		return
	end
	local productId = part:GetAttribute("ProductId")
	part:Destroy()
	local value = State.getMarket(productId)
	State.addIncome(value)
	State.addStat("recovered", 1)
	if player then
		State.notify(player, "📦 Producto recuperado: +" .. fmt(value), "good")
	end
end

local function dropItem(productId, position)
	local prod = Config.ProductsById[productId]
	if not prod then
		return
	end
	local part = Products.buildLoose(prod, position + Vector3.new(math.random(-1, 1), 1.5, math.random(-1, 1)))
	part:SetAttribute("Kind", "dropped")
	part:SetAttribute("ProductId", productId)
	part.Parent = droppedFolder
	CollectionService:AddTag(part, "Dropped")
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	part:SetAttribute("ProductName", prod.name)
	task.delay(180, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Ladrones
---------------------------------------------------------------------------
local function runThief(c)
	local npc = c.npc
	c.thief = true
	c.willSteal = false
	c.forceThief = false
	if c.checkout then
		Checkouts.leave(c)
	end
	if #c.cart == 0 then
		c.thief = false
		leaveStore(c)
		return
	end
	NPC.setIcon(npc, "🦹 LADRÓN", Color3.fromRGB(200, 40, 40))
	NPC.say(npc, "😈", 2)
	State.notify(nil, "🚨 ¡Un ladrón se escapa con mercadería! Pegale con la escoba antes de que llegue a la calle.", "bad")
	npc.humanoid.WalkSpeed = 19
	local target = Vector3.new(math.random(-15, 40), Config.FLOOR_Y, Config.ESCAPE_Z + 6)
	local started = os.clock()

	while c.thief and not c.gone do
		if npc.knocked then
			task.wait(0.2)
		else
			NPC.walkTo(npc, target, 40)
			if c.gone then
				return
			end
			if c.thief and not npc.knocked and (npc.root.Position.Z >= Config.ESCAPE_Z or os.clock() - started > 90) then
				State.addStat("thefts", 1)
				State.changeSatisfaction(-2)
				State.notify(nil, "💸 El ladrón escapó con " .. #c.cart .. " producto(s).", "bad")
				c.cart = {}
				Customers.remove(c)
				return
			end
			task.wait(0.1)
		end
	end

	if not c.gone then
		NPC.setIcon(npc, nil)
		npc.humanoid.WalkSpeed = 10
		NPC.say(npc, "¡Está bien, me rindo! 😣", 3)
		task.wait(1)
		leaveStore(c)
	end
end

-- Escobazo (jugador o guardia). Devuelve true si el modelo era un cliente.
function Customers.hitNPC(model, fromPosition, byName)
	local c
	for _, other in Customers.active do
		if other.npc and other.npc.model == model then
			c = other
			break
		end
	end
	if not c then
		return false
	end
	if c.npc.knocked then
		return true
	end
	if c.thief then
		task.spawn(NPC.knockDown, c.npc, fromPosition, 1.6)
		local line = table.remove(c.cart)
		if line then
			dropItem(line.productId, c.npc.root.Position)
		end
		if #c.cart == 0 then
			c.thief = false
			State.addStat("caught", 1)
			State.notify(nil, "👮 " .. (byName or "Alguien") .. " atrapó al ladrón. ¡Recuperá lo que tiró!", "good")
		end
	elseif c.willSteal then
		c.forceThief = true
		NPC.say(c.npc, "¡Me descubrieron! 😱", 2)
		task.spawn(NPC.knockDown, c.npc, fromPosition, 1)
	else
		NPC.say(c.npc, "¡Ay! ¿Qué te pasa? 😠", 2.5)
		State.changeSatisfaction(-3)
		task.spawn(function()
			NPC.knockDown(c.npc, fromPosition, 0.8)
			c.queueMoved = c.checkout ~= nil
		end)
	end
	return true
end

function Customers.activeThieves()
	local list = {}
	for _, c in Customers.active do
		if c.thief and c.npc and NPC.alive(c.npc) then
			table.insert(list, c)
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Compras y caja
---------------------------------------------------------------------------
local function shop(c)
	local npc = c.npc
	for _, item in c.list do
		if c.gone or c.forceThief then
			return
		end
		local prod = Config.ProductsById[item.id]
		local found = pickSlot(item.id, npc.root.Position)
		if not found then
			complain(c, "No hay " .. prod.name .. " 😕")
			task.wait(1)
		else
			local fixture, index = found.fixture, found.index
			local standAt, faceAt = Fixtures.standPoint(fixture, index)
			NPC.walkTo(npc, standAt, 30)
			if c.gone or c.forceThief then
				return
			end
			NPC.face(npc, faceAt)
			task.wait(0.6 + math.random() * 0.6)

			local price = State.getPrice(item.id)
			local ratio = price / math.max(State.getMarket(item.id), 1)
			-- Demanda realista: hasta 1.3x compran todos; más caro, cada vez menos; desde 2x nadie
			local buyChance = 1
			if ratio > Config.PRICE_COMFORT_RATIO then
				buyChance = 1 - (ratio - Config.PRICE_COMFORT_RATIO) / (Config.PRICE_LIMIT_RATIO - Config.PRICE_COMFORT_RATIO)
			end
			if ratio >= Config.PRICE_LIMIT_RATIO then
				complain(c, "¡" .. prod.name .. " está carísimo! 😤")
			elseif math.random() > buyChance then
				NPC.say(npc, prod.name .. " está caro... lo dejo 😒", 2.5)
				State.addStat("complaints", 1)
				State.changeSatisfaction(-0.5)
			else
				if ratio <= 1.05 and math.random() < 0.3 then
					NPC.say(npc, "¡Qué buen precio! 😄", 2)
					State.changeSatisfaction(0.3)
				end
				local taken = 0
				for _ = 1, item.qty do
					local slot = fixture.slots[index]
					if not Fixtures.list[fixture.id] or not slot or slot.productId ~= item.id or slot.stock <= 0 then
						break
					end
					Fixtures.removeUnit(fixture, index, false)
					table.insert(c.cart, { productId = item.id, price = price })
					taken += 1
					task.wait(0.35)
				end
				if taken == 0 then
					complain(c, "Se acabó " .. prod.name .. " 😞")
				end
			end
		end
	end
end

-- Devuelve "paid", "thief" o "left"
local function waitAtCheckout(c, co)
	local npc = c.npc
	Checkouts.join(co, c)
	local patience = Config.PATIENCE + (State.hasPerk("aircon") and 30 or 0)
	local waited, warned, last = 0, false, os.clock()

	while not c.paid and not c.gone do
		if c.forceThief then
			return "thief"
		end
		if c.queueMoved and c.checkout and not npc.knocked then
			c.queueMoved = false
			local index = c.queueIndex
			local co2 = c.checkout
			NPC.walkTo(npc, Checkouts.spot(co2, index), 25)
			if c.gone or not c.checkout then
				break
			end
			if index == 1 then
				NPC.face(npc, co2.fixture.anchors.counter)
			else
				NPC.face(npc, Checkouts.spot(co2, index - 1))
			end
			if not c.queueMoved and c.queueIndex == 1 then
				c.atFront = true
			end
		end

		local now = os.clock()
		local dt = now - last
		last = now
		local beingServed = c.checkout and c.checkout.current == c
		waited += beingServed and dt * 0.25 or dt

		if not warned and waited > patience * 0.6 then
			warned = true
			NPC.say(npc, "Qué lento va esto... 😤", 3)
		end
		if waited > patience then
			Checkouts.leave(c)
			if State.data.day >= Config.THIEF_START_DAY and math.random() < 0.5 then
				NPC.say(npc, "¡Me canso de esperar! Me lo llevo gratis 😈", 3)
				return "thief"
			end
			complain(c, "¡Me voy, tardan demasiado!")
			returnCart(c)
			return "left"
		end
		task.wait(0.25)
	end
	return c.paid and "paid" or "left"
end

local function runCustomer(c)
	local npc = c.npc
	-- Algunos pasan antes por el cajero Tesoro Digital a sacar plata (y pagan en efectivo)
	if math.random() < Config.ATM_CHANCE and Bank.npcWithdraw(npc) then
		c.payCard = false
	end
	if c.gone then
		return
	end
	NPC.addBasket(npc)
	NPC.walkTo(npc, refs.points.entranceOutside + Vector3.new(math.random(-4, 4), 0, 0), 70)
	if c.gone then
		return
	end
	NPC.walkTo(npc, refs.points.entranceInside + Vector3.new(math.random(-3, 3), 0, 0), 20)
	if c.gone then
		return
	end

	shop(c)
	if c.gone then
		return
	end
	if math.random() < 0.1 then
		Trash.spawnAt(npc.root.Position)
	end
	if #c.cart == 0 then
		NPC.say(npc, "No encontré nada... 😞", 3)
		State.changeSatisfaction(-1)
		leaveStore(c)
		return
	end
	if c.willSteal or c.forceThief then
		runThief(c)
		return
	end
	-- Algunos juegan una partida en las maquinitas antes de pagar
	if math.random() < Config.ARCADE_CHANCE then
		playArcade(c)
		if c.gone then
			return
		end
	end

	local co = Checkouts.choose()
	if not co then
		if Checkouts.count() == 0 then
			complain(c, "¡No hay cajas para pagar! 😡")
		else
			complain(c, "¡Las cajas están llenas! 😡")
		end
		if State.data.day >= Config.THIEF_START_DAY then
			runThief(c)
		else
			returnCart(c)
			leaveStore(c)
		end
		return
	end

	local result = waitAtCheckout(c, co)
	if result == "thief" then
		runThief(c)
		return
	end
	leaveStore(c)
end

function Customers.remove(c)
	if c.removed then
		return
	end
	c.removed = true
	c.gone = true
	if c.checkout then
		Checkouts.leave(c)
	end
	if c.npc and c.npc.model then
		c.npc.model:Destroy()
	end
	-- Si vino en auto, se va manejando
	if c.stall and not c.carLeft then
		c.carLeft = true
		if c.car then
			Vehicles.departCar(c.car, c.stall)
		else
			Vehicles.releaseStall(c.stall)
		end
	end
	Customers.active[c.id] = nil
end

local function spawnPoint()
	if #StoreBuilder.houseDoors > 0 and math.random() < 0.65 then
		return StoreBuilder.houseDoors[math.random(#StoreBuilder.houseDoors)]
	end
	local z = math.random() < 0.5 and 78 or 98
	return Vector3.new(math.random(-60, 80), 0.3, z)
end

-- opts.thief = true fuerza un ladrón (lo usa la herramienta de prueba de Studio)
function Customers.spawn(opts)
	if #State.unlockedProducts() == 0 then
		return
	end
	nextId += 1
	local c = {
		id = nextId,
		cart = {},
		list = makeShoppingList(),
		payCard = math.random() < Config.CARD_CHANCE,
		willSteal = (opts and opts.thief) or math.random() < thiefChance(),
		home = spawnPoint(),
	}
	Customers.active[c.id] = c
	-- Algunos llegan en auto y estacionan
	if math.random() < Config.CAR_CUSTOMER_CHANCE then
		c.stall = Vehicles.reserveStall()
	end

	task.spawn(function()
		if c.stall then
			local ok, car, door = pcall(Vehicles.arriveCar, c.stall)
			if ok and car then
				c.car = car
				c.home = door
			end
			if c.gone then
				-- lo sacaron mientras llegaba (por ejemplo, al cerrar): el auto se vuelve a ir
				if c.car then
					Vehicles.departCar(c.car, c.stall)
				end
				return
			end
		end
		-- Velocidad con decimales: casi nunca dos clientes caminan exactamente igual
		c.npc = NPC.create("Cliente", { walkSpeed = 9.5 + math.random() * 3.5, randomAvatar = true })
		c.npc.pathCosts = { StaffOnly = math.huge } -- no pasan por el depósito ni la oficina
		if c.gone then
			c.npc.model:Destroy()
			return
		end
		NPC.spawn(c.npc, c.home)
		local ok, err = pcall(runCustomer, c)
		if not ok then
			warn("[Supermercado] Error en cliente:", err)
		end
		Customers.remove(c)
	end)
end

-- Al cerrar, los que quedan se van y devuelven lo que tenían en el canasto
function Customers.forceLeaveAll()
	for _, c in Customers.active do
		if not c.paid and not c.thief then
			returnCart(c)
		end
		Customers.remove(c)
	end
end

return Customers
