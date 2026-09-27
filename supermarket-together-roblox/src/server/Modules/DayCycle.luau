-- Ciclo del día como el original: botón verde abre a las 08:00, a las 22:30 dejan de entrar
-- clientes y con el botón rojo cerrás: se pagan las facturas y aparece el reporte del día.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Fixtures = require(script.Parent.Fixtures)
local Customers = require(script.Parent.Customers)
local Trash = require(script.Parent.Trash)
local Employees = require(script.Parent.Employees)
local Loans = require(script.Parent.Loans)
local Persistence = require(script.Parent.Persistence)
local Interact = require(script.Parent.Interact)
local Bank = require(script.Parent.Bank)
local Delivery = require(script.Parent.Delivery)

local DayCycle = {}
local refs
local isNight

local SIGN_HINTS = {
	Cerrado = "Click: ABRIR el supermercado",
	Abierto = "Abierto hasta las 22:30 · después podés cerrar acá",
	Cierre = "Click: CERRAR el supermercado y terminar el día",
}

local function updateButtons()
	refs.openButton.Enabled = State.phase == "Cerrado"
	refs.closeButton.Enabled = State.phase ~= "Cerrado"
	-- Cartel de la entrada
	StoreBuilder.setOpenSign(State.phase)
	Interact.setHint(StoreBuilder.openSign, SIGN_HINTS[State.phase])
end

local function spawnInterval()
	local d = State.data
	local mult = 1 + 0.1 * (d.level - 1)
	if State.hasPerk("wifi") then
		mult *= 1.15
	end
	if State.hasPerk("aircon") then
		mult *= 1.15
	end
	mult *= 0.6 + d.satisfaction / 100 * 0.8
	mult *= Config.demandMultiplier(State.clock, ((d.day - 1) % 7) + 1)
	return math.max(Config.CUSTOMER_MIN_INTERVAL, Config.CUSTOMER_BASE_INTERVAL / mult) * (0.7 + math.random() * 0.6)
end

local function setLighting(clock)
	Lighting.ClockTime = clock % 24
	local night = clock >= 19.5 or clock < 6.5
	if night ~= isNight then
		isNight = night
		StoreBuilder.setNight(night)
	end
end

function DayCycle.open(player)
	if State.phase ~= "Cerrado" then
		return
	end
	if not State.ready then
		State.notify(player, "Cargando la partida, esperá un segundo...", "warn")
		return
	end
	State.resetStats()
	State.clock = Config.OPEN_HOUR
	State.setPhase("Abierto")
	Loans.newDay()
	updateButtons()
	local weekday = Config.weekdayName(State.data.day)
	State.notify(nil, "🏪 " .. player.DisplayName .. " abrió el supermercado. ¡" .. weekday .. ", día " .. State.data.day .. "!", "good")
	if ((State.data.day - 1) % 7) + 1 == Config.INFLATION_WEEKDAY then
		State.applyInflation()
		State.notify(nil, "📈 Es jueves: subieron los precios de mercado. Revisá tus precios con la pistola.", "warn")
	end
end

function DayCycle.endDay()
	local rent = Config.RENT_BASE
	for _ in State.data.expansions do
		rent += Config.RENT_PER_EXPANSION
	end
	local electricity = Config.ELECTRICITY_PER_FIXTURE * Fixtures.countNonDecor()
	local wages = Employees.dailyWages()
	State.forceSpend(rent + electricity + wages)
	local loanInfo = Loans.endOfDay()
	-- Si no alcanzó el efectivo, se debita del banco; después se cobra el interés del día
	Bank.autoDebit()
	local bankInterest = Bank.endOfDay()

	local s = State.stats
	local d = State.data
	Remotes.DaySummary:FireAllClients({
		day = d.day,
		weekday = Config.weekdayName(d.day),
		income = s.income,
		sales = s.sales,
		customers = s.customers,
		complaints = s.complaints,
		thefts = s.thefts,
		caught = s.caught,
		recovered = s.recovered,
		recycled = s.recycled,
		overpaid = s.overpaid,
		shipping = s.shipping or 0,
		bank = d.bank or 0,
		bankInterest = bankInterest,
		arcade = s.arcade or 0,
		rent = rent,
		electricity = electricity,
		wages = wages,
		loan = loanInfo,
		money = d.money,
		level = d.level,
		xp = d.xp,
		xpNext = Config.xpForLevel(d.level),
		satisfaction = math.floor(d.satisfaction + 0.5),
	})

	d.day += 1
	State.clock = Config.PREP_HOUR
	State.setPhase("Cerrado")
	updateButtons()
	Employees.newDay()
	Persistence.save()
end

function DayCycle.close(player)
	if State.phase == "Cerrado" then
		return
	end
	if State.phase == "Abierto" then
		State.notify(player, "No podés cerrar antes de las 22:30.", "warn")
		return
	end
	State.notify(nil, "🔒 " .. player.DisplayName .. " cerró el supermercado.", "info")
	Customers.forceLeaveAll()
	Delivery.closeDay()
	DayCycle.endDay()
end

local function loop()
	local spawnTimer, trashTimer = 3, 30
	local last = os.clock()
	while true do
		task.wait(0.2)
		local now = os.clock()
		local dt = now - last
		last = now

		if State.phase == "Cerrado" then
			setLighting(Config.PREP_HOUR)
		else
			State.setClock(math.min(State.clock + dt / Config.SECONDS_PER_GAME_HOUR, 26))
			setLighting(State.clock)
			Trash.step(dt)
		end

		if State.phase == "Abierto" then
			spawnTimer -= dt
			if spawnTimer <= 0 then
				if Customers.count() < Customers.maxCustomers() then
					Customers.spawn()
				end
				spawnTimer = spawnInterval()
			end
			trashTimer -= dt
			if trashTimer <= 0 then
				Trash.spawnRandom()
				trashTimer = math.random(25, 45)
			end
			Loans.tick(State.clock)
			if State.clock >= Config.LAST_ENTRY_HOUR then
				State.setPhase("Cierre")
				updateButtons()
				State.notify(nil, "🌙 Son las 22:30: ya no entran clientes. Cuando terminen, cerrá con el botón rojo de la oficina.", "warn")
			end
		end
	end
end

function DayCycle.init(builderRefs)
	refs = builderRefs
	refs.openButton.Triggered:Connect(DayCycle.open)
	refs.closeButton.Triggered:Connect(DayCycle.close)
	-- Cartel de ABIERTO/CERRADO de la entrada: un click abre o cierra (se controla ahí mismo)
	if StoreBuilder.openSign then
		Interact.mark(StoreBuilder.openSign, "storesign", SIGN_HINTS.Cerrado)
		Interact.register("storesign", function(player)
			if State.phase == "Cerrado" then
				DayCycle.open(player)
			elseif State.phase == "Cierre" then
				DayCycle.close(player)
			else
				local left = math.max(0, Config.LAST_ENTRY_HOUR - State.clock)
				State.notify(player, string.format("🕙 Está abierto. Podés cerrar desde las 22:30 (faltan %s h).", Config.formatClock(left)), "info")
			end
		end)
	end
	updateButtons()
	task.spawn(loop)
end

return DayCycle
