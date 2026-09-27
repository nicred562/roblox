-- Empleados: se contratan en la pizarra de empleados y se les asigna un puesto:
-- Cajero, Repositor (llena estanterías), Depósito (guarda cajas) o Seguridad (atrapa ladrones).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local NPC = require(script.Parent.NPC)
local Fixtures = require(script.Parent.Fixtures)
local Boxes = require(script.Parent.Boxes)
local Checkouts = require(script.Parent.Checkouts)
local Customers = require(script.Parent.Customers)
local Loans = require(script.Parent.Loans)

local Employees = {}
Employees.hired = {} -- lista de empleados
Employees.candidates = {}
local refs
local nextId = 0

local ROLE_NAMES = {}
for _, role in Config.ROLES do
	ROLE_NAMES[role.id] = role.name
end

local UNIFORM = { shirt = Color3.fromRGB(40, 130, 70), pants = Color3.fromRGB(40, 45, 55) }

local function speedMult()
	return State.hasPerk("coffee") and 1.2 or 1
end

function Employees.publicList()
	local list = {}
	for _, e in Employees.hired do
		table.insert(list, { id = e.id, name = e.name, role = e.role })
	end
	return list
end

function Employees.refreshCandidates()
	Employees.candidates = {}
	local used = {}
	for _, e in Employees.hired do
		used[e.name] = true
	end
	for _ = 1, 3 do
		local name
		for _ = 1, 20 do
			name = Config.EMPLOYEE_NAMES[math.random(#Config.EMPLOYEE_NAMES)]
			if not used[name] then
				break
			end
		end
		used[name] = true
		nextId += 1
		table.insert(Employees.candidates, { id = "C" .. nextId, name = name })
	end
end

function Employees.dailyWages()
	return #Employees.hired * Config.EMPLOYEE_WAGE
end

local function releaseResources(e)
	if e.post then
		if e.post.employee == e then
			e.post.employee = nil
		end
		e.post = nil
	end
	if e.box and e.box.Parent then
		if e.box:FindFirstChild("CarryWeld") then
			Boxes.detach(e.box, CFrame.new(Boxes.groundPosition(e.npc.root.Position + e.npc.root.CFrame.LookVector * 2, { e.box })))
		end
		e.box:SetAttribute("ClaimedBy", nil)
	end
	e.box = nil
end

local function claim(e, box)
	box:SetAttribute("ClaimedBy", e.id)
	local prompt = box:FindFirstChild("Prompt")
	if prompt then
		prompt.Enabled = false
	end
	e.box = box
end

-- Caja libre para un empleado (las cajas de muebles las arman los jugadores)
local function isFree(box)
	return box.Parent
		and box:GetAttribute("Kind") ~= "crate"
		and not box:GetAttribute("CarrierId")
		and not box:GetAttribute("ClaimedBy")
end

local function walk(e, target, timeout)
	e.npc.humanoid.WalkSpeed = 13 * speedMult()
	return NPC.walkTo(e.npc, target, timeout or 30)
end

-- Lleva la caja que tiene el empleado a un lugar libre del depósito (o la deja en el piso)
local function putAway(e)
	local box = e.box
	if not box or not box.Parent then
		return
	end
	if (box:GetAttribute("Units") or 0) <= 0 then
		walk(e, refs.points.recycleInside, 40)
		if box.Parent then
			Boxes.recycleBox(box)
		end
		e.box = nil
		return
	end
	local fixture, index = Fixtures.freeStorageSlot(e.npc.root.Position)
	if fixture then
		local standAt = Fixtures.standPoint(fixture, index, true)
		walk(e, standAt, 40)
		if Fixtures.list[fixture.id] and not (fixture.storage[index].box and fixture.storage[index].box.Parent) then
			Boxes.storeBox(box, fixture, index)
			box:SetAttribute("ClaimedBy", nil)
			e.box = nil
			return
		end
	end
	releaseResources(e)
end

local function pickUpBox(e, box)
	local fixtureId = box:GetAttribute("StorageFixture")
	local fixture = fixtureId and Fixtures.list[fixtureId]
	local target = fixture and Fixtures.standPoint(fixture, box:GetAttribute("StorageSlot"), true) or box.Position
	walk(e, target, 40)
	if not box.Parent or box:GetAttribute("CarrierId") or NPC.flatDistance(e.npc.root.Position, box.Position) > 7 then
		return false
	end
	if box:GetAttribute("StorageFixture") then
		Fixtures.clearStorageBox(box)
	end
	Boxes.attach(box, e.npc.root)
	return true
end

---------------------------------------------------------------------------
-- Puestos
---------------------------------------------------------------------------
local TASKS = {}

TASKS.cashier = function(e)
	local co = e.post
	if co and not Checkouts.list[co.id] then
		co = nil
		e.post = nil
	end
	if not co then
		co = Checkouts.freePost()
		if co then
			co.employee = e
			e.post = co
		end
	end
	if not co then
		task.wait(2)
		return
	end
	local anchor = co.fixture.anchors.cashier
	if NPC.flatDistance(e.npc.root.Position, anchor) > 2.5 then
		walk(e, anchor, 40)
	end
	NPC.face(e.npc, co.fixture.anchors.counter)
	task.wait(1)
end

local function findSourceBox(productId)
	for _, stored in Fixtures.storedBoxes() do
		local box = stored.box
		if isFree(box) and box:GetAttribute("ProductId") == productId and (box:GetAttribute("Units") or 0) > 0 then
			return box
		end
	end
	for box in Boxes.all do
		if isFree(box) and not box:GetAttribute("StorageFixture") and box:GetAttribute("ProductId") == productId and (box:GetAttribute("Units") or 0) > 0 then
			return box
		end
	end
	return nil
end

TASKS.restock = function(e)
	-- Busca el nivel más vacío que tenga caja disponible de su producto
	local jobs = {}
	for _, s in Fixtures.allProductSlots() do
		local slot = s.slot
		if slot.productId then
			local cap = Fixtures.capacity(s.fixture, s.index, slot.productId)
			if cap > 0 and slot.stock < cap * 0.6 then
				table.insert(jobs, { fixture = s.fixture, index = s.index, productId = slot.productId, ratio = slot.stock / cap })
			end
		end
	end
	table.sort(jobs, function(a, b)
		return a.ratio < b.ratio
	end)
	for _, job in jobs do
		local box = findSourceBox(job.productId)
		if box then
			claim(e, box)
			if not pickUpBox(e, box) then
				releaseResources(e)
				return
			end
			local standAt, faceAt = Fixtures.standPoint(job.fixture, job.index)
			walk(e, standAt, 40)
			NPC.face(e.npc, faceAt)
			while box.Parent and Fixtures.list[job.fixture.id] and (box:GetAttribute("Units") or 0) > 0 do
				if not Fixtures.addUnit(job.fixture, job.index, job.productId) then
					break
				end
				local units = box:GetAttribute("Units") - 1
				box:SetAttribute("Units", units)
				if units <= 0 then
					box:SetAttribute("ProductId", "")
				end
				Boxes.updateText(box)
				task.wait(0.22 / speedMult())
			end
			putAway(e)
			return
		end
	end
	task.wait(2)
end

TASKS.storage = function(e)
	for box in Boxes.all do
		if isFree(box) and not box:GetAttribute("StorageFixture") then
			local isEmpty = (box:GetAttribute("Units") or 0) <= 0
			if isEmpty or Fixtures.freeStorageSlot(box.Position) then
				claim(e, box)
				if pickUpBox(e, box) then
					putAway(e)
				else
					releaseResources(e)
				end
				return
			end
		end
	end
	task.wait(2)
end

TASKS.security = function(e)
	local targets = {}
	for _, c in Customers.activeThieves() do
		table.insert(targets, { model = c.npc.model, root = c.npc.root, isCollector = false })
	end
	for _, col in Loans.activeCollectors() do
		table.insert(targets, { model = col.npc.model, root = col.npc.root, isCollector = true })
	end
	local best, bestDist
	for _, t in targets do
		local d = (t.root.Position - e.npc.root.Position).Magnitude
		if not best or d < bestDist then
			best, bestDist = t, d
		end
	end
	if not best then
		if NPC.flatDistance(e.npc.root.Position, refs.points.securityPost) > 3 then
			walk(e, refs.points.securityPost, 30)
		end
		task.wait(1.5)
		return
	end
	e.npc.humanoid.WalkSpeed = 20 * speedMult()
	if bestDist > 5 then
		NPC.walkTo(e.npc, best.root.Position, 1.2)
	else
		NPC.face(e.npc, best.root.Position)
		NPC.say(e.npc, "¡Alto ahí!", 1)
		if best.isCollector then
			Loans.hitCollector(best.model, e.npc.root.Position, nil)
		else
			Customers.hitNPC(best.model, e.npc.root.Position, e.name .. " (seguridad)")
		end
		task.wait(0.9)
	end
end

local function run(e)
	NPC.say(e.npc, "¡Hola! Soy " .. e.name .. " 👋", 3)
	while e.active and NPC.alive(e.npc) do
		local fn = TASKS[e.role]
		local ok, err = pcall(fn, e)
		if not ok then
			warn("[Supermercado] Error de empleado:", err)
			releaseResources(e)
			task.wait(2)
		end
		task.wait(0.3)
	end
end

local function spawnEmployee(name, role)
	nextId += 1
	local e = { id = "E" .. nextId, name = name, role = role or "restock", active = true }
	table.insert(Employees.hired, e)
	task.spawn(function()
		e.npc = NPC.create(name, {
			uniform = UNIFORM,
			randomAvatar = true,
			displayName = name .. " · " .. ROLE_NAMES[e.role],
			walkSpeed = 13,
		})
		NPC.spawn(e.npc, refs.points.staff)
		if not e.active then
			e.npc.model:Destroy()
			return
		end
		run(e)
	end)
	return e
end

local function findEmployee(id)
	for i, e in Employees.hired do
		if e.id == id then
			return e, i
		end
	end
	return nil
end

function Employees.restore(list)
	for _, data in list or {} do
		if type(data) == "table" and type(data.name) == "string" and ROLE_NAMES[data.role] then
			spawnEmployee(data.name, data.role)
		end
	end
end

function Employees.newDay()
	Employees.refreshCandidates()
	State.broadcastSnapshot()
end

function Employees.init(builderRefs)
	refs = builderRefs
	Employees.refreshCandidates()

	-- Cuando un cliente toca el timbre, va un cajero libre (o uno de una caja sin gente)
	Checkouts.onBell = function(co)
		if co.employee and co.employee.active then
			return
		end
		for _, e in Employees.hired do
			if e.active and e.role == "cashier" and e.npc then
				local post = e.post
				if post ~= co and (not post or (#post.queue == 0 and not post.current)) then
					if post then
						post.employee = nil
					end
					co.employee = e
					e.post = co
					NPC.say(e.npc, "¡Ya voy a la caja " .. co.number .. "! 🏃", 2.5)
					return
				end
			end
		end
	end
	State.snapshotProviders.employees = function()
		return {
			employees = Employees.publicList(),
			candidates = Employees.candidates,
			hireLimit = State.hireLimit(),
		}
	end

	Remotes.HireEmployee.OnServerInvoke = function(player, candidateId)
		if #Employees.hired >= State.hireLimit() then
			return false, State.hireLimit() == 0 and "Primero desbloqueá \"Empleados I\" en la pizarra de franquicia." or "Llegaste al límite de empleados."
		end
		for i, candidate in Employees.candidates do
			if candidate.id == candidateId then
				table.remove(Employees.candidates, i)
				spawnEmployee(candidate.name, "restock")
				State.broadcastSnapshot()
				State.notify(nil, "👷 " .. player.DisplayName .. " contrató a " .. candidate.name .. ".", "good")
				return true, candidate.name .. " empieza como repositor. Cambiale el puesto cuando quieras."
			end
		end
		return false, "Ese candidato ya no está disponible."
	end

	Remotes.FireEmployee.OnServerInvoke = function(_player, id)
		local e, index = findEmployee(id)
		if not e then
			return false, "Ese empleado no existe."
		end
		e.active = false
		releaseResources(e)
		if e.npc and e.npc.model then
			e.npc.model:Destroy()
		end
		table.remove(Employees.hired, index)
		State.broadcastSnapshot()
		return true, e.name .. " fue despedido."
	end

	Remotes.SetEmployeeRole.OnServerInvoke = function(_player, id, role)
		local e = findEmployee(id)
		if not e or type(role) ~= "string" or not ROLE_NAMES[role] then
			return false, "Datos inválidos."
		end
		if role == "security" and not State.hasPerk("security") then
			return false, "Necesitás \"Formación en seguridad\" en la pizarra de franquicia."
		end
		releaseResources(e)
		e.role = role
		if e.npc then
			e.npc.humanoid.DisplayName = e.name .. " · " .. ROLE_NAMES[role]
		end
		State.broadcastSnapshot()
		return true, e.name .. " ahora trabaja de " .. ROLE_NAMES[role] .. "."
	end
end

return Employees
