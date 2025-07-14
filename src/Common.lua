local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(script.Parent.Parent.Signal)

export type Signal = typeof(Signal.new(...))
export type Connection = typeof(Signal.new(...):Connect(...))
export type PathTable = {PathIndex}
export type Path = string | PathTable
export type PathIndex = string | number
export type Filter = "All" | "Include" | "Exclude"
export type Inclusion = { [Player | "All"]: boolean? }
export type _Replica = {
	Id: string,

	--[[
		SHARED
	]]
	-- Getters
	IsActive: (self: _Replica) -> boolean,
	Identify: (self: _Replica) -> string,
	GetToken: (self: _Replica) -> string,
	GetParent: (self: _Replica) -> _Replica?,
	GetChildren: (self: _Replica) -> {[_Replica]: true},
	-- Mutators
	SetValue: (self: _Replica, path: Path, value: any, inclusion: Inclusion?) -> (),
	SetValues: (self: _Replica, path: Path?, values: {[PathIndex]: any}, inclusion: Inclusion?) -> (),
	ArrayInsert: (self: _Replica, path: Path, value: any, index: number?, inclusion: Inclusion?) -> (),
	ArraySet: (self: _Replica, path: Path, index: number, value: any, inclusion: Inclusion?) -> (),
	ArrayRemove: (self: _Replica, path: Path, index: number, inclusion: Inclusion?) -> (),
	-- Listeners
	OnDestroy: (self: _Replica, listener: (replica: _Replica) -> ()) -> Connection,
	OnChange: (self: _Replica, path: Path, listener: (new: any, old: any) -> ()) -> Connection,
	OnValuesChanged: (self: _Replica, path: Path?, listener: (new: {[PathIndex]: any}, old: {[PathIndex]: any}) -> ()) -> Connection,
	OnNewKey: (self: _Replica, path: Path?, listener: (key: any, value: any) -> ()) -> Connection,
	OnArrayInsert: (self: _Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArraySet: (self: _Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArrayRemove: (self: _Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnKeyChanged: (self: _Replica, path: Path?, listener: (key: any, new: any, old: any) -> ()) -> Connection,
	OnRawChange: (self: _Replica, path: Path?, listener: (actionName: string, pathArray: PathTable, ...any) -> ()) -> Connection,
	OnChildAdded: (self: _Replica, listener: (child: _Replica) -> ()) -> Connection,
	OnNil: (self: _Replica, path: Path, listener: (old: any) -> (), once: boolean?) -> Connection,
	-- Observers
	Observe: (self: _Replica, path: Path, observer: (new: any, old: any) -> ()) -> Connection,

	--[[
		SERVER ONLY
	]]
	-- Getters
	GetFilterList: (self: _Replica) -> { [Player]: true },
	GetFilter: (self: _Replica) -> Filter,
	-- Mutators
	SetParent: (self: _Replica, parent: _Replica) -> (),
	SetReplication: (self: _Replica, settings: {
		filter: Filter?,
		players: { [Player]: true }?,
	}) -> (),
	AddToFilter: (self: _Replica, player: Player) -> (),
	RemoveFromFilter: (self: _Replica, player: Player) -> (),
	Destroy: (self: _Replica) -> (),

	-- Private methods
	_GetChildReplicaData: (self: _Replica) -> {[string]: any},
	
	-- Private Variables
	_token: string,
	_active: boolean,
	_parentId: string?,
	_parent: _Replica?,
	_children: {[_Replica]: true},
	_signals: {[any]: any}?,
	_OnDestroy: Signal,
	_filter: Filter,
	_filterList: {[Player]: true},
	_child_replica_data: {[string]: any}?,
}
export type Replica<Tags, Data> = _Replica & {
	Tags: Tags,
	Data: Data,
}
type Table = { [string]: Table | any }
export type ReplicaAny = Replica<Table, Table>

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

local EMPTY_TABLE = {}
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
		error(`Invalid path: Cannot index non-table value '{value}'`, 5)
	end
end

local function getPathTable(path: Path): PathTable
	if type(path) == "table" then
		local pathTable = {}
		for _, key in pairs(path) do
			local keyType = type(key)
			if keyType ~= "string" and keyType ~= "number" then
				error(`Invalid path: Cannot index non-string/number value "{key}"`, 3)
			end
			if keyType == 'string' and string.find(key :: string, '.') ~= nil then
				local keys = string.split(key, ".")
				table.move(keys, 1, #keys, #pathTable + 1, pathTable)
			else
				table.insert(pathTable, key)
			end
		end
		return pathTable
	end
	return string.split(path, ".")
end

local function getPathTablePointer(data: { [any]: any }, create: boolean, newKey: (key: PathIndex, value: any) -> ()?, ...: PathIndex): ({ [PathIndex]: any }?, PathIndex?, number?)
	local pointer = data
	local num = select('#', ...)
	if num == 0 then
		return pointer
	end

	local index = select(-1, ...)
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
		signal = Signal.new()
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
	if i == 0 or i > numKeys then
		return
	end
	local newKey = select(i, ...)
	local newValue = _pointer[newKey]
	_newKeyRecursive(self, numKeys, newValue, i + 1, ...)
	local signalTable = getSignalTable(self, i - 1, ...)
	fireReplicaSignal(self, SIGNAL.OnKeyChanged, signalTable, newKey, newValue, nil)
	fireReplicaSignal(self, SIGNAL.OnNewKey, signalTable, newKey, newValue)
end

function Common._onSetValue(self: any, newKeyIndex: number?, pointer:{[PathIndex]: any}, index: PathIndex, value: any, maxIndex: number, pathHasIndex: boolean, ...: PathIndex): (boolean, any)
	local old = pointer[index]
	if old == value then return false end
	pointer[index] = value
	local onChangeSignals = getSignalTable(self, nil, ...)
	local onKeyChangedSignals = pathHasIndex and getSignalTable(self, nil, table.unpack({...}, nil, select('#', ...) - 1)) or onChangeSignals
	if onChangeSignals and not pathHasIndex then
		onChangeSignals = onChangeSignals[index]
	end
	fireReplicaSignal(self, SIGNAL.OnChange, onChangeSignals, value, old)
	fireReplicaSignal(self, SIGNAL.OnKeyChanged, onKeyChangedSignals, index, value, old)
	if old == nil then
		local _newKeyIndex = newKeyIndex or maxIndex
		local _pointer = self.Data
		for i = 1, _newKeyIndex - 1 do
			local key = select(i, ...)
			_pointer = _pointer[key]
		end
		fireReplicaSignal(self, SIGNAL.OnNewKey, onKeyChangedSignals, index, value)
		_newKeyRecursive(self, select('#', ...) - 1, _pointer, _newKeyIndex, ...)
	end
	return true, old
end

local function onSetValue(self: any, value: any, pathTable, ...: PathIndex)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, ...)
	local success = Common._onSetValue(self, newKeyIndex, pointer, index, value, select('#', ...), true, ...)
	if success then
		fireReplicaSignal(self, SIGNAL.OnRawChange, getSignalTable(self, nil, ...), "SetValue", pathTable, value)
	end
end
function Common.onSetValue(self: any, path: Path, value: any)
	local pathTable = getPathTable(path)
	return onSetValue(self, value, pathTable, table.unpack(pathTable))
end

local function onSetValues(self: any, values: { [PathIndex]: any }, nilKeys: { PathIndex }?, pathTable: PathTable, ...: PathIndex)
	local _pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, ...)
	local oldValues = {}
	local num = select('#', ...) + 1
	local pointer = index and _pointer[index] or _pointer
	for key, value in pairs(values) do
		if value == Common.NIL then
			value = nil
		end
		local success, old = Common._onSetValue(self, newKeyIndex, pointer, key, value, num, false, ...)
		if not success then
			values[key] = nil
		else
			oldValues[key] = old
		end
	end
	if nilKeys ~= nil and #nilKeys > 0 then
		for _, key in ipairs(nilKeys) do
			local success, old = Common._onSetValue(self, newKeyIndex, pointer, key, nil, num, false, ...)
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
function Common.onSetValues(self: any, path: Path?, values: { [PathIndex]: any }, nilKeys: { PathIndex }?)
	local pathTable = EMPTY_TABLE
	if path ~= nil then
		pathTable = getPathTable(path)
	end
	return onSetValues(self, values, nilKeys, pathTable, path ~= nil and table.unpack(pathTable) or nil)
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
	observer(value, nil)
	local onChange
	onChange = self:OnChange(path, function(new: any, old: any)
		observer(new, old)
	end)
	return onChange
end

function Common.connectOnChange(self: any, path: Path, listener: (new: any, old: any) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnChange, path, listener)
end

function Common.connectOnValuesChanged(self: any, path: Path, listener: (new: {[PathIndex]: any}, old: {[PathIndex]: any}) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnValuesChanged, path, listener)
end

function Common.connectOnNewKey(self: any, path: Path?, listener: (key: any, value: any) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnNewKey, path, listener)
end

function Common.connectOnArrayInsert(self: any, path: Path, listener: (index: number, value: any) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnArrayInsert, path, listener)
end

function Common.connectOnArraySet(self: any, path: Path, listener: (index: number, value: any) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnArraySet, path, listener)
end

function Common.connectOnArrayRemove(self: any, path: Path, listener: (index: number, value: any) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnArrayRemove, path, listener)
end

function Common.connectOnKeyChanged(self: any, path: Path?, listener: (key: any, new: any, old: any) -> ()): RBXScriptConnection
	return Common.connectReplicaSignal(self, SIGNAL.OnKeyChanged, path, listener)
end

function Common.connectOnNil(self: any, path: Path, listener: (old: any) -> (), autoDisconnect: boolean?): RBXScriptConnection
	local conn
	conn = Common.connectOnChange(self, path, function(new: any, old: any)
		if new == nil then
			if autoDisconnect ~= false then
				conn:Disconnect()
			end
			listener(old)
		end
	end)
	return conn
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