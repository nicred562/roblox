-- Préstamos del banco: cuotas diarias. Si no pagás, vienen los cobradores: te persiguen,
-- te pegan y se llevan la plata que debés (con recargo). Se los puede echar a escobazos.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local NPC = require(script.Parent.NPC)

local Loans = {}
Loans.collectors = {}
local refs
local spawnedToday = false
local fmt = Config.formatMoney

local THREATS = { "¡Pagá lo que debés!", "¡La plata o te rompo todo!", "¡Tomá! 👊", "¡El banco no espera!", "¡Te dijimos que pagaras!" }

local function publishLoan()
	State.publish()
	State.broadcastSnapshot()
end

function Loans.activeCollectors()
	local list = {}
	for _, col in Loans.collectors do
		if col.active and NPC.alive(col.npc) then
			table.insert(list, col)
		end
	end
	return list
end

local function nearestPlayer(position)
	local best, bestDist
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local d = (root.Position - position).Magnitude
			if not best or d < bestDist then
				best, bestDist = p, d
			end
		end
	end
	return best
end

local function removeCollector(col)
	col.active = false
	if col.npc.model.Parent then
		col.npc.model:Destroy()
	end
	local idx = table.find(Loans.collectors, col)
	if idx then
		table.remove(Loans.collectors, idx)
	end
end

local function attack(col, player)
	local loan = State.data.loan
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not loan or not humanoid or not root then
		return
	end
	NPC.face(col.npc, root.Position)
	NPC.say(col.npc, THREATS[math.random(#THREATS)], 2)
	humanoid:TakeDamage(Config.COLLECTOR_DAMAGE)
	Remotes.Knockback:FireClient(player, (root.Position - col.npc.root.Position).Unit)

	local steal = math.min(loan.overdue, math.max(1500, math.floor(loan.overdue * Config.COLLECTOR_STEAL)))
	local penalty = math.floor(steal * Config.COLLECTOR_PENALTY)
	State.data.money -= steal + penalty
	loan.overdue -= steal
	loan.remaining -= steal
	if loan.remaining <= 0 then
		State.data.loan = nil
	end
	publishLoan()
	State.notify(nil, string.format("💢 Los cobradores le pegaron a %s y se llevaron %s (+%s de recargo).", player.DisplayName, fmt(steal), fmt(penalty)), "bad")
end

local function runCollector(col)
	local npc = col.npc
	NPC.setIcon(npc, "💼 COBRADOR", Color3.fromRGB(35, 35, 40))
	NPC.say(npc, "¡Venimos a cobrar la deuda!", 4)
	NPC.walkTo(npc, refs.points.entranceOutside, 60)
	while col.active and NPC.alive(npc) do
		local loan = State.data.loan
		if not loan or loan.overdue <= 0 then
			break
		end
		if npc.knocked then
			task.wait(0.2)
		else
			local target = nearestPlayer(npc.root.Position)
			local troot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if not troot then
				NPC.walkTo(npc, refs.points.entranceInside, 6)
				task.wait(1)
			elseif NPC.flatDistance(npc.root.Position, troot.Position) > 4.5 then
				NPC.walkTo(npc, troot.Position, 1.5)
			else
				attack(col, target)
				task.wait(Config.COLLECTOR_ATTACK_DELAY)
			end
		end
	end
	if NPC.alive(npc) then
		col.active = false
		NPC.setIcon(npc, nil)
		local loan = State.data.loan
		NPC.say(npc, (loan and loan.overdue > 0) and "¡Ya vamos a volver!" or "Cuenta saldada. Hasta la próxima. 😎", 3)
		npc.humanoid.WalkSpeed = 18
		NPC.walkTo(npc, Vector3.new(0, 0.3, 90), 40)
	end
	removeCollector(col)
end

local function spawnCollectors()
	local loan = State.data.loan
	if not loan or loan.overdue <= 0 then
		return
	end
	local amount = math.min(Config.COLLECTOR_MAX, 1 + loan.missed)
	State.notify(nil, "⚠️ ¡Llegaron " .. amount .. " cobrador(es) por la deuda atrasada (" .. fmt(loan.overdue) .. ")! Pagá en la pizarra o echalos a escobazos.", "bad")
	for i = 1, amount do
		task.spawn(function()
			local npc = NPC.create("Cobrador", {
				uniform = { shirt = Color3.fromRGB(25, 25, 28), pants = Color3.fromRGB(25, 25, 28) },
				displayName = "Cobrador",
				walkSpeed = 16,
			})
			NPC.spawn(npc, Vector3.new(-6 + i * 3, 0.3, 90))
			local col = { npc = npc, hits = 0, active = true }
			table.insert(Loans.collectors, col)
			local ok, err = pcall(runCollector, col)
			if not ok then
				warn("[Supermercado] Error en cobrador:", err)
				removeCollector(col)
			end
		end)
	end
end

-- Escobazo a un cobrador. Devuelve true si el modelo era un cobrador.
function Loans.hitCollector(model, fromPosition, player)
	for _, col in Loans.collectors do
		if col.npc.model == model then
			if col.npc.knocked or not col.active then
				return true
			end
			col.hits += 1
			task.spawn(NPC.knockDown, col.npc, fromPosition, 1.2)
			if col.hits >= Config.COLLECTOR_HITS then
				col.active = false
				State.notify(nil, "💪 " .. (player and player.DisplayName or "Seguridad") .. " echó a un cobrador. ¡Pero la deuda sigue!", "good")
			else
				NPC.say(col.npc, "¡Ay! ¡Ya vas a ver!", 1.5)
			end
			return true
		end
	end
	return false
end

function Loans.dismissAll()
	for _, col in Loans.collectors do
		col.active = false
	end
end

-- Lo llama DayCycle cada tick con la hora actual
function Loans.tick(clock)
	local loan = State.data.loan
	if spawnedToday or State.phase ~= "Abierto" or not loan or loan.overdue <= 0 then
		return
	end
	if clock >= Config.COLLECTOR_ARRIVAL_HOUR then
		spawnedToday = true
		spawnCollectors()
	end
end

function Loans.newDay()
	spawnedToday = false
end

-- Cobro automático de la cuota al cerrar el día. Devuelve info para el resumen.
function Loans.endOfDay()
	local loan = State.data.loan
	if not loan then
		return nil
	end
	local due = math.min(loan.remaining, loan.overdue + loan.perDay)
	local info = { due = due, paid = 0, missed = false }
	if State.data.money >= due then
		State.data.money -= due
		loan.remaining -= due
		loan.overdue = 0
		loan.missed = 0
		info.paid = due
	else
		loan.overdue = due
		loan.missed += 1
		info.missed = true
	end
	info.remaining = loan.remaining
	info.overdue = loan.overdue
	if loan.remaining <= 0 then
		State.data.loan = nil
		State.notify(nil, "🏦 ¡Terminaste de pagar el préstamo!", "good")
	end
	Loans.dismissAll()
	publishLoan()
	return info
end

function Loans.init(builderRefs)
	refs = builderRefs

	Remotes.TakeLoan.OnServerInvoke = function(player, loanId)
		if not State.isOwner(player) then
			return false, "Solo el dueño de la sala puede pedir préstamos."
		end
		if State.data.loan then
			return false, "Ya tenés un préstamo activo."
		end
		local def = type(loanId) == "string" and Config.LoansById[loanId]
		if not def then
			return false, "Préstamo inválido."
		end
		local total = math.floor(def.amount * (1 + def.interest) + 0.5)
		State.data.loan = { id = def.id, remaining = total, perDay = math.ceil(total / def.days), overdue = 0, missed = 0 }
		State.data.money += def.amount
		publishLoan()
		State.notify(nil, "🏦 " .. player.DisplayName .. " pidió un préstamo de " .. fmt(def.amount) .. ".", "info")
		return true, "Préstamo aprobado: devolvés " .. fmt(total) .. " en " .. def.days .. " días."
	end

	Remotes.PayLoan.OnServerInvoke = function(_player, amount)
		local loan = State.data.loan
		if not loan then
			return false, "No tenés préstamos."
		end
		if amount == "all" then
			amount = loan.remaining
		end
		if type(amount) ~= "number" or amount ~= amount then
			return false, "Monto inválido."
		end
		amount = math.clamp(math.floor(amount), 1, loan.remaining)
		if State.data.money < amount then
			return false, "No te alcanza la plata."
		end
		State.data.money -= amount
		loan.remaining -= amount
		loan.overdue = math.max(0, loan.overdue - amount)
		if loan.overdue <= 0 then
			loan.missed = 0
			Loans.dismissAll()
		end
		if loan.remaining <= 0 then
			State.data.loan = nil
			State.notify(nil, "🏦 ¡Préstamo pagado por completo!", "good")
		end
		publishLoan()
		return true, "Pagaste " .. fmt(amount) .. "."
	end
end

return Loans
