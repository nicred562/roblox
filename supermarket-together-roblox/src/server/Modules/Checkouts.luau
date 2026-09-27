-- Cajas registradoras y autocajas: fila de clientes, productos en la cinta (se escanean con click),
-- cobro con tarjeta (tipear el total) o efectivo (armar el vuelto), empleados cajeros.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local NPC = require(script.Parent.NPC)
local Fixtures = require(script.Parent.Fixtures)
local Products = require(script.Parent.Products)

local Checkouts = {}
Checkouts.list = {} -- [fixtureId] = co
local operatorOf = {} -- [player] = co

local BELT_SLOTS = 5
local fmt = Config.formatMoney

local function flat(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------------
-- Visual
---------------------------------------------------------------------------
local function updateMonitor(co)
	local label = co.fixture.monitorLabel
	if not label then
		return
	end
	local title = co.auto and "AUTOCAJA" or ("CAJA " .. co.number)
	if co.current then
		label.Text = string.format("%s\n%d/%d artículos\n%s", title, co.scannedCount, co.itemsTotal, fmt(co.scannedTotal))
	else
		label.Text = title .. (co.open and "\nLIBRE" or "\nCERRADA")
	end
	local customer = co.fixture.customerLabel
	if customer then
		customer.Text = co.current and ("TOTAL\n" .. fmt(co.scannedTotal)) or (co.open and "BIENVENIDO" or "CAJA CERRADA")
	end
end

local function updateLight(co)
	local f = co.fixture
	if f.laneLight then
		f.laneLight.Color = co.open and Color3.fromRGB(40, 200, 80) or Color3.fromRGB(220, 50, 50)
	end
	for _, label in f.laneLabels or {} do
		label.Text = tostring(co.number)
	end
	if f.laneLight then
		f.laneLight:SetAttribute("Open", co.open)
	end
	updateMonitor(co)
end

local function sendState(co)
	local player = co.operator
	if not player then
		return
	end
	if not co.current then
		Remotes.CheckoutState:FireClient(player, { id = co.id, number = co.number, stage = "idle", open = co.open })
		return
	end
	Remotes.CheckoutState:FireClient(player, {
		id = co.id,
		number = co.number,
		stage = co.stage,
		scanned = co.scannedCount,
		count = co.itemsTotal,
		total = co.scannedTotal,
		method = co.method,
		open = co.open,
	})
end

local function beep(co)
	local sound = co.sound
	if sound then
		sound:Play()
	end
end

---------------------------------------------------------------------------
-- Productos en la cinta
---------------------------------------------------------------------------
local function clearVisuals(co)
	for _, item in co.belt do
		if item.model then
			item.model:Destroy()
		end
	end
	co.belt = {}
	co.beltSlots = {}
	if co.payModel then
		co.payModel:Destroy()
		co.payModel = nil
	end
end

local function freeBeltSlot(co)
	for k = 1, BELT_SLOTS do
		if not co.beltSlots[k] then
			return k
		end
	end
	return nil
end

local function placeNextItem(co)
	local k = freeBeltSlot(co)
	if not k or #co.pending == 0 then
		return false
	end
	local line = table.remove(co.pending, 1)
	co.nextItemId += 1
	local itemId = co.nextItemId
	local prod = Config.ProductsById[line.productId]
	local model = Products.build(prod, co.fixture.anchors.belt(k), true)
	model:SetAttribute("Kind", "beltitem")
	model:SetAttribute("CheckoutId", co.id)
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("ProductName", prod.name)
	model:SetAttribute("ProductId", prod.id)
	model.Parent = co.fixture.model
	co.belt[itemId] = { id = itemId, productId = line.productId, price = line.price, model = model, k = k }
	co.beltSlots[k] = itemId
	return true
end

local function makePayModel(co)
	local isCard = co.method == "card"
	local p = Instance.new("Part")
	p.Name = isCard and "Card" or "Cash"
	p.Anchored = true
	p.CanCollide = false
	p.Size = isCard and Vector3.new(0.55, 0.05, 0.35) or Vector3.new(0.75, 0.22, 0.38)
	p.Color = isCard and Color3.fromRGB(40, 90, 200) or Color3.fromRGB(110, 170, 100)
	p.Material = Enum.Material.SmoothPlastic
	p.CFrame = (isCard and co.fixture.anchors.card or co.fixture.anchors.cash) * CFrame.new(0, p.Size.Y / 2, 0)
	p:SetAttribute("Kind", isCard and "card" or "cash")
	p:SetAttribute("CheckoutId", co.id)
	p.Parent = co.fixture.model
	co.payModel = p
end

-- El cliente paga con un billete "redondo" mayor o igual al total
local function cashGiven(total)
	local options = {}
	for _, step in { 100, 500, 1000, 2000, 5000, 10000 } do
		local v = math.ceil(total / step) * step
		if v >= total then
			table.insert(options, v)
		end
	end
	return options[math.random(#options)]
end

local function enterPayment(co)
	co.stage = "payment"
	co.autoTimer = 1.2
	if co.method == "cash" then
		co.given = cashGiven(co.scannedTotal)
	end
	makePayModel(co)
	local c = co.current
	if c and c.npc then
		NPC.say(c.npc, co.method == "card" and "Pago con tarjeta 💳" or ("Tomá, " .. fmt(co.given) .. " 💵"), 3)
	end
	updateMonitor(co)
	sendState(co)
end

local function checkReady(co)
	if co.stage ~= "payment" and #co.pending == 0 and next(co.belt) == nil and co.current then
		enterPayment(co)
	end
end

function Checkouts.scanItem(co, itemId)
	local item = co.belt[itemId]
	if not item then
		return false
	end
	co.belt[itemId] = nil
	co.beltSlots[item.k] = nil
	co.scannedTotal += item.price
	co.scannedCount += 1
	if item.model then
		item.model:PivotTo(co.fixture.anchors.bag)
		task.delay(0.35, function()
			if item.model then
				item.model:Destroy()
			end
		end)
	end
	beep(co)
	placeNextItem(co)
	updateMonitor(co)
	sendState(co)
	checkReady(co)
	return true
end

---------------------------------------------------------------------------
-- Clientes
---------------------------------------------------------------------------
function Checkouts.refreshQueue(co)
	for i, c in co.queue do
		if c.queueIndex ~= i then
			c.queueIndex = i
			c.queueMoved = true
			c.atFront = false
		end
	end
end

function Checkouts.count()
	local n = 0
	for _ in Checkouts.list do
		n += 1
	end
	return n
end

-- La caja abierta con menos fila (prioriza las atendidas); nil si no hay lugar
function Checkouts.choose()
	local best, bestScore
	for _, co in Checkouts.list do
		if co.open and #co.queue < Checkouts.capacity(co) then
			local staffed = co.auto or co.operator ~= nil or co.employee ~= nil
			local score = #co.queue + (staffed and 0 or 4)
			if not best or score < bestScore then
				best, bestScore = co, score
			end
		end
	end
	return best
end

function Checkouts.join(co, c)
	table.insert(co.queue, c)
	c.checkout = co
	c.queueIndex = nil
	Checkouts.refreshQueue(co)
end

---------------------------------------------------------------------------
-- Lugares de la fila: van derecho detrás de la caja y, si chocan con una pared, la vidriera
-- o un mueble, la fila dobla en "S". Nunca queda un lugar afuera del local.
---------------------------------------------------------------------------
local QUEUE_SPACING = 2.8
local layoutVersion = 0
local function bumpLayout()
	layoutVersion += 1
end
Fixtures.onCreated(bumpLayout)
Fixtures.onRemoved(bumpLayout)

local function queueBlockers()
	local list = {}
	for _, name in { "NPCs", "Boxes", "Trash", "Vehicles", "Dropped" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function insideShop(pos)
	local level = Config.levelAt(pos.Y)
	if level > 0 and pos.X >= Config.STAIRWELL.minX - 0.8 and pos.X <= Config.STAIRWELL.maxX and pos.Z <= Config.STAIRWELL.maxZ + 0.8 then
		return false -- la escalera
	end
	for _, zone in Config.Zones do
		if zone.kind == "shop" and (zone.level or 0) == level and (not zone.expansion or State.data.expansions[zone.expansion]) then
			if pos.X >= zone.minX + 0.9 and pos.X <= zone.maxX - 0.9 and pos.Z >= zone.minZ + 0.9 and pos.Z <= zone.maxZ - 0.9 then
				return true
			end
		end
	end
	return false
end

local function inNoBuild(pos)
	if Config.levelAt(pos.Y) == 0 and State.data.expansions.floor1 and pos.X > Config.STAIRWELL.minX - 0.8 and pos.X < Config.STAIRWELL.maxX and pos.Z < Config.STAIRWELL.maxZ + 0.8 then
		return true
	end
	for _, nb in Config.NoBuild do
		if pos.X > nb.minX - 0.8 and pos.X < nb.maxX + 0.8 and pos.Z > nb.minZ - 0.8 and pos.Z < nb.maxZ + 0.8 then
			return true
		end
	end
	return false
end

local function queueSpotOk(from, to, ignore)
	if not insideShop(to) or inNoBuild(to) then
		return false
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	overlap.RespectCanCollide = true
	if #workspace:GetPartBoundsInBox(CFrame.new(to.X, to.Y + 2.4, to.Z), Vector3.new(1.6, 3.6, 1.6), overlap) > 0 then
		return false
	end
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = ignore
	ray.RespectCanCollide = true
	for _, h in { 1.2, 3.2 } do
		local a = Vector3.new(from.X, from.Y + h, from.Z)
		local b = Vector3.new(to.X, to.Y + h, to.Z)
		if workspace:Raycast(a, (b - a).Unit * ((b - a).Magnitude + 0.8), ray) then
			return false
		end
	end
	return true
end

local function computeQueueSpots(co)
	local fixture = co.fixture
	local first = fixture.anchors.queue(1)
	local spots = { first }
	local ignore = queueBlockers()
	local dir = fixture.anchors.queue(2) - first
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	-- Primero intenta doblar hacia el lado contrario al mostrador
	local side = fixture.cframe:VectorToWorldSpace(Vector3.new(-1, 0, 0))
	local pos = first
	while #spots < Config.QUEUE_MAX do
		local nextPos
		local straight = pos + dir * QUEUE_SPACING
		if queueSpotOk(pos, straight, ignore) then
			nextPos = straight
		else
			for _, s in { side, -side } do
				local turned = pos + s * QUEUE_SPACING
				if queueSpotOk(pos, turned, ignore) then
					nextPos = turned
					side = s
					dir = -dir
					break
				end
			end
		end
		if not nextPos then
			break
		end
		table.insert(spots, nextPos)
		pos = nextPos
	end
	return spots
end

local function expansionsKey()
	local list = {}
	for id in State.data.expansions do
		table.insert(list, id)
	end
	table.sort(list)
	return table.concat(list, ",")
end

function Checkouts.queueSpots(co)
	local key = layoutVersion .. "|" .. expansionsKey()
	if co.queueKey ~= key or not co.queueSpotList then
		co.queueKey = key
		co.queueSpotList = computeQueueSpots(co)
		-- Si cambió el armado del local, los que ya estaban en la fila se reacomodan
		for _, c in co.queue do
			c.queueMoved = true
			c.atFront = false
		end
	end
	return co.queueSpotList
end

-- Cuántas personas entran en la fila de esta caja sin salirse del local
function Checkouts.capacity(co)
	return #Checkouts.queueSpots(co)
end

function Checkouts.spot(co, index)
	local spots = Checkouts.queueSpots(co)
	return spots[math.clamp(index or 1, 1, #spots)]
end

local function cancelCurrent(co, message)
	clearVisuals(co)
	co.current = nil
	co.stage = "idle"
	co.pending = {}
	if co.operator then
		Remotes.PaymentClose:FireClient(co.operator)
		if message then
			State.notify(co.operator, message, "warn")
		end
	end
	updateMonitor(co)
	sendState(co)
end

function Checkouts.leave(c)
	local co = c.checkout
	if not co then
		return
	end
	local idx = table.find(co.queue, c)
	if idx then
		table.remove(co.queue, idx)
	end
	if co.current == c then
		cancelCurrent(co, "El cliente se fue de la caja.")
	end
	c.checkout = nil
	c.atFront = false
	Checkouts.refreshQueue(co)
end

local function startCustomer(co, c)
	co.current = c
	co.stage = "scanning"
	co.belt = {}
	co.beltSlots = {}
	co.pending = {}
	co.scannedTotal = 0
	co.scannedCount = 0
	co.itemsTotal = #c.cart
	co.method = c.payCard and "card" or "cash"
	co.given = nil
	co.loadTimer = 0
	co.autoTimer = 1.5
	for _, line in c.cart do
		table.insert(co.pending, { productId = line.productId, price = line.price })
	end
	NPC.say(c.npc, "¡Hola! 👋", 2)
	updateMonitor(co)
	sendState(co)
end

local function complete(co, loss)
	local c = co.current
	if not c then
		return
	end
	local total = co.scannedTotal
	local income = total
	if State.hasPerk("marketing") then
		income = math.floor(total * 1.1 + 0.5)
	end
	income -= loss
	State.addIncome(income)
	State.addStat("sales", co.scannedCount)
	State.addStat("customers", 1)
	if loss > 0 then
		State.addStat("overpaid", loss)
	end
	State.addXP(co.scannedCount)
	State.changeSatisfaction(0.4)

	clearVisuals(co)
	co.current = nil
	co.stage = "idle"
	c.paid = true
	local idx = table.find(co.queue, c)
	if idx then
		table.remove(co.queue, idx)
	end
	c.checkout = nil
	Checkouts.refreshQueue(co)
	if co.operator then
		Remotes.PaymentClose:FireClient(co.operator)
		State.notify(co.operator, "✅ Cobraste " .. fmt(income), "good")
	end
	NPC.say(c.npc, "¡Gracias! 😊", 2)
	updateMonitor(co)
	sendState(co)
end

---------------------------------------------------------------------------
-- Jugador atendiendo
---------------------------------------------------------------------------
local function release(co)
	local player = co.operator
	if not player then
		return
	end
	co.operator = nil
	operatorOf[player] = nil
	if player.Parent then
		player:SetAttribute("AtCheckout", nil)
		Remotes.PaymentClose:FireClient(player)
		Remotes.CheckoutState:FireClient(player, nil)
	end
end

local function assign(co, player)
	co.operator = player
	operatorOf[player] = co
	player:SetAttribute("AtCheckout", co.number)
	sendState(co)
end

function Checkouts.releasePlayer(player)
	local co = operatorOf[player]
	if co then
		release(co)
	end
end

local function employeeAtPost(co)
	local e = co.employee
	return e and e.npc and NPC.alive(e.npc) and flat(e.npc.root.Position, co.fixture.anchors.cashier) < 3
end

-- Checkout sin empleado asignado (para los cajeros)
function Checkouts.freePost()
	for _, co in Checkouts.list do
		if not co.auto and not co.employee then
			return co
		end
	end
	return nil
end

local ringBell -- se define más abajo (timbre)

local function step(dt)
	for _, co in Checkouts.list do
		-- ¿Quién atiende?
		if not co.auto then
			local anchor = co.fixture.anchors.cashier
			if co.operator then
				local root = rootOf(co.operator)
				if not co.operator.Parent or not root or flat(root.Position, anchor) > 3.2 or math.abs(root.Position.Y - anchor.Y) > 7 then
					release(co)
				end
			end
			if not co.operator then
				for _, p in Players:GetPlayers() do
					if not operatorOf[p] then
						local root = rootOf(p)
						if root and flat(root.Position, anchor) <= 2.6 and math.abs(root.Position.Y - anchor.Y) < 7 then
							assign(co, p)
							break
						end
					end
				end
			end
		end

		-- Siguiente cliente
		if not co.current then
			local c = co.queue[1]
			if c and c.atFront and not c.gone then
				startCustomer(co, c)
			end
		end

		if co.current then
			if co.current.gone then
				cancelCurrent(co)
			else
				-- El cliente va poniendo los productos en la cinta
				co.loadTimer -= dt
				if co.loadTimer <= 0 and #co.pending > 0 then
					if placeNextItem(co) then
						co.loadTimer = 0.35
					end
				end
				-- Cobro automático (autocaja o empleado cajero, si no hay un jugador)
				local automatic = co.auto or (not co.operator and employeeAtPost(co))
				if automatic then
					co.autoTimer -= dt
					if co.autoTimer <= 0 then
						if co.stage == "payment" then
							complete(co, 0)
						else
							local _, item = next(co.belt)
							if item then
								Checkouts.scanItem(co, item.id)
							end
							local speed = State.hasPerk("coffee") and 1.2 or 1
							co.autoTimer = co.auto and 1.3 or (Config.EMPLOYEE_SCAN_TIME / speed)
						end
					end
				end
			end
		end

		-- Timbre: caja sin nadie atendiendo y con clientes esperando
		if not co.auto then
			local waiting = #co.queue > 0
			local attended = co.operator ~= nil or employeeAtPost(co)
			if waiting and not attended then
				co.unattended += dt
				if co.unattended >= 5 and os.clock() - co.lastRing >= 12 then
					ringBell(co)
				end
			else
				co.unattended = 0
			end
		end
	end
end

---------------------------------------------------------------------------
-- Alta / baja de cajas (cuando se construyen o venden)
---------------------------------------------------------------------------
local function nextNumber()
	local used = {}
	for _, co in Checkouts.list do
		used[co.number] = true
	end
	local n = 1
	while used[n] do
		n += 1
	end
	return n
end

local function register(fixture)
	local co = {
		id = fixture.id,
		fixture = fixture,
		auto = fixture.type == "self_checkout",
		number = nextNumber(),
		open = true,
		queue = {},
		current = nil,
		belt = {},
		beltSlots = {},
		pending = {},
		stage = "idle",
		scannedTotal = 0,
		scannedCount = 0,
		itemsTotal = 0,
		nextItemId = 0,
		loadTimer = 0,
		autoTimer = 0,
	}
	local sound = Instance.new("Sound")
	sound.SoundId = Config.SOUNDS.beep
	sound.Volume = 0.45
	sound.RollOffMaxDistance = 60
	sound.Parent = fixture.model.PrimaryPart or fixture.model:FindFirstChildWhichIsA("BasePart")
	co.sound = sound
	local bell = Instance.new("Sound")
	bell.SoundId = Config.SOUNDS.bell
	bell.Volume = 0.8
	bell.RollOffMaxDistance = 150
	bell.Parent = fixture.laneLight or sound.Parent
	co.bellSound = bell
	co.unattended = 0
	co.lastRing = 0
	Checkouts.list[fixture.id] = co
	updateLight(co)
end

function Checkouts.toggle(co)
	co.open = not co.open
	updateLight(co)
	sendState(co)
end

---------------------------------------------------------------------------
-- Timbre: si la caja quedó sola con gente esperando, el cliente toca el timbre
---------------------------------------------------------------------------
Checkouts.onBell = nil -- lo define Employees: function(co) llama a un cajero

local function showBellIcon(co)
	local anchor = co.fixture.laneLight
	if not anchor then
		return
	end
	local bb = anchor:FindFirstChild("BellIcon")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "BellIcon"
		bb.Size = UDim2.fromOffset(150, 42)
		bb.StudsOffset = Vector3.new(0, 1.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 150
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(200, 150, 40)
		label.TextColor3 = Color3.fromRGB(25, 25, 25)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = "🔔 ¡ATENCIÓN!"
		label.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		bb.Parent = anchor
	end
	bb.Enabled = true
	task.delay(3.5, function()
		if bb.Parent then
			bb.Enabled = false
		end
	end)
end

ringBell = function(co)
	co.lastRing = os.clock()
	if co.bellSound then
		co.bellSound:Play()
	end
	showBellIcon(co)
	local waiting = #co.queue
	State.notify(nil, string.format("🔔 ¡Tocaron el timbre en la caja %d! Hay %d cliente(s) esperando para pagar.", co.number, waiting), "warn")
	if Checkouts.onBell then
		Checkouts.onBell(co)
	end
end

function Checkouts.init()
	Fixtures.onCreated(function(fixture)
		if fixture.type == "checkout" or fixture.type == "self_checkout" then
			register(fixture)
		end
	end)
	Fixtures.onRemoved(function(fixture)
		local co = Checkouts.list[fixture.id]
		if co then
			release(co)
			if co.employee then
				co.employee.post = nil
			end
			clearVisuals(co)
			Checkouts.list[fixture.id] = nil
		end
	end)
	table.insert(Fixtures.removeGuards, function(fixture)
		local co = Checkouts.list[fixture.id]
		if co and (#co.queue > 0 or co.current) then
			return false, "Hay clientes en esta caja. Esperá a que se vayan."
		end
		return true
	end)

	Remotes.Action.OnServerEvent:Connect(function(player, kind, a, b)
		local co = type(a) == "string" and Checkouts.list[a]
		if not co then
			return
		end
		-- Abrir / cerrar la caja: cualquiera que esté cerca (click en el poste) o el cajero (botón del panel)
		if kind == "togglecheckout" then
			local root = rootOf(player)
			if co.operator == player or (root and flat(root.Position, co.fixture.anchors.counter) < 14) then
				Checkouts.toggle(co)
			end
			return
		end
		if co.operator ~= player then
			return
		end
		if kind == "scan" and type(b) == "number" then
			if co.stage ~= "payment" then
				Checkouts.scanItem(co, b)
			end
		elseif kind == "pay" then
			if co.stage == "payment" and co.current then
				Remotes.PaymentOpen:FireClient(player, {
					checkoutId = co.id,
					method = co.method,
					total = co.scannedTotal,
					given = co.given,
				})
			end
		end
	end)

	Remotes.ConfirmPayment.OnServerInvoke = function(player, checkoutId, amount)
		local co = type(checkoutId) == "string" and Checkouts.list[checkoutId]
		if not co or co.operator ~= player or co.stage ~= "payment" or not co.current then
			return false, "No hay nada para cobrar."
		end
		if type(amount) ~= "number" or amount ~= amount then
			return false, "Monto inválido."
		end
		amount = math.floor(amount + 0.5)
		if co.method == "card" then
			if amount ~= co.scannedTotal then
				return false, "El monto no coincide con el total (" .. fmt(co.scannedTotal) .. ")."
			end
			complete(co, 0)
			return true
		end
		local expected = co.given - co.scannedTotal
		if amount < expected then
			return false, "Te falta dar vuelto: el cambio es " .. fmt(expected) .. "."
		end
		local loss = amount - expected
		complete(co, loss)
		if loss > 0 then
			return true, "Diste " .. fmt(loss) .. " de más."
		end
		return true
	end

	Players.PlayerRemoving:Connect(Checkouts.releasePlayer)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.2)
			local now = os.clock()
			step(now - last)
			last = now
		end
	end)
end

return Checkouts
