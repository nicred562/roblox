-- Basura en el piso de la tienda: se limpia con la escoba y baja la satisfacción mientras esté.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent.State)
local Fixtures = require(script.Parent.Fixtures)

local Trash = {}
local folder
local count = 0
local MAX_TRASH = 15

function Trash.init()
	folder = Instance.new("Folder")
	folder.Name = "Trash"
	folder.Parent = workspace
end

function Trash.count()
	return count
end

function Trash.spawnAt(position)
	if count >= MAX_TRASH then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Trash"
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local kind = math.random(3)
	local base = CFrame.new(position.X, Config.FLOOR_Y, position.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	if kind == 1 then -- papel arrugado
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(0.6, 0.6, 0.6)
		p.Color = Color3.fromRGB(235, 235, 230)
		p.CFrame = base * CFrame.new(0, 0.3, 0)
	elseif kind == 2 then -- lata
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.8, 0.5, 0.5)
		p.Color = Color3.fromRGB(200, 40, 40)
		p.Material = Enum.Material.Metal
		p.CFrame = base * CFrame.new(0, 0.25, 0)
	else -- mancha
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.05, 2.4, 2.4)
		p.Color = Color3.fromRGB(120, 85, 40)
		p.Transparency = 0.2
		p.CFrame = base * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
	p:SetAttribute("Kind", "trash")
	p.Parent = folder
	CollectionService:AddTag(p, "Trash")
	count += 1
end

-- Lo llama la escoba
function Trash.clean(part)
	if part.Parent and CollectionService:HasTag(part, "Trash") then
		part:Destroy()
		count = math.max(0, count - 1)
		State.changeSatisfaction(0.5)
		return true
	end
	return false
end

local function insideFixture(x, z)
	for _, f in Fixtures.list do
		local fp = f.footprint
		if x > fp.minX - 1 and x < fp.maxX + 1 and z > fp.minZ - 1 and z < fp.maxZ + 1 then
			return true
		end
	end
	return false
end

function Trash.spawnRandom()
	local zones = {}
	for _, zone in Config.Zones do
		if zone.kind == "shop" and (zone.level or 0) == 0 and (not zone.expansion or State.hasExpansion(zone.expansion)) then
			table.insert(zones, zone)
		end
	end
	if #zones == 0 then
		return
	end
	for _ = 1, 10 do
		local zone = zones[math.random(#zones)]
		local x = zone.minX + 2 + math.random() * (zone.maxX - zone.minX - 4)
		local z = zone.minZ + 2 + math.random() * (zone.maxZ - zone.minZ - 4)
		if not insideFixture(x, z) then
			Trash.spawnAt(Vector3.new(x, 0, z))
			return
		end
	end
end

function Trash.step(dt)
	if count > 0 then
		State.changeSatisfaction(-0.015 * count * dt)
	end
end

return Trash
