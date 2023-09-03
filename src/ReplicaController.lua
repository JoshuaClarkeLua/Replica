--!strict
--[[
	@JCL
	(discord: jcl.)
]]
local RunService = game:GetService("RunService")
local Comm = require(script.Parent.Parent.Comm)
local Signal = require(script.Parent.Parent.Signal)
local Trove = require(script.Parent.Parent.Trove)
local Fusion = require(script.Parent.Parent.Fusion)
local Common = require(script.Parent.Common)

type Signal = typeof(Signal.new(...))
type Connection = typeof(Signal.new():Connect(...))

-- Fusion Imports
type StateObject<T> = Fusion.StateObject<T>
--

-- ServerComm
local comm
-- Receive init data signal
local requestData
-- Create Comm RemoteSignals
local rep_Create
local rep_SetValue
local rep_SetValues
local rep_ArrayInsert
local rep_ArraySet
local rep_ArrayRemove
-- local rep_Write
local rep_SetParent
local rep_Destroy
--
local replicas: { [string]: Replica }
local onInitDataReceived
local onReplicaCreated
local newReplicaSignals

--[=[
	@class Replica

	An object that can be replicated to clients.
]=]
local Replica = {}
Replica.__index = Replica

local connectReplicaSignal = Common.connectReplicaSignal
local _onSetValue = Common.onSetValue
local _onSetValues = Common.onSetValues
local _onArrayInsert = Common.onArrayInsert
local _onArraySet = Common.onArraySet
local _onArrayRemove = Common.onArrayRemove
local _onSetParent = Common.onSetParent
local getState = Common.getState
local identify = Common.identify

local function onSetValue(id: string, ...: any): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	_onSetValue(self, ...)
end

local function onSetValues(id: string, ...: any): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	_onSetValues(self, ...)
end

local function onArrayInsert(id: string, ...: any): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	_onArrayInsert(self, ...)
end

local function onArraySet(id: string, ...: any): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	_onArraySet(self, ...)
end

local function onArrayRemove(id: string, ...: any): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	_onArrayRemove(self, ...)
end

local function onSetParent(id: string, parentId: string): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	-- Remove from old parent
	local parent = self:GetParent()
	if parent ~= nil then
		parent._children[self] = nil
	end
	-- Add to new parent
	self._parentId = parentId
	parent = self:GetParent()
	if parent == nil then
		error(`Failed to set parent of replica '{id}': Parent replica '{parentId}' does not exist!`)
	end
	parent._children[self] = true
	_onSetParent(self, parent)
end

local function onDestroy(id: string): ()
	local self = replicas[id]
	if self == nil then
		return
	end
	self._trove:Destroy()
end

function Replica:IsActive(): boolean
	return self._active == true
end

function Replica:Identify(): string
	return identify(self)
end

function Replica:GetToken(): string
	return self._token
end

function Replica:GetParent(): Replica?
	local id = self._parentId
	if id == nil then
		return
	end
	return replicas[id]
end

function Replica:GetChildren(): {[Replica]: true}
	return self._children
end

function Replica:OnDestroy(listener: (replica: Replica) -> ())
	if not self:IsActive() then
		task.spawn(listener, self)
		return
	end
	return self._OnDestroy:Connect(listener)
end

function Replica:SetValue(path: Common.Path, value: any, inclusion: { [Player]: boolean }?): ()
	_onSetValue(self, path)
end

function Replica:SetValues(path: Common.Path, values: { [Common.PathIndex]: any }, inclusion: { [Player]: boolean }?): ()
	_onSetValues(self, path, values)
end

function Replica:ArrayInsert(path: Common.Path, value: any, index: number?, inclusion: { [Player]: boolean }?): ()
	_onArrayInsert(self, path)
end

function Replica:ArraySet(path: Common.Path, index: number, value: any, inclusion: { [Player]: boolean }?): ()
	_onArraySet(self, path, index)
end

function Replica:ArrayRemove(path: Common.Path, index: number, inclusion: { [Player]: boolean }?): ()
	_onArrayRemove(self, path, index)
end

function Replica:OnChange(path: Common.Path, listener: (new: any, old: any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnChange, path, listener)
end

function Replica:OnNewKey(path: Common.Path?, listener: (key: any, value: any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnNewKey, path, listener)
end

function Replica:OnArrayInsert(path: Common.Path, listener: (index: number, value: any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnArrayInsert, path, listener)
end

function Replica:OnArraySet(path: Common.Path, listener: (index: number, value: any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnArraySet, path, listener)
end

function Replica:OnArrayRemove(path: Common.Path, listener: (index: number, value: any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnArrayRemove, path, listener)
end

function Replica:OnRawChange(path: Common.Path?, listener: (actionName: string, pathTable: Common.PathTable, ...any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnRawChange, path, listener)
end

function Replica:OnChildAdded(listener: (child: Replica) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnChildAdded, nil, listener)
end

function Replica:GetState(path: Common.Path?): StateObject<any>
	return getState(self, path)
end

function Replica.new(
	id: string,
	token: string,
	tags: { [string]: any },
	data: { [string]: any },
	child_replica_data: { [string]: any }?,
	parentId: string?
): Replica
	local trove = Trove.new()

	local self = setmetatable({
		-- Identification
		Id = id,
		_token = token,
		_active = true,
		-- Data
		Tags = tags,
		Data = data,
		_parentId = parentId,
		_children = {},
		-- Signals
		_OnDestroy = Signal.new(),
		-- _listeners = nil,
		-- Cleanup
		_trove = trove,
	}, Replica)
	replicas[self.Id] = self

	trove:Add(function()
		self._active = false
		replicas[self.Id] = nil

		for child in pairs(self._children) do
			child._trove:Destroy()
		end

		local parent = self:GetParent()
		if parent ~= nil then
			parent._children[self] = nil
		end

		self._OnDestroy:Fire(self)
		self._OnDestroy:Destroy()
	end)

	-- Create children (if any)
	local waitForParent = {}
	if child_replica_data ~= nil then
		for token, parentTable in pairs(child_replica_data) do
			for parentId, childTable in pairs(parentTable) do
				if not replicas[parentId] then
					waitForParent[parentId] = {}
				end
				for childId, childData in pairs(childTable) do
					local child = Replica.new(childId, token, childData[1], childData[2], nil, parentId)
					if waitForParent[childId] then
						for _, otherChild in ipairs(waitForParent[childId]) do
							child._children[otherChild] = true
						end
						waitForParent[childId] = nil
					end
					if waitForParent[parentId] then
						table.insert(waitForParent[parentId], child)
					end
				end
			end
		end
	end
	
	if next(waitForParent) ~= nil  then
		error(`Failed to construct replica '{id}': Parent replica '{self._parentId}' does not exist!`)
	end

	-- Add to parent (if any)
	if self._parentId ~= nil then
		local parent = self:GetParent()
		if parent then
			parent._children[self] = true
		end
	end

	onReplicaCreated:Fire(self)
	if newReplicaSignals[self._token] ~= nil then
		newReplicaSignals[self._token]:Fire(self)
	end

	return self
end
export type Replica = {
	Id: string,
	Tags: {[any]: any},
	Data: {[any]: any},
	-- Getters
	IsActive: (self: Replica) -> boolean,
	Identify: (self: Replica) -> string,
	GetToken: (self: Replica) -> string,
	GetParent: (self: Replica) -> Replica?,
	GetChildren: (self: Replica) -> {[Replica]: true},
	-- Mutator methods
	SetValue: (self: Replica, path: Common.Path, value: any, inclusion: {[Player]: boolean}?) -> (),
	SetValues: (self: Replica, path: Common.Path, values: {[Common.PathIndex]: any}, inclusion: {[Player]: boolean}?) -> (),
	ArrayInsert: (self: Replica, path: Common.Path, value: any, index: number?, inclusion: {[Player]: boolean}?) -> (),
	ArraySet: (self: Replica, path: Common.Path, index: number, value: any, inclusion: {[Player]: boolean}?) -> (),
	ArrayRemove: (self: Replica, path: Common.Path, index: number, inclusion: {[Player]: boolean}?) -> (),
	-- Listener methods
	OnDestroy: (self: Replica, listener: (replica: Replica) -> ()) -> Connection?,
	OnChange: (self: Replica, path: Common.Path, listener: (new: any, old: any) -> ()) -> Connection,
	OnNewKey: (self: Replica, path: Common.Path?, listener: (key: any, value: any) -> ()) -> Connection,
	OnArrayInsert: (self: Replica, path: Common.Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArraySet: (self: Replica, path: Common.Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArrayRemove: (self: Replica, path: Common.Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnRawChange: (self: Replica, path: Common.Path?, listener: (actionName: string, pathArray: Common.PathTable, ...any) -> ()) -> Connection,
	OnChildAdded: (self: Replica, listener: (child: Replica) -> ()) -> Connection,
	GetState: (self: Replica, path: Common.Path?) -> StateObject<any>,

	-- Private
	_token: string,
	_active: boolean,
	_parentId: string?,
	_children: {[Replica]: true},
	_listeners: {[any]: any}?,
	_OnDestroy: Signal,
	_trove: typeof(Trove.new()),
}


--[=[
	@class ReplicaController
	@client

	Manages the replication of Replicas to clients.
]=]
local ReplicaController = {}
ReplicaController.InitialDataReceived = false

local function getNewReplicaSignalForToken(token: string): Signal
	local signal = newReplicaSignals[token]
	if signal == nil then
		signal = Signal.new()
		newReplicaSignals[token] = signal
		signal.Connect = function(self, listener: (...any) -> ())
			local meta = getmetatable(self)
			local conn = meta.Connect(self, listener)
			local disconnect = function(self)
				local meta = getmetatable(self)
				meta.Disconnect(self)
				if #signal:GetConnections() == 0 then
					signal:Destroy()
					newReplicaSignals[token] = nil
				end
			end
			conn.Disconnect = disconnect
			return conn
		end
	end
	return signal
end

--[=[
	@method RequestData
	@within ReplicaController
	@client

	Requests the initial data from the server.
]=]
function ReplicaController:RequestData(): ()
	if not RunService:IsClient() then
		error("ReplicaController:RequestData() can only be called on the client!")
	end
	local conn
	conn = requestData:Connect(function(data)
		for id, rootReplica: {any} in pairs(data) do
			Replica.new(id, rootReplica[1], rootReplica[2], rootReplica[3], rootReplica[4])
		end
		conn:Disconnect()
		requestData:Destroy()
	end)
	requestData:Fire()
end

--[=[
	@method OnNewReplica
	@within ReplicaController
	@client

	Calls listener when a new Replica is created.

	@param listener (replica: Replica) -> () -- Callback function
	@return Connection -- Signal Connection
]=]
function ReplicaController:OnNewReplica(listener: (replica: Replica) -> ())
	if not RunService:IsClient() then
		error("ReplicaController:OnNewReplica() can only be called on the client!")
	end
	return onReplicaCreated:Connect(listener)
end

--[=[
	@method OnNewReplicaWithToken
	@within ReplicaController
	@client

	Calls listener when a new Replica with the specified token is created.

	@param token string -- Replica token name
	@param listener (replica: Replica) -> () -- Callback function
	@return Connection -- Signal Connection
]=]
function ReplicaController:OnNewReplicaWithToken(token: string, listener: (replica: Replica) -> ())
	if not RunService:IsClient() then
		error("ReplicaController:OnNewReplicaWithToken() can only be called on the client!")
	end
	return getNewReplicaSignalForToken(token):Connect(listener)
end

--[=[
	@method OnInitialDataReceived
	@within ReplicaController
	@client

	Calls listener when the initial data has been received from the server.

	@param listener () -> () -- Callback function
	@return Connection -- Signal Connection
]=]
function ReplicaController:OnInitialDataReceived(listener: () -> ()): any
	if not RunService:IsClient() then
		error("ReplicaController:OnInitialDataReceived() can only be called on the client!")
	end
	if ReplicaController.InitialDataReceived then
		task.spawn(listener)
	else
		return onInitDataReceived:Connect(listener)
	end
	return
end

--[=[
	@method GetReplicaById
	@within ReplicaController
	@client

	Returns the Replica with the specified id.

	@param id string -- Replica id
	@return Replica? -- Replica
]=]
function ReplicaController:GetReplicaById(id: string): Replica?
	if not RunService:IsClient() then
		error("ReplicaController:GetReplicaById() can only be called on the client!")
	end
	return replicas[id]
end

if RunService:IsClient() then
	replicas = {}
	onInitDataReceived = Signal.new() -- () -> ()
	onReplicaCreated = Signal.new() -- (replica: Replica) -> ()
	newReplicaSignals = {}
	--
	comm = Comm.ClientComm.new(script.Parent, false, "ReplicaService_Comm")
	-- Receive init data signal
	requestData = comm:GetSignal("RequestData") -- (player: Player) -> ()
	-- Create Comm RemoteSignals
	rep_Create = comm:GetSignal("Create") -- (id: string, token: string, tags: {[string]: any}, data: {[string]: any}, child_replica_data: {}, parentId: string?)
	rep_SetValue = comm:GetSignal("SetValue") -- (id: string, path: Common.Path, value: any)
	rep_SetValues = comm:GetSignal("SetValues") -- (id: string, path: Common.Path, values: {[string]: any})
	rep_ArrayInsert = comm:GetSignal("ArrayInsert") -- (id: string, path: Common.Path, index: number, value: any)
	rep_ArraySet = comm:GetSignal("ArraySet") -- (id: string, path: Common.Path, index: number, value: any)
	rep_ArrayRemove = comm:GetSignal("ArrayRemove") -- (id: string, path: Common.Path, index: number)
	-- rep_Write = comm:GetSignal("Write")
	rep_SetParent = comm:GetSignal("SetParent") -- (id: string, parentId: string)
	rep_Destroy = comm:GetSignal("Destroy") -- (id: string)
	--
	rep_Create:Connect(Replica.new)
	rep_SetValue:Connect(onSetValue)
	rep_SetValues:Connect(onSetValues)
	rep_ArrayInsert:Connect(onArrayInsert)
	rep_ArraySet:Connect(onArraySet)
	rep_ArrayRemove:Connect(onArrayRemove)
	-- rep_Write:Connect(onWrite)
	rep_SetParent:Connect(onSetParent)
	rep_Destroy:Connect(onDestroy)
end
return ReplicaController
