-- Delivery "PedidosLla": con el súper abierto y un mostrador de pedidos, llegan pedidos online.
-- 1) El pedido aparece en la pantalla del mostrador (con tiempo límite).
-- 2) Un jugador hace click en el mostrador: se sacan los productos de las estanterías y se arma la bolsa
--    (si falta algo, queda anotado y se completa después de reponer).
-- 3) Llega la moto, el repartidor entra, retira la bolsa y se va. Se cobra el pedido menos la comisión.
-- Si no se prepara a tiempo, el pedido se cancela y baja la satisfacción.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.State)
local Fixtures = require(script.Parent.Fixtures)
local NPC = require(script.Parent.NPC)
local Vehicles = require(script.Parent.Vehicles)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Interact = require(script.Parent.Interact)

local Delivery = {}
local refs
local order -- pedido actual (uno a la vez)
local nextOrderAt = 0
local nextId = 0
local fmt = Config.formatMoney
local APP = Config.DELIVERY_APP

local HINTS = {
	none = "🛵 Mostrador " .. APP .. ": esperando pedidos online",
	pending = "🛵 Click: preparar el pedido (saca los productos de las estanterías)",
	ready = "🛵 Pedido listo: ya viene el repartidor a buscarlo",
}

local function counters()
	return Fixtures.byType("delivery_counter")
end

local function productsOnShelves()
	local list, seen = {}, {}
	for _, s in Fixtures.allProductSlots() do
		local id = s.slot.productId
		if id and s.slot.stock > 0 and not seen[id] and State.isProductUnlocked(id) then
			seen[id] = true
			table.insert(list, id)
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Pantalla del mostrador
---------------------------------------------------------------------------
local function refreshScreens()
	for _, f in counters() do
		local textValue
		if order and order.counter == f then
			local lines = { string.format("<b>%s · Pedido #%d</b>", APP, order.id) }
			for _, line in order.lines do
				local prod = Config.ProductsById[line.id]
				table.insert(lines, string.format("%s %dx %s", line.done >= line.qty and "✅" or "⬜", line.qty, prod.name))
			end
			if order.status == "pending" then
				table.insert(lines, string.format("⏱ %ds · Click para preparar", math.max(0, math.ceil(order.expires - os.clock()))))
			elseif order.status == "ready" then
				table.insert(lines, "🛍 Listo · esperando la moto")
			else
				table.insert(lines, "🛵 Retirando...")
			end
			textValue = table.concat(lines, "\n")
		else
			textValue = "<b>" .. APP .. "</b>\n" .. (State.phase == "Abierto" and "Esperando pedidos..." or "Abrí el súper para recibir pedidos")
		end
		for _, label in f.orderLabels or {} do
			label.Text = textValue
		end
		if f.counterPart then
			local hint = HINTS.none
			if order and order.counter == f then
				hint = order.status == "pending" and HINTS.pending or HINTS.ready
			end
			Interact.setHint(f.counterPart, hint)
		end
	end
end

local function markCounter(f)
	if f.counterPart then
		Interact.mark(f.counterPart, "delivery", HINTS.none)
	end
end

---------------------------------------------------------------------------
-- Bolsa del pedido
---------------------------------------------------------------------------
local function makeBag(counter)
	local bag = StoreBuilder.part({
		Name = "PedidoBolsa",
		Size = Vector3.new(1.1, 1.2, 0.7),
		CFrame = counter.anchors.bag * CFrame.new(0, 0.6, 0),
		Color = Color3.fromRGB(196, 160, 118),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = counter.model,
	})
	local band = StoreBuilder.part({
		Name = "PedidoBanda",
		Size = Vector3.new(1.12, 0.3, 0.72),
		CFrame = bag.CFrame * CFrame.new(0, 0.2, 0),
		Color = Color3.fromRGB(214, 36, 74),
		CanCollide = false,
		CanQuery = false,
		Parent = counter.model,
	})
	return { bag, band }
end

local function destroyBag()
	if order and order.bag then
		for _, p in order.bag do
			p:Destroy()
		end
		order.bag = nil
	end
end

local function orderTotal()
	local total = 0
	for _, line in order.lines do
		total += line.price * line.qty
	end
	return total
end

local function cancel(reason)
	if not order then
		return
	end
	-- lo que ya se había sacado vuelve a las estanterías
	for _, line in order.lines do
		for _ = 1, line.done do
			Fixtures.returnProduct(line.id)
		end
	end
	destroyBag()
	if order.rider and order.rider.model then
		order.rider.model:Destroy()
	end
	if order.moto then
		Vehicles.setRider(order.moto, true)
		Vehicles.motoDepart(order.moto)
	end
	State.notify(nil, "❌ " .. APP .. ": " .. reason, "bad")
	order = nil
	nextOrderAt = os.clock() + math.random(Config.DELIVERY_EVERY_MIN, Config.DELIVERY_EVERY_MAX)
	refreshScreens()
end

---------------------------------------------------------------------------
-- El repartidor viene a buscar la bolsa
---------------------------------------------------------------------------
local function pickup(current)
	local ok, moto, door = pcall(Vehicles.motoArrive)
	if not ok or not moto then
		warn("[Supermercado] La moto de " .. APP .. " no pudo llegar:", moto)
		moto = nil
		door = refs.points.entranceOutside
	end
	if order ~= current then
		if moto then
			Vehicles.motoDepart(moto)
		end
		return
	end
	current.moto = moto
	if moto then
		Vehicles.setRider(moto, false)
	end
	local rider = NPC.create("Repartidor", {
		displayName = APP,
		walkSpeed = 13,
		uniform = { shirt = Color3.fromRGB(214, 36, 74), pants = Color3.fromRGB(40, 45, 60) },
	})
	current.rider = rider
	NPC.spawn(rider, door)
	local counter = current.counter
	NPC.walkTo(rider, refs.points.entranceOutside, 40)
	NPC.walkTo(rider, refs.points.entranceInside, 20)
	local reached = order == current and Fixtures.list[counter.id] == counter and NPC.walkTo(rider, counter.anchors.rider, 40)
	if order ~= current then
		return
	end
	if reached then
		NPC.face(rider, counter.anchors.face)
		NPC.say(rider, "¡Hola! Vengo a buscar el pedido #" .. current.id .. " 🛵", 2.5)
		task.wait(1.2)
		current.status = "pickup"
		destroyBag()
		-- Cobro: total a precio de góndola menos la comisión de la app (+ propina si fue rápido)
		local total = orderTotal()
		local income = math.floor(total * (1 - Config.DELIVERY_COMMISSION) + 0.5)
		local tip = 0
		if current.preparedFast and math.random() < Config.DELIVERY_TIP_CHANCE then
			tip = math.random(1, 4) * 100
		end
		State.addIncome(income + tip)
		State.addStat("delivery", 1)
		State.addStat("sales", current.units)
		State.addXP(current.units)
		State.changeSatisfaction(0.5)
		State.notify(nil, string.format("🛵 %s retiró el pedido #%d: +%s (total %s − %d%% de comisión)%s", APP, current.id, fmt(income), fmt(total), math.floor(Config.DELIVERY_COMMISSION * 100 + 0.5), tip > 0 and (" · propina " .. fmt(tip) .. " 🎉") or ""), "good")
		NPC.say(rider, tip > 0 and "¡Gracias! Te dejaron propina 😄" or "¡Gracias, nos vemos! 👋", 2.5)
	end
	-- vuelve a la moto y se va
	NPC.walkTo(rider, refs.points.entranceInside, 20)
	NPC.walkTo(rider, refs.points.entranceOutside, 20)
	NPC.walkTo(rider, door, 30)
	if rider.model then
		rider.model:Destroy()
	end
	if moto and moto.Parent then
		Vehicles.setRider(moto, true)
		Vehicles.motoDepart(moto)
	end
	if order == current then
		order = nil
		nextOrderAt = os.clock() + math.random(Config.DELIVERY_EVERY_MIN, Config.DELIVERY_EVERY_MAX)
		refreshScreens()
	end
end

---------------------------------------------------------------------------
-- Preparar (click en el mostrador)
---------------------------------------------------------------------------
local function prepare(player, part)
	local counter
	for _, f in counters() do
		if f.counterPart == part then
			counter = f
		end
	end
	if not order or order.counter ~= counter then
		State.notify(player, "No hay pedidos para preparar en este mostrador todavía.", "info")
		return
	end
	if order.status ~= "pending" then
		State.notify(player, "El pedido ya está listo: espera al repartidor.", "info")
		return
	end
	local missing = {}
	for _, line in order.lines do
		while line.done < line.qty do
			local found
			for _, s in Fixtures.findSlotsWithProduct(line.id) do
				if s.fixture.slots[s.index].stock > 0 then
					found = s
					break
				end
			end
			if not found then
				break
			end
			Fixtures.removeUnit(found.fixture, found.index, false)
			line.done += 1
			order.units += 1
		end
		if line.done < line.qty then
			table.insert(missing, (line.qty - line.done) .. "x " .. Config.ProductsById[line.id].name)
		end
	end
	if #missing > 0 then
		State.notify(player, "📋 Faltan productos en las estanterías: " .. table.concat(missing, ", ") .. ". Reponé y volvé a hacer click.", "warn")
		refreshScreens()
		return
	end
	order.status = "ready"
	order.preparedFast = (order.expires - os.clock()) > Config.DELIVERY_TIME * 0.5
	order.bag = makeBag(counter)
	State.notify(nil, "🛍 " .. player.DisplayName .. " preparó el pedido #" .. order.id .. ". ¡Ya sale la moto de " .. APP .. "!", "good")
	refreshScreens()
	task.spawn(pickup, order)
end

local function newOrder()
	local available = productsOnShelves()
	if #available == 0 then
		return
	end
	local counter = counters()[math.random(#counters())]
	nextId += 1
	local lines, used = {}, {}
	for _ = 1, math.random(2, 4) do
		local id = available[math.random(#available)]
		if not used[id] then
			used[id] = true
			local prod = Config.ProductsById[id]
			table.insert(lines, { id = id, qty = math.random(1, math.min(prod.maxQty or 3, 3)), done = 0, price = State.getPrice(id) })
		end
	end
	order = { id = nextId, counter = counter, lines = lines, status = "pending", expires = os.clock() + Config.DELIVERY_TIME, units = 0 }
	local names = {}
	for _, line in lines do
		table.insert(names, line.qty .. "x " .. Config.ProductsById[line.id].name)
	end
	State.notify(nil, "🛵 ¡Nuevo pedido de " .. APP .. "! " .. table.concat(names, ", ") .. " · Preparalo en el mostrador (" .. Config.DELIVERY_TIME .. " s).", "info")
	refreshScreens()
end

function Delivery.init(builderRefs)
	refs = builderRefs
	Interact.register("delivery", prepare)
	Fixtures.onCreated(function(f)
		if f.type == "delivery_counter" then
			markCounter(f)
			task.defer(refreshScreens)
		end
	end)
	Fixtures.onRemoved(function(f)
		if order and order.counter == f and order.status == "pending" then
			task.defer(cancel, "se quitó el mostrador y se canceló el pedido.")
		end
	end)
	-- No se puede mover ni vender el mostrador con un pedido en curso
	table.insert(Fixtures.removeGuards, function(f)
		if order and order.counter == f then
			return false, "Hay un pedido de " .. APP .. " en curso en este mostrador."
		end
		return true
	end)
	nextOrderAt = os.clock() + 25
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				if order then
					if order.status == "pending" and os.clock() > order.expires then
						State.changeSatisfaction(-2)
						cancel("el pedido #" .. order.id .. " no se preparó a tiempo y el cliente lo canceló 😠")
					elseif order.status == "pending" then
						refreshScreens()
					end
				elseif State.phase == "Abierto" and State.hasPerk("delivery") and #counters() > 0 and os.clock() >= nextOrderAt then
					nextOrderAt = os.clock() + math.random(Config.DELIVERY_EVERY_MIN, Config.DELIVERY_EVERY_MAX)
					newOrder()
				end
			end)
			if not ok then
				warn("[Supermercado] Error en " .. APP .. ":", err)
			end
		end
	end)
end

-- Al cerrar el día se cancela lo que quedó sin preparar
function Delivery.closeDay()
	if order and order.status == "pending" then
		cancel("el pedido pendiente se canceló por el cierre.")
	end
	refreshScreens()
end

return Delivery
