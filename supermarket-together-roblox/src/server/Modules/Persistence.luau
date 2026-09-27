-- Guardado con DataStore: cada sala tiene su propio supermercado guardado.
-- En Studio: Game Settings > Security > "Enable Studio Access to API Services" para probarlo.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent.State)
local Fixtures = require(script.Parent.Fixtures)
local Boxes = require(script.Parent.Boxes)
local Employees = require(script.Parent.Employees)
local StoreBuilder = require(script.Parent.StoreBuilder)

local Persistence = {}
local store
local key

pcall(function()
	store = DataStoreService:GetDataStore("SMT_Saves_v1")
end)

function Persistence.setKey(saveKey)
	key = saveKey
end

function Persistence.load()
	if not store or not key then
		return nil
	end
	local ok, data = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn("[Supermercado] No se pudo cargar la partida:", data)
		return nil
	end
	return data
end

local function serialize()
	local d = State.data
	local fixtures = {}
	for id, f in Fixtures.list do
		local entry = { id = id, t = f.type, x = f.x, z = f.z, r = f.rot, l = f.level or 0, s = {}, b = {} }
		for i, slot in f.slots do
			if slot.productId then
				table.insert(entry.s, { i = i, p = slot.productId, n = slot.stock })
			end
		end
		for i, s in f.storage do
			local box = s.box
			if box and box.Parent then
				table.insert(entry.b, { i = i, p = box:GetAttribute("ProductId") or "", n = box:GetAttribute("Units") or 0 })
			end
		end
		table.insert(fixtures, entry)
	end
	local loose = {}
	for box in Boxes.all do
		if box.Parent and not box:GetAttribute("StorageFixture") and #loose < Config.MAX_BOXES then
			local pos = box:GetAttribute("CarrierId") and StoreBuilder.deliveryRect and Vector3.new(-39, 1, 38) or box.Position
			table.insert(loose, { p = box:GetAttribute("ProductId") or "", n = box:GetAttribute("Units") or 0, x = pos.X, z = pos.Z, f = box:GetAttribute("FixtureType") })
		end
	end
	local employees = {}
	for _, e in Employees.hired do
		table.insert(employees, { name = e.name, role = e.role })
	end
	return {
		v = 2,
		money = d.money,
		day = d.day,
		xp = d.xp,
		level = d.level,
		fp = d.fp,
		satisfaction = d.satisfaction,
		perks = d.perks,
		expansions = d.expansions,
		prices = d.prices,
		marketPrices = d.marketPrices,
		loan = d.loan,
		bank = d.bank,
		rival = d.rival,
		custom = d.custom,
		fixtures = fixtures,
		loose = loose,
		employees = employees,
	}
end

function Persistence.save()
	if not store or not key or not State.ready then
		return
	end
	local data = serialize()
	local ok, err = pcall(function()
		store:SetAsync(key, data)
	end)
	if not ok then
		warn("[Supermercado] No se pudo guardar:", err)
	end
end

local function validProduct(id)
	return type(id) == "string" and Config.ProductsById[id] ~= nil
end

function Persistence.apply(data, Upgrades)
	if type(data) ~= "table" or data.v ~= 2 then
		return false
	end
	local d = State.data
	for _, field in { "money", "day", "xp", "level", "fp", "satisfaction", "bank" } do
		if type(data[field]) == "number" then
			d[field] = data[field]
		end
	end
	for _, field in { "perks", "expansions" } do
		if type(data[field]) == "table" then
			for id, value in data[field] do
				if value == true then
					d[field][id] = true
				end
			end
		end
	end
	for _, field in { "prices", "marketPrices" } do
		if type(data[field]) == "table" then
			for id, value in data[field] do
				if validProduct(id) and type(value) == "number" then
					d[field][id] = value
				end
			end
		end
	end
	if type(data.loan) == "table" and type(data.loan.remaining) == "number" then
		d.loan = data.loan
	end
	if type(data.rival) == "table" then
		d.rival = data.rival
	end
	if type(data.custom) == "table" then
		for k, v in data.custom do
			d.custom[k] = v
		end
	end

	Upgrades.applyExpansions()
	StoreBuilder.applyCustom(d.custom)

	for _, entry in data.fixtures or {} do
		if type(entry) == "table" and Config.Fixtures[entry.t] then
			local ok, fixture = pcall(Fixtures.create, entry.t, entry.x, entry.z, entry.r or 0, entry.id, entry.l or 0)
			if ok and fixture then
				for _, s in entry.s or {} do
					if validProduct(s.p) then
						Fixtures.fillSlot(fixture, s.i, s.p, s.n or 0)
					end
				end
				for _, b in entry.b or {} do
					if fixture.storage[b.i] then
						local box = Boxes.create(validProduct(b.p) and b.p or "", b.n or 0, fixture.storage[b.i].cf)
						Fixtures.setStorageBox(fixture, b.i, box)
					end
				end
			else
				warn("[Supermercado] No se pudo restaurar un mueble:", fixture)
			end
		end
	end
	for _, b in data.loose or {} do
		if type(b.x) == "number" and type(b.z) == "number" then
			if type(b.f) == "string" and Config.Fixtures[b.f] then
				local pos = Boxes.groundPosition(Vector3.new(b.x, Config.FLOOR_Y, b.z), nil, Config.CRATE_SIZE.Y)
				Boxes.createCrate(b.f, CFrame.new(pos))
			else
				local pos = Boxes.groundPosition(Vector3.new(b.x, Config.FLOOR_Y, b.z))
				Boxes.create(validProduct(b.p) and b.p or "", b.n or 0, CFrame.new(pos))
			end
		end
	end
	Employees.restore(data.employees)
	return true
end

return Persistence
