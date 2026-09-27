-- Salas: el menú principal (lobby) crea salas con nombre y contraseña. Cada sala es un
-- servidor reservado con su propio guardado. Los jugadores entran con la contraseña que les pasa el dueño.
-- IMPORTANTE: los teleports solo funcionan en un juego PUBLICADO. En Studio la sala arranca en el mismo servidor.
--
-- Seguridad:
--  * Las contraseñas se guardan con sal + hash, nunca en texto plano, y nunca viajan al cliente.
--  * Límite de intentos: pocos intentos fallidos por jugador y por sala cada 10 minutos (contra "fuerza bruta").
--  * Pase de entrada: al acertar la contraseña, el lobby deja un pase de 3 minutos para ESE jugador y ESA sala.
--    El servidor de la sala expulsa a cualquiera que llegue sin pase (salvo el dueño).
--  * Si la sala no se puede verificar (fallo de Roblox), nadie entra: se prefiere cerrar a dejar pasar.
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)

local Rooms = {}
Rooms.isStudio = RunService:IsStudio()
Rooms.isRoomServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
Rooms.record = nil
Rooms.allowed = {} -- [player] = true cuando ya se verificó que puede estar en la sala

local roomsStore, namesStore, ownersStore, serversStore, activeMap, ticketsMap, failsMap
pcall(function()
	roomsStore = DataStoreService:GetDataStore("SMT_Rooms_v1")
	namesStore = DataStoreService:GetDataStore("SMT_RoomNames_v1")
	ownersStore = DataStoreService:GetDataStore("SMT_OwnerRooms_v1")
	serversStore = DataStoreService:GetDataStore("SMT_RoomServers_v1")
end)
pcall(function()
	activeMap = MemoryStoreService:GetSortedMap("SMT_ActiveRooms_v1")
	ticketsMap = MemoryStoreService:GetSortedMap("SMT_JoinTickets_v1")
	failsMap = MemoryStoreService:GetSortedMap("SMT_JoinFails_v1")
end)

-- Reintenta una llamada a Roblox (DataStore/MemoryStore) hasta 3 veces
local function retry(fn)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	return false, nil
end

---------------------------------------------------------------------------
-- Contraseñas: se guardan con "sal" y un hash (nunca en texto plano)
---------------------------------------------------------------------------
local function fnv(text, seed)
	local h = seed
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

local function hashPassword(password, salt)
	local a, b = 2166136261, 3735928559
	local text = salt .. "|" .. password
	for _ = 1, 300 do
		a = fnv(text, a)
		b = fnv(text, bit32.bxor(b, a))
		text = string.format("%08x%08x", a, b) .. salt
	end
	return string.format("%08x%08x", a, b)
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function filterName(name, userId)
	local ok, result = pcall(function()
		local filtered = game:GetService("TextService"):FilterStringAsync(name, userId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return nil
	end
	return result
end

---------------------------------------------------------------------------
-- Límite de intentos fallidos (se guarda en MemoryStore para que valga en todos los lobbies)
---------------------------------------------------------------------------
local localFails = {} -- respaldo en memoria: [clave] = { count, expires }

local function failCount(key)
	local count = 0
	if failsMap then
		local ok, value = pcall(function()
			return failsMap:GetAsync(key)
		end)
		if ok and type(value) == "number" then
			count = value
		end
	end
	local l = localFails[key]
	if l and l.expires > os.time() then
		count = math.max(count, l.count)
	end
	return count
end

local function addFail(key)
	local l = localFails[key]
	if not l or l.expires <= os.time() then
		l = { count = 0, expires = os.time() + Config.FAIL_WINDOW }
		localFails[key] = l
	end
	l.count += 1
	if failsMap then
		pcall(function()
			failsMap:UpdateAsync(key, function(old)
				return (type(old) == "number" and old or 0) + 1
			end, Config.FAIL_WINDOW)
		end)
	end
end

---------------------------------------------------------------------------
-- Pases de entrada
---------------------------------------------------------------------------
local function ticketKey(roomId, userId)
	return "t_" .. string.sub(roomId, 1, 80) .. "_" .. userId
end

local function issueTicket(roomId, userId)
	if not ticketsMap then
		return false
	end
	return (retry(function()
		ticketsMap:SetAsync(ticketKey(roomId, userId), true, Config.TICKET_SECONDS)
	end))
end

local function hasTicket(roomId, userId)
	if not ticketsMap then
		return false
	end
	local ok, value = retry(function()
		return ticketsMap:GetAsync(ticketKey(roomId, userId))
	end)
	return ok and value == true
end

local function teleport(player, record)
	if not issueTicket(record.id, player.UserId) then
		return false, "No se pudo verificar tu entrada. Probá de nuevo en unos segundos."
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = record.accessCode
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn("[Salas] Error al teletransportar:", err)
		return false, "No se pudo entrar a la sala. Probá de nuevo."
	end
	return true, "Entrando a la sala..."
end

local function getRecord(roomId)
	if not roomsStore or type(roomId) ~= "string" or #roomId == 0 or #roomId > 100 then
		return nil
	end
	local ok, record = retry(function()
		return roomsStore:GetAsync(roomId)
	end)
	return ok and record or nil
end

local function findByName(name)
	if not namesStore or #name == 0 then
		return nil
	end
	local ok, roomId = retry(function()
		return namesStore:GetAsync(string.lower(name))
	end)
	if ok and roomId then
		return getRecord(roomId)
	end
	return nil
end

local function addToOwnerList(userId, record)
	ownersStore:UpdateAsync(tostring(userId), function(list)
		list = list or {}
		for i = #list, 1, -1 do
			if list[i].id == record.id then
				table.remove(list, i)
			end
		end
		table.insert(list, 1, { id = record.id, name = record.name })
		while #list > 10 do
			table.remove(list)
		end
		return list
	end)
end

---------------------------------------------------------------------------
-- LOBBY
---------------------------------------------------------------------------
-- onStudioStart(record): en Studio, la sala arranca en este mismo servidor
function Rooms.initLobby(onStudioStart)
	local busy = {} -- [player] = true mientras se procesa un pedido suyo
	local lastTry = {} -- [player] = os.clock() del último intento

	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastTry[player] = nil
	end)

	-- Evita que un jugador (o un script tramposo) mande pedidos sin parar
	local function throttle(player)
		if busy[player] then
			return false, "Esperá, todavía se está procesando lo anterior."
		end
		local now = os.clock()
		if lastTry[player] and now - lastTry[player] < Config.JOIN_COOLDOWN then
			return false, "Esperá un segundo antes de volver a intentar."
		end
		lastTry[player] = now
		return true
	end

	Remotes.ListRooms.OnServerInvoke = function()
		if not activeMap then
			return {}
		end
		local ok, entries = pcall(function()
			return activeMap:GetRangeAsync(Enum.SortDirection.Descending, 50)
		end)
		if not ok then
			return {}
		end
		local list = {}
		for _, entry in entries do
			local v = entry.value
			if type(v) == "table" then
				table.insert(list, { id = entry.key, name = v.name, ownerName = v.ownerName, players = v.players, day = v.day })
			end
		end
		return list
	end

	Remotes.MyRooms.OnServerInvoke = function(player)
		if not ownersStore then
			return {}
		end
		local ok, list = pcall(function()
			return ownersStore:GetAsync(tostring(player.UserId))
		end)
		return ok and list or {}
	end

	Remotes.CreateRoom.OnServerInvoke = function(player, name, password)
		if type(name) ~= "string" or type(password) ~= "string" or #name > 100 or #password > 100 then
			return false, "Datos inválidos."
		end
		local okThrottle, why = throttle(player)
		if not okThrottle then
			return false, why
		end
		name = trim(name)
		if #name < Config.ROOM_NAME_MIN or #name > Config.ROOM_NAME_MAX then
			return false, "El nombre tiene que tener entre " .. Config.ROOM_NAME_MIN .. " y " .. Config.ROOM_NAME_MAX .. " caracteres."
		end
		if #password < Config.PASSWORD_MIN or #password > Config.PASSWORD_MAX then
			return false, "La contraseña tiene que tener entre " .. Config.PASSWORD_MIN .. " y " .. Config.PASSWORD_MAX .. " caracteres."
		end
		local filtered = filterName(name, player.UserId)
		if not filtered then
			if not Rooms.isStudio then
				return false, "No se pudo verificar el nombre. Probá de nuevo."
			end
			filtered = name
		end
		if filtered ~= name then
			return false, "Ese nombre no está permitido. Elegí otro."
		end

		local salt = HttpService:GenerateGUID(false)
		local record = {
			id = HttpService:GenerateGUID(false),
			name = name,
			ownerId = player.UserId,
			ownerName = player.DisplayName,
			salt = salt,
			hash = hashPassword(password, salt),
			created = os.time(),
		}

		if Rooms.isStudio then
			record.id = "studio_" .. player.UserId .. "_" .. string.lower(name):gsub("%W", "")
			onStudioStart(record)
			return true, "studio"
		end

		busy[player] = true
		local ok, result = pcall(function()
			local claimed = namesStore:UpdateAsync(string.lower(name), function(old)
				if old then
					return nil
				end
				return record.id
			end)
			if claimed ~= record.id then
				return "taken"
			end
			local accessCode, privateServerId = TeleportService:ReserveServer(game.PlaceId)
			record.accessCode = accessCode
			record.privateServerId = privateServerId
			roomsStore:SetAsync(record.id, record)
			serversStore:SetAsync(privateServerId, record.id)
			addToOwnerList(player.UserId, record)
			return "ok"
		end)
		busy[player] = nil
		if not ok then
			warn("[Salas] Error al crear:", result)
			return false, "No se pudo crear la sala (¿el juego está publicado y con API Services activado?)."
		end
		if result == "taken" then
			return false, "Ya existe una sala con ese nombre."
		end
		return teleport(player, record)
	end

	Remotes.JoinRoom.OnServerInvoke = function(player, idOrName, password)
		if type(idOrName) ~= "string" or type(password) ~= "string" or #idOrName > 100 or #password > Config.PASSWORD_MAX then
			return false, "Datos inválidos."
		end
		if Rooms.isStudio then
			return false, "En Studio no se puede entrar a otras salas: creá una sala o usá «Jugar solo»."
		end
		local okThrottle, why = throttle(player)
		if not okThrottle then
			return false, why
		end
		busy[player] = true
		local okCall, success, message = pcall(function()
			local userKey = "u_" .. player.UserId
			if failCount(userKey) >= Config.MAX_FAILS_PER_PLAYER then
				return false, "🔒 Demasiados intentos fallidos. Esperá unos minutos y probá de nuevo."
			end
			local record = getRecord(idOrName) or findByName(trim(idOrName))
			if not record then
				return false, "No existe una sala con ese nombre."
			end
			if record.ownerId == player.UserId then
				return teleport(player, record)
			end
			if record.solo then
				return false, "Esa es una partida privada: solo puede entrar su dueño."
			end
			local roomKey = "r_" .. string.sub(record.id, 1, 80)
			if failCount(roomKey) >= Config.MAX_FAILS_PER_ROOM then
				return false, "🔒 Esta sala recibió muchos intentos fallidos. Probá de nuevo en unos minutos."
			end
			if hashPassword(password, record.salt) ~= record.hash then
				addFail(userKey)
				addFail(roomKey)
				local left = Config.MAX_FAILS_PER_PLAYER - failCount(userKey)
				return false, "Contraseña incorrecta." .. (left > 0 and (" Te quedan " .. left .. " intentos.") or "")
			end
			return teleport(player, record)
		end)
		busy[player] = nil
		if not okCall then
			warn("[Salas] Error al entrar:", success)
			return false, "No se pudo entrar a la sala. Probá de nuevo."
		end
		return success, message
	end

	-- "Jugar solo": tu propio súper privado, sin nombre ni contraseña. Nadie más puede entrar.
	Remotes.PlaySolo.OnServerInvoke = function(player)
		local okThrottle, why = throttle(player)
		if not okThrottle then
			return false, why
		end
		local soloId = "solo_" .. player.UserId
		if Rooms.isStudio then
			onStudioStart({
				id = "studio_" .. player.UserId,
				name = "Súper de " .. player.DisplayName,
				ownerId = player.UserId,
				ownerName = player.DisplayName,
				solo = true,
			})
			return true, "studio"
		end
		busy[player] = true
		local ok, result = pcall(function()
			local record = getRecord(soloId)
			if not record then
				local accessCode, privateServerId = TeleportService:ReserveServer(game.PlaceId)
				record = {
					id = soloId,
					name = "Súper de " .. player.DisplayName,
					ownerId = player.UserId,
					ownerName = player.DisplayName,
					solo = true,
					accessCode = accessCode,
					privateServerId = privateServerId,
					created = os.time(),
				}
				roomsStore:SetAsync(record.id, record)
				serversStore:SetAsync(privateServerId, record.id)
			end
			return record
		end)
		busy[player] = nil
		if not ok or type(result) ~= "table" then
			warn("[Salas] Error en jugar solo:", result)
			return false, "No se pudo abrir tu partida (¿el juego está publicado y con API Services activado?)."
		end
		return teleport(player, result)
	end
end

---------------------------------------------------------------------------
-- SERVIDOR DE LA SALA
---------------------------------------------------------------------------
local function heartbeat()
	if not activeMap or not Rooms.record or not Rooms.record.verified or Rooms.record.solo then
		return
	end
	pcall(function()
		activeMap:SetAsync(Rooms.record.id, {
			name = Rooms.record.name,
			ownerName = Rooms.record.ownerName,
			players = #Players:GetPlayers(),
			day = State.data.day,
		}, 120)
	end)
end

function Rooms.applyRecord(record)
	Rooms.record = record
	State.room = { id = record.id, name = record.name, ownerId = record.ownerId, ownerName = record.ownerName, solo = record.solo }
	State.publish()
end

-- ¿Este jugador puede estar en la sala? (el dueño siempre; los demás solo con pase)
function Rooms.verifyPlayer(player)
	if Rooms.isStudio then
		return true
	end
	local record = Rooms.record
	if not record or not record.verified then
		return false
	end
	if player.UserId == record.ownerId then
		return true
	end
	if record.solo then
		return false
	end
	return hasTicket(record.id, player.UserId)
end

function Rooms.isAllowed(player)
	return Rooms.isStudio or Rooms.allowed[player] == true
end

-- Devuelve la clave de guardado de la sala
function Rooms.initRoomServer()
	-- La sala se identifica SOLO por el servidor reservado (dato que el jugador no puede tocar)
	local roomId
	if serversStore then
		local _, value = retry(function()
			return serversStore:GetAsync(game.PrivateServerId)
		end)
		roomId = value
	end
	local record = roomId and getRecord(roomId)
	if record and record.privateServerId == game.PrivateServerId then
		record.verified = true
	else
		warn("[Salas] ❌ No se pudo verificar esta sala: nadie va a poder entrar.")
		record = { id = game.PrivateServerId, name = "Sala no verificada", ownerId = 0, ownerName = "?", verified = false }
	end
	Rooms.applyRecord(record)

	local function gate(player)
		task.spawn(function()
			if Rooms.verifyPlayer(player) then
				Rooms.allowed[player] = true
			else
				warn("[Salas] Acceso denegado a " .. player.Name .. " (" .. player.UserId .. ")")
				player:Kick("🔒 No tenés acceso a esta sala. Entrá desde el menú principal con la contraseña que te pasó el dueño.")
			end
		end)
	end
	Players.PlayerAdded:Connect(gate)
	for _, p in Players:GetPlayers() do
		gate(p)
	end

	task.spawn(function()
		while true do
			heartbeat()
			task.wait(45)
		end
	end)
	Players.PlayerAdded:Connect(heartbeat)
	Players.PlayerRemoving:Connect(function(player)
		Rooms.allowed[player] = nil
		task.defer(heartbeat)
	end)
	game:BindToClose(function()
		if activeMap and Rooms.record and Rooms.record.verified then
			pcall(function()
				activeMap:RemoveAsync(Rooms.record.id)
			end)
		end
	end)
	return "save_" .. record.id
end

function Rooms.setPassword(password)
	local record = Rooms.record
	if not record then
		return false, "No hay sala."
	end
	if record.solo then
		return false, "Tu partida solo es privada: no usa contraseña."
	end
	record.salt = HttpService:GenerateGUID(false)
	record.hash = hashPassword(password, record.salt)
	if Rooms.isStudio or not roomsStore then
		return true, "Contraseña cambiada (en Studio no se guarda)."
	end
	local stored = table.clone(record)
	stored.verified = nil
	local ok = pcall(function()
		roomsStore:SetAsync(record.id, stored)
	end)
	if not ok then
		return false, "No se pudo guardar la contraseña."
	end
	return true, "¡Contraseña cambiada!"
end

return Rooms
