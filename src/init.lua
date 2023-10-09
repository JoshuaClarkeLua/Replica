local RunService = game:GetService("RunService")
local Common = require(script.Common)
local Controller = require(script.ReplicaController)
local Service = require(script.ReplicaService)

export type Replica = Common.Replica
export type Path = Common.Path
export type FilterName = Common.FilterName
export type Inclusion = Common.Inclusion

local Replica = {}

function Replica:GetReplicaById(id: string): Replica?
	if RunService:IsServer() then
		return Service:GetReplicaById(id)
	end
	return Controller:GetReplicaById(id)
end


Replica.Controller = Controller
Replica.Service = Service
Replica.NIL = Common.NIL
return Replica