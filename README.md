# Replica
Check out the [Documentation](https://joshuaclarkelua.github.io/Replica/)

## IMPORTANT
In these examples, Replica is the Package required like below:
```lua
local Replica = require(Packages.Replica)
```



## Server Usage
### Creating a Token
Tokens are used to identify different types of **Replicas**. You cannot register a Token
more than once, but you *can* and *should* use it multiple times for the same type of replica.
```lua
local inventoryToken = Replica.Service:RegisterToken("PlayerInventory")
```
### Creating a Replica
This replica's Filter is set to **Include** and so players in the **FilterList**
will receive this replica on their client.
```lua
local player -- A player in the game
local replica: Replica.Server = Replica.Service:NewReplica({
	Token = inventoryToken,
	Tags = { -- Tags are only replicated once upon the creation of the replica
		ownerId = player.UserId,
	},
	Data = { -- Data is replicated when changed
		money = 0,
		items = {
			[1] = "axe",
		},
	},
	Filter = "Include", -- "Include" or "Exclude" or "All"
	FilterList = {
		[player] = true,
	},
})
```
### Changing Values
```lua
replica:SetValue("money", 50)
replica:SetValue({"items", 1}, "pickaxe") -- Cannot use string ("items.1") syntax here because 1 is a number, not a string
```
### Destroying a Replica
This will cleanup the Replica and destroy it on the client as well.
```lua
replica:Destroy()
```

## Client Usage
### Setting up Listeners
Before calling **Replica.Controller:RequestData()**, you must first setup your listeners
to listen for incoming replicas.
```lua
local Players = game:GetService("Players")
-- Listen for new "PlayerInventory" Replicas
Replica.Controller:OnNewReplicaWithToken("PlayerInventory", function(replica: Replica.Client)
	local owner = Players:GetPlayerByUserId(replica.Tags.ownerId)
	if not owner then return end

	-- When receiving the replica, we want to listen for changes in "money" or other values
	replica:OnChange("money", function(new: number, old: number)
		print(owner.Name .. "'s money went from $" .. old .. " to $" .. new)
	end)

	-- OR

	replica:OnChange({"money"}, function(new: number, old: number)
		print(owner.Name .. "'s money went from $" .. old .. " to $" .. new)
	end)

	-- Example use for array {} path syntax
	replica:OnChange({"items", 1}, function(new: string, old: string)
		print(owner.Name .. " changed item slot 1 from " .. old .. " to " .. new)
	end)

	print(owner.Name .. " has $" .. replica.Data.money .. " and " .. #replica.Data.items .. " items")
end)
```
### Receiving Replicas
After setting up your listeners, you can then call
```lua
Replica.Controller:RequestData()
```

## ReplicaService
This library is extremely similar to [ReplicaService](https://madstudioroblox.github.io/ReplicaService/) by MadStudio.