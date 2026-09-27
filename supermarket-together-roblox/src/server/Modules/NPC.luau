-- NPCs (clientes, empleados, cobradores): apariencia, animaciones, movimiento, globos de texto y caídas.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")

local NPC = {}
NPC.GROUP = "NPCs"
NPC.PLAYER_GROUP = "Players"
NPC.RANDOM_AVATARS = true -- usa avatares de usuarios reales de Roblox para que se vean variados

pcall(function()
	PhysicsService:RegisterCollisionGroup(NPC.GROUP)
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup(NPC.PLAYER_GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(NPC.GROUP, NPC.GROUP, false)
PhysicsService:CollisionGroupSetCollidable(NPC.GROUP, NPC.PLAYER_GROUP, false)

local folder = workspace:FindFirstChild("NPCs") or Instance.new("Folder")
folder.Name = "NPCs"
folder.Parent = workspace
NPC.folder = folder

local SKINS = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 94),
	Color3.fromRGB(141, 85, 54), Color3.fromRGB(96, 60, 40),
}
local SHIRTS = {
	Color3.fromRGB(52, 120, 220), Color3.fromRGB(220, 80, 80), Color3.fromRGB(240, 200, 60),
	Color3.fromRGB(90, 170, 110), Color3.fromRGB(160, 90, 200), Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(40, 40, 45), Color3.fromRGB(255, 140, 60),
}
local PANTS = {
	Color3.fromRGB(40, 50, 90), Color3.fromRGB(30, 30, 30), Color3.fromRGB(110, 90, 70), Color3.fromRGB(80, 80, 85),
}

-- Animaciones R15 por defecto de Roblox
local WALK_ANIM = "rbxassetid://507777826"
local IDLE_ANIM = "rbxassetid://507766388"
local SIT_ANIM = "rbxassetid://2506281703"

local descriptionCache = {}
local nextUid = 0

local function pick(t)
	return t[math.random(#t)]
end

local function colorDescription(skin, shirt, pants)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = shirt
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	return desc
end

-- Avatar aleatorio de un usuario real (con caché y respaldo de colores)
local function randomDescription()
	if #descriptionCache > 0 and (math.random() < 0.4 or #descriptionCache >= 40) then
		return descriptionCache[math.random(#descriptionCache)]:Clone()
	end
	for _ = 1, 2 do
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(math.random(10000, 2500000000))
		end)
		if ok and desc then
			table.insert(descriptionCache, desc:Clone())
			return desc
		end
	end
	return nil
end

-- Rig simple de respaldo por si falla la creación del avatar
local function buildSimpleRig(skin, shirt, pants)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	local function body(name, size, color, y)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.CanCollide = false
		p.Massless = true
		p.CFrame = CFrame.new(0, y, 0)
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	body("Torso", Vector3.new(2, 2, 1), shirt, 3)
	body("Legs", Vector3.new(2, 2, 1), pants, 1)
	body("Head", Vector3.new(1.2, 1.2, 1.2), skin, 4.6)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

-- opts: displayName, walkSpeed, uniform = {shirt, pants}, randomAvatar (bool)
function NPC.create(name, opts)
	opts = opts or {}
	local skin = pick(SKINS)
	local shirt = opts.uniform and opts.uniform.shirt or pick(SHIRTS)
	local pants = opts.uniform and opts.uniform.pants or pick(PANTS)

	local desc
	if opts.randomAvatar and NPC.RANDOM_AVATARS then
		desc = randomDescription()
	end
	desc = desc or colorDescription(skin, shirt, pants)
	if opts.uniform then
		desc.TorsoColor = opts.uniform.shirt
		desc.LeftLegColor = opts.uniform.pants
		desc.RightLegColor = opts.uniform.pants
		desc.Shirt = 0
		desc.Pants = 0
		desc.GraphicTShirt = 0
	end

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	local fromDescription = ok and result ~= nil
	local model = fromDescription and result or buildSimpleRig(skin, shirt, pants)
	model.Name = name
	nextUid += 1
	model:SetAttribute("NpcId", nextUid)

	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = opts.displayName or ""
	humanoid.DisplayDistanceType = opts.displayName and Enum.HumanoidDisplayDistanceType.Viewer
		or Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 40
	humanoid.WalkSpeed = opts.walkSpeed or 12
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = NPC.GROUP
		end
	end

	return {
		model = model,
		humanoid = humanoid,
		root = model:FindFirstChild("HumanoidRootPart"),
		animated = fromDescription,
		cancelled = false,
		knocked = false,
		-- Cada NPC camina un poco corrido a un costado del camino: así dos que van al mismo
		-- lugar no quedan "fundidos" en las mismas coordenadas
		laneOffset = (math.random() - 0.5) * 1.5,
		uid = nextUid,
	}
end

local function setupAnimations(npc)
	local animator = npc.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = npc.humanoid
	end
	local function load(id)
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		return ok and track or nil
	end
	local walk, idle = load(WALK_ANIM), load(IDLE_ANIM)
	if idle then
		idle.Looped = true
		idle:Play()
	end
	-- Sentado en un banco
	local sit = load(SIT_ANIM)
	if sit then
		sit.Looped = true
		sit.Priority = Enum.AnimationPriority.Action
		npc.humanoid.Seated:Connect(function(active)
			if active then
				sit:Play(0.2)
			else
				sit:Stop(0.2)
			end
		end)
	end
	if not walk then
		return
	end
	walk.Looped = true
	npc.humanoid.Running:Connect(function(speed)
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.2)
			end
			walk:AdjustSpeed(speed / 12)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
end

function NPC.spawn(npc, position)
	npc.model:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	npc.model.Parent = folder
	pcall(function()
		npc.root:SetNetworkOwner(nil)
	end)
	if npc.animated then
		setupAnimations(npc)
	end
end

function NPC.alive(npc)
	return npc.model.Parent ~= nil and npc.root ~= nil and npc.root.Parent ~= nil
end

function NPC.flatDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- ¿Hay otro NPC justo adelante, yendo para el mismo lado? (para no caminar encimados)
local function someoneAhead(npc, dir)
	local pos = npc.root.Position
	for _, model in folder:GetChildren() do
		if model ~= npc.model then
			local r = model:FindFirstChild("HumanoidRootPart")
			if r then
				local offset = r.Position - pos
				offset = Vector3.new(offset.X, 0, offset.Z)
				local dist = offset.Magnitude
				if dist < 2.4 and dist > 0.05 then
					local ahead = offset:Dot(dir)
					-- adelante y casi en la misma línea
					if ahead > 0.3 and (offset - dir * ahead).Magnitude < 1.4 then
						return true
					end
				elseif dist <= 0.05 and (model:GetAttribute("NpcId") or 0) > (npc.uid or 0) then
					return true
				end
			end
		end
	end
	return false
end

local function waitMove(npc, timeout, target)
	local finished = false
	local conn = npc.humanoid.MoveToFinished:Connect(function()
		finished = true
	end)
	local humanoid = npc.humanoid
	local baseSpeed = humanoid.WalkSpeed
	local slowed = false
	local elapsed = 0
	while not finished and elapsed < timeout and not npc.cancelled and NPC.alive(npc) do
		elapsed += task.wait(0.15)
		if target and NPC.alive(npc) then
			local dir = Vector3.new(target.X - npc.root.Position.X, 0, target.Z - npc.root.Position.Z)
			if dir.Magnitude > 0.5 then
				-- Si alguien camina justo adelante, afloja el paso (como una persona de verdad)
				local shouldSlow = someoneAhead(npc, dir.Unit)
				if shouldSlow ~= slowed then
					slowed = shouldSlow
					humanoid.WalkSpeed = shouldSlow and baseSpeed * 0.45 or baseSpeed
				end
			end
		end
	end
	if slowed and NPC.alive(npc) then
		humanoid.WalkSpeed = baseSpeed
	end
	conn:Disconnect()
end

-- Camina hasta `target` con pathfinding. Devuelve true si llegó.
function NPC.walkTo(npc, target, timeout)
	timeout = timeout or 30
	if not NPC.alive(npc) or npc.cancelled then
		return false
	end
	local startTime = os.clock()
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.2,
		AgentHeight = 5,
		AgentCanJump = false,
		WaypointSpacing = 4,
		Costs = npc.pathCosts, -- los clientes evitan la zona "StaffOnly"
	})
	local ok = pcall(function()
		path:ComputeAsync(npc.root.Position, target)
	end)
	local waypoints
	if ok and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
	else
		waypoints = { { Position = target } }
	end

	local stuck = 0
	local previous = npc.root.Position
	for index, wp in ipairs(waypoints) do
		if npc.cancelled or not NPC.alive(npc) then
			return false
		end
		if os.clock() - startTime > timeout then
			break
		end
		local before = npc.root.Position
		-- Punto del camino corrido a su "carril" personal (menos el último, que es el destino exacto)
		local goal = wp.Position
		if index < #waypoints then
			local d = Vector3.new(goal.X - previous.X, 0, goal.Z - previous.Z)
			if d.Magnitude > 0.5 then
				d = d.Unit
				goal += Vector3.new(-d.Z, 0, d.X) * (npc.laneOffset or 0)
			end
		end
		previous = wp.Position
		npc.humanoid:MoveTo(goal)
		waitMove(npc, 4, goal)
		-- Desatascar: si no avanzó dos veces seguidas, lo ponemos en el punto del camino
		if not npc.cancelled and NPC.alive(npc) and (npc.root.Position - before).Magnitude < 0.8 and NPC.flatDistance(npc.root.Position, wp.Position) > 2 then
			stuck += 1
			if stuck >= 2 and not npc.knocked then
				npc.root.CFrame = CFrame.new(wp.Position + Vector3.new(0, npc.humanoid.HipHeight + npc.root.Size.Y / 2 + 0.2, 0))
				stuck = 0
			end
		else
			stuck = 0
		end
	end
	if npc.cancelled or not NPC.alive(npc) then
		return false
	end
	if NPC.flatDistance(npc.root.Position, target) > 2.5 then
		npc.humanoid:MoveTo(target)
		waitMove(npc, 4, target)
	end
	return NPC.alive(npc) and NPC.flatDistance(npc.root.Position, target) <= 3
end

function NPC.stop(npc)
	npc.cancelled = true
	if NPC.alive(npc) then
		npc.humanoid:MoveTo(npc.root.Position)
	end
end

function NPC.resume(npc)
	npc.cancelled = false
end

function NPC.face(npc, position)
	if not NPC.alive(npc) or npc.knocked then
		return
	end
	local pos = npc.root.Position
	local look = Vector3.new(position.X, pos.Y, position.Z)
	if (look - pos).Magnitude > 0.1 then
		npc.root.CFrame = CFrame.lookAt(pos, look)
	end
end

-- Se sienta en un asiento (Seat). Devuelve true si quedó sentado.
function NPC.sit(npc, seat)
	if not NPC.alive(npc) or not seat or seat.Occupant then
		return false
	end
	local wasDisabled = seat.Disabled
	seat.Disabled = false
	seat:Sit(npc.humanoid)
	task.wait(0.2)
	local ok = seat.Occupant == npc.humanoid
	if not ok then
		seat.Disabled = wasDisabled
	end
	return ok
end

function NPC.standUp(npc, seat)
	if NPC.alive(npc) then
		npc.humanoid.Sit = false
		npc.humanoid.Jump = true
	end
	if seat then
		task.delay(0.5, function()
			if not seat.Occupant then
				seat.Disabled = true
			end
		end)
	end
end

-- Lo tira al piso (escobazo); vuelve a pararse después de `duration`
function NPC.knockDown(npc, fromPosition, duration)
	if npc.knocked or not NPC.alive(npc) then
		return
	end
	npc.knocked = true
	NPC.stop(npc)
	local humanoid = npc.humanoid
	humanoid.PlatformStand = true
	local dir = npc.root.Position - fromPosition
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, 1)
	end
	npc.root.AssemblyLinearVelocity = dir.Unit * 22 + Vector3.new(0, 16, 0)
	npc.root.AssemblyAngularVelocity = Vector3.new(4, 0, 4)
	task.wait(duration or 1.6)
	if NPC.alive(npc) then
		humanoid.PlatformStand = false
		local pos = npc.root.Position
		npc.root.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0))
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	npc.knocked = false
	npc.cancelled = false
end

local function head(npc)
	return npc.model and npc.model:FindFirstChild("Head")
end

-- Globo de texto sobre la cabeza
function NPC.say(npc, text, duration)
	local h = head(npc)
	if not h then
		return
	end
	local bb = h:FindFirstChild("Speech")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "Speech"
		bb.Size = UDim2.fromOffset(230, 52)
		bb.StudsOffset = Vector3.new(0, 2.8, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 55
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.new(1, 1, 1)
		label.TextColor3 = Color3.fromRGB(30, 30, 30)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = label
		bb.Parent = h
	end
	bb.Label.Text = text
	bb.Enabled = true
	local token = {}
	npc.speechToken = token
	task.delay(duration or 3, function()
		if npc.speechToken == token and bb.Parent then
			bb.Enabled = false
		end
	end)
end

-- Ícono fijo sobre la cabeza (ladrón, cobrador); nil lo saca
function NPC.setIcon(npc, text, color)
	local h = head(npc)
	if not h then
		return
	end
	local bb = h:FindFirstChild("Icon")
	if not text then
		if bb then
			bb:Destroy()
		end
		return
	end
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "Icon"
		bb.Size = UDim2.fromOffset(120, 34)
		bb.StudsOffset = Vector3.new(0, 4.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 120
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		bb.Parent = h
	end
	bb.Label.Text = text
	bb.Label.BackgroundColor3 = color or Color3.fromRGB(200, 40, 40)
end

-- Canasto de compras en la mano
function NPC.addBasket(npc)
	local hand = npc.model:FindFirstChild("RightHand") or npc.root
	if not hand then
		return
	end
	local basket = Instance.new("Part")
	basket.Name = "Basket"
	basket.Size = Vector3.new(1.1, 0.6, 0.8)
	basket.Color = Color3.fromRGB(200, 40, 40)
	basket.CanCollide = false
	basket.CanQuery = false
	basket.Massless = true
	basket.CollisionGroup = NPC.GROUP
	basket.CFrame = hand.CFrame * CFrame.new(0, -0.7, 0)
	basket.Parent = npc.model
	local handle = Instance.new("Part")
	handle.Name = "BasketHandle"
	handle.Size = Vector3.new(0.12, 0.5, 0.7)
	handle.Color = Color3.fromRGB(40, 40, 40)
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CollisionGroup = NPC.GROUP
	handle.CFrame = hand.CFrame * CFrame.new(0, -0.25, 0)
	handle.Parent = npc.model
	for _, p in { basket, handle } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
	end
end

return NPC
