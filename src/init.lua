local Controller = require(script.ReplicaController)
local Service = require(script.ReplicaService)

export type Client = Controller.Replica
export type Server = Service.Replica

return {
	Controller = Controller,
	Service = Service,
}