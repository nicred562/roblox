-- Menú principal: lista de salas abiertas, crear sala (nombre + contraseña), unirse con contraseña
-- y "Mis supermercados". Solo se muestra cuando el servidor está en modo "lobby".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local function currentMode()
	return ReplicatedStorage:GetAttribute("Mode")
end
while currentMode() == nil or currentMode() == "loading" do
	ReplicatedStorage:GetAttributeChangedSignal("Mode"):Wait()
end
if currentMode() ~= "lobby" then
	return
end

local THEME = {
	bg = Color3.fromRGB(22, 26, 34),
	panel = Color3.fromRGB(34, 40, 52),
	panel2 = Color3.fromRGB(50, 58, 74),
	text = Color3.fromRGB(245, 247, 250),
	muted = Color3.fromRGB(165, 173, 186),
	green = Color3.fromRGB(46, 170, 95),
	blue = Color3.fromRGB(52, 120, 220),
	red = Color3.fromRGB(210, 72, 72),
	yellow = Color3.fromRGB(240, 190, 50),
}

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

local function text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
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
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 40),
	}
	for k, v in props or {} do
		base[k] = v
	end
	return create("TextButton", base, { corner(8) })
end

local function input(parent, placeholder, order, masked)
	local holder = create("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = THEME.panel2, LayoutOrder = order, Parent = parent }, { corner(8) })
	local box = create("TextBox", {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = THEME.muted,
		TextColor3 = THEME.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = holder,
	})
	if masked then
		-- Roblox no tiene campos de contraseña: mostramos puntitos encima del texto real
		box.TextTransparency = 1
		local dots = text({ Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(12, 0), Text = "", TextSize = 18, Parent = holder })
		box:GetPropertyChangedSignal("Text"):Connect(function()
			dots.Text = string.rep("•", #box.Text)
		end)
	end
	return box
end

---------------------------------------------------------------------------
-- Cámara de fondo girando alrededor del supermercado
---------------------------------------------------------------------------
local camera = workspace.CurrentCamera
local angle = 0
RunService:BindToRenderStep("LobbyCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	angle += dt * 0.06
	camera.CameraType = Enum.CameraType.Scriptable
	local center = Vector3.new(0, 6, 20)
	local pos = center + Vector3.new(math.sin(angle) * 120, 42, math.cos(angle) * 120)
	camera.CFrame = CFrame.lookAt(pos, center)
end)
local blur = Instance.new("BlurEffect")
blur.Size = 6
blur.Parent = Lighting

---------------------------------------------------------------------------
-- Interfaz
---------------------------------------------------------------------------
local gui = create("ScreenGui", {
	Name = "LobbyUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Parent = gui })

text({
	Text = "SUPERMERCADO TOGETHER",
	Font = Enum.Font.FredokaOne,
	TextSize = 54,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 40),
	Size = UDim2.new(0.9, 0, 0, 64),
	TextScaled = true,
	Parent = gui,
}, nil)
text({
	Text = "Simulador de supermercado cooperativo · Creá una sala y pasale la contraseña a tus amigos",
	TextColor3 = THEME.muted,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 108),
	Size = UDim2.new(0.9, 0, 0, 24),
	Parent = gui,
})

local main = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.new(0.94, 0, 1, -200),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UISizeConstraint", { MaxSize = Vector2.new(1000, 560) }),
})

local statusLabel = text({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(0.9, 0, 0, 26),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = THEME.yellow,
	Font = Enum.Font.GothamBold,
	Text = RunService:IsStudio() and "Estás en Studio: al crear una sala o jugar solo, el supermercado se carga acá mismo (los teleports solo andan en el juego publicado)." or "",
	Parent = gui,
})

local function setStatus(message, color)
	statusLabel.Text = message or ""
	statusLabel.TextColor3 = color or THEME.yellow
end

local function panel(props)
	local p = create("Frame", props, { corner(12), create("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}) })
	p.BackgroundColor3 = THEME.bg
	return p
end

-- Columna izquierda: salas abiertas
local left = panel({ Size = UDim2.new(0.55, -8, 1, 0), Parent = main })
text({ Text = "🏪 Salas abiertas", Font = Enum.Font.GothamBold, TextSize = 20, Size = UDim2.new(1, -120, 0, 30), Parent = left })
local refreshButton = button("↻ Actualizar", THEME.panel2, { Size = UDim2.fromOffset(110, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextSize = 14, Parent = left })
local roomList = create("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 40),
	Size = UDim2.new(1, 0, 1, -40),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	Parent = left,
}, { create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

-- Columna derecha: crear / unirse / mis supermercados
local right = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.45, -8, 1, 0), Parent = main })
local tabs = create("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = right }, {
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local pages = {}
local tabButtons = {}
local function page(id)
	local p = create("Frame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48), BackgroundTransparency = 1, Visible = false, Parent = right }, {
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	pages[id] = p
	return p
end
local function showPage(id)
	for key, p in pages do
		p.Visible = key == id
		tabButtons[key].BackgroundColor3 = key == id and THEME.green or THEME.panel2
	end
end
for i, t in { { "create", "Crear sala" }, { "join", "Unirse" }, { "mine", "Mis súper" } } do
	local b = button(t[2], THEME.panel2, { Size = UDim2.new(0.333, -4, 1, 0), LayoutOrder = i, TextSize = 14, Parent = tabs })
	tabButtons[t[1]] = b
	b.Activated:Connect(function()
		showPage(t[1])
	end)
end

-- Crear
local createPage = page("create")
-- Jugar solo: sin nombre ni contraseña (partida privada, nadie más puede entrar)
local soloButton = button("▶  Jugar solo (sin nombre ni contraseña)", THEME.yellow, { LayoutOrder = -2, TextColor3 = Color3.fromRGB(30, 30, 30), Parent = createPage })
text({ Text = "— o creá una sala para jugar con amigos —", TextColor3 = THEME.muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), TextSize = 13, LayoutOrder = -1, Parent = createPage })
text({ Text = "Creá tu supermercado. Pasale el nombre y la contraseña a tus amigos para que entren.", TextColor3 = THEME.muted, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = createPage })
local createName = input(createPage, "Nombre de la sala (" .. Config.ROOM_NAME_MIN .. "-" .. Config.ROOM_NAME_MAX .. " letras)", 2)
local createPass = input(createPage, "Contraseña (" .. Config.PASSWORD_MIN .. "-" .. Config.PASSWORD_MAX .. " caracteres)", 3, true)
local createPass2 = input(createPage, "Repetí la contraseña", 4, true)
local createButton = button("Crear sala y entrar", THEME.green, { LayoutOrder = 5, Parent = createPage })

-- Unirse
local joinPage = page("join")
text({ Text = "Entrá a la sala de un amigo con el nombre y la contraseña que te pasó.", TextColor3 = THEME.muted, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = joinPage })
local joinName = input(joinPage, "Nombre de la sala", 2)
local joinPass = input(joinPage, "Contraseña", 3, true)
local joinButton = button("Unirse", THEME.blue, { LayoutOrder = 4, Parent = joinPage })

-- Mis supermercados
local minePage = page("mine")
local mineList = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, LayoutOrder = 1, Parent = minePage }, {
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

showPage("create")

---------------------------------------------------------------------------
-- Acciones
---------------------------------------------------------------------------
local busy = false
local function call(remote, ...)
	if busy then
		return false, "Esperá un momento..."
	end
	busy = true
	setStatus("Conectando...", THEME.muted)
	local args = table.pack(...)
	local ok, a, b = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	busy = false
	if not ok then
		return false, "Error de conexión."
	end
	return a, b
end

local function afterResult(success, message)
	if success then
		setStatus(message == "studio" and "Cargando el supermercado..." or (message or "Entrando..."), THEME.green)
	else
		setStatus(message or "Algo salió mal.", THEME.red)
	end
end

createButton.Activated:Connect(function()
	if createPass.Text ~= createPass2.Text then
		setStatus("Las contraseñas no coinciden.", THEME.red)
		return
	end
	afterResult(call(Remotes.CreateRoom, createName.Text, createPass.Text))
end)

joinButton.Activated:Connect(function()
	afterResult(call(Remotes.JoinRoom, joinName.Text, joinPass.Text))
end)

soloButton.Activated:Connect(function()
	afterResult(call(Remotes.PlaySolo))
end)

-- Ventanita para pedir la contraseña de una sala de la lista
local dialog = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(360, 200),
	BackgroundColor3 = THEME.bg,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
}, { corner(12), create("UIStroke", { Color = THEME.panel2, Thickness = 2 }) })
local dialogTitle = text({ Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 28), Font = Enum.Font.GothamBold, TextSize = 18, Parent = dialog })
local dialogBody = create("Frame", { Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 0, 42), BackgroundTransparency = 1, Parent = dialog })
local dialogPass = input(dialogBody, "Contraseña", 1, true)
local dialogJoin = button("Unirse", THEME.green, { Position = UDim2.new(0, 16, 1, -56), Size = UDim2.new(0.5, -22, 0, 40), Parent = dialog })
local dialogCancel = button("Cancelar", THEME.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -56), Size = UDim2.new(0.5, -22, 0, 40), Parent = dialog })
local dialogRoomId
dialogCancel.Activated:Connect(function()
	dialog.Visible = false
end)
dialogJoin.Activated:Connect(function()
	dialog.Visible = false
	afterResult(call(Remotes.JoinRoom, dialogRoomId or "", dialogPass.Text))
end)

local function roomRow(parent, order, title, subtitle, actionText, onAction)
	local row = create("Frame", { Size = UDim2.new(1, -8, 0, 58), BackgroundColor3 = THEME.panel, LayoutOrder = order, Parent = parent }, { corner(8) })
	text({ Text = title, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -140, 0, 24), Parent = row })
	text({ Text = subtitle, TextSize = 13, TextColor3 = THEME.muted, Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -140, 0, 20), Parent = row })
	local b = button(actionText, THEME.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 36), Parent = row })
	b.Activated:Connect(onAction)
end

local function clear(frame)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function refreshRooms()
	clear(roomList)
	local ok, rooms = pcall(function()
		return Remotes.ListRooms:InvokeServer()
	end)
	if not ok or type(rooms) ~= "table" or #rooms == 0 then
		text({ Text = RunService:IsStudio() and "En Studio no hay salas publicadas. Creá una para probar." or "No hay salas abiertas ahora. ¡Creá la tuya!", TextColor3 = THEME.muted, Size = UDim2.new(1, 0, 0, 40), Parent = roomList })
		return
	end
	for i, room in rooms do
		roomRow(roomList, i, "🔒 " .. tostring(room.name), string.format("Dueño: %s · %d jugador(es) · Día %d", tostring(room.ownerName), room.players or 0, room.day or 1), "Unirse", function()
			dialogRoomId = room.id
			dialogTitle.Text = "Unirse a " .. tostring(room.name)
			dialogPass.Text = ""
			dialog.Visible = true
		end)
	end
end

local function refreshMine()
	clear(mineList)
	local ok, rooms = pcall(function()
		return Remotes.MyRooms:InvokeServer()
	end)
	if not ok or type(rooms) ~= "table" or #rooms == 0 then
		text({ Text = "Todavía no creaste ningún supermercado.", TextColor3 = THEME.muted, Size = UDim2.new(1, 0, 0, 40), Parent = mineList })
		return
	end
	for i, room in rooms do
		roomRow(mineList, i, tostring(room.name), "Sos el dueño: entrás sin contraseña", "Abrir", function()
			afterResult(call(Remotes.JoinRoom, room.id, ""))
		end)
	end
end

refreshButton.Activated:Connect(refreshRooms)
tabButtons.mine.Activated:Connect(refreshMine)
task.spawn(refreshRooms)
task.spawn(function()
	while gui.Parent do
		task.wait(20)
		if gui.Parent and not dialog.Visible then
			refreshRooms()
		end
	end
end)

---------------------------------------------------------------------------
-- Cuando el servidor pasa a modo supermercado (Studio), se cierra el menú
---------------------------------------------------------------------------
ReplicatedStorage:GetAttributeChangedSignal("Mode"):Connect(function()
	if currentMode() == "store" then
		RunService:UnbindFromRenderStep("LobbyCamera")
		camera.CameraType = Enum.CameraType.Custom
		blur:Destroy()
		gui:Destroy()
	end
end)
