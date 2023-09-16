local Common = require(script.Common)
local Controller = require(script.ReplicaController)
local Service = require(script.ReplicaService)

export type Replica = Common.Replica
export type Path = Common.Path
export type FilterName = Common.FilterName
export type Inclusion = Service.Inclusion

return {
	Controller = Controller,
	Service = Service,
	--
	NIL = Common.NIL,
}