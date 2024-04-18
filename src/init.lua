local RunService = game:GetService("RunService")
local Common = require(script.Common)
local Controller = require(script.ReplicaController)
local Service = require(script.ReplicaService)

export type Replica = Common.Replica
export type Path = Common.Path
export type Filter = Common.Filter
export type Inclusion = Common.Inclusion

--[=[
	@class ReplicaModule

	Module that contains the Replica API.
]=]
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

--[=[
	@method ObserveActivePlayers
	@within ReplicaModule
	@server

	Calls observer for current active players and whenever a player is added to the active players list.

	@param observer (player: Player) -> () -- The function to call when a player is added to the active players list.
	@return Connection -- Signal Connection
]=]
function Replica:ObserveActivePlayers(observer: (player: Player) -> ()): RBXScriptConnection
	if not RunService:IsServer() then
		error("Replica:ObserveActivePlayers() can only be called on the server")
	end
	return Service:ObserveActivePlayers(observer)
end

--[=[
	@method OnActivePlayerRemoved
	@within ReplicaModule
	@server

	Calls listener whenever a player is removed from the active players list.

	@param listener (player: Player) -> () -- The function to call when a player is removed from the active players list.
	@return Connection -- Signal Connection
]=]
function Replica:OnActivePlayerRemoved(listener: (player: Player) -> ()): RBXScriptConnection
	if not RunService:IsServer() then
		error("Replica:OnActivePlayerRemoved() can only be called on the server")
	end
	return Service:OnActivePlayerRemoved(listener)
end

--[=[
	@method RegisterToken
	@within ReplicaModule
	@server

	Creates a new ReplicaToken.

	@param name string -- The name of the ReplicaToken.
	@return ReplicaToken -- The ReplicaToken.
]=]
function Replica:RegisterToken(name: string)
	if not RunService:IsServer() then
		error("Replica:RegisterToken() can only be called on the server")
	end
	return Service:RegisterToken(name)
end

--[=[
	@method NewReplica
	@within ReplicaModule
	@server

	Creates a new Replica.

	@param props ReplicaProps -- The properties to create the Replica with.
	@return Replica -- The Replica.
]=]
function Replica:NewReplica(props: Service.ReplicaProps): Replica
	if not RunService:IsServer() then
		error("Replica:NewReplica() can only be called on the server")
	end
	return Service:NewReplica(props)
end


--[[
	CLIENT
]]
--[=[
	@method RequestData
	@within ReplicaModule
	@client

	Requests the initial data from the server.
]=]
function Replica:RequestData()
	if not RunService:IsClient() then
		error("Replica:RequestData() can only be called on the client")
	end
	return Controller:RequestData()
end

--[=[
	@method OnNewReplica
	@within ReplicaModule
	@client

	Calls listener when a new Replica is created.

	@param listener (replica: Replica) -> () -- Callback function
	@return Connection -- Signal Connection
]=]
function Replica:OnNewReplica(listener: (replica: Replica) -> ()): RBXScriptConnection
	if not RunService:IsClient() then
		error("Replica:OnNewReplica() can only be called on the client")
	end
	return Controller:OnNewReplica(listener)
end

--[=[
	@method OnNewReplicaWithToken
	@within ReplicaModule
	@client

	Calls listener when a new Replica with the specified token is created.

	@param token string -- Replica token name
	@param listener (replica: Replica) -> () -- Callback function
	@return Connection -- Signal Connection
]=]
function Replica:OnNewReplicaWithToken(token: string, listener: (replica: Replica) -> ()): RBXScriptConnection
	if not RunService:IsClient() then
		error("Replica:OnNewReplicaWithToken() can only be called on the client")
	end
	return Controller:OnNewReplicaWithToken(token, listener)
end

--[=[
	@method OnInitialDataReceived
	@within ReplicaModule
	@client

	Calls listener when the initial data has been received from the server.

	@param listener () -> () -- Callback function
	@return Connection -- Signal Connection
]=]
function Replica:OnInitialDataReceived(listener: () -> ()): ()
	if not RunService:IsClient() then
		error("Replica:OnInitialDataReceived() can only be called on the client")
	end
	return Controller:OnInitialDataReceived(listener)
end


--[[
	SHARED
]]
--[=[
	@method GetReplicaById
	@within ReplicaModule
	@server
	@client

	Returns the Replica with the specified id.

	@param id string -- Replica id
	@return Replica? -- Replica
]=]
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
	Replica.ALL = Service.ALL
	Replica.INCLUDE = Service.INCLUDE
	Replica.EXCLUDE = Service.EXCLUDE
end
return Replica