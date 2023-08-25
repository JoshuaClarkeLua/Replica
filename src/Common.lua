local Signal = require(script.Parent.Parent.Signal)

-- type Replica = {
-- 	Id: string,
-- 	Tags: { [string]: any },
-- 	Data: { [any]: any },
-- 
-- 	_listeners: { [any]: any }?,
-- 	_trove: typeof(Trove.new()),
-- 
-- 	IsActive: (self: Replica) -> boolean,
-- 	GetToken: (self: Replica) -> string,
-- }

export type Path = string | PathTable
export type PathTable = {string | number}
export type PathIndex = string | number

local Common = {}
local TOP_LEVEL_LISTENERS = {}


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
		local pointer
		if pathTable == nil or #pathTable == 0 then
			pointer = self._listeners[TOP_LEVEL_LISTENERS]
		else
			pointer = getTableFromPathTable(self._listeners, pathTable, false)
		end
		if pointer then
			local signal = pointer[signalName]
			if signal ~= nil then
				signal:Fire(...)
			end
		end
	end
end

function Common.assertActive(self: any): ()
	if not self:IsActive() then
		error(`Replica has already been destroyed`)
	end
end

function Common.connectReplicaSignal(self: any, signalName: string, path: Path, listener: (...any) -> ())
	Common.assertActive(self)
	local listeners = self._listeners
	if listeners == nil then
		listeners = {}
		self._listeners = listeners
	end

	local signalTable
	if path == "" or (type(path) == "table" and #path == 0) then
		signalTable = listeners[TOP_LEVEL_LISTENERS]
		if signalTable == nil then
			signalTable = {}
			listeners[TOP_LEVEL_LISTENERS] = signalTable
		end
	else
		local pathTable = getPathTable(path)
		signalTable = getTableFromPathTableCreate(listeners, pathTable)
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
					if signalTable ~= listeners[TOP_LEVEL_LISTENERS] then
						cleanSignalTable(listeners, getPathTable(path), signalTable)
					elseif next(signalTable) == nil then
						listeners[TOP_LEVEL_LISTENERS] = nil
					end
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

function Common._onSetValue(self: any, pathTable: PathTable, newKeyIndex: number?, pointer:{[PathIndex]: any}, index: PathIndex, value: any): ()
	local old = pointer[index]
	pointer[index] = value
	if old == nil then
		if newKeyIndex ~= nil and newKeyIndex > 1 then
			local _tempPathTable = table.move(pathTable, 1, newKeyIndex - 1, 1, {})
			for i = newKeyIndex, #pathTable do
				local newKey = pathTable[i]
				fireReplicaSignal(self, "_OnNewKey", _tempPathTable, newKey, pointer)
				table.insert(_tempPathTable, newKey)
			end
		end
		fireReplicaSignal(self, "_OnNewKey", pathTable, index, value)
	end

	fireReplicaSignal(self, "_OnChange", pathTable, value, old)
end

function Common.onSetValue(self: any, path: Path, value: any): ()
	local pathTable = getPathTable(path)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, pathTable)
	Common._onSetValue(self, pathTable, newKeyIndex, pointer, index, value)
	fireReplicaSignal(self, "_OnRawChange", pathTable, "SetValue", pathTable, value)
end

function Common.onSetValues(self: any, path: Path, values: { [PathIndex]: any }): ()
	local pathTable = getPathTable(path)
	local pointer, index, newKeyIndex = getPathTablePointerCreate(self.Data, pathTable)
	pathTable[#pathTable + 1] = index
	for key, value in pairs(values) do
		Common._onSetValue(self, pathTable, newKeyIndex, pointer[index], key, value)
	end
	fireReplicaSignal(self, "_OnRawChange", pathTable, "SetValues", pathTable, values)
end

function Common.onArrayInsert(self: any, path: Path, index: number?, value: any): number
	local pathTable = getPathTable(path)
	local pointer, pointer_index = getPathTablePointerCreate(self.Data, pathTable)
	local _index = index or #pointer[pointer_index] + 1
	table.insert(pointer[pointer_index], _index, value)
	fireReplicaSignal(self, "_OnArrayInsert", pathTable, _index, value)
	fireReplicaSignal(self, "_OnRawChange", pathTable, "ArrayInsert", pathTable, index, value)
	return _index
end

function Common.onArraySet(self: any, path: Path, index: number, value: any): ()
	local pathTable = getPathTable(path)
	local pointer, _index = getPathTablePointerCreate(self.Data, pathTable)
	pointer[_index][index] = value
	fireReplicaSignal(self, "_OnArraySet", pathTable, index, value)
	fireReplicaSignal(self, "_OnRawChange", pathTable, "ArraySet", pathTable, index, value)
end

function Common.onArrayRemove(self: any, path: Path, index: number): ()
	local pathTable = getPathTable(path)
	local pointer, _index = getPathTablePointerCreate(self.Data, pathTable)
	local old = pointer[_index][index]
	table.remove(pointer[_index], index)
	fireReplicaSignal(self, "_OnArrayRemove", pathTable, index, old)
	fireReplicaSignal(self, "_OnRawChange", pathTable, "ArrayRemove", pathTable, index, old)
end

function Common.onSetParent(self: any, parent): ()
	fireReplicaSignal(parent, "_OnChildAdded", nil, self)
end

function Common.identify(self: any): string
	local tagString = ""
	for key, val in pairs(self.Tags) do
		tagString ..= `{key}={val};`
	end
	return `Id:{self.Id};Token:{self:GetToken()};Tags:\{{tagString}\}`
end

return Common