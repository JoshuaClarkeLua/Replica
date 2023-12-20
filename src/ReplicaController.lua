--!strict
--[[
	@JCL
	(discord: jcl.)
]]
local RunService = game:GetService("RunService")
local Comm = require(script.Parent.Parent.Comm)
local Signal = require(script.Parent.Parent.Signal)
local Fusion = require(script.Parent.Parent.Fusion)
local Common = require(script.Parent.Common)

-- Fusion Imports
type Value<T> = Fusion.Value<T>
--

type Signal = Common.Signal
type Connection = Common.Connection

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
	self:_Destroy()
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
	if self._OnDestroy == nil then
		self._OnDestroy = Signal.new()
	end
	return self._OnDestroy:Connect(listener)
end

function Replica:SetValue(path: Common.Path, value: any, inclusion: { [Player]: boolean }?): ()
	_onSetValue(self, path, value)
end

function Replica:SetValues(path: Common.Path?, values: { [Common.PathIndex]: any }, inclusion: { [Player]: boolean }?): ()
	_onSetValues(self, path, values)
end

function Replica:ArrayInsert(path: Common.Path, value: any, index: number?, inclusion: { [Player]: boolean }?): ()
	_onArrayInsert(self, path, index, value)
end

function Replica:ArraySet(path: Common.Path, index: number, value: any, inclusion: { [Player]: boolean }?): ()
	_onArraySet(self, path, index, value)
end

function Replica:ArrayRemove(path: Common.Path, index: number, inclusion: { [Player]: boolean }?): ()
	_onArrayRemove(self, path, index)
end

function Replica:OnChange(path: Common.Path, listener: (new: any, old: any) -> ())
	return Common.connectOnChange(self, path, listener)
end

function Replica:OnValuesChanged(path: Common.Path?, listener: (new: {[Common.PathIndex]: any}, old: {[Common.PathIndex]: any}) -> ())
	return Common.connectOnValuesChanged(self, path, listener)
end

function Replica:OnNewKey(path: Common.Path?, listener: (key: any, value: any) -> ())
	return Common.connectOnNewKey(self, path, listener)
end

function Replica:OnArrayInsert(path: Common.Path, listener: (index: number, value: any) -> ())
	return Common.connectOnArrayInsert(self, path, listener)
end

function Replica:OnArraySet(path: Common.Path, listener: (index: number, value: any) -> ())
	return Common.connectOnArraySet(self, path, listener)
end

function Replica:OnArrayRemove(path: Common.Path, listener: (index: number, value: any) -> ())
	return Common.connectOnArrayRemove(self, path, listener)
end

function Replica:OnKeyChanged(path: Common.Path?, listener: (key: any, new: any, old: any) -> ())
	return Common.connectOnKeyChanged(self, path, listener)
end

function Replica:OnNil(path: Common.Path, listener: (old: any) -> (), once: boolean?): Connection
	return Common.connectOnNil(self, path, listener, once)
end

function Replica:OnRawChange(path: Common.Path?, listener: (actionName: string, pathTable: Common.PathTable, ...any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnRawChange, path, listener)
end

function Replica:OnChildAdded(listener: (child: Replica) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnChildAdded, nil, listener)
end

function Replica:ObserveState(path: Common.Path, valueObject: Value<any>): Connection
	return Common.observeState(self, path, valueObject)
end

function Replica:Observe(path: Common.Path, observer: (new: any, old: any) -> ()): Connection
	return Common.observe(self, path, observer)
end

function Replica.new(
	id: string,
	token: string,
	tags: { [string]: any },
	data: { [string]: any },
	child_replica_data: { [string]: any }?,
	parentId: string?
): Replica
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
	}, Replica)
	replicas[self.Id] = self

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
export type Replica = Common.Replica

function Replica:_Destroy(): ()
	self._active = false
	replicas[self.Id] = nil
	Common.cleanSignals(self)

	for child in pairs(self._children) do
		child:_Destroy()
	end

	local parent = self:GetParent()
	if parent ~= nil then
		parent._children[self] = nil
	end

	if self._OnDestroy ~= nil then
		self._OnDestroy:Fire(self)
		self._OnDestroy:Destroy()
	end
end


--[[
	@class ReplicaController
	@client

	Manages the replication of Replicas to clients.
]]
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

function ReplicaController:RequestData(): ()
	local conn
	conn = requestData:Connect(function(data)
		ReplicaController.InitialDataReceived = true
		for id, rootReplica: {any} in pairs(data) do
			Replica.new(id, rootReplica[1], rootReplica[2], rootReplica[3], rootReplica[4])
		end
		conn:Disconnect()
		requestData:Destroy()
		onInitDataReceived:Fire()
		onInitDataReceived:Destroy()
		onInitDataReceived = nil
	end)
	requestData:Fire()
end

function ReplicaController:OnNewReplica(listener: (replica: Replica) -> ())
	return onReplicaCreated:Connect(listener)
end

function ReplicaController:OnNewReplicaWithToken(token: string, listener: (replica: Replica) -> ())
	return getNewReplicaSignalForToken(token):Connect(listener)
end

function ReplicaController:OnInitialDataReceived(listener: () -> ()): ()
	if ReplicaController.InitialDataReceived then
		task.spawn(listener)
	else
		onInitDataReceived:Connect(listener)
	end
end

function ReplicaController:GetReplicaById(id: string): Replica?
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
