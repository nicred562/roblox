-- Objetos que se "usan" con un click (sin la tecla E): el cartel de ABIERTO/CERRADO de la entrada,
-- el mostrador de pedidos, etc. Cada pieza tiene Kind = "use", UseAction = nombre de la acción
-- y Hint = el texto que ve el jugador al apuntarle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Interact = {}
local handlers = {} -- [acción] = function(player, part)
local lastUse = {} -- [player] = os.clock()

-- Marca una pieza para que se pueda usar con click
function Interact.mark(part, action, hint)
	part:SetAttribute("Kind", "use")
	part:SetAttribute("UseAction", action)
	part:SetAttribute("Hint", hint or "")
end

function Interact.setHint(part, hint)
	if part and part.Parent then
		part:SetAttribute("Hint", hint or "")
	end
end

function Interact.register(action, fn)
	handlers[action] = fn
end

function Interact.init()
	Remotes.Action.OnServerEvent:Connect(function(player, kind, part)
		if kind ~= "use" or typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
			return
		end
		-- anti-spam
		local now = os.clock()
		if lastUse[player] and now - lastUse[player] < 0.35 then
			return
		end
		lastUse[player] = now
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - part.Position).Magnitude > Config.INTERACT_DISTANCE + 4 then
			return
		end
		local fn = handlers[part:GetAttribute("UseAction") or ""]
		if fn then
			local ok, err = pcall(fn, player, part)
			if not ok then
				warn("[Supermercado] Error al usar " .. tostring(part:GetAttribute("UseAction")) .. ":", err)
			end
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)
end

return Interact
