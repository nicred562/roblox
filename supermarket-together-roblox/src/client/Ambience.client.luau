-- Ambiente del lado del jugador: animación de las pantallas de las maquinitas retro,
-- música de fondo y sonidos del ambiente (con volumen configurable en ⚙ Sonido).
-- Todo esto corre solo en tu compu/celular: no carga al servidor.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Esperar a que el juego esté en modo supermercado
local function currentMode()
	return ReplicatedStorage:GetAttribute("Mode")
end
while currentMode() ~= "store" do
	ReplicatedStorage:GetAttributeChangedSignal("Mode"):Wait()
end

local C = Color3.fromRGB

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function round(f, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0.5, 0)
	c.Parent = f
	return f
end

---------------------------------------------------------------------------
-- Maquinitas retro: cada juego es una animación sencilla hecha con cuadraditos
---------------------------------------------------------------------------
local W, H = 190, 155
local screens = {} -- [part] = { gui, step }

local BUILDERS = {}

BUILDERS.comepuntos = function(canvas)
	local border = frame(canvas, { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 1, -40), Position = UDim2.fromOffset(6, 28) })
	local stroke = Instance.new("UIStroke")
	stroke.Color = C(40, 70, 220)
	stroke.Thickness = 2
	stroke.Parent = border
	local dots = {}
	for i = 1, 11 do
		dots[i] = round(frame(canvas, { Size = UDim2.fromOffset(4, 4), Position = UDim2.fromOffset(12 + i * 14, 88), BackgroundColor3 = C(250, 220, 170) }))
	end
	local pac = round(frame(canvas, { Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C(250, 220, 40) }))
	local mouth = frame(pac, { Size = UDim2.fromOffset(9, 6), Position = UDim2.fromOffset(10, 6), BackgroundColor3 = C(0, 0, 0) })
	local ghost = round(frame(canvas, { Size = UDim2.fromOffset(16, 18), BackgroundColor3 = C(230, 50, 60) }), UDim.new(0.45, 0))
	frame(ghost, { Size = UDim2.fromOffset(4, 4), Position = UDim2.fromOffset(3, 5), BackgroundColor3 = C(255, 255, 255) })
	frame(ghost, { Size = UDim2.fromOffset(4, 4), Position = UDim2.fromOffset(9, 5), BackgroundColor3 = C(255, 255, 255) })
	return function(t, playing)
		local speed = playing and 70 or 35
		local x = (t * speed) % (W + 60) - 30
		pac.Position = UDim2.fromOffset(x, 81)
		mouth.Visible = math.floor(t * 8) % 2 == 0
		ghost.Position = UDim2.fromOffset(x - 34, 81)
		for i, d in dots do
			d.Visible = (12 + i * 14) > x + 9
		end
	end
end

BUILDERS.invasores = function(canvas)
	local aliens = {}
	for row = 0, 2 do
		for col = 0, 5 do
			local a = frame(canvas, { Size = UDim2.fromOffset(12, 8), BackgroundColor3 = row == 0 and C(230, 90, 200) or C(90, 230, 110) })
			frame(a, { Size = UDim2.fromOffset(4, 3), Position = UDim2.fromOffset(4, 8), BackgroundColor3 = a.BackgroundColor3 })
			table.insert(aliens, { f = a, row = row, col = col })
		end
	end
	local ship = frame(canvas, { Size = UDim2.fromOffset(16, 6), BackgroundColor3 = C(80, 200, 255) })
	frame(ship, { Size = UDim2.fromOffset(4, 4), Position = UDim2.fromOffset(6, -4), BackgroundColor3 = C(80, 200, 255) })
	local shot = frame(canvas, { Size = UDim2.fromOffset(2, 8), BackgroundColor3 = C(255, 255, 255) })
	return function(t, playing)
		local sway = math.sin(t * (playing and 1.6 or 0.8)) * 30
		for _, a in aliens do
			a.f.Position = UDim2.fromOffset(40 + a.col * 20 + sway, 32 + a.row * 16 + (math.floor(t * 2) % 2))
		end
		local sx = W / 2 + math.sin(t * 1.3) * 60
		ship.Position = UDim2.fromOffset(sx - 8, H - 22)
		local cycle = (t * (playing and 1.8 or 1)) % 1
		shot.Position = UDim2.fromOffset(sx - 1, H - 30 - cycle * 100)
		shot.Visible = playing or cycle < 0.8
	end
end

BUILDERS.bloques = function(canvas)
	local colors = { C(230, 80, 80), C(80, 200, 120), C(80, 140, 230), C(240, 200, 60), C(200, 90, 220) }
	local cols, size = 8, 14
	local left = (W - cols * size) / 2
	local well = frame(canvas, { BackgroundTransparency = 1, Size = UDim2.fromOffset(cols * size + 4, 118), Position = UDim2.fromOffset(left - 2, 28) })
	local stroke = Instance.new("UIStroke")
	stroke.Color = C(200, 200, 210)
	stroke.Thickness = 1
	stroke.Parent = well
	local stack = {}
	local heights = {}
	for i = 1, cols do
		heights[i] = 0
	end
	local falling = frame(canvas, { Size = UDim2.fromOffset(size - 1, size - 1), BackgroundColor3 = colors[1] })
	local col, y, lastT = math.random(cols), 0, 0
	local function reset()
		for _, f in stack do
			f:Destroy()
		end
		stack = {}
		for i = 1, cols do
			heights[i] = 0
		end
	end
	return function(t, playing)
		local dt = math.clamp(t - lastT, 0, 0.2)
		lastT = t
		y += dt * (playing and 90 or 45)
		local floorY = 28 + 116 - (heights[col] + 1) * size
		if y >= floorY then
			local placed = frame(canvas, { Size = falling.Size, Position = UDim2.fromOffset(left + (col - 1) * size, floorY), BackgroundColor3 = falling.BackgroundColor3 })
			table.insert(stack, placed)
			heights[col] += 1
			if heights[col] >= 7 then
				reset()
			end
			col, y = math.random(cols), 28
			falling.BackgroundColor3 = colors[math.random(#colors)]
		end
		falling.Position = UDim2.fromOffset(left + (col - 1) * size, y)
	end
end

local TITLES = { comepuntos = "COME-PUNTOS", invasores = "INVASORES", bloques = "BLOQUES" }

local function setupScreen(part)
	if screens[part] then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(W, H)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.MaxDistance = 80
	local canvas = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(6, 6, 14), ClipsDescendants = true })
	local score = Instance.new("TextLabel")
	score.BackgroundTransparency = 1
	score.Size = UDim2.new(1, 0, 0, 22)
	score.Font = Enum.Font.Arcade
	score.TextSize = 14
	score.TextColor3 = C(255, 255, 255)
	score.Parent = canvas
	local coin = Instance.new("TextLabel")
	coin.BackgroundTransparency = 1
	coin.Size = UDim2.new(1, 0, 0, 18)
	coin.Position = UDim2.new(0, 0, 1, -20)
	coin.Font = Enum.Font.Arcade
	coin.TextSize = 12
	coin.TextColor3 = C(250, 220, 60)
	coin.Text = "INSERT COIN"
	coin.Parent = canvas
	local game = part:GetAttribute("Game") or "comepuntos"
	local builder = BUILDERS[game] or BUILDERS.comepuntos
	local step = builder(canvas)
	gui.Parent = part
	screens[part] = { gui = gui, step = step, score = score, coin = coin, points = 0, title = TITLES[game] or "ARCADE" }
end

for _, part in CollectionService:GetTagged("ArcadeScreen") do
	setupScreen(part)
end
CollectionService:GetInstanceAddedSignal("ArcadeScreen"):Connect(setupScreen)
CollectionService:GetInstanceRemovedSignal("ArcadeScreen"):Connect(function(part)
	local s = screens[part]
	if s then
		s.gui:Destroy()
		screens[part] = nil
	end
end)

-- Solo se animan las pantallas cercanas (ahorra batería en celulares), a ~15 cuadros por segundo
local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 15 then
		return
	end
	accumulator = 0
	local camPos = workspace.CurrentCamera.CFrame.Position
	local t = os.clock()
	for part, s in screens do
		if part.Parent and (part.Position - camPos).Magnitude < 70 then
			local playing = part:GetAttribute("Playing") == true
			s.step(t, playing)
			if playing then
				s.points += math.random(5, 25)
				s.score.Text = s.title .. "  " .. string.format("%05d", s.points)
				s.coin.Visible = false
			else
				s.points = 0
				s.score.Text = s.title
				s.coin.Visible = math.floor(t * 2) % 2 == 0
			end
		end
	end
end)
