local RunService = game:GetService("RunService")
local Common = require(script.Common)
local Controller = require(script.ReplicaController)
local Service = require(script.ReplicaService)

export type Replica = Common.Replica
export type Path = Common.Path
export type FilterName = Common.FilterName
export type Inclusion = Common.Inclusion

local Replica = {}

--[[
	SERVER
]]
function Replica:ActivePlayers(): { [Player]: true }
	if not RunService:IsServer() then
		error("Replica:ActivePlayers() can only be called on the server")
	end
	return Service.ActivePlayers
end

function Replica:ObserveActivePlayers(observer: (player: Player) -> ()): RBXScriptConnection
	if not RunService:IsServer() then
		error("Replica:ObserveActivePlayers() can only be called on the server")
	end
	return Service:ObserveActivePlayers(observer)
end

function Replica:OnActivePlayerRemoved(listener: (player: Player) -> ()): RBXScriptConnection
	if not RunService:IsServer() then
		error("Replica:OnActivePlayerRemoved() can only be called on the server")
	end
	return Service:OnActivePlayerRemoved(listener)
end

function Replica:RegisterToken(name: string)
	if not RunService:IsServer() then
		error("Replica:RegisterToken() can only be called on the server")
	end
	return Service:RegisterToken(name)
end

function Replica:NewReplica(props: Service.ReplicaProps): Replica
	if not RunService:IsServer() then
		error("Replica:NewReplica() can only be called on the server")
	end
	return Service:NewReplica(props)
end


--[[
	CLIENT
]]
function Replica:RequestData()
	if not RunService:IsClient() then
		error("Replica:RequestData() can only be called on the client")
	end
	return Controller:RequestData()
end

function Replica:OnNewReplica(listener: (replica: Replica) -> ()): RBXScriptConnection
	if not RunService:IsClient() then
		error("Replica:OnNewReplica() can only be called on the client")
	end
	return Controller:OnNewReplica(listener)
end

function Replica:OnNewReplicaWithToken(token: string, listener: (replica: Replica) -> ()): RBXScriptConnection
	if not RunService:IsClient() then
		error("Replica:OnNewReplicaWithToken() can only be called on the client")
	end
	return Controller:OnNewReplicaWithToken(token, listener)
end

function Replica:OnInitialDataReceived(listener: () -> ()): ()
	if not RunService:IsClient() then
		error("Replica:OnInitialDataReceived() can only be called on the client")
	end
	return Controller:OnInitialDataReceived(listener)
end


--[[
	SHARED
]]
function Replica:GetReplicaById(id: string): Replica?
	if RunService:IsServer() then
		return Service:GetReplicaById(id)
	end
	return Controller:GetReplicaById(id)
end


Replica.Controller = Controller
Replica.Service = Service
Replica.NIL = Common.NIL
if RunService:IsServer() then
	Replica.TEMP = Service.Temporary
end
return Replica