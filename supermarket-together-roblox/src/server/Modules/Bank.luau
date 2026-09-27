-- Banco "Tesoro Digital": cajeros automáticos afuera del súper.
--  * Los jugadores depositan o retiran la plata del súper. Lo que está en el banco no lo pueden
--    robar (cobradores, patoteros de la competencia) y gana un poquito de interés por día.
--  * Si al cerrar el día no alcanza el efectivo para las facturas, se debita solo del banco.
--  * Los clientes (NPCs) a veces sacan plata del cajero antes de comprar y pagan en efectivo;
--    el súper cobra una comisión por tener el cajero.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TesoroLogo = require(Shared:WaitForChild("TesoroLogo"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)
local NPC = require(script.Parent.NPC)
local Interact = require(script.Parent.Interact)

local Bank = {}
Bank.atms = {} -- { body, screenLabel, stand, face, busy }

local V, C = Vector3.new, Color3.fromRGB
local fmt = Config.formatMoney
local part = StoreBuilder.part

local function screenGui(target, face, canvas)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = target
	return gui
end

-- Un cajero: el frente mira hacia `facing`
local function buildATM(parent, position, facing, index)
	local cf = CFrame.lookAt(position, position + facing)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local navy, navy2, dark = TesoroLogo.NAVY, TesoroLogo.NAVY2, C(28, 32, 38)
	local body = part({ Name = "ATMBody", Size = V(2.4, 5.4, 1.2), CFrame = at(0, 2.7, 0), Color = navy, Material = Enum.Material.SmoothPlastic, Parent = parent })
	part({ Name = "ATMFrame", Size = V(2.5, 0.3, 1.3), CFrame = at(0, 5.5, 0), Color = TesoroLogo.TEAL, Material = Enum.Material.SmoothPlastic, Parent = parent })
	part({ Name = "ATMBase", Size = V(2.6, 0.3, 1.4), CFrame = at(0, 0.15, 0), Color = dark, Parent = parent })
	-- Frente: hueco con pantalla, teclado, ranura de tarjeta y dispensador de billetes
	part({ Name = "ATMFace", Size = V(2.1, 3.2, 0.1), CFrame = at(0, 3.1, -0.62), Color = navy2, CanQuery = false, Parent = parent })
	local screen = part({ Name = "ATMScreen", Size = V(1.5, 1.05, 0.05), CFrame = at(0, 3.95, -0.68) * CFrame.Angles(math.rad(-6), 0, 0), Color = C(10, 20, 30), CastShadow = false, Parent = parent })
	local sgui = screenGui(screen, Enum.NormalId.Front, Vector2.new(300, 210))
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = navy
	bg.BorderSizePixel = 0
	bg.Parent = sgui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(navy, navy2)
	gradient.Rotation = 90
	gradient.Parent = bg
	TesoroLogo.create(bg, 96, UDim2.fromOffset(102, 14))
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, 120)
	label.Size = UDim2.new(1, -20, 0, 80)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = TesoroLogo.LIGHT
	label.Text = "Tesoro Digital\nInsertá tu tarjeta"
	label.Parent = bg

	-- teclado numérico
	local keypad = part({ Name = "ATMKeypad", Size = V(1.1, 0.08, 0.6), CFrame = at(-0.25, 2.85, -0.85) * CFrame.Angles(math.rad(20), 0, 0), Color = C(190, 194, 200), Material = Enum.Material.Metal, CastShadow = false, Parent = parent })
	local kgui = screenGui(keypad, Enum.NormalId.Top, Vector2.new(110, 60))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(32, 12)
	grid.CellPadding = UDim2.fromOffset(4, 3)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.Parent = kgui
	for i = 1, 12 do
		local key = Instance.new("TextLabel")
		key.BackgroundColor3 = i == 10 and C(200, 60, 60) or (i == 12 and C(60, 170, 90) or C(70, 74, 82))
		key.BorderSizePixel = 0
		key.Text = ({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "✕", "0", "✓" })[i]
		key.TextColor3 = Color3.new(1, 1, 1)
		key.TextScaled = true
		key.Font = Enum.Font.GothamBold
		key.Parent = kgui
	end
	part({ Name = "ATMCardSlot", Size = V(0.45, 0.08, 0.1), CFrame = at(0.62, 2.95, -0.72), Color = dark, CanQuery = false, Parent = parent })
	part({ Name = "ATMCardLight", Size = V(0.45, 0.04, 0.05), CFrame = at(0.62, 3.03, -0.73), Color = TesoroLogo.TEAL, Material = Enum.Material.Neon, CanQuery = false, CastShadow = false, Parent = parent })
	part({ Name = "ATMCash", Size = V(1.2, 0.12, 0.12), CFrame = at(0, 2.2, -0.7), Color = dark, CanQuery = false, Parent = parent })
	part({ Name = "ATMCashLight", Size = V(1.2, 0.04, 0.05), CFrame = at(0, 2.29, -0.72), Color = TesoroLogo.TEAL, Material = Enum.Material.Neon, CanQuery = false, CastShadow = false, Parent = parent })

	-- Se usa con click en el cuerpo o en la pantalla
	for _, p in { body, screen } do
		Interact.mark(p, "atm", "🏦 Click: usar el cajero Tesoro Digital (depositar / retirar)")
	end
	local atm = {
		index = index,
		body = body,
		label = label,
		stand = (cf * CFrame.new(0, 0, -2.4)).Position,
		face = position,
		busy = false,
	}
	table.insert(Bank.atms, atm)
	return atm
end

local function buildLobby(parent)
	-- Dos cajeros contra la vidriera, a la izquierda de la entrada, con el cartel del banco arriba
	for i, x in { -13.4, -10.2 } do
		buildATM(parent, V(x, Config.FLOOR_Y + 0.05, 31.75), V(0, 0, 1), i)
	end
	local sign = part({ Name = "TesoroSign", Size = V(6.6, 1.3, 0.3), Position = V(-11.8, 6.9, 31.3), Color = TesoroLogo.NAVY, Parent = parent })
	local sgui = screenGui(sign, Enum.NormalId.Back, Vector2.new(660, 130))
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = TesoroLogo.NAVY
	bg.BorderSizePixel = 0
	bg.Parent = sgui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(TesoroLogo.NAVY, TesoroLogo.NAVY2)
	gradient.Parent = bg
	TesoroLogo.create(bg, 110, UDim2.fromOffset(18, 10))
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(142, 12)
	title.Size = UDim2.new(1, -160, 0, 70)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "Tesoro Digital"
	title.Parent = bg
	local sub = title:Clone()
	sub.Position = UDim2.fromOffset(144, 82)
	sub.Size = UDim2.new(1, -160, 0, 34)
	sub.Font = Enum.Font.GothamBold
	sub.TextColor3 = TesoroLogo.TEAL
	sub.Text = "Cajeros automáticos · 24 hs"
	sub.Parent = bg
	part({ Name = "TesoroSignEdge", Size = V(6.7, 0.1, 0.34), Position = V(-11.8, 6.2, 31.3), Color = TesoroLogo.TEAL, Material = Enum.Material.Neon, CastShadow = false, CanQuery = false, Parent = parent })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 10
	light.Angle = 80
	light.Brightness = 0.7
	light.Color = C(200, 240, 235)
	light.Shadows = false
	light.Parent = sign
end

local function nearATM(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, atm in Bank.atms do
		if (root.Position - atm.body.Position).Magnitude <= Config.INTERACT_DISTANCE + 4 then
			return true
		end
	end
	return false
end

-- Monto válido (entero positivo y razonable) o "all"
local function parseAmount(amount)
	if amount == "all" then
		return "all"
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > 1e12 then
		return nil
	end
	return math.floor(amount)
end

function Bank.init()
	local folder = Instance.new("Folder")
	folder.Name = "TesoroDigital"
	folder.Parent = StoreBuilder.structure
	buildLobby(folder)

	Interact.register("atm", function(player)
		Remotes.OpenBank:FireClient(player)
	end)

	Remotes.BankTransfer.OnServerInvoke = function(player, action, amount)
		if not nearATM(player) then
			return false, "Tenés que estar parado en un cajero Tesoro Digital."
		end
		local value = parseAmount(amount)
		if not value then
			return false, "Monto inválido."
		end
		local d = State.data
		d.bank = d.bank or 0
		if action == "deposit" then
			value = value == "all" and d.money or math.min(value, d.money)
			if value <= 0 then
				return false, "No hay efectivo para depositar."
			end
			d.money -= value
			d.bank += value
			State.publish()
			State.notify(nil, "🏦 " .. player.DisplayName .. " depositó " .. fmt(value) .. " en Tesoro Digital.", "info")
			return true, "Depositaste " .. fmt(value) .. ". En el banco no te lo pueden robar."
		elseif action == "withdraw" then
			value = value == "all" and d.bank or math.min(value, d.bank)
			if value <= 0 then
				return false, "No hay plata en el banco."
			end
			d.bank -= value
			d.money += value
			State.publish()
			State.notify(nil, "🏦 " .. player.DisplayName .. " retiró " .. fmt(value) .. " de Tesoro Digital.", "info")
			return true, "Retiraste " .. fmt(value) .. "."
		end
		return false, "Operación inválida."
	end
end

-- Al cerrar el día: interés sobre lo guardado
function Bank.endOfDay()
	local d = State.data
	d.bank = d.bank or 0
	local gain = math.floor(d.bank * Config.BANK_INTEREST)
	if gain > 0 then
		d.bank += gain
		State.notify(nil, "🏦 Tesoro Digital te pagó " .. fmt(gain) .. " de interés por la plata guardada.", "good")
	end
	State.publish()
	return gain
end

-- Si el efectivo quedó en negativo (facturas, cuotas), se cubre con el banco
function Bank.autoDebit()
	local d = State.data
	d.bank = d.bank or 0
	if d.money < 0 and d.bank > 0 then
		local take = math.min(-d.money, d.bank)
		d.bank -= take
		d.money += take
		State.notify(nil, "🏦 Débito automático de Tesoro Digital: " .. fmt(take) .. " para pagar las cuentas.", "warn")
		State.publish()
	end
end

-- Un cliente saca plata del cajero (vuelve cuando terminó). Devuelve true si lo usó.
function Bank.npcWithdraw(npc)
	local free = {}
	for _, atm in Bank.atms do
		if not atm.busy then
			table.insert(free, atm)
		end
	end
	if #free == 0 then
		return false
	end
	local atm = free[math.random(#free)]
	atm.busy = true
	local used = false
	if NPC.walkTo(npc, atm.stand, 30) then
		NPC.face(npc, atm.face)
		atm.label.Text = "Procesando...\n⏳"
		task.wait(1.6 + math.random())
		atm.label.Text = "Retirá tu dinero\n💵"
		task.wait(1.2)
		NPC.say(npc, "💵 Listo, saqué plata", 2)
		State.addIncome(Config.ATM_HOST_FEE)
		State.addStat("atm", 1)
		used = true
	end
	atm.label.Text = "Tesoro Digital\nInsertá tu tarjeta"
	atm.busy = false
	return used
end

return Bank
