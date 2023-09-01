local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(script.Parent.Parent.Trove)
local Signal = require(script.Parent.Parent.Signal)

type Signal = typeof(Signal.new(...))
type Connection = typeof(Signal.new(...):Connect(...))
export type PathTable = {string | number}
export type Path = string | PathTable
export type PathIndex = string | number
export type FilterName = "All" | "Include" | "Exclude"
export type Filter = number
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
	SetValue: (self: Replica, path: Path, value: any, inclusion: {[Player]: boolean}?) -> (),
	SetValues: (self: Replica, path: Path, values: {[PathIndex]: any}, inclusion: {[Player]: boolean}?) -> (),
	ArrayInsert: (self: Replica, path: Path, value: any, index: number?, inclusion: {[Player]: boolean}?) -> (),
	ArraySet: (self: Replica, path: Path, index: number, value: any, inclusion: {[Player]: boolean}?) -> (),
	ArrayRemove: (self: Replica, path: Path, index: number, inclusion: {[Player]: boolean}?) -> (),
	-- Listeners
	OnDestroy: (self: Replica, listener: (replica: Replica) -> ()) -> Connection?,
	OnChange: (self: Replica, path: Path, listener: (new: any, old: any) -> ()) -> Connection,
	OnNewKey: (self: Replica, path: Path?, listener: (key: any, value: any) -> ()) -> Connection,
	OnArrayInsert: (self: Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArraySet: (self: Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnArrayRemove: (self: Replica, path: Path, listener: (index: number, value: any) -> ()) -> Connection,
	OnRawChange: (self: Replica, path: Path?, listener: (actionName: string, pathArray: PathTable, ...any) -> ()) -> Connection,
	OnChildAdded: (self: Replica, listener: (child: Replica) -> ()) -> Connection,

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
	_listeners: {[any]: any}?,
	_OnDestroy: Signal,
	_filter: Filter,
	_filterList: {[Player]: true},
	_trove: typeof(Trove.new()),
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
}


local function getPathTable(path: Path): PathTable
	if type(path) == "table" then
		return table.clone(path)
	end
	return string.split(path, ".")
end

local function getPathTablePointer(data: { [any]: any }, pathTable: PathTable, create: boolean, newKey: (key: PathIndex, value: any) -> ()?): ({ [PathIndex]: any }?, PathIndex?, number?)
	local pointer = data
	local index = pathTable[#pathTable]

	local newKeyIndex: number
	if #pathTable ~= 0 then
		for i = 1, #pathTable - 1 do
			if type(pointer) ~= "table" then
				error(`Invalid path: Cannot index non-table value "{pointer}"`)
			end
			local key = pathTable[i]
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

local function getTableFromPathTable(data: {[any]: any}, pathTable: PathTable, create: boolean?): {[any]: any}?
	local pointer = data
	for _, key in ipairs(pathTable) do
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
	end
	return pointer
end

local function getTableFromPathTableCreate(data: {[any]: any}, pathTable: PathTable): {[any]: any}
	return getTableFromPathTable(data, pathTable, true) :: {[any]: any}
end

local function getPathTablePointerCreate(data: { [any]: any }, pathTable: PathTable): ({ [PathIndex]: any }, PathIndex, number?)
	local pointer, index, newKeyIndex = getPathTablePointer(data, pathTable, true)
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

local function fireReplicaSignal(self: any, signalName: string, pathTable: PathTable?, ...: any): ()
	if self._listeners ~= nil then
		local pointer = self._listeners
		if pathTable ~= nil then
			pointer = getTableFromPathTable(self._listeners, pathTable, false)
		end
		if pointer then
			local signalList = pointer[SIGNAL_LIST]
			if signalList then
				local signal = signalList[signalName]
				if signal ~= nil then
					signal:Fire(...)
				end
			end
		end
	end
end

function Common.assertActive(self: any): ()
	if not self:IsActive() then
		error(`Replica has already been destroyed`)
	end
end

function Common.connectReplicaSignal(self: any, signalName: string, path: Path?, listener: (...any) -> ())
	Common.assertActive(self)
	local listeners = self._listeners
	if listeners == nil then
		listeners = {}
		self._listeners = listeners
	end

	local pointer = listeners
	
	if path ~= nil then
		local pathTable = getPathTable(path)
		pointer = getTableFromPathTableCreate(listeners, pathTable)
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
					cleanSignalTable(listeners, pathTable, signalTable)
					if next(listeners) == nil then
						self._listeners = nil
					end
				end
			end
			conn.Disconnect = disconnect
			return conn
		end
	end
	return signal:Connect(listener)
end


local function _newKeyRecursive(self: any, pathTable, _pointer, i): ()
	if i == 0 or i > #pathTable then return end
	local newKey = pathTable[i]
	local newValue = _pointer[newKey]
	_newKeyRecursive(self, pathTable, newValue, i + 1)
	table.remove(pathTable, i)
	fireReplicaSignal(self, SIGNAL.OnNewKey, pathTable, newKey, newValue)
end

function Common._onSetValue(self: any, pathTable: PathTable, newKeyIndex: number?, pointer:{[PathIndex]: any}, index: PathIndex, value: any): ()
	local old = pointer[index]
	pointer[index] = value
	fireReplicaSignal(self, SIGNAL.OnChange, pathTable, value, old)
	if old == nil then
		local _newKeyIndex = newKeyIndex or #pathTable
		local _pointer = self.Data
		for i = 1, _newKeyIndex - 1 do
			_pointer = _pointer[pathTable[i]]
		end
		_newKeyRecursive(self, table.clone(pathTable), _pointer, _newKeyIndex)
	end
end

function Common.onSetValue(self: any, path: Path, value: any): ()
	local pathTable = getPathTable(path)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, pathTable)
	Common._onSetValue(self, pathTable, newKeyIndex, pointer, index, value)
	fireReplicaSignal(self, SIGNAL.OnRawChange, pathTable, "SetValue", pathTable, value)
end

function Common.onSetValues(self: any, path: Path, values: { [PathIndex]: any }): ()
	local pathTable = getPathTable(path)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, pathTable)
	pathTable[#pathTable + 1] = index
	for key, value in pairs(values) do
		Common._onSetValue(self, pathTable, newKeyIndex, pointer[index], key, value)
	end
	fireReplicaSignal(self, SIGNAL.OnRawChange, pathTable, "SetValues", pathTable, values)
end

function Common.onArrayInsert(self: any, path: Path, index: number?, value: any): number
	local pathTable = getPathTable(path)
	local pointer, pointer_index = getPathTablePointerCreate(self.Data, pathTable)
	local _index = index or #pointer[pointer_index] + 1
	table.insert(pointer[pointer_index], _index, value)
	fireReplicaSignal(self, SIGNAL.OnArrayInsert, pathTable, _index, value)
	fireReplicaSignal(self, SIGNAL.OnRawChange, pathTable, "ArrayInsert", pathTable, index, value)
	return _index
end

function Common.onArraySet(self: any, path: Path, index: number, value: any): ()
	local pathTable = getPathTable(path)
	local pointer, _index = getPathTablePointerCreate(self.Data, pathTable)
	pointer[_index][index] = value
	fireReplicaSignal(self, SIGNAL.OnArraySet, pathTable, index, value)
	fireReplicaSignal(self, SIGNAL.OnRawChange, pathTable, "ArraySet", pathTable, index, value)
end

function Common.onArrayRemove(self: any, path: Path, index: number): ()
	local pathTable = getPathTable(path)
	local pointer, _index = getPathTablePointerCreate(self.Data, pathTable)
	local old = pointer[_index][index]
	table.remove(pointer[_index], index)
	fireReplicaSignal(self, SIGNAL.OnArrayRemove, pathTable, index, old)
	fireReplicaSignal(self, SIGNAL.OnRawChange, pathTable, "ArrayRemove", pathTable, index, old)
end

function Common.onSetParent(self: any, parent): ()
	fireReplicaSignal(parent, SIGNAL.OnChildAdded, nil, self)
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