-- Oficina del gerente: abre las pizarras, hace pedidos de mercadería y personaliza el local.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Fixtures = require(script.Parent.Fixtures)
local Boxes = require(script.Parent.Boxes)
local Vehicles = require(script.Parent.Vehicles)

local Office = {}
local pendingBoxes = 0
local fmt = Config.formatMoney

-- Filtra texto que van a ver otros jugadores (obligatorio en Roblox)
function Office.filter(text, userId)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	return nil
end

function Office.init(refs, Rooms)
	for tab, prompt in refs.boards do
		prompt.Triggered:Connect(function(player)
			Remotes.OpenOffice:FireClient(player, tab)
		end)
	end

	Remotes.GetSnapshot.OnServerInvoke = function()
		local snap = State.snapshot()
		if State.hasPerk("logistics") then
			snap.stockShelf, snap.stockStorage = Fixtures.stockCounts()
		end
		return snap
	end

	Remotes.PlaceOrder.OnServerInvoke = function(player, cart)
		if type(cart) ~= "table" then
			return false, "Pedido inválido."
		end
		local lines, boxes, cost = {}, 0, 0
		for productId, amount in cart do
			local prod = type(productId) == "string" and Config.ProductsById[productId]
			if prod and type(amount) == "number" and amount >= 1 then
				amount = math.floor(math.min(amount, Config.MAX_BOXES_PER_ORDER))
				if not State.isProductUnlocked(productId) then
					return false, prod.name .. " está bloqueado."
				end
				table.insert(lines, { prod = prod, amount = amount })
				boxes += amount
				cost += prod.unitsPerBox * State.getMarket(productId) * amount
			end
		end
		if boxes == 0 then
			return false, "El carrito está vacío."
		end
		if boxes > Config.MAX_BOXES_PER_ORDER then
			return false, "Máximo " .. Config.MAX_BOXES_PER_ORDER .. " cajas por pedido."
		end
		if Boxes.count() + pendingBoxes + boxes > Config.MAX_BOXES then
			return false, "Hay demasiadas cajas en el local. ¡Reponé o reciclá primero!"
		end
		local total = cost + Config.DELIVERY_FEE
		if not State.trySpend(total) then
			return false, "No tenés suficiente dinero (" .. fmt(cost) .. " + " .. fmt(Config.DELIVERY_FEE) .. " de envío)."
		end
		State.addStat("orders", 1)
		State.addStat("shipping", Config.DELIVERY_FEE)
		pendingBoxes += boxes
		local list = {}
		for _, line in lines do
			for _ = 1, line.amount do
				table.insert(list, line.prod.id)
			end
		end
		local position = Vehicles.enqueueDelivery({ boxes = list })
		task.delay(1, function()
			pendingBoxes = math.max(0, pendingBoxes - boxes)
		end)
		State.notify(nil, string.format("📦 %s pidió %d caja(s) por %s (+%s de envío). La camioneta de %s ya sale%s.", player.DisplayName, boxes, fmt(cost), fmt(Config.DELIVERY_FEE), Config.VAN_NAME, position > 1 and (" (hay " .. (position - 1) .. " envío/s antes)") or ""), "info")
		return true, "Pedido realizado: " .. fmt(total)
	end

	-- Comprar un mueble: llega en una caja de madera con la camioneta (envío gratis)
	Remotes.BuyFixture.OnServerInvoke = function(player, fixtureType)
		local def = type(fixtureType) == "string" and Config.Fixtures[fixtureType]
		if not def then
			return false, "Mueble inválido."
		end
		if def.requires and not State.hasPerk(def.requires) then
			return false, "Necesitás la mejora de franquicia: " .. Config.PerksById[def.requires].name
		end
		if not State.trySpend(def.cost) then
			return false, "No tenés suficiente dinero (" .. fmt(def.cost) .. ")."
		end
		Vehicles.enqueueDelivery({ crates = { fixtureType } })
		State.notify(nil, "🛻 " .. player.DisplayName .. " compró: " .. def.name .. ". Llega en su caja con la camioneta.", "info")
		return true, "Compraste " .. def.name .. " (-" .. fmt(def.cost) .. "). La camioneta de " .. Config.VAN_NAME .. " te la deja en unos segundos en la zona de descarga."
	end

	Remotes.Customize.OnServerInvoke = function(player, key, value)
		local custom = State.data.custom
		if key == "floor" and type(value) == "number" and Config.FloorPresets[value] then
			custom.floor = value
		elseif key == "walls" and type(value) == "number" and Config.WallPresets[value] then
			custom.walls = value
		elseif key == "signColor" and type(value) == "number" and Config.SignColors[value] then
			custom.signColor = value
		elseif key == "storeName" and type(value) == "string" then
			if not State.isOwner(player) then
				return false, "Solo el dueño puede cambiar el nombre."
			end
			local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
			if #trimmed < 2 or #trimmed > 22 then
				return false, "El nombre tiene que tener entre 2 y 22 letras."
			end
			local filtered = Office.filter(trimmed, player.UserId)
			if not filtered then
				return false, "No se pudo verificar el nombre. Probá de nuevo."
			end
			custom.storeName = string.upper(filtered)
		else
			return false, "Opción inválida."
		end
		StoreBuilder.applyCustom(custom)
		State.publish()
		State.broadcastSnapshot()
		return true
	end

	Remotes.SetRoomPassword.OnServerInvoke = function(player, password)
		if not State.isOwner(player) then
			return false, "Solo el dueño puede cambiar la contraseña."
		end
		if type(password) ~= "string" or #password < Config.PASSWORD_MIN or #password > Config.PASSWORD_MAX then
			return false, "La contraseña tiene que tener entre " .. Config.PASSWORD_MIN .. " y " .. Config.PASSWORD_MAX .. " caracteres."
		end
		return Rooms.setPassword(password)
	end
end

return Office
