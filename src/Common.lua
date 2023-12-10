local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(script.Parent.Parent.Trove)
local Signal = require(script.Parent.Parent.Signal)
local Fusion = require(script.Parent.Parent.Fusion)

-- Fusion Imports
type Value<T> = Fusion.Value<T>
--

export type Signal = typeof(Signal.new(...))
export type Connection = typeof(Signal.new(...):Connect(...))
export type PathTable = {PathIndex}
export type Path = string | PathTable
export type PathIndex = string | number
export type FilterName = "All" | "Include" | "Exclude"
export type Filter = number
export type Inclusion = { [Player | "All"]: boolean? }
export type Replica = {
	Id: string,
	Tags: {[any]: any},
	Data: {[any]: any},

	--[[
		SHARED
	]]
	-- Getters
	IsActive: (self: Replica) -> boolean,
	Identify: (self: Replica) -> string,
	GetToken: (self: Replica) -> string,
	GetParent: (self: Replica) -> Replica?,
	GetChildren: (self: Replica) -> {[Replica]: true},
	-- Mutators
	SetValue: (self: Replica, path: Path, value: any, inclusion: Inclusion?) -> (),
	SetValues: (self: Replica, path: Path, values: {[PathIndex]: any}, inclusion: Inclusion?) -> (),
	ArrayInsert: (self: Replica, path: Path, value: any, index: number?, inclusion: Inclusion?) -> (),
	ArraySet: (self: Replica, path: Path, index: number, value: any, inclusion: Inclusion?) -> (),
	ArrayRemove: (self: Replica, path: Path, index: number, inclusion: Inclusion?) -> (),
	-- Listeners
	OnDestroy: (self: Replica, listener: (replica: Replica) -> ()) -> Connection?,
	OnChange: (self: Replica, path: Path, listener: (new: any, old: any) -> ()) -> Connection,
	OnValuesChanged: (self: Replica, path: Path, listener: (new: {[PathIndex]: any}, old: {[PathIndex]: any}) -> ()) -> Connection,
	OnNewKey: (self: Replica, path: Path?, listener: (key: any, value: any) -> ()) -> Connection,
	OnArrayInsert: (self: Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArraySet: (self: Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArrayRemove: (self: Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnKeyChanged: (self: Replica, path: Path, listener: (key: any, new: any, old: any) -> ()) -> Connection,
	OnRawChange: (self: Replica, path: Path?, listener: (actionName: string, pathArray: PathTable, ...any) -> ()) -> Connection,
	OnChildAdded: (self: Replica, listener: (child: Replica) -> ()) -> Connection,
	-- Observers
	ObserveState: (self: Replica, path: Path, valueObject: Value<any>) -> Connection,
	Observe: (self: Replica, path: Path, observer: (new: any, old: any) -> ()) -> Connection,

	--[[
		SERVER ONLY
	]]
	-- Getters
	GetFilterList: (self: Replica) -> { [Player]: true },
	GetFilter: (self: Replica) -> Filter,
	-- Mutators
	SetParent: (self: Replica, parent: Replica) -> (),
	SetReplication: (self: Replica, settings: {
		filter: Filter?,
		players: { [Player]: true }?,
	}) -> (),
	AddToFilter: (self: Replica, player: Player) -> (),
	RemoveFromFilter: (self: Replica, player: Player) -> (),
	Destroy: (self: Replica) -> (),

	-- Private methods
	_GetChildReplicaData: (self: Replica) -> {[string]: any},
	
	-- Private Variables
	_token: string,
	_active: boolean,
	_parentId: string?,
	_parent: Replica?,
	_children: {[Replica]: true},
	_signals: {[any]: any}?,
	_OnDestroy: Signal,
	_filter: Filter,
	_filterList: {[Player]: true},
	_trove: typeof(Trove.new()),
	_child_replica_data: {[string]: any}?,
}

--[=[
	@type PathTable {string | number}
	@within Replica
]=]
--[=[
	@type Path string | PathTable
	@within Replica
]=]
--[=[
	@type PathIndex string | number
	@within Replica
]=]

local Common = {}
local SIGNAL_LIST = {}
local SIGNAL = {
	OnChange = 1,
	OnRawChange = 2,
	OnNewKey = 3,
	OnArrayInsert = 4,
	OnArraySet = 5,
	OnArrayRemove = 6,
	OnChildAdded = 7,
	OnValuesChanged = 8,
	OnKeyChanged = 9,
}
Common.NIL = {}
Common.TEMP = {} :: Replica

local function assertTable(value: any): ()
	if not value or typeof(value) ~= 'table' then
		error(`Invalid path: Cannot index non-table value '{value}'`)
	end
end

local function getPathTable(path: Path): PathTable
	if type(path) == "table" then
		return table.clone(path)
	end
	return string.split(path, ".")
end

local function getPathTablePointer(data: { [any]: any }, create: boolean, newKey: (key: PathIndex, value: any) -> ()?, ...: PathIndex): ({ [PathIndex]: any }?, PathIndex?, number?)
	local pointer = data
	local index = select(-1, ...)

	local num = select('#', ...)
	local newKeyIndex: number
	if num > 1 then
		for i = 1, num - 1 do
			if type(pointer) ~= "table" then
				error(`Invalid path: Cannot index non-table value "{pointer}"`)
			end
			local key = select(i, ...)
			local newPointer = pointer[key]
			if newPointer == nil then
				if create ~= false then
					newPointer = {}
					pointer[key] = newPointer
					if newKeyIndex == nil then
						newKeyIndex = i
					end
				else
					return
				end
			end
			pointer = newPointer
		end
	end

	return pointer, index, newKeyIndex
end

local function getTableFromPathTable(data: {[any]: any}, create: boolean?, max: number?, ...: PathIndex): {[any]: any}?
	local pointer = data
	local i = 1
	local key = select(i, ...)
	while key ~= nil do
		if type(pointer) ~= "table" then
			error(`Invalid path: Cannot index non-table value "{pointer}"`)
		end
		local newPointer = pointer[key]
		if newPointer == nil then
			if create ~= false then
				newPointer = {}
				pointer[key] = newPointer
			else
				return
			end
		end
		pointer = pointer[key]
		i += 1
		if max and i > max then
			break
		end
		key = select(i, ...)
	end
	return pointer
end

local function getTableFromPathTableCreate(data: {[any]: any}, ...: PathIndex): {[any]: any}
	return getTableFromPathTable(data, true, nil, ...) :: {[any]: any}
end

local function getPathTablePointerCreate(data: { [any]: any }, ...: PathIndex): ({ [PathIndex]: any }, PathIndex, number?)
	local pointer, index, newKeyIndex = getPathTablePointer(data, true, nil, ...)
	return pointer :: {[any]: any}, index :: PathIndex, newKeyIndex
end

local function cleanSignalTable(signals: { [PathIndex]: any }, pathTable: PathTable, signalTable: {[PathIndex]: any}): ()
	if next(signalTable) ~= nil then
		return
	end
	local i = 1
	local pointer, index = signals, pathTable[i]
	local removePointer: any, removeIndex: any
	while index ~= nil do
		if pointer[index] == nil then
			if next(pointer) ~= nil then
				removePointer, removeIndex = nil, nil
			end
			return
		end
		i += 1
		local nextIndex = pathTable[i]
		local key = next(pointer[index])
		-- If table only has 1 entry, set as removePointer
		if (key == nil or (key == nextIndex and next(pointer[index], key) == nil)) then
			if removePointer == nil then
				removePointer, removeIndex = pointer, index
			end
		else
			removePointer, removeIndex = nil, nil
		end
		pointer = pointer[index]
		index = nextIndex
	end
	if removePointer ~= nil and removeIndex ~= nil then
		removePointer[removeIndex] = nil
	end
end

local function fireReplicaSignal(self: any, signalName: string, signalTable: {[any]: any}?, ...: any)
	if signalTable == nil then
		return
	end
	local signalList = signalTable[SIGNAL_LIST]
	if signalList then
		local signal = signalList[signalName]
		if signal ~= nil then
			signal:Fire(...)
		end
	end
end

local function getSignalTable(self: any, max: number?, ...: PathIndex)
	if self._signals ~= nil then
		local pointer = self._signals
		if (not max or max > 0) and select('#', ...) ~= 0 then
			pointer = getTableFromPathTable(self._signals, false, max, ...)
		end
		return pointer
	end
	return
end

function Common.assertActive(self: any): ()
	if not self:IsActive() then
		error(`Replica has already been destroyed`)
	end
end

function Common.connectReplicaSignal(self: any, signalName: string, path: Path?, listener: (...any) -> ())
	Common.assertActive(self)
	local signals = self._signals
	if signals == nil then
		signals = {}
		self._signals = signals
	end

	local pointer = signals
	
	if path ~= nil then
		pointer = getTableFromPathTableCreate(signals, table.unpack(getPathTable(path)))
	end

	local signalTable = pointer[SIGNAL_LIST]
	if signalTable == nil then
		signalTable = {}
		pointer[SIGNAL_LIST] = signalTable
	end

	local signal = signalTable[signalName]
	if signal == nil then
		signal = self._trove:Add(Signal.new())
		signalTable[signalName] = signal
		signal.Connect = function(self, listener: (...any) -> ())
			local meta = getmetatable(self)
			local conn = meta.Connect(self, listener)
			local disconnect = function(self)
				local meta = getmetatable(self)
				meta.Disconnect(self)
				if #signal:GetConnections() == 0 then
					signal:Destroy()
					signalTable[signalName] = nil
					local pathTable = path ~= nil and getPathTable(path) or {}
					table.insert(pathTable, SIGNAL_LIST)
					cleanSignalTable(signals, pathTable, signalTable)
					if next(signals) == nil then
						self._signals = nil
					end
				end
			end
			conn.Disconnect = disconnect
			return conn
		end
	end
	return signal:Connect(listener)
end

local function _cleanSignalsRecursive(self: any, signals): ()
	local signalTable = signals[SIGNAL_LIST]
	if signalTable ~= nil then
		for signalName, signal in pairs(signalTable) do
			signal:Destroy()
			signalTable[signalName] = nil
		end
		signals[SIGNAL_LIST] = nil
	end
	for index, table in pairs(signals) do
		task.spawn(_cleanSignalsRecursive, self, table)
	end
end

function Common.cleanSignals(self: any): ()
	local signals = self._signals
	if signals == nil then return end
	_cleanSignalsRecursive(self, signals)
end

local function _newKeyRecursive(self: any, numKeys: number, _pointer, i, ...: PathIndex): ()
	if i == 0 or i > numKeys then return end
	local newKey = select(i, ...)
	local newValue = _pointer[newKey]
	_newKeyRecursive(self, numKeys, newValue, i + 1, ...)
	fireReplicaSignal(self, SIGNAL.OnNewKey, getSignalTable(self, i - 1, ...), newKey, newValue)
end

function Common._onSetValue(self: any, newKeyIndex: number?, pointer:{[PathIndex]: any}, index: PathIndex, value: any, maxIndex: number, ...: PathIndex): (boolean, any)
	local old = pointer[index]
	if old == value then return false end
	pointer[index] = value
	fireReplicaSignal(self, SIGNAL.OnChange, getSignalTable(self, nil, ...), value, old)
	fireReplicaSignal(self, SIGNAL.OnKeyChanged, getSignalTable(self, nil, table.unpack({...}, nil, select('#', ...) - 1)), index, value, old)
	if old == nil then
		local _newKeyIndex = newKeyIndex or maxIndex
		local _pointer = self.Data
		for i = 1, _newKeyIndex - 1 do
			local key = select(i, ...)
			_pointer = _pointer[key]
		end
		_newKeyRecursive(self, select('#', ...), _pointer, _newKeyIndex, ...)
	end
	return true, old
end

local function onSetValue(self: any, value: any, pathTable, ...: PathIndex)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, ...)
	local success = Common._onSetValue(self, newKeyIndex, pointer, index, value, select('#', ...), ...)
	if success then
		fireReplicaSignal(self, SIGNAL.OnRawChange, getSignalTable(self, nil, ...), "SetValue", pathTable, value)
	end
end
function Common.onSetValue(self: any, path: Path, value: any)
	local pathTable = getPathTable(path)
	return onSetValue(self, value, pathTable, table.unpack(pathTable))
end

local function onSetValues(self: any, values: { [PathIndex]: any }, nilKeys: { PathIndex }?, pathTable: PathTable, ...: PathIndex)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, ...)
	local oldValues = {}
	local num = select('#', ...) + 1
	for key, value in pairs(values) do
		if value == Common.NIL then
			value = nil
		end
		local success, old = Common._onSetValue(self, newKeyIndex, pointer[index], key, value, num, ...)
		if not success then
			values[key] = nil
		else
			oldValues[key] = old
		end
	end
	if nilKeys ~= nil and #nilKeys > 0 then
		for _, key in ipairs(nilKeys) do
			local success, old = Common._onSetValue(self, newKeyIndex, pointer[index], key, nil, num, ...)
			if success then
				values[key] = Common.NIL
				oldValues[key] = old
			end
		end
	end
	if next(values) ~= nil then
		local signalTable = getSignalTable(self, nil, ...)
		fireReplicaSignal(self, SIGNAL.OnValuesChanged, signalTable, values, oldValues)
		fireReplicaSignal(self, SIGNAL.OnRawChange, signalTable, "SetValues", pathTable, values)
	end
end
function Common.onSetValues(self: any, path: Path, values: { [PathIndex]: any }, nilKeys: { PathIndex }?)
	local pathTable = getPathTable(path)
	return onSetValues(self, values, nilKeys, pathTable, table.unpack(pathTable))
end

local function onArrayInsert(self: any, index: number?, value: any, pathTable, ...: PathIndex)
	local pointer, pointer_index = getPathTablePointerCreate(self.Data, ...)
	assertTable(pointer[pointer_index])
	local _index = index or #pointer[pointer_index] + 1
	table.insert(pointer[pointer_index], _index, value)
	local signalTable = getSignalTable(self, nil, ...)
	fireReplicaSignal(self, SIGNAL.OnArrayInsert, signalTable, _index, value)
	fireReplicaSignal(self, SIGNAL.OnRawChange, signalTable, "ArrayInsert", pathTable, index, value)
	return _index
end
function Common.onArrayInsert(self: any, path: Path, index: number?, value: any): number
	local pathTable = getPathTable(path)
	return onArrayInsert(self, index, value, pathTable, table.unpack(pathTable))
end

local function onArraySet(self: any, index: number, value: any, pathTable, ...: PathIndex)
	local pointer, _index = getPathTablePointerCreate(self.Data, ...)
	assertTable(pointer[_index])
	local old = pointer[_index][index]
	if old == value then return end
	pointer[_index][index] = value
	local signalTable = getSignalTable(self, nil, ...)
	fireReplicaSignal(self, SIGNAL.OnArraySet, signalTable, index, value)
	fireReplicaSignal(self, SIGNAL.OnRawChange, signalTable, "ArraySet", pathTable, index, value)
end
function Common.onArraySet(self: any, path: Path, index: number, value: any): ()
	local pathTable = getPathTable(path)
	return onArraySet(self, index, value, pathTable, table.unpack(pathTable))
end

local function onArrayRemove(self: any, index: number, pathTable, ...: PathIndex)
	local pointer, _index = getPathTablePointerCreate(self.Data, ...)
	assertTable(pointer[_index])
	local old = pointer[_index][index]
	table.remove(pointer[_index], index)
	local signalTable = getSignalTable(self, nil, ...)
	fireReplicaSignal(self, SIGNAL.OnArrayRemove, signalTable, index, old)
	fireReplicaSignal(self, SIGNAL.OnRawChange, signalTable, "ArrayRemove", pathTable, index, old)
end
function Common.onArrayRemove(self: any, path: Path, index: number): ()
	local pathTable = getPathTable(path)
	return onArrayRemove(self, index, pathTable, table.unpack(pathTable))
end

function Common.onSetParent(self: any, parent): ()
	fireReplicaSignal(parent, SIGNAL.OnChildAdded, getSignalTable(parent), self)
end

function Common.observe(self: any, path: Path, observer: (new: any, old: any) -> ()): Connection
	local pointer, index = getPathTablePointer(self.Data, false, nil, table.unpack(getPathTable(path)))
	local value = nil
	if pointer then
		value = pointer[index]
	end
	observer(value, value)
	return self:OnChange(path, function(new: any, old: any)
		observer(new, old)
	end)
end

function Common.observeState(self: any, path: Path, valueObject: Value<any>): Connection
	local pointer, index = getPathTablePointer(self.Data, false, nil, table.unpack(getPathTable(path)))
	local value = nil
	if pointer then
		value = pointer[index]
	end
	valueObject:set(value)
	return self:OnChange(path, function(new: any)
		valueObject:set(new)
	end)
end

function Common.identify(self: any): string
	local tagString = ""
	for key, val in pairs(self.Tags) do
		tagString ..= `{key}={val};`
	end
	return `Id:{self.Id};Token:{self:GetToken()};Tags:\{{tagString}\}`
end

Common.SIGNAL = SIGNAL
return Common