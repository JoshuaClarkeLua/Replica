--!strict
--[[
	@JCL
	(discord: jcl.)
]]
local RunService = game:GetService("RunService")
if RunService:IsServer() then
	return {}
end
local Comm = require(script.Parent.Parent.Comm)
local Signal = require(script.Parent.Parent.Signal)
local Trove = require(script.Parent.Parent.Trove)
local Common = require(script.Parent.Common)

type Signal = typeof(Signal.new(...))

-- ServerComm
local comm = Comm.ClientComm.new(script.Parent, false, "ReplicaService_Comm")
-- Receive init data signal
local requestData = comm:GetSignal("RequestData") -- (player: Player) -> ()
-- Create Comm RemoteSignals
local rep_Create = comm:GetSignal("Create") -- (id: string, token: string, tags: {[string]: any}, data: {[string]: any}, child_replica_data: {}, parentId: string?)
local rep_SetValue = comm:GetSignal("SetValue") -- (id: string, path: string, value: any)
local rep_SetValues = comm:GetSignal("SetValues") -- (id: string, path: string, values: {[string]: any})
local rep_ArrayInsert = comm:GetSignal("ArrayInsert") -- (id: string, path: string, index: number, value: any)
local rep_ArraySet = comm:GetSignal("ArraySet") -- (id: string, path: string, index: number, value: any)
local rep_ArrayRemove = comm:GetSignal("ArrayRemove") -- (id: string, path: string, index: number)
-- local rep_Write = comm:GetSignal("Write")
local rep_SetParent = comm:GetSignal("SetParent") -- (id: string, parentId: string)
local rep_Destroy = comm:GetSignal("Destroy") -- (id: string)
--
local replicas: { [string]: Replica } = {}
local onInitDataReceived = Signal.new() -- () -> ()
local onReplicaCreated = Signal.new() -- (replica: Replica) -> ()
local newReplicaSignals = {}

--[=[
	@class Replica

	An object that can be replicated to clients.
]=]
local Replica = {}
Replica.__index = Replica

local getPathPointer = Common.getPathPointer
local assertActive = Common.assertActive
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
	self._trove:Destroy()
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
export type Replica = typeof(Replica.new(...))

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

function Replica:OnDestroy(listener: (replica: Replica) -> ())
	assertActive(self)
	return self._OnDestroy:Connect(listener)
end

function Replica:SetValue(path: string, value: any, inclusion: { [Player]: boolean }?): ()
	local pointer, index = getPathPointer(self.Data, path)
	pointer[index] = value
end

function Replica:SetValues(path: string, values: { [string]: any }, inclusion: { [Player]: boolean }?): ()
	local pointer, index = getPathPointer(self.Data, path)
	for key, value in pairs(values) do
		pointer[index][key] = value
	end
end

function Replica:ArrayInsert(path: string, value: any, index: number?, inclusion: { [Player]: boolean }?): ()
	local pointer, pointer_index = getPathPointer(self.Data, path)
	local _index = index or #pointer[pointer_index] + 1
	table.insert(pointer[pointer_index], _index, value)
end

function Replica:ArraySet(path: string, index: number, value: any, inclusion: { [Player]: boolean }?): ()
	local pointer, _index = getPathPointer(self.Data, path)
	pointer[_index][index] = value
end

function Replica:ArrayRemove(path: string, index: number, inclusion: { [Player]: boolean }?): ()
	local pointer, _index = getPathPointer(self.Data, path)
	table.remove(pointer[_index], index)
end

function Replica:OnChange(path: string, listener: (new: any, old: any) -> ())
	return connectReplicaSignal(self, "_OnChange", path, listener)
end

function Replica:OnNewKey(path: string, listener: (keyOrIndex: string | number, value: any) -> ())
	return connectReplicaSignal(self, "_OnNewKey", path, listener)
end

function Replica:OnArrayInsert(path: string, listener: (index: number, value: any) -> ())
	return connectReplicaSignal(self, "_OnArrayInsert", path, listener)
end

function Replica:OnArraySet(path: string, listener: (index: number, value: any) -> ())
	return connectReplicaSignal(self, "_OnArraySet", path, listener)
end

function Replica:OnArrayRemove(path: string, listener: (index: number, value: any) -> ())
	return connectReplicaSignal(self, "_OnArrayRemove", path, listener)
end

function Replica:OnRawChange(path: string, listener: (actionName: string, pathArray: { string }, ...any) -> ())
	return connectReplicaSignal(self, "_OnRawChange", path, listener)
end

function Replica:OnChildAdded(listener: (child: Replica) -> ())
	return connectReplicaSignal(self, "_OnChildAdded", "", listener)
end

function Replica:ListenToRaw(listener: (action: string, pathTable: {string}, value: any) -> ())
	return connectReplicaSignal(self, "_ListenToRaw", "", listener)
end

--[=[
	@class ReplicaController

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

function ReplicaController:RequestData(): ()
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

function ReplicaController:OnNewReplica(listener: (replica: Replica) -> ())
	return onReplicaCreated:Connect(listener)
end

function ReplicaController:OnNewReplicaWithToken(token: string, listener: (replica: Replica) -> ())
	return getNewReplicaSignalForToken(token):Connect(listener)
end

function ReplicaController:OnInitialDataReceived(listener: () -> ()): any
	if ReplicaController.InitialDataReceived then
		task.spawn(listener)
	else
		return onInitDataReceived:Connect(listener)
	end
	return
end

function ReplicaController:GetReplicaById(id: string): Replica?
	return replicas[id]
end

rep_Create:Connect(Replica.new)
rep_SetValue:Connect(onSetValue)
rep_SetValues:Connect(onSetValues)
rep_ArrayInsert:Connect(onArrayInsert)
rep_ArraySet:Connect(onArraySet)
rep_ArrayRemove:Connect(onArrayRemove)
-- rep_Write:Connect(onWrite)
rep_SetParent:Connect(onSetParent)
rep_Destroy:Connect(onDestroy)
return ReplicaController
