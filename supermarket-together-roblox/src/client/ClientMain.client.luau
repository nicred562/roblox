-- Interfaz del supermercado (solo en modo "store"):
-- HUD, mira e interacciones en primera persona, construcción (TAB), pistola de precios,
-- caja registradora y cobro, oficina (pedidos, franquicia, empleados, préstamos, personalizar),
-- reporte del día, ayuda y tutorial de primeros pasos.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TesoroLogo = require(Shared:WaitForChild("TesoroLogo"))

while ReplicatedStorage:GetAttribute("Mode") ~= "store" do
	ReplicatedStorage:GetAttributeChangedSignal("Mode"):Wait()
end

local status = ReplicatedStorage:WaitForChild("StoreStatus")
local fmt = Config.formatMoney
local V = Vector3.new

local THEME = {
	bg = Color3.fromRGB(24, 28, 36),
	panel = Color3.fromRGB(38, 44, 56),
	panel2 = Color3.fromRGB(56, 64, 80),
	stroke = Color3.fromRGB(80, 90, 110),
	text = Color3.fromRGB(245, 247, 250),
	muted = Color3.fromRGB(165, 173, 186),
	green = Color3.fromRGB(46, 170, 95),
	blue = Color3.fromRGB(52, 120, 220),
	yellow = Color3.fromRGB(215, 165, 30),
	red = Color3.fromRGB(210, 72, 72),
}

---------------------------------------------------------------------------
-- Helpers de UI
---------------------------------------------------------------------------
local function create(className, props, children)
	local inst = Instance.new(className)
	local parent
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function corner(r)
	return create("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end

local function padding(px)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function listLayout(direction, spacing, extra)
	local props = { FillDirection = direction or Enum.FillDirection.Vertical, Padding = UDim.new(0, spacing or 6), SortOrder = Enum.SortOrder.LayoutOrder }
	for k, v in extra or {} do
		props[k] = v
	end
	return create("UIListLayout", props)
end

local function text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = THEME.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}
	for k, v in props do
		base[k] = v
	end
	return create("TextLabel", base)
end

local function button(label, color, props)
	local base = {
		Text = label,
		BackgroundColor3 = color or THEME.blue,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		Size = UDim2.fromOffset(110, 34),
	}
	for k, v in props or {} do
		base[k] = v
	end
	return create("TextButton", base, { corner(8) })
end

local function scrollList(parent, props)
	local base = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}
	for k, v in props or {} do
		base[k] = v
	end
	return create("ScrollingFrame", base, { listLayout(nil, 6), create("UIPadding", { PaddingRight = UDim.new(0, 10) }) })
end

local function clearList(frame)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function row(parent, order, height)
	return create("Frame", { Size = UDim2.new(1, 0, 0, height or 60), BackgroundColor3 = THEME.panel, LayoutOrder = order, Parent = parent }, { corner(8) })
end

local function safeInvoke(remote, ...)
	local args = table.pack(...)
	local ok, a, b = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, "Error de conexión con el servidor."
	end
	return a, b
end

local screenGui = create("ScreenGui", {
	Name = "SupermarketUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
-- Toda la interfaz cuelga de un marco con UIScale: en pantallas chicas (celulares) se achica sola
local gui = create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screenGui })
local uiScale = create("UIScale", { Parent = gui })
local function updateScale()
	local viewport = workspace.CurrentCamera.ViewportSize
	local s = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1)
	uiScale.Scale = s
	gui.Size = UDim2.fromScale(1 / s, 1 / s)
end
updateScale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

---------------------------------------------------------------------------
-- Notificaciones
---------------------------------------------------------------------------
local toastArea = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -150),
	Size = UDim2.fromOffset(340, 400),
	BackgroundTransparency = 1,
	Parent = gui,
}, { listLayout(nil, 6, { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right }) })

local KIND_COLORS = { good = THEME.green, bad = THEME.red, warn = THEME.yellow, info = THEME.blue }
local toastCount = 0

local function notify(message, kind)
	toastCount += 1
	local toast = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.bg,
		BackgroundTransparency = 0.08,
		LayoutOrder = toastCount,
		Parent = toastArea,
	}, {
		corner(8),
		padding(10),
		create("UIStroke", { Color = KIND_COLORS[kind] or THEME.blue, Thickness = 2 }),
		text({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = tostring(message) }),
	})
	task.delay(5, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
	local toasts = {}
	for _, child in toastArea:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 6 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
end
Remotes.Notify.OnClientEvent:Connect(notify)

---------------------------------------------------------------------------
-- Snapshot (precios, mejoras, empleados...)
---------------------------------------------------------------------------
local snapshot = { prices = {}, market = {}, perks = {}, expansions = {}, employees = {}, candidates = {}, hireLimit = 0, custom = {}, room = {} }
local snapshotListeners = {}

local function applySnapshot(data)
	if typeof(data) ~= "table" then
		return
	end
	for k, v in data do
		snapshot[k] = v
	end
	for _, fn in snapshotListeners do
		fn()
	end
end
Remotes.Snapshot.OnClientEvent:Connect(applySnapshot)
task.spawn(function()
	local ok, data = pcall(function()
		return Remotes.GetSnapshot:InvokeServer()
	end)
	if ok then
		applySnapshot(data)
	end
end)

---------------------------------------------------------------------------
-- HUD superior
---------------------------------------------------------------------------
local hud = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, {
	corner(10),
	create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	listLayout(Enum.FillDirection.Horizontal, 14, { VerticalAlignment = Enum.VerticalAlignment.Center }),
})
local function chip(order)
	return text({ Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Font = Enum.Font.GothamBold, TextSize = 15, TextWrapped = false, LayoutOrder = order, Parent = hud })
end
local moneyChip, dayChip, clockChip, phaseChip, levelChip, fpChip, satChip, debtChip = chip(1), chip(2), chip(3), chip(4), chip(5), chip(6), chip(7), chip(8)
moneyChip.LayoutOrder = 0
local bankChip = chip(1) -- plata guardada en Tesoro Digital

local xpBack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 51),
	Size = UDim2.fromOffset(260, 6),
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.2,
	Parent = gui,
}, { corner(3) })
local xpFill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.yellow, Parent = xpBack }, { corner(3) })

local PHASE_TEXT = { Cerrado = "🔒 Cerrado", Abierto = "🟢 Abierto", Cierre = "🌙 Cierre" }
local function refreshHud()
	local money = status:GetAttribute("Money") or 0
	moneyChip.Text = "💰 " .. fmt(money)
	moneyChip.TextColor3 = money < 0 and THEME.red or THEME.text
	local bank = status:GetAttribute("Bank") or 0
	bankChip.Visible = bank > 0
	bankChip.Text = "🏛 " .. fmt(bank)
	bankChip.TextColor3 = TesoroLogo.TEAL
	dayChip.Text = "📅 " .. tostring(status:GetAttribute("Weekday") or "") .. " " .. tostring(status:GetAttribute("Day") or 1)
	clockChip.Text = "🕒 " .. Config.formatClock((status:GetAttribute("Clock") or 450) / 60)
	phaseChip.Text = PHASE_TEXT[status:GetAttribute("Phase")] or "..."
	levelChip.Text = "⭐ Nv " .. tostring(status:GetAttribute("Level") or 1)
	fpChip.Text = "🏆 " .. tostring(status:GetAttribute("FP") or 0) .. " FP"
	satChip.Text = "😊 " .. tostring(status:GetAttribute("Satisfaction") or 0) .. "%"
	local debt = status:GetAttribute("Debt") or 0
	local overdue = status:GetAttribute("Overdue") or 0
	debtChip.Visible = debt > 0
	debtChip.Text = overdue > 0 and ("🏦 ¡ATRASADO " .. fmt(overdue) .. "!") or ("🏦 Deuda " .. fmt(debt))
	debtChip.TextColor3 = overdue > 0 and THEME.red or THEME.yellow
	local xp, xpNext = status:GetAttribute("XP") or 0, status:GetAttribute("XPNext") or 100
	xpFill.Size = UDim2.fromScale(math.clamp(xp / math.max(xpNext, 1), 0, 1), 1)
end
for _, attr in { "Money", "Bank", "Day", "Weekday", "Clock", "Phase", "Level", "XP", "XPNext", "FP", "Satisfaction", "Debt", "Overdue" } do
	status:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
refreshHud()

---------------------------------------------------------------------------
-- Ventanas
---------------------------------------------------------------------------
local windows = {}

local function anyWindowOpen()
	for _, w in windows do
		if w.Visible then
			return true
		end
	end
	return false
end

local function makeWindow(name, title, maxWidth, maxHeight, props)
	-- Pegadas abajo para no chocar con el chat de Roblox (arriba a la izquierda)
	local base = {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromScale(0.94, 0.8),
		BackgroundColor3 = THEME.bg,
		Visible = false,
		Parent = gui,
	}
	for k, v in props or {} do
		base[k] = v
	end
	local win = create("Frame", base, {
		corner(12),
		create("UIStroke", { Color = THEME.stroke, Thickness = 1.5 }),
		create("UISizeConstraint", { MaxSize = Vector2.new(maxWidth, maxHeight) }),
		create("TextButton", { Name = "ModalCatcher", Modal = true, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(0, 0) }),
	})
	local titleLabel = text({ Name = "Title", Text = title, Font = Enum.Font.GothamBold, TextSize = 20, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -70, 0, 48), TextWrapped = false, Parent = win })
	local close = button("✕", THEME.red, { Size = UDim2.fromOffset(36, 36), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Parent = win })
	close.Activated:Connect(function()
		win.Visible = false
	end)
	local body = create("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 1, -62), Parent = win })
	table.insert(windows, win)
	return win, body, titleLabel
end

---------------------------------------------------------------------------
-- Mira, pista y resaltado
---------------------------------------------------------------------------
local crosshair = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(6, 6),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Parent = gui,
}, { corner(3), create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.4 }) })
local hintLabel = text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 18),
	Size = UDim2.fromOffset(520, 44),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBold,
	TextStrokeTransparency = 0.4,
	TextSize = 16,
	Text = "",
	Parent = gui,
})
local highlight = Instance.new("SelectionBox")
highlight.Color3 = Color3.fromRGB(80, 255, 140)
highlight.LineThickness = 0.03
highlight.SurfaceTransparency = 1
highlight.Parent = workspace.CurrentCamera

---------------------------------------------------------------------------
-- Barra de la caja que llevás en la mano + botones táctiles
---------------------------------------------------------------------------
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local carryBar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.fromOffset(0, 40),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = gui,
}, { corner(10), create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }) })
local carryText = text({ Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, Parent = carryBar })

local function refreshCarry()
	local units = player:GetAttribute("CarryUnits")
	carryBar.Visible = units ~= nil
	if units and player:GetAttribute("CarryKind") == "crate" then
		carryText.Text = "📦 Mueble: " .. (player:GetAttribute("CarryName") or "") .. "   ·   Apuntá al piso y hacé click para armarlo   ·   R: rotar   ·   F: soltar"
	elseif units then
		local name = player:GetAttribute("CarryName") or "Caja"
		carryText.Text = units > 0 and string.format("📦 %s x%d   ·   Click: poner   ·   Click der.: sacar   ·   F: soltar", name, units)
			or "📦 Caja vacía   ·   Click der. en un nivel: sacar productos   ·   Reciclala en el tacho azul   ·   F: soltar"
	end
end
for _, attr in { "CarryUnits", "CarryName", "CarryKind" } do
	player:GetAttributeChangedSignal(attr):Connect(refreshCarry)
end

local touchBar = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -170, 1, -30),
	Size = UDim2.fromOffset(250, 60),
	BackgroundTransparency = 1,
	Visible = isTouch,
	Parent = gui,
}, { listLayout(Enum.FillDirection.Horizontal, 8) })
local touchPrimary = button("Usar", THEME.green, { Size = UDim2.fromOffset(78, 56), LayoutOrder = 1, Parent = touchBar })
local touchSecondary = button("Sacar", THEME.blue, { Size = UDim2.fromOffset(78, 56), LayoutOrder = 2, Parent = touchBar })
local touchDrop = button("Soltar", THEME.yellow, { Size = UDim2.fromOffset(78, 56), LayoutOrder = 3, Parent = touchBar })

---------------------------------------------------------------------------
-- Interacciones con el mundo (apuntar + click)
---------------------------------------------------------------------------
local builder -- se define más abajo
local cursorMode = false -- Alt: muestra la flecha del mouse (y libera el mouse de la mira)
local cursorCatcher = create("TextButton", { Name = "CursorCatcher", Modal = true, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(0, 0), Visible = false, Parent = gui })

local function carriedBox()
	if player:GetAttribute("CarryUnits") == nil then
		return nil
	end
	local boxes = workspace:FindFirstChild("Boxes")
	if not boxes then
		return nil
	end
	for _, b in boxes:GetChildren() do
		if b:GetAttribute("CarrierId") == player.UserId then
			return b
		end
	end
	return nil
end

local function equippedTool()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

-- point: nil/false = automático (mira o mouse), true = centro, Vector2 = punto tocado en la pantalla
local function aimRay(point)
	local cam = workspace.CurrentCamera
	if typeof(point) == "Vector2" then
		return cam:ScreenPointToRay(point.X, point.Y)
	end
	local p
	-- Con la flecha visible (Alt/C) se apunta con el mouse; con la flecha oculta, con el punto del centro
	if point == true or isTouch or (not cursorMode and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter) then
		p = cam.ViewportSize / 2
	else
		p = UserInputService:GetMouseLocation()
	end
	return cam:ViewportPointToRay(p.X, p.Y)
end

local function aimRaycast(point, params, distance)
	local ray = aimRay(point)
	return workspace:Raycast(ray.Origin, ray.Direction * (distance or 20), params)
end

local function interactParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	local box = carriedBox()
	if box then
		table.insert(list, box)
	end
	params.FilterDescendantsInstances = list
	return params
end

local function resolve(instance)
	local current = instance
	for _ = 1, 4 do
		if not current or current == workspace then
			return nil
		end
		if current:GetAttribute("Kind") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function currentTarget(useCenter)
	local result = aimRaycast(useCenter, interactParams())
	if not result then
		return nil
	end
	local target = resolve(result.Instance)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not target or not root or (root.Position - result.Position).Magnitude > Config.INTERACT_DISTANCE then
		return nil
	end
	return target
end

local function storedBoxAt(fixtureId, slotIndex)
	local boxes = workspace:FindFirstChild("Boxes")
	if not boxes then
		return nil
	end
	for _, b in boxes:GetChildren() do
		if b:GetAttribute("StorageFixture") == fixtureId and b:GetAttribute("StorageSlot") == slotIndex then
			return b
		end
	end
	return nil
end

local function actionsFor(target)
	local kind = target:GetAttribute("Kind")
	local carrying = player:GetAttribute("CarryUnits") ~= nil
	if kind == "checkouttoggle" then
		return "toggle", nil
	end
	-- Objetos que se usan con click (cartel de abrir/cerrar, mostrador de pedidos...)
	if kind == "use" then
		return "use", nil
	end
	if carrying and player:GetAttribute("CarryKind") == "crate" then
		return nil, nil
	end
	if carrying then
		if kind == "recycle" then
			return "recycle", nil
		elseif kind == "slot" then
			return "place", "take"
		elseif kind == "storageslot" then
			if storedBoxAt(target:GetAttribute("FixtureId"), target:GetAttribute("Slot")) then
				return nil, nil
			end
			return "store", nil
		end
		return nil, nil
	end
	if kind == "box" or kind == "crate" then
		return "pickup", nil
	elseif kind == "dropped" then
		return "recover", nil
	elseif kind == "storageslot" then
		if storedBoxAt(target:GetAttribute("FixtureId"), target:GetAttribute("Slot")) then
			return "pickupStored", nil
		end
	elseif kind == "beltitem" then
		return "scan", nil
	elseif kind == "card" or kind == "cash" then
		return "pay", nil
	end
	return nil, nil
end

local function productName(id)
	local prod = id and Config.ProductsById[id]
	return prod and prod.name or nil
end

local function hintFor(target)
	local kind = target:GetAttribute("Kind")
	local p, s = actionsFor(target)
	if p == "place" then
		local units = player:GetAttribute("CarryUnits") or 0
		local here = productName(target:GetAttribute("ProductId"))
		local line = units > 0 and ("Click: poner " .. (player:GetAttribute("CarryName") or "")) or "Caja vacía"
		return line .. (s and "   ·   Click der.: sacar" or "") .. (here and ("\n" .. here .. " · " .. fmt(snapshot.prices[target:GetAttribute("ProductId")] or 0)) or "")
	elseif p == "store" then
		return "Click: guardar la caja en el estante"
	elseif p == "pickup" and kind == "crate" then
		local def = Config.Fixtures[target:GetAttribute("FixtureType") or ""]
		return "Click: levantar la caja del mueble (" .. (def and def.name or "mueble") .. ")"
	elseif p == "pickup" then
		local name = productName(target:GetAttribute("ProductId"))
		return "Click: levantar caja" .. (name and (" (" .. name .. " x" .. (target:GetAttribute("Units") or 0) .. ")") or " (vacía)")
	elseif p == "recycle" then
		return "Click: reciclar la caja vacía (+" .. fmt(snapshot.perks.recycling and Config.RECYCLE_VALUE_PERK or Config.RECYCLE_VALUE) .. ")"
	elseif p == "recover" then
		return "Click: recuperar " .. (target:GetAttribute("ProductName") or "el producto")
	elseif p == "use" then
		return target:GetAttribute("Hint") or ""
	elseif kind == "info" then
		return target:GetAttribute("Hint") or ""
	elseif p == "toggle" then
		local lamp = target.Parent and target.Parent:FindFirstChild("LaneLight")
		local open = lamp and lamp:GetAttribute("Open")
		return open == false and "Click: ABRIR esta caja" or "Click: CERRAR esta caja"
	elseif kind == "recycle" then
		return "Traé una caja vacía para reciclarla"
	elseif kind == "crate" then
		return "Soltá lo que llevás (F) para levantar esta caja"
	elseif p == "pickupStored" then
		local box = storedBoxAt(target:GetAttribute("FixtureId"), target:GetAttribute("Slot"))
		local name = box and productName(box:GetAttribute("ProductId"))
		return "Click: sacar caja del estante" .. (name and (" (" .. name .. ")") or "")
	elseif p == "scan" then
		return "Click: escanear " .. (target:GetAttribute("ProductName") or "")
	elseif p == "pay" then
		return kind == "card" and "Click: cobrar con tarjeta 💳" or "Click: cobrar en efectivo 💵"
	elseif kind == "slot" then
		local id = target:GetAttribute("ProductId")
		if id and id ~= "" then
			return string.format("%s · %s (stock %d)", productName(id) or "", fmt(snapshot.prices[id] or 0), target:GetAttribute("Stock") or 0)
		end
		return "Nivel vacío: traé una caja para reponer"
	end
	return ""
end

local function perform(action, target)
	if action == "place" or action == "take" or action == "store" or action == "pickupStored" then
		Remotes.Action:FireServer(action, target:GetAttribute("FixtureId"), target:GetAttribute("Slot"))
	elseif action == "pickup" then
		Remotes.Action:FireServer("pickup", target)
	elseif action == "scan" then
		Remotes.Action:FireServer("scan", target:GetAttribute("CheckoutId"), target:GetAttribute("ItemId"))
	elseif action == "pay" then
		Remotes.Action:FireServer("pay", target:GetAttribute("CheckoutId"))
	elseif action == "recycle" then
		Remotes.Action:FireServer("recycle", target)
	elseif action == "recover" then
		Remotes.Action:FireServer("recover", target)
	elseif action == "toggle" then
		Remotes.Action:FireServer("togglecheckout", target:GetAttribute("CheckoutId"))
	elseif action == "use" then
		Remotes.Action:FireServer("use", target)
	end
end

local REPEATABLE = { place = true, take = true, scan = true }
local hold = { primary = false, secondary = false, useCenter = false, nextRepeat = 0 }

local function interactionBlocked()
	return anyWindowOpen() or (builder and builder.active) or equippedTool() ~= nil
end

local function tryAction(which, useCenter)
	if interactionBlocked() then
		return nil
	end
	local target = currentTarget(useCenter)
	if not target then
		return nil
	end
	local p, s = actionsFor(target)
	local action = which == "primary" and p or s
	if action then
		perform(action, target)
	end
	return action
end

local function startHold(which, useCenter)
	local action = tryAction(which, useCenter)
	hold[which] = action ~= nil and REPEATABLE[action] == true
	hold.useCenter = useCenter
	hold.nextRepeat = os.clock() + 0.3
end

touchPrimary.MouseButton1Down:Connect(function()
	startHold("primary", true)
end)
touchPrimary.MouseButton1Up:Connect(function()
	hold.primary = false
end)
touchSecondary.MouseButton1Down:Connect(function()
	startHold("secondary", true)
end)
touchSecondary.MouseButton1Up:Connect(function()
	hold.secondary = false
end)
touchDrop.Activated:Connect(function()
	Remotes.Action:FireServer("drop")
end)

---------------------------------------------------------------------------
-- Pistola de precios
---------------------------------------------------------------------------
local gunPanel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(380, 172),
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.08,
	Visible = false,
	Parent = gui,
}, { corner(12), create("UIStroke", { Color = THEME.yellow, Thickness = 2 }) })
local gunTitle = text({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22), Font = Enum.Font.GothamBold, TextSize = 17, Parent = gunPanel })
local gunBuy = text({ Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 20), TextSize = 15, TextColor3 = THEME.muted, Parent = gunPanel })
local gunPrice = text({ Position = UDim2.fromOffset(14, 52), Size = UDim2.new(1, -28, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 24, Parent = gunPanel })
local gunProfit = text({ Position = UDim2.fromOffset(14, 82), Size = UDim2.new(1, -28, 0, 22), Font = Enum.Font.GothamBold, TextSize = 16, Parent = gunPanel })
local gunButtons = create("Frame", { Position = UDim2.fromOffset(14, 108), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1, Parent = gunPanel }, { listLayout(Enum.FillDirection.Horizontal, 6) })
local gunHint = text({ Position = UDim2.fromOffset(14, 146), Size = UDim2.new(1, -28, 0, 18), TextSize = 12, TextColor3 = THEME.muted, Text = "Rueda del mouse o Z / X: ±$0.10   ·   con Shift: ±$0.01", Parent = gunPanel })
local gun = { productId = nil, pending = nil, sendAt = 0 }

local function gunShow()
	local id = gun.productId
	if not id then
		gunTitle.Text = "🔫 Pistola de precios"
		gunBuy.Text = "Apuntá a un producto del estante o a una caja."
		gunPrice.Text = ""
		gunProfit.Text = ""
		return
	end
	local market = snapshot.market[id] or Config.ProductsById[id].market
	local price = gun.pending or snapshot.prices[id] or market
	local profit = price - market
	local ratio = price / market
	gunTitle.Text = "🔫 " .. productName(id)
	gunBuy.Text = "Lo comprás a:  " .. fmt(market)
	gunPrice.Text = "Lo vendés a:  " .. fmt(price)
	local note = ""
	if ratio >= Config.PRICE_LIMIT_RATIO then
		note = "   ·   ¡nadie lo compra!"
	elseif ratio > Config.PRICE_COMFORT_RATIO then
		note = "   ·   caro: algunos no lo compran"
	end
	gunProfit.Text = string.format("Ganancia: %s por unidad (%+d%%)%s", fmt(profit), math.floor((ratio - 1) * 100 + 0.5), note)
	gunProfit.TextColor3 = profit <= 0 and THEME.red or (ratio > Config.PRICE_COMFORT_RATIO and THEME.yellow or THEME.green)
end

local function gunAdjust(delta)
	local id = gun.productId
	if not id then
		return
	end
	local market = snapshot.market[id] or Config.ProductsById[id].market
	local base = gun.pending or snapshot.prices[id] or market
	gun.pending = math.clamp(base + delta, 1, market * 5)
	gun.sendAt = os.clock() + 0.35
	gunShow()
end

local function gunSet(value)
	if not gun.productId then
		return
	end
	gun.pending = math.max(1, math.floor(value + 0.5))
	gun.sendAt = os.clock() + 0.1
	gunShow()
end

local function gunSend()
	local id, value = gun.productId, gun.pending
	gun.pending = nil
	if not id or not value then
		return
	end
	task.spawn(function()
		local ok, result = safeInvoke(Remotes.SetPrice, id, value)
		if ok and type(result) == "number" then
			snapshot.prices[id] = result
			_G.SMT_PRICE_SET = true
		elseif not ok then
			notify(result or "No se pudo cambiar el precio", "bad")
		end
		gunShow()
	end)
end

for i, spec in { { "−", -10, 56 }, { "+", 10, 56 }, { "Recomendado", "rec", 116 }, { "Máximo", "max", 96 } } do
	local b = button(spec[1], i <= 2 and THEME.panel2 or THEME.blue, { Size = UDim2.fromOffset(spec[3], 32), TextSize = 14, LayoutOrder = i, Parent = gunButtons })
	b.Activated:Connect(function()
		local id = gun.productId
		if not id then
			return
		end
		local market = snapshot.market[id] or Config.ProductsById[id].market
		if spec[2] == "rec" then
			gunSet(market * 1.3) -- lo más caro sin perder clientes
		elseif spec[2] == "max" then
			gunSet(market * Config.PRICE_LIMIT_RATIO - 1)
		else
			gunAdjust(spec[2])
		end
	end)
end

local function gunEquipped()
	local tool = equippedTool()
	return tool and tool.Name == "Pistola de precios"
end

local function gunStep()
	local active = gunEquipped() and not anyWindowOpen()
	gunPanel.Visible = active
	if not active then
		if gun.pending then
			gunSend()
		end
		return
	end
	local result = aimRaycast(false, interactParams(), 20)
	local target = result and resolve(result.Instance)
	local id = target and target:GetAttribute("ProductId")
	if id == "" then
		id = nil
	end
	if id ~= gun.productId then
		if gun.pending then
			gunSend()
		end
		gun.productId = id and Config.ProductsById[id] and id or nil
		gunShow()
	end
	if gun.pending and os.clock() >= gun.sendAt then
		gunSend()
	end
end

---------------------------------------------------------------------------
-- Caja registradora: panel del cajero y ventana de cobro
---------------------------------------------------------------------------
local checkoutPanel = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 110),
	Size = UDim2.fromOffset(300, 142),
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, { corner(10), create("UIStroke", { Color = THEME.blue, Thickness = 2 }) })
local checkoutTitle = text({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 24), Font = Enum.Font.GothamBold, TextSize = 17, Parent = checkoutPanel })
local checkoutInfo = text({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 66), TextSize = 14, TextYAlignment = Enum.TextYAlignment.Top, Parent = checkoutPanel })
local checkoutToggle = button("Cerrar caja", THEME.red, { Position = UDim2.fromOffset(12, 104), Size = UDim2.new(1, -24, 0, 30), TextSize = 14, Parent = checkoutPanel })
local currentCheckoutId
checkoutToggle.Activated:Connect(function()
	if currentCheckoutId then
		Remotes.Action:FireServer("togglecheckout", currentCheckoutId)
	end
end)

Remotes.CheckoutState.OnClientEvent:Connect(function(data)
	if not data then
		checkoutPanel.Visible = false
		return
	end
	checkoutPanel.Visible = true
	currentCheckoutId = data.id
	checkoutToggle.Text = data.open and "Cerrar caja (no entran más clientes)" or "Abrir caja"
	checkoutToggle.BackgroundColor3 = data.open and THEME.red or THEME.green
	checkoutTitle.Text = "🧾 Atendiendo la caja " .. tostring(data.number) .. (data.open and "" or " (cerrada)")
	if data.stage == "idle" then
		checkoutInfo.Text = "Esperando clientes...\nQuedate parado detrás de la caja."
	elseif data.stage == "scanning" then
		checkoutInfo.Text = string.format("Escaneá los productos de la cinta (click en cada uno).\n%d/%d artículos · %s", data.scanned or 0, data.count or 0, fmt(data.total or 0))
	elseif data.stage == "payment" then
		checkoutInfo.Text = string.format("Total %s\nHacé click en %s del cliente para cobrar.", fmt(data.total or 0), data.method == "card" and "la TARJETA 💳" or "el EFECTIVO 💵")
	end
end)

local payWin, payBody, payTitle = makeWindow("Payment", "Cobro", 420, 540)
local payInfo = text({ Size = UDim2.new(1, 0, 0, 76), TextSize = 17, RichText = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = payBody })
local payDisplay = text({
	Position = UDim2.fromOffset(0, 82),
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(15, 35, 25),
	TextColor3 = Color3.fromRGB(120, 255, 150),
	Font = Enum.Font.Code,
	TextSize = 30,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = payBody,
}, nil)
corner(8).Parent = payDisplay
create("UIPadding", { PaddingRight = UDim.new(0, 12) }).Parent = payDisplay
local payGrid = create("Frame", { Position = UDim2.fromOffset(0, 142), Size = UDim2.new(1, 0, 0, 250), BackgroundTransparency = 1, Parent = payBody }, {
	create("UIGridLayout", { CellSize = UDim2.new(0.333, -6, 0, 54), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local payConfirm = button("Cobrar", THEME.green, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46), TextSize = 18, Parent = payBody })

local payment = nil -- { data, typed, change }

local function sumChange()
	local total = 0
	for _, v in payment and payment.change or {} do
		total += v
	end
	return total
end

local function renderPayment()
	if not payment then
		return
	end
	local d = payment.data
	if d.method == "card" then
		payTitle.Text = "💳 Terminal de tarjeta"
		payInfo.Text = "Total a cobrar: <b>" .. fmt(d.total) .. "</b>\nTipeá el monto exacto y cobrá."
		payDisplay.Text = payment.typed == "" and "0.00" or payment.typed
		payConfirm.Text = "Cobrar"
	else
		payTitle.Text = "💵 Caja de efectivo"
		payInfo.Text = string.format("El cliente te da <b>%s</b> · Total <b>%s</b>\nVuelto a entregar: <b>%s</b>   (click der. saca)", fmt(d.given), fmt(d.total), fmt(d.given - d.total))
		payDisplay.Text = fmt(sumChange())
		payConfirm.Text = "Entregar vuelto"
	end
end

local function buildPaymentButtons()
	clearList(payGrid)
	local d = payment.data
	if d.method == "card" then
		for i, key in { "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫" } do
			local b = button(key, THEME.panel2, { LayoutOrder = i, TextSize = 22, Parent = payGrid })
			b.Activated:Connect(function()
				if key == "⌫" then
					payment.typed = payment.typed:sub(1, -2)
				elseif #payment.typed < 10 then
					payment.typed ..= key
				end
				renderPayment()
			end)
		end
	else
		for i, value in Config.CASH_DENOMINATIONS do
			local label = value >= 100 and ("$" .. math.floor(value / 100)) or (value .. "¢")
			local b = button(label, value >= 100 and THEME.green or THEME.yellow, { LayoutOrder = i, TextSize = 18, Parent = payGrid })
			b.Activated:Connect(function()
				table.insert(payment.change, value)
				renderPayment()
			end)
			b.MouseButton2Click:Connect(function()
				local idx = table.find(payment.change, value)
				if idx then
					table.remove(payment.change, idx)
					renderPayment()
				end
			end)
		end
		local undo = button("↶", THEME.panel2, { LayoutOrder = 99, TextSize = 22, Parent = payGrid })
		undo.Activated:Connect(function()
			table.remove(payment.change)
			renderPayment()
		end)
	end
end

local function confirmPayment()
	if not payment then
		return
	end
	local amount
	if payment.data.method == "card" then
		local value = tonumber(payment.typed)
		if not value then
			notify("Tipeá el monto, por ejemplo 12.50", "warn")
			return
		end
		amount = math.floor(value * 100 + 0.5)
	else
		amount = sumChange()
	end
	local ok, msg = safeInvoke(Remotes.ConfirmPayment, payment.data.checkoutId, amount)
	if not ok then
		notify(msg or "No se pudo cobrar", "bad")
	else
		_G.SMT_CHARGED = true
		if msg then
			notify(msg, "warn")
		end
	end
end
payConfirm.Activated:Connect(confirmPayment)

-- Mientras está abierta la caja, las teclas 1-9 no cambian de herramienta
payWin:GetPropertyChangedSignal("Visible"):Connect(function()
	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not payWin.Visible)
	end)
end)

-- Tipear el monto de la tarjeta con el teclado
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not payWin.Visible or not payment or payment.data.method ~= "card" then
		return
	end
	local map = {
		[Enum.KeyCode.Zero] = "0", [Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2", [Enum.KeyCode.Three] = "3",
		[Enum.KeyCode.Four] = "4", [Enum.KeyCode.Five] = "5", [Enum.KeyCode.Six] = "6", [Enum.KeyCode.Seven] = "7",
		[Enum.KeyCode.Eight] = "8", [Enum.KeyCode.Nine] = "9", [Enum.KeyCode.Period] = ".",
		[Enum.KeyCode.KeypadZero] = "0", [Enum.KeyCode.KeypadOne] = "1", [Enum.KeyCode.KeypadTwo] = "2",
		[Enum.KeyCode.KeypadThree] = "3", [Enum.KeyCode.KeypadFour] = "4", [Enum.KeyCode.KeypadFive] = "5",
		[Enum.KeyCode.KeypadSix] = "6", [Enum.KeyCode.KeypadSeven] = "7", [Enum.KeyCode.KeypadEight] = "8",
		[Enum.KeyCode.KeypadNine] = "9", [Enum.KeyCode.KeypadPeriod] = ".",
	}
	local key = map[input.KeyCode]
	if key and #payment.typed < 10 then
		payment.typed ..= key
		renderPayment()
	elseif input.KeyCode == Enum.KeyCode.Backspace then
		payment.typed = payment.typed:sub(1, -2)
		renderPayment()
	elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		confirmPayment()
	end
end)

Remotes.PaymentOpen.OnClientEvent:Connect(function(data)
	payment = { data = data, typed = "", change = {} }
	buildPaymentButtons()
	renderPayment()
	payWin.Visible = true
end)
Remotes.PaymentClose.OnClientEvent:Connect(function()
	payment = nil
	payWin.Visible = false
end)

---------------------------------------------------------------------------
-- Oficina: Pedidos, Ampliaciones, Préstamos, Franquicia, Empleados, Personalizar
---------------------------------------------------------------------------
local officeWin, officeBody = makeWindow("Office", "🗂 Oficina del gerente", 900, 580)
local tabBar = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = officeBody }, { listLayout(Enum.FillDirection.Horizontal, 6) })
local officeList = scrollList(officeBody, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44) })
local cartBar = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundColor3 = THEME.panel,
	Visible = false,
	Parent = officeBody,
}, { corner(8) })
local cartLabel = text({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -300, 1, 0), Font = Enum.Font.GothamBold, TextSize = 16, Parent = cartBar })
local cartClear = button("Vaciar", THEME.panel2, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -170, 0.5, 0), Size = UDim2.fromOffset(90, 36), Parent = cartBar })
local cartBuy = button("Comprar pedido", THEME.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(154, 36), Parent = cartBar })

local currentTab = "orders"
local tabButtons = {}
local renderers = {}
local cart = {}

local function renderOffice()
	for id, b in tabButtons do
		b.BackgroundColor3 = id == currentTab and THEME.green or THEME.panel2
	end
	cartBar.Visible = currentTab == "orders"
	officeList.Size = UDim2.new(1, 0, 1, currentTab == "orders" and -100 or -44)
	clearList(officeList)
	renderers[currentTab]()
end

for i, tab in {
	{ "orders", "📦 Pedidos" }, { "expansions", "🏗 Ampliaciones" }, { "loans", "🏦 Préstamos" },
	{ "franchise", "⭐ Franquicia" }, { "employees", "👷 Empleados" }, { "custom", "🎨 Personalizar" },
} do
	local b = button(tab[2], THEME.panel2, { Size = UDim2.fromOffset(140, 34), TextSize = 14, LayoutOrder = i, Parent = tabBar })
	tabButtons[tab[1]] = b
	b.Activated:Connect(function()
		currentTab = tab[1]
		renderOffice()
	end)
end

local function header(textValue, order)
	text({ Text = textValue, TextColor3 = THEME.muted, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, RichText = true, Parent = officeList })
end

local function section(textValue, order)
	text({ Text = textValue, Font = Enum.Font.GothamBold, TextSize = 17, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, Parent = officeList })
end

local function swatch(parent, color, x)
	create("Frame", { Size = UDim2.fromOffset(10, 40), Position = UDim2.fromOffset(x or 8, 8), BackgroundColor3 = color, Parent = parent }, { corner(4) })
end

local function rightControls(parent, width)
	return create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(width, 36),
		Parent = parent,
	}, { listLayout(Enum.FillDirection.Horizontal, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center }) })
end

local function refreshCart()
	local boxes, cost = 0, 0
	for id, n in cart do
		local prod = Config.ProductsById[id]
		boxes += n
		cost += prod.unitsPerBox * (snapshot.market[id] or prod.market) * n
	end
	cartLabel.Text = boxes > 0 and string.format("🛒 %d caja(s) · %s + %s de envío = %s", boxes, fmt(cost), fmt(Config.DELIVERY_FEE), fmt(cost + Config.DELIVERY_FEE)) or "🛒 Carrito vacío"
end

local STORAGE_ICON = { fridge = "  ❄ heladera", freezer = "  🧊 freezer", shelf = "", produce = "  🧺 verdulería", appliance = "  🔌 góndola electro" }

renderers.orders = function()
	header("Los pedidos llegan a la <b>ZONA DE DESCARGA</b> (afuera, frente al portón del depósito). Comprás a precio de mercado.", 0)
	local order = 1
	for _, cat in Config.Categories do
		local unlocked = cat.id == "basic1" or snapshot.perks[cat.id]
		section(cat.name .. (unlocked and "" or "   🔒 desbloquealo en Franquicia"), order)
		order += 1
		if unlocked then
			for _, prod in Config.Products do
				if prod.category == cat.id then
					local r = row(officeList, order, 56)
					order += 1
					local market = snapshot.market[prod.id] or prod.market
					swatch(r, prod.color)
					text({ Text = prod.name .. STORAGE_ICON[prod.storage], Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(28, 6), Size = UDim2.new(0.5, 0, 0, 22), Parent = r })
					local info = string.format("Caja x%d · %s (%s c/u)", prod.unitsPerBox, fmt(prod.unitsPerBox * market), fmt(market))
					if snapshot.stockShelf then
						info ..= string.format("   ·   Tienda %d · Depósito %d", snapshot.stockShelf[prod.id] or 0, snapshot.stockStorage and snapshot.stockStorage[prod.id] or 0)
					end
					text({ Text = info, TextColor3 = THEME.muted, TextSize = 13, Position = UDim2.fromOffset(28, 28), Size = UDim2.new(1, -220, 0, 20), Parent = r })
					local controls = rightControls(r, 150)
					local minus = button("−", THEME.panel2, { Size = UDim2.fromOffset(36, 32), LayoutOrder = 1, Parent = controls })
					local qty = text({ Text = tostring(cart[prod.id] or 0), Size = UDim2.fromOffset(40, 32), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, LayoutOrder = 2, Parent = controls })
					local plus = button("+", THEME.green, { Size = UDim2.fromOffset(36, 32), LayoutOrder = 3, Parent = controls })
					minus.Activated:Connect(function()
						local n = (cart[prod.id] or 0) - 1
						cart[prod.id] = n > 0 and n or nil
						qty.Text = tostring(cart[prod.id] or 0)
						refreshCart()
					end)
					plus.Activated:Connect(function()
						cart[prod.id] = math.min((cart[prod.id] or 0) + 1, Config.MAX_BOXES_PER_ORDER)
						qty.Text = tostring(cart[prod.id])
						refreshCart()
					end)
				end
			end
		end
	end
	refreshCart()
end

cartClear.Activated:Connect(function()
	cart = {}
	renderOffice()
end)
cartBuy.Activated:Connect(function()
	local ok, msg = safeInvoke(Remotes.PlaceOrder, cart)
	notify(msg or (ok and "Pedido realizado" or "No se pudo pedir"), ok and "good" or "bad")
	if ok then
		cart = {}
		renderOffice()
	end
end)

renderers.expansions = function()
	header("Las ampliaciones abren más espacio para la tienda y el depósito. Se pagan con dinero.", 0)
	for i, exp in Config.Expansions do
		local r = row(officeList, i, 66)
		text({ Text = exp.name, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -200, 0, 22), Parent = r })
		text({ Text = exp.desc .. "  ·  " .. fmt(exp.cost), TextColor3 = THEME.muted, TextSize = 13, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -200, 0, 22), Parent = r })
		local owned = snapshot.expansions[exp.id]
		local locked = exp.requires and not snapshot.expansions[exp.requires]
		local b = button(owned and "✔ Comprada" or (locked and "🔒 Bloqueada" or "Comprar"), (owned or locked) and THEME.panel2 or THEME.green, {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 38), Parent = r,
		})
		if not owned then
			b.Activated:Connect(function()
				local ok, msg = safeInvoke(Remotes.BuyExpansion, exp.id)
				notify(msg or "", ok and "good" or "bad")
			end)
		end
	end
end

renderers.loans = function()
	local loan = snapshot.loan
	header("Si una cuota queda sin pagar, al día siguiente llegan <b>cobradores</b>: te persiguen, te pegan y se llevan la plata con 20% de recargo. Se los echa con " .. Config.COLLECTOR_HITS .. " escobazos cada uno (pero vuelven si la deuda sigue).", 0)
	if type(loan) == "table" then
		local def = Config.LoansById[loan.id]
		local r = row(officeList, 1, 150)
		text({
			Text = string.format("<b>%s</b>\nTe falta pagar: <b>%s</b>\nCuota diaria: %s (se cobra sola al cerrar el día)%s",
				def and def.name or "Préstamo", fmt(loan.remaining), fmt(loan.perDay),
				(loan.overdue or 0) > 0 and ("\n<font color=\"#ff6b6b\"><b>⚠️ Atrasado: " .. fmt(loan.overdue) .. " — ¡vienen los cobradores!</b></font>") or ""),
			RichText = true, TextSize = 16, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 90), TextYAlignment = Enum.TextYAlignment.Top, Parent = r,
		})
		local payDue = button("Pagar atraso/cuota", THEME.yellow, { Position = UDim2.new(0, 12, 1, -46), Size = UDim2.fromOffset(200, 38), Parent = r })
		local payAll = button("Pagar todo (" .. fmt(loan.remaining) .. ")", THEME.green, { Position = UDim2.new(0, 222, 1, -46), Size = UDim2.fromOffset(240, 38), Parent = r })
		payDue.Activated:Connect(function()
			local ok, msg = safeInvoke(Remotes.PayLoan, math.max(loan.overdue or 0, loan.perDay))
			notify(msg or "", ok and "good" or "bad")
		end)
		payAll.Activated:Connect(function()
			local ok, msg = safeInvoke(Remotes.PayLoan, "all")
			notify(msg or "", ok and "good" or "bad")
		end)
		return
	end
	for i, def in Config.Loans do
		local total = math.floor(def.amount * (1 + def.interest) + 0.5)
		local r = row(officeList, i, 66)
		text({ Text = def.name .. " · " .. fmt(def.amount), Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -200, 0, 22), Parent = r })
		text({
			Text = string.format("Interés %d%% · Devolvés %s en %d días (%s por día)", math.floor(def.interest * 100 + 0.5), fmt(total), def.days, fmt(math.ceil(total / def.days))),
			TextColor3 = THEME.muted, TextSize = 13, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -200, 0, 22), Parent = r,
		})
		local b = button("Pedir préstamo", THEME.blue, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 38), Parent = r })
		b.Activated:Connect(function()
			local ok, msg = safeInvoke(Remotes.TakeLoan, def.id)
			notify(msg or "", ok and "good" or "bad")
		end)
	end
end

renderers.franchise = function()
	header("Tenés <b>🏆 " .. tostring(status:GetAttribute("FP") or 0) .. " puntos de franquicia</b>. Ganás 1 cada vez que el súper sube de nivel (cobrando clientes).", 0)
	local grid = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = officeList }, {
		create("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 104), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, perk in Config.Perks do
		local card = create("Frame", { BackgroundColor3 = THEME.panel, LayoutOrder = i, Parent = grid }, { corner(8) })
		local owned = snapshot.perks[perk.id]
		local locked = perk.requires and not snapshot.perks[perk.requires]
		text({ Text = perk.name, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 22), Parent = card })
		text({ Text = perk.desc, TextColor3 = THEME.muted, TextSize = 13, Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 34), TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
		local label = owned and "✔ Desbloqueado"
			or (locked and ("🔒 Requiere " .. Config.PerksById[perk.requires].name))
			or ("Desbloquear · " .. perk.cost .. " FP")
		local b = button(label, (owned or locked) and THEME.panel2 or THEME.green, { Position = UDim2.new(0, 10, 1, -40), Size = UDim2.new(1, -20, 0, 32), TextSize = 13, Parent = card })
		if not owned and not locked then
			b.Activated:Connect(function()
				local ok, msg = safeInvoke(Remotes.BuyPerk, perk.id)
				notify(msg or "", ok and "good" or "bad")
			end)
		end
	end
end

local ROLE_NAMES = {}
for _, role in Config.ROLES do
	ROLE_NAMES[role.id] = role.name
end

renderers.employees = function()
	local limit = snapshot.hireLimit or 0
	header(string.format("Empleados: <b>%d / %d</b> · Sueldo %s por día cada uno. %s", #(snapshot.employees or {}), limit, fmt(Config.EMPLOYEE_WAGE),
		limit == 0 and "Desbloqueá <b>Empleados I</b> en Franquicia para contratar." or ""), 0)
	section("Tu equipo", 1)
	local order = 2
	for _, e in snapshot.employees or {} do
		local r = row(officeList, order, 60)
		order += 1
		text({ Text = "👷 " .. e.name .. " · " .. (ROLE_NAMES[e.role] or e.role), Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.3, 0, 1, 0), Parent = r })
		local controls = rightControls(r, 560)
		for j, role in Config.ROLES do
			local available = not role.requires or snapshot.perks[role.requires]
			local b = button(role.name, e.role == role.id and THEME.green or (available and THEME.panel2 or THEME.bg), { Size = UDim2.fromOffset(100, 32), TextSize = 13, LayoutOrder = j, Parent = controls })
			b.Activated:Connect(function()
				local ok, msg = safeInvoke(Remotes.SetEmployeeRole, e.id, role.id)
				notify(msg or "", ok and "good" or "bad")
			end)
		end
		local fire = button("Despedir", THEME.red, { Size = UDim2.fromOffset(90, 32), TextSize = 13, LayoutOrder = 10, Parent = controls })
		fire.Activated:Connect(function()
			local ok, msg = safeInvoke(Remotes.FireEmployee, e.id)
			notify(msg or "", ok and "info" or "bad")
		end)
	end
	section("Candidatos", order)
	order += 1
	for _, c in snapshot.candidates or {} do
		local r = row(officeList, order, 52)
		order += 1
		text({ Text = "🙋 " .. c.name, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, 0, 1, 0), Parent = r })
		local b = button("Contratar", THEME.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(130, 34), Parent = r })
		b.Activated:Connect(function()
			local ok, msg = safeInvoke(Remotes.HireEmployee, c.id)
			notify(msg or "", ok and "good" or "bad")
		end)
	end
end

local function presetRow(title, order, presets, current, key, colorsOf)
	section(title, order * 10)
	local r = create("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, LayoutOrder = order * 10 + 1, Parent = officeList }, { listLayout(Enum.FillDirection.Horizontal, 8) })
	for i, preset in presets do
		local colors = colorsOf(preset)
		local b = button(preset.name or "", colors[1], { Size = UDim2.fromOffset(120, 54), TextColor3 = Color3.new(0, 0, 0), TextSize = 13, LayoutOrder = i, Parent = r })
		if colors[2] then
			create("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = colors[2], Parent = b }, { corner(4) })
		end
		if i == current then
			create("UIStroke", { Color = THEME.green, Thickness = 3 }).Parent = b
		end
		b.Activated:Connect(function()
			local ok, msg = safeInvoke(Remotes.Customize, key, i)
			if not ok then
				notify(msg or "No se pudo cambiar", "bad")
			end
		end)
	end
end

renderers.custom = function()
	local custom = snapshot.custom or {}
	header("Personalizá tu supermercado. Los muebles se mueven y venden con <b>B</b> o <b>TAB</b> (modo construcción).", 0)
	presetRow("Piso", 1, Config.FloorPresets, custom.floor, "floor", function(p)
		return { p.a, p.b }
	end)
	presetRow("Paredes", 2, Config.WallPresets, custom.walls, "walls", function(p)
		return { p.color, p.stripe }
	end)
	local signPresets = {}
	for i, c in Config.SignColors do
		signPresets[i] = { name = "", color = c }
	end
	presetRow("Color del cartel", 3, signPresets, custom.signColor, "signColor", function(p)
		return { p.color }
	end)

	section("Nombre del supermercado (lo ve todo el barrio)", 40)
	local nameRow = row(officeList, 41, 50)
	local nameBox = create("TextBox", {
		Text = custom.storeName or "", PlaceholderText = "SUPERMERCADO", ClearTextOnFocus = false, Font = Enum.Font.GothamBold,
		TextSize = 16, TextColor3 = THEME.text, BackgroundColor3 = THEME.panel2, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -150, 0, 34), Parent = nameRow,
	}, { corner(6) })
	local saveName = button("Guardar", THEME.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(120, 34), Parent = nameRow })
	saveName.Activated:Connect(function()
		local ok, msg = safeInvoke(Remotes.Customize, "storeName", nameBox.Text)
		notify(ok and "Nombre actualizado" or (msg or "No se pudo"), ok and "good" or "bad")
	end)

	local room = snapshot.room or {}
	section("Sala", 50)
	header("Sala: <b>" .. tostring(room.name or "?") .. "</b> · Dueño: <b>" .. tostring(room.ownerName or "?") .. "</b>. Pasale el nombre y la contraseña a tus amigos para que entren desde el menú.", 51)
	local passRow = row(officeList, 52, 50)
	local passBox = create("TextBox", {
		Text = "", PlaceholderText = "Nueva contraseña (solo el dueño)", ClearTextOnFocus = false, Font = Enum.Font.GothamMedium, TextSize = 16,
		TextColor3 = THEME.text, BackgroundColor3 = THEME.panel2, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -170, 0, 34), Parent = passRow,
	}, { corner(6) })
	local savePass = button("Cambiar clave", THEME.blue, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(140, 34), Parent = passRow })
	savePass.Activated:Connect(function()
		local ok, msg = safeInvoke(Remotes.SetRoomPassword, passBox.Text)
		notify(msg or "", ok and "good" or "bad")
		if ok then
			passBox.Text = ""
		end
	end)
end

table.insert(snapshotListeners, function()
	if officeWin.Visible and currentTab ~= "orders" and currentTab ~= "custom" then
		renderOffice()
	elseif officeWin.Visible and currentTab == "custom" then
		-- no re-dibujar mientras se escribe, solo si no hay foco
		if not UserInputService:GetFocusedTextBox() then
			renderOffice()
		end
	end
end)
status:GetAttributeChangedSignal("FP"):Connect(function()
	if officeWin.Visible and currentTab == "franchise" then
		renderOffice()
	end
end)

---------------------------------------------------------------------------
-- Cajero Tesoro Digital
---------------------------------------------------------------------------
local bankWin, bankBody = makeWindow("Bank", "", 560, 460)
local bankHeader = create("Frame", { BackgroundColor3 = TesoroLogo.NAVY, Size = UDim2.new(1, 0, 0, 70), Parent = bankBody }, {
	corner(10),
	create("UIGradient", { Color = ColorSequence.new(TesoroLogo.NAVY, TesoroLogo.NAVY2) }),
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
})
TesoroLogo.lockup(bankHeader, 54, Color3.new(1, 1, 1))
local bankInfo = text({ Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 56), RichText = true, TextSize = 17, Parent = bankBody })
text({
	Text = "La plata en el banco <b>no te la pueden robar</b> (cobradores ni patoteros) y gana " .. string.format("%.1f", Config.BANK_INTEREST * 100) .. "% por día. Si al cerrar no alcanza el efectivo para las cuentas, se debita solo.",
	RichText = true, TextColor3 = THEME.muted, TextSize = 13, Position = UDim2.fromOffset(0, 138), Size = UDim2.new(1, 0, 0, 40), Parent = bankBody,
})
local amountBox = create("TextBox", {
	Text = "", PlaceholderText = "Monto (ej: 250)", ClearTextOnFocus = false, Font = Enum.Font.GothamBold, TextSize = 16,
	TextColor3 = THEME.text, BackgroundColor3 = THEME.panel2, Position = UDim2.fromOffset(0, 186), Size = UDim2.new(1, 0, 0, 38), Parent = bankBody,
}, { corner(6) })
local function bankRow(y, label, action, color)
	local r = create("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 40), Parent = bankBody }, {
		listLayout(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	text({ Text = label, Font = Enum.Font.GothamBold, Size = UDim2.fromOffset(92, 40), LayoutOrder = 0, Parent = r })
	local function send(amount)
		local ok, msg = safeInvoke(Remotes.BankTransfer, action, amount)
		notify(msg or "", ok and "good" or "bad")
	end
	for i, preset in { { "$100", 10000 }, { "$1.000", 100000 }, { "Monto", "box" }, { "Todo", "all" } } do
		local b = button(preset[1], color, { Size = UDim2.fromOffset(100, 36), TextSize = 14, LayoutOrder = i, Parent = r })
		b.Activated:Connect(function()
			if preset[2] == "box" then
				local n = tonumber((amountBox.Text:gsub("[^%d%.]", "")))
				if not n or n <= 0 then
					notify("Escribí un monto válido arriba.", "bad")
					return
				end
				send(math.floor(n * 100 + 0.5))
			else
				send(preset[2])
			end
		end)
	end
end
bankRow(234, "Depositar", "deposit", THEME.green)
bankRow(282, "Retirar", "withdraw", THEME.blue)
local function refreshBank()
	bankInfo.Text = string.format("💰 Efectivo del súper: <b>%s</b>\n🏛 En Tesoro Digital: <b><font color=\"#1abc9c\">%s</font></b>", fmt(status:GetAttribute("Money") or 0), fmt(status:GetAttribute("Bank") or 0))
end
status:GetAttributeChangedSignal("Money"):Connect(refreshBank)
status:GetAttributeChangedSignal("Bank"):Connect(refreshBank)
Remotes.OpenBank.OnClientEvent:Connect(function()
	refreshBank()
	bankWin.Visible = true
end)

Remotes.OpenOffice.OnClientEvent:Connect(function(tab)
	currentTab = renderers[tab] and tab or "orders"
	officeWin.Visible = true
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.GetSnapshot:InvokeServer()
		end)
		if ok then
			applySnapshot(data)
		end
		renderOffice()
	end)
	renderOffice()
end)

---------------------------------------------------------------------------
-- Modo construcción (TAB)
---------------------------------------------------------------------------
builder = { active = false, crateMode = false, selected = nil, moving = nil, rot = 0, ghost = nil, hover = nil, lookHeld = false, sellConfirm = 0, x = 0, z = 0, valid = false }

local builderPanel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(0.96, 0, 0, 150),
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.08,
	Visible = false,
	Parent = gui,
}, { corner(12), create("UISizeConstraint", { MaxSize = Vector2.new(1100, 150) }) })
local builderCatcher = create("TextButton", { Modal = true, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(0, 0), Visible = false, Parent = builderPanel })
local builderHint = text({ Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -140, 0, 22), TextSize = 14, TextColor3 = THEME.muted, Parent = builderPanel })
local builderExit = button("Salir (TAB o B)", THEME.red, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(120, 28), TextSize = 13, Parent = builderPanel })
local palette = create("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 36),
	Size = UDim2.new(1, -20, 1, -44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 6,
	Parent = builderPanel,
}, { listLayout(Enum.FillDirection.Horizontal, 8) })
local builderStatus = text({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.fromOffset(600, 50),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextStrokeTransparency = 0.4,
	Visible = false,
	Parent = gui,
})
local builderTouch = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -175),
	Size = UDim2.fromOffset(330, 50),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
}, { listLayout(Enum.FillDirection.Horizontal, 6) })
local bPlace = button("Colocar", THEME.green, { Size = UDim2.fromOffset(78, 46), LayoutOrder = 1, Parent = builderTouch })
local bRotate = button("Rotar", THEME.blue, { Size = UDim2.fromOffset(78, 46), LayoutOrder = 2, Parent = builderTouch })
local bMove = button("Mover", THEME.panel2, { Size = UDim2.fromOffset(78, 46), LayoutOrder = 3, Parent = builderTouch })
local bSell = button("Vender", THEME.red, { Size = UDim2.fromOffset(78, 46), LayoutOrder = 4, Parent = builderTouch })

local SORTED_FIXTURES = {}
for id, def in Config.Fixtures do
	table.insert(SORTED_FIXTURES, { id = id, def = def })
end
table.sort(SORTED_FIXTURES, function(a, b)
	return a.def.order < b.def.order
end)

local function fixturesFolder()
	local model = workspace:FindFirstChild("Supermarket")
	return model and model:FindFirstChild("Fixtures")
end

-- level: solo los muebles de ese piso
local function footprints(ignoreId, level)
	local list = {}
	local folder = fixturesFolder()
	for _, m in folder and folder:GetChildren() or {} do
		if m:GetAttribute("FixtureId") ~= ignoreId and m:GetAttribute("FMinX") and (level == nil or (m:GetAttribute("FLevel") or 0) == level) then
			table.insert(list, { minX = m:GetAttribute("FMinX"), maxX = m:GetAttribute("FMaxX"), minZ = m:GetAttribute("FMinZ"), maxZ = m:GetAttribute("FMaxZ") })
		end
	end
	return list
end

local function clearGhost()
	if builder.ghost then
		builder.ghost:Destroy()
		builder.ghost = nil
	end
	builder.selected = nil
	builder.moving = nil
end

local function makeGhost(fixtureType)
	clearGhost()
	local def = Config.Fixtures[fixtureType]
	local model = Instance.new("Model")
	model.Name = "BuildGhost"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	body.Size = V(def.footprint.X, def.size.Y, def.footprint.Z)
	body.Transparency = 0.55
	body.Color = THEME.green
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model
	local arrow = Instance.new("Part")
	arrow.Name = "Front"
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.Size = V(1.2, 0.3, 1.2)
	arrow.Color = Color3.new(1, 1, 1)
	arrow.Material = Enum.Material.Neon
	arrow.CFrame = body.CFrame * CFrame.new(0, -def.size.Y / 2 + 0.3, -def.footprint.Z / 2 - 0.8)
	arrow.Parent = model
	model.PrimaryPart = body
	model.Parent = workspace.CurrentCamera
	builder.ghost = model
	builder.selected = fixtureType
end

local function renderPalette()
	clearList(palette)
	for i, entry in SORTED_FIXTURES do
		local def = entry.def
		local locked = def.requires and not snapshot.perks[def.requires]
		local card = button("", locked and THEME.bg or THEME.panel, { Size = UDim2.fromOffset(150, 100), LayoutOrder = i, Parent = palette })
		text({ Text = def.name, Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 36), Parent = card })
		text({ Text = "Comprar · " .. fmt(def.cost), TextColor3 = THEME.yellow, Font = Enum.Font.GothamBold, TextSize = 14, Position = UDim2.fromOffset(8, 44), Size = UDim2.new(1, -16, 0, 20), Parent = card })
		text({ Text = locked and ("🔒 " .. Config.PerksById[def.requires].name) or def.desc, TextColor3 = THEME.muted, TextSize = 11, Position = UDim2.fromOffset(8, 64), Size = UDim2.new(1, -16, 0, 32), Parent = card })
		card.Activated:Connect(function()
			if locked then
				notify("Necesitás la mejora \"" .. Config.PerksById[def.requires].name .. "\" en la pizarra de franquicia.", "warn")
				return
			end
			local ok, msg = safeInvoke(Remotes.BuyFixture, entry.id)
			notify(msg or "", ok and "good" or "bad")
		end)
	end
end
table.insert(snapshotListeners, function()
	if builder.active then
		renderPalette()
	end
end)

local function setBuilder(active)
	builder.active = active
	builderPanel.Visible = active
	builderStatus.Visible = active or builder.crateMode
	builderTouch.Visible = (active or builder.crateMode) and isTouch
	builderCatcher.Visible = active
	highlight.Adornee = nil
	if not active then
		if not builder.crateMode then
			clearGhost()
		end
		builder.hover = nil
	else
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
		renderPalette()
	end
end
builderExit.Activated:Connect(function()
	setBuilder(false)
end)

local function floorParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged("BuildFloor")
	return params
end

local function snapHalf(v)
	return math.floor(v * 2 + 0.5) / 2
end

local function hoveredFixture()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, workspace.CurrentCamera }
	local result = aimRaycast(false, params, 60)
	local folder = fixturesFolder()
	if not result or not folder then
		return nil
	end
	local current = result.Instance
	while current and current ~= workspace do
		if current.Parent == folder then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function builderStep()
	if not builder.active and not builder.crateMode then
		return
	end
	builderCatcher.Visible = builder.active and not builder.lookHeld
	builderHint.Text = "Tocá un mueble para COMPRARLO (llega en caja con la camioneta)  ·  Apuntá a uno armado: Q mover · X vender  ·  B: salir"

	if builder.ghost then
		highlight.Adornee = nil
		local def = Config.Fixtures[builder.selected]
		local result = aimRaycast(false, floorParams(), 120)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local myLevel = root and Config.levelAt(root.Position.Y) or 0
		if result and Config.levelAt(result.Position.Y) ~= myLevel then
			-- se apunta al piso de otro nivel (a través del techo): no vale
			result = nil
		end
		if result then
			builder.x, builder.z = snapHalf(result.Position.X), snapHalf(result.Position.Z)
			builder.level = myLevel
			builder.ghost:PivotTo(CFrame.new(builder.x, Config.levelY(myLevel) + def.size.Y / 2, builder.z) * CFrame.Angles(0, builder.rot * math.pi / 2, 0))
			local ok, reason = Config.validatePlacement(builder.selected, builder.x, builder.z, builder.rot, snapshot.expansions or {}, footprints(builder.moving, myLevel), myLevel)
			builder.valid = ok
			builder.ghost.PrimaryPart.Color = ok and THEME.green or THEME.red
			builderStatus.Text = ok and ((builder.moving and "Click: mover " or "Click: armar ") .. def.name .. "   ·   R: rotar") or reason
			builderStatus.TextColor3 = ok and Color3.new(1, 1, 1) or Color3.fromRGB(255, 120, 120)
		else
			builder.valid = false
			builderStatus.Text = "Apuntá al piso"
		end
	elseif builder.active then
		local hovered = hoveredFixture()
		builder.hover = hovered
		highlight.Adornee = hovered
		if hovered then
			local def = Config.Fixtures[hovered:GetAttribute("FixtureType")]
			builderStatus.Text = (def and def.name or "Mueble") .. "   ·   Q: mover   ·   X: vender (+" .. fmt(math.floor((def and def.cost or 0) * Config.FIXTURE_REFUND)) .. ")"
			builderStatus.TextColor3 = Color3.new(1, 1, 1)
		else
			builderStatus.Text = "Comprá un mueble abajo, o apuntá a uno armado para moverlo o venderlo."
			builderStatus.TextColor3 = THEME.muted
		end
	end
end

local function builderPlace()
	if not builder.ghost or not builder.valid then
		if builder.ghost then
			notify(builderStatus.Text, "warn")
		end
		return
	end
	local ok, msg
	if builder.moving then
		ok, msg = safeInvoke(Remotes.MoveFixture, builder.moving, builder.x, builder.z, builder.rot)
		if ok then
			clearGhost()
			renderPalette()
		end
	elseif builder.crateMode then
		ok, msg = safeInvoke(Remotes.PlaceCrate, builder.x, builder.z, builder.rot)
		if ok then
			_G.SMT_BUILT = true
		end
	else
		return
	end
	notify(msg or "", ok and "good" or "bad")
end

-- Si llevás una caja de mueble, aparece el "fantasma" para armarlo donde apuntes
local function updateCrateMode()
	local crateType = player:GetAttribute("CarryKind") == "crate" and player:GetAttribute("CarryFixture") or nil
	if crateType and not builder.moving then
		if not builder.crateMode or builder.selected ~= crateType or not builder.ghost then
			builder.crateMode = true
			makeGhost(crateType)
			builderStatus.Visible = true
			builderTouch.Visible = isTouch
		end
	elseif builder.crateMode then
		builder.crateMode = false
		clearGhost()
		builderStatus.Visible = builder.active
		builderTouch.Visible = builder.active and isTouch
	end
end

local function builderMove()
	local hovered = builder.hover
	if builder.ghost or not hovered then
		return
	end
	local fixtureType = hovered:GetAttribute("FixtureType")
	builder.rot = hovered:GetAttribute("FRot") or 0
	makeGhost(fixtureType)
	builder.moving = hovered:GetAttribute("FixtureId")
end

local function builderSell()
	local hovered = builder.hover
	if builder.ghost or not hovered then
		return
	end
	if os.clock() - builder.sellConfirm > 2.5 then
		builder.sellConfirm = os.clock()
		notify("Apretá X (o Vender) de nuevo para confirmar la venta.", "warn")
		return
	end
	builder.sellConfirm = 0
	local ok, msg = safeInvoke(Remotes.SellFixture, hovered:GetAttribute("FixtureId"))
	notify(msg or "", ok and "good" or "bad")
end

bPlace.Activated:Connect(builderPlace)
bRotate.Activated:Connect(function()
	builder.rot = (builder.rot + 1) % 4
end)
bMove.Activated:Connect(builderMove)
bSell.Activated:Connect(builderSell)

---------------------------------------------------------------------------
-- Reporte del día
---------------------------------------------------------------------------
local summaryWin, summaryBody = makeWindow("Summary", "📊 Fin del día", 480, 600)
local summaryScroll = scrollList(summaryBody, { Size = UDim2.new(1, 0, 1, -54) })
local summaryText = text({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextSize = 16, Parent = summaryScroll })
local continueButton = button("Continuar", THEME.green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(200, 44), Parent = summaryBody })
continueButton.Activated:Connect(function()
	summaryWin.Visible = false
end)

Remotes.DaySummary.OnClientEvent:Connect(function(s)
	local bills = s.rent + s.electricity + s.wages
	local net = s.income - bills
	local lines = {
		string.format("<b>%s · Día %d terminado</b>", s.weekday, s.day),
		"",
		"<b>Ventas</b>",
		"🧍 Clientes atendidos: " .. s.customers .. "   ·   🛒 Productos vendidos: " .. s.sales,
		"💵 Ingresos: <b>" .. fmt(s.income) .. "</b>",
		s.overpaid > 0 and ("🤦 Vuelto de más: -" .. fmt(s.overpaid)) or nil,
		"♻ Cajas recicladas: " .. s.recycled,
		"",
		"<b>Facturas del día</b>",
		"🏠 Alquiler: " .. fmt(s.rent),
		"💡 Electricidad: " .. fmt(s.electricity),
		"👷 Sueldos: " .. fmt(s.wages),
		string.format('📈 Resultado del día: <font color="%s"><b>%s</b></font>', net >= 0 and "#4fd17a" or "#ff6b6b", fmt(net)),
		"",
		"<b>Clientes y seguridad</b>",
		"😠 Quejas: " .. s.complaints .. "   ·   😊 Satisfacción: " .. s.satisfaction .. "%",
		"🦹 Robos: " .. s.thefts .. "   ·   👮 Atrapados: " .. s.caught .. "   ·   📦 Recuperados: " .. s.recovered,
	}
	if s.loan then
		table.insert(lines, "")
		table.insert(lines, "<b>Préstamo</b>")
		if s.loan.missed then
			table.insert(lines, '<font color="#ff6b6b"><b>⚠️ No alcanzó para la cuota (' .. fmt(s.loan.due) .. '). Mañana vienen los cobradores.</b></font>')
		else
			table.insert(lines, "✔ Cuota pagada: " .. fmt(s.loan.paid))
		end
		table.insert(lines, "Te falta pagar: " .. fmt(s.loan.remaining or 0))
	end
	table.insert(lines, "")
	table.insert(lines, string.format("⭐ Nivel %d (%d/%d XP)   ·   💰 Dinero: <b>%s</b>", s.level, s.xp, s.xpNext, fmt(s.money)))
	local final = {}
	for _, l in lines do
		if l then
			table.insert(final, l)
		end
	end
	summaryText.Text = table.concat(final, "\n")
	summaryWin.Visible = true
end)

---------------------------------------------------------------------------
-- Ayuda
---------------------------------------------------------------------------
local helpWin, helpBody = makeWindow("Help", "❓ Cómo se juega", 620, 600)
local helpScroll = scrollList(helpBody)
text({
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	RichText = true,
	TextSize = 15,
	Parent = helpScroll,
	Text = table.concat({
		"<b>Controles</b>",
		"• <b>Click</b>: levantar caja · poner un producto (mantené para ir más rápido) · escanear · cobrar",
		"• <b>Click derecho</b>: sacar un producto del estante a la caja que tenés en la mano",
		"• <b>F</b>: soltar la caja   · <b>B</b> o <b>TAB</b>: comprar / mover / vender muebles   · <b>H</b>: esta ayuda",
		"• <b>Alt</b> o <b>C</b>: mostrar u ocultar la flecha del mouse (oculta = el punto del centro es tu mouse)",
		"• <b>Celular</b>: tocá los objetos para usarlos; botones Usar / Sacar / Soltar abajo a la derecha",
		"• <b>1</b>: escoba (barrer basura, pegarle a ladrones y cobradores)   · <b>2</b>: pistola de precios (rueda del mouse)",
		"",
		"<b>Cómo arrancar</b>",
		"1. Apretá <b>B</b> y comprá una <b>estantería</b> y una <b>caja registradora</b>. Llegan en cajas de madera con la camioneta de <b>" .. Config.VAN_NAME .. "</b> a la zona de <b>carga y descarga</b> del estacionamiento.",
		"2. Levantá la caja del mueble (click), llevala adentro, apuntá al piso y hacé click para armarlo (R para rotar).",
		"3. En la <b>oficina</b> (dentro del depósito) usá la <b>Pizarra del gerente</b> para pedir productos (cada pedido cuesta " .. fmt(Config.DELIVERY_FEE) .. " de envío). Arrancás con la plata justa: ¡gastala bien!",
		"4. Llevá las cajas a los estantes y poné los productos de a uno con click. Guardá lo que sobre en los estantes del depósito.",
		"5. Con la <b>pistola de precios</b> apuntá a un producto: te muestra a cuánto lo comprás y cuánto ganás. Hasta 1.3x compran todos; más caro, cada vez menos; a 2x nadie.",
		"6. Apretá el <b>botón verde</b> de la oficina para abrir (08:00). A las 22:30 dejan de entrar clientes: cerrá con el <b>botón rojo</b>.",
		"7. Parate <b>detrás de la caja</b> para atender: click en cada producto de la cinta y después en la tarjeta o el efectivo. Si te vas y queda gente, tocan el <b>timbre</b> 🔔 (y va un cajero si tenés).",
		"8. Para abrir o cerrar una caja, hacé click en su poste con el número (o usá el botón del panel del cajero).",
		"9. Tirá las cajas vacías al <b>tacho azul</b> de reciclaje: te pagan $1.50 por cada una.",
		"• Hay más clientes al mediodía, a la tarde-noche y los fines de semana. Algunos vienen en auto.",
		"",
		"<b>Progreso</b>",
		"• Cada producto vendido da experiencia. Al subir de nivel ganás <b>puntos de franquicia</b> para desbloquear productos, empleados y mejoras.",
		"• Con dinero comprás <b>ampliaciones</b>. Cada día pagás alquiler, luz y sueldos.",
		"• Los <b>jueves</b> hay inflación: suben los precios de mercado.",
		"• Desde el día 7 aparecen <b>ladrones</b>: pegales con la escoba y recuperá lo que tiran.",
		"• Podés pedir <b>préstamos</b>. Si no pagás la cuota, vienen <b>cobradores</b> a pegarte y llevarse la plata.",
		"",
		"💡 En cooperativo lo mejor es repartirse: uno en la caja, otro reponiendo, otro pidiendo y vigilando.",
	}, "\n"),
})

local helpButton = button("❓ Ayuda (H)", THEME.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 64), Size = UDim2.fromOffset(120, 32), TextSize = 14, Parent = gui })
helpButton.Activated:Connect(function()
	helpWin.Visible = not helpWin.Visible
end)
local buildButton = button("🔨 Construir (B)", THEME.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -144, 0, 64), Size = UDim2.fromOffset(150, 32), TextSize = 14, Parent = gui })
buildButton.Activated:Connect(function()
	setBuilder(not builder.active)
end)

---------------------------------------------------------------------------
-- Tutorial de primeros pasos
---------------------------------------------------------------------------
local tutorial = create("Frame", {
	Position = UDim2.new(0, 16, 0.5, -40),
	Size = UDim2.fromOffset(310, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(10), padding(10), listLayout(nil, 4) })
text({ Text = "📋 Primeros pasos", Font = Enum.Font.GothamBold, TextSize = 16, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = tutorial })

local function hasFixture(fixtureType)
	local folder = fixturesFolder()
	for _, m in folder and folder:GetChildren() or {} do
		if m:GetAttribute("FixtureType") == fixtureType then
			return true
		end
	end
	return false
end
local function anyUnits()
	local folder = fixturesFolder()
	for _, m in folder and folder:GetChildren() or {} do
		local units = m:FindFirstChild("Units")
		if units and #units:GetChildren() > 0 then
			return true
		end
	end
	return false
end
local function anyBoxes()
	local boxes = workspace:FindFirstChild("Boxes")
	return boxes ~= nil and #boxes:GetChildren() > 0
end
local function dayAfter(n)
	return (status:GetAttribute("Day") or 1) > n
end

local STEPS = {
	{ "Apretá B y comprá una Estantería y una Caja registradora", function()
		return hasFixture("product_shelf") or _G.SMT_BUILT == true or dayAfter(1)
	end },
	{ "Buscá las cajas de madera en el estacionamiento y armá los muebles (click en el piso)", function()
		return (hasFixture("product_shelf") and hasFixture("checkout")) or dayAfter(1)
	end },
	{ "En la oficina, pedí productos en la Pizarra del gerente", function()
		return anyBoxes() or anyUnits() or dayAfter(1)
	end },
	{ "Levantá una caja (click) y poné productos en el estante (click)", function()
		return anyUnits() or dayAfter(1)
	end },
	{ "Con la pistola de precios (tecla 2) ajustá un precio", function()
		return _G.SMT_PRICE_SET == true or dayAfter(1)
	end },
	{ "Abrí la tienda con el botón verde de la oficina", function()
		return status:GetAttribute("Phase") ~= "Cerrado" or dayAfter(1)
	end },
	{ "Parate detrás de la caja y cobrale a un cliente", function()
		return _G.SMT_CHARGED == true or dayAfter(1)
	end },
}
local stepLabels = {}
for i, step in STEPS do
	stepLabels[i] = text({ Text = "", TextSize = 13, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = tutorial })
	stepLabels[i]:SetAttribute("Base", step[1])
end
task.spawn(function()
	while tutorial.Parent do
		local allDone = true
		for i, step in STEPS do
			local ok, done = pcall(step[2])
			done = ok and done
			allDone = allDone and done
			stepLabels[i].Text = (done and "✅ " or "⬜ ") .. step[1]
			stepLabels[i].TextColor3 = done and THEME.muted or THEME.text
		end
		tutorial.Visible = not allDone and (status:GetAttribute("Day") or 1) <= 3 and not anyWindowOpen()
		task.wait(1)
	end
end)

---------------------------------------------------------------------------
-- Golpe de los cobradores
---------------------------------------------------------------------------
local flash = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 0, 0), BackgroundTransparency = 1, ZIndex = 10, Parent = gui })
Remotes.Knockback.OnClientEvent:Connect(function(direction)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	flash.BackgroundTransparency = 0.5
	TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	root.AssemblyLinearVelocity = (typeof(direction) == "Vector3" and direction or V(0, 0, 1)) * 40 + V(0, 22, 0)
	task.delay(1.4, function()
		if humanoid.Parent then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end)

---------------------------------------------------------------------------
-- Entrada (teclado y mouse)
---------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and builder.active then
		builder.lookHeld = true
		return
	end
	local key = input.KeyCode
	-- TAB lo usa también Roblox (lista de jugadores), así que se acepta aunque venga "procesado". B es alternativa.
	if (key == Enum.KeyCode.Tab or key == Enum.KeyCode.B) and not UserInputService:GetFocusedTextBox() then
		setBuilder(not builder.active)
		return
	end
	-- Alt también se acepta aunque venga "procesado" (a veces Roblox lo marca así)
	local isAlt = key == Config.CURSOR_KEY or key == Config.CURSOR_KEY_ALT
	if (isAlt or (key == Config.CURSOR_KEY_EXTRA and not processed)) and not UserInputService:GetFocusedTextBox() then
		cursorMode = not cursorMode
		notify(cursorMode and "🖱️ Mouse visible (Alt o C para ocultarlo y usar la mira)" or "🎯 Mira activada: el punto del centro es tu mouse", "info")
		return
	end
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if builder.active or builder.crateMode then
			builderPlace()
		else
			startHold("primary", false)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		startHold("secondary", false)
	elseif key == Enum.KeyCode.F then
		Remotes.Action:FireServer("drop")
	elseif key == Enum.KeyCode.H then
		helpWin.Visible = not helpWin.Visible
	elseif (builder.active or builder.crateMode) and key == Enum.KeyCode.R then
		builder.rot = (builder.rot + 1) % 4
	elseif builder.active and key == Enum.KeyCode.Q then
		builderMove()
	elseif builder.active and key == Enum.KeyCode.X then
		builderSell()
	elseif gunEquipped() and (key == Enum.KeyCode.Z or key == Enum.KeyCode.X) then
		local step = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and 100 or 10)
		gunAdjust(key == Enum.KeyCode.X and step or -step)
	end
end)

-- Celular: tocar un objeto del mundo lo usa directamente
UserInputService.TouchTapInWorld:Connect(function(position, processed)
	if processed then
		return
	end
	if builder.active or builder.crateMode then
		builderPlace()
		return
	end
	tryAction("primary", position)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		hold.primary = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		hold.secondary = false
		builder.lookHeld = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and gunEquipped() and not processed then
		local step = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 1 or (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and 100 or 10)
		gunAdjust(input.Position.Z > 0 and step or -step)
	end
end)

---------------------------------------------------------------------------
-- Bucle por frame
---------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	updateCrateMode()
	local blocked = interactionBlocked()
	-- Flecha del mouse: se muestra con Alt, con ventanas abiertas o construyendo; si no, el punto del centro es el mouse
	local windowOpen = anyWindowOpen()
	local showCursor = cursorMode or windowOpen or (builder.active and not builder.lookHeld)
	cursorCatcher.Visible = cursorMode and not windowOpen
	UserInputService.MouseIconEnabled = showCursor
	crosshair.Visible = not showCursor or isTouch

	-- Mantener apretado para repetir (poner/sacar/escanear)
	if (hold.primary or hold.secondary) and os.clock() >= hold.nextRepeat then
		if hold.primary then
			tryAction("primary", hold.useCenter)
		end
		if hold.secondary then
			tryAction("secondary", hold.useCenter)
		end
		hold.nextRepeat = os.clock() + 0.12
	end

	if builder.active or builder.crateMode then
		builderStep()
		hintLabel.Text = ""
	elseif blocked then
		highlight.Adornee = nil
		hintLabel.Text = ""
	else
		local target = currentTarget(false)
		if target then
			highlight.Adornee = target
			hintLabel.Text = hintFor(target)
		else
			highlight.Adornee = nil
			hintLabel.Text = ""
		end
	end
	gunStep()
end)

refreshCarry()
print("[Supermercado] Interfaz lista ✔")
