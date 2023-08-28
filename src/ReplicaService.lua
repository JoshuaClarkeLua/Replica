--!strict
--[[
	@JCL
	(discord: jcl.)
]]
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Comm = require(script.Parent.Parent.Comm)
local Signal = require(script.Parent.Parent.Signal)
local Trove = require(script.Parent.Parent.Trove)
local Common = require(script.Parent.Common)

export type FilterName = "All" | "Include" | "Exclude"
export type Filter = number

export type ReplicaProps = {
	Token: ReplicaToken,
	Tags: { [string]: any }?, -- Default: {}
	Data: { [string]: any }?, -- Default: {}
	Filter: FilterName?, -- Default: "All"
	FilterList: { [Player]: true }?, -- Default: {}
	Parent: Replica?, -- Default: nil
	-- WriteLib: any, -- ModuleScript
}

export type Signal = typeof(Signal.new(...))

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
local activePlayers: { [Player]: true }
local replicaTokens: { [string]: ReplicaToken }
local replicas: { [string]: Replica }
local FILTER: {
	All: number,
	Include: number,
	Exclude: number,
}
-- Signals
local onActivePlayerAdded
local onActivePlayerRemoved

--[=[
	@class Replica

	An object that can be replicated to clients.
]=]
local Replica = {}
Replica.__index = Replica


local connectReplicaSignal = Common.connectReplicaSignal
local onSetValue = Common.onSetValue
local onSetValues = Common.onSetValues
local onArrayInsert = Common.onArrayInsert
local onArraySet = Common.onArraySet
local onArrayRemove = Common.onArrayRemove
local _onSetParent = Common.onSetParent
local identify = Common.identify


local function fireRemoteSignalForReplica(self: Replica, signal: any, inclusion: { [Player]: boolean }?, ...: any): ()
	local replicationFilter = self:GetFilter()
	if replicationFilter == FILTER.All then
		signal:FireFilter(function(player: Player)
			if not activePlayers[player] then
				return false
			end
			return if inclusion ~= nil and inclusion[player] ~= nil then inclusion[player] else true
		end, self.Id, ...)
	else
		signal:FireFilter(function(player: Player)
			if not activePlayers[player] then
				return false
			end
			if inclusion ~= nil and inclusion[player] ~= nil then
				return inclusion[player]
			end
			if replicationFilter == FILTER.Include then
				return self:GetFilterList()[player] ~= nil
			elseif replicationFilter == FILTER.Exclude then
				return self:GetFilterList()[player] == nil
			end
			return false
		end, self.Id, ...)
	end
end

local function replicateFor(self: Replica, player: Player): ()
	if activePlayers[player] then
		rep_Create:Fire(
			player,
			self.Id,
			self._token.name,
			self.Tags,
			self.Data,
			if self._parent == nil then self:_GetChildReplicaData() else nil,
			if self._parent ~= nil then self._parent.Id else nil
		)
	end
end

local function destroyFor(self: Replica, player: Player): ()
	if activePlayers[player] then
		rep_Destroy:Fire(player, self.Id)
	end
end

local function shouldReplicateForPlayer(self: Replica, player: Player): boolean
	local filter = self:GetFilter()
	local filterList = self:GetFilterList()
	if filter == FILTER.All then
		return true
	else
		if filterList[player] ~= nil then
			return filter == FILTER.Include
		else
			return filter == FILTER.Exclude
		end
	end
end

local function updateReplicationForPlayer(
	self: Replica,
	player: Player,
	oldFilter: Filter,
	oldPlayers: { [Player]: true },
	newFilter: Filter,
	newPlayers: { [Player]: true }
): boolean? -- Created = true, Destroyed = false, None = nil
	local change: boolean? = nil

	if oldFilter == FILTER.All then
		if
			(newFilter == FILTER.Include and newPlayers[player] == nil)
			or (newFilter == FILTER.Exclude and newPlayers[player] ~= nil)
		then
			change = false
		end
	elseif newFilter == FILTER.All then
		if oldFilter == FILTER.Include then
			if oldPlayers[player] == nil then
				change = true
			end
		elseif oldFilter == FILTER.Exclude then
			if oldPlayers[player] ~= nil then
				change = true
			end
		end
	elseif newFilter == oldFilter then
		if oldPlayers[player] == nil and newPlayers[player] ~= nil then
			change = oldFilter == FILTER.Include
		elseif oldPlayers[player] ~= nil and newPlayers[player] == nil then
			change = oldFilter == FILTER.Exclude
		end
	else
		if oldPlayers[player] ~= nil and newPlayers[player] ~= nil then
			change = oldFilter == FILTER.Exclude
		elseif oldPlayers[player] == nil and newPlayers[player] == nil then
			change = oldFilter == FILTER.Include
		end
	end
	if change == true then
		replicateFor(self, player)
	elseif change == false then
		destroyFor(self, player)
	end
	return change
end

local function updateReplication(
	self: Replica,
	oldFilter: Filter,
	oldPlayers: { [Player]: true },
	newFilter: Filter,
	newPlayers: { [Player]: true }
): { [Player]: boolean }
	local changeList = {}
	if self._parent == nil then
		self._filter = newFilter
		self._filterList = newPlayers
	end
	for player in pairs(activePlayers) do
		local change = updateReplicationForPlayer(self, player, oldFilter, oldPlayers, newFilter, newPlayers)
		if change ~= nil then
			changeList[player] = change
		end
	end
	return changeList
end

local function _addChildData(self: Replica, child: Replica): ()
	local childData = {
		child.Tags,
		child.Data,
	}
	local childReplicaData = self:_GetChildReplicaData()
	local parentTable = childReplicaData[child._token.name]
	if parentTable == nil then
		parentTable = {}
		childReplicaData[child._token.name] = parentTable
	end
	local childTable = parentTable[self.Id]
	if childTable == nil then
		childTable = {}
		parentTable[self.Id] = childTable
	end
	childTable[child.Id] = childData
end

local function addChild(self: Replica, child: Replica): ()
	for _otherChild in pairs(child._children) do
		_addChildData(child, _otherChild)
	end

	self._children[child] = true
	_addChildData(self, child)
end

local function _removeChildData(self: Replica, child: Replica): ()
	local childReplicaData = self:_GetChildReplicaData()
	local parentTable = childReplicaData[child._token.name]
	if parentTable == nil then
		return
	end
	local childTable = parentTable[self.Id]
	if childTable == nil then
		return
	end
	childTable[child.Id] = nil
	if next(childTable) == nil then
		parentTable[self.Id] = nil
		if next(parentTable) == nil then
			childReplicaData[child._token.name] = nil
		end
	end
end

local function removeChild(self: Replica, child: Replica): ()
	for _otherChild in pairs(child._children) do
		_removeChildData(child, _otherChild)
	end

	self._children[child] = nil
	_removeChildData(self, child)
end

local function setParent(self: Replica, parent: Replica): ()
	local oldFilter = self:GetFilter()
	local oldPlayers = self:GetFilterList()
	local newFilter = parent:GetFilter()
	local newPlayers = parent:GetFilterList()
	-- remove from old parent
	removeChild(self._parent, self)
	-- add to new parent
	self._parent = parent
	addChild(parent, self)
	--

	local inclusion = updateReplication(self, oldFilter, oldPlayers, newFilter, newPlayers)
	for player, change in pairs(inclusion) do
		inclusion[player] = not change
	end
	fireRemoteSignalForReplica(self, rep_SetParent, inclusion, parent.Id)
end

local function initReplication(self: Replica): ()
	for player in pairs(activePlayers) do
		if shouldReplicateForPlayer(self, player) then
			replicateFor(self, player)
		end
	end
end

local function addToFilter(self: Replica, player: Player): ()
	if self._parent ~= nil then
		error(`Cannot add to filter list of non-root Replica`)
	end
	if self._filter == FILTER.All or self._filterList[player] ~= nil then
		return
	end
	self._filterList[player] = true
	if shouldReplicateForPlayer(self, player) then
		replicateFor(self, player)
	else
		destroyFor(self, player)
	end
end

local function removeFromFilter(self: Replica, player: Player): ()
	if self._parent ~= nil then
		error(`Cannot remove from filter list of non-root Replica`)
	end
	if self._filter == FILTER.All or self._filterList[player] == nil then
		return
	end
	self._filterList[player] = nil
	if shouldReplicateForPlayer(self, player) then
		replicateFor(self, player)
	else
		destroyFor(self, player)
	end
end

local function onPlayerRemoving(player: Player): ()
	activePlayers[player] = nil
	for _, replica in pairs(replicas) do
		if replica._parent == nil then
			replica._filterList[player] = nil
		end
	end
end

local function onPlayerRequestData(player: Player): ()
	if not player:IsDescendantOf(game) then
		return
	end
	activePlayers[player] = true
	local data = {}
	for id, replica in pairs(replicas) do
		if replica._parent == nil and shouldReplicateForPlayer(replica, player) then
			-- replicateFor(replica, player)
			data[id] = {
				replica:GetToken().name,
				replica.Tags,
				replica.Data,
				replica:_GetChildReplicaData(),
			}
		end
	end
	requestData:Fire(player, data)
end


function Replica.new(props: ReplicaProps): Replica
	local trove = Trove.new()

	local replicationFilter = FILTER[props.Filter or "All"]
	local filterList = props.FilterList

	if props.Parent == nil and (filterList == nil or replicationFilter == FILTER.All) then
		filterList = {}
	end

	local self = setmetatable({
		-- Identification
		Id = HttpService:GenerateGUID(false),
		_token = props.Token,
		_active = true,
		-- Data
		Tags = (props.Tags or {}) :: { [any]: any },
		Data = (props.Data or {}) :: { [any]: any },
		_parent = props.Parent,
		-- Replication
		_filter = props.Parent == nil and replicationFilter or nil,
		_filterList = props.Parent == nil and filterList or nil,
		_child_replica_data = props.Parent == nil and {} or nil,
		_children = {},
		-- Signals (setting them to nil uses memory...)
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

		if self._parent ~= nil then
			removeChild(self._parent, self)
		end

		self._OnDestroy:Fire(self)
		self._OnDestroy:Destroy()
	end)

	if self._parent ~= nil then
		addChild(self._parent, self)
	end

	initReplication(self)
	return self
end
export type Replica = typeof(Replica.new(...))

function Replica:IsActive(): boolean
	return self._active
end

function Replica:Identify(): string
	return identify(self)
end

function Replica:GetToken(): ReplicaToken
	return self._token
end

function Replica:GetFilter(): Filter
	return self._filter or self._parent:GetFilter()
end

function Replica:GetFilterList(): { [Player]: true }
	return self._filterList or self._parent:GetFilterList()
end

function Replica:_GetChildReplicaData(): { [string]: any }
	return self._child_replica_data or self._parent:_GetChildReplicaData()
end

function Replica:SetValue(path: Common.Path, value: any, inclusion: { [Player]: boolean }?): ()
	onSetValue(self, path, value)
	fireRemoteSignalForReplica(self, rep_SetValue, inclusion, path, value)
end

function Replica:SetValues(path: Common.Path, values: { [Common.PathIndex]: any }, inclusion: { [Player]: boolean }?): ()
	onSetValues(self, path, values)
	fireRemoteSignalForReplica(self, rep_SetValues, inclusion, path, values)
end

function Replica:ArrayInsert(path: Common.Path, value: any, index: number?, inclusion: { [Player]: boolean }?): ()
	local _index = onArrayInsert(self, path, index, value)
	fireRemoteSignalForReplica(self, rep_ArrayInsert, inclusion, path, _index, value)
end

function Replica:ArraySet(path: Common.Path, index: number, value: any, inclusion: { [Player]: boolean }?): ()
	onArraySet(self, path, index, value)
	fireRemoteSignalForReplica(self, rep_ArraySet, inclusion, path, index, value)
end

function Replica:ArrayRemove(path: Common.Path, index: number, inclusion: { [Player]: boolean }?): ()
	onArrayRemove(self, path, index)
	fireRemoteSignalForReplica(self, rep_ArrayRemove, inclusion, path, index)
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

function Replica:OnDestroy(listener: (replica: Replica) -> ())
	if not self:IsActive() then
		task.spawn(listener, self)
		return
	end
	return self._OnDestroy:Connect(listener)
end

-- function Replica:Write(): ()
--
-- end
--[[
	SERVER ONLY
]]
function Replica:SetParent(parent: Replica): ()
	if self._parent == nil then
		error(`Could not set parent: A root Replica cannot have parents`)
	end
	if not parent then
		error(`Could not set parent: Parent cannot be nil`)
	end
	if parent == (self :: Replica) then
		error(`Could not set parent: Parent cannot be itself`)
	end
	local _parent = parent
	while _parent._parent ~= nil do
		_parent = _parent._parent
		if _parent == (self :: Replica) then
			error(`Could not set parent: Trying to set a descendant as parent`)
		end
	end
	setParent(self, parent)
	_onSetParent(self, parent)
end

function Replica:SetReplication(settings: {
	filter: Filter?,
	players: { [Player]: true }?,
}): ()
	if self._parent ~= nil then
		error(`Cannot set replication settings for non-root Replica`)
	end
	if settings.filter == nil and settings.players == nil then
		return
	end
	local newFilter = settings.filter and FILTER[settings.filter] or self._filter
	local newFilterList = settings.players or self._filterList
	if newFilter == FILTER.All then
		newFilterList = {}
	end
	updateReplication(
		self,
		self._filter,
		self._filterList :: { [Player]: true },
		newFilter,
		newFilterList
	)
end

function Replica:AddToFilter(player: Player): ()
	addToFilter(self, player)
end

function Replica:RemoveFromFilter(player: Player): ()
	removeFromFilter(self, player)
end

function Replica:Destroy(): ()
	fireRemoteSignalForReplica(self, rep_Destroy)
	self._trove:Destroy()
end

--[=[
	@class ReplicaService

	Manages the replication of Replicas to clients.
]=]
local ReplicaService = {}

function ReplicaService:ActivePlayers()
	if not RunService:IsServer() then
		error("ReplicaService:ActivePlayers() can only be called on the server")
	end
	return activePlayers
end

function ReplicaService:ObserveActivePlayers(observer: (player: Player) -> ())
	if not RunService:IsServer() then
		error("ReplicaService:ObserveActivePlayers() can only be called on the server")
	end
	for player in pairs(activePlayers) do
		task.spawn(observer, player)
	end
	return onActivePlayerAdded:Connect(observer)
end

function ReplicaService:OnActivePlayerRemoved(listener: (player: Player) -> ())
	if not RunService:IsServer() then
		error("ReplicaService:OnActivePlayerRemoved() can only be called on the server")
	end
	return onActivePlayerRemoved:Connect(listener)
end

function ReplicaService:RegisterToken(name: string): ReplicaToken
	if not RunService:IsServer() then
		error("ReplicaService:RegisterToken() can only be called on the server")
	end
	assert(replicaTokens[name] == nil, `ReplicaToken "{name}" already exists!`)
	local token = setmetatable({
		__ClassName = "ReplicaToken",
		name = name,
	}, {
		__tostring = function(self)
			return self.name
		end,
	})
	replicaTokens[name] = token
	return token
end
export type ReplicaToken = typeof(ReplicaService:RegisterToken(...))

function ReplicaService:NewReplica(props: ReplicaProps)
	if not RunService:IsServer() then
		error("ReplicaService:NewReplica() can only be called on the server")
	end
	return Replica.new(props)
end

if RunService:IsServer() then
	-- ServerComm
	comm = Comm.ServerComm.new(script.Parent, "ReplicaService_Comm")
	-- Receive init data signal
	requestData = comm:CreateSignal("RequestData") -- (player: Player) -> ()
	-- Create Comm RemoteSignals
	rep_Create = comm:CreateSignal("Create") -- (id: string, token: string, tags: {[string]: any}, data: {[string]: any}, child_replica_data: {}, parentId: string?)
	rep_SetValue = comm:CreateSignal("SetValue") -- (id: string, path: Common.Path, value: any)
	rep_SetValues = comm:CreateSignal("SetValues") -- (id: string, path: Common.Path, values: {[string]: any})
	rep_ArrayInsert = comm:CreateSignal("ArrayInsert") -- (id: string, path: Common.Path, index: number, value: any)
	rep_ArraySet = comm:CreateSignal("ArraySet") -- (id: string, path: Common.Path, index: number, value: any)
	rep_ArrayRemove = comm:CreateSignal("ArrayRemove") -- (id: string, path: Common.Path, index: number)
	-- rep_Write = comm:CreateSignal("Write")
	rep_SetParent = comm:CreateSignal("SetParent") -- (id: string, parentId: string)
	rep_Destroy = comm:CreateSignal("Destroy") -- (id: string)
	--
	activePlayers = {}
	replicaTokens = {}
	replicas = {}
	FILTER = {
		All = 1,
		Include = 2,
		Exclude = 3,
	}

	-- Signals
	onActivePlayerAdded = Signal.new() -- (player: Player) -> ()
	onActivePlayerRemoved = Signal.new() -- (player: Player) -> ()
	--
	ReplicaService.Temporary = Replica.new({
		Token = ReplicaService:RegisterToken(HttpService:GenerateGUID(false)),
		Filter = "Include",
		FilterList = {},
	})
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	requestData:Connect(onPlayerRequestData)
end
return ReplicaService
