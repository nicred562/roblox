-- Vehículos: la camioneta de reparto "MercadoPibre" (trae la mercadería y los muebles y los deja
-- en la zona de descarga del estacionamiento), los autos de los clientes y el tránsito de la calle.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Boxes = require(script.Parent.Boxes)

local Vehicles = {}
local V, C = Vector3.new, Color3.fromRGB
local GROUND_Y = 0.12
local folder
local refs

-- Carriles de la calle principal (hacia +X por z=84, hacia -X por z=92)
local LANE_EAST, LANE_WEST = 84, 92
local STREET_END = 300
local VAN_X = -42 -- carril de entrada de la camioneta a la zona de descarga
local CAR_ENTRY_X = -26 -- entrada de autos al estacionamiento
local CAR_EXIT_X = -32 -- salida de autos (columna aparte: nunca se cruzan de frente con los que entran)
local AISLE_IN_Z = 55 -- carril del pasillo para ir a estacionar (hacia +X)
local AISLE_OUT_Z = 47.5 -- carril del pasillo para irse (hacia -X)
local STALL_Z = 64
local STALL_XS = { -19, -13, -7, -1, 5, 11, 17, 23, 29, 35, 41, 47, 53 }
local stallTaken = {}

local CAR_COLORS = {
	C(170, 45, 45), C(45, 80, 150), C(200, 200, 200), C(35, 35, 40), C(120, 120, 125),
	C(200, 165, 60), C(45, 110, 70), C(110, 60, 40), C(90, 40, 110),
}

---------------------------------------------------------------------------
-- Modelos
---------------------------------------------------------------------------
local function piece(model, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in extra or {} do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function wheel(model, cf, radius)
	piece(model, "Tire", V(0.9, radius * 2, radius * 2), cf, C(28, 28, 30), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	piece(model, "Hub", V(0.95, radius * 1.1, radius * 1.1), cf, C(170, 172, 176), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CastShadow = false })
end

-- Auto: el origen es el centro en el piso y el frente mira hacia -Z
function Vehicles.buildCar(color)
	local m = Instance.new("Model")
	m.Name = "Auto"
	local root = piece(m, "Root", V(4.6, 0.2, 9.4), CFrame.new(0, GROUND_Y + 0.1, 0), C(0, 0, 0), nil, { Transparency = 1, CastShadow = false })
	m.PrimaryPart = root
	local base = root.CFrame * CFrame.new(0, -0.1, 0)
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	color = color or CAR_COLORS[math.random(#CAR_COLORS)]
	local glassColor = C(45, 55, 65)
	piece(m, "Body", V(4.6, 1.25, 9.2), at(0, 1.35, 0), color)
	piece(m, "Hood", V(4.5, 0.25, 2.6), at(0, 2.05, -3.2), color)
	piece(m, "Trunk", V(4.5, 0.25, 1.8), at(0, 2.05, 3.6), color)
	-- Cabina opaca (techo del color del auto) con ventanas oscuras: se ve bien a través de vidrieras
	piece(m, "Cabin", V(4.1, 1.35, 4.4), at(0, 2.75, 0.3), glassColor)
	piece(m, "Roof", V(4.2, 0.18, 4.0), at(0, 3.5, 0.35), color)
	piece(m, "PillarFront", V(4.15, 1.3, 0.25), at(0, 2.75, -1.85), color)
	piece(m, "PillarBack", V(4.15, 1.3, 0.3), at(0, 2.75, 2.45), color)
	piece(m, "PillarMid", V(4.15, 1.3, 0.2), at(0, 2.75, 0.4), color)
	piece(m, "BumperFront", V(4.7, 0.5, 0.35), at(0, 0.95, -4.65), C(40, 40, 45))
	piece(m, "BumperBack", V(4.7, 0.5, 0.35), at(0, 0.95, 4.65), C(40, 40, 45))
	for _, x in { -1.6, 1.6 } do
		piece(m, "Headlight", V(1, 0.35, 0.12), at(x, 1.6, -4.62), C(230, 225, 200), Enum.Material.Neon, { CastShadow = false })
		piece(m, "Taillight", V(0.9, 0.3, 0.12), at(x, 1.6, 4.62), C(170, 30, 30), Enum.Material.Neon, { CastShadow = false })
		piece(m, "Mirror", V(0.4, 0.3, 0.5), at(x > 0 and 2.45 or -2.45, 2.4, -1.6), color)
	end
	for _, x in { -2.3, 2.3 } do
		for _, z in { -3, 3 } do
			wheel(m, at(x, 0.85, z), 0.85)
		end
	end
	return m
end

-- Camioneta de reparto "MercadoPibre"
function Vehicles.buildVan()
	local m = Instance.new("Model")
	m.Name = "Camioneta" .. Config.VAN_NAME
	local root = piece(m, "Root", V(5, 0.2, 13), CFrame.new(0, GROUND_Y + 0.1, 0), C(0, 0, 0), nil, { Transparency = 1, CastShadow = false })
	m.PrimaryPart = root
	local base = root.CFrame * CFrame.new(0, -0.1, 0)
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local yellow, blue, dark = C(236, 196, 48), C(40, 62, 140), C(40, 40, 45)
	piece(m, "Chassis", V(4.9, 0.7, 12.6), at(0, 1.15, 0), dark)
	local cargo = piece(m, "Cargo", V(4.9, 4.6, 8.4), at(0, 3.8, 2.0), yellow)
	piece(m, "Cab", V(4.9, 3.1, 3.9), at(0, 3.05, -4.2), yellow)
	piece(m, "CabRoof", V(4.7, 0.25, 3.5), at(0, 4.7, -4.0), yellow)
	piece(m, "Windshield", V(4.3, 1.4, 0.12), at(0, 3.8, -6.15), C(45, 55, 65))
	for _, x in { -2.46, 2.46 } do
		piece(m, "SideWindow", V(0.12, 1.2, 1.9), at(x, 3.8, -4.5), C(45, 55, 65))
		piece(m, "Stripe", V(0.1, 0.45, 8.3), at(x, 2.2, 2.0), blue)
	end
	piece(m, "Grille", V(3.2, 0.9, 0.15), at(0, 2.2, -6.2), dark)
	piece(m, "BumperFront", V(5, 0.55, 0.4), at(0, 1.2, -6.4), dark)
	piece(m, "BumperBack", V(5, 0.55, 0.4), at(0, 1.2, 6.4), dark)
	piece(m, "RearDoor", V(4.6, 4.2, 0.12), at(0, 3.75, 6.25), C(220, 180, 45))
	for _, x in { -1.8, 1.8 } do
		piece(m, "Headlight", V(0.9, 0.5, 0.12), at(x, 2.3, -6.22), C(230, 225, 200), Enum.Material.Neon, { CastShadow = false })
		piece(m, "Taillight", V(0.5, 0.9, 0.12), at(x > 0 and 2.2 or -2.2, 2.2, 6.28), C(170, 30, 30), Enum.Material.Neon, { CastShadow = false })
		piece(m, "Mirror", V(0.3, 0.6, 0.5), at(x > 0 and 2.7 or -2.7, 3.6, -5.6), dark)
	end
	for _, x in { -2.35, 2.35 } do
		for _, z in { -4.1, 4.2 } do
			wheel(m, at(x, 1.0, z), 1.0)
		end
	end
	-- Logo en los costados y atrás
	local function logo(face)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0.3
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(600, 330)
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0.45, 0)
		title.Position = UDim2.fromScale(0, 0.18)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = blue
		title.Text = Config.VAN_NAME
		title.Parent = gui
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0.18, 0)
		sub.Position = UDim2.fromScale(0, 0.66)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = blue
		sub.Text = "📦 envíos a tu súper"
		sub.Parent = gui
		gui.Parent = cargo
	end
	logo(Enum.NormalId.Left)
	logo(Enum.NormalId.Right)
	return m
end

-- Todas las piezas quedan soldadas a Root: al moverlo se mueve el vehículo entero y por la red
-- viaja una sola posición por vehículo (mucho más liviano para celulares).
local function weldToRoot(model)
	local root = model.PrimaryPart
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			p.Anchored = false
			p.Massless = true
		end
	end
	return model
end

local buildCarRaw, buildVanRaw = Vehicles.buildCar, Vehicles.buildVan
function Vehicles.buildCar(color)
	return weldToRoot(buildCarRaw(color))
end
function Vehicles.buildVan()
	return weldToRoot(buildVanRaw())
end

-- Moto de reparto "PedidosLla" con el repartidor montado (las piezas "Rider" se esconden al bajarse)
function Vehicles.buildMoto()
	local m = Instance.new("Model")
	m.Name = "Moto" .. Config.DELIVERY_APP
	local root = piece(m, "Root", V(1.4, 0.2, 4.2), CFrame.new(0, GROUND_Y + 0.1, 0), C(0, 0, 0), nil, { Transparency = 1, CastShadow = false })
	m.PrimaryPart = root
	local base = root.CFrame * CFrame.new(0, -0.1, 0)
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local red, dark, metal = C(214, 36, 74), C(35, 35, 40), C(170, 172, 176)
	for _, z in { -1.45, 1.45 } do
		piece(m, "Tire", V(0.35, 1.4, 1.4), at(0, 0.7, z), dark, Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
		piece(m, "Hub", V(0.38, 0.6, 0.6), at(0, 0.7, z), metal, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CastShadow = false })
	end
	piece(m, "Frame", V(0.5, 0.6, 2.6), at(0, 1.2, 0), red)
	piece(m, "Tank", V(0.8, 0.5, 0.9), at(0, 1.7, -0.5), red)
	piece(m, "Seat", V(0.7, 0.2, 1.3), at(0, 1.85, 0.5), dark)
	piece(m, "Fork", V(0.15, 1.3, 0.15), at(0, 1.5, -1.45) * CFrame.Angles(math.rad(-15), 0, 0), metal, Enum.Material.Metal)
	piece(m, "Handlebar", V(1.3, 0.12, 0.12), at(0, 2.3, -1.25), dark)
	piece(m, "Headlight", V(0.35, 0.3, 0.1), at(0, 2.0, -1.6), C(230, 225, 200), Enum.Material.Neon, { CastShadow = false })
	piece(m, "Taillight", V(0.3, 0.12, 0.08), at(0, 1.55, 1.75), C(170, 30, 30), Enum.Material.Neon, { CastShadow = false })
	-- Caja térmica de delivery con el logo
	local box = piece(m, "DeliveryBox", V(1.3, 1.2, 1.2), at(0, 2.6, 1.1), red)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(200, 180)
		gui.LightInfluence = 0.3
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = C(255, 255, 255)
		label.Text = "🛵\n" .. Config.DELIVERY_APP
		label.Parent = gui
		gui.Parent = box
	end
	-- Repartidor (con casco rojo)
	local skin = C(214, 170, 130)
	piece(m, "RiderLegs", V(0.9, 0.5, 1.1), at(0, 2.15, 0.35), C(40, 45, 60))
	piece(m, "RiderTorso", V(1, 1.1, 0.55), at(0, 2.9, 0.3) * CFrame.Angles(math.rad(-15), 0, 0), red)
	piece(m, "RiderArmL", V(0.25, 0.25, 1.1), at(-0.45, 2.85, -0.4), red)
	piece(m, "RiderArmR", V(0.25, 0.25, 1.1), at(0.45, 2.85, -0.4), red)
	piece(m, "RiderHead", V(0.55, 0.55, 0.55), at(0, 3.75, 0.15), skin)
	piece(m, "RiderHelmet", V(0.7, 0.45, 0.7), at(0, 3.95, 0.18), red, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	return weldToRoot(m)
end

-- Muestra u oculta al repartidor montado en la moto
function Vehicles.setRider(moto, visible)
	for _, p in moto:GetDescendants() do
		if p:IsA("BasePart") and string.sub(p.Name, 1, 5) == "Rider" then
			p.Transparency = visible and 0 or 1
		end
	end
end

---------------------------------------------------------------------------
-- Movimiento con distancia de frenado: cada vehículo mira lo que tiene adelante (otros autos,
-- la camioneta, clientes caminando o jugadores) y frena si está muy cerca. Así no se
-- superponen nunca y no atropellan a nadie.
---------------------------------------------------------------------------
local ACCEL = 16 -- studs/s² al arrancar
local BRAKE = 70 -- studs/s² al frenar
local SAFE_MARGIN = 1.6 -- espacio libre que dejan con el de adelante

local function extents(model)
	local root = model.PrimaryPart
	if not root then
		return 2.3, 4.7
	end
	return root.Size.X / 2, root.Size.Z / 2 -- medio ancho, medio largo
end

-- Cuánto ocupa un rectángulo girado (cf) medido sobre un eje
local function projected(cf, halfWidth, halfLength, axis)
	return math.abs(cf.LookVector:Dot(axis)) * halfLength + math.abs(cf.RightVector:Dot(axis)) * halfWidth
end

local function pedestrianRoots()
	local list = {}
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in npcs:GetChildren() do
			local r = m:FindFirstChild("HumanoidRootPart")
			if r then
				table.insert(list, r)
			end
		end
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			table.insert(list, r)
		end
	end
	return list
end

local function obstacleAhead(model, pos, dir, speedNow)
	local myHW, myHL = extents(model)
	local lat = V(-dir.Z, 0, dir.X)
	-- cuanto más rápido va, más lejos mira (lo que necesita para frenar a tiempo)
	local stopping = (speedNow or 0) ^ 2 / (2 * BRAKE)
	for _, other in folder:GetChildren() do
		if other ~= model and other.PrimaryPart then
			local ocf = other.PrimaryPart.CFrame
			local offset = ocf.Position - pos
			local ahead = offset.X * dir.X + offset.Z * dir.Z
			if ahead > 0 then
				local ohw, ohl = extents(other)
				local lateral = math.abs(offset.X * lat.X + offset.Z * lat.Z)
				if lateral < myHW + projected(ocf, ohw, ohl, lat) + 0.5 and ahead < myHL + projected(ocf, ohw, ohl, dir) + SAFE_MARGIN + stopping then
					return true
				end
			end
		end
	end
	for _, r in pedestrianRoots() do
		local offset = r.Position - pos
		local ahead = offset.X * dir.X + offset.Z * dir.Z
		if ahead > 0 and ahead < myHL + 2.5 + stopping and math.abs(offset.X * lat.X + offset.Z * lat.Z) < myHW + 1.2 then
			return true
		end
	end
	return false
end

local TURN_SPEED = 8 -- velocidad en las curvas
local DECEL = 22 -- frenado suave al llegar a una curva o al destino

-- Curva suave de a hasta b "doblando" en la esquina c (Bézier cuadrática)
local function curve(a, c, b, steps)
	local list = {}
	steps = steps or 7
	for i = 1, steps do
		local t = i / steps
		local u = 1 - t
		table.insert(list, a * (u * u) + c * (2 * u * t) + b * (t * t))
	end
	return list
end

-- Junta puntos sueltos y listas de puntos en un solo recorrido
local function path(...)
	local list = {}
	for _, part in { ... } do
		if typeof(part) == "Vector3" then
			table.insert(list, part)
		else
			for _, point in part do
				table.insert(list, point)
			end
		end
	end
	return list
end

-- endSpeed: con qué velocidad termina el recorrido (0 = se detiene)
function Vehicles.drive(model, points, speed, reverse, endSpeed)
	local root = model.PrimaryPart
	local current = model:GetAttribute("Speed") or 0
	endSpeed = endSpeed or 0
	for index, target in points do
		local startCF = root.CFrame
		local startPos = startCF.Position
		local finalPos = V(target.X, startPos.Y, target.Z)
		local delta = finalPos - startPos
		local dist = delta.Magnitude
		if dist > 0.05 then
			local dir = delta.Unit
			local faceDir = reverse and -dir or dir
			local startLook = startCF.LookVector
			local turnDist = math.min(5, dist)
			-- Los tramos cortos son pedazos de curva: se hacen despacio
			local cap = dist < 3 and math.min(speed, TURN_SPEED) or speed
			-- Con qué velocidad tiene que llegar al final de este tramo
			local exitSpeed = endSpeed
			local nextPoint = points[index + 1]
			if nextPoint then
				local nd = V(nextPoint.X - finalPos.X, 0, nextPoint.Z - finalPos.Z)
				local nextCap = nd.Magnitude < 3 and math.min(speed, TURN_SPEED) or speed
				exitSpeed = (nd.Magnitude < 0.05 or nd.Unit:Dot(dir) > 0.8) and nextCap or 3
			end
			local travelled = 0
			local blockedFor, ghostUntil = 0, 0
			while travelled < dist do
				local dt = RunService.Heartbeat:Wait()
				if not model.Parent then
					return false
				end
				local pos = startPos + dir * travelled
				local now = os.clock()
				local blocked = now > ghostUntil and obstacleAhead(model, pos, dir, current)
				if blocked then
					blockedFor += dt
					-- Por si dos quedan trabados mirándose: después de un rato pasa despacio
					if blockedFor > 7 then
						ghostUntil = now + 2
						blockedFor = 0
					end
				else
					blockedFor = 0
				end
				local wanted = blocked and 0 or cap
				wanted = math.min(wanted, math.sqrt(exitSpeed * exitSpeed + 2 * DECEL * (dist - travelled)))
				if now <= ghostUntil then
					wanted = math.min(speed, 4)
				end
				if current < wanted then
					current = math.min(wanted, current + ACCEL * dt)
				else
					current = math.max(wanted, current - BRAKE * dt)
				end
				-- nunca se queda "clavado" a centímetros del destino
				travelled = math.min(dist, travelled + math.max(current, blocked and 0 or 0.6) * dt)
				pos = startPos + dir * travelled
				local look = startLook:Lerp(faceDir, math.clamp(travelled / turnDist, 0, 1))
				look = V(look.X, 0, look.Z)
				if look.Magnitude < 0.05 then
					look = faceDir
				end
				root.CFrame = CFrame.lookAt(pos, pos + look)
			end
		end
	end
	model:SetAttribute("Speed", current)
	return true
end

-- Espera a que no haya ningún vehículo en estas zonas (para salir marcha atrás o incorporarse a la calle)
-- rects = { { minX, maxX, minZ, maxZ }, ... }
local function waitClear(model, rects, maxWait)
	local start = os.clock()
	while os.clock() - start < (maxWait or 15) do
		local clear = true
		for _, other in folder:GetChildren() do
			local p = other ~= model and other.PrimaryPart and other.PrimaryPart.Position
			if p then
				for _, r in rects do
					if p.X > r[1] and p.X < r[2] and p.Z > r[3] and p.Z < r[4] then
						clear = false
						break
					end
				end
			end
			if not clear then
				break
			end
		end
		if clear then
			return
		end
		task.wait(0.3)
	end
end

local function place(model, x, z, faceDir)
	-- el pivote es la pieza Root (0.1 sobre el suelo): así las ruedas apoyan en el asfalto
	local pos = V(x, GROUND_Y + 0.1, z)
	-- PivotTo mueve TODAS las piezas antes de entrar al mundo; recién ahí se activan las soldaduras.
	-- (Si solo se mueve Root fuera del mundo, la carrocería queda atrás en el centro del mapa.)
	model:PivotTo(CFrame.lookAt(pos, pos + faceDir))
	model.Parent = folder
end

-- ¿Hay lugar para que aparezca un vehículo en este punto de la calle?
local function spawnClear(x, z, radius)
	for _, other in folder:GetChildren() do
		local p = other.PrimaryPart and other.PrimaryPart.Position
		if p and (V(p.X, 0, p.Z) - V(x, 0, z)).Magnitude < radius then
			return false
		end
	end
	return true
end

-- Espera (hasta maxWait segundos) a que se libere el punto de aparición y ubica el vehículo
local function placeWhenClear(model, x, z, faceDir, maxWait)
	local start = os.clock()
	while not spawnClear(x, z, 16) do
		if os.clock() - start > (maxWait or 30) then
			break
		end
		task.wait(0.4)
	end
	place(model, x, z, faceDir)
end

---------------------------------------------------------------------------
-- Reparto con la camioneta
---------------------------------------------------------------------------
local queue = {}
local running = false

local function unloadPositions(count)
	local rect = refs.deliveryRect
	local list = {}
	for i = 1, count do
		local k = (i - 1) % 18
		local col = k % 6
		local row = math.floor(k / 6)
		table.insert(list, V(rect.minX + 1.2 + col * 2.3, 0, rect.minZ + 1.2 + row * 2.3))
	end
	return list
end

local function deliver(shipment)
	local van = Vehicles.buildVan()
	placeWhenClear(van, -STREET_END, LANE_EAST, V(1, 0, 0))
	local R = 6
	Vehicles.drive(van, { V(VAN_X - R, 0, LANE_EAST) }, 45, false, TURN_SPEED)
	Vehicles.drive(van, path(curve(V(VAN_X - R, 0, LANE_EAST), V(VAN_X, 0, LANE_EAST), V(VAN_X, 0, LANE_EAST - R)), V(VAN_X, 0, 50)), 16)

	-- Descarga: las cajas salen de la camioneta y caen en la zona de descarga
	local items = {}
	for _, crateType in shipment.crates or {} do
		table.insert(items, { crate = crateType })
	end
	for _, productId in shipment.boxes or {} do
		table.insert(items, { product = productId })
	end
	local spots = unloadPositions(#items)
	local cargoCF = van:GetPivot() * CFrame.new(0, 3, 3)
	for i, item in items do
		local object
		if item.crate then
			object = Boxes.createCrate(item.crate, CFrame.new(Boxes.groundPosition(spots[i], nil, Config.CRATE_SIZE.Y)))
		else
			object = Boxes.spawnDelivery(item.product, spots[i])
		end
		if object then
			local finalCF = object.CFrame
			object.CFrame = cargoCF
			TweenService:Create(object, TweenInfo.new(0.55, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = finalCF }):Play()
		end
		task.wait(0.3)
	end
	State.notify(nil, "🚚 La camioneta de " .. Config.VAN_NAME .. " dejó tu pedido en la zona de descarga (estacionamiento, frente al portón).", "good")
	task.wait(1)
	-- Sale marcha atrás y, antes de meterse en la calle, espera que no venga nadie
	Vehicles.drive(van, { V(VAN_X, 0, LANE_EAST - R) }, 10, true, 0)
	waitClear(van, { { VAN_X - 75, VAN_X + 10, LANE_EAST - 4, LANE_EAST + 4 } })
	Vehicles.drive(van, curve(V(VAN_X, 0, LANE_EAST - R), V(VAN_X, 0, LANE_EAST), V(VAN_X - R, 0, LANE_EAST)), 6, true, 0)
	Vehicles.drive(van, { V(STREET_END, 0, LANE_EAST) }, 45)
	van:Destroy()
end

function Vehicles.enqueueDelivery(shipment)
	table.insert(queue, shipment)
	if running then
		return #queue
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			-- Espera un momento y junta todo lo pedido en un solo viaje
			task.wait(2)
			local current = { boxes = {}, crates = {} }
			while #queue > 0 do
				local s = table.remove(queue, 1)
				for _, b in s.boxes or {} do
					table.insert(current.boxes, b)
				end
				for _, c in s.crates or {} do
					table.insert(current.crates, c)
				end
			end
			local ok, err = pcall(deliver, current)
			if not ok then
				warn("[Supermercado] Error en el reparto:", err)
				-- Si falla la animación, la mercadería igual llega
				for _, crateType in current.crates or {} do
					Boxes.createCrate(crateType, CFrame.new(Boxes.groundPosition(refs.points.delivery, nil, Config.CRATE_SIZE.Y)))
				end
				for _, productId in current.boxes or {} do
					Boxes.spawnDelivery(productId)
				end
			end
		end
		running = false
	end)
	return 1
end

---------------------------------------------------------------------------
-- Autos de clientes
---------------------------------------------------------------------------
function Vehicles.reserveStall()
	local free = {}
	for i in STALL_XS do
		if not stallTaken[i] then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return nil
	end
	local index = free[math.random(#free)]
	stallTaken[index] = true
	return index
end

function Vehicles.releaseStall(index)
	stallTaken[index] = nil
end

-- Llega un auto y estaciona. Devuelve el modelo y el punto donde baja el cliente.
function Vehicles.arriveCar(stallIndex)
	local car = Vehicles.buildCar()
	local x = STALL_XS[stallIndex]
	local R = 5
	local ex = CAR_ENTRY_X
	placeWhenClear(car, -STREET_END, LANE_EAST, V(1, 0, 0))
	Vehicles.drive(car, { V(ex - R, 0, LANE_EAST) }, 45, false, TURN_SPEED)
	-- Dobla a la derecha para entrar, baja por su carril, dobla por el pasillo y estaciona de frente
	local turnStart = math.max(x - R, ex + R)
	Vehicles.drive(car, path(
		curve(V(ex - R, 0, LANE_EAST), V(ex, 0, LANE_EAST), V(ex, 0, LANE_EAST - R)),
		V(ex, 0, AISLE_IN_Z + R),
		curve(V(ex, 0, AISLE_IN_Z + R), V(ex, 0, AISLE_IN_Z), V(ex + R, 0, AISLE_IN_Z)),
		V(turnStart, 0, AISLE_IN_Z),
		curve(V(turnStart, 0, AISLE_IN_Z), V(x, 0, AISLE_IN_Z), V(x, 0, AISLE_IN_Z + (x - turnStart))),
		V(x, 0, STALL_Z)
	), 14)
	return car, V(x + 3.2, Config.FLOOR_Y, STALL_Z - 2)
end

function Vehicles.departCar(car, stallIndex)
	task.spawn(function()
		if car and car.Parent then
			local x = STALL_XS[stallIndex]
			local R = 5
			local back = 6
			-- Marcha atrás girando: queda mirando hacia la salida, en el carril de salida
			Vehicles.drive(car, { V(x, 0, AISLE_OUT_Z + back) }, 6, true, 3)
			Vehicles.drive(car, curve(V(x, 0, AISLE_OUT_Z + back), V(x, 0, AISLE_OUT_Z), V(x + back, 0, AISLE_OUT_Z)), 6, true, 0)
			-- Sale por su columna (nunca de frente con los que entran)
			Vehicles.drive(car, path(
				V(CAR_EXIT_X + R, 0, AISLE_OUT_Z),
				curve(V(CAR_EXIT_X + R, 0, AISLE_OUT_Z), V(CAR_EXIT_X, 0, AISLE_OUT_Z), V(CAR_EXIT_X, 0, AISLE_OUT_Z + R)),
				V(CAR_EXIT_X, 0, LANE_EAST - R - 6)
			), 14, false, 0)
			-- Antes de meterse en la calle, mira que no venga nadie (ni por la calle ni entrando al estacionamiento)
			waitClear(car, {
				{ CAR_EXIT_X - 60, CAR_EXIT_X + 8, LANE_EAST - 4, LANE_EAST + 4 },
				{ CAR_ENTRY_X - 4, CAR_ENTRY_X + 4, LANE_EAST - 16, LANE_EAST },
			})
			Vehicles.drive(car, path(
				V(CAR_EXIT_X, 0, LANE_EAST - R),
				curve(V(CAR_EXIT_X, 0, LANE_EAST - R), V(CAR_EXIT_X, 0, LANE_EAST), V(CAR_EXIT_X + R, 0, LANE_EAST)),
				V(STREET_END, 0, LANE_EAST)
			), 45)
			car:Destroy()
		end
		Vehicles.releaseStall(stallIndex)
	end)
end

---------------------------------------------------------------------------
-- Moto de PedidosLla: llega, estaciona frente a la entrada y después se va
---------------------------------------------------------------------------
local MOTO_STOP = V(4, 0, 41)

-- Devuelve la moto estacionada y el punto donde se baja el repartidor
function Vehicles.motoArrive()
	local moto = Vehicles.buildMoto()
	local R, ex = 4, CAR_ENTRY_X
	placeWhenClear(moto, -STREET_END, LANE_EAST, V(1, 0, 0))
	Vehicles.drive(moto, { V(ex - R, 0, LANE_EAST) }, 50, false, TURN_SPEED)
	Vehicles.drive(moto, path(
		curve(V(ex - R, 0, LANE_EAST), V(ex, 0, LANE_EAST), V(ex, 0, LANE_EAST - R)),
		V(ex, 0, MOTO_STOP.Z + R),
		curve(V(ex, 0, MOTO_STOP.Z + R), V(ex, 0, MOTO_STOP.Z), V(ex + R, 0, MOTO_STOP.Z)),
		MOTO_STOP
	), 16)
	return moto, V(MOTO_STOP.X, Config.FLOOR_Y, MOTO_STOP.Z - 2)
end

function Vehicles.motoDepart(moto)
	task.spawn(function()
		if not (moto and moto.Parent) then
			return
		end
		-- Da la vuelta en U y sale por el carril de salida
		Vehicles.drive(moto, path(
			V(8, 0, MOTO_STOP.Z),
			curve(V(8, 0, MOTO_STOP.Z), V(12, 0, MOTO_STOP.Z), V(12, 0, MOTO_STOP.Z + 3.2)),
			curve(V(12, 0, MOTO_STOP.Z + 3.2), V(12, 0, AISLE_OUT_Z), V(8, 0, AISLE_OUT_Z)),
			V(CAR_EXIT_X + 4, 0, AISLE_OUT_Z),
			curve(V(CAR_EXIT_X + 4, 0, AISLE_OUT_Z), V(CAR_EXIT_X, 0, AISLE_OUT_Z), V(CAR_EXIT_X, 0, AISLE_OUT_Z + 4)),
			V(CAR_EXIT_X, 0, LANE_EAST - 11)
		), 16, false, 0)
		waitClear(moto, {
			{ CAR_EXIT_X - 60, CAR_EXIT_X + 8, LANE_EAST - 4, LANE_EAST + 4 },
			{ CAR_ENTRY_X - 4, CAR_ENTRY_X + 4, LANE_EAST - 16, LANE_EAST },
		})
		Vehicles.drive(moto, path(
			V(CAR_EXIT_X, 0, LANE_EAST - 4),
			curve(V(CAR_EXIT_X, 0, LANE_EAST - 4), V(CAR_EXIT_X, 0, LANE_EAST), V(CAR_EXIT_X + 4, 0, LANE_EAST)),
			V(STREET_END, 0, LANE_EAST)
		), 50)
		moto:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Tránsito de ambiente
---------------------------------------------------------------------------
local trafficCount = 0
local function spawnTraffic()
	if trafficCount >= Config.MAX_TRAFFIC_CARS then
		return
	end
	local east = math.random() < 0.5
	local startX = east and -STREET_END or STREET_END
	local lane = east and LANE_EAST or LANE_WEST
	-- Si justo hay otro auto donde aparecería, esta vez no sale ninguno (nunca aparecen encimados)
	if not spawnClear(startX, lane, 18) then
		return
	end
	trafficCount += 1
	task.spawn(function()
		local car = Vehicles.buildCar()
		place(car, startX, lane, V(east and 1 or -1, 0, 0))
		Vehicles.drive(car, { V(-startX, 0, lane) }, math.random(35, 50))
		car:Destroy()
		trafficCount -= 1
	end)
end

function Vehicles.init(builderRefs)
	refs = builderRefs
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace
	-- Dos autos estacionados fijos (ocupan su lugar)
	for _, index in { 3, 12 } do
		stallTaken[index] = true
		local car = Vehicles.buildCar()
		place(car, STALL_XS[index], STALL_Z, V(0, 0, 1))
	end
	task.spawn(function()
		while true do
			task.wait(math.random(7, 14))
			spawnTraffic()
		end
	end)
end

return Vehicles
