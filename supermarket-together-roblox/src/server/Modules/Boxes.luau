-- Cajas de mercadería y cajas de muebles (de madera). Llegan con la camioneta a la zona de descarga.
-- Se levantan con click (o tocando en el celular), se ponen productos de a uno en los niveles,
-- se sacan con click derecho, se guardan en el depósito, se reciclan y los muebles se arman desde su caja.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local StoreBuilder = require(script.Parent.StoreBuilder)
local Fixtures = require(script.Parent.Fixtures)

local Boxes = {}
Boxes.all = {} -- set: [caja] = true (incluye las cajas de muebles)
Boxes.carrying = {} -- [player] = caja

local CARRY_OFFSET = CFrame.new(0, 0.1, -2.1)
local CRATE_CARRY_OFFSET = CFrame.new(0, 0.5, -2.6)
local refs
local folder
local lastNotify = {}

local function throttledNotify(player, text, kind)
	local now = os.clock()
	if (lastNotify[player] or 0) + 1.2 > now then
		return
	end
	lastNotify[player] = now
	State.notify(player, text, kind or "warn")
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart"), humanoid
end

local function near(player, position)
	local root = rootOf(player)
	return root ~= nil and (root.Position - position).Magnitude <= Config.INTERACT_DISTANCE
end

local function isCrate(box)
	return box:GetAttribute("Kind") == "crate"
end

local function defaultIgnore(extra)
	local list = {}
	for _, name in { "NPCs", "Vehicles" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, e in extra or {} do
		table.insert(list, e)
	end
	return list
end

-- Busca el piso (o la caja de abajo) para apoyar algo de altura `height`
function Boxes.groundPosition(position, extraIgnore, height)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = defaultIgnore(extraIgnore)
	params.RespectCanCollide = true
	local result = workspace:Raycast(Vector3.new(position.X, position.Y + 8, position.Z), Vector3.new(0, -30, 0), params)
	local y = result and result.Position.Y or Config.FLOOR_Y
	return Vector3.new(position.X, y + (height or Config.BOX_SIZE.Y) / 2 + 0.01, position.Z)
end

function Boxes.count()
	local n = 0
	for _ in Boxes.all do
		n += 1
	end
	return n
end

local function setCarryAttributes(player, box)
	if not player then
		return
	end
	if box and isCrate(box) then
		local def = Config.Fixtures[box:GetAttribute("FixtureType") or ""]
		player:SetAttribute("CarryKind", "crate")
		player:SetAttribute("CarryFixture", box:GetAttribute("FixtureType"))
		player:SetAttribute("CarryId", "")
		player:SetAttribute("CarryUnits", 0)
		player:SetAttribute("CarryName", def and def.name or "Mueble")
	elseif box then
		local prod = Config.ProductsById[box:GetAttribute("ProductId") or ""]
		player:SetAttribute("CarryKind", "box")
		player:SetAttribute("CarryFixture", nil)
		player:SetAttribute("CarryId", prod and prod.id or "")
		player:SetAttribute("CarryUnits", box:GetAttribute("Units") or 0)
		player:SetAttribute("CarryName", prod and prod.name or "Caja vacía")
	else
		for _, attr in { "CarryKind", "CarryFixture", "CarryId", "CarryUnits", "CarryName" } do
			player:SetAttribute(attr, nil)
		end
	end
end

function Boxes.updateText(box)
	local text
	if isCrate(box) then
		local def = Config.Fixtures[box:GetAttribute("FixtureType") or ""]
		text = "📦 " .. (def and def.name or "Mueble")
	else
		local prod = Config.ProductsById[box:GetAttribute("ProductId") or ""]
		local units = box:GetAttribute("Units") or 0
		text = (prod and units > 0) and string.format("%s\nx%d", prod.name, units) or "VACÍA"
	end
	for _, name in { "FrontGui", "TopGui", "BackGui" } do
		local gui = box:FindFirstChild(name)
		if gui then
			gui.Label.Text = text
		end
	end
	local carrierId = box:GetAttribute("CarrierId")
	if carrierId then
		setCarryAttributes(Players:GetPlayerByUserId(carrierId), box)
	end
	local storageFixture = Fixtures.list[box:GetAttribute("StorageFixture") or ""]
	if storageFixture then
		Fixtures.updateStorageLabel(storageFixture, box:GetAttribute("StorageSlot"))
	end
end

local function addLabel(box, face, name, color)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.LightInfluence = 0.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(200, 150)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or Color3.fromRGB(70, 45, 20)
	label.Parent = gui
	gui.Parent = box
end

local function welded(box, name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p.CFrame = box.CFrame * offset
	p.Parent = box
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = box
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function register(box)
	box.Parent = folder
	CollectionService:AddTag(box, "Box")
	Boxes.all[box] = true
	box.Destroying:Connect(function()
		Boxes.all[box] = nil
	end)
	Boxes.updateText(box)
end

function Boxes.create(productId, units, cframe)
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Size = Config.BOX_SIZE
	box.Color = Color3.fromRGB(190, 152, 104)
	pcall(function()
		box.Material = Enum.Material.Cardboard
	end)
	box.TopSurface = Enum.SurfaceType.Smooth
	box.BottomSurface = Enum.SurfaceType.Smooth
	box.Anchored = true
	box.CFrame = cframe
	box:SetAttribute("ProductId", productId or "")
	box:SetAttribute("Units", units or 0)
	box:SetAttribute("Kind", "box")
	welded(box, "Tape", Vector3.new(0.4, 0.02, Config.BOX_SIZE.Z + 0.02), CFrame.new(0, Config.BOX_SIZE.Y / 2 + 0.01, 0), Color3.fromRGB(215, 192, 145))
	local prod = Config.ProductsById[productId or ""]
	if prod then
		-- franja con el color del producto para reconocerlo de lejos
		welded(box, "Band", Vector3.new(Config.BOX_SIZE.X + 0.02, 0.3, Config.BOX_SIZE.Z + 0.02), CFrame.new(0, -0.35, 0), prod.color:Lerp(Color3.fromRGB(190, 186, 178), 0.2))
	end
	addLabel(box, Enum.NormalId.Front, "FrontGui")
	addLabel(box, Enum.NormalId.Top, "TopGui")
	register(box)
	return box
end

-- Caja de madera con un mueble adentro
function Boxes.createCrate(fixtureType, cframe)
	local s = Config.CRATE_SIZE
	local crate = Instance.new("Part")
	crate.Name = "Crate"
	crate.Size = s
	crate.Color = Color3.fromRGB(170, 128, 82)
	crate.Material = Enum.Material.WoodPlanks
	crate.TopSurface = Enum.SurfaceType.Smooth
	crate.BottomSurface = Enum.SurfaceType.Smooth
	crate.Anchored = true
	crate.CFrame = cframe
	crate:SetAttribute("Kind", "crate")
	crate:SetAttribute("FixtureType", fixtureType)
	crate:SetAttribute("ProductId", "")
	crate:SetAttribute("Units", 0)
	local wood = Color3.fromRGB(128, 92, 58)
	for _, y in { -s.Y / 2 + 0.15, s.Y / 2 - 0.15 } do
		welded(crate, "Slat", Vector3.new(s.X + 0.06, 0.25, s.Z + 0.06), CFrame.new(0, y, 0), wood, Enum.Material.Wood)
	end
	for _, x in { -s.X / 2 + 0.15, s.X / 2 - 0.15 } do
		for _, z in { -s.Z / 2 + 0.15, s.Z / 2 - 0.15 } do
			welded(crate, "Post", Vector3.new(0.3, s.Y + 0.04, 0.3), CFrame.new(x, 0, z), wood, Enum.Material.Wood)
		end
	end
	addLabel(crate, Enum.NormalId.Front, "FrontGui", Color3.fromRGB(45, 30, 15))
	addLabel(crate, Enum.NormalId.Back, "BackGui", Color3.fromRGB(45, 30, 15))
	addLabel(crate, Enum.NormalId.Top, "TopGui", Color3.fromRGB(45, 30, 15))
	register(crate)
	return crate
end

-- Pone una caja en la zona de descarga (en `position` o en un lugar libre)
function Boxes.spawnDelivery(productId, position)
	local prod = Config.ProductsById[productId]
	if position then
		return Boxes.create(productId, prod.unitsPerBox, CFrame.new(Boxes.groundPosition(position)))
	end
	local rect = refs.deliveryRect
	for _ = 1, 12 do
		local x = rect.minX + 1.2 + math.random(0, 5) * 2.3
		local z = rect.minZ + 1.2 + math.random(0, 2) * 2.3
		local pos = Boxes.groundPosition(Vector3.new(x, Config.FLOOR_Y, z))
		if pos.Y < 5 then
			return Boxes.create(productId, prod.unitsPerBox, CFrame.new(pos))
		end
	end
	return Boxes.create(productId, prod.unitsPerBox, CFrame.new(Boxes.groundPosition(refs.points.delivery)))
end

---------------------------------------------------------------------------
-- Cargar / soltar (también lo usan los empleados)
---------------------------------------------------------------------------
function Boxes.attach(box, rootPart)
	box.Anchored = true
	box.CFrame = rootPart.CFrame * (isCrate(box) and CRATE_CARRY_OFFSET or CARRY_OFFSET)
	box.CanCollide = false
	box.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = rootPart
	weld.Part1 = box
	weld.Parent = box
	box.Anchored = false
end

function Boxes.detach(box, cframe)
	local weld = box:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	box.Anchored = true
	box.CanCollide = true
	box.Massless = false
	box.CFrame = cframe
end

function Boxes.storeBox(box, fixture, index)
	Boxes.detach(box, fixture.storage[index].cf)
	Fixtures.setStorageBox(fixture, index, box)
end

function Boxes.recycleBox(box)
	if box.Parent then
		box:Destroy()
	end
	local value = State.hasPerk("recycling") and Config.RECYCLE_VALUE_PERK or Config.RECYCLE_VALUE
	State.addIncome(value)
	State.addStat("recycled", 1)
	return value
end

function Boxes.pickUp(player, box)
	if Boxes.carrying[player] then
		throttledNotify(player, "Ya llevás algo en la mano. Soltalo con F (o el botón Soltar).")
		return
	end
	if not box.Parent or box:GetAttribute("CarrierId") or box:GetAttribute("ClaimedBy") then
		return
	end
	local root, humanoid = rootOf(player)
	if not root or (root.Position - box.Position).Magnitude > Config.INTERACT_DISTANCE then
		return
	end
	if box:GetAttribute("StorageFixture") then
		Fixtures.clearStorageBox(box)
	end
	humanoid:UnequipTools()
	box:SetAttribute("CarrierId", player.UserId)
	Boxes.carrying[player] = box
	Boxes.attach(box, root)
	Boxes.updateText(box)
	if isCrate(box) then
		State.notify(player, "📦 Llevala adentro y apuntá al piso: click (o Colocar) para armar el mueble. R para rotar.", "info")
	end
end

function Boxes.drop(player)
	local box = Boxes.carrying[player]
	if not box then
		return
	end
	Boxes.carrying[player] = nil
	setCarryAttributes(player, nil)
	if not box.Parent then
		return
	end
	box:SetAttribute("CarrierId", nil)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local base = root and (root.Position + root.CFrame.LookVector * 2.8) or box.Position
	local height = isCrate(box) and Config.CRATE_SIZE.Y or Config.BOX_SIZE.Y
	Boxes.detach(box, CFrame.new(Boxes.groundPosition(base, { box }, height)) * (root and root.CFrame.Rotation or CFrame.identity))
end

---------------------------------------------------------------------------
-- Acciones con la caja en la mano
---------------------------------------------------------------------------
local WRONG_TYPE = {
	shelf = "Este producto va en una estantería común.",
	fridge = "Este producto va en una heladera (desbloqueala en Franquicia).",
	freezer = "Este producto va en un freezer (desbloquealo en Franquicia).",
	produce = "Las frutas y verduras van en la verdulería (cajones de madera).",
	appliance = "Los electrodomésticos van en la góndola de electrodomésticos.",
}

local function carriedBox(player)
	local box = Boxes.carrying[player]
	if box and isCrate(box) then
		throttledNotify(player, "Eso es un mueble: apuntá al piso y hacé click para armarlo.", "info")
		return nil
	end
	return box
end

local function placeUnit(player, fixtureId, index)
	local box = carriedBox(player)
	local fixture = Fixtures.list[fixtureId]
	if not box or not fixture or not fixture.slots[index] then
		return
	end
	if not near(player, fixture.slots[index].hit.Position) then
		return
	end
	local units = box:GetAttribute("Units") or 0
	local productId = box:GetAttribute("ProductId") or ""
	if units <= 0 or productId == "" then
		throttledNotify(player, "La caja está vacía. Reciclala en un tacho azul.")
		return
	end
	local ok, reason = Fixtures.addUnit(fixture, index, productId)
	if ok then
		units -= 1
		box:SetAttribute("Units", units)
		if units <= 0 then
			box:SetAttribute("ProductId", "")
		end
		Boxes.updateText(box)
	elseif reason == "wrongtype" then
		throttledNotify(player, WRONG_TYPE[Config.ProductsById[productId].storage])
	elseif reason == "occupied" then
		local current = Config.ProductsById[fixture.slots[index].productId]
		throttledNotify(player, "Este nivel ya tiene " .. current.name .. ". Usá otro nivel.")
	elseif reason == "full" then
		throttledNotify(player, "El nivel está lleno.", "info")
	end
end

local function takeUnit(player, fixtureId, index)
	local box = carriedBox(player)
	local fixture = Fixtures.list[fixtureId]
	if not box or not fixture then
		return
	end
	local slot = fixture.slots[index]
	if not slot or not near(player, slot.hit.Position) then
		return
	end
	if slot.stock <= 0 then
		throttledNotify(player, "No hay productos para sacar.", "info")
		return
	end
	local productId = slot.productId
	local boxProduct = box:GetAttribute("ProductId") or ""
	local units = box:GetAttribute("Units") or 0
	if boxProduct ~= "" and units > 0 and boxProduct ~= productId then
		throttledNotify(player, "La caja tiene otro producto. Usá una caja vacía o del mismo producto.")
		return
	end
	if units >= Config.ProductsById[productId].unitsPerBox then
		throttledNotify(player, "La caja está llena.", "info")
		return
	end
	Fixtures.removeUnit(fixture, index, true)
	box:SetAttribute("ProductId", productId)
	box:SetAttribute("Units", units + 1)
	Boxes.updateText(box)
end

local function storeCarried(player, fixtureId, index)
	local box = carriedBox(player)
	local fixture = Fixtures.list[fixtureId]
	if not box or not fixture then
		return
	end
	local s = fixture.storage[index]
	if not s or not near(player, s.cf.Position) then
		return
	end
	if s.box and s.box.Parent then
		throttledNotify(player, "Ese lugar ya tiene una caja.", "info")
		return
	end
	Boxes.carrying[player] = nil
	setCarryAttributes(player, nil)
	box:SetAttribute("CarrierId", nil)
	Boxes.storeBox(box, fixture, index)
end

local function pickUpStored(player, fixtureId, index)
	local fixture = Fixtures.list[fixtureId]
	local s = fixture and fixture.storage[index]
	if s and s.box and s.box.Parent then
		Boxes.pickUp(player, s.box)
	end
end

local function recycle(player, bin)
	local box = Boxes.carrying[player]
	if not box then
		throttledNotify(player, "Traé una caja vacía para reciclar.", "info")
		return
	end
	if bin and not near(player, bin.Position) then
		return
	end
	if isCrate(box) or (box:GetAttribute("Units") or 0) > 0 then
		throttledNotify(player, isCrate(box) and "Esa caja tiene un mueble adentro: armalo primero." or "Vaciá la caja antes de reciclarla.")
		return
	end
	Boxes.carrying[player] = nil
	setCarryAttributes(player, nil)
	local value = Boxes.recycleBox(box)
	State.notify(player, "♻ Caja reciclada: +" .. Config.formatMoney(value), "good")
end

-- Armar el mueble de la caja que lleva el jugador
local function placeCrate(player, x, z, rot)
	local crate = Boxes.carrying[player]
	if not crate or not isCrate(crate) then
		return false, "No llevás ninguna caja de mueble."
	end
	if type(x) ~= "number" or type(z) ~= "number" or type(rot) ~= "number" then
		return false, "Datos inválidos."
	end
	local fixtureType = crate:GetAttribute("FixtureType")
	local def = Config.Fixtures[fixtureType]
	if not def then
		return false, "Mueble desconocido."
	end
	x, z, rot = math.floor(x * 2 + 0.5) / 2, math.floor(z * 2 + 0.5) / 2, math.floor(rot) % 4
	local root = rootOf(player)
	if not root or (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude > 40 then
		return false, "Acercate más al lugar donde lo querés armar."
	end
	-- Se arma en el piso donde está parado el jugador
	local level = Config.levelAt(root.Position.Y)
	local ok, reason = Config.validatePlacement(fixtureType, x, z, rot, State.data.expansions, Fixtures.footprints(nil, level), level)
	if not ok then
		return false, reason
	end
	Boxes.carrying[player] = nil
	setCarryAttributes(player, nil)
	crate:Destroy()
	Fixtures.create(fixtureType, x, z, rot, nil, level)
	return true, "✔ Armaste: " .. def.name
end

function Boxes.init(builderRefs)
	refs = builderRefs
	folder = Instance.new("Folder")
	folder.Name = "Boxes"
	folder.Parent = workspace

	for _, bin in refs.recycleBins do
		bin:SetAttribute("Kind", "recycle")
	end

	Remotes.Action.OnServerEvent:Connect(function(player, kind, a, b)
		if kind == "pickup" then
			if typeof(a) == "Instance" and Boxes.all[a] then
				Boxes.pickUp(player, a)
			end
		elseif kind == "drop" then
			Boxes.drop(player)
		elseif kind == "recycle" then
			recycle(player, typeof(a) == "Instance" and a or nil)
		elseif type(a) == "string" and type(b) == "number" then
			if kind == "place" then
				placeUnit(player, a, b)
			elseif kind == "take" then
				takeUnit(player, a, b)
			elseif kind == "store" then
				storeCarried(player, a, b)
			elseif kind == "pickupStored" then
				pickUpStored(player, a, b)
			end
		end
	end)

	Remotes.PlaceCrate.OnServerInvoke = placeCrate

	local function hookPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					Boxes.drop(player)
				end)
			end
		end)
		player.CharacterRemoving:Connect(function()
			Boxes.drop(player)
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		Boxes.drop(player)
		lastNotify[player] = nil
	end)
end

return Boxes
