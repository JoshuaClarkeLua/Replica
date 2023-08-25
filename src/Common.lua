local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

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


function Common.getPathTable(path: Path): PathTable
	if type(path) == "table" then
		return table.clone(path)
	end
	return string.split(path, ".")
end

function Common.getPathTablePointer(data: { [any]: any }, pathTable: PathTable, create: boolean?): ({ [PathIndex]: any }?, PathIndex?)
	local pointer = data
	local index = table.remove(pathTable, #pathTable)

	if #pathTable ~= 0 then
		for _, key in ipairs(pathTable) do
			if type(pointer) ~= "table" then
				error(`Invalid path: Cannot index non-table value "{pointer}"`)local ReplicatedStorage = game:GetService("ReplicatedStorage")
				local Signal = require(ReplicatedStorage.Packages.Signal)
				
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
				
				
				function Common.getPathTable(path: Path): PathTable
					if type(path) == "table" then
						return table.clone(path)
					end
					return string.split(path, ".")
				end
				
				function Common.getPathTablePointer(data: { [any]: any }, pathTable: PathTable, create: boolean?): ({ [PathIndex]: any }?, PathIndex?)
					local pointer = data
					local index = table.remove(pathTable, #pathTable)
				
					if #pathTable ~= 0 then
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
							pointer = newPointer
						end
					end
				
					return pointer, index
				end
				
				function Common.getPathTablePointerCreate(data: { [any]: any }, pathTable: PathTable): ({ [PathIndex]: any }, PathIndex)
					local pointer, index = Common.getPathTablePointer(data, pathTable, true)
					return pointer :: {[any]: any}, index :: PathIndex
				end
				
				--[=[
					@within Replcia
					@function getPathPointer
				
					Returns the pointer (table) in which the value is stored in
					and the final index
				
					@param data: table - The table to get the value from
					@param path: string - The path to get the value with
				
					@return pointer: table - The table containing the value
					@return index: string - The final index
				]=]
				function Common.getPathPointer(data: { [any]: any }, path: Path): ({ [PathIndex]: any }, PathIndex)
					return Common.getPathTablePointerCreate(data, Common.getPathTable(path))
				end
				
				function Common.assertActive(self: any): ()
					if not self:IsActive() then
						error(`Replica has already been destroyed`)
					end
				end
				
				function Common.cleanSignalTable(signals: { [PathIndex]: any }, pathTable: PathTable, signalTable: {[PathIndex]: any}): ()
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
						local pathTable = Common.getPathTable(path)
						table.insert(pathTable, signalName)
						signalTable = Common.getPathTablePointerCreate(listeners, pathTable)
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
										Common.cleanSignalTable(listeners, Common.getPathTable(path), signalTable)
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
				
				function Common.fireReplicaSignal(self: any, signalName: string, pathTable: PathTable?, index: PathIndex?, ...: any): ()
					if self._listeners ~= nil then
						local pointer
						if pathTable == nil or (#pathTable == 0 and index == nil) then
							pointer = self._listeners[TOP_LEVEL_LISTENERS]
						else
							table.insert(pathTable, index)
							table.insert(pathTable, signalName)
							pointer = Common.getPathTablePointer(self._listeners, pathTable, false)
						end
						if pointer then
							local signal = pointer[signalName]
							if signal ~= nil then
								signal:Fire(...)
							end
						end
					end
				end
				
				function Common._onSetValue(self: any, pathTable: PathTable, pointer:{[PathIndex]: any}, index: PathIndex, value: any): ()
					local old = pointer[index]
					pointer[index] = value
					if old == nil then
						Common.fireReplicaSignal(self, "_OnNewKey", pathTable, nil, index, value)
					end
				
					Common.fireReplicaSignal(self, "_OnChange", pathTable, index, value, old)
				end
				
				function Common.onSetValue(self: any, path: Path, value: any): ()
					local pathTable = Common.getPathTable(path)
					local pointer, index = Common.getPathTablePointerCreate(self.Data, pathTable)
					Common._onSetValue(self, pathTable, pointer, index, value)
					Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, index, "SetValue", pathTable, value)
				end
				
				function Common.onSetValues(self: any, path: Path, values: { [string]: any }): ()
					local pathTable = Common.getPathTable(path)
					local pointer, index = Common.getPathTablePointerCreate(self.Data, pathTable)
					pathTable[#pathTable + 1] = index
					for key, value in pairs(values) do
						Common._onSetValue(self, pathTable, pointer[index], key, value)
					end
					Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, index, "SetValues", pathTable, values)
				end
				
				function Common.onArrayInsert(self: any, path: Path, index: number?, value: any): number
					local pathTable = Common.getPathTable(path)
					local pointer, pointer_index = Common.getPathTablePointerCreate(self.Data, pathTable)
					local _index = index or #pointer[pointer_index] + 1
					table.insert(pointer[pointer_index], _index, value)
					Common.fireReplicaSignal(self, "_OnArrayInsert", pathTable, pointer_index, _index, value)
					Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, pointer_index, "ArrayInsert", pathTable, index, value)
					return _index
				end
				
				function Common.onArraySet(self: any, path: Path, index: number, value: any): ()
					local pathTable = Common.getPathTable(path)
					local pointer, _index = Common.getPathTablePointerCreate(self.Data, pathTable)
					pointer[_index][index] = value
					Common.fireReplicaSignal(self, "_OnArraySet", pathTable, _index, index, value)
					Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, _index, "ArraySet", pathTable, index, value)
				end
				
				function Common.onArrayRemove(self: any, path: Path, index: number): ()
					local pathTable = Common.getPathTable(path)
					local pointer, _index = Common.getPathTablePointerCreate(self.Data, pathTable)
					local old = pointer[_index][index]
					table.remove(pointer[_index], index)
					Common.fireReplicaSignal(self, "_OnArrayRemove", pathTable, _index, index, old)
					Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, _index, "ArrayRemove", pathTable, index, old)
				end
				
				function Common.onSetParent(self: any, parent): ()
					Common.fireReplicaSignal(parent, "_OnChildAdded", nil, nil, self)
				end
				
				function Common.identify(self: any): string
					local tagString = ""
					for key, val in pairs(self.Tags) do
						tagString ..= `{key}={val};`
					end
					return `Id:{self.Id};Token:{self:GetToken()};Tags:\{{tagString}\}`
				end
				
				return Common
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
			pointer = newPointer
		end
	end

	return pointer, index
end

function Common.getPathTablePointerCreate(data: { [any]: any }, pathTable: PathTable): ({ [PathIndex]: any }, PathIndex)
	local pointer, index = Common.getPathTablePointer(data, pathTable, true)
	return pointer :: {[any]: any}, index :: PathIndex
end

--[=[
	@within Replcia
	@function getPathPointer

	Returns the pointer (table) in which the value is stored in
	and the final index

	@param data: table - The table to get the value from
	@param path: string - The path to get the value with

	@return pointer: table - The table containing the value
	@return index: string - The final index
]=]
function Common.getPathPointer(data: { [any]: any }, path: Path): ({ [PathIndex]: any }, PathIndex)
	return Common.getPathTablePointerCreate(data, Common.getPathTable(path))
end

function Common.assertActive(self: any): ()
	if not self:IsActive() then
		error(`Replica has already been destroyed`)
	end
end

function Common.cleanSignalTable(signals: { [PathIndex]: any }, pathTable: PathTable, signalTable: {[PathIndex]: any}): ()
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
		local pathTable = Common.getPathTable(path)
		table.insert(pathTable, signalName)
		signalTable = Common.getPathTablePointerCreate(listeners, pathTable)
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
						Common.cleanSignalTable(listeners, Common.getPathTable(path), signalTable)
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

function Common.fireReplicaSignal(self: any, signalName: string, pathTable: PathTable?, index: PathIndex?, ...: any): ()
	if self._listeners ~= nil then
		local pointer
		if pathTable == nil or (#pathTable == 0 and index == nil) then
			pointer = self._listeners[TOP_LEVEL_LISTENERS]
		else
			table.insert(pathTable, index)
			table.insert(pathTable, signalName)
			pointer = Common.getPathTablePointer(self._listeners, pathTable, false)
		end
		if pointer then
			local signal = pointer[signalName]
			if signal ~= nil then
				signal:Fire(...)
			end
		end
	end
end

function Common._onSetValue(self: any, pathTable: PathTable, pointer:{[PathIndex]: any}, index: PathIndex, value: any): ()
	local old = pointer[index]
	pointer[index] = value
	if old == nil then
		Common.fireReplicaSignal(self, "_OnNewKey", pathTable, nil, index, value)
	end

	Common.fireReplicaSignal(self, "_OnChange", pathTable, index, value, old)
end

function Common.onSetValue(self: any, path: Path, value: any): ()
	local pathTable = Common.getPathTable(path)
	local pointer, index = Common.getPathTablePointerCreate(self.Data, pathTable)
	Common._onSetValue(self, pathTable, pointer, index, value)
	Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, index, "SetValue", pathTable, value)
end

function Common.onSetValues(self: any, path: Path, values: { [string]: any }): ()
	local pathTable = Common.getPathTable(path)
	local pointer, index = Common.getPathTablePointerCreate(self.Data, pathTable)
	pathTable[#pathTable + 1] = index
	for key, value in pairs(values) do
		Common._onSetValue(self, pathTable, pointer[index], key, value)
	end
	Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, index, "SetValues", pathTable, values)
end

function Common.onArrayInsert(self: any, path: Path, index: number?, value: any): number
	local pathTable = Common.getPathTable(path)
	local pointer, pointer_index = Common.getPathTablePointerCreate(self.Data, pathTable)
	local _index = index or #pointer[pointer_index] + 1
	table.insert(pointer[pointer_index], _index, value)
	Common.fireReplicaSignal(self, "_OnArrayInsert", pathTable, pointer_index, _index, value)
	Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, pointer_index, "ArrayInsert", pathTable, index, value)
	return _index
end

function Common.onArraySet(self: any, path: Path, index: number, value: any): ()
	local pathTable = Common.getPathTable(path)
	local pointer, _index = Common.getPathTablePointerCreate(self.Data, pathTable)
	pointer[_index][index] = value
	Common.fireReplicaSignal(self, "_OnArraySet", pathTable, _index, index, value)
	Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, _index, "ArraySet", pathTable, index, value)
end

function Common.onArrayRemove(self: any, path: Path, index: number): ()
	local pathTable = Common.getPathTable(path)
	local pointer, _index = Common.getPathTablePointerCreate(self.Data, pathTable)
	local old = pointer[_index][index]
	table.remove(pointer[_index], index)
	Common.fireReplicaSignal(self, "_OnArrayRemove", pathTable, _index, index, old)
	Common.fireReplicaSignal(self, "_ListenToRaw", pathTable, _index, "ArrayRemove", pathTable, index, old)
end

function Common.onSetParent(self: any, parent): ()
	Common.fireReplicaSignal(parent, "_OnChildAdded", nil, nil, self)
end

function Common.identify(self: any): string
	local tagString = ""
	for key, val in pairs(self.Tags) do
		tagString ..= `{key}={val};`
	end
	return `Id:{self.Id};Token:{self:GetToken()};Tags:\{{tagString}\}`
end

return Common