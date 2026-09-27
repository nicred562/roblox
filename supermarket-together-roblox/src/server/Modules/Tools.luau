-- Herramientas de cada jugador: Escoba (limpiar, pegarle a ladrones y cobradores)
-- y Pistola de precios (apuntás a un producto y cambiás el precio con la rueda del mouse).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.State)
local NPC = require(script.Parent.NPC)
local Fixtures = require(script.Parent.Fixtures)
local Boxes = require(script.Parent.Boxes)
local Trash = require(script.Parent.Trash)
local Customers = require(script.Parent.Customers)
local Loans = require(script.Parent.Loans)

local Tools = {}
local templates = {}
local cooldown = {}

local BROOM_GRIP = CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(-35), 0, 0)

local function weldTo(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

local function makeBroom()
	local tool = Instance.new("Tool")
	tool.Name = "Escoba"
	tool.ToolTip = "Click: barrer y pegarle a ladrones"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = BROOM_GRIP
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.25, 5, 0.25)
	handle.Color = Color3.fromRGB(160, 110, 60)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local head = Instance.new("Part")
	head.Name = "Bristles"
	head.Size = Vector3.new(1.8, 0.7, 0.45)
	head.Color = Color3.fromRGB(230, 190, 60)
	head.Material = Enum.Material.Fabric
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 2.7, 0)
	head.Parent = tool
	weldTo(handle, head)
	return tool
end

local function makePriceGun()
	local tool = Instance.new("Tool")
	tool.Name = "Pistola de precios"
	tool.ToolTip = "Apuntá a un producto y usá la rueda del mouse (o Z / X)"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 0.9, 0.35)
	handle.Color = Color3.fromRGB(240, 140, 30)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(0.5, 0.5, 0.9)
	body.Color = Color3.fromRGB(50, 50, 55)
	body.CanCollide = false
	body.Massless = true
	body.CFrame = handle.CFrame * CFrame.new(0, 0.6, 0)
	body.Parent = tool
	weldTo(handle, body)
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(0.4, 0.05, 0.5)
	screen.Color = Color3.fromRGB(120, 230, 140)
	screen.Material = Enum.Material.Neon
	screen.CanCollide = false
	screen.Massless = true
	screen.CFrame = handle.CFrame * CFrame.new(0, 0.87, 0)
	screen.Parent = tool
	weldTo(handle, screen)
	return tool
end

local function swing(tool)
	local out = TweenService:Create(tool, TweenInfo.new(0.1), { Grip = BROOM_GRIP * CFrame.Angles(math.rad(70), 0, 0) })
	out:Play()
	out.Completed:Once(function()
		TweenService:Create(tool, TweenInfo.new(0.18), { Grip = BROOM_GRIP }):Play()
	end)
end

local function onBroom(tool)
	local character = tool.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not player or not root then
		return
	end
	if (cooldown[player] or 0) > os.clock() then
		return
	end
	cooldown[player] = os.clock() + 0.5
	swing(tool)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local parts = workspace:GetPartBoundsInBox(root.CFrame * CFrame.new(0, -0.5, -3), Vector3.new(5, 6, 5.5), params)
	local hitModels = {}
	for _, part in parts do
		if CollectionService:HasTag(part, "Trash") then
			Trash.clean(part)
		elseif CollectionService:HasTag(part, "Dropped") then
			Customers.recoverDropped(part, player)
		else
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model.Parent == NPC.folder and not hitModels[model] then
				hitModels[model] = true
				if not Customers.hitNPC(model, root.Position, player.DisplayName) then
					Loans.hitCollector(model, root.Position, player)
				end
			end
		end
	end
end

local function giveTools(player)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then
		return
	end
	for name, template in templates do
		if not backpack:FindFirstChild(name) and not (player.Character and player.Character:FindFirstChild(name)) then
			local tool = template:Clone()
			if name == "Escoba" then
				tool.Activated:Connect(function()
					onBroom(tool)
				end)
			end
			tool.Parent = backpack
		end
	end
end

local function hookPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(giveTools, player)
		-- No se puede usar una herramienta con una caja en la mano
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and Boxes.carrying[player] then
				task.defer(function()
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid:UnequipTools()
					end
				end)
				State.notify(player, "Soltá la caja (F) para usar herramientas.", "warn")
			end
		end)
	end)
	if player.Character then
		task.defer(giveTools, player)
	end
end

function Tools.init()
	templates["Escoba"] = makeBroom()
	templates["Pistola de precios"] = makePriceGun()

	Remotes.SetPrice.OnServerInvoke = function(_player, productId, cents)
		local prod = type(productId) == "string" and Config.ProductsById[productId]
		if not prod or not State.isProductUnlocked(productId) or type(cents) ~= "number" or cents ~= cents then
			return false, "Precio inválido."
		end
		cents = math.clamp(math.floor(cents + 0.5), 1, State.getMarket(productId) * 5)
		State.setPrice(productId, cents)
		Fixtures.refreshLabels()
		return true, cents
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		cooldown[player] = nil
	end)
end

return Tools
