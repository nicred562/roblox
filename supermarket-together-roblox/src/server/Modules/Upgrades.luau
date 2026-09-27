-- Pizarra de franquicia (mejoras con puntos) y ampliaciones del local (con dinero).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)

local Upgrades = {}

function Upgrades.applyExpansions()
	for id in State.data.expansions do
		StoreBuilder.unlockExpansion(id)
	end
end

function Upgrades.init()
	Remotes.BuyPerk.OnServerInvoke = function(player, id)
		local perk = type(id) == "string" and Config.PerksById[id]
		if not perk then
			return false, "Esa mejora no existe."
		end
		if State.hasPerk(id) then
			return false, "Ya tenés esta mejora."
		end
		if perk.requires and not State.hasPerk(perk.requires) then
			return false, "Primero necesitás: " .. Config.PerksById[perk.requires].name
		end
		if State.data.fp < perk.cost then
			return false, "Te faltan puntos de franquicia (subí de nivel atendiendo clientes)."
		end
		State.data.fp -= perk.cost
		State.data.perks[id] = true
		State.publish()
		State.broadcastSnapshot()
		State.notify(nil, "⭐ " .. player.DisplayName .. " desbloqueó: " .. perk.name, "good")
		return true, "¡Desbloqueado!"
	end

	Remotes.BuyExpansion.OnServerInvoke = function(player, id)
		local exp = type(id) == "string" and Config.ExpansionsById[id]
		if not exp then
			return false, "Esa ampliación no existe."
		end
		if State.hasExpansion(id) then
			return false, "Ya compraste esta ampliación."
		end
		if exp.requires and not State.hasExpansion(exp.requires) then
			return false, "Primero necesitás: " .. Config.ExpansionsById[exp.requires].name
		end
		-- El primer piso necesita lugar para la escalera (fondo a la derecha de la tienda)
		if id == "floor1" then
			local Fixtures = require(script.Parent.Fixtures)
			for _, fp in Fixtures.footprints(nil, 0) do
				if Config.Overlaps(fp, Config.STAIRWELL) then
					return false, "Primero mové los muebles del fondo a la derecha de la tienda: ahí va la escalera."
				end
			end
		end
		if not State.trySpend(exp.cost) then
			return false, "No tenés suficiente dinero."
		end
		State.data.expansions[id] = true
		StoreBuilder.unlockExpansion(id)
		StoreBuilder.applyCustom(State.data.custom)
		State.publish()
		State.broadcastSnapshot()
		State.notify(nil, "🏗️ " .. player.DisplayName .. " compró: " .. exp.name, "good")
		return true, "¡Ampliación lista!"
	end
end

return Upgrades
