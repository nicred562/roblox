-- Estado global de la tienda: dinero, día, nivel, puntos de franquicia, precios, mejoras, préstamo...
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local State = {}

State.ready = false -- true cuando ya se cargó (o no) la partida guardada
State.phase = "Cerrado" -- "Cerrado" | "Abierto" | "Cierre"
State.clock = Config.PREP_HOUR -- horas (8.5 = 08:30)
State.room = { id = nil, name = "", ownerId = 0, ownerName = "" }
State.data = {
	money = Config.STARTING_MONEY,
	day = 1,
	xp = 0,
	level = 1,
	fp = 0,
	satisfaction = Config.START_SATISFACTION,
	perks = {},
	expansions = {},
	prices = {},
	marketPrices = {},
	loan = nil, -- { id, remaining, perDay, overdue, missed }
	bank = 0, -- plata guardada en el banco Tesoro Digital (no la pueden robar)
	rival = nil, -- estado de la competencia CARREFIVE
	custom = { floor = 1, walls = 1, signColor = 1, storeName = Config.DEFAULT_STORE_NAME },
}
State.snapshotProviders = {} -- funciones que agregan datos al snapshot (empleados, etc.)

local status = ReplicatedStorage:FindFirstChild("StoreStatus")
if not status then
	status = Instance.new("Configuration")
	status.Name = "StoreStatus"
	status.Parent = ReplicatedStorage
end
State.status = status

function State.resetStats()
	State.stats = {
		income = 0,
		sales = 0,
		customers = 0,
		complaints = 0,
		thefts = 0,
		caught = 0,
		recovered = 0,
		recycled = 0,
		orders = 0,
		overpaid = 0,
		shipping = 0,
	}
end
State.resetStats()

function State.publish()
	local d = State.data
	status:SetAttribute("Money", d.money)
	status:SetAttribute("Bank", d.bank or 0)
	status:SetAttribute("Day", d.day)
	status:SetAttribute("Weekday", Config.weekdayName(d.day))
	status:SetAttribute("Clock", math.floor(State.clock * 60))
	status:SetAttribute("Phase", State.phase)
	status:SetAttribute("Level", d.level)
	status:SetAttribute("XP", d.xp)
	status:SetAttribute("XPNext", Config.xpForLevel(d.level))
	status:SetAttribute("FP", d.fp)
	status:SetAttribute("Satisfaction", math.floor(d.satisfaction + 0.5))
	status:SetAttribute("Debt", d.loan and d.loan.remaining or 0)
	status:SetAttribute("Overdue", d.loan and d.loan.overdue or 0)
	status:SetAttribute("StoreName", d.custom.storeName)
	status:SetAttribute("RoomName", State.room.name)
	status:SetAttribute("OwnerId", State.room.ownerId)
end

function State.notify(target, text, kind)
	if target then
		Remotes.Notify:FireClient(target, text, kind or "info")
	else
		Remotes.Notify:FireAllClients(text, kind or "info")
	end
end

function State.isOwner(player)
	-- Si la sala no tiene dueño verificado (ownerId 0), nadie tiene permisos de dueño
	return State.room.ownerId ~= 0 and player.UserId == State.room.ownerId
end

---------------------------------------------------------------------------
-- Productos y precios
---------------------------------------------------------------------------
function State.getMarket(productId)
	local prod = Config.ProductsById[productId]
	return State.data.marketPrices[productId] or (prod and prod.market) or 0
end

function State.getPrice(productId)
	return State.data.prices[productId] or math.floor(State.getMarket(productId) * 1.5 + 0.5)
end

function State.setPrice(productId, cents)
	State.data.prices[productId] = cents
	State.broadcastSnapshot()
end

function State.hasPerk(id)
	return State.data.perks[id] == true
end

function State.hasExpansion(id)
	return State.data.expansions[id] == true
end

function State.isCategoryUnlocked(category)
	return category == "basic1" or State.hasPerk(category)
end

function State.isProductUnlocked(productId)
	local prod = Config.ProductsById[productId]
	return prod ~= nil and State.isCategoryUnlocked(prod.category)
end

function State.unlockedProducts()
	local list = {}
	for _, prod in Config.Products do
		if State.isCategoryUnlocked(prod.category) then
			table.insert(list, prod)
		end
	end
	return list
end

function State.hireLimit()
	if State.hasPerk("employees3") then
		return 6
	elseif State.hasPerk("employees2") then
		return 4
	elseif State.hasPerk("employees1") then
		return 2
	end
	return 0
end

-- Inflación de los jueves: suben los precios de mercado
function State.applyInflation()
	for _, prod in Config.Products do
		local pct = math.random(Config.INFLATION_MIN, Config.INFLATION_MAX)
		State.data.marketPrices[prod.id] = math.floor(State.getMarket(prod.id) * (1 + pct / 100) + 0.5)
	end
	State.broadcastSnapshot()
end

function State.snapshot()
	local prices, market = {}, {}
	for _, prod in Config.Products do
		prices[prod.id] = State.getPrice(prod.id)
		market[prod.id] = State.getMarket(prod.id)
	end
	local snap = {
		prices = prices,
		market = market,
		perks = State.data.perks,
		expansions = State.data.expansions,
		level = State.data.level,
		custom = State.data.custom,
		loan = State.data.loan,
		room = { name = State.room.name, ownerId = State.room.ownerId, ownerName = State.room.ownerName },
	}
	for _, provider in State.snapshotProviders do
		for key, value in provider() do
			snap[key] = value
		end
	end
	return snap
end

function State.broadcastSnapshot()
	Remotes.Snapshot:FireAllClients(State.snapshot())
end

---------------------------------------------------------------------------
-- Dinero, experiencia y satisfacción
---------------------------------------------------------------------------
function State.addIncome(cents)
	State.data.money += cents
	State.stats.income += cents
	State.publish()
end

function State.trySpend(cents)
	if State.data.money < cents then
		return false
	end
	State.data.money -= cents
	State.publish()
	return true
end

-- Gastos obligatorios (facturas): pueden dejar el dinero en negativo
function State.forceSpend(cents)
	State.data.money -= cents
	State.publish()
end

function State.addXP(amount)
	local d = State.data
	d.xp += amount
	while d.xp >= Config.xpForLevel(d.level) do
		d.xp -= Config.xpForLevel(d.level)
		d.level += 1
		d.fp += 1
		State.notify(nil, "⭐ ¡El supermercado subió a nivel " .. d.level .. "! +1 punto de franquicia.", "good")
	end
	State.publish()
end

function State.changeSatisfaction(delta)
	State.data.satisfaction = math.clamp(State.data.satisfaction + delta, 0, 100)
	State.publish()
end

function State.addStat(key, n)
	State.stats[key] = (State.stats[key] or 0) + (n or 1)
end

function State.setPhase(phase)
	State.phase = phase
	State.publish()
end

function State.setClock(hours)
	State.clock = hours
	State.publish()
end

State.publish()

return State
