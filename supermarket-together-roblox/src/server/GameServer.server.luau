-- Script principal del servidor.
-- Si es un servidor normal -> LOBBY (menú principal con salas).
-- Si es un servidor reservado (una sala) -> SUPERMERCADO.
-- En Studio: arranca en el lobby y, al crear una sala, el supermercado se carga en el mismo servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[Supermercado] Iniciando servidor...")
ReplicatedStorage:SetAttribute("Mode", "loading")

local function findChild(parent, name)
	local child = parent:WaitForChild(name, 10)
	if not child then
		error("[Supermercado] No encuentro '" .. name .. "' dentro de " .. parent:GetFullName() .. " (revisá mayúsculas)")
	end
	return child
end

-- Una función que cada módulo DEBE tener; si falta, el módulo está vacío o tiene otro archivo pegado
local EXPECTED = {
	Config = "formatMoney", Remotes = "Notify", State = "publish", StoreBuilder = "build", Products = "build",
	NPC = "create", Fixtures = "create", Boxes = "create", Checkouts = "choose", Trash = "spawnAt",
	Customers = "spawn", Vehicles = "enqueueDelivery", Loans = "tick", Tools = "init", Employees = "restore", Upgrades = "init",
	Office = "init", Rooms = "initLobby", Persistence = "save", DayCycle = "open", Interact = "register", Bank = "npcWithdraw", Delivery = "closeDay",
}
local problems = {}

local function load(parent, name)
	local module = findChild(parent, name)
	if not module:IsA("ModuleScript") then
		table.insert(problems, name .. ": tiene que ser un ModuleScript y es un " .. module.ClassName)
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		table.insert(problems, name .. ": error al cargar → " .. tostring(result))
		return nil
	end
	local key = EXPECTED[name]
	if type(result) ~= "table" or (key and result[key] == nil) then
		table.insert(problems, name .. ": no tiene el código correcto (¿quedó la plantilla vacía o pegaste otro archivo?)")
		return nil
	end
	return result
end

local Shared = findChild(ReplicatedStorage, "Shared")
local Config = load(Shared, "Config")
load(Shared, "Remotes")

local Modules = findChild(script.Parent, "Modules")
local State = load(Modules, "State")
local Interact = load(Modules, "Interact")
local StoreBuilder = load(Modules, "StoreBuilder")
load(Modules, "Products")
local NPC = load(Modules, "NPC")
local Fixtures = load(Modules, "Fixtures")
local Boxes = load(Modules, "Boxes")
local Checkouts = load(Modules, "Checkouts")
local Trash = load(Modules, "Trash")
local Vehicles = load(Modules, "Vehicles")
local Bank = load(Modules, "Bank")
local Customers = load(Modules, "Customers")
local Delivery = load(Modules, "Delivery")
local Loans = load(Modules, "Loans")
local Tools = load(Modules, "Tools")
local Employees = load(Modules, "Employees")
local Upgrades = load(Modules, "Upgrades")
local Office = load(Modules, "Office")
local Rooms = load(Modules, "Rooms")
local Persistence = load(Modules, "Persistence")
local DayCycle = load(Modules, "DayCycle")

if #problems > 0 then
	for _, problem in problems do
		warn("[Supermercado] ❌ " .. problem)
	end
	error("[Supermercado] Hay " .. #problems .. " módulo(s) con problemas: revisá la lista de arriba.")
end
print("[Supermercado] Todos los módulos cargaron bien ✔")

-- El mundo se construye siempre (en el lobby se ve de fondo)
local refs = StoreBuilder.build()

---------------------------------------------------------------------------
-- Modo SUPERMERCADO
---------------------------------------------------------------------------
local storeStarted = false

local function setupCharacter(character)
	local function apply(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = NPC.PLAYER_GROUP
		end
	end
	for _, d in character:GetDescendants() do
		apply(d)
	end
	character.DescendantAdded:Connect(apply)
end

local function setupPlayer(player)
	if Config.FIRST_PERSON then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	else
		task.spawn(function()
			pcall(function()
				player:LoadCharacter()
			end)
		end)
	end
	task.delay(4, function()
		if player.Parent then
			State.notify(player, "👋 ¡Bienvenido a " .. (State.room.name ~= "" and State.room.name or "tu supermercado") .. "! Apretá H para ver cómo se juega.", "info")
		end
	end)
end

local function startStore(saveKey)
	if storeStarted then
		return
	end
	storeStarted = true

	Interact.init()
	Bank.init()
	Fixtures.init()
	Boxes.init(refs)
	Checkouts.init()
	Trash.init(refs)
	Vehicles.init(refs)
	Customers.init(refs)
	Delivery.init(refs)
	Loans.init(refs)
	Tools.init()
	Employees.init(refs)
	Upgrades.init()
	Office.init(refs, Rooms)
	DayCycle.init(refs)

	Persistence.setKey(saveKey)
	local data = Persistence.load()
	if data and Persistence.apply(data, Upgrades) then
		State.notify(nil, "💾 Partida cargada: día " .. State.data.day, "good")
	end
	StoreBuilder.applyCustom(State.data.custom)
	State.ready = true
	State.publish()
	State.broadcastSnapshot()

	Players.CharacterAutoLoads = true
	Players.PlayerAdded:Connect(setupPlayer)
	for _, p in Players:GetPlayers() do
		setupPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		Boxes.drop(player)
		Checkouts.releasePlayer(player)
	end)

	task.spawn(function()
		while true do
			task.wait(120)
			Persistence.save()
		end
	end)
	game:BindToClose(function()
		Persistence.save()
	end)

	-- Herramienta de prueba SOLO en Studio (no existe en el juego publicado)
	if game:GetService("RunService"):IsStudio() then
		local debugFn = Instance.new("BindableFunction")
		debugFn.Name = "SMT_Debug"
		debugFn.OnInvoke = function(command, arg)
			local p = Players:GetPlayers()[1]
			if command == "open" and p then
				DayCycle.open(p)
			elseif command == "close" and p then
				DayCycle.close(p)
			elseif command == "clock" then
				State.clock = arg
			elseif command == "spawn" then
				for _ = 1, arg or 1 do
					Customers.spawn()
				end
			elseif command == "thief" then
				Customers.spawn({ thief = true })
			elseif command == "money" then
				State.data.money += arg
				State.publish()
			elseif command == "fp" then
				State.data.fp += arg
				State.publish()
			elseif command == "day" then
				State.data.day = arg
				State.publish()
			elseif command == "perk" then
				State.data.perks[arg] = true
				State.publish()
				State.broadcastSnapshot()
			elseif command == "expansion" then
				State.data.expansions[arg] = true
				Upgrades.applyExpansions()
				State.publish()
				State.broadcastSnapshot()
			elseif command == "place" then
				-- arg = { tipo, x, z, rot, nivel }
				local f = Fixtures.create(arg[1], arg[2], arg[3], arg[4] or 0, nil, arg[5])
				return f and f.id or "error"
			elseif command == "fill" then
				-- arg = { fixtureId, nivelDelMueble, productId, cantidad }
				local f = Fixtures.list[arg[1]]
				if f then
					Fixtures.fillSlot(f, arg[2], arg[3], arg[4])
				end
			elseif command == "fillall" then
				-- Llena todos los niveles de todos los muebles (gratis). Los niveles con etiqueta se completan
				-- con su producto; los vacíos reciben productos desbloqueados que entren en ese mueble.
				local unlocked = State.unlockedProducts()
				local nextIndex = {}
				local added = 0
				for _, f in Fixtures.list do
					for i, slot in f.slots do
						local productId = slot.productId
						if not productId then
							local options = {}
							for _, prod in unlocked do
								if Fixtures.accepts(f, prod.id) then
									table.insert(options, prod.id)
								end
							end
							if #options > 0 then
								local key = f.def.storage
								nextIndex[key] = (nextIndex[key] or 0) % #options + 1
								productId = options[nextIndex[key]]
							end
						end
						if productId then
							local missing = Fixtures.capacity(f, i, productId) - slot.stock
							if missing > 0 then
								Fixtures.fillSlot(f, i, productId, missing)
								added += missing
							end
						end
					end
				end
				State.notify(nil, "📦 Estantes llenos (+" .. added .. " productos)", "good")
			end
			local lines = { string.format("fase=%s hora=%s dinero=%s dia=%d nivel=%d xp=%d fp=%d satisf=%d", State.phase, Config.formatClock(State.clock), Config.formatMoney(State.data.money), State.data.day, State.data.level, State.data.xp, State.data.fp, State.data.satisfaction) }
			for _, c in Customers.active do
				table.insert(lines, string.format("  cliente %d: carrito=%d lista=%d caja=%s fila=%s frente=%s pagó=%s ladrón=%s", c.id, #c.cart, #c.list, c.checkout and c.checkout.id or "-", tostring(c.queueIndex), tostring(c.atFront), tostring(c.paid), tostring(c.thief or c.willSteal)))
			end
			for id, co in Checkouts.list do
				table.insert(lines, string.format("  caja %s: fila=%d etapa=%s actual=%s escaneados=%d/%d operador=%s", id, #co.queue, co.stage, co.current and co.current.id or "-", co.scannedCount, co.itemsTotal, co.operator and co.operator.Name or "-"))
			end
			return table.concat(lines, "\n")
		end
		debugFn.Parent = game:GetService("ServerStorage")
	end

	ReplicatedStorage:SetAttribute("Mode", "store")
	print("[Supermercado] Supermercado listo ✔ (guardado: " .. saveKey .. ")")
end

if Rooms.isRoomServer then
	local saveKey = Rooms.initRoomServer()
	startStore(saveKey)
elseif Rooms.isStudio and Config.STUDIO_SKIP_LOBBY then
	-- Prueba rápida en Studio: directo a tu súper, sin menú, nombre ni contraseña
	-- (para probar el menú de salas, poné Config.STUDIO_SKIP_LOBBY = false)
	local owner = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	Rooms.applyRecord({ id = "studio_" .. owner.UserId, name = "Súper de prueba", ownerId = owner.UserId, ownerName = owner.DisplayName })
	startStore("studio_" .. owner.UserId)
	print("[Supermercado] Modo prueba rápida (Config.STUDIO_SKIP_LOBBY = true)")
else
	-- LOBBY: sin personajes, solo el menú
	Players.CharacterAutoLoads = false
	Rooms.initLobby(function(record)
		Rooms.applyRecord(record)
		startStore("studio_" .. record.ownerId)
	end)
	ReplicatedStorage:SetAttribute("Mode", "lobby")
	print("[Supermercado] Lobby listo ✔")
end
