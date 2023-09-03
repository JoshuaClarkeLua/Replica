local SelfCleanTable = {}
SelfCleanTable.__ClassName = "SelfCleanTable"
SelfCleanTable.__mode = "v"
local PARENT = newproxy(false)
local NONE = {}

function SelfCleanTable.new(): SelfCleanTable
	return setmetatable({}, SelfCleanTable)
end
export type SelfCleanTable = typeof(SelfCleanTable.new(...))

function SelfCleanTable.NONE(table: any): any
	return setmetatable(table, NONE)
end

function SelfCleanTable.__newindex(table: any, index: any, value: any): ()
	if getmetatable(value) == nil then
		setmetatable(value, SelfCleanTable)
	end
	local oldParent = rawget(value, PARENT)
	if oldParent then
		rawset(value, oldParent, nil)
	end
	rawset(table, index, value)
	rawset(value, PARENT, table)
	rawset(value, table, true)
end
return SelfCleanTable
