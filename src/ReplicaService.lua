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
local Fusion = require(script.Parent.Parent.Fusion)
local Common = require(script.Parent.Common)

-- Fusion Imports
type Value<T> = Fusion.Value<T>
--

type Signal = Common.Signal
type Connection = Common.Connection

type FilterName = Common.FilterName
type Filter = Common.Filter
type Inclusion = Common.Inclusion

export type ReplicaProps = {
	Token: ReplicaToken,
	Tags: { [string]: any }?, -- Default: {}
	Data: { [string]: any }?, -- Default: {}
	Filter: FilterName?, -- Default: "All"
	FilterList: { [Player]: true }?, -- Default: {}
	Parent: Replica?, -- Default: nil
	-- WriteLib: any, -- ModuleScript
}

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
local ALL: "All" = "All"
local INCLUDE: "Include" = "Include"
local EXCLUDE: "Exclude" = "Exclude"
local TempReplica: Replica
-- Signals
local onActivePlayerAdded
local onActivePlayerRemoved

--[=[
	@class Replica

	An object that can be replicated to clients.
]=]
--[=[
	@prop Id string
	@within Replica
	@readonly
	@server
	@client

	The Replica's unique identifier.
]=]
--[=[
	@prop Tags { [string]: any }
	@within Replica
	@server
	@client

	The Replica's tags.
]=]
--[=[
	@prop Data { [string]: any }
	@within Replica
	@server
	@client

	The Replica's data.
]=]
--[=[
	@interface FilterSettings
	@within Replica
	@field filter FilterName? -- The name of the Filter to set. If nil, the filter will not be changed.
	@field players { [Player]: true }? -- List of players added to the filter list. If nil, the filter list will not be changed.
]=]
--[=[
	@type FilterName "All" | "Include" | "Exclude"
	@within Replica
]=]
--[=[
	@type FilterList { [Player]: true }
	@within Replica
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


local function fireRemoteSignalForReplica(self: Replica, signal: any, inclusion: Inclusion?, ...: any): ()
	local replicationFilter = self:GetFilter()
	if replicationFilter == FILTER.All then
		signal:FireFilter(function(player: Player)
			if not activePlayers[player] then
				return false
			end
			if inclusion ~= nil then
				if inclusion[player] ~= nil then
					return inclusion[player] :: boolean
				elseif inclusion[ALL] ~= nil then
					return inclusion[ALL] :: boolean
				end
			end
			return true
		end, self.Id, ...)
	else
		signal:FireFilter(function(player: Player)
			if not activePlayers[player] then
				return false
			end
			if inclusion ~= nil then
				if inclusion[player] ~= nil then
					return inclusion[player] :: boolean
				elseif inclusion[ALL] ~= nil then
					return inclusion[ALL] :: boolean
				end
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
			self:GetToken(),
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
): { [Player]: boolean? } -- { [Player]: true } = Created, { [Player]: false } = Destroyed
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
	local parentTable = childReplicaData[child:GetToken()]
	if parentTable == nil then
		parentTable = {}
		childReplicaData[child:GetToken()] = parentTable
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
	local parentTable = childReplicaData[child:GetToken()]
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
			childReplicaData[child:GetToken()] = nil
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
	removeChild(self._parent :: Replica, self)
	-- add to new parent
	self._parent = parent
	addChild(parent, self)
	--

	local inclusion = updateReplication(self, oldFilter, oldPlayers, newFilter, newPlayers)
	for player, change in pairs(inclusion) do
		inclusion[player] = change or nil
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
	onActivePlayerRemoved:Fire(player)
end

local function onPlayerRequestData(player: Player): ()
	if not player:IsDescendantOf(game) then
		return
	end
	activePlayers[player] = true
	local data: {[string]: {any}} = {}
	for id, replica in pairs(replicas) do
		if replica._parent == nil and shouldReplicateForPlayer(replica, player) then
			-- replicateFor(replica, player)
			data[id] = {
				replica:GetToken(),
				replica.Tags,
				replica.Data,
				replica:_GetChildReplicaData(),
			}
		end
	end
	requestData:Fire(player, data)
	onActivePlayerAdded:Fire(player)
end

--[=[
	@function new
	@within Replica
	@ignore

	Creates a new Replica.
]=]
function Replica.new(props: ReplicaProps): Replica
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
	}, Replica)
	replicas[self.Id] = self

	if self._parent ~= nil then
		addChild(self._parent, self)
	end

	initReplication(self)
	return self
end
export type Replica = Common.Replica

--[=[
	@method IsActive
	@within Replica
	@server
	@client

	Returns whether the Replica is active or not.

	@return boolean -- Whether the Replica is active or not.
]=]
function Replica:IsActive(): boolean
	return self._active
end

--[=[
	@method Identify
	@within Replica
	@server
	@client
	
	Returns a string that identifies the Replica.

	@return string -- A string that identifies the Replica.
]=]
function Replica:Identify(): string
	return identify(self)
end

--[=[
	@method GetToken
	@within Replica
	@server
	@client

	Returns the Replica's Token name.

	@return string -- The name of the ReplicaToken used to create the Replica.
]=]
function Replica:GetToken(): string
	return tostring(self._token)
end

--[=[
	@method GetParent
	@within Replica
	@server
	@client

	Returns the Replica's parent.

	@return Replica? -- The Replica's parent. If nil, the Replica is a root Replica.
]=]
function Replica:GetParent(): Replica?
	return self._parent
end

--[=[
	@method GetChildren
	@within Replica
	@server
	@client

	Returns the Replica's children.

	@return { [Replica]: true } -- A list of the Replica's children.
]=]
function Replica:GetChildren(): { [Replica]: true }
	return self._children
end

--[=[
	@method SetValue
	@within Replica
	@server
	@client

	Sets a value at a path.

	@param path Path -- The path to set the value at.
	@param value any -- The value to set.
	@param inclusion Inclusion? -- Overrides the Replica's filtering settings for this call.
]=]
function Replica:SetValue(path: Common.Path, value: any, inclusion: Inclusion?): ()
	onSetValue(self, path, value)
	fireRemoteSignalForReplica(self, rep_SetValue, inclusion, path, value)
end

--[=[
	@method SetValues
	@within Replica
	@server
	@client

	Sets multiple values at a path.

	@param path Path -- The path to set the values at.
	@param values { [PathIndex]: any } -- The values to set.
	@param inclusion Inclusion? -- Overrides the Replica's filtering settings for this call.
]=]
function Replica:SetValues(path: Common.Path?, values: { [Common.PathIndex]: any }, inclusion: Inclusion?): ()
	onSetValues(self, path, values)
	local nilKeys = {}
	local _values = table.clone(values)
	for key, value in pairs(_values) do
		if value == Common.NIL then
			table.insert(nilKeys, key)
			_values[key] = nil
		end
	end
	fireRemoteSignalForReplica(self, rep_SetValues, inclusion, path, _values, nilKeys)
end

--[=[
	@method ArrayInsert
	@within Replica
	@server
	@client

	Inserts a value into an array at a path.

	@param path Path -- The path to insert the value at.
	@param value any -- The value to insert.
	@param index number? -- The index to insert the value at. If nil, the value will be inserted at the end of the array.
	@param inclusion Inclusion? -- Overrides the Replica's filtering settings for this call.
]=]
function Replica:ArrayInsert(path: Common.Path, value: any, index: number?, inclusion: Inclusion?): ()
	local _index = onArrayInsert(self, path, index, value)
	fireRemoteSignalForReplica(self, rep_ArrayInsert, inclusion, path, _index, value)
end

--[=[
	@method ArraySet
	@within Replica
	@server
	@client

	Sets a value in an array at a path.

	@param path Path -- The path to set the value at.
	@param index number -- The index to set the value at.
	@param value any -- The value to set.
	@param inclusion Inclusion? -- Overrides the Replica's filtering settings for this call.
]=]
function Replica:ArraySet(path: Common.Path, index: number, value: any, inclusion: Inclusion?): ()
	onArraySet(self, path, index, value)
	fireRemoteSignalForReplica(self, rep_ArraySet, inclusion, path, index, value)
end

--[=[
	@method ArrayRemove
	@within Replica
	@server
	@client

	Removes a value from an array at a path.

	@param path Path -- The path to remove the value from.
	@param index number -- The index to remove the value from.
	@param inclusion Inclusion? -- Overrides the Replica's filtering settings for this call.
]=]
function Replica:ArrayRemove(path: Common.Path, index: number, inclusion: Inclusion?): ()
	onArrayRemove(self, path, index)
	fireRemoteSignalForReplica(self, rep_ArrayRemove, inclusion, path, index)
end

--[=[
	@method OnChange
	@within Replica
	@server
	@client

	Listens for value changes at a path.

	@param path Path? -- The path to listen for changes at.
	@param listener (new: any, old: any) -> () -- The function to call when the value at the path changes.
	@return Connection -- Signal Connection
]=]
function Replica:OnChange(path: Common.Path, listener: (new: any, old: any) -> ())
	return Common.connectOnChange(self, path, listener)
end

--[=[
	@method OnValuesChanged
	@within Replica
	@server
	@client

	Listens for SetValues changes at a path.

	@param path Path? -- The path to listen for SetValues changes at.
	@param listener (new: { [PathIndex]: any }, old: { [PathIndex]: any }) -> () -- The function to call when the values at the path change.
	@return Connection -- Signal Connection
]=]
function Replica:OnValuesChanged(path: Common.Path?, listener: (new: {[Common.PathIndex]: any}, old: {[Common.PathIndex]: any}) -> ())
	return Common.connectOnValuesChanged(self, path, listener)
end

--[=[
	@method OnNewKey
	@within Replica
	@server
	@client

	Listens for new keys at a path.

	@param path Path? -- The path to listen for new keys at. If nil, the listener will be called when a new key is added to the root Data table.
	@param listener (key: any, value: any) -> () -- The function to call when a new key is added to the path.
	@return Connection -- Signal Connection
]=]
function Replica:OnNewKey(path: Common.Path?, listener: (key: any, value: any) -> ())
	return Common.connectOnNewKey(self, path, listener)
end

--[=[
	@method OnArrayInsert
	@within Replica
	@server
	@client

	Listens for array inserts at a path.

	@param path Path? -- The path to listen for array inserts at.
	@param listener (index: number, value: any) -> () -- The function to call when a value is inserted into the array at the path.
	@return Connection -- Signal Connection
]=]
function Replica:OnArrayInsert(path: Common.Path, listener: (index: number, value: any) -> ())
	return Common.connectOnArrayInsert(self, path, listener)
end

--[=[
	@method OnArraySet
	@within Replica
	@server
	@client

	Listens for array sets at a path.

	@param path Path? -- The path to listen for array sets at.
	@param listener (index: number, value: any) -> () -- The function to call when a value is set in the array at the path.
	@return Connection -- Signal Connection
]=]
function Replica:OnArraySet(path: Common.Path, listener: (index: number, value: any) -> ())
	return Common.connectOnArraySet(self, path, listener)
end

--[=[
	@method OnArrayRemove
	@within Replica
	@server
	@client

	Listens for array removes at a path.

	@param path Path? -- The path to listen for array removes at.
	@param listener (index: number, value: any) -> () -- The function to call when a value is removed from the array at the path.
	@return Connection -- Signal Connection
]=]
function Replica:OnArrayRemove(path: Common.Path, listener: (index: number, value: any) -> ())
	return Common.connectOnArrayRemove(self, path, listener)
end

--[=[
	@method OnKeyChanged
	@within Replica
	@server
	@client

	Listens for key changes at a path.

	@param path Path? -- The path to listen for key changes at.
	@param listener (key: any, new: any, old: any) -> () -- The function to call when a key changes at the path.
	@return Connection -- Signal Connection
]=]
function Replica:OnKeyChanged(path: Common.Path?, listener: (key: any, new: any, old: any) -> ())
	return Common.connectOnKeyChanged(self, path, listener)
end

--[=[
	@method OnNil
	@within Replica
	@server
	@client

	Listens for the value at the specified path being set to nil.

	@param path Path -- The path to listen for nil at.
	@param listener (old: any) -> () -- The function to call when the value at the path is set to nil.
	@param once boolean? -- Whether to disconnect the listener after it is called. Default: true
	@return Connection -- Signal Connection
]=]
function Replica:OnNil(path: Common.Path, listener: (old: any) -> (), once: boolean?): Connection
	return Common.connectOnNil(self, path, listener, once)
end

--[=[
	@method OnRawChange
	@within Replica
	@server
	@client

	Listens for raw changes at a path.

	@param path Path? -- The path to listen for raw changes at.
	@param listener (actionName: string, pathTable: PathTable, ...any) -> () -- The function to call when a raw change occurs at the path.
	@return Connection -- Signal Connection
]=]
function Replica:OnRawChange(path: Common.Path?, listener: (actionName: string, pathTable: Common.PathTable, ...any) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnRawChange, path, listener)
end

--[=[
	@method OnChildAdded
	@within Replica
	@server
	@client

	Listens for child Replicas being added.

	@param listener (child: Replica) -> () -- The function to call when a child Replica is added.
	@return Connection -- Signal Connection
]=]
function Replica:OnChildAdded(listener: (child: Replica) -> ())
	return connectReplicaSignal(self, Common.SIGNAL.OnChildAdded, nil, listener)
end

--[=[
	@method ObserveState
	@within Replica
	@server
	@client

	Observes the value at the specified path and sets it as the value of the Fusion Value object.

	@param path Path -- The path to observe.
	@param valueObject Value<any> -- The Fusion Value object to set the value of.
	@return Connection -- Signal Connection
]=]
function Replica:ObserveState(path: Common.Path, valueObject: Value<any>): Connection
	return Common.observeState(self, path, valueObject)
end

--[=[
	@method Observe
	@within Replica
	@server
	@client

	Observes the value at the specified path and calls the observer function when it changes.
	NOTE: The observer function will be called immediately with the current value at the path.

	@param path Path -- The path to observe.
	@param observer (new: any, old: any) -> () -- The function to call when the value at the path changes.
	@return Connection -- Signal Connection
]=]
function Replica:Observe(path: Common.Path, observer: (new: any, old: any) -> ()): Connection
	return Common.observe(self, path, observer)
end

--[=[
	@method OnChildRemoved
	@within Replica
	@server
	@client

	Listens for child Replicas being removed.

	@param listener (child: Replica) -> () -- The function to call when this Replica is destroyed.
	@return Connection -- Signal Connection
]=]
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

-- function Replica:Write(): ()
--
-- end

--[=[
	@method _GetChildReplicaData
	@within Replica
	@server
	@ignore

	@return { [string]: any } -- A table of child Replica data.
]=]
function Replica:_GetChildReplicaData(): { [string]: any }
	return self._child_replica_data or self._parent:_GetChildReplicaData()
end

--[=[
	@method SetParent
	@within Replica
	@server

	Sets the parent of the Replica. Only works on root Replicas 
	(replicas with no initial parent.)

	@param parent Replica -- The Replica to set as the parent.
]=]
function Replica:SetParent(parent: Replica): ()
	if parent == self:GetParent() then return end
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

--[=[
	@method SetReplication
	@within Replica
	@server

	@param settings FilterSettings -- The settings to set the Replica's replication to.

	Sets the replication settings of the Replica.
]=]
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

--[=[
	@method AddToFilter
	@within Replica
	@server

	Adds a player to the Replica's filter list.

	@param player Player -- The player to add to the filter list.
]=]
function Replica:AddToFilter(player: Player): ()
	addToFilter(self, player)
end

--[=[
	@method RemoveFromFilter
	@within Replica
	@server

	Removes a player from the Replica's filter list.

	@param player Player -- The player to remove from the filter list.
]=]
function Replica:RemoveFromFilter(player: Player): ()
	removeFromFilter(self, player)
end

function Replica:_Destroy(): ()
	self._active = false
	replicas[self.Id] = nil
	Common.cleanSignals(self)

	for child in pairs(self._children) do
		child:_Destroy()
	end

	if self._parent ~= nil then
		removeChild(self._parent, self)
	end

	if self._OnDestroy ~= nil then
		self._OnDestroy:Fire(self)
		self._OnDestroy:Destroy()
	end
end

--[=[
	@method Destroy
	@within Replica
	@server

	Destroys the Replica.
]=]
function Replica:Destroy(): ()
	self:_Destroy()
	fireRemoteSignalForReplica(self, rep_Destroy)
end

--[=[
	@method GetFilterList
	@within Replica
	@server

	Returns the Replica's filter list.

	@return { [Player]: true } -- A list of players that the Replica is filtered to.
]=]
function Replica:GetFilterList(): { [Player]: true }
	return self._filterList or self._parent:GetFilterList()
end

--[=[
	@method GetFilter
	@within Replica
	@server

	Returns the Replica's filter.

	@return Filter -- Type of filter the Replica is using
]=]
function Replica:GetFilter(): Filter
	return self._filter or self._parent:GetFilter()
end

--[[
	@class ReplicaService
	@server
	
	Manages the replication of Replicas to clients.
]]
--[=[
	@class ReplicaToken

	Token used to identify different types of Replicas.
]=]
--[=[
	@interface ReplicaProps
	@within ReplicaModule
	@field Token ReplicaToken -- The ReplicaToken to create the Replica with.
	@field Tags { [string]: any }? -- The tags to create the Replica with. Default: {}
	@field Data { [string]: any }? -- The data to create the Replica with. Default: {}
	@field Filter FilterName? -- The filter type to create the Replica with. Default: "All"
	@field FilterList { [Player]: true }? -- The filter list to create the Replica with. Default: {}
	@field Parent Replica? -- The parent to create the Replica with. Default: nil
	@field WriteLib any? -- The write library to create the Replica with. Default: nil
]=]
local ReplicaService = {}
ReplicaService.ALL = ALL
ReplicaService.INCLUDE = INCLUDE
ReplicaService.EXCLUDE = EXCLUDE


function ReplicaService:ObserveActivePlayers(observer: (player: Player) -> ())
	for player in pairs(activePlayers) do
		task.spawn(observer, player)
	end
	return onActivePlayerAdded:Connect(observer)
end


function ReplicaService:OnActivePlayerRemoved(listener: (player: Player) -> ())
	return onActivePlayerRemoved:Connect(listener)
end

local ReplicaToken = {
	__ClassName = "ReplicaToken",
	__tostring = function(self)
		return self.name
	end,
}
function ReplicaService:RegisterToken(name: string): ReplicaToken
	assert(replicaTokens[name] == nil, `ReplicaToken "{name}" already exists!`)
	local token = setmetatable({
		name = name,
	}, ReplicaToken)
	replicaTokens[name] = token
	return token
end
export type ReplicaToken = typeof(ReplicaService:RegisterToken(...))

function ReplicaService:NewReplica(props: ReplicaProps)
	return Replica.new(props)
end

function ReplicaService:GetReplicaById(id: string): Replica?
	return replicas[id]
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
	ReplicaService.ActivePlayers = activePlayers
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
	TempReplica = Replica.new({
		Token = ReplicaService:RegisterToken(HttpService:GenerateGUID(false)),
		Filter = "Include",
		FilterList = {},
	})
	ReplicaService.Temporary = TempReplica
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	requestData:Connect(onPlayerRequestData)
end
return ReplicaService
