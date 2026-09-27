-- Crea (en el servidor) o espera (en el cliente) todos los RemoteEvents y RemoteFunctions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Notify", -- S->C (texto, tipo)
	"Snapshot", -- S->C precios, mejoras, empleados...
	"OpenOffice", -- S->C (pestaña)
	"Action", -- C->S (tipo, ...) interacciones con el mundo: poner, sacar, escanear...
	"PaymentOpen", -- S->C datos del cobro
	"PaymentClose", -- S->C
	"CheckoutState", -- S->C estado de la caja que atiende el jugador
	"DaySummary", -- S->C reporte de fin de día
	"Knockback", -- S->C al jugador le pegaron (cobradores)
	"OpenBank", -- S->C abrir la pantalla del cajero Tesoro Digital
}

local FUNCTIONS = {
	-- Tienda
	"GetSnapshot",
	"PlaceOrder",
	"BuyPerk",
	"BuyExpansion",
	"HireEmployee",
	"FireEmployee",
	"SetEmployeeRole",
	"SetPrice",
	"ConfirmPayment",
	"PlaceFixture",
	"BuyFixture", -- compra un mueble: llega en caja con la camioneta
	"PlaceCrate", -- arma el mueble de la caja que llevás en la mano
	"MoveFixture",
	"SellFixture",
	"TakeLoan",
	"PayLoan",
	"Customize",
	"SetRoomPassword",
	"BankTransfer", -- depositar / retirar en Tesoro Digital
	-- Menú principal
	"ListRooms",
	"MyRooms",
	"CreateRoom",
	"JoinRoom",
	"PlaySolo", -- entra a tu súper privado sin nombre ni contraseña (solo vos)
}

local isServer = RunService:IsServer()
local folder

if isServer then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function get(name, className)
	if isServer then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end
	return folder:WaitForChild(name)
end

local Remotes = {}
for _, name in EVENTS do
	Remotes[name] = get(name, "RemoteEvent")
end
for _, name in FUNCTIONS do
	Remotes[name] = get(name, "RemoteFunction")
end

return Remotes
