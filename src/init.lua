local Controller = require(script.ReplicaController)
local Service = require(script.ReplicaService)

export type Replica = Controller.Replica & Service.Replica

return {
	Controller = Controller,
	Service = Service,
}